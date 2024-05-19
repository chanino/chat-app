import boto3
import os
import json
from datetime import datetime
import logging
from pdf2png import convert_pdf2pngs

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Specify the AWS region
region_name = os.getenv('AWS_REGION', 'us-west-2')  # Default to 'us-west-2' if not set

s3 = boto3.client('s3', region_name=region_name)
dynamodb = boto3.client('dynamodb', region_name=region_name)

BUCKET_NAME = os.getenv('BUCKET_NAME')
DYNAMODB_TABLE = os.getenv('DYNAMODB_TABLE')

if not BUCKET_NAME or not DYNAMODB_TABLE:
    logger.error("Environment variables BUCKET_NAME and DYNAMODB_TABLE must be set.")
    raise EnvironmentError("Required environment variables are not set.")

def lambda_handler(event, context):
    request_id = context.aws_request_id
    # logger.info(f"Received event: {json.dumps(event)} [Request ID: {request_id}]")

    # Parse S3 event
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        if not key.lower().endswith('.pdf'):
            logger.info(f"Skipping non-PDF file: {key} [Request ID: {request_id}]")
            continue

        try:
            # Get object size
            response = s3.head_object(Bucket=bucket, Key=key)
            object_size = response['ContentLength']

            # Check if the object is too large (e.g., > 1 GB)
            if object_size > 1024 * 1024 * 1024:
                logger.error(f"File {key} is too large to process: {object_size} bytes [Request ID: {request_id}]")
                continue  
              
            process_pdf(bucket, key, request_id)
        except s3.exceptions.NoSuchKey:
            logger.error(f"File {key} does not exist in bucket {bucket} [Request ID: {request_id}]")
        except Exception as e:
            logger.error(f"Error getting object {key} from bucket {bucket}: {e} [Request ID: {request_id}]")

def process_pdf(bucket, key, request_id):
    # logger.info(f"process_pdf({bucket}, {key}) [Request ID: {request_id}]")

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
                # logger.info(f"Saving page {i} to s3://{bucket}/{png_key} [Request ID: {request_id}]")
                s3.upload_fileobj(image_buffer, bucket, png_key)
                image_buffer.close()  # Close the buffer after uploading
                # logger.info(f"Uploaded page {i} as PNG to s3://{bucket}/{png_key} [Request ID: {request_id}]")
                metadata_entries.append(f"s3://{bucket}/{png_key}")
            except Exception as e:
                logger.error(f"Error uploading page {i} for PDF {key}: {e} [Request ID: {request_id}]")

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
        logger.error(f"Error processing PDF {key}: {e} [Request ID: {request_id}]")

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
        # logger.info(f"Metadata updated in DynamoDB table {DYNAMODB_TABLE} for PDF {key}")
    except Exception as e:
        logger.error(f"Error updating metadata for PDF {key}: {e}")
