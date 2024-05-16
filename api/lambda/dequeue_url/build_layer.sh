#!/bin/bash

# Set variables
PYTHON_VERSION=python3.9
LAYER_NAME=pdf_processing_layer
LAYER_ZIP=layer.zip
BUCKET_NAME="chat-bro-userdata"
LAYER_S3_KEY=layers/$LAYER_ZIP


# Create a virtual environment
echo "Creating virtual environment..."
$PYTHON_VERSION -m venv venv
source venv/bin/activate

# Install dependencies from requirements.txt
echo "Installing dependencies..."
pip install -r requirements.txt

# Prepare the Lambda layer package
echo "Preparing Lambda layer package..."
mkdir -p layer/python/lib/$PYTHON_VERSION/site-packages
cp -r venv/lib/$PYTHON_VERSION/site-packages/* layer/python/lib/$PYTHON_VERSION/site-packages/
cd layer
zip -r9 ../$LAYER_ZIP .
cd ..

# Upload the Lambda layer package to S3
echo "Uploading Lambda layer package to S3..."
aws s3 cp $LAYER_ZIP s3://$BUCKET_NAME/$LAYER_S3_KEY --region $REGION --profile $PROFILE

# Publish a new layer version
echo "Publishing new Lambda layer version..."
LAYER_VERSION=$(aws lambda publish-layer-version --layer-name $LAYER_NAME --description "PDF processing dependencies" --content S3Bucket=$BUCKET_NAME,S3Key=$LAYER_S3_KEY --compatible-runtimes $PYTHON_VERSION --region $REGION --profile $PROFILE --output text --query Version)

# Add public access permissions to the layer (optional)
aws lambda add-layer-version-permission --layer-name $LAYER_NAME --version-number $LAYER_VERSION --statement-id public-access --action lambda:GetLayerVersion --principal "*" --region $REGION --profile $PROFILE

# Clean up
echo "Cleaning up..."
deactivate
rm -rf venv layer $LAYER_ZIP

echo "Published new layer version: $LAYER_VERSION"
