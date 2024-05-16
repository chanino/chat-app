#!/bin/bash

# Variables
BUCKET_NAME="chat-bro-userdata"
TABLE_NAME="PdfMetadataTable"
QUEUE_NAME="MyReceiveURLQueue"
LAMBDA_FUNCTION_NAME="dequeue_url"
ROLE_NAME="LambdaS3DynamoDBRole"
POLICY_NAME="LambdaS3DynamoDBPolicy"
ZIP_FILE="dequeuen.zip"
HANDLER="lambda_function.lambda_handler"
RUNTIME="python3.9"
TIMEOUT=300
MEMORY_SIZE=2048
S3_KEY="$ZIP_FILE"
POLICY_FILE="sqs_policy.json"
POLICY_NAME="LambdaSQSPolicy"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region $REGION --profile $PROFILE)

LAMBDA_FUNCTION_FILE="lambda_function.py"
LAYER_NAME="pdf_processing_layer"
LAMBDA_S3_KEY="lambda/$ZIP_FILE"


# Function to check if a Lambda function exists
function lambda_exists() {
    aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME --region $REGION --profile $PROFILE >/dev/null 2>&1
}

# Step 1: Check if S3 bucket exists, create if it does not
if aws s3api head-bucket --bucket $BUCKET_NAME --region $REGION --profile $PROFILE 2>/dev/null; then
    echo "S3 bucket '$BUCKET_NAME' already exists."
else
    aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION --create-bucket-configuration LocationConstraint=$REGION --profile $PROFILE
    echo "S3 bucket '$BUCKET_NAME' created."
fi

# Step 2: Check if DynamoDB table exists, create if it does not
if aws dynamodb describe-table --table-name $TABLE_NAME --region $REGION --profile $PROFILE 2>/dev/null; then
    echo "DynamoDB table '$TABLE_NAME' already exists."
else
    aws dynamodb create-table \
        --table-name $TABLE_NAME \
        --attribute-definitions \
            AttributeName=hostname,AttributeType=S \
            AttributeName=unique_id,AttributeType=S \
        --key-schema \
            AttributeName=hostname,KeyType=HASH \
            AttributeName=unique_id,KeyType=RANGE \
        --provisioned-throughput \
            ReadCapacityUnits=5,WriteCapacityUnits=5 \
        --region $REGION \
        --profile $PROFILE
    echo "DynamoDB table '$TABLE_NAME' created."
fi

# Step 3: Check if IAM role exists, create if it does not
# if aws iam get-role --role-name $ROLE_NAME --region $REGION --profile $PROFILE 2>/dev/null; then
#     echo "IAM role '$ROLE_NAME' already exists."
# else
    # POLICY_DOCUMENT='{
    #     "Version": "2012-10-17",
    #     "Statement": [
    #         {
    #             "Effect": "Allow",
    #             "Action": [
    #                 "logs:CreateLogGroup",
    #                 "logs:CreateLogStream",
    #                 "logs:PutLogEvents"
    #             ],
    #             "Resource": "*"
    #         },
    #         {
    #             "Effect": "Allow",
    #             "Action": [
    #                 "s3:GetObject",
    #                 "s3:PutObject",
    #                 "s3:HeadObject",
    #                 "s3:ListBucket"
    #             ],
    #             "Resource": [
    #                 "arn:aws:s3:::'$BUCKET_NAME'",
    #                 "arn:aws:s3:::'$BUCKET_NAME'/*"
    #             ]
    #         },
    #         {
    #             "Effect": "Allow",
    #             "Action": [
    #                 "dynamodb:PutItem",
    #                 "dynamodb:UpdateItem",
    #                 "dynamodb:GetItem"
    #             ],
    #             "Resource": "arn:aws:dynamodb:'$REGION':your-account-id:table/'$TABLE_NAME'"
    #         },
    #         {
    #             "Effect": "Allow",
    #             "Action": [
    #                 "sqs:ReceiveMessage",
    #                 "sqs:DeleteMessage",
    #                 "sqs:GetQueueAttributes"
    #             ],
    #             "Resource": "arn:aws:sqs:'$REGION':your-account-id:'$QUEUE_NAME'"
    #         }
    #     ]
    # }'

    # # Create IAM role
    # aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust-policy.json --region $REGION --profile $PROFILE
    # aws iam put-role-policy --role-name $ROLE_NAME --policy-name $POLICY_NAME --policy-document "$POLICY_DOCUMENT" --region $REGION --profile $PROFILE
    # echo "IAM role '$ROLE_NAME' created and policy attached."
# fi

# Step 4: Check if SQS queue exists, create if it does not
QUEUE_URL=$(aws sqs get-queue-url --queue-name $QUEUE_NAME --region $REGION --profile $PROFILE --query 'QueueUrl' --output text 2>/dev/null)
if [ -n "$QUEUE_URL" ]; then
    echo "SQS queue '$QUEUE_NAME' already exists."
else
    aws sqs create-queue --queue-name $QUEUE_NAME --region $REGION --profile $PROFILE
    echo "SQS queue '$QUEUE_NAME' created."
    QUEUE_URL=$(aws sqs get-queue-url --queue-name $QUEUE_NAME --region $REGION --profile $PROFILE --query 'QueueUrl' --output text)
