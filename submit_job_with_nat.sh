#!/bin/bash

# Load environment variables from .env file
export $(grep -v '^#' start.env | xargs)

start_nat_instance() {
    instance_state=$(aws ec2 describe-instances --instance-ids $NAT_INSTANCE_ID --region $REGION --profile $PROFILE --query 'Reservations[*].Instances[*].State.Name' --output text)
    
    if [ "$instance_state" != "running" ]; then
        aws ec2 start-instances --instance-ids $NAT_INSTANCE_ID --region $REGION --profile $PROFILE
        echo "Starting NAT instance: $NAT_INSTANCE_ID"
        
        # Wait for the instance to be in 'running' state
        aws ec2 wait instance-running --instance-ids $NAT_INSTANCE_ID --region $REGION --profile $PROFILE
        echo "NAT instance is running."
    else
        echo "NAT instance is already running."
    fi
    
    # Wait for the instance to be in 'status ok' state
    aws ec2 wait instance-status-ok --instance-ids $NAT_INSTANCE_ID --region $REGION --profile $PROFILE
    echo "NAT instance is initialized and ready."
}

stop_nat_instance() {
    aws ec2 stop-instances --instance-ids $NAT_INSTANCE_ID --region $REGION --profile $PROFILE
    echo "Stopping NAT instance: $NAT_INSTANCE_ID"
    
    # Wait for the instance to be in 'stopped' state
    aws ec2 wait instance-stopped --instance-ids $NAT_INSTANCE_ID --region $REGION --profile $PROFILE
    echo "NAT instance is stopped."
}

submit_batch_job() {
    # Get the latest job definition ARN
    JOB_DEFINITION_ARN=$(aws batch describe-job-definitions \
        --job-definition-name $BATCH_JOB_NAME \
        --status ACTIVE \
        --region $REGION \
        --profile $PROFILE \
        --query 'jobDefinitions[?status==`ACTIVE`]|[0].jobDefinitionArn' \
        --output text)
    
    echo "Latest Job Definition ARN: $JOB_DEFINITION_ARN"
    
    # Submit the job
    JOB_ID=$(aws batch submit-job \
        --job-name $BATCH_JOB_NAME \
        --job-queue $JOB_QUEUE \
        --job-definition $JOB_DEFINITION_ARN \
        --region $REGION \
        --profile $PROFILE \
        --query 'jobId' \
        --output text)
    
    echo "Job submitted successfully. Job ID: $JOB_ID"
    
    # Wait for the job to complete with timeout
    echo "Waiting for the job to complete with a timeout of $JOB_TIMEOUT seconds."
    elapsed_time=0
    while [ $elapsed_time -lt $JOB_TIMEOUT ]; do
        job_status=$(aws batch describe-jobs --jobs $JOB_ID --region $REGION --profile $PROFILE --query 'jobs[0].status' --output text)
        if [[ "$job_status" == "SUCCEEDED" || "$job_status" == "FAILED" ]]; then
            break
        fi
        sleep $CHECK_INTERVAL
        elapsed_time=$((elapsed_time + CHECK_INTERVAL))
    done
    
    if [ "$job_status" == "SUCCEEDED" ]; then
        echo "Job completed successfully."
    else
        echo "Job failed or timed out."
    fi
}

# Main script execution
start_nat_instance

submit_batch_job

stop_nat_instance
