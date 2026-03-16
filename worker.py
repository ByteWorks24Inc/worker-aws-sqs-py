import boto3
import json
import subprocess
import requests
import time
import os

QUEUE_URL = "*"

BACKEND_RESULT_URL = "http://*:8080/api/result"

WORK_DIR = "/tmp/qnx_jobs"

os.makedirs(WORK_DIR, exist_ok=True)

sqs = boto3.client(
    "sqs",
    region_name="us-east-2",
    aws_access_key_id="*",
    aws_secret_access_key="*"
)


def execute_qnx(code, job_id):

    file_path = f"{WORK_DIR}/{job_id}.c"

    with open(file_path, "w") as f:
        f.write(code)

    try:
        result = subprocess.run(
            ["/home/utej/backend/scripts/run_qnx.sh", file_path],
            capture_output=True,
            text=True,
            timeout=30
        )

        logs = result.stdout + "\n" + result.stderr

    except Exception as e:
        logs = str(e)

    return logs


# -----------------------------
# PURGE QUEUE BEFORE STARTING
# -----------------------------

print("Purging SQS queue before starting worker...")

try:
    sqs.purge_queue(QueueUrl=QUEUE_URL)
    print("Queue purge requested. Waiting for AWS to clear messages...")
    time.sleep(5)
except Exception as e:
    print("Queue purge failed:", e)

print("Worker started. Waiting for jobs...")


# -----------------------------
# WORKER LOOP
# -----------------------------

while True:

    try:

        response = sqs.receive_message(
            QueueUrl=QUEUE_URL,
            MaxNumberOfMessages=1,
            WaitTimeSeconds=10
        )

        messages = response.get("Messages", [])

        if not messages:
            continue

        msg = messages[0]

        body = json.loads(msg["Body"])

        job_id = body["jobId"]
        code = body["code"]

        print("Running job:", job_id)

        logs = execute_qnx(code, job_id)

        print("Execution finished")

        try:
            requests.post(
                BACKEND_RESULT_URL,
                json={
                    "jobId": job_id,
                    "logs": logs
                },
                timeout=10
            )
        except Exception as e:
            print("Failed sending result:", e)

        sqs.delete_message(
            QueueUrl=QUEUE_URL,
            ReceiptHandle=msg["ReceiptHandle"]
        )

        print("Job completed:", job_id)

    except Exception as e:
        print("Worker error:", e)

    time.sleep(1)
