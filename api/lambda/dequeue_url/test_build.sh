mkdir lambda_package
pip install -r requirements.txt -t lambda_package/
cp lambda_function.py lambda_package/
cp pdf_downloader.py lambda_package/
cd lambda_package
zip -r ../function.zip .
cd ..

aws lambda update-function-code --function-name "dequeue_url" --zip-file fileb://function.zip \
    --region $REGION --profile $PROFILE

aws lambda delete-function --function-name "dequeue_url" \
    --region $REGION --profile $PROFILE

aws lambda create-function --function-name "dequeue_url" \
--zip-file fileb://function.zip --handler lambda_function.lambda_handler \
--runtime python3.9 --role arn:aws:iam::811945593738:role/LambdaS3DynamoDBRole \
--environment Variables="{BUCKET_NAME=chat-bro-userdata,QUEUE_URL=https://sqs.us-west-2.amazonaws.com/811945593738/MyReceiveURLQueue,DYNAMODB_TABLE=PdfMetadataTable}" \
--region $REGION --profile $PROFILE



aws dynamodb update-table \
    --table-name PdfMetadataTable \
    --attribute-definitions \
        AttributeName=url,AttributeType=S \
        AttributeName=s3_uri,AttributeType=S \
        AttributeName=status,AttributeType=S \
        AttributeName=timestamp,AttributeType=S \
        AttributeName=file_size,AttributeType=N \
    --global-secondary-index-updates \
        "[{\"Create\":{\"IndexName\": \"UrlIndex\",\"KeySchema\":[{\"AttributeName\":\"url\",\"KeyType\":\"HASH\"}],\"Projection\":{\"ProjectionType\":\"ALL\"}}}]" \
    --region $REGION --profile $PROFILE


aws dynamodb delete-table --table-name PdfMetadataTable --region $REGION --profile $PROFILE

aws dynamodb create-table \
    --table-name PdfMetadataTable \
    --attribute-definitions \
        AttributeName=url,AttributeType=S \
    --key-schema \
        AttributeName=url,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --global-secondary-indexes \
        "[{\"IndexName\": \"UrlIndex\",\"KeySchema\":[{\"AttributeName\":\"url\",\"KeyType\":\"HASH\"}],\"Projection\":{\"ProjectionType\":\"ALL\"}}]" \
    --region $REGION --profile $PROFILE

