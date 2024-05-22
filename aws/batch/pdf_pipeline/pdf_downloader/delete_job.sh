#!/bin/bash

set -e

# Define your environment variables


# Function to deregister all job definitions
deregister_job_definitions() {
    job_definitions=$(aws batch describe-job-definitions --status ACTIVE --region $REGION --profile $PROFILE --query 'jobDefinitions[*].jobDefinitionArn' --output text)
    for job_definition in $job_definitions; do
        echo "Deregistering job definition: $job_definition"
        aws batch deregister-job-definition --job-definition $job_definition --region $REGION --profile $PROFILE || echo "Failed to deregister $job_definition"
    done
}

# Function to disable and delete job queue
delete_job_queue() {
    echo "Disabling job queue: $JOB_QUEUE_NAME"
    aws batch update-job-queue --job-queue $JOB_QUEUE_NAME --state DISABLED --region $REGION --profile $PROFILE || echo "Failed to disable job queue $JOB_QUEUE_NAME"

    echo "Waiting for job queue to be disabled..."
    while : ; do
        state=$(aws batch describe-job-queues --job-queues $JOB_QUEUE_NAME --region $REGION --profile $PROFILE --query 'jobQueues[0].state' --output text)
        if [[ $state == "DISABLED" ]]; then
            break
        fi
        echo "Job queue still disabling, waiting..."
        sleep 10
    done

    echo "Deleting job queue: $JOB_QUEUE_NAME"
    while : ; do
        aws batch delete-job-queue --job-queue $JOB_QUEUE_NAME --region $REGION --profile $PROFILE && break
        echo "Retrying deletion of job queue $JOB_QUEUE_NAME..."
        sleep 10
    done
}

# Function to disable and delete compute environment
delete_compute_environment() {
    echo "Disabling compute environment: $COMPUTE_ENV_NAME"
    aws batch update-compute-environment --compute-environment $COMPUTE_ENV_NAME --state DISABLED --region $REGION --profile $PROFILE || echo "Failed to disable compute environment $COMPUTE_ENV_NAME"

    echo "Waiting for compute environment to be disabled..."
    while : ; do
        state=$(aws batch describe-compute-environments --compute-environments $COMPUTE_ENV_NAME --region $REGION --profile $PROFILE --query 'computeEnvironments[0].state' --output text)
        if [[ $state == "DISABLED" ]]; then
            break
        fi
        echo "Compute environment still disabling, waiting..."
        sleep 10
    done

    echo "Deleting compute environment: $COMPUTE_ENV_NAME"
    while : ; do
        aws batch delete-compute-environment --compute-environment $COMPUTE_ENV_NAME --region $REGION --profile $PROFILE && break
        echo "Retrying deletion of compute environment $COMPUTE_ENV_NAME..."
        sleep 10
    done
}

# Deregister job definitions
deregister_job_definitions

# Disable and delete job queue
# delete_job_queue

# Disable and delete compute environment
delete_compute_environment

