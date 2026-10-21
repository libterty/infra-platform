# Python 3.14 is the newest generally available Lambda Python runtime (3.15 is in public preview as of 2026-10-21).
# The digest is the manifest list (linux/arm64 and linux/amd64) of the tag, read on 2026-10-21 from
# https://public.ecr.aws/v2/lambda/python/manifests/3.14 (sha256 of the response body). Bump tag and digest together.
FROM public.ecr.aws/lambda/python:3.14@sha256:252cbb0879717b1c049b9f909d86d06d88e129f3208386d7ba1189d535f5f981

# boto3 comes with the base image; the code uses only the standard library otherwise.
COPY breaker.py handler.py ${LAMBDA_TASK_ROOT}/

CMD ["handler.lambda_handler"]
