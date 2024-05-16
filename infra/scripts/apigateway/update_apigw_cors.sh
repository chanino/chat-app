API_NAME="ChatBroAPI"

API_ID=$(aws apigateway get-rest-apis --region "$REGION" --profile "$PROFILE" \
    --query "items[?name=='$API_NAME'].id" --output text)
echo "API ID: $API_ID"

RESOURCE_PATH="message"
RESOURCE_ID=$(aws apigateway get-resources --rest-api-id "$API_ID" --region "$REGION" --profile "$PROFILE" \
    --query "items[?path=='/$RESOURCE_PATH'].id" --output text)
echo "RESOURCE_ID: $RESOURCE_ID"

aws apigateway update-method-response \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method POST \
    --status-code 200 \
    --patch-operations op=replace,path=/responseParameters/method.response.header.Access-Control-Allow-Origin,value="'*'"\
    --region $REGION --profile $PROFILE



aws apigateway put-integration-response \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method POST \
    --status-code 200 \
    --response-templates application/json="{}" \
    --content-handling CONVERT_TO_TEXT \
    --region $REGION --profile $PROFILE

aws apigateway update-method-response \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method POST \
    --status-code 200 \
    --patch-operations op=add,path=/responseParameters/method.response.header.Access-Control-Allow-Origin,value="'*'" \
    --region $REGION --profile $PROFILE

aws apigateway update-integration-response \
    --rest-api-id "$API_ID" \
    --resource-id "$RESOURCE_ID" \
    --http-method POST \
    --status-code 200 \
    --patch-operations op=add,path=/responseParameters/method.response.header.Access-Control-Allow-Origin,value="'*'" \
    --region $REGION --profile $PROFILE

aws apigateway create-deployment --rest-api-id "$API_ID" --stage-name 'prod' \
    --region "$REGION" --profile "$PROFILE"


