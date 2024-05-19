import os
import json
import boto3
import logging
import re
from pdf_downloader import clean_url, download_pdf
from urllib.parse import urlparse, unquote
from datetime import datetime

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
sqs = boto3.client('sqs')
dynamodb = boto3.client('dynamodb')
bucket_name = os.environ['BUCKET_NAME']
queue_url = os.environ['QUEUE_URL']
dynamodb_table = os.environ['DYNAMODB_TABLE']

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            message_body = record['body']
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
                        receipt_handle = record['receiptHandle']
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

    return {
        'statusCode': 200,
        'body': json.dumps('Processing Complete')
    }
