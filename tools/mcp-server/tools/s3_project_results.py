"""S3 Project Results — List/fetch project scan results from S3."""

import json
import fnmatch
import subprocess

import boto3


def s3_project_results(args: dict, infra: dict, region: str) -> dict:
    project = args["project"]
    run_id = args.get("run_id", "latest")
    file_filter = args.get("filter")
    download_to = args.get("download_to")

    bucket = infra["bucket"]
    s3 = boto3.client("s3", region_name=region)
    prefix = f"projects/{project}/"

    # List runs
    def _list_runs():
        resp = s3.list_objects_v2(Bucket=bucket, Prefix=prefix, Delimiter="/")
        return sorted(
            p["Prefix"].rstrip("/").split("/")[-1]
            for p in resp.get("CommonPrefixes", [])
            if "run-" in p["Prefix"]
        )

    if run_id == "list":
        return {"runs": _list_runs()}

    if run_id == "latest":
        runs = _list_runs()
        if not runs:
            return {"error": "No runs found"}
        run_id = runs[-1]

    # List files in run
    run_prefix = f"{prefix}{run_id}/"
    paginator = s3.get_paginator("list_objects_v2")
    files = []
    for page in paginator.paginate(Bucket=bucket, Prefix=run_prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            rel = key[len(run_prefix):]
            if rel.startswith("input/"):
                continue
            files.append({"key": key, "path": rel, "size": obj["Size"]})

    # Apply filter
    if file_filter:
        files = [f for f in files if fnmatch.fnmatch(f["path"], file_filter)]

    # Download mode
    if download_to:
        subprocess.run(
            ["aws", "s3", "sync", f"s3://{bucket}/{run_prefix}", download_to, "--exclude", "input/*", "--quiet", "--region", region],
            check=True,
        )
        return {"run_id": run_id, "downloaded": len(files), "path": download_to}

    # Inline mode — return file contents (< 100KB each)
    result_files = []
    for f in files:
        if f["size"] > 100_000:
            result_files.append({"path": f["path"], "content": f"<too large: {f['size']} bytes>"})
            continue
        obj = s3.get_object(Bucket=bucket, Key=f["key"])
        raw = obj["Body"].read().decode("utf-8")
        try:
            content = json.loads(raw)
        except json.JSONDecodeError:
            content = raw
        result_files.append({"path": f["path"], "content": content})

    return {"run_id": run_id, "files": result_files}
