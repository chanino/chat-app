#!/bin/bash

# Variables
LAMBDA_FUNCTION_NAME="dequeue_url"
QUEUE_NAME="MyReceiveURLQueue"

# Get the Queue URL
QUEUE_URL=$(
    aws sqs get-queue-url --queue-name $QUEUE_NAME \ 
    --query 'QueueUrl' \ 
    --output text \
    --region $REGION --profile $PROFILE)

# Get the Queue ARN
QUEUE_ARN=$(
    aws sqs get-queue-attributes --queue-url $QUEUE_URL \
    --attribute-name QueueArn \
    --query 'Attributes.QueueArn' \
    --output text\
    --region $REGION --profile $PROFILE)

# Add SQS trigger to Lambda
aws lambda create-event-source-mapping \
    --function-name $LAMBDA_FUNCTION_NAME \
    --batch-size 10 \
    --event-source-arn $QUEUE_ARN \
    --region $REGION --profile $PROFILE

echo "SQS trigger added to Lambda function '$LAMBDA_FUNCTION_NAME'."
