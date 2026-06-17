"""ECS Task Logs — Fetch CloudWatch logs for an ECS task."""

import boto3
from botocore.exceptions import ClientError


def ecs_task_logs(args: dict, region: str) -> dict:
    task_arn = args["task_arn"]
    lines = args.get("lines", 100)
    log_group = args.get("log_group", "/ecs/openant")

    task_id = task_arn.split("/")[-1]
    stream_name = f"agent/agent/{task_id}"

    client = boto3.client("logs", region_name=region)

    try:
        resp = client.get_log_events(
            logGroupName=log_group,
            logStreamName=stream_name,
            limit=lines,
            startFromHead=True,
        )
    except ClientError as e:
        if "ResourceNotFoundException" in str(e):
            # Try to find the stream
            streams = client.describe_log_streams(
                logGroupName=log_group,
                logStreamNamePrefix=f"agent/agent/{task_id[:8]}",
                limit=5,
            )
            names = [s["logStreamName"] for s in streams.get("logStreams", [])]
            return {"error": f"Stream '{stream_name}' not found", "available_streams": names}
        raise

    log_lines = []
    for event in resp.get("events", []):
        for line in event["message"].split("\t"):
            stripped = line.strip()
            if stripped:
                log_lines.append(stripped)

    return {
        "log_stream": stream_name,
        "lines": log_lines,
        "total_events": len(resp.get("events", [])),
    }
