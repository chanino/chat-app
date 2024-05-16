#QUEUE_NAME="MyReceiveURLQueue"
QUEUE_NAME="MyReceiveURLQueue"
REGION="us-west-2"
PROFILE="AdministratorAccess-811945593738"

# Check if the SQS queue exists
QUEUE_URL=$(aws sqs get-queue-url --queue-name $QUEUE_NAME \
    --region $REGION \
    --profile $PROFILE 2>/dev/null | jq -r '.QueueUrl')

if [ -z "$QUEUE_URL" ]; then
    echo "Creating SQS Queue..."
    QUEUE_URL=$(
        aws sqs create-queue --queue-name $QUEUE_NAME \
            --region $REGION \
            --profile $PROFILE | jq -r '.QueueUrl')
else
    echo "SQS Queue already exists: $QUEUE_URL"
fi

ROLE_NAME="ApiGatewaySQSRole"
POLICY_NAME="SQSPolicy"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --region $REGION --profile $PROFILE --output text)
POLICY_DOCUMENT=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "sqs:SendMessage",
      "Resource": "arn:aws:sqs:$REGION:$ACCOUNT_ID:$QUEUE_NAME"
    }
  ]
}
EOF
)

# Check if the role exists
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --region $REGION --profile $PROFILE 2>/dev/null | jq -r '.Role.Arn')

if [ -z "$ROLE_ARN" ]; then
    echo "Creating IAM Role..."
    TRUST_POLICY=$(cat <<EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": "apigateway.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }
EOF
    )

    aws iam create-role --role-name $ROLE_NAME --assume-role-policy-document "$TRUST_POLICY" \
        --region $REGION --profile $PROFILE
    aws iam put-role-policy --role-name $ROLE_NAME --policy-name $POLICY_NAME \
        --policy-document "$POLICY_DOCUMENT" --region $REGION --profile $PROFILE

    ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --region $REGION --profile $PROFILE | jq -r '.Role.Arn')
    echo "Created IAM Role: $ROLE_ARN"
else
    echo "IAM Role already exists: $ROLE_ARN"
fi


API_NAME="ChatBroAPI"

# Check if the API exists
API_ID=$(aws apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text --region $REGION --profile $PROFILE)

if [ -z "$API_ID" ]; then
    echo "Creating API Gateway..."
    API_ID=$(aws apigateway create-rest-api --name $API_NAME --region $REGION --profile $PROFILE | jq -r '.id')
    echo "Created API Gateway: $API_ID"
else
    echo "API Gateway already exists: $API_ID"
fi

ROOT_RESOURCE_ID=$(aws apigateway get-resources --rest-api-id $API_ID --region $REGION --profile $PROFILE --query "items[?path=='/'].id" --output text)

MESSAGE_RESOURCE_ID=$(aws apigateway get-resources --rest-api-id $API_ID --region $REGION --profile $PROFILE --query "items[?pathPart=='message'].id" --output text)

if [ -z "$MESSAGE_RESOURCE_ID" ]; then
    echo "Creating /message resource..."
    MESSAGE_RESOURCE_ID=$(aws apigateway create-resource --rest-api-id $API_ID --parent-id $ROOT_RESOURCE_ID --path-part message --region $REGION --profile $PROFILE | jq -r '.id')
    echo "Created /message resource: $MESSAGE_RESOURCE_ID"
else
    echo "/message resource already exists: $MESSAGE_RESOURCE_ID"
fi

METHOD_EXISTS=$(aws apigateway get-method --rest-api-id $API_ID --resource-id $MESSAGE_RESOURCE_ID --http-method POST --region $REGION --profile $PROFILE 2>/dev/null)

if [ -z "$METHOD_EXISTS" ]; then
    echo "Creating POST method for /message..."
    aws apigateway put-method --rest-api-id $API_ID --resource-id $MESSAGE_RESOURCE_ID --http-method POST --authorization-type "NONE" --region $REGION --profile $PROFILE
    aws apigateway put-integration --rest-api-id $API_ID --resource-id $MESSAGE_RESOURCE_ID --http-method POST --type AWS --integration-http-method POST --uri "arn:aws:apigateway:$REGION:sqs:path/$ACCOUNT_ID/$QUEUE_NAME" --credentials $ROLE_ARN --region $REGION --profile $PROFILE

    aws apigateway put-method-response --rest-api-id $API_ID --resource-id $MESSAGE_RESOURCE_ID --http-method POST --status-code 200 --region $REGION --profile $PROFILE
    aws apigateway put-integration-response --rest-api-id $API_ID --resource-id $MESSAGE_RESOURCE_ID --http-method POST --status-code 200 --selection-pattern "" --region $REGION --profile $PROFILE
    echo "POST method and integration for /message created"
