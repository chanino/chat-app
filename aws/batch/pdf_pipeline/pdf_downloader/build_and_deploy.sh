echo "" # Load environment variables from .env file
export $(grep -v '^#' .env | xargs)

echo "ACCOUNT_ID : $ACCOUNT_ID"
echo "REGION : $REGION"
echo "PROFILE : $PROFILE"
echo "BUCKET_NAME : $BUCKET_NAME"
echo "QUEUE_URL : $QUEUE_URL"
echo "DYNAMODB_TABLE : $DYNAMODB_TABLE"
CONTAINER_CMD='["python3", "./batch_processor.py"]'

echo "" # Function to check if a required variable is set
check_variable() {
    if [ -z "$1" ]; then
        echo "Error: $2 is not set."
    fi
}

echo "" # Check required variables
check_variable "$ACCOUNT_ID" "ACCOUNT_ID"
check_variable "$REGION" "REGION"
check_variable "$PROFILE" "PROFILE"
check_variable "$BUCKET_NAME" "BUCKET_NAME"
check_variable "$QUEUE_URL" "QUEUE_URL"
check_variable "$DYNAMODB_TABLE" "DYNAMODB_TABLE"

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

echo "" # Function to create or update IAM policy
create_or_update_policy() {
    local policy_name=$1
    local policy_document=$2

    aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$policy_name --region $REGION --profile $PROFILE >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo "Creating policy $policy_name..."
        aws iam create-policy --policy-name $policy_name --policy-document file://$policy_document --region $REGION --profile $PROFILE || { echo "Error creating policy $policy_name";  }
    else
        echo "Policy $policy_name exists. Checking for changes..."
        local policy_version=$(aws iam get-policy --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$policy_name --query 'Policy.DefaultVersionId' --output text --region $REGION --profile $PROFILE)
        local existing_policy_document=$(aws iam get-policy-version --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$policy_name --version-id $policy_version --query 'PolicyVersion.Document' --output json --region $REGION --profile $PROFILE)

        echo "$existing_policy_document" | jq --compact-output --sort-keys . > existing_policy.tmp
        jq --compact-output --sort-keys . "$policy_document" > new_policy.tmp
        if ! cmp -s existing_policy.tmp new_policy.tmp; then
            echo "Policy $policy_name has changed. Updating..."
            aws iam create-policy-version --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$policy_name --policy-document file://$policy_document --set-as-default --region $REGION --profile $PROFILE || { echo "Error updating policy $policy_name";  }
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
        aws iam create-role --role-name $role_name --assume-role-policy-document file://$assume_role_policy_document --region $REGION --profile $PROFILE || { echo "Error creating role $role_name";  }
        aws iam attach-role-policy --role-name $role_name --policy-arn arn:aws:iam::$ACCOUNT_ID:policy/$policy_name --region $REGION --profile $PROFILE || { echo "Error attaching policy to role $role_name";  }
    else
        echo "Role $role_name exists. Checking for changes..."
        local existing_assume_role_policy=$(aws iam get-role --role-name $role_name --query 'Role.AssumeRolePolicyDocument' --output json --region $REGION --profile $PROFILE)

        echo "$existing_assume_role_policy" | jq --compact-output --sort-keys . > existing_role.tmp
        jq --compact-output --sort-keys . "$assume_role_policy_document" > new_role.tmp
        if ! cmp -s existing_role.tmp new_role.tmp; then
            echo "Role $role_name has changed. Updating..."
            aws iam update-assume-role-policy --role-name $role_name --policy-document file://$assume_role_policy_document --region $REGION --profile $PROFILE || { echo "Error updating role $role_name";  }
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
echo "" # rm -f BatchServiceRolePolicy.json TaskExecutionRolePolicy.json BatchServiceRole.json TaskExecutionRole.json existing_policy.tmp new_policy.tmp existing_role.tmp new_role.tmp

echo "" # Login to Amazon ECR
aws ecr get-login-password --region $REGION --profile $PROFILE | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com

echo "" # Build, tag, and push the Docker image to ECR, specifying the platform for ARM
docker buildx build --platform linux/arm64 -t ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:${BATCH_JOB_NAME} --push .

echo "" # Setup job definition
cat <<EOF > job-definition.json
{
    "jobDefinitionName": "${BATCH_JOB_NAME}",
    "type": "container",
    "containerProperties": {
        "image": "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${REPO_NAME}:${BATCH_JOB_NAME}",
        "vcpus": 2,
        "memory": 4096,
        "command": ${CONTAINER_CMD},
        "environment": [
            {
                "name": "BUCKET_NAME",
                "value": "${BUCKET_NAME}"
            },
            {
                "name": "QUEUE_URL",
                "value": "${QUEUE_URL}"
            },
            {
                "name": "DYNAMODB_TABLE",
                "value": "${DYNAMODB_TABLE}"
            }
        ]
    }
}
EOF

echo "" # Get default subnets and security group - this could be customized
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text --region $REGION --profile $PROFILE)
SUBNET_IDS=$(aws ec2 describe-subnets --filters Name=vpc-id,Values=$DEFAULT_VPC_ID --query 'Subnets[*].SubnetId' --output text --region $REGION --profile $PROFILE)
DEFAULT_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups --filters Name=vpc-id,Values=$DEFAULT_VPC_ID Name=group-name,Values='default' --query 'SecurityGroups[0].GroupId' --output text --region $REGION --profile $PROFILE)
SUBNETS_JSON=$(echo $SUBNET_IDS | tr '\t' '\n' | jq -R -s 'split("\n") | map(select(length > 0))')

