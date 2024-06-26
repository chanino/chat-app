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


######
######

API_EXISTS=$(aws apigateway get-rest-apis --region "$REGION" --profile "$PROFILE" | \
    python -c "import sys, json; print(next((item for item in json.load(sys.stdin)['items'] if item['name'] == '$API_NAME'), ''))")

if [ -z "$API_EXISTS" ]; then
    echo "API does not exist. Creating API..."
    aws apigateway create-rest-api --name "$API_NAME" \
        --region "$REGION" \
        --profile "$PROFILE"
else
    echo "API already exists. No action needed."
fi

API_ID=$(aws apigateway get-rest-apis --region "$REGION" --profile "$PROFILE" | \
    python -c "import sys, json; print(next((item['id'] for item in json.load(sys.stdin)['items'] if item['name'] == '$API_NAME'), ''))")
echo "API ID: $API_ID"

LAMBDA_ARN=$(aws lambda list-functions --query 'Functions[?FunctionName==`$FUNCTION_NAME`].FunctionArn' \
    --region "$REGION" \
    --profile "$PROFILE" \
    --output text)
echo "Lambda ARN: $LAMBDA_ARN"

aws apigateway create-authorizer --rest-api-id "$API_ID" \
    --name "$API_NAME" \
    --type TOKEN \
    --authorizer-uri "arn:aws:apigateway:${REGION}:lambda:path/2015-03-31/functions/${LAMBDA_ARN}/invocations" \
    --identity-source "method.request.header.Authorization" \
    --region "$REGION" \
    --profile "$PROFILE" 

ROOT_ID=$(aws apigateway get-resources --rest-api-id "$API_ID" \
    --region "$REGION" \
    --profile "$PROFILE" \
    | python -c "import sys, json; print(next((item['id'] for item in json.load(sys.stdin)['items'] if item['path'] == '/'), 'Root resource not found'))")
echo $ROOT_ID

aws apigateway create-resource --rest-api-id "$API_ID" \
    --parent-id "$ROOT_ID" \
    --path-part "message" \
    --region "$REGION" \
    --profile "$PROFILE"

RESOURCE_ID=$(aws apigateway get-resources --rest-api-id "$API_ID" \
     --region "$REGION" \
     --profile "$PROFILE" \
    | python -c "import sys, json; print(next((item['id'] for item in json.load(sys.stdin)['items'] if 'message' in item['path']), ''))")
echo $RESOURCE_ID

AUTHORIZER_ID=$(aws apigateway get-authorizers --rest-api-id "$API_ID" \
    --region "$REGION" \
    --profile "$PROFILE" \
    | python -c "import sys, json; print(next((item['id'] for item in json.load(sys.stdin)['items'] if item['name'] == '$API_NAME'), ''))")
echo $AUTHORIZER_ID

aws apigateway put-method --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method "POST" \
    --authorization-type "CUSTOM" \
    --authorizer-id "$AUTHORIZER_ID" \
    --region "$REGION" \
    --profile "$PROFILE"

aws sqs list-queues --profile $PROFILE --region $REGION \
 | python -c "import sys, json; print([url for url in json.load(sys.stdin)['QueueUrls'] if '$QUEUE_NAME' in url])"


aws iam create-role --role-name  $APIGW_ROLE \
    --assume-role-policy-document file://./apigw-trust-policy.json \
    --profile $PROFILE \
    --region $REGION

aws iam attach-role-policy --role-name $APIGW_ROLE \
    --policy-arn "arn:aws:iam::aws:policy/AmazonSQSFullAccess" \
    --profile $PROFILE \
    --region $REGION

ROLE_ARN=$(aws iam get-role --role-name "$APIGW_ROLE" \
    --profile $PROFILE \
    --region $REGION \
    | python -c "import sys, json; print(json.load(sys.stdin)['Role']['Arn'])")
echo $ROLE_ARN


aws apigateway put-method-response --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method "POST" \
    --status-code 200 \
    --response-models "{\"application/json\": \"Empty\"}" \
    --response-parameters "{\"method.response.header.Access-Control-Allow-Origin\": true}" \
    --region "$REGION" \
    --profile "$PROFILE"

aws apigateway put-integration-response --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method "POST" \
    --status-code 200 \
    --response-templates "{\"application/json\": \"\"}" \
    --response-parameters "{\"method.response.header.Access-Control-Allow-Origin\": \"'*'\"}" \
    --region "$REGION" \
    --profile "$PROFILE"


aws apigateway create-deployment --rest-api-id "$API_ID" \
    --stage-name 'prod' \
    --region "$REGION" \
    --profile "$PROFILE"


aws apigateway get-stage --rest-api-id $API_ID \
    --stage-name 'prod' \
    --region "$REGION" \
    --profile "$PROFILE"


aws iam create-policy --policy-name APIGatewayCloudWatchLogsPolicy \
    --policy-document file://cwlogs-policy.json \
    --region $REGION \
    --profile $PROFILE

aws iam attach-role-policy --role-name ApiGatewaySQSRole \
    --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/APIGatewayCloudWatchLogsPolicy \
    --region $REGION \
    --profile $PROFILE

