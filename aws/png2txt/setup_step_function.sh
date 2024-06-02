#!/bin/bash -xe

# Load environment variables from .env file
export $(grep -v '^#' .env | xargs)

# Retrieve Lambda function ARN
LAMBDA_FUNCTION_ARN=$(aws lambda get-function --function-name $LAMBDA_FUNCTION_NAME \
    --region $REGION --profile $PROFILE \
    --query 'Configuration.FunctionArn' --output text)

if [ -z "$LAMBDA_FUNCTION_ARN" ]; then
    echo "Lambda function $LAMBDA_FUNCTION_NAME not found."
    exit 1
fi

# Check if IAM Role exists
ROLE_EXISTS=$(aws iam get-role --role-name $ROLE_NAME \
    --region $REGION --profile $PROFILE \
    --query "Role.RoleName" --output text 2>/dev/null)

if [ "$ROLE_EXISTS" == "$ROLE_NAME" ]; then
    echo "IAM role $ROLE_NAME already exists."
else
    # Create IAM Role for Step Functions
    cat << EOF > trust-policy.json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "states.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    aws iam create-role --role-name $ROLE_NAME \
        --region $REGION --profile $PROFILE \
        --assume-role-policy-document file://trust-policy.json

    # Attach AWS managed policy for Step Functions
    aws iam attach-role-policy --role-name $ROLE_NAME \
      --region $REGION --profile $PROFILE \
      --policy-arn arn:aws:iam::aws:policy/AWSStepFunctionsFullAccess

    # Attach AWS managed policy for Lambda execution
    aws iam attach-role-policy --role-name $ROLE_NAME \
      --region $REGION --profile $PROFILE \
      --policy-arn arn:aws:iam::aws:policy/AWSLambda_FullAccess
    echo "IAM role $ROLE_NAME created and policies attached."
fi

# Get the ARN of the IAM role
ROLE_ARN=$(aws iam get-role --role-name $ROLE_NAME \
  --region $REGION --profile $PROFILE \
  --query "Role.Arn" --output text)



# Define the Step Function state machine definition
cat << EOF > state-machine-definition.json
{
  "Comment": "A step function to process PNG files to TXT using a Lambda function",
  "StartAt": "Initialize",
  "States": {
    "Initialize": {
      "Type": "Pass",
      "Parameters": {
        "currentIndex": 0,
        "pngFiles.$": "$.pngFiles",
        "maxFiles": 3200
      },
      "ResultPath": "$.processingInfo",
      "Next": "EvaluateFileLimit"
    },
    "EvaluateFileLimit": {
      "Type": "Pass",
      "Parameters": {
        "fileCount.$": "States.ArrayLength($.processingInfo.pngFiles)"
      },
      "ResultPath": "$.fileCount",
      "Next": "CheckFileLimitCount"
    },
    "CheckFileLimitCount": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.fileCount",
          "NumericGreaterThanEquals": 3200,
          "Next": "LimitFiles"
        }
      ],
      "Default": "ProcessPage"
    },
    "LimitFiles": {
      "Type": "Pass",
      "Parameters": {
        "currentIndex.$": "$.processingInfo.currentIndex",
        "pngFiles.$": "$.processingInfo.pngFiles[:3200]"
      },
      "ResultPath": "$.processingInfo",
      "Next": "ProcessPage"
    },
    "ProcessPage": {
      "Type": "Task",
      "Resource": "$LAMBDA_FUNCTION_ARN",
      "Parameters": {
        "currentIndex.$": "$.processingInfo.currentIndex",
        "pngFiles.$": "$.processingInfo.pngFiles"
      },
      "ResultPath": "$.lambdaResult",
      "Next": "CheckForMorePages"
    },
    "CheckForMorePages": {
      "Type": "Choice",
      "Choices": [
        {
          "Variable": "$.processingInfo.currentIndex",
          "NumericLessThanPath": "$.fileCount.fileCount",
          "Next": "IncrementIndex"
        }
      ],
      "Default": "Done"
    },
    "IncrementIndex": {
      "Type": "Pass",
      "Parameters": {
        "currentIndex.$": "States.MathAdd($.processingInfo.currentIndex, 1)",
        "pngFiles.$": "$.processingInfo.pngFiles"
      },
      "ResultPath": "$.processingInfo",
      "Next": "ProcessPage"
    },
    "Done": {
      "Type": "Succeed"
    }
  }
}
EOF

# Check if the Step Function state machine exists
STATE_MACHINE_ARN=$(aws stepfunctions list-state-machines \
    --region $REGION --profile $PROFILE \
    --query "stateMachines[?name=='$STATE_MACHINE_NAME'].stateMachineArn" --output text)

if [ -n "$STATE_MACHINE_ARN" ]; then
    echo "Step Function State Machine $STATE_MACHINE_NAME already exists. Updating the definition."
    # Update the Step Function state machine
    aws stepfunctions update-state-machine \
        --state-machine-arn $STATE_MACHINE_ARN \
        --definition file://state-machine-definition.json \
        --role-arn $ROLE_ARN \
        --region $REGION --profile $PROFILE
    echo "Step Function State Machine $STATE_MACHINE_NAME updated."
else
    # Create the Step Function state machine
    aws stepfunctions create-state-machine \
        --name $STATE_MACHINE_NAME \
        --definition file://state-machine-definition.json \
        --role-arn $ROLE_ARN \
        --region $REGION --profile $PROFILE
    echo "Step Function State Machine $STATE_MACHINE_NAME created."
fi

echo "Setup completed successfully."
