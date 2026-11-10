# Test stub only (see app.py), pushed as both the import-extract and the import-load image.
FROM --platform=linux/arm64 docker.io/amazon/aws-lambda-python:3.12
COPY app.py ${LAMBDA_TASK_ROOT}/
CMD ["app.handler"]
