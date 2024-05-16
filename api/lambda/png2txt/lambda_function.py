import json
import boto3
import os
import base64
import requests
import logging
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def extract_text_from_image(image_data, api_key):
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {api_key}"
    }

    prompt = (
        "This image was created from a single page of a PDF document. "
        "Extract the text from this image into a markdown format that mimics the structure of the original PDF page in the image. "
        "Provide the extracted text, but no other information. "
        "For example, do not start with a lead-in like 'This image contains'. "
    )

    payload = {
        "model": "gpt-4-turbo",
        "messages": [
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": prompt
                    },
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{image_data}"
                        }
                    }
                ]
            }
        ],
        "max_tokens": 4000
    }

    response = requests.post("https://api.openai.com/v1/chat/completions", headers=headers, json=payload)
    return response.json()

def lambda_handler(event, context):
    s3 = boto3.client('s3')
    api_key = os.getenv('OPENAI_API_KEY')
    if not api_key:
        raise ValueError("OPENAI_API_KEY environment variable is not set.")

    for record in event['Records']:
        bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']

        # Only process PNG files
        if not key.endswith('.png'):
            continue

        logger.info(f"Processing image: s3://{bucket}/{key}")

        # Download the image from S3
        image_object = s3.get_object(Bucket=bucket, Key=key)
        image_data = base64.b64encode(image_object['Body'].read()).decode('utf-8')

        # Extract text from image
        extracted_text_response = extract_text_from_image(image_data, api_key)

        # Log the response for debugging
        logger.info(f"Extracted text response: {extracted_text_response}")

        # Save the extracted text back to S3
        text_key = key.replace('.png', '.txt')
        s3.put_object(Bucket=bucket, Key=text_key, Body=json.dumps(extracted_text_response))
        logger.info(f"Extracted text saved to s3://{bucket}/{text_key}")

    return {
        'statusCode': 200,
        'body': json.dumps('Text extraction complete.')
    }
