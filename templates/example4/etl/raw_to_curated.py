"""Sample Glue job of the example4 pipeline: raw JSON tables to curated Parquet tables.

The pipeline stack runs it from s3://<glue-assets>/scripts/raw_to_curated.py. CI uploads this file there; Terraform
does not upload objects. Arguments come from the job's default_arguments in pipeline/glue.tf.

For every table the daily raw crawler created in the raw database (GZIP JSON written by Firehose), the job reads only
the data the job bookmark has not processed yet, writes it as Parquet under the curated bucket and creates or updates
the matching table in the curated database. S3 events may start the workflow twice or not at all; the bookmark makes a
repeated run skip processed files and lets the next run pick up missed ones.
"""

import sys

import boto3
from awsglue.context import GlueContext
from awsglue.dynamicframe import DynamicFrame
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext

# The crawler names a table after the folder it crawls (raw/). The bi stack's dataset reads "events" from the curated
# database, so the raw table is renamed on the way. Tables not listed keep their name.
TARGET_TABLES = {"raw": "events"}

# Partition columns the crawler derives from Firehose's raw/yyyy/MM/dd/HH/ prefix.
PARTITION_COLUMNS = {"partition_0": "year", "partition_1": "month", "partition_2": "day", "partition_3": "hour"}


def raw_table_names(database):
    """Names of the tables in the raw database; the job role may read this database only."""
    paginator = boto3.client("glue").get_paginator("get_tables")
    return [t["Name"] for page in paginator.paginate(DatabaseName=database) for t in page["TableList"]]


def to_curated(glue_context, frame, table):
    """Rename the crawler's partition columns and return the frame and its partition keys."""
    df = frame.toDF()
    partition_keys = []
    for old, new in PARTITION_COLUMNS.items():
        if old in df.columns:
            df = df.withColumnRenamed(old, new)
            partition_keys.append(new)
    return DynamicFrame.fromDF(df, glue_context, f"curated_{table}"), partition_keys


def main():
    args = getResolvedOptions(sys.argv, ["JOB_NAME", "raw_database", "curated_database", "curated_path"])
    glue_context = GlueContext(SparkContext.getOrCreate())
    job = Job(glue_context)
    job.init(args["JOB_NAME"], args)

    for table in raw_table_names(args["raw_database"]):
        # transformation_ctx is the bookmark key: keep it stable, or the next run reprocesses everything.
        frame = glue_context.create_dynamic_frame.from_catalog(
            database=args["raw_database"],
            table_name=table,
            transformation_ctx=f"read_{table}",
        )
        if frame.toDF().isEmpty():
            continue

        target = TARGET_TABLES.get(table, table)
        curated, partition_keys = to_curated(glue_context, frame, table)
        sink = glue_context.getSink(
            connection_type="s3",
            path=f"{args['curated_path']}{target}/",
            enableUpdateCatalog=True,
            updateBehavior="UPDATE_IN_DATABASE",
            partitionKeys=partition_keys,
            transformation_ctx=f"write_{table}",
        )
        sink.setFormat("glueparquet")
        sink.setCatalogInfo(catalogDatabase=args["curated_database"], catalogTableName=target)
        sink.writeFrame(curated)

    # Saves the bookmark; a run that fails before this point is processed again next time.
    job.commit()


if __name__ == "__main__":
    main()