aws apigateway update-account \
    --patch-operations op=replace,path=/cloudwatchRoleArn,value=arn:aws:iam::${ACCOUNT_ID}:role/ApiGatewaySQSRole \
    --region $REGION \
    --profile $PROFILE


LOG_GROUP_ARN="arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/apigateway/$API_NAME"
echo $LOG_GROUP_ARN

##### FIX THIS
LOG='{ "requestId":"$context.requestId", "extendedRequestId":"$context.extendedRequestId","ip": "$context.identity.sourceIp", "caller":"$context.identity.caller", "user":"$context.identity.user", "requestTime":"$context.requestTime", "httpMethod":"$context.httpMethod", "resourcePath":"$context.resourcePath", "status":"$context.status", "protocol":"$context.protocol", "responseLength":"$context.responseLength" }'

PATCH_OPERATIONS=$(cat <<"EOF"
[
  {
    "op": "replace",
    "path": "/accessLogSettings/destinationArn",
    "value": "arn:aws:logs:$REGION:$ACCOUNT_ID:log-group:/aws/apigateway/ChatBroAPI"
  },
  {
    "op": "replace",
    "path": "/accessLogSettings/format",
    "value": "${LOG}"
  }
]
EOF
)
aws apigateway update-stage \
    --rest-api-id $API_ID \
    --stage-name 'prod' \
    --patch-operations "$PATCH_OPERATIONS" \
    --region $REGION \
    --profile $PROFILE



TOKEN='ey...'
curl -v -X POST https://${API_ID}.execute-api.${REGION}.amazonaws.com/prod/message -H "Authorization: Bearer ${TOKEN}"


aws iam list-attached-role-policies --role-name firebase-authenticator-stack-LambdaExecutionRole-ib0No5elDzNC \
    --profile $PROFILE \
    --region $REGION

aws iam create-policy --policy-name LambdaExecutionPolicy --policy-document file://lambda-policy.json \
    --profile $PROFILE \
    --region $REGION

aws iam attach-role-policy --role-name firebase-authenticator-stack-LambdaExecutionRole-ib0No5elDzNC \
    --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/LambdaExecutionPolicy \
    --profile $PROFILE \
    --region $REGION

aws apigateway create-deployment --rest-api-id $API_ID \
    --stage-name 'prod' \
    --profile $PROFILE \
    --region $REGION

aws lambda add-permission \
    --function-name "arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME" \
    --statement-id "apigateway-test" \
    --action "lambda:InvokeFunction" \
    --principal "apigateway.amazonaws.com" \
    --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:${API_ID}/*/*/*" \
    --region $REGION \
    --profile $PROFILE


aws lambda remove-permission \
    --function-name "arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME" \
    --statement-id "apigateway-test" \
    --profile $PROFILE \
    --region $REGION

aws lambda add-permission \
    --function-name "arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME" \
    --statement-id "ApiGatewaySpecificAccess" \
    --action "lambda:InvokeFunction" \
    --principal "apigateway.amazonaws.com" \
    --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/prod/POST/message" \
    --profile $PROFILE \
    --region $REGION

aws lambda get-policy --function-name arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME \
    --profile $PROFILE \
    --region $REGION

aws apigateway get-rest-api --rest-api-id $API_ID --region $REGION --profile $PROFILE


aws lambda remove-permission \
    --function-name "arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME" \
    --statement-id "apigateway-expanded-access" \
    --profile $PROFILE \
    --region $REGION

aws lambda add-permission \
    --function-name arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME \
    --statement-id apigateway-expanded-access \
    --action lambda:InvokeFunction \
    --principal apigateway.amazonaws.com \
    --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*/*/*" \
    --profile $PROFILE \
    --region $REGION

aws iam create-role \
    --role-name APIGatewayLambdaInvokerRole \
    --assume-role-policy-document file://apigw-trust-policy.json \
    --profile $PROFILE \
    --region $REGION

aws iam put-role-policy \
    --role-name APIGatewayLambdaInvokerRole \
    --policy-name InvokeLambdaPolicy \
    --policy-document file://apigw-role-policy.json\
    --profile $PROFILE \
    --region $REGION


aws apigateway update-integration \
    --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --patch-operations op='replace',path='/credentials',value='arn:aws:iam::$ACCOUNT_ID:role/APIGatewayLambdaInvokerRole' \
    --profile $PROFILE \
    --region $REGION





aws apigateway create-deployment --rest-api-id "$API_ID" \
    --stage-name 'prod' \
    --region "$REGION" \
    --profile "$PROFILE"


aws lambda add-permission \
    --function-name "arn:aws:lambda:$REGION:$ACCOUNT_ID:function:$FUNCTION_NAME" \
    --statement-id "ApiGatewayExtendedAccess" \
    --action "lambda:InvokeFunction" \
    --principal "apigateway.amazonaws.com" \
    --source-arn "arn:aws:execute-api:$REGION:$ACCOUNT_ID:$API_ID/*"



aws lambda get-function --function-name $FUNCTION_NAME \
    --profile $PROFILE \
    --region $REGION

