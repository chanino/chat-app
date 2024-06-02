[ssm-user@ip-172-31-8-8 ~]$ cat processor.py
import os
import json
import boto3
import logging
import re
from datetime import datetime
from io import BytesIO
from pdf2image import convert_from_bytes
import requests
from requests.adapters import HTTPAdapter
from requests.packages.urllib3.util.retry import Retry
from urllib.parse import urlparse, urlunparse, unquote
import fitz  # PyMuPDF


# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)
region_name = os.getenv('AWS_REGION', 'us-west-2')

s3 = boto3.client('s3', region_name=region_name)
sqs = boto3.client('sqs', region_name=region_name)
dynamodb = boto3.client('dynamodb', region_name=region_name)
step_functions = boto3.client('stepfunctions', region_name=region_name)

bucket_name = os.getenv('BUCKET_NAME')
queue_url = os.getenv('QUEUE_URL')
dynamodb_table = os.getenv('DYNAMODB_TABLE')
state_machine_arn = os.getenv('STATE_MACHINE_ARN')

# Check for required environment variables
if not all([bucket_name, queue_url, dynamodb_table]):
    logger.error("One or more required environment variables are missing.")
    raise ValueError("Missing required environment variables.")

# Setup requests session with retries
session = requests.Session()
retry = Retry(
    total=5,
    backoff_factor=0.3,
    status_forcelist=(500, 502, 504),
)
adapter = HTTPAdapter(max_retries=retry)
session.mount('http://', adapter)
session.mount('https://', adapter)


def is_valid_pdf(content):
    return content.startswith(b'%PDF')


def clean_url(pdf_url):
    parsed_url = urlparse(pdf_url)
    cleaned_url = urlunparse(parsed_url._replace(query='', fragment=''))
    return cleaned_url


def download_pdf(cleaned_url):
    try:
        if not re.match(r'^https?://.*\.pdf$', cleaned_url, re.IGNORECASE):
            logger.info(f"Not a PDF URL: {cleaned_url}")
            return None

        headers = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537.3'}
        response = session.get(cleaned_url, headers=headers, stream=True)
        response.raise_for_status()

        pdf_data = BytesIO()
        for chunk in response.iter_content(chunk_size=1024):
            pdf_data.write(chunk)
        pdf_data.seek(0)

        if not is_valid_pdf(pdf_data.read(4)):
            logger.error(f"Downloaded content is not a valid PDF: {cleaned_url}")
            return None

        pdf_data.seek(0)
        return pdf_data

    except requests.exceptions.RequestException as e:
        logger.error(f"Failed to download PDF: {cleaned_url}, error: {e}")
        return None
    except ValueError as e:
        logger.error(f"Invalid PDF content from URL: {cleaned_url}, error: {e}")
        return None


def process_messages():
    list_of_s3s = []
    try:
        while True:
            response = sqs.receive_message(
                QueueUrl=queue_url,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=20,
                VisibilityTimeout=60  # Add visibility timeout to handle processing failures
            )

            if 'Messages' not in response:
                logger.info("No messages in queue")
                break

            for record in response['Messages']:
                message_body = record['Body']
                logger.info(f"Processing message: {message_body}")

                cleaned_url = clean_url(message_body)
                if re.match(r'^https?://.*\.pdf$', cleaned_url, re.IGNORECASE):
                    try:
                        pdf_data = download_pdf(cleaned_url)
                        if pdf_data:
                            parsed_url = urlparse(cleaned_url)
                            hostname = parsed_url.netloc.replace('.', '_')
                            base_name = os.path.basename(unquote(parsed_url.path)).replace('.pdf', '')
                            object_name = f"{hostname}/{base_name}/{base_name}.pdf"

                            # Upload PDF to S3
                            s3.upload_fileobj(pdf_data, bucket_name, object_name)
                            logger.info(f"PDF saved to S3: s3://{bucket_name}/{object_name}")

                            list_of_s3s.append(object_name)

                            # Construct S3 URI
                            s3_uri = f"s3://{bucket_name}/{object_name}"

                            # Save metadata to DynamoDB
                            current_time = datetime.utcnow().isoformat()
                            response = s3.head_object(Bucket=bucket_name, Key=object_name)
                            file_size = response['ContentLength']

                            dynamodb.put_item(
                                TableName=dynamodb_table,
                                Item={
                                    'url': {'S': cleaned_url},
                                    's3_uri': {'S': s3_uri},
                                    'status': {'S': 'Downloaded'},
                                    'downloaded_timestamp': {'S': current_time},
                                    'file_size': {'N': str(file_size)}
                                }
                            )
                            logger.info(f"Metadata saved to DynamoDB for URL: {cleaned_url}")

                            # Remove the message from the queue
                            receipt_handle = record['ReceiptHandle']
                            sqs.delete_message(
                                QueueUrl=queue_url,
                                ReceiptHandle=receipt_handle
                            )
                            logger.info(f"Message removed from the queue: {message_body}")
                        else:
                            logger.error(f"Failed to download or validate the PDF: {cleaned_url}")
                    except Exception as e:
                        logger.error(f"Error processing PDF URL {cleaned_url}: {e}", exc_info=True)
                else:
                    logger.warning(f"Message is not a PDF URL: {message_body}")
    except Exception as e:
        logger.error(f"Error processing messages: {e}", exc_info=True)

    return list_of_s3s


