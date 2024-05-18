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
--environment Variables="{BUCKET_NAME=chat-bro-userdata,QUEUE_URL=https://sqs.us-west-2.amazonaws.com/811945593738/MyReceiveURLQueue,TABLE_NAME=PdfMetadataTable}" \
--region $REGION --profile $PROFILE


