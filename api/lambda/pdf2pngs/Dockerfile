FROM public.ecr.aws/lambda/python:3.11

# Install necessary packages
RUN yum update -y && yum install -y poppler-utils

# Copy application code
COPY lambda_function.py ${LAMBDA_TASK_ROOT}
COPY pdf2png.py ${LAMBDA_TASK_ROOT}
COPY requirements.txt ${LAMBDA_TASK_ROOT}

# Install Python dependencies
RUN pip3.11 install --no-cache-dir -r ${LAMBDA_TASK_ROOT}/requirements.txt

# Set the CMD to your handler
CMD ["lambda_function.lambda_handler"]
