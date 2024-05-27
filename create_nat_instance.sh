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

# On the first run, create role and policy and attach them
# # Create IAM Role
# aws iam create-role --role-name "$IAM_ROLE_NAME" --assume-role-policy-document file://<(cat <<EOF
# {
#   "Version": "2012-10-17",
#   "Statement": [
#     {
#       "Effect": "Allow",
#       "Principal": {
#         "Service": "ec2.amazonaws.com"
#       },
#       "Action": "sts:AssumeRole"
#     }
#   ]
# }
# EOF
# ) --region "$REGION" --profile "$PROFILE"

# # Attach Policies to the Role
# aws iam attach-role-policy --role-name "$IAM_ROLE_NAME" \
#     --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore \
#     --region "$REGION" --profile "$PROFILE"
# aws iam attach-role-policy --role-name "$IAM_ROLE_NAME" \
#     --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess \
#     --region "$REGION" --profile "$PROFILE"

# # Create Instance Profile and Attach Role
# aws iam create-instance-profile --instance-profile-name "$IAM_ROLE_NAME" \
#     --region "$REGION" --profile "$PROFILE"
# aws iam add-role-to-instance-profile --instance-profile-name "$IAM_ROLE_NAME" \
#     --role-name "$IAM_ROLE_NAME" --region "$REGION" --profile "$PROFILE"

# # Wait for instance profile to be created
# sleep 10

# Define user data script for NAT configuration
USER_DATA=$(cat <<EOF
#!/bin/bash

# Enable IP forwarding
echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -w net.ipv4.ip_forward=1

# Install iptables-services
sudo yum install iptables-services -y

# Enable and start the iptables service
sudo systemctl enable iptables
sudo systemctl start iptables

# Add the NAT rule
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Save the iptables rules
sudo service iptables save

# Update the package repository and install updates
yum update -y
EOF
)

# Base64 encode the user data for Linux and macOS compatibility
USER_DATA_ENCODED=$(echo "$USER_DATA" | base64)

# Launch EC2 Instance without EBS volume, utilizing instance storage
INSTANCE_ID=$(aws ec2 run-instances --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --iam-instance-profile Name="$IAM_ROLE_NAME" \
    --subnet-id "$SUBNET_ID" \
    --region "$REGION" --profile "$PROFILE" \
    --user-data "$USER_DATA" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --network-interfaces "DeviceIndex=0,SubnetId=$SUBNET_ID,AssociatePublicIpAddress=true,Groups=$SECURITY_GROUP_ID" \
    --query 'Instances[0].InstanceId' --output text)

echo "Launched instance ID: $INSTANCE_ID"

# Wait for the instance to be running
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION" --profile "$PROFILE"

# Disable source/destination check
aws ec2 modify-instance-attribute --instance-id "$INSTANCE_ID" --no-source-dest-check --region "$REGION" --profile "$PROFILE"

# Check if the instance is registered with SSM
echo "Checking SSM registration..."
for i in {1..10}; do
  SSM_STATUS=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$INSTANCE_ID" \
    --region "$REGION" --profile "$PROFILE" --query "InstanceInformationList[0].PingStatus" --output text)
  if [ "$SSM_STATUS" == "Online" ]; then
    echo "Instance is online with SSM."
    break
  else
    echo "Waiting for SSM registration..."
    sleep 10
  fi
done

# Connect to the instance via SSM
aws ssm start-session --target "$INSTANCE_ID" --region "$REGION" --profile "$PROFILE"


