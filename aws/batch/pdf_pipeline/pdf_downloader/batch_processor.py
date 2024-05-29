import os
import json
import boto3
import logging
import re
from pdf_downloader import clean_url, download_pdf
from urllib.parse import urlparse, unquote
from datetime import datetime
from pdf2pngs import convert_pdf2pngs

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
sqs = boto3.client('sqs')
dynamodb = boto3.client('dynamodb')
bucket_name = os.environ['BUCKET_NAME']
queue_url = os.environ['QUEUE_URL']
dynamodb_table = os.environ['DYNAMODB_TABLE']

def process_messages():
    list_of_s3s = []
    try:
        while True:
            response = sqs.receive_message(
                QueueUrl=queue_url,
                MaxNumberOfMessages=10,
                WaitTimeSeconds=20
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

                            list_of_s3s.append({'s3': {'bucket': {'name': bucket_name}, 'object': {'key': object_name}}})

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
                        logger.error(f"Error processing PDF URL {cleaned_url}: {e}")
                else:
                    logger.warning(f"Message is not a PDF URL: {message_body}")
    except Exception as e:
        logger.error(f"Error processing message: {e}", exc_info=True)

    return list_of_s3s

def convert_pdf2pngs(list_of_s3s):
    logger.info(f"convert_pdf2pngs: {list_of_s3s}")

    for record in list_of_s3s:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        if not key.lower().endswith('.pdf'):
            logger.info(f"Skipping non-PDF file: {key}")
            continue

        try:
            # Get object size
            response = s3.head_object(Bucket=bucket, Key=key)
            object_size = response['ContentLength']

            # Check if the object is too large (e.g., > 1 GB)
            if object_size > 1024 * 1024 * 1024:
                logger.error(f"File {key} is too large to process: {object_size} bytes")
                continue  
              
            process_pdf(bucket, key)
        except s3.exceptions.NoSuchKey:
            logger.error(f"File {key} does not exist in bucket {bucket}")
        except Exception as e:
            logger.error(f"Error getting object {key} from bucket {bucket}: {e}")

def process_pdf(bucket, key):
    try:
        # Get the PDF file from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        pdf_content = response['Body'].read()
        response['Body'].close()  # Ensure the body is closed
        
        # Convert PDF to images
        png_images = convert_pdf2pngs(pdf_content)
        metadata_entries = []
        
        for i, image_buffer in enumerate(png_images, start=1):
            try:
                # Save each page as a PNG to S3
                png_key = f"{key.rstrip('.pdf')}/page-{i}.png"
                s3.upload_fileobj(image_buffer, bucket, png_key)
                image_buffer.close()  # Close the buffer after uploading
                metadata_entries.append(f"s3://{bucket}/{png_key}")
            except Exception as e:
                logger.error(f"Error uploading page {i} for PDF {key}: {e}")

        # Update metadata
        current_time = datetime.utcnow().isoformat()
        metadata = {
            "pages": metadata_entries,
            "pages_extracted_timestamp": current_time,
            "status": "PagesExtracted"
        }
        
        # Save metadata to DynamoDB
        save_metadata_to_dynamodb(key, metadata)
    except Exception as e:
        logger.error(f"Error processing PDF {key}: {e}")

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
        logger.error(f"Error updating metadata for PDF {key}: {e}")

if __name__ == "__main__":
    list_of_s3s = process_messages()
    if list_of_s3s:
        convert_pdf2pngs(list_of_s3s)
