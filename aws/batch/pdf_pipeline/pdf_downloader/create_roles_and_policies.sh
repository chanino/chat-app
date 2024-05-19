echo "" # Load environment variables from .env file
export $(grep -v '^#' .env | xargs)

echo "ACCOUNT_ID : $ACCOUNT_ID"
echo "REGION : $REGION"
echo "PROFILE : $PROFILE"
echo "BUCKET_NAME : $BUCKET_NAME"
echo "QUEUE_URL : $QUEUE_URL"
echo "DYNAMODB_TABLE : $DYNAMODB_TABLE"
ECS_ROLE_ARN=$(aws iam list-roles \
    --query "Roles[?contains(RoleName, 'EcsService') && contains(RoleName, 'prod')].Arn | [0]" \
    --output text --region $REGION --profile $PROFILE)
if [ -z "$ECS_ROLE_ARN" ]; then
    echo "Error: ECS Task Role ARN not found."
fi
echo "ECS_ROLE_ARN : $ECS_ROLE_ARN"

echo "" # Function to check if a required variable is set
check_variable() {
    if [ -z "$1" ]; then
        echo "Error: $2 is not set."
        exit 1
    fi
}

echo "" # Check required variables
check_variable "$ACCOUNT_ID" "ACCOUNT_ID"
check_variable "$REGION" "REGION"
check_variable "$PROFILE" "PROFILE"
check_variable "$BUCKET_NAME" "BUCKET_NAME"
check_variable "$QUEUE_URL" "QUEUE_URL"
check_variable "$DYNAMODB_TABLE" "DYNAMODB_TABLE"

echo "" # Create BatchServiceRolePolicy.json
cat <<EOF > BatchServiceRolePolicy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:${REGION}:${ACCOUNT_ID}:log-group:/aws/batch/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "ec2:DescribeVpcs",
                "ec2:DescribeSubnets",
                "ec2:DescribeSecurityGroups",
                "ecs:DescribeClusters",
                "ecs:DescribeContainerInstances",
                "ecs:DescribeTaskDefinition",
                "ecs:ListContainerInstances",
                "ecs:ListTasks",
                "iam:PassRole",
                "batch:SubmitJob",
                "batch:DescribeJobQueues",
                "batch:DescribeJobDefinitions",
                "batch:DescribeJobs",
                "batch:ListJobs"
            ],
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "sts:AssumeRole",
            "Resource": "arn:aws:iam::${ACCOUNT_ID}:role/service-role/${$BATCH_ROLE}"
        }
    ]
}
EOF

echo "" # Create TaskExecutionRolePolicy.json
cat <<EOF > TaskExecutionRolePolicy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${BUCKET_NAME}",
                "arn:aws:s3:::${BUCKET_NAME}/*"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes"
            ],
            "Resource": [
                "arn:aws:sqs:${REGION}:${ACCOUNT_ID}:${QUEUE_URL##*/}"
            ]
        },
        {
            "Effect": "Allow",
            "Action": [
                "dynamodb:PutItem",
                "dynamodb:UpdateItem",
                "dynamodb:GetItem"
            ],
            "Resource": [
                "arn:aws:dynamodb:${REGION}:${ACCOUNT_ID}:table/${DYNAMODB_TABLE}"
            ]
        }
    ]
}
EOF

echo "" # Create BatchServiceRole.json
cat <<EOF > BatchServiceRole.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "batch.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        },
        {
            "Effect": "Allow",
            "Principal": {
                "AWS": "${ECS_ROLE_ARN}"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

echo "" # Create TaskExecutionRole.json
cat <<EOF > TaskExecutionRole.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ecs-tasks.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

echo "" # Function to create or update IAM policy
create_or_update_policy() {
    local policy_name=$1
    local policy_document=$2

    aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$policy_name \
        --region $REGION --profile $PROFILE >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Creating policy $policy_name..."
        aws iam create-policy --policy-name $policy_name --policy-document file://$policy_document \
            --region $REGION --profile $PROFILE || { echo "Error creating policy $policy_name"; exit 1; }
    else
        echo "Policy $policy_name exists. Checking for changes..."
        local policy_version=$(aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$policy_name \
            --query 'Policy.DefaultVersionId' --output text --region $REGION --profile $PROFILE)
        local existing_policy_document=$(aws iam get-policy-version \
            --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$policy_name \
            --version-id $policy_version --query 'PolicyVersion.Document' \
            --output json --region $REGION --profile $PROFILE)

        if ! echo "$existing_policy_document" | jq --compact-output --sort-keys . > existing_policy.tmp && \
           jq --compact-output --sort-keys . "$policy_document" > new_policy.tmp && \
           cmp -s existing_policy.tmp new_policy.tmp; then
            echo "Policy $policy_name has changed. Updating..."
            aws iam create-policy-version --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$policy_name \
                --policy-document file://$policy_document --set-as-default \
                --region $REGION --profile $PROFILE || { echo "Error updating policy $policy_name"; exit 1; }
        else
            echo "No changes detected in policy $policy_name."
        fi
    fi
}

echo "" # Function to create or update IAM role
create_or_update_role() {
    local role_name=$1
    local assume_role_policy_document=$2
    local policy_name=$3

    aws iam get-role --role-name $role_name --region $REGION --profile $PROFILE >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Creating role $role_name..."
        aws iam create-role --role-name $role_name \
            --assume-role-policy-document file://$assume_role_policy_document \
            --region $REGION --profile $PROFILE || { echo "Error creating role $role_name"; exit 1; }
        aws iam attach-role-policy --role-name $role_name \
            --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$policy_name --region $REGION --profile $PROFILE || { echo "Error attaching policy to role $role_name"; exit 1; }
    else
        echo "Role $role_name exists. Checking for changes..."
        local existing_assume_role_policy=$(aws iam get-role --role-name $role_name \
            --query 'Role.AssumeRolePolicyDocument' --output json --region $REGION --profile $PROFILE)

        if ! echo "$existing_assume_role_policy" | jq --compact-output --sort-keys . > existing_role.tmp && \
            jq --compact-output --sort-keys . "$assume_role_policy_document" > new_role.tmp && \
            cmp -s existing_role.tmp new_role.tmp; then
            echo "Role $role_name has changed. Updating..."
            aws iam update-assume-role-policy --role-name $role_name \
                --policy-document file://$assume_role_policy_document --region $REGION --profile $PROFILE || { echo "Error updating role $role_name"; exit 1; }
        else
            echo "No changes detected in role $role_name."
        fi
    fi
}

echo "" # Create or update policies
create_or_update_policy "BatchServiceRolePolicy" "BatchServiceRolePolicy.json"
create_or_update_policy "TaskExecutionRolePolicy" "TaskExecutionRolePolicy.json"

echo "" # Create or update roles
create_or_update_role "AWSBatchServiceRole" "BatchServiceRole.json" "BatchServiceRolePolicy"
create_or_update_role "BatchTaskExecutionRole" "TaskExecutionRole.json" "TaskExecutionRolePolicy"

echo "" # Cleanup temporary files
rm -f BatchServiceRolePolicy.json TaskExecutionRolePolicy.json BatchServiceRole.json TaskExecutionRole.json existing_policy.tmp new_policy.tmp existing_role.tmp new_role.tmp
