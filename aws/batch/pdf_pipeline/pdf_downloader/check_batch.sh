#!/bin/bash

# Load environment variables from .env2 file
export $(grep -v '^#' .env | xargs)

echo "COMPUTE_ENV_NAME: $COMPUTE_ENV_NAME"
# Describe the compute environment and extract the service role
compute_env_json=$(aws batch describe-compute-environments --compute-environments "$COMPUTE_ENV_NAME" \
    --region "$REGION" --profile "$PROFILE")

# Extract the service role using jq
service_role=$(echo "$compute_env_json" | jq -r '.computeEnvironments[0].serviceRole')

# Check if the service role was extracted successfully
if [ -z "$service_role" ]; then
  echo "Service role not found."
  exit 1
fi

echo "Service Role: $service_role"

# Extract the role name from the ARN
role_name=$(echo "$service_role" | awk -F'/' '{print $NF}')

# Get the details of the IAM role
role_details=$(aws iam get-role --role-name "$role_name" \
    --region "$REGION" --profile "$PROFILE")

# Output the role details
echo "Role Details: $role_details"

# Save role details to a file
echo "$role_details" > "${role_name}_role_details.json"

# List attached role policies
attached_policies=$(aws iam list-attached-role-policies --role-name "$role_name" \
    --region "$REGION" --profile "$PROFILE")
echo "Attached Policies: $attached_policies"

# Save attached policies to a file
echo "$attached_policies" > "${role_name}_attached_policies.json"

# List inline role policies
inline_policies=$(aws iam list-role-policies --role-name "$role_name" \
    --region "$REGION" --profile "$PROFILE")
echo "Inline Policies: $inline_policies"

# Save inline policies to a file
echo "$inline_policies" > "${role_name}_inline_policies.json"

# Describe each attached policy and save to a file
echo "Attached Policy Details:"
for policy_arn in $(echo "$attached_policies" | jq -r '.AttachedPolicies[].PolicyArn'); do
  policy_name=$(echo "$policy_arn" | awk -F'/' '{print $NF}')
  policy_details=$(aws iam get-policy --policy-arn "$policy_arn" \
    --region "$REGION" --profile "$PROFILE")
  echo "Policy Name: $policy_name"
  echo "Policy Details: $policy_details"
  echo "$policy_details" > "${role_name}_${policy_name}_policy.json"
  
  # Get the policy document version
  policy_version=$(echo "$policy_details" | jq -r '.Policy.DefaultVersionId')
  policy_document=$(aws iam get-policy-version --policy-arn "$policy_arn" --version-id "$policy_version" \
    --region "$REGION" --profile "$PROFILE")
  echo "$policy_document" > "${role_name}_${policy_name}_policy_document.json"
  
  # Output the policy document
  echo "Policy Document for $policy_name:"
  echo "$policy_document"
done

# Describe each inline policy and save to a file
echo "Inline Policy Details:"
for policy_name in $(echo "$inline_policies" | jq -r '.PolicyNames[]'); do
  policy_details=$(aws iam get-role-policy --role-name "$role_name" --policy-name "$policy_name" \
    --region "$REGION" --profile "$PROFILE")
  echo "Policy Name: $policy_name"
  echo "Policy Details: $policy_details"
  echo "$policy_details" > "${role_name}_${policy_name}_inline_policy.json"
done

# aws iam create-role --role-name CustomBatchServiceRole --assume-role-policy-document file://trust-policy.json \
#     --region $REGION --profile $PROFILE
# aws iam attach-role-policy --role-name CustomBatchServiceRole \
#     --policy-arn arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole --region $REGION --profile $PROFILE
# aws iam attach-role-policy --role-name CustomBatchServiceRole \
#     --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/BatchCustomPolicy --region $REGION --profile $PROFILE
# aws batch update-compute-environment --compute-environment "$COMPUTE_ENV_NAME" \
#     --service-role arn:aws:iam::${ACCOUNT_ID}:role/CustomBatchServiceRole \
#     --region $REGION --profile $PROFILE
