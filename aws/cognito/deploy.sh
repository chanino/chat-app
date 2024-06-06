#!/bin/bash

REGION='us-west-2'
PROFILE='AdministratorAccess-811945593738'

USER_POOL_NAME='MyUserPool'
USER_POOL_CLIENT_NAME='MyUserPoolClient'
IDENTITY_POOL_NAME='MyIdentityPool'
AUTH_ROLE_NAME='Cognito_MyIdentityPoolAuth_Role'
UNAUTH_ROLE_NAME='Cognito_MyIdentityPoolUnauth_Role'
BUCKET_NAME='chat-bro-userdata'

# Check if User Pool exists
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 10 --region $REGION --profile $PROFILE --query "UserPools[?Name=='$USER_POOL_NAME'].Id | [0]" --output text)

if [ "$USER_POOL_ID" == "None" ]; then
  echo "Creating User Pool..."
  USER_POOL_ID=$(aws cognito-idp create-user-pool --pool-name $USER_POOL_NAME --region $REGION --profile $PROFILE --query 'UserPool.Id' --output text)
else
  echo "User Pool already exists: $USER_POOL_ID"
fi

# Check if User Pool Client exists
USER_POOL_CLIENT_ID=$(aws cognito-idp list-user-pool-clients --user-pool-id $USER_POOL_ID --max-results 10 --region $REGION --profile $PROFILE --query "UserPoolClients[?ClientName=='$USER_POOL_CLIENT_NAME'].ClientId | [0]" --output text)

if [ "$USER_POOL_CLIENT_ID" == "None" ]; then
  echo "Creating User Pool Client..."
  USER_POOL_CLIENT_ID=$(aws cognito-idp create-user-pool-client --user-pool-id $USER_POOL_ID --client-name $USER_POOL_CLIENT_NAME --generate-secret --region $REGION --profile $PROFILE --query 'UserPoolClient.ClientId' --output text)
else
  echo "User Pool Client already exists: $USER_POOL_CLIENT_ID"
fi

# Check if Identity Pool exists
IDENTITY_POOL_ID=$(aws cognito-identity list-identity-pools --max-results 10 --region $REGION --profile $PROFILE --query "IdentityPools[?IdentityPoolName=='$IDENTITY_POOL_NAME'].IdentityPoolId | [0]" --output text)

if [ "$IDENTITY_POOL_ID" == "None" ]; then
  echo "Creating Identity Pool..."
  IDENTITY_POOL_ID=$(aws cognito-identity create-identity-pool --identity-pool-name $IDENTITY_POOL_NAME --allow-unauthenticated-identities --region $REGION --profile $PROFILE --query 'IdentityPoolId' --output text)
else
  echo "Identity Pool already exists: $IDENTITY_POOL_ID"
fi

# Create roles if they do not exist
AUTH_ROLE_ARN=$(aws iam get-role --role-name $AUTH_ROLE_NAME --region $REGION --profile $PROFILE --query 'Role.Arn' --output text 2>/dev/null)
if [ -z "$AUTH_ROLE_ARN" ]; then
  echo "Creating Authenticated Role..."
  AUTH_ROLE_ARN=$(aws iam create-role --role-name $AUTH_ROLE_NAME --assume-role-policy-document file://<(echo '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"cognito-identity.amazonaws.com"},"Action":"sts:AssumeRoleWithWebIdentity","Condition":{"StringEquals":{"cognito-identity.amazonaws.com:aud":"'$IDENTITY_POOL_ID'"},"ForAnyValue:StringLike":{"cognito-identity.amazonaws.com:amr":"authenticated"}}}]}') --region $REGION --profile $PROFILE --query 'Role.Arn' --output text)
  aws iam attach-role-policy --role-name $AUTH_ROLE_NAME --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --region $REGION --profile $PROFILE
else
  echo "Authenticated Role already exists: $AUTH_ROLE_ARN"
fi

UNAUTH_ROLE_ARN=$(aws iam get-role --role-name $UNAUTH_ROLE_NAME --region $REGION --profile $PROFILE --query 'Role.Arn' --output text 2>/dev/null)
if [ -z "$UNAUTH_ROLE_ARN" ]; then
  echo "Creating Unauthenticated Role..."
  UNAUTH_ROLE_ARN=$(aws iam create-role --role-name $UNAUTH_ROLE_NAME --assume-role-policy-document file://<(echo '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Federated":"cognito-identity.amazonaws.com"},"Action":"sts:AssumeRoleWithWebIdentity","Condition":{"StringEquals":{"cognito-identity.amazonaws.com:aud":"'$IDENTITY_POOL_ID'"},"ForAnyValue:StringLike":{"cognito-identity.amazonaws.com:amr":"unauthenticated"}}}]}') --region $REGION --profile $PROFILE --query 'Role.Arn' --output text)
else
  echo "Unauthenticated Role already exists: $UNAUTH_ROLE_ARN"
fi

# Attach Roles to Identity Pool
echo "Attaching Roles to Identity Pool..."
aws cognito-identity set-identity-pool-roles --identity-pool-id $IDENTITY_POOL_ID --roles authenticated=$AUTH_ROLE_ARN,unauthenticated=$UNAUTH_ROLE_ARN --region $REGION --profile $PROFILE

echo "Setup completed. USER_POOL_ID=$USER_POOL_ID, USER_POOL_CLIENT_ID=$USER_POOL_CLIENT_ID, IDENTITY_POOL_ID=$IDENTITY_POOL_ID"