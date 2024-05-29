#!/bin/bash

# Load environment variables from .env file
echo "Loading environment variables from start.env..."
export $(grep -v '^#' start.env | xargs)

start_instance() {
    local instance_id=$1
    local instance_name=$2

    echo "Checking the current state of the $instance_name instance..."
    instance_state=$(aws ec2 describe-instances --instance-ids $instance_id \
        --region $REGION --profile $PROFILE --query 'Reservations[*].Instances[*].State.Name' \
        --output text)
    echo "Current $instance_name instance state: $instance_state"
    
    if [ "$instance_state" != "running" ]; then
        echo "Starting the $instance_name instance..."
        aws ec2 start-instances --instance-ids $instance_id \
            --region $REGION --profile $PROFILE
        echo "Starting $instance_name instance: $instance_id"
        
        # Wait for the instance to be in 'running' state
        echo "Waiting for the $instance_name instance to reach 'running' state..."
        aws ec2 wait instance-running --instance-ids $instance_id \
            --region $REGION --profile $PROFILE
        echo "$instance_name instance is running."
    else
        echo "$instance_name instance is already running."
    fi
    
    # Wait for the instance to be in 'status ok' state
    echo "Waiting for the $instance_name instance to reach 'status ok' state..."
    aws ec2 wait instance-status-ok --instance-ids $instance_id \
        --region $REGION --profile $PROFILE
    echo "$instance_name instance is initialized and ready."
}

stop_instance() {
    local instance_id=$1
    local instance_name=$2

    echo "Stopping the $instance_name instance..."
    aws ec2 stop-instances --instance-ids $instance_id \
        --region $REGION --profile $PROFILE
    echo "Stopping $instance_name instance: $instance_id"
    
    # Wait for the instance to be in 'stopped' state
    echo "Waiting for the $instance_name instance to reach 'stopped' state..."
    aws ec2 wait instance-stopped --instance-ids $instance_id \
        --region $REGION --profile $PROFILE
    echo "$instance_name instance is stopped."
}

test_nat_connectivity() {
    local test_instance_id=$1

    echo "Testing NAT instance connectivity from test instance $test_instance_id..."
    ssm_command_id=$(aws ssm send-command \
        --instance-ids $test_instance_id \
        --document-name "AWS-RunShellScript" \
        --parameters 'commands=["curl -sSf https://www.google.com > /dev/null"]' \
        --region $REGION --profile $PROFILE \
        --query 'Command.CommandId' --output text)
    
    echo "SSM command ID: $ssm_command_id"
    
    # Wait for the command to complete
    aws ssm wait command-executed --command-id $ssm_command_id --instance-id $test_instance_id \
        --region $REGION --profile $PROFILE
    
    # Check command status
    command_status=$(aws ssm get-command-invocation \
        --command-id $ssm_command_id --instance-id $test_instance_id \
        --region $REGION --profile $PROFILE \
        --query 'Status' --output text)
    
    if [ "$command_status" == "Success" ]; then
        echo "NAT instance connectivity test passed."
    else
        echo "NAT instance connectivity test failed."
        exit 1
    fi
}

submit_batch_job() {
    echo "Getting the latest job definition ARN..."
    JOB_DEFINITION_ARN=$(aws batch describe-job-definitions \
        --job-definition-name $BATCH_JOB_NAME \
        --status ACTIVE \
        --region $REGION \
        --profile $PROFILE \
        --query 'jobDefinitions[?status==`ACTIVE`]|[0].jobDefinitionArn' \
        --output text)
    echo "Latest Job Definition ARN: $JOB_DEFINITION_ARN"
    
    echo "Submitting the batch job..."
    JOB_ID=$(aws batch submit-job \
        --job-name $BATCH_JOB_NAME \
        --job-queue $JOB_QUEUE \
        --job-definition $JOB_DEFINITION_ARN \
        --region $REGION \
        --profile $PROFILE \
        --query 'jobId' \
        --output text)
    echo "Job submitted successfully. Job ID: $JOB_ID"
    
    echo "Waiting for the job to complete with a timeout of $JOB_TIMEOUT seconds."
    
    start_time=$(date +%s)
    end_time=$((start_time + JOB_TIMEOUT))
    job_status=""
    
    while [ $(date +%s) -lt $end_time ]; do
        echo "Checking the job status..."
        job_status=$(aws batch describe-jobs --jobs $JOB_ID \
            --region $REGION --profile $PROFILE --query 'jobs[0].status' --output text)
        echo "Current job status: $job_status"
        
        if [[ "$job_status" == "SUCCEEDED" || "$job_status" == "FAILED" ]]; then
            break
        fi
        
        sleep 10
    done
    
    if [ "$job_status" == "SUCCEEDED" ]; then
        echo "Job completed successfully."
    else
        echo "Job failed or timed out."
    fi
}

# Main script execution
echo "Starting NAT instance..."
start_instance $NAT_INSTANCE_ID "NAT"

echo "Starting test instance..."
start_instance $TEST_INSTANCE_ID "Test"

echo "Testing NAT instance connectivity..."
test_nat_connectivity $TEST_INSTANCE_ID

echo "Submitting batch job..."
submit_batch_job

echo "Stopping test instance..."
stop_instance $TEST_INSTANCE_ID "Test"

echo "Stopping NAT instance..."
stop_instance $NAT_INSTANCE_ID "NAT"

echo "Script execution completed."