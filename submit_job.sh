#!/bin/bash

# Get the latest job definition ARN
JOB_DEFINITION_ARN=$(aws batch describe-job-definitions \
    --job-definition-name $BATCH_JOB_NAME \
    --status ACTIVE \
    --region $REGION \
    --profile $PROFILE \
    --query 'jobDefinitions[?status==`ACTIVE`]|[0].jobDefinitionArn' \
    --output text)

echo "Latest Job Definition ARN: $JOB_DEFINITION_ARN"

# Submit the job
aws batch submit-job \
    --job-name $JOB_NAME \
    --job-queue $JOB_QUEUE \
    --job-definition $JOB_DEFINITION_ARN \
    --region $REGION \
    --profile $PROFILE

echo "Job submitted successfully."
