import os
import json
import boto3
import re
import requests
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
sqs = boto3.client('sqs')
bucket_name = os.environ['BUCKET_NAME']
queue_url = os.environ['QUEUE_URL']

def lambda_handler(event, context):
    try:
        for record in event['Records']:
            message_body = record['body']
            logger.info(f"Processing message: {message_body}")

            if re.match(r'^https?://.*\.pdf$', message_body):
                pdf_url = message_body
                response = requests.get(pdf_url)
                if response.status_code == 200:
                    # Save the PDF to S3
                    pdf_key = f"pdfs/{pdf_url.split('/')[-1]}"
                    s3.put_object(Bucket=bucket_name, Key=pdf_key, Body=response.content)
                    logger.info(f"PDF saved to S3: s3://{bucket_name}/{pdf_key}")

                    # Remove the message from the queue
                    receipt_handle = record['receiptHandle']
                    sqs.delete_message(
                        QueueUrl=queue_url,
                        ReceiptHandle=receipt_handle
                    )
                    logger.info(f"Message removed from the queue: {message_body}")
                else:
                    logger.error(f"Failed to download PDF: {pdf_url}, Status Code: {response.status_code}")
            else:
                logger.warning(f"Message is not a PDF URL: {message_body}")

    except Exception as e:
        logger.error(f"Error processing message: {e}", exc_info=True)

    return {
        'statusCode': 200,
        'body': json.dumps('Processing Complete')
    }
