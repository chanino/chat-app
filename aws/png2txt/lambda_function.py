import json
import base64
import time
import random
import os
import logging
import boto3
from openai import OpenAI


# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize OpenAI client with the API key from environment variables
client = OpenAI()

region_name = os.getenv('REGION', 'us-west-2')
s3 = boto3.client('s3', region_name=region_name)

def png2txt(base64_image, max_retries=5):
    instruction = ("This image was created from a single page of a PDF document. "
                   "Extract the text from this image into a markdown format that "
                   "mimics the structure of the original PDF page in the image. "
                   "Provide the extracted text, but no other information. "
                   "For example, do not start with a lead-in like 'This image contains'.")
    retries = 0
    while retries < max_retries:
        try:
            response = client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {
                        "role": "user",
                        "content": [
                            {"type": "text", "text": instruction},
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:image/png;base64,{base64_image}",
                                    "detail": "low"
                                },
                            },
                        ],
                    }
                ],
                max_tokens=300,
            )
            return response.choices[0].message.content
        except Exception as e:
            retries += 1
            if retries >= max_retries:
                logger.error(f"Max retries reached. Error: {e}")
                raise e
            wait_time = (2 ** retries) + random.uniform(0, 1)
            logger.warning(f"Retry {retries}/{max_retries} after error: {e}. Waiting for {wait_time:.2f} seconds.")
            time.sleep(wait_time)

def encode_image(bucket, key):
    try:
        response = s3.get_object(Bucket=bucket, Key=key)
        image_content = response['Body'].read()
        return base64.b64encode(image_content).decode('utf-8')
    except Exception as e:
        logger.error(f"Failed to get object {key} from bucket {bucket}. Error: {e}")

def save_text_to_s3(bucket, key, text):
    try:
        s3.put_object(Bucket=bucket, Key=key, Body=text)
        logger.info(f"Saved text to {key} in bucket {bucket}")
    except Exception as e:
        logger.error(f"Failed to save text to {key} in bucket {bucket}. Error: {e}")

def lambda_handler(event, context):
    try:
        # Get the S3 bucket name from environment variables
        bucket_name = os.environ['S3_BUCKET_NAME']
        logger.info(f"Processing PNG files from bucket: {bucket_name}")
        
        # Get current index and PNG files from event
        current_index = event['currentIndex']
        png_files = event['pngFiles']
        
        # Process the current page
        image_key = png_files[current_index].replace(f's3://{bucket_name}/', '')
        logger.info(f"Processing file: {image_key}")
        
        base64_image = encode_image(bucket_name, image_key)
        extracted_text = png2txt(base64_image)
        
        # Save the extracted text back to S3
        text_key = image_key.replace('.png', '.txt')
        save_text_to_s3(bucket_name, text_key, extracted_text)
        
        logger.info(f"Successfully processed file: {image_key}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'extracted_text': extracted_text,
                'current_index': current_index
            })
        }
    except Exception as e:
        logger.error(f"An unexpected error occurred. Event: {event}, Error: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
