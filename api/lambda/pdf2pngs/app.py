import boto3
import os
import json
from datetime import datetime
import logging
from pdf2png import convert_pdf2pngs

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3 = boto3.client('s3')
dynamodb = boto3.client('dynamodb')

BUCKET_NAME = os.getenv('BUCKET_NAME')
DYNAMODB_TABLE = os.getenv('DYNAMODB_TABLE')

def lambda_handler(event, context):
    logger.info(f"Received event: {json.dumps(event, indent=2)}")
    # Parse S3 event
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        if not key.lower().endswith('.pdf'):
            logger.info(f"Skipping non-PDF file: {key}")
            continue
        
        process_pdf(bucket, key)

def process_pdf(bucket, key):
    try:
        # Get the PDF file from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        pdf_content = response['Body'].read()
        
        # Convert PDF to images
        png_images = convert_pdf2pngs(pdf_content)
        metadata_entries = []
        
        for i, image_buffer in enumerate(png_images, start=1):
            # Save each page as a PNG to S3
            png_key = f"{key.rstrip('.pdf')}/page-{i}.png"
            s3.upload_fileobj(image_buffer, bucket, png_key)
            logger.info(f"Uploaded page {i} as PNG to s3://{bucket}/{png_key}")
            metadata_entries.append(f"s3://{bucket}/{png_key}")
        
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
            TableName=DYNAMODB_TABLE,
            Key={'url': {'S': f"s3://{BUCKET_NAME}/{key}"}},
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
        logger.info(f"Metadata updated in DynamoDB table {DYNAMODB_TABLE} for PDF {key}")
    except Exception as e:
        logger.error(f"Error updating metadata for PDF {key}: {e}")
