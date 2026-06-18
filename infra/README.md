# OpenAnt — Cloud Run Infrastructure (GCP)

Deploys the OpenAnt pipeline (`parse → enhance → analyze → verify → build-output → report`) on GCP Cloud Run with GCS storage per step and Vertex AI for LLM calls.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│  run.sh     │────▶│  Cloud Run   │────▶│  GCS Bucket     │
│  (local)    │     │  (service)   │     │  results/step   │
└─────────────┘     └──────┬───────┘     └─────────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  Vertex AI   │
                    │  (Claude)    │
                    └──────────────┘
```

### GCS layout

```
gs://<bucket>/projects/<org>/<repo>/<run-id>/
├── input/              # Uploaded source code
├── parse/              # Parsing results
├── enhance/            # Enriched security context
├── analyze/            # Detected vulnerabilities
├── verify/             # Attacker verification (Stage 2)
├── build-output/       # pipeline_output.json
└── report/             # Final report
```

## Prerequisites

- `gcloud` CLI configured (`gcloud auth login` + `gcloud auth application-default login`)
- Terraform >= 1.5
- Docker
- Vertex AI enabled on the GCP project (Claude models available)

## Deployment

```bash
# 1. Provision infrastructure
cd infra/terraform
terraform init
terraform apply -var="project_id=<your-gcp-project>"

# 2. Build and push the Docker image
./infra/scripts/build-and-push.sh
```

## Usage

### Run a full scan (step by step)

```bash
# Parse (uploads code + runs parsing)
./infra/scripts/run.sh --project myorg/myrepo --code ./path/to/code --stage parse

# Enhance (adds security context via LLM)
./infra/scripts/run.sh --project myorg/myrepo --stage enhance

# Analyze (vulnerability detection — Stage 1)
./infra/scripts/run.sh --project myorg/myrepo --stage analyze

# Verify (attack simulation — Stage 2)
./infra/scripts/run.sh --project myorg/myrepo --stage verify

# Build output (generates pipeline_output.json)
./infra/scripts/run.sh --project myorg/myrepo --stage build-output

# Report (final report)
./infra/scripts/run.sh --project myorg/myrepo --stage report
```

### Multi-stage pipeline

```bash
./infra/scripts/run.sh --project myorg/myrepo --code ./path/to/code \
  --pipeline parse,enhance,analyze,verify
```

### Resume from a specific run

```bash
./infra/scripts/run.sh --project myorg/myrepo --stage verify --from-run run-20260616T120000-abcd1234
```

### Download results

```bash
./infra/scripts/download.sh --project myorg/myrepo --run-id run-20260616T120000-abcd1234
```

### View logs

```bash
gcloud logging read "resource.type=cloud_run_job AND resource.labels.job_name=openant-agent" --limit 50 --format="value(textPayload)"
```

## LLM configuration

The LLM client supports 3 backends via environment variables:

| Backend | Env vars | Auth |
|---------|----------|------|
| **Vertex AI** (default) | `USE_VERTEX_AI=1`, `GCP_REGION`, `GCP_PROJECT` | GCP service account |
| **Bedrock** | `USE_BEDROCK=1`, `AWS_REGION` | IAM role |
| **Direct API** | `ANTHROPIC_API_KEY` | API key |

To change the model:

```bash
./infra/scripts/run.sh --project myorg/myrepo --stage analyze --model claude-opus-4-20250514
```

## Project structure

```
infra/
├── docker/
│   ├── Dockerfile          # Python 3.11 + gcloud CLI + openant-core
│   └── entrypoint.sh       # Orchestration: GCS sync → run step → upload
├── terraform/
│   ├── providers.tf        # Google provider
│   ├── variables.tf        # project_id, region, model, cpu/memory
│   ├── main.tf             # GCS, Artifact Registry, Cloud Run, IAM (Vertex AI + GCS)
│   └── outputs.tf
└── scripts/
    ├── run.sh              # Launches a step on Cloud Run
    ├── download.sh         # Downloads results from GCS
    └── build-and-push.sh   # Builds image → pushes to Artifact Registry
```

## Terraform variables

| Variable | Default | Description |
|----------|---------|-------------|
| `project_id` | — | GCP project ID (required) |
| `region` | `europe-west1` | GCP region |
| `project_name` | `openant` | Resource name prefix |
| `default_model_id` | `claude-sonnet-4-20250514` | Default model |
| `task_cpu` | `4` | CPU (vCPUs) |
| `task_memory` | `8Gi` | Memory |
