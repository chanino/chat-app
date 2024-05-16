import json
import boto3
import requests
from urllib.parse import urlparse, unquote
import os
from io import BytesIO
from pdf2image import convert_from_bytes
from uuid import uuid4

def download_and_convert_pdf(url, bucket_name):
    s3 = boto3.client('s3')
    dynamodb = boto3.client('dynamodb')
    table_name = os.getenv('DYNAMODB_TABLE_NAME')
    
    parsed_url = urlparse(url)
    hostname = parsed_url.netloc.replace('.', '_')
    base_name = os.path.basename(unquote(parsed_url.path)).replace('.pdf', '')
    unique_id = str(uuid4())
    object_prefix = f"{hostname}/{base_name}_{unique_id}/"
    
    pdf_object_name = f"{object_prefix}{base_name}.pdf"
    metadata_path = f"{object_prefix}metadata.json"

    # Check if the PDF already exists in the bucket
    pdf_exists = False
    try:
        s3.head_object(Bucket=bucket_name, Key=pdf_object_name)
        print(f"PDF already exists in S3: {pdf_object_name}")
        pdf_exists = True
    except s3.exceptions.ClientError:
        pass

    # Check if metadata exists
    metadata_exists = False
    try:
        s3.head_object(Bucket=bucket_name, Key=metadata_path)
        metadata_exists = True
    except s3.exceptions.ClientError:
        pass

    # Download the PDF if it's not in S3
    if not pdf_exists:
        headers = {'User-Agent': 'Mozilla/5.0'}
        response = requests.get(url, headers=headers)
        if response.status_code == 200:
            pdf_data = BytesIO(response.content)
            s3.upload_fileobj(pdf_data, bucket_name, pdf_object_name)
            print(f"Uploaded PDF to s3://{bucket_name}/{pdf_object_name}")
        else:
            print(f"Failed to download PDF: {url}, HTTP status: {response.status_code}")
            return

    # Process PDF to PNG and check each PNG
    if not metadata_exists:
        response = s3.get_object(Bucket=bucket_name, Key=pdf_object_name)
        images = convert_from_bytes(response['Body'].read())
        metadata_entries = []
        for i, image in enumerate(images, start=1):
            png_object_name = f"{object_prefix}page_{i}.png"
            try:
                s3.head_object(Bucket=bucket_name, Key=png_object_name)
                print(f"PNG page {i} already exists: {png_object_name}")
            except s3.exceptions.ClientError:
                image_buffer = BytesIO()
                image.save(image_buffer, format='PNG')
                image_buffer.seek(0)
                s3.upload_fileobj(image_buffer, bucket_name, png_object_name)
                print(f"Uploaded page {i} as PNG to s3://{bucket_name}/{png_object_name}")
            metadata_entries.append(f"s3://{bucket_name}/{png_object_name}")
        
        # Save metadata
        metadata = {
            "pdf_url": url,
            "number_of_pages": len(images),
            "status": "Completed",
            "s3_path": object_prefix,
            "pages": metadata_entries
        }
        save_metadata(metadata, bucket_name, metadata_path)
        store_metadata_in_dynamodb(dynamodb, table_name, hostname, unique_id, metadata)
    else:
        print(f"Metadata already exists: {metadata_path}")

def save_metadata(metadata, bucket_name, metadata_path):
    s3 = boto3.client('s3')
    metadata_json = json.dumps(metadata)
    s3.put_object(Bucket=bucket_name, Key=metadata_path, Body=metadata_json)
    print(f"Metadata saved to s3://{bucket_name}/{metadata_path}")

def store_metadata_in_dynamodb(dynamodb, table_name, hostname, unique_id, metadata):
    dynamodb.put_item(
        TableName=table_name,
        Item={
            'hostname': {'S': hostname},
            'unique_id': {'S': unique_id},
            'metadata': {'S': json.dumps(metadata)}
        }
    )
    print(f"Metadata stored in DynamoDB table {table_name}")

def lambda_handler(event, context):
    bucket_name = os.getenv('BUCKET_NAME')
    if not bucket_name:
        raise ValueError("BUCKET_NAME environment variable is not set.")
    table_name = os.getenv('DYNAMODB_TABLE_NAME')
    if not table_name:
        raise ValueError("DYNAMODB_TABLE_NAME environment variable is not set.")

    # Iterate over SQS messages
    for record in event['Records']:
        body = record['body']
        message = json.loads(body)
        url = message['url']  # Adjust this based on your actual SQS message structure
        
        print(f"Processing URL: {url}")
        download_and_convert_pdf(url, bucket_name)

    return {
        'statusCode': 200,
        'body': json.dumps('Processing complete.')
    }
