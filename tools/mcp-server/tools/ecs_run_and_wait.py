"""ECS Run and Wait — Launch a Fargate task and wait for completion."""

import json
import os
import subprocess
import time
import secrets
from datetime import datetime, timezone

import boto3


def ecs_run_and_wait(args: dict, infra: dict, region: str) -> dict:
    project = args["project"]
    stage = args["stage"]
    code_path = args.get("code_path")
    from_run = args.get("from_run")
    model = args.get("model")
    timeout = args.get("timeout", 600)

    bucket = infra["bucket"]
    cluster = infra["cluster"]
    task_def = infra["task_def"]
    subnet = infra["subnet"]
    sg = infra["sg"]

    run_id = f"run-{datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S')}-{secrets.token_hex(4)}"

    s3 = boto3.client("s3", region_name=region)
    ecs = boto3.client("ecs", region_name=region)

    # Find latest run if needed
    if stage != "parse" and not from_run:
        resp = s3.list_objects_v2(Bucket=bucket, Prefix=f"projects/{project}/", Delimiter="/")
        prefixes = sorted(
            p["Prefix"].rstrip("/").split("/")[-1]
            for p in resp.get("CommonPrefixes", [])
            if "run-" in p["Prefix"]
        )
        if not prefixes:
            return {"error": "No previous run found. Run parse first."}
        from_run = prefixes[-1]

    # Upload code
    if code_path:
        subprocess.run(
            ["aws", "s3", "sync", code_path, f"s3://{bucket}/projects/{project}/{run_id}/input/", "--quiet", "--region", region],
            check=True,
        )

    # Copy previous outputs
    if from_run and from_run != run_id:
        subprocess.run(
            ["aws", "s3", "sync", f"s3://{bucket}/projects/{project}/{from_run}/", f"s3://{bucket}/projects/{project}/{run_id}/", "--exclude", "input/*", "--quiet", "--region", region],
            check=True,
        )

    # Build overrides
    env_vars = [
        {"name": "PROJECT_PATH", "value": project},
        {"name": "RUN_ID", "value": run_id},
        {"name": "STAGE", "value": stage},
    ]
    if model:
        env_vars.append({"name": "MODEL_ID", "value": model})

    overrides = {"containerOverrides": [{"name": "agent", "environment": env_vars}]}

    # Launch
    start = time.time()
    resp = ecs.run_task(
        cluster=cluster,
        taskDefinition=task_def,
        launchType="FARGATE",
        networkConfiguration={"awsvpcConfiguration": {"subnets": [subnet], "securityGroups": [sg], "assignPublicIp": "ENABLED"}},
        overrides=overrides,
    )
    task_arn = resp["tasks"][0]["taskArn"]

    # Wait
    waiter = ecs.get_waiter("tasks_stopped")
    waiter.wait(cluster=cluster, tasks=[task_arn], WaiterConfig={"MaxAttempts": timeout // 6})

    duration = int(time.time() - start)

    # Get exit code
    desc = ecs.describe_tasks(cluster=cluster, tasks=[task_arn])
    exit_code = desc["tasks"][0]["containers"][0].get("exitCode")
    stopped_reason = desc["tasks"][0].get("stoppedReason", "")

    return {
        "task_arn": task_arn,
        "run_id": run_id,
        "project": project,
        "stage": stage,
        "exit_code": exit_code,
        "duration_seconds": duration,
        "s3_results": f"s3://{bucket}/projects/{project}/{run_id}/",
        "stopped_reason": stopped_reason,
        "success": exit_code == 0,
    }
