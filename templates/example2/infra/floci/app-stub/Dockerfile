# Test stub only (see app.py), pushed as both the api and the worker image. arm64 matches the task definitions.
FROM --platform=linux/arm64 docker.io/library/python:3.12-slim
# scramp 1.5 dropped a function pg8000 1.31 calls, so it stays at the oldest version pg8000 accepts.
RUN pip install --no-cache-dir boto3==1.40.61 pg8000==1.31.5 scramp==1.4.5 redis==6.4.0
COPY app.py /app/app.py
CMD ["python", "/app/app.py"]
