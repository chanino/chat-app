# Variables
FUNCTION_NAME="pdf2pngs"
ZIP_FILE="function.zip"
PYTHON_FILE="lambda_function.py"
REQUIREMENTS_FILE="requirements.txt"
LAMBDA_ROLE_ARN="arn:aws:iam::811945593738:role/LambdaS3DynamoDBRole"
BUCKET_NAME="chat-bro-userdata"
DYNAMODB_TABLE="PdfMetadataTable"

docker buildx build --platform linux/arm64 \
-t ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/my-repo:latest --push .


aws lambda delete-function --function-name $FUNCTION_NAME --region $REGION --profile $PROFILE

aws lambda create-function --function-name $FUNCTION_NAME \
--package-type Image \
--code ImageUri=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/my-repo:latest \
--role $LAMBDA_ROLE_ARN \
--environment Variables="{BUCKET_NAME=${BUCKET_NAME},DYNAMODB_TABLE=${DYNAMODB_TABLE}}" \
--architectures arm64 \
--region $REGION --profile $PROFILE


aws lambda update-function-code --function-name "$FUNCTION_NAME" \
--image-uri ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/my-repo:latest \
--region $REGION --profile $PROFILE

aws lambda update-function-configuration \
    --function-name $FUNCTION_NAME \
    --memory-size 3000 \
    --timeout 30 \
    --region $REGION \
    --profile $PROFILE

aws lambda invoke --function-name $FUNCTION_NAME --region $REGION --profile $PROFILE \
 --cli-binary-format raw-in-base64-out \
 --payload '{"Records":[{"s3":{"bucket":{"name":"chat-bro-userdata"},"object":{"key":"docs_aws_amazon_com/introduction-aws-security/introduction-aws-security.pdf"}}}]}' response.json



# Build the Docker image
docker build -t lambda-container .

docker run  -p 9000:8080 lambda-container:latest
curl "http://localhost:9000/2015-03-31/functions/function/invocations" -d '{}'


# Login to ECR
aws ecr get-login-password --region $REGION --profile $PROFILE \
 | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

aws ecr create-repository --repository-name my-repo --region $REGION --profile $PROFILE

docker tag lambda-container:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/my-repo:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/my-repo:latest

aws lambda delete-function --function-name $FUNCTION_NAME --region $REGION --profile $PROFILE

aws lambda create-function --function-name $FUNCTION_NAME \
--package-type Image \
--code ImageUri=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/my-repo:latest \
--role $LAMBDA_ROLE_ARN \
--environment Variables="{BUCKET_NAME=$BUCKET_NAME,DYNAMODB_TABLE=$DYNAMODB_TABLE}" \
--region $REGION --profile $PROFILE

aws lambda create-function \
  --function-name $FUNCTION_NAME \
  --package-type Image \
  --code ImageUri=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/my-repo:latest  \
  --role $LAMBDA_ROLE_ARN \
  --region $REGION --profile $PROFILE


aws lambda update-function-code --function-name "$FUNCTION_NAME" \
--image-uri ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/my-repo:latest \
--region $REGION --profile $PROFILE

aws lambda invoke --function-name $FUNCTION_NAME --region $REGION --profile $PROFILE \
 --cli-binary-format raw-in-base64-out \
 --payload '{"Records":[{"s3":{"bucket":{"name":"$BUCKET_NAME"},"object":{"key":"docs_aws_amazon_com/introduction-aws-security/introduction-aws-security.pdf"}}}]}' response.json


aws lambda add-permission \
    --function-name ${FUNCTION_NAME} \
    --statement-id s3invoke \
    --action "lambda:InvokeFunction" \
    --principal s3.amazonaws.com \
    --source-arn arn:aws:s3:::${BUCKET_NAME} \
    --source-account $ACCOUNT_ID \
    --region $REGION --profile $PROFILE

# Create the notification policy variable
NOTIFICATION_POLICY=$(cat <<EOF
{
    "LambdaFunctionConfigurations": [
        {
            "Id": "InvokeLambdaFunctionOnPDFUpload",
            "LambdaFunctionArn": "arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:${FUNCTION_NAME}",
            "Events": ["s3:ObjectCreated:*"],
            "Filter": {
                "Key": {
                    "FilterRules": [
                        {
                            "Name": "suffix",
                            "Value": ".pdf"
                        }
                    ]
                }
            }
        }
    ]
}
EOF
)

# Echo the notification policy to ensure it is accurate
echo "$NOTIFICATION_POLICY"

# Add Lambda permissions
aws lambda add-permission \
    --function-name $FUNCTION_NAME \
    --statement-id s3invoke \
    --action "lambda:InvokeFunction" \
    --principal s3.amazonaws.com \
    --source-arn arn:aws:s3:::$BUCKET_NAME \
    --region $REGION --profile $PROFILE

# Apply the notification policy
aws s3api put-bucket-notification-configuration \
    --bucket $BUCKET_NAME \
    --notification-configuration "$NOTIFICATION_POLICY" \
    --region $REGION --profile $PROFILE


docker run --rm -it lambda-package-container /bin/bash

echo "
from io import BytesIO
from pdf2image import convert_from_bytes
import logging

# Set up logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def convert_pdf2pngs(pdf_content):
    images = convert_from_bytes(pdf_content)
    logger.info(f'Number of pages: {len(images)}')
    png_images = []
    
    for i, image in enumerate(images, start=1):
        image_buffer = BytesIO()
        image.save(image_buffer, format='PNG')
        image_buffer.seek(0)
        png_images.append(image_buffer)
        logger.info(f'Converted page {i} to PNG')
    
    return png_images

# Example usage
if __name__ == '__main__':
    # Create a simple PDF in memory
    pdf_content = b'%PDF-1.4\n1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Count 1 /Kids [3 0 R] >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >>\nendobj\n4 0 obj\n<< /Length 44 >>\nstream\nBT /F1 24 Tf 100 700 Td (Hello, PDF2Image!) Tj ET\nendstream\nendobj\nxref\n0 5\n0000000000 65535 f\n0000000010 00000 n\n0000000063 00000 n\n0000000111 00000 n\n0000000200 00000 n\ntrailer\n<< /Size 5 /Root 1 0 R >>\nstartxref\n304\n%%EOF\n'
    convert_pdf2pngs(pdf_content)
" > test_pdf2png.py

# local build
# Build the Docker image
docker build --platform linux/arm64 -t mytest .

# Run the Docker container and get a bash shell, removing the container when you exit
docker run --rm -it --entrypoint /bin/bash mytest

aws lambda get-function-configuration --function-name $FUNCTION_NAME \
--region $REGION --profile $PROFILE