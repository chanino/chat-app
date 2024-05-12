# chat-app

## Overview
This project is envisioned as a comprehensive solution incorporating a web frontend, backend services, mobile and desktop applications, all interacting through APIs. Currently it is under development, with the web frontend under development.

Clone the repo
```bash
git clone https://github.com/chanino/chat-app
cd chat-app
Run the web content in Docker

bash
Copy code
cd web
docker build -t my-nginx-app:latest .

docker run -p 80:80 --rm \
-e FIREBASE_API_KEY=<YOUR_FIREBASE_API_KEY> \
-e FIREBASE_AUTH_DOMAIN=<YOUR_FIREBASE_AUTH_DOMAIN> \
-e FIREBASE_PROJECT_ID=<YOUR_FIREBASE_PROJECT_ID> \
-e FIREBASE_STORAGE_BUCKET=<YOUR_FIREBASE_STORAGE_BUCKET> \
-e FIREBASE_MESSAGING_SENDER_ID=<YOUR_FIREBASE_MESSAGING_SENDER_ID> \
-e FIREBASE_APP_ID=<YOUR_FIREBASE_APP_ID> \
-e FIREBASE_MEASUREMENT_ID=<YOUR_FIREBASE_MEASUREMENT_ID> \
my-nginx-app:latest
Configure AWS to accept request from web page

bash
Copy code

aws configure sso

DEBUG_ON=1
log_message() {
    local message=$1
    if [ $DEBUG_ON ]; then
        echo "$message"
    fi
}

log_message "Set env vars"
PROFILE="<AWS_PROFILE>"
REGION="<AWS_REGION>"
AWS_ACCOUNT="<AWS_ACCOUNT_ID>"

log_message "Setup Trail"
TRAIL_NAME="ChatAppTrail"
TRAIL_STACK="${TRAIL_NAME}-stack"
TRAIL_YAML=file://./infra/cloudformation/create_trail.yaml
TRAIL_BUCKET="<GENERATED_BUCKET_NAME>"
echo $TRAIL_BUCKET

if ! aws cloudformation validate-template --template-body "$TRAIL_YAML" \
    --region "$REGION" \
    --profile "$PROFILE"; then
    echo "Template validation failed."
    exit 1
fi

if ! aws cloudformation create-stack \
    --stack-name "$TRAIL_STACK" \
    --template-body "$TRAIL_YAML" \
    --parameters ParameterKey=TrailName,ParameterValue="$TRAIL_NAME" \
                 ParameterKey=BucketName,ParameterValue="$TRAIL_BUCKET" \
                 ParameterKey=LogRetentionDays,ParameterValue=365 \
                 ParameterKey=EncryptionType,ParameterValue=AES256 \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --region "$REGION" \
    --profile "$PROFILE"; then
    echo "Stack creation failed"
fi

aws cloudtrail get-trail-status --name $TRAIL_NAME \
    --region "$REGION" \
    --profile "$PROFILE"

QUEUE_NAME="MyReceiveURLQueue"
QUEUE_DLQ_NAME="${QUEUE_NAME}_DLQ"
QUEUE_STACK="${QUEUE_NAME}-stack"
QUEUE_YAML=file://./infra/cloudformation/create_sqs.yaml

QUEUE_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" \
    --region "$REGION" \
    --profile "$PROFILE" 2>/dev/null)

if [ -z "$QUEUE_URL" ]; then
    echo "Queue does not exist. Creating queue via CloudFormation..."

    if aws cloudformation create-stack \
        --stack-name "$QUEUE_STACK" \
        --template-body $QUEUE_YAML \
        --parameters \
            ParameterKey=MainQueueName,ParameterValue="$QUEUE_NAME" \
            ParameterKey=DLQName,ParameterValue="$QUEUE_DLQ_NAME" \
        --capabilities CAPABILITY_NAMED_IAM \
        --region "$REGION" \
        --profile "$PROFILE"; then

        echo "Waiting for the CloudFormation stack to be created completely..."
        aws cloudformation wait stack-create-complete \
            --stack-name "$QUEUE_STACK" \
            --region "$REGION" \
            --profile "$PROFILE"

        if [ $? -eq 0 ]; then
            QUEUE_URL=$(aws sqs get-queue-url --queue-name "$QUEUE_NAME" \
                --region "$REGION" \
                --profile "$PROFILE")
            echo "Queue created: $QUEUE_URL"
        else
            echo "Failed to create queue via CloudFormation."
        fi
    else
        echo "CloudFormation stack creation failed."
    fi
else
    echo "Queue already exists: $QUEUE_URL"
fi

DEPLOYMENT_BUCKET="<DEPLOYMENT_BUCKET>"
bucket_exists() {
    aws s3api head-bucket --bucket $1 \
        --region "$REGION" \
        --profile "$PROFILE" 2>&1
}

if bucket_exists $DEPLOYMENT_BUCKET; then
    echo "Bucket $DEPLOYMENT_BUCKET already exists."
else
    aws s3api create-bucket --bucket $DEPLOYMENT_BUCKET \
        --region $REGION \
        --create-bucket-configuration LocationConstraint=$REGION \
        --profile "$PROFILE"

    aws s3api put-public-access-block --bucket $DEPLOYMENT_BUCKET \
        --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true" \
        --region $REGION \
        --profile "$PROFILE"
fi

DEPLOYMENT_DIR="./api/lambda/firebase_auth"
DEPLOYMENT_FILE="deployment.zip"
aws s3 cp ${DEPLOYMENT_DIR}/${DEPLOYMENT_FILE} s3://${DEPLOYMENT_BUCKET}/${DEPLOYMENT_FILE} \
    --region $REGION \
    --profile $PROFILE

STACK_NAME=firebase-authenticator-stack
TEMPLATE_FILE=./infra/cloudformation/create_lambda_firebase_authenticator.yaml
JSON_FILE="<FIREBASE_CREDENTIALS_JSON>"

FIREBASE_PROJECT_ID="<YOUR_FIREBASE_PROJECT_ID>"
FIREBASE_PRIVATE_KEY_ID="<YOUR_FIREBASE_PRIVATE_KEY_ID>"
FIREBASE_PRIVATE_KEY="<YOUR_FIREBASE_PRIVATE_KEY>"
FIREBASE_CLIENT_EMAIL="<YOUR_FIREBASE_CLIENT_EMAIL>"
FIREBASE_CLIENT_ID="<YOUR_FIREBASE_CLIENT_ID>"
FIREBASE_AUTH_URI="<YOUR_FIREBASE_AUTH_URI>"
FIREBASE_TOKEN_URI="<YOUR_FIREBASE_TOKEN_URI>"
FIREBASE_AUTH_PROVIDER_X509_CERT_URL="<YOUR_FIREBASE_AUTH_PROVIDER_X509_CERT_URL>"
FIREBASE_CLIENT_X509_CERT_URL="<YOUR_FIREBASE_CLIENT_X509_CERT_URL>"
FIREBASE_UNIVERSE_DOMAIN="<YOUR_FIREBASE_UNIVERSE_DOMAIN>"
echo "FIREBASE_PROJECT_ID: $FIREBASE_PROJECT_ID"
echo "FIREBASE_PRIVATE_KEY_ID: $FIREBASE_PRIVATE_KEY_ID"
echo "FIREBASE_PRIVATE_KEY: $FIREBASE_PRIVATE_KEY"
echo "FIREBASE_CLIENT_EMAIL: $FIREBASE_CLIENT_EMAIL"
echo "FIREBASE_CLIENT_ID: $FIREBASE_CLIENT_ID"
echo "FIREBASE_AUTH_URI: $FIREBASE_AUTH_URI"
echo "FIREBASE_TOKEN_URI: $FIREBASE_TOKEN_URI"
echo "FIREBASE_AUTH_PROVIDER_X509_CERT_URL: $FIREBASE_AUTH_PROVIDER_X509_CERT_URL"
echo "FIREBASE_CLIENT_X509_CERT_URL: $FIREBASE_CLIENT_X509_CERT_URL"
echo "FIREBASE_UNIVERSE_DOMAIN: $FIREBASE_UNIVERSE_DOMAIN"

aws cloudformation validate-template --template-body "$TEMPLATE_FILE" \
    --region "$REGION" \
    --profile "$PROFILE"

aws cloudformation deploy \
    --template-file "$TEMPLATE_FILE" \
    --stack-name "$STACK_NAME" \
    --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
    --parameter-overrides \
        LambdaCodeS3Bucket="$DEPLOYMENT_BUCKET" \
        LambdaCodeS3Key="$DEPLOYMENT_FILE" \
        FIREBASEPROJECTID="$FIREBASE_PROJECT_ID" \
        FIREBASEPRIVATEKEYID="$FIREBASE_PRIVATE_KEY_ID" \
        FIREBASEPRIVATEKEY="\"$FIREBASE_PRIVATE_KEY\"" \
        FIREBASECLIENTEMAIL="$FIREBASE_CLIENT_EMAIL" \
        FIREBASECLIENTID="$FIREBASE_CLIENT_ID" \
        FIREBASEAUTHURI="$FIREBASE_AUTH_URI" \
        FIREBASETOKENURI="$FIREBASE_TOKEN_URI" \
        FIREBASEAUTHPROVIDERX509CERTURL="$FIREBASE_AUTH_PROVIDER_X509_CERT_URL" \
        FIREBASECLIENTX509CERTURL="$FIREBASE_CLIENT_X509_CERT_URL" \
        FIREBASEUNIVERSEDOMAIN="$FIREBASE_UNIVERSE_DOMAIN" \
    --region "$REGION" \
    --profile "$PROFILE"

aws cloudformation wait stack-create-complete \
    --stack-name "$STACK_NAME" \
    --region "$REGION" \
    --profile "$PROFILE"

