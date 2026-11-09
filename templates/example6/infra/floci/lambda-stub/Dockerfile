# Test stub only (see app.py). The Lambda base image ships boto3; arm64 matches the function's architectures.
FROM --platform=linux/arm64 docker.io/amazon/aws-lambda-python:3.12
COPY app.py ${LAMBDA_TASK_ROOT}/
CMD ["app.handler"]