echo "DEFAULT_VPC_ID: $DEFAULT_VPC_ID"
echo "SUBNET_IDS: $SUBNET_IDS"
echo "DEFAULT_SECURITY_GROUP_ID: $DEFAULT_SECURITY_GROUP_ID"
echo "SUBNETS_JSON: $SUBNETS_JSON"

echo "" # Function to check if compute environment exists
check_compute_environment_exists() {
    COMPUTE_ENV_ARN=$(aws batch describe-compute-environments --compute-environments ${COMPUTE_ENV_NAME} --query 'computeEnvironments[0].computeEnvironmentArn' --output text --region $REGION --profile $PROFILE 2>/dev/null)
    if [ "$COMPUTE_ENV_ARN" = "None" ] || [ -z "$COMPUTE_ENV_ARN" ]; then
        echo ""
    else
        echo "$COMPUTE_ENV_ARN"
    fi
}

echo "" # Function to create a compute environment with default VPC, subnet, security group, etc.
create_compute_environment() {
    aws batch create-compute-environment --compute-environment-name ${COMPUTE_ENV_NAME} --type MANAGED --state ENABLED --compute-resources "type=EC2,maxvCpus=16,subnets=${SUBNETS_JSON},securityGroupIds=[\"${DEFAULT_SECURITY_GROUP_ID}\"]" --service-role arn:aws:iam::${ACCOUNT_ID}:role/service-role/${BATCH_ROLE} --region $REGION --profile $PROFILE
}

echo "" # Function to check if job queue exists
check_job_queue_exists() {
    JOB_QUEUE_ARN=$(aws batch describe-job-queues --job-queues $JOB_QUEUE --query 'jobQueues[0].jobQueueArn' --output text --region $REGION --profile $PROFILE 2>/dev/null)
    if [ "$JOB_QUEUE_ARN" = "None" ] || [ -z "$JOB_QUEUE_ARN" ]; then
        echo ""
    else
        echo "$JOB_QUEUE_ARN"
    fi
}

echo "" # Function to create a job queue
create_job_queue() {
    aws batch create-job-queue --job-queue-name $JOB_QUEUE --state ENABLED --priority 1 --compute-environment-order "order=1,computeEnvironment=${COMPUTE_ENV_NAME}" --region $REGION --profile $PROFILE
}

echo "" # Function to wait until the compute environment is valid
wait_for_compute_environment() {
    while true; do
        STATUS=$(aws batch describe-compute-environments --compute-environments ${COMPUTE_ENV_NAME} \
        --query 'computeEnvironments[0].status' --output text --region $REGION --profile $PROFILE)
        if [ "$STATUS" = "VALID" ]; then
            echo "Compute environment is valid."
            break
        else
            echo "Waiting for compute environment to become valid..."
            sleep 10
        fi
    done
}

echo "" # Check if compute environment exists
if [ -z "$(check_compute_environment_exists)" ]; then
    echo "Compute environment does not exist. Creating..."
    create_compute_environment
    wait_for_compute_environment
else
    echo "Compute environment already exists. Skipping creation."
    wait_for_compute_environment
fi

echo "" # Check if job queue exists
if [ -z "$(check_job_queue_exists)" ]; then
    echo "Job queue does not exist. Creating..."
    create_job_queue
else
    echo "Job queue already exists. Skipping creation."
fi

echo "" # Function to get the latest job definition revision
get_latest_job_definition_revision() {
    aws batch describe-job-definitions --job-definition-name $BATCH_JOB_NAME --query 'jobDefinitions[0].revision' --output text --region $REGION --profile $PROFILE
}

echo "" # Function to get the latest job definition JSON
get_latest_job_definition() {
    aws batch describe-job-definitions --job-definition-name $BATCH_JOB_NAME --query 'jobDefinitions[0]' --output json --region $REGION --profile $PROFILE
}

echo "" # Check if the job definition exists
LATEST_REVISION=$(get_latest_job_definition_revision)

if [ "$LATEST_REVISION" != "None" ]; then
    echo "Job definition exists. Checking for changes..."
    LATEST_JOB_DEFINITION=$(get_latest_job_definition)
    echo $LATEST_JOB_DEFINITION > latest-job-definition.json

    # Compare the new job definition with the latest one
    if cmp -s job-definition.json latest-job-definition.json; then
        echo "No changes detected in the job definition. Skipping registration."
        SUBMIT_JOB=true
    else
        echo "Changes detected in the job definition. Registering new job definition..."
        aws batch register-job-definition --cli-input-json file://job-definition.json --region $REGION --profile $PROFILE
        SUBMIT_JOB=true
    fi
else
    echo "Job definition does not exist. Registering new job definition..."
    aws batch register-job-definition --cli-input-json file://job-definition.json --region $REGION --profile $PROFILE
    SUBMIT_JOB=true
fi

echo "" # Submit the job if required
if [ "$SUBMIT_JOB" = true ]; then
    aws batch submit-job --job-name $JOB_NAME --job-queue $JOB_QUEUE --job-definition ${BATCH_JOB_NAME} --region $REGION --profile $PROFILE
fi

echo "" # Clean up temporary files
echo "" # rm -f job-definition.json latest-job-definition.json
