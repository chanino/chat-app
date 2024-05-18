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

BUCKET_NAME = os.getenv('BUCKET_NAME')

def lambda_handler(event, context):
    logger.info(f"Received event: {event}")

    # Parse S3 event
    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        
        if not key.lower().endswith('.pdf'):
            logger.info(f"Skipping non-PDF file: {key}")
            continue
        
        process_pdf(bucket, key)

def process_pdf(bucket, key):
    logger.info(f"process_pdf({bucket}, {key})")

    try:
        # Get the PDF file from S3
        response = s3.get_object(Bucket=bucket, Key=key)
        pdf_content = response['Body'].read()
        
        # Convert PDF to images
        png_images = convert_pdf2pngs(pdf_content)
        
        for i, image_buffer in enumerate(png_images, start=1):
            # Save each page as a PNG to S3
            png_key = f"{key.rstrip('.pdf')}/page-{i}.png"
            logger.info(f"Save {i} to s3://{bucket}/{png_key}")
            s3.upload_fileobj(image_buffer, bucket, png_key)
            image_buffer.close()  # Close the buffer after uploading
            logger.info(f"Uploaded page {i} as PNG to s3://{bucket}/{png_key}")
        
    except Exception as e:
        logger.error(f"Error processing PDF {key}: {e}")