def png_process(list_of_s3s):
    logger.info(f"png_process: {list_of_s3s}")

    for key in list_of_s3s:
        if not key.lower().endswith('.pdf'):
            logger.info(f"Skipping non-PDF file: {key}")
            continue
        try:
            png_files = process_pdf(bucket_name, key)
            return png_files
        except s3.exceptions.NoSuchKey:
            logger.error(f"File {key} does not exist in bucket {bucket_name}")
        except Exception as e:
            logger.error(f"Error getting object {key} from bucket {bucket_name}: {e}")


def convert_pdf2pngs(pdf_content, bucket, key):
    logger.info("Enter convert_pdf2pngs")

    # Open the PDF file with PyMuPDF
    pdf_document = fitz.open(stream=pdf_content, filetype="pdf")
    logger.info("PDF document opened")

    metadata_entries = []
    for i in range(len(pdf_document)):
        page = pdf_document.load_page(i)
        pix = page.get_pixmap()
        image_buffer = BytesIO(pix.tobytes(output="png"))
        png_key = f"{key.rstrip('.pdf')}/page-{i + 1}.png"

        try:
            # Save each page as a PNG to S3
            s3.upload_fileobj(image_buffer, bucket, png_key)
            metadata_entries.append(f"s3://{bucket}/{png_key}")
            logger.info(f"Uploaded page {i + 1} to S3")
        except Exception as e:
            logger.error(f"Error uploading page {i + 1} for PDF {key}: {e}")

    key = 'metadata/png_files.json'
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=json.dumps(metadata_entries)
    )
    logger.info(f"PNG files metadata saved to s3://{bucket_name}/{key}")

    return metadata_entries


def process_pdf(bucket, key):
    logger.info(f"process_pdf({bucket}, {key})")
    try:
        # Get the PDF file from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        pdf_content = response['Body'].read()
        response['Body'].close()  # Ensure the body is closed
        logger.info("PDF downloaded from S3")

        # Convert PDF to images
        metadata_entries = convert_pdf2pngs(pdf_content, bucket, key)
        logger.info("PDF conversion to PNG completed")

        # Update metadata
        current_time = datetime.utcnow().isoformat()
        metadata = {
            "pages": metadata_entries,
            "pages_extracted_timestamp": current_time,
            "status": "PagesExtracted"
        }

        # Save metadata to DynamoDB
        save_metadata_to_dynamodb(key, metadata)
        return metadata_entries
    
    except Exception as e:
        logger.error(f"Error processing PDF {key}: {e}", exc_info=True)


def trigger_step_functions(png_files):
    try:
        response = step_functions.start_execution(
            stateMachineArn=state_machine_arn,
            input=json.dumps({'pngFiles': png_files})
        )
        logger.info(f"Step Functions state machine triggered: {response['executionArn']}")
    except Exception as e:
        logger.error(f"Error triggering Step Functions: {e}", exc_info=True)


def save_metadata_to_dynamodb(key, metadata):
    try:
        dynamodb.update_item(
            TableName=dynamodb_table,
            Key={'url': {'S': f"s3://{bucket_name}/{key}"}},
            UpdateExpression="set pages = :pages, pages_extracted_timestamp = :pages_extracted_timestamp, #status = :status",
            ExpressionAttributeNames={
                '#status': 'status'
            },
            ExpressionAttributeValues={
                ':pages': {'L': [{'S': page} for page in metadata['pages']]},
                ':pages_extracted_timestamp': {'S': metadata['pages_extracted_timestamp']},
                ':status': {'S': metadata['status']}
            }
        )
        logger.info(f"Metadata updated in DynamoDB table {dynamodb_table} for PDF {key}")
    except Exception as e:
        logger.error(f"Error updating metadata for PDF {key}: {e}", exc_info=True)


if __name__ == "__main__":
    list_of_s3s = process_messages()
    if list_of_s3s:
        list_of_pngs = png_process(list_of_s3s)
        if list_of_pngs:
            trigger_step_functions(list_of_pngs)
