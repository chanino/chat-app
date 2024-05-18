FROM public.ecr.aws/lambda/python:3.9

RUN yum update -y &&     yum install -y poppler-utils

COPY requirements.txt ${LAMBDA_TASK_ROOT}/requirements.txt
RUN pip3.9 install -r ${LAMBDA_TASK_ROOT}/requirements.txt

# Copy function code
COPY app.py ${LAMBDA_TASK_ROOT}
COPY pdf2png.py ${LAMBDA_TASK_ROOT}

# Set the CMD to your handler
CMD [ "app.lambda_handler" ]

