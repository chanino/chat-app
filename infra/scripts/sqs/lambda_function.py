import json
import boto3
import os
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

sqs = boto3.client('sqs')

def lambda_handler(event, context):
    logger.info("Event received: %s", json.dumps(event))

    # Extract the message from the event
    try:
        if 'body' not in event:
            raise KeyError('body')
        body = json.loads(event['body'])
        if 'message' not in body:
            raise KeyError('message')
        message = body['message']
        logger.info("Extracted message: %s", message)
    except KeyError as e:
        logger.error("Missing key: %s", str(e))
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid request', 'message': f'Missing key: {str(e)}'})
        }
    except json.JSONDecodeError as e:
        logger.error("JSON decode error: %s", str(e))
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid request', 'message': 'JSON decode error'})
        }
    
    # Get the SQS queue URL from the environment variables
    queue_url = os.environ.get('SQS_QUEUE_URL')
    if not queue_url:
        logger.error("SQS_QUEUE_URL environment variable not set")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Internal server error', 'message': 'SQS queue URL not set'})
        }
    logger.info("Queue URL: %s", queue_url)
    
    # Send the message to SQS
    try:
        response = sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=message
        )
        logger.info("Message sent to SQS: %s", response['MessageId'])
        return {
            'statusCode': 200,
            'body': json.dumps({'messageId': response['MessageId']})
        }
    except Exception as e:
        logger.error("Failed to send message: %s", str(e))
        return {
            'statusCode': 500,
            'body': json.dumps({'error': 'Failed to send message', 'message': str(e)})
        }
