#!/bin/bash

# Describe the job definition and output the full JSON response for debugging
echo "Fetching job definition details for: $BATCH_JOB_NAME"
JOB_DEFINITION_OUTPUT=$(aws batch describe-job-definitions \
    --job-definition-name $BATCH_JOB_NAME \
    --region $REGION \
    --profile $PROFILE \
    --output json)

echo "Job definition details: $JOB_DEFINITION_OUTPUT"

# Extract the job role ARN for the active job definition
JOB_ROLE_ARN=$(echo $JOB_DEFINITION_OUTPUT | jq -r '.jobDefinitions[] | select(.status == "ACTIVE") | .containerProperties.jobRoleArn' | head -n 1)

if [ "$JOB_ROLE_ARN" == "null" ] || [ -z "$JOB_ROLE_ARN" ]; then
    echo "No active job role ARN found for the job definition: $BATCH_JOB_NAME"
    exit 1
fi

# Extract the role name from the job role ARN
ROLE_NAME=$(echo $JOB_ROLE_ARN | awk -F/ '{print $NF}')

if [ -z "$ROLE_NAME" ]; then
    echo "Failed to extract role name from job role ARN: $JOB_ROLE_ARN"
    exit 1
fi

echo "Job Role ARN: $JOB_ROLE_ARN"
echo "Role Name: $ROLE_NAME"

# List attached policies for the role
ATTACHED_POLICIES=$(aws iam list-attached-role-policies \
    --role-name $ROLE_NAME \
    --region $REGION \
    --profile $PROFILE \
    --query 'AttachedPolicies[*].PolicyArn' \
    --output text)

if [ -z "$ATTACHED_POLICIES" ]; then
    echo "No attached policies found for the role: $ROLE_NAME"
    exit 1
fi

echo "Attached Policies: $ATTACHED_POLICIES"

# Loop through each attached policy and get the policy details
for POLICY_ARN in $ATTACHED_POLICIES
do
    echo "Policy ARN: $POLICY_ARN"

    # Get the default version ID of the policy
    VERSION_ID=$(aws iam get-policy \
        --policy-arn $POLICY_ARN \
        --region $REGION \
        --profile $PROFILE \
        --query 'Policy.DefaultVersionId' \
        --output text)

    if [ -z "$VERSION_ID" ]; then
        echo "Failed to get policy version ID for policy: $POLICY_ARN"
        continue
    fi

    echo "Policy Version ID: $VERSION_ID"

    # Get the policy document
    aws iam get-policy-version \
        --policy-arn $POLICY_ARN \
        --version-id $VERSION_ID \
        --region $REGION \
        --profile $PROFILE \
        --query 'PolicyVersion.Document' \
        --output json
done
