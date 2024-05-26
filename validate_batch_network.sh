#!/bin/bash

# Describe the AWS Batch Compute Environment and get the subnet IDs and VPC ID
COMPUTE_ENV_DESC=$(aws batch describe-compute-environments --compute-environments $COMPUTE_ENV_NAME \
    --region $REGION --profile $PROFILE)
SUBNET_IDS=$(echo $COMPUTE_ENV_DESC | jq -r '.computeEnvironments[0].computeResources.subnets[]')
SECURITY_GROUPS=$(echo $COMPUTE_ENV_DESC | jq -r '.computeEnvironments[0].computeResources.securityGroupIds[]')
echo "SUBNET_IDS: $SUBNET_IDS"
echo "SECURITY_GROUPS: $SECURITY_GROUPS"

# Extract VPC ID for each subnet and check route table associations
for SUBNET_ID in $SUBNET_IDS; do
  echo "Describing Subnet: $SUBNET_ID"
  
  # Describe the subnet to retrieve its details
  SUBNET_DESC=$(aws ec2 describe-subnets --subnet-ids $SUBNET_ID --region $REGION --profile $PROFILE)
  VPC_ID=$(echo $SUBNET_DESC | jq -r '.Subnets[0].VpcId')
  
  echo "SUBNET_ID: $SUBNET_ID"
  echo "VPC_ID: $VPC_ID"
  
  # Check for associated route tables
  echo "Describing Route Tables for Subnet: $SUBNET_ID"
  ROUTE_TABLES=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$SUBNET_ID" --region $REGION --profile $PROFILE)
  
  if [[ $(echo $ROUTE_TABLES | jq '.RouteTables | length') -eq 0 ]]; then
    echo "No specific route tables found for Subnet: $SUBNET_ID. Checking main route table for VPC: $VPC_ID."
    
    # Get the main route table for the VPC
    MAIN_ROUTE_TABLE=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --profile $PROFILE)
    MAIN_ROUTE_TABLE_ID=$(echo $MAIN_ROUTE_TABLE | jq -r '.RouteTables[] | select(.Associations[]?.Main == true) | .RouteTableId')
    
    if [ -n "$MAIN_ROUTE_TABLE_ID" ]; then
      echo "Main Route Table for VPC: $VPC_ID"
      aws ec2 describe-route-tables --route-table-ids $MAIN_ROUTE_TABLE_ID --region $REGION --profile $PROFILE | jq '.'
    else
      echo "No main route table found for VPC: $VPC_ID"
    fi
  else
    echo "Route Tables for Subnet: $SUBNET_ID"
    echo $ROUTE_TABLES | jq '.'
  fi
  
  echo "========================================"
done

# Describe Internet Gateways
echo "Describing Internet Gateways..."
aws ec2 describe-internet-gateways --region $REGION --profile $PROFILE

# Describe NAT Gateways
echo "Describing NAT Gateways..."
aws ec2 describe-nat-gateways --region $REGION --profile $PROFILE

# Describe Security Groups
echo "Describing Security Groups..."
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --profile $PROFILE

# Describe Network ACLs
echo "Describing Network ACLs..."
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --profile $PROFILE

# Check IAM Role Policies
echo "Listing IAM Role Policies..."
aws iam list-attached-role-policies --role-name $BATCH_ROLE --region $REGION --profile $PROFILE
aws iam list-role-policies --role-name $BATCH_ROLE --region $REGION --profile $PROFILE

# Describe VPC Endpoints
echo "Describing VPC Endpoints..."
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$VPC_ID" --region $REGION --profile $PROFILE