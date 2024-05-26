#!/bin/bash -xe

# Load environment variables from .env file
export $(grep -v '^#' .env | xargs)

# Variables (ensure these are set in your .env file)
# INSTANCE_TYPE="t4g.micro"
# AMI_ID="ami-0b61ab36e7d8d5881"  # Example AMI ID for Amazon Linux 2 ARM in us-west-2
# KEY_NAME="your-key-name"
# IAM_ROLE_NAME="SSMGravitonInstanceRole"
# INSTANCE_NAME="GravitonSSMInstance"
# PROFILE="your-aws-profile"
# REGION="us-west-2"
# SUBNET_ID="your-subnet-id"  # Add this to your .env file
# EBS_VOLUME_SIZE=8  # Example size in GiB
# VPC_ID="your-vpc-id"  # Add this to your .env file

# Create Interface Endpoints

# ECR API Endpoint
aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --service-name com.amazonaws.us-west-2.ecr.api \
  --vpc-endpoint-type Interface --subnet-ids "$SUBNET_ID" --security-group-ids "$SECURITY_GROUP_ID" \
  --region "$REGION" --profile "$PROFILE"

# ECR DKR Endpoint
aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --service-name com.amazonaws.us-west-2.ecr.dkr \
  --vpc-endpoint-type Interface --subnet-ids "$SUBNET_ID" --security-group-ids "$SECURITY_GROUP_ID" \
  --region "$REGION" --profile "$PROFILE"

# SSM Endpoint
aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --service-name com.amazonaws.us-west-2.ssm \
  --vpc-endpoint-type Interface --subnet-ids "$SUBNET_ID" --security-group-ids "$SECURITY_GROUP_ID" \
  --region "$REGION" --profile "$PROFILE"

# SSM Messages Endpoint
aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --service-name com.amazonaws.us-west-2.ssmmessages \
  --vpc-endpoint-type Interface --subnet-ids "$SUBNET_ID" --security-group-ids "$SECURITY_GROUP_ID" \
  --region "$REGION" --profile "$PROFILE"

# EC2 Messages Endpoint
aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --service-name com.amazonaws.us-west-2.ec2messages \
  --vpc-endpoint-type Interface --subnet-ids "$SUBNET_ID" --security-group-ids "$SECURITY_GROUP_ID" \
  --region "$REGION" --profile "$PROFILE"

# SQS Endpoint
aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --service-name com.amazonaws.$REGION.sqs \
  --vpc-endpoint-type Interface --subnet-ids "$SUBNET_ID" --security-group-ids "$SECURITY_GROUP_ID" \
  --region "$REGION" --profile "$PROFILE"

# DynamoDB Endpoint
aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --service-name com.amazonaws.$REGION.dynamodb \
  --vpc-endpoint-type Interface --subnet-ids "$SUBNET_ID" --security-group-ids "$SECURITY_GROUP_ID" \
  --region "$REGION" --profile "$PROFILE"

# Create Gateway Endpoint for S3
aws ec2 create-vpc-endpoint --vpc-id "$VPC_ID" --service-name com.amazonaws.us-west-2.s3 \
  --vpc-endpoint-type Gateway --route-table-ids $MAIN_ROUTE_TABLE_ID \
  --region "$REGION" --profile "$PROFILE"
