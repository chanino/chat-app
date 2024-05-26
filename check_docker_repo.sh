export $(grep -v '^#' .env | xargs)

aws ecr get-login-password --region $REGION --profile $PROFILE \
    | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

aws ecr describe-images --repository-name ${REPO_NAME} --region $REGION --profile $PROFILE

