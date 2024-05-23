#!/bin/bash

# List all job definitions and deregister them
echo "Fetching all job definition ARNs for: $BATCH_JOB_NAME"
JOB_DEFINITION_ARNS=$(aws batch describe-job-definitions \
    --job-definition-name $BATCH_JOB_NAME \
    --region $REGION \
    --profile $PROFILE \
    --query 'jobDefinitions[*].jobDefinitionArn' \
    --output text)

if [ -z "$JOB_DEFINITION_ARNS" ]; then
    echo "No job definitions found for: $BATCH_JOB_NAME"
    exit 0
fi

echo "Job Definitions ARNs: $JOB_DEFINITION_ARNS"

# Deregister each job definition
for JOB_DEFINITION_ARN in $JOB_DEFINITION_ARNS; do
    echo "Deregistering job definition: $JOB_DEFINITION_ARN"
    aws batch deregister-job-definition \
        --job-definition $JOB_DEFINITION_ARN \
        --region $REGION \
        --profile $PROFILE
done

echo "All job definitions for $BATCH_JOB_NAME have been deregistered."