fi
QUEUE_ARN=$(aws sqs get-queue-attributes --queue-url $QUEUE_URL --region $REGION --profile $PROFILE --attribute-name QueueArn --query 'Attributes.QueueArn' --output text)


# Step 5: Create or update the Lambda function
# Check if the zip file exists and get its modification time
if [ -f "$ZIP_FILE" ]; then
    ZIP_MOD_TIME=$(stat -f %m "$ZIP_FILE")
else
    ZIP_MOD_TIME=0
fi

# Get the modification time of the Lambda function file
LAMBDA_MOD_TIME=$(stat -f %m "$LAMBDA_FUNCTION_FILE")

echo "LAMBDA_MOD_TIME: $LAMBDA_MOD_TIME"
echo "ZIP_MOD_TIME: $ZIP_MOD_TIME"
echo "ZIP_FILE: $ZIP_FILE"
echo "aws s3 cp $ZIP_FILE s3://$BUCKET_NAME/$LAMBDA_S3_KEY --region $REGION --profile $PROFILE"

# If the Lambda function file is newer than the zip file, rebuild the package
if [ "$LAMBDA_MOD_TIME" -gt "$ZIP_MOD_TIME" ]; then
    echo "Rebuilding and uploading Lambda function package..."

    # Create a deployment package
    rm -rf package
    mkdir package
    cp $LAMBDA_FUNCTION_FILE package/
    cd package
    zip -r ../$ZIP_FILE .
    cd ..

    # List contents of the zip file
    echo "Contents of $ZIP_FILE:"
    unzip -l $ZIP_FILE

    # Upload the deployment package to S3
    aws s3 cp $ZIP_FILE s3://$BUCKET_NAME/$LAMBDA_S3_KEY --region $REGION --profile $PROFILE

    # Update Lambda function code and attach the new layer
    aws lambda update-function-code --function-name $LAMBDA_FUNCTION_NAME --s3-bucket $BUCKET_NAME --s3-key $LAMBDA_S3_KEY --region $REGION --profile $PROFILE
    
    # Get the latest version of the layer
    LAYER_VERSION=$(aws lambda list-layer-versions --layer-name $LAYER_NAME --query 'LayerVersions[0].Version' --output text --region $REGION --profile $PROFILE)
    
    # Update the Lambda function configuration to use the new layer version
    aws lambda update-function-configuration --function-name $LAMBDA_FUNCTION_NAME --layers arn:aws:lambda:$REGION:$(aws sts get-caller-identity --query Account --output text --profile $PROFILE):layer:$LAYER_NAME:$LAYER_VERSION --region $REGION --profile $PROFILE
else
    echo "No changes detected in $LAMBDA_FUNCTION_FILE. Skipping rebuild."
fi









ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --region $REGION --profile $PROFILE --query 'Role.Arn' --output text)

if lambda_exists; then
    aws lambda update-function-code \
        --function-name $LAMBDA_FUNCTION_NAME \
        --s3-bucket $BUCKET_NAME \
        --s3-key $S3_KEY \
        --region $REGION \
        --profile $PROFILE
    echo "Lambda function '$LAMBDA_FUNCTION_NAME' updated."
else
    aws lambda create-function \
        --function-name $LAMBDA_FUNCTION_NAME \
        --runtime $RUNTIME \
        --role $ROLE_ARN \
        --handler $HANDLER \
        --timeout $TIMEOUT \
        --memory-size $MEMORY_SIZE \
        --code S3Bucket=$BUCKET_NAME,S3Key=$S3_KEY \
        --region $REGION \
        --profile $PROFILE
    echo "Lambda function '$LAMBDA_FUNCTION_NAME' created."
fi

# Step 6: Check if the SQS trigger exists and create it if not
MAPPING_UUID=$(aws lambda list-event-source-mappings --function-name $LAMBDA_FUNCTION_NAME --region $REGION --profile $PROFILE --query "EventSourceMappings[?EventSourceArn=='$QUEUE_ARN'].UUID" --output text)

# Create policy JSON file
cat <<EOF > $POLICY_FILE
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes"
            ],
            "Resource": "$QUEUE_ARN"
        }
    ]
}
EOF

# Create or update the IAM policy
aws iam create-policy --policy-name $POLICY_NAME --policy-document file://$POLICY_FILE --region $REGION --profile $PROFILE 2>/dev/null ||
aws iam create-policy-version --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME --policy-document file://$POLICY_FILE --set-as-default --region $REGION --profile $PROFILE

# Attach the policy to the role
aws iam attach-role-policy --role-name $ROLE_NAME --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$POLICY_NAME --region $REGION --profile $PROFILE

# Update SQS queue visibility timeout
aws sqs set-queue-attributes --queue-url $QUEUE_URL --attributes VisibilityTimeout=$TIMEOUT --region $REGION --profile $PROFILE


if [ -z "$MAPPING_UUID" ]; then
    echo "QUEUE_ARN: $QUEUE_ARN"
    aws lambda create-event-source-mapping \
        --function-name $LAMBDA_FUNCTION_NAME \
        --batch-size 10 \
        --event-source-arn $QUEUE_ARN \
        --region $REGION \
        --profile $PROFILE
    echo "SQS trigger added to Lambda function '$LAMBDA_FUNCTION_NAME'."
else
    echo "SQS trigger already exists for Lambda function '$LAMBDA_FUNCTION_NAME'."
fi

echo "Setup complete."
