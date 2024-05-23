#!/bin/bash

# Details of the new job definition
IMAGE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:${JOB_NAME}"
COMMAND='["python3", "./batch_processor.py"]'
ENVIRONMENT=$(cat <<EOF
[
    {"name": "DYNAMODB_TABLE", "value": "${DYNAMODB_TABLE}"}, 
    {"name": "QUEUE_URL", "value": "${QUEUE_URL}"}, 
    {"name": "BUCKET_NAME", "value": "${BUCKET_NAME}"}
]
EOF
)
JOB_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/BatchTaskExecutionRole"
EXECUTION_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/BatchTaskExecutionRole"

# Container properties as a multi-line JSON string
CONTAINER_PROPERTIES=$(cat <<EOF
{
    "image": "$IMAGE",
    "command": $COMMAND,
    "environment": $ENVIRONMENT,
    "jobRoleArn": "$JOB_ROLE_ARN",
    "executionRoleArn": "$EXECUTION_ROLE_ARN",
    "resourceRequirements": [
        {
            "value": "2",
            "type": "VCPU"
        },
        {
            "value": "4096",
            "type": "MEMORY"
        }
    ],
    "fargatePlatformConfiguration": {
        "platformVersion": "LATEST"
    }
}
EOF
)

echo "ENVIRONMENT: $ENVIRONMENT"
echo "CONTAINER_PROPERTIES: $CONTAINER_PROPERTIES"

# Register a new job definition
aws batch register-job-definition \
    --job-definition-name $BATCH_JOB_NAME \
    --type container \
    --container-properties "$CONTAINER_PROPERTIES" \
    --platform-capabilities "FARGATE" \
    --region $REGION \
    --profile $PROFILE

echo "New job definition registered successfully."
