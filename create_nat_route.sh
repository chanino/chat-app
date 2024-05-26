#!/bin/bash -xe

# Load environment variables from .env file
export $(grep -v '^#' nat.env | xargs)

# Variables (ensure these are set in your .env file)
# INSTANCE_TYPE="c6gd.medium"
# AMI_ID="ami-0d527b8c289b4af7f"  # Example AMI ID for Amazon Linux 2 ARM in us-west-2
# KEY_NAME="your-key-name"
# IAM_ROLE_NAME="NATInstanceRole"
# INSTANCE_NAME="NATInstance"
# PROFILE="your-aws-profile"
# REGION="us-west-2"
# SUBNET_ID="your-subnet-id"  # Add this to your .env file
# SECURITY_GROUP_ID="your-security-group-id"  # Security group allowing necessary traffic
# PRIVATE_SUBNET_ID="your-private-subnet-id"  # Subnet where other instances are located
# VPC_ID="your-vpc-id"  # Add this to your .env file
# ROUTE_TABLE_NAME="PrivateSubnetRouteTable"  # Name for the route table

# Retrieve the NAT instance ID using its name
NAT_INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=$INSTANCE_NAME" --query "Reservations[*].Instances[*].InstanceId" --output text --region $REGION --profile $PROFILE)
echo "NAT Instance ID: $NAT_INSTANCE_ID"

# Check if a route table with the specified name exists
EXISTING_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=tag:Name,Values=$ROUTE_TABLE_NAME" --query "RouteTables[*].RouteTableId" --output text --region $REGION --profile $PROFILE)

if [ -z "$EXISTING_ROUTE_TABLE_ID" ]; then
    # Create a new route table for the private subnet and capture its ID
    ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --region $REGION --profile $PROFILE)
    echo "Created Route Table ID: $ROUTE_TABLE_ID"

    # Tag the new route table
    aws ec2 create-tags --resources $ROUTE_TABLE_ID --tags Key=Name,Value=$ROUTE_TABLE_NAME --region $REGION --profile $PROFILE

    # Add a route to the new or existing route table to send traffic to the internet via the NAT instance
    aws ec2 create-route --route-table-id $ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --instance-id $NAT_INSTANCE_ID --region $REGION --profile $PROFILE || echo "Route already exists in Route Table ID: $ROUTE_TABLE_ID"

    # Associate the new or existing route table with the private subnet
    aws ec2 associate-route-table --route-table-id $ROUTE_TABLE_ID --subnet-id $PRIVATE_SUBNET_ID --region $REGION --profile $PROFILE
    echo "Associated Route Table ID: $ROUTE_TABLE_ID with Subnet ID: $PRIVATE_SUBNET_ID"

else
    ROUTE_TABLE_ID=$EXISTING_ROUTE_TABLE_ID
    echo "Using existing Route Table ID: $ROUTE_TABLE_ID"
fi


