#!/bin/bash

# Variables
BUCKET_NAME="chat-bro-userdata"
TEXT_EXTRACTION_LAMBDA_NAME="png2txt"
ROLE_NAME="LambdaS3Role"
POLICY_NAME="LambdaS3Policy"
LAMBDA_FUNCTION_FILE="lambda_function.py"
TEXT_EXTRACTION_ZIP="png2txt.zip"
TEXT_EXTRACTION_HANDLER="lambda_function.lambda_handler"
RUNTIME="python3.9"
TIMEOUT=300
MEMORY_SIZE=2048
S3_KEY="lambda_packages/"

# Function to check if a Lambda function exists
function lambda_exists() {
    aws lambda get-function --function-name $1 --region $REGION --profile $PROFILE >/dev/null 2>&1
}

# Step 1: Check if S3 bucket exists, create if it does not
if aws s3api head-bucket --bucket $BUCKET_NAME --region $REGION --profile $PROFILE 2>/dev/null; then
    echo "S3 bucket '$BUCKET_NAME' already exists."
else
    aws s3api create-bucket --bucket $BUCKET_NAME --region $REGION --create-bucket-configuration LocationConstraint=$REGION --profile $PROFILE
    echo "S3 bucket '$BUCKET_NAME' created."
fi

# Step 3: Check if IAM role exists, create if it does not
if aws iam get-role --role-name $ROLE_NAME --region $REGION --profile $PROFILE 2>/dev/null; then
    echo "IAM role '$ROLE_NAME' already exists."
else
    POLICY_DOCUMENT='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "logs:CreateLogGroup",
                    "logs:CreateLogStream",
                    "logs:PutLogEvents"
                ],
                "Resource": "*"
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:HeadObject",
                    "s3:ListBucket"
                ],
                "Resource": [
                    "arn:aws:s3:::'$BUCKET_NAME'",
                    "arn:aws:s3:::'$BUCKET_NAME'/*"
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "lambda:InvokeFunction"
                ],
                "Resource": "arn:aws:lambda:'$REGION':'$(aws sts get-caller-identity --query Account --output text --region $REGION --profile $PROFILE)':function:'$TEXT_EXTRACTION_LAMBDA_NAME'"
            }
        ]
    }'

    # Create IAM role
    aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document file://trust-policy.json --region $REGION --profile $PROFILE
    aws iam put-role-policy --role-name $ROLE_NAME --policy-name $POLICY_NAME --policy-document "$POLICY_DOCUMENT" --region $REGION --profile $PROFILE
    echo "IAM role '$ROLE_NAME' created and policy attached."
fi


# Step 5: Package and upload the Lambda functions
# Check modification dates
if [ -f "$TEXT_EXTRACTION_ZIP" ]; then
    ZIP_MOD_TIME=$(stat -f %m "$TEXT_EXTRACTION_ZIP")
else
    ZIP_MOD_TIME=0
fi
LAMBDA_MOD_TIME=$(stat -f %m "$LAMBDA_FUNCTION_FILE")

if [ "$LAMBDA_MOD_TIME" -gt "$ZIP_MOD_TIME" ]; then
    echo "Rebuilding and uploading Lambda function package..."

    # Create a deployment package for the text extraction Lambda
    rm -rf package
    mkdir package
    pip install --target ./package -r requirements.txt
    cp $LAMBDA_FUNCTION_FILE package/
    cp .env package/
    cd package
    zip -r ../$TEXT_EXTRACTION_ZIP .
    cd ..

    # Upload the text extraction deployment package to S3
    aws s3 cp $TEXT_EXTRACTION_ZIP s3://$BUCKET_NAME/$S3_KEY$TEXT_EXTRACTION_ZIP --region $REGION --profile $PROFILE
else
    echo "Lambda function package is up to date. No rebuild needed."
fi

# Create or update the text extraction Lambda function
if lambda_exists $TEXT_EXTRACTION_LAMBDA_NAME; then
    aws lambda update-function-code \
        --function-name $TEXT_EXTRACTION_LAMBDA_NAME \
        --s3-bucket $BUCKET_NAME \
        --s3-key $S3_KEY$TEXT_EXTRACTION_ZIP \
        --region $REGION \
        --profile $PROFILE
    echo "Lambda function '$TEXT_EXTRACTION_LAMBDA_NAME' updated."
else
    aws lambda create-function \
        --function-name $TEXT_EXTRACTION_LAMBDA_NAME \
        --runtime $RUNTIME \
        --role $(aws iam get-role --role-name $ROLE_NAME --query 'Role.Arn' --output text --region $REGION --profile $PROFILE) \
        --handler $TEXT_EXTRACTION_HANDLER \
        --timeout $TIMEOUT \
        --memory-size $MEMORY_SIZE \
        --code S3Bucket=$BUCKET_NAME,S3Key=$S3_KEY$TEXT_EXTRACTION_ZIP \
        --region $REGION \
        --profile $PROFILE
    echo "Lambda function '$TEXT_EXTRACTION_LAMBDA_NAME' created."
fi


# Step 6: Add S3 trigger to the text extraction Lambda function
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region $REGION --profile $PROFILE)

# aws lambda add-permission \
#     --function-name $TEXT_EXTRACTION_LAMBDA_NAME \
#     --principal s3.amazonaws.com \
#     --statement-id s3invoke \
#     --action "lambda:InvokeFunction" \
#     --source-arn arn:aws:s3:::$BUCKET_NAME \
#     --source-account $ACCOUNT_ID \
#     --region $REGION \
#     --profile $PROFILE

# Add S3 trigger to the text extraction Lambda function
echo "ACCOUNT_ID=$ACCOUNT_ID"
echo "TEXT_EXTRACTION_LAMBDA_NAME=$TEXT_EXTRACTION_LAMBDA_NAME"

aws s3api put-bucket-notification-configuration --bucket $BUCKET_NAME --notification-configuration "$(cat <<EOF
{
    "LambdaFunctionConfigurations": [
        {
            "LambdaFunctionArn": "arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${TEXT_EXTRACTION_LAMBDA_NAME}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".png"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
)" --region $REGION --profile $PROFILE

echo "Setup complete."
