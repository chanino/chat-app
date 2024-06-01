#!/bin/bash

# Load environment variables from .env file
export $(grep -v '^#' .env | xargs)

rm -rf lambda_package function.zip

# Build the lambda zip
docker run --rm --platform=linux/arm64 --entrypoint bash -v $(pwd):/var/task -w /var/task amazon/aws-lambda-python:3.9.2024.05.20.23 -c "
    yum install -y zip &&
    pip install --platform manylinux2014_aarch64 --target=lambda_package/ --implementation cp --python-version 3.9 --only-binary=:all: --upgrade -r requirements.txt &&
    cp lambda_function.py lambda_package/ &&
    cd lambda_package &&
    zip -r ../function.zip .
"

# Validate the zip
docker run --rm --platform=linux/arm64 --entrypoint bash -v $(pwd):/var/task -w /var/task amazon/aws-lambda-python:3.9.2024.05.20.23 -c "
    yum install -y zip unzip &&
    pip install --platform manylinux2014_aarch64 --target=lambda_package/ --implementation cp --python-version 3.9 --only-binary=:all: --upgrade -r requirements.txt &&
    cp lambda_function.py lambda_package/ &&
    cd lambda_package &&
    zip -r ../function.zip . &&
    cd .. &&
    mkdir -p validate_package &&
    unzip function.zip -d validate_package &&
    ls validate_package &&
    python3.9 -c 'import sys; sys.path.append(\"validate_package\"); import pydantic_core; print(\"pydantic_core version:\", pydantic_core.__version__)'
"

# Output the environment variables for the Lambda function
echo "{OPENAI_API_KEY=${OPENAI_API_KEY},S3_BUCKET_NAME=${S3_BUCKET_NAME},REGION=${REGION}}"

# Check if the Lambda function exists
LAMBDA_EXISTS=$(aws lambda get-function --function-name ProcessOCRPage --region $REGION --profile $PROFILE 2>&1)

if [[ $LAMBDA_EXISTS == *"ResourceNotFoundException"* ]]; then
  # Create the Lambda function if it does not exist
  aws lambda create-function --function-name ProcessOCRPage \
    --runtime python3.9 \
    --role arn:aws:iam::${ACCOUNT_ID}:role/lambda-execution-role \
    --handler lambda_function.lambda_handler \
    --architectures arm64 \
    --zip-file fileb://function.zip \
    --environment Variables="{OPENAI_API_KEY=${OPENAI_API_KEY},S3_BUCKET_NAME=${S3_BUCKET_NAME},REGION=${REGION}}" \
    --region $REGION --profile $PROFILE

else
  # Update the Lambda function code and configuration if it exists
  aws lambda update-function-code --function-name ProcessOCRPage --zip-file fileb://function.zip \
    --region $REGION --profile $PROFILE

  aws lambda update-function-configuration --function-name ProcessOCRPage \
    --environment Variables="{OPENAI_API_KEY=${OPENAI_API_KEY},S3_BUCKET_NAME=${S3_BUCKET_NAME},REGION=${REGION}}" \
    --region $REGION --profile $PROFILE
fi

# Define the S3 access policy
cat <<EOT > s3_policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
        }
    ]
}
EOT

# Define the CloudWatch Logs access policy
cat <<EOT > cloudwatch_policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOT

# Check if the S3 access policy exists
S3_POLICY_EXISTS=$(aws iam list-policies --query 'Policies[?PolicyName==`LambdaS3AccessPolicy`].Arn' --output text --profile $PROFILE --region $REGION)

if [ -z "$S3_POLICY_EXISTS" ]; then
  # Create the S3 access policy if it does not exist
  S3_POLICY_ARN=$(aws iam create-policy --policy-name LambdaS3AccessPolicy --policy-document file://s3_policy.json --query 'Policy.Arn' --output text --profile $PROFILE --region $REGION)
else
  S3_POLICY_ARN=$S3_POLICY_EXISTS
fi

# Check if the CloudWatch Logs access policy exists
CLOUDWATCH_POLICY_EXISTS=$(aws iam list-policies --query 'Policies[?PolicyName==`LambdaCloudWatchLogsPolicy`].Arn' --output text --profile $PROFILE --region $REGION)

if [ -z "$CLOUDWATCH_POLICY_EXISTS" ]; then
  # Create the CloudWatch Logs access policy if it does not exist
  CLOUDWATCH_POLICY_ARN=$(aws iam create-policy --policy-name LambdaCloudWatchLogsPolicy --policy-document file://cloudwatch_policy.json --query 'Policy.Arn' --output text --profile $PROFILE --region $REGION)
else
  CLOUDWATCH_POLICY_ARN=$CLOUDWATCH_POLICY_EXISTS
fi

# Attach the S3 access policy to the Lambda execution role
aws iam attach-role-policy --role-name lambda-execution-role --policy-arn $S3_POLICY_ARN --profile $PROFILE --region $REGION

# Attach the CloudWatch Logs access policy to the Lambda execution role
aws iam attach-role-policy --role-name lambda-execution-role --policy-arn $CLOUDWATCH_POLICY_ARN --profile $PROFILE --region $REGION

# Clean up temporary files
rm s3_policy.json cloudwatch_policy.json

# Test
{
  "currentIndex": 0,
  "pngFiles": [
    "s3://chat-bro-userdata/docs_aws_amazon_com/web-application-hosting-best-practices/web-application-hosting-best-practices/page-1.png"
  ]
}
