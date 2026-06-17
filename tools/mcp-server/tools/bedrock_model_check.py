"""Bedrock Model Check — Test model invokability."""

import json
import boto3
from botocore.exceptions import ClientError


def bedrock_model_check(args: dict, region: str) -> list:
    model_ids = args["model_ids"]
    region = args.get("region", region)
    client = boto3.client("bedrock-runtime", region_name=region)

    payload = json.dumps({
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": 1,
        "messages": [{"role": "user", "content": "hi"}],
    }).encode()

    results = []
    for model_id in model_ids:
        try:
            client.invoke_model(modelId=model_id, body=payload, contentType="application/json", accept="application/json")
            results.append({"model_id": model_id, "status": "ok"})
        except ClientError as e:
            code = e.response["Error"]["Code"]
            msg = e.response["Error"]["Message"]
            if "Legacy" in msg or code == "ResourceNotFoundException":
                status = "legacy"
            elif "AccessDenied" in code or "403" in str(e.response.get("ResponseMetadata", {}).get("HTTPStatusCode")):
                status = "access_denied"
            elif code == "ValidationException":
                status = "invalid_model_id"
            else:
                status = "error"
            results.append({"model_id": model_id, "status": status, "error": msg})

    return results
