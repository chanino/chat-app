ROLE_NAME="APIGatewayInvokeLambdaRole"
LAMBDA_FUNCTION_NAME="SendMessageToSQS"

# Create the role
aws iam create-role \
    --role-name $ROLE_NAME \
    --assume-role-policy-document '{
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
    }' \
    --profile $PROFILE

# Attach the policy to allow invoking the Lambda function
aws iam attach-role-policy \
    --role-name $ROLE_NAME \
    --policy-arn arn:aws:iam::aws:policy/AWSLambdaRole \
    --profile $PROFILE

# Create an inline policy to allow specific Lambda function invocation
aws iam put-role-policy \
    --role-name $ROLE_NAME \
    --policy-name InvokeLambdaPolicy \
    --policy-document '{
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Action": "lambda:InvokeFunction",
          "Resource": "arn:aws:lambda:'$REGION':'$(aws sts get-caller-identity --query Account --output text --profile $PROFILE)':function:'$LAMBDA_FUNCTION_NAME'"
        }
      ]
    }' \
    --profile $PROFILE
