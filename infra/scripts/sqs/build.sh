#!/bin/bash

set -e

# Ensure REGION and PROFILE are provided
if [ -z "$REGION" ] || [ -z "$PROFILE" ] || [ -z "$QUEUE_NAME"]; then
  echo "You must set REGION and PROFILE and QUEUE_NAME environment variables."
  exit 1
fi

# Parameters
FUNCTION_NAME="SendMessageToSQS"
ROLE_NAME="LambdaExecutionRole"
ZIP_FILE="function.zip"
LAMBDA_HANDLER="lambda_function.lambda_handler"
RUNTIME="python3.9"

# Step 1: Create a zip file for the Lambda function
echo "Zipping the Lambda function..."
zip -j $ZIP_FILE lambda_function.py

# Step 2: Discover the SQS Queue URL
echo "Discovering the SQS Queue URL..."
QUEUE_URL=$(aws sqs get-queue-url --queue-name $QUEUE_NAME --region $REGION --profile $PROFILE --query 'QueueUrl' --output text)

if [ -z "$QUEUE_URL" ]; then
  echo "Failed to get SQS Queue URL."
  exit 1
fi

echo "Queue URL: $QUEUE_URL"

# Step 3: Create the IAM Role for Lambda execution if not exists
echo "Creating IAM Role..."
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --region $REGION --profile $PROFILE --query 'Role.Arn' --output text 2>/dev/null || true)

if [ -z "$ROLE_ARN" ]; then
  ROLE_ARN=$(aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "lambda.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }' \
    --region $REGION \
    --profile $PROFILE \
    --query 'Role.Arn' --output text)
  
  # Attach policies to the role
  aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole --region $REGION --profile $PROFILE
  aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonSQSFullAccess --region $REGION --profile $PROFILE
else
  # Update the assume role policy document to ensure Lambda can assume the role
  aws iam update-assume-role-policy \
    --role-name $ROLE_NAME \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "lambda.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }' \
    --region $REGION \
    --profile $PROFILE
fi

echo "Role ARN: $ROLE_ARN"

# Step 4: Create or update the Lambda function
echo "Deploying the Lambda function..."
LAMBDA_ARN=$(aws lambda get-function --function-name $FUNCTION_NAME --region $REGION --profile $PROFILE --query 'Configuration.FunctionArn' --output text 2>/dev/null || true)

if [ -z "$LAMBDA_ARN" ]; then
  aws lambda create-function \
    --function-name $FUNCTION_NAME \
    --zip-file fileb://$ZIP_FILE \
    --handler $LAMBDA_HANDLER \
    --runtime $RUNTIME \
    --role $ROLE_ARN \
    --environment Variables={SQS_QUEUE_URL=$QUEUE_URL} \
    --region $REGION \
    --profile $PROFILE
else
  aws lambda update-function-code \
    --function-name $FUNCTION_NAME \
    --zip-file fileb://$ZIP_FILE \
    --region $REGION \
    --profile $PROFILE

  aws lambda update-function-configuration \
    --function-name $FUNCTION_NAME \
    --environment Variables={SQS_QUEUE_URL=$QUEUE_URL} \
    --region $REGION \
    --profile $PROFILE
fi

echo "Lambda function deployed successfully."

# Cleanup
rm $ZIP_FILE

echo "Build and deployment complete."
