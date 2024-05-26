#!/bin/bash

# 811945593738.dkr.ecr.us-west-2.amazonaws.com/my-repo:chat-bro-batch-job


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
    --job-name $BATCH_JOB_NAME \
    --job-queue $JOB_QUEUE \
    --job-definition $JOB_DEFINITION_ARN \
    --region $REGION \
    --profile $PROFILE

echo "Job submitted successfully."

