//fix ssh

import boto3
import json
import subprocess
import requests
import time
import os
import threading
import signal
import sys

QUEUE_URL = "*"

BACKEND_BASE_URL      = "https://bitlab.utej.me"
BACKEND_RESULT_URL    = f"{BACKEND_BASE_URL}/api/result"
BACKEND_HEARTBEAT_URL = f"{BACKEND_BASE_URL}/api/worker/qnx/heartbeat"
BACKEND_CONNECT_URL   = f"{BACKEND_BASE_URL}/api/worker/qnx/connect"
BACKEND_DISCONNECT_URL= f"{BACKEND_BASE_URL}/api/worker/qnx/disconnect"

WORK_DIR           = "/tmp/qnx_jobs"
HEARTBEAT_INTERVAL = 15   # seconds — also acts as crash-detection window on backend

os.makedirs(WORK_DIR, exist_ok=True)

sqs = boto3.client(
    "sqs",
    region_name="us-east-2",
    aws_access_key_id="*",
    aws_secret_access_key="*"
)


# ─────────────────────────────────────────────
# Signal: notify backend immediately on
# clean shutdown (Ctrl+C, kill, systemd stop)
# ─────────────────────────────────────────────

def on_shutdown(signum, frame):
    print("\n[worker] Shutting down — notifying backend...")
    try:
        requests.post(BACKEND_DISCONNECT_URL, timeout=5)
        print("[worker] Backend notified: OFFLINE")
    except Exception as e:
        print(f"[worker] Could not notify backend: {e}")
    sys.exit(0)

signal.signal(signal.SIGINT,  on_shutdown)
signal.signal(signal.SIGTERM, on_shutdown)


# ─────────────────────────────────────────────
# Heartbeat thread — periodic liveness ping
# (also covers crash/kill where on_shutdown
#  doesn't run — backend times out after 30s)
# ─────────────────────────────────────────────

def heartbeat_loop():
    while True:
        try:
            r = requests.post(BACKEND_HEARTBEAT_URL, timeout=5)
            print(f"[heartbeat] {r.status_code}")
        except Exception as e:
            print(f"[heartbeat] failed: {e}")
        time.sleep(HEARTBEAT_INTERVAL)

threading.Thread(target=heartbeat_loop, daemon=True).start()


# ─────────────────────────────────────────────
# QNX Execution
# ─────────────────────────────────────────────

def execute_qnx(code, job_id):
    file_path = f"{WORK_DIR}/{job_id}.c"
    with open(file_path, "w") as f:
        f.write(code)
    try:
        result = subprocess.run(
            ["/home/utej/backend/scripts/run_qnx.sh", file_path],
            capture_output=True, text=True, timeout=30
        )
        logs = result.stdout + "\n" + result.stderr
    except Exception as e:
        logs = str(e)
    return logs


# ─────────────────────────────────────────────
# Startup sequence
# ─────────────────────────────────────────────

print("Purging SQS queue before starting worker...")
try:
    sqs.purge_queue(QueueUrl=QUEUE_URL)
    print("Queue purge requested. Waiting for AWS to clear messages...")
    time.sleep(5)
except Exception as e:
    print("Queue purge failed:", e)

# Notify backend immediately that worker is ONLINE
try:
    requests.post(BACKEND_CONNECT_URL, timeout=5)
    print("[worker] Backend notified: ONLINE")
except Exception as e:
    print(f"[worker] Could not notify backend on startup: {e}")

print("Worker started. Waiting for jobs...")


# ─────────────────────────────────────────────
# Worker loop
# ─────────────────────────────────────────────

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

        msg  = messages[0]
        body = json.loads(msg["Body"])
        job_id = body["jobId"]
        code   = body["code"]

        print("Running job:", job_id)
        logs = execute_qnx(code, job_id)
        print("Execution finished")

        try:
            requests.post(BACKEND_RESULT_URL,
                          json={"jobId": job_id, "logs": logs}, timeout=10)
        except Exception as e:
            print("Failed sending result:", e)

        sqs.delete_message(QueueUrl=QUEUE_URL,
                           ReceiptHandle=msg["ReceiptHandle"])
        print("Job completed:", job_id)

    except Exception as e:
        print("Worker error:", e)

    time.sleep(1)
