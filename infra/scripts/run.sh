#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --project <org/repo> [options]

Launch an OpenAnt pipeline step on Cloud Run.

Options:
  --project    Project path org/repo (required)
  --code       Path to source code directory (required for parse)
  --stage      Pipeline step: parse|enhance|analyze|verify|build-output|report (default: parse)
  --pipeline   Comma-separated stages to run sequentially (e.g. parse,enhance,analyze,verify)
  --from-run   Previous run ID to resume from (default: latest)
  --model      Model ID (default: claude-sonnet-4-20250514)
  --region     GCP region (default: europe-west1)
  --help       Show this help
EOF
  exit 0
}

PROJECT="" CODE_PATH="" STAGE="parse" FROM_RUN="" MODEL="" REGION="europe-west1" PIPELINE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --project) PROJECT="$2"; shift 2;;
    --code) CODE_PATH="$2"; shift 2;;
    --stage) STAGE="$2"; shift 2;;
    --pipeline) PIPELINE="$2"; shift 2;;
    --from-run) FROM_RUN="$2"; shift 2;;
    --model) MODEL="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --help) usage;;
    *) echo "Unknown option: $1"; usage;;
  esac
done

[[ -z "$PROJECT" ]] && { echo "Error: --project required"; usage; }
[[ -z "$CODE_PATH" && "$STAGE" == "parse" && -z "$PIPELINE" ]] && { echo "Error: --code required for parse stage"; usage; }

# Resolve Terraform outputs
INFRA_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
BUCKET=$(terraform -chdir="$INFRA_DIR" output -raw bucket_name)
SERVICE_URL=$(terraform -chdir="$INFRA_DIR" output -raw cloud_run_service_url)

RUN_ID="run-$(date +%Y%m%dT%H%M%S)-$(openssl rand -hex 4)"

# --- Helper: run a single stage ---
run_stage() {
  local STAGE_NAME="$1"
  local STAGE_RUN_ID="$2"
  local STAGE_FROM_RUN="$3"
  local STAGE_START=$(date +%s)

  # Find latest run if needed
  if [[ "$STAGE_NAME" != "parse" && -z "$STAGE_FROM_RUN" ]]; then
    STAGE_FROM_RUN=$(gsutil ls "gs://${BUCKET}/projects/${PROJECT}/" 2>/dev/null | \
      grep -o 'run-[^/]*' | sort | tail -1)
    [[ -z "$STAGE_FROM_RUN" ]] && { echo "Error: no previous run found."; return 1; }
  fi

  # Upload code if parse and code_path provided
  if [[ "$STAGE_NAME" == "parse" && -n "$CODE_PATH" ]]; then
    echo "==> Uploading code to gs://${BUCKET}/projects/${PROJECT}/${STAGE_RUN_ID}/input/"
    gsutil -m -q rsync -r "$CODE_PATH" "gs://${BUCKET}/projects/${PROJECT}/${STAGE_RUN_ID}/input/"
  fi

  # Copy previous outputs
  if [[ -n "$STAGE_FROM_RUN" && "$STAGE_FROM_RUN" != "$STAGE_RUN_ID" ]]; then
    echo "==> Copying previous outputs from ${STAGE_FROM_RUN} to ${STAGE_RUN_ID}"
    gsutil -m -q rsync -r -x "input/.*" \
      "gs://${BUCKET}/projects/${PROJECT}/${STAGE_FROM_RUN}/" \
      "gs://${BUCKET}/projects/${PROJECT}/${STAGE_RUN_ID}/"
  fi

  echo "==> Launching Cloud Run job (project=${PROJECT}, run=${STAGE_RUN_ID}, stage=${STAGE_NAME})"

  local ENV_VARS="PROJECT_PATH=${PROJECT},RUN_ID=${STAGE_RUN_ID},STAGE=${STAGE_NAME},GCS_BUCKET=${BUCKET}"
  [[ -n "$MODEL" ]] && ENV_VARS="${ENV_VARS},MODEL_ID=${MODEL}"

  # Invoke Cloud Run service
  local RESPONSE
  RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${SERVICE_URL}" \
    -H "Authorization: Bearer $(gcloud auth print-identity-token)" \
    -H "Content-Type: application/json" \
    -d "{\"project_path\":\"${PROJECT}\",\"run_id\":\"${STAGE_RUN_ID}\",\"stage\":\"${STAGE_NAME}\",\"model_id\":\"${MODEL:-}\"}")

  local HTTP_CODE=$(echo "$RESPONSE" | tail -1)
  local BODY=$(echo "$RESPONSE" | sed '$d')

  local STAGE_END=$(date +%s)
  local DURATION=$((STAGE_END - STAGE_START))

  if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
    echo "==> ${STAGE_NAME}: success (HTTP ${HTTP_CODE}) duration=${DURATION}s"
    return 0
  else
    echo "==> ${STAGE_NAME}: failed (HTTP ${HTTP_CODE}) duration=${DURATION}s"
    echo "    Response: ${BODY}"
    return 1
  fi
}

# --- Pipeline mode ---
if [[ -n "$PIPELINE" ]]; then
  IFS=',' read -ra STAGES <<< "$PIPELINE"
  CURRENT_RUN="$RUN_ID"
  PIPELINE_START=$(date +%s)
  echo "==> Pipeline: ${PIPELINE} (run=${CURRENT_RUN})"
  echo ""

  for PSTAGE in "${STAGES[@]}"; do
    run_stage "$PSTAGE" "$CURRENT_RUN" "$FROM_RUN" || {
      echo ""
      echo "❌ Pipeline failed at stage: ${PSTAGE}"
      echo "==> Results so far: gs://${BUCKET}/projects/${PROJECT}/${CURRENT_RUN}/"
      exit 1
    }
    FROM_RUN="$CURRENT_RUN"
    echo ""
  done

  PIPELINE_END=$(date +%s)
  echo "✅ Pipeline complete in $((PIPELINE_END - PIPELINE_START))s"
  echo "==> Run ID: ${CURRENT_RUN}"
  echo "==> Results: gs://${BUCKET}/projects/${PROJECT}/${CURRENT_RUN}/"
  exit 0
fi

# --- Single stage mode ---
if [[ "$STAGE" != "parse" && -z "$FROM_RUN" ]]; then
  echo "==> Finding latest run for project: ${PROJECT}"
  FROM_RUN=$(gsutil ls "gs://${BUCKET}/projects/${PROJECT}/" 2>/dev/null | \
    grep -o 'run-[^/]*' | sort | tail -1)
  if [[ -z "$FROM_RUN" ]]; then
    echo "Error: no previous run found. Run parse first."
    exit 1
  fi
  echo "==> Using from-run: ${FROM_RUN}"
fi

run_stage "$STAGE" "$RUN_ID" "$FROM_RUN"

echo ""
echo "==> Run ID: ${RUN_ID}"
echo "==> Results: gs://${BUCKET}/projects/${PROJECT}/${RUN_ID}/"
echo "==> Logs: gcloud logging read 'resource.type=cloud_run_revision' --limit 50"
