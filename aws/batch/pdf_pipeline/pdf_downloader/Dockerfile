# Use an official Python runtime as a parent image
FROM python:3.11

# Install necessary packages
RUN apt-get update && apt-get install -y poppler-utils

# Set the working directory
WORKDIR /app

# Copy the current directory contents into the container
COPY . /app

# Install any needed packages specified in requirements.txt
RUN pip3 install --no-cache-dir -r requirements.txt

# # Environment variables to be passed in via AWS job
# ENV BUCKET_NAME=my-bucket
# ENV QUEUE_URL=my-queue-url
# ENV DYNAMODB_TABLE=my-dynamodb-table

# Commented this out to let the AWS Batch job definition define the command
# # Run "./batch_processor.py" when the container launches
# # ENTRYPOINT ["python", "./batch_processor.py"]