else
    echo "POST method for /message already exists"
fi

STAGE_NAME="prod"

STAGE_EXISTS=$(aws apigateway get-stage --rest-api-id $API_ID --stage-name $STAGE_NAME --region $REGION --profile $PROFILE 2>/dev/null)

if [ -z "$STAGE_EXISTS" ]; then
    echo "Creating deployment and stage..."
    DEPLOYMENT_ID=$(aws apigateway create-deployment --rest-api-id $API_ID --stage-name $STAGE_NAME --region $REGION --profile $PROFILE | jq -r '.id')
    echo "Created deployment: $DEPLOYMENT_ID"
else
    echo "Stage $STAGE_NAME already exists"
    DEPLOYMENT_ID=$(aws apigateway create-deployment --rest-api-id $API_ID --stage-name $STAGE_NAME --region $REGION --profile $PROFILE | jq -r '.id')
    echo "Updated deployment: $DEPLOYMENT_ID"
fi


TOKEN='your_valid_jwt_token'

curl -X POST https://${API_ID}.execute-api.${REGION}.amazonaws.com/prod/message \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d '{
        "MessageBody": "This is a test message",
        "Attribute1": "Value1",
        "Attribute2": "Value2"
    }'


API_ID="7zl9faran2"  # Replace with your API ID
RESOURCE_ID="o89p69"  # Resource ID for /message
REGION="us-west-2"
PROFILE="AdministratorAccess-811945593738"
QUEUE_NAME="MyReceiveURLQueue"
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text --profile $PROFILE)
ROLE_NAME="ApiGatewaySQSRole"

# Get the IAM Role ARN
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME --region $REGION --profile $PROFILE | jq -r '.Role.Arn')

aws apigateway put-integration --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --type AWS \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${REGION}:sqs:path/$ACCOUNT_ID/$QUEUE_NAME" \
    --credentials $ROLE_ARN \
    --region $REGION \
    --profile $PROFILE

# Set up the method response
aws apigateway put-method-response --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --status-code 200 \
    --response-models '{"application/json": "Empty"}' \
    --region $REGION \
    --profile $PROFILE

# Set up the integration response
aws apigateway put-integration-response --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --status-code 200 \
    --selection-pattern "" \
    --response-templates '{"application/json": ""}' \
    --region $REGION \
    --profile $PROFILE


STAGE_NAME="prod"

# Check if the stage exists
STAGE_EXISTS=$(aws apigateway get-stage --rest-api-id $API_ID --stage-name $STAGE_NAME --region $REGION --profile $PROFILE 2>/dev/null)

if [ -z "$STAGE_EXISTS" ]; then
    echo "Creating deployment and stage..."
    DEPLOYMENT_ID=$(aws apigateway create-deployment --rest-api-id $API_ID --stage-name $STAGE_NAME --region $REGION --profile $PROFILE | jq -r '.id')
    echo "Created deployment: $DEPLOYMENT_ID"
else
    echo "Stage $STAGE_NAME already exists"
    DEPLOYMENT_ID=$(aws apigateway create-deployment --rest-api-id $API_ID --stage-name $STAGE_NAME --region $REGION --profile $PROFILE | jq -r '.id')
    echo "Updated deployment: $DEPLOYMENT_ID"
fi



aws apigateway put-integration --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --type AWS \
    --integration-http-method POST \
    --uri "arn:aws:apigateway:${REGION}:sqs:path/$ACCOUNT_ID/$QUEUE_NAME" \
    --credentials $ROLE_ARN \
    --region $REGION \
    --profile $PROFILE

aws apigateway put-method-response --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --status-code 200 \
    --response-models '{"application/json": "Empty"}' \
    --region $REGION \
    --profile $PROFILE

aws apigateway put-integration-response --rest-api-id $API_ID \
    --resource-id $RESOURCE_ID \
    --http-method POST \
    --status-code 200 \
    --selection-pattern "" \
    --response-templates '{"application/json": ""}' \
    --region $REGION \
    --profile $PROFILE

{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "sqs:SendMessage",
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage"
      ],
      "Resource": "arn:aws:sqs:us-west-2:811945593738:MyReceiveURLQueue",
      "Condition": {
        "ArnEquals": {
          "aws:SourceArn": "arn:aws:sqs:us-west-2:811945593738:MyReceiveURLQueue"
        }
      }
    }
  ]
}


