# OpenAnt MCP Tools

MCP server exposing 4 tools for Claude to interact with the OpenAnt ECS/Bedrock/S3 infrastructure.

## Setup

```bash
pip install -r tools/mcp-server/requirements.txt
```

Auto-loaded via `.kiro/settings/mcp.json` when using Kiro CLI.

## Tools

### ecs_run_and_wait

Launch an ECS Fargate task and wait for completion.

```json
{"project": "vuln/buffer-overflow", "stage": "analyze", "from_run": "run-xxx"}
```

Returns: `{task_arn, run_id, exit_code, duration_seconds, s3_results, success}`

### bedrock_model_check

Test Bedrock model availability.

```json
{"model_ids": ["eu.anthropic.claude-sonnet-4-5-20250929-v1:0", "eu.anthropic.claude-opus-4-8"]}
```

Returns: `[{model_id, status: "ok"|"legacy"|"access_denied"|"error"}]`

### ecs_task_logs

Fetch CloudWatch logs for an ECS task.

```json
{"task_arn": "arn:aws:ecs:eu-west-1:123:task/openant/abc123", "lines": 50}
```

Returns: `{log_stream, lines: [...], total_events}`

### s3_project_results

List or fetch project results from S3.

```json
{"project": "vuln/buffer-overflow", "run_id": "latest", "filter": "*.report.json"}
```

Returns: `{run_id, files: [{path, content}]}`

## Script Adaptations

### run.sh --pipeline

Run full pipeline in one command:

```bash
./infra/scripts/run.sh --project vuln/buffer-overflow --code ./src --pipeline parse,enhance,analyze,verify
```

### build-and-push.sh --json

Get structured output from build:

```bash
./infra/scripts/build-and-push.sh --json
# {"success":true,"ecr_url":"...","digest":"sha256:...","duration_seconds":45}
```
