#!/bin/bash

# Set the Python version and Lambda function name
PYTHON_VERSION=python3.9
LAMBDA_FUNCTION_NAME=firebase-authenticator

# Create a virtual environment
echo "Creating virtual environment..."
$PYTHON_VERSION -m venv venv
source venv/bin/activate

# Install dependencies from requirements.txt
echo "Installing dependencies..."
pip install -r requirements.txt

# # Clean up unnecessary files
# echo "Cleaning up..."
# find venv/lib/$PYTHON_VERSION/site-packages/ -name "*.pyc" -delete
# find venv/lib/$PYTHON_VERSION/site-packages/ -type d -name "tests" -exec rm -rf {} +

# Prepare the deployment package
current_dir=$(pwd)
cd venv/lib/$PYTHON_VERSION/site-packages/
echo "Preparing deployment package..."
zip -r9 $current_dir/deployment.zip .

# Add your lambda function code and the Firebase Admin SDK JSON key to the deployment package
echo "Adding Lambda function code and JSON key to the package..."
cd $current_dir
zip -g deployment.zip lambda_function.py aspertusia-com-firebase-adminsdk-35ey4-bccc899aea.json

# Deactivate virtual environment
deactivate

echo "Deployment package is ready."
