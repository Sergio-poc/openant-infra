#!/usr/bin/env python3
"""OpenAnt MCP Server — exposes ECS/Bedrock/S3 tools for Claude."""

import os
import subprocess
import functools

from mcp.server import Server
from mcp.server.stdio import stdio_server
from mcp.types import Tool, TextContent

from tools.ecs_run_and_wait import ecs_run_and_wait
from tools.bedrock_model_check import bedrock_model_check
from tools.ecs_task_logs import ecs_task_logs
from tools.s3_project_results import s3_project_results

server = Server("openant-tools")

REGION = os.environ.get("AWS_REGION", "eu-west-1")
INFRA_DIR = os.environ.get("INFRA_DIR", os.path.join(os.path.dirname(__file__), "..", "..", "infra", "terraform"))


@functools.lru_cache()
def get_infra():
    """Resolve terraform outputs once."""
    def _out(name):
        return subprocess.check_output(
            ["terraform", f"-chdir={INFRA_DIR}", "output", "-raw", name],
            text=True
        ).strip()
    return {
        "bucket": _out("bucket_name"),
        "cluster": _out("ecs_cluster_name"),
        "task_def": _out("task_definition_arn"),
        "subnet": _out("subnet_id"),
        "sg": _out("security_group_id"),
    }


@server.list_tools()
async def list_tools():
    return [
        Tool(
            name="ecs_run_and_wait",
            description="Launch an OpenAnt ECS Fargate task and wait for completion. Returns task status, run_id, and S3 results path.",
            inputSchema={
                "type": "object",
                "properties": {
                    "project": {"type": "string", "description": "Project path (org/repo)"},
                    "stage": {"type": "string", "enum": ["parse", "enhance", "analyze", "verify", "build-output"]},
                    "code_path": {"type": "string", "description": "Local source code path (required for parse)"},
                    "from_run": {"type": "string", "description": "Previous run ID to resume from"},
                    "model": {"type": "string", "description": "Model ID override"},
                    "timeout": {"type": "integer", "description": "Max wait seconds", "default": 600},
                },
                "required": ["project", "stage"],
            },
        ),
        Tool(
            name="bedrock_model_check",
            description="Test Bedrock model availability. Checks if model IDs are invokable and reports status (ok/legacy/access_denied/error).",
            inputSchema={
                "type": "object",
                "properties": {
                    "model_ids": {"type": "array", "items": {"type": "string"}, "description": "List of Bedrock model IDs to test"},
                    "region": {"type": "string", "default": "eu-west-1"},
                },
                "required": ["model_ids"],
            },
        ),
        Tool(
            name="ecs_task_logs",
            description="Fetch CloudWatch logs for an ECS task. Resolves log stream automatically from task ARN.",
            inputSchema={
                "type": "object",
                "properties": {
                    "task_arn": {"type": "string", "description": "ECS task ARN"},
                    "lines": {"type": "integer", "default": 100, "description": "Number of log lines to fetch"},
                    "log_group": {"type": "string", "default": "/ecs/openant"},
                },
                "required": ["task_arn"],
            },
        ),
        Tool(
            name="s3_project_results",
            description="List or fetch OpenAnt project results from S3. Can list runs, fetch reports, or download files.",
            inputSchema={
                "type": "object",
                "properties": {
                    "project": {"type": "string", "description": "Project path (org/repo)"},
                    "run_id": {"type": "string", "description": "'latest', 'list', or specific run-id", "default": "latest"},
                    "filter": {"type": "string", "description": "Glob pattern (e.g. '*.report.json')"},
                    "download_to": {"type": "string", "description": "Local directory to download results to"},
                },
                "required": ["project"],
            },
        ),
    ]


@server.call_tool()
async def call_tool(name: str, arguments: dict):
    infra = get_infra()
    region = arguments.get("region", REGION)

    if name == "ecs_run_and_wait":
        result = ecs_run_and_wait(arguments, infra, region)
    elif name == "bedrock_model_check":
        result = bedrock_model_check(arguments, region)
    elif name == "ecs_task_logs":
        result = ecs_task_logs(arguments, region)
    elif name == "s3_project_results":
        result = s3_project_results(arguments, infra, region)
    else:
        result = {"error": f"Unknown tool: {name}"}

    import json
    return [TextContent(type="text", text=json.dumps(result, indent=2))]


async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
