#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 --project <org/repo> --run-id <id> [options]

Download results from GCS.

Options:
  --project    Project path org/repo (required)
  --run-id     Run ID (required)
  --help       Show this help
EOF
  exit 0
}

PROJECT="" RUN_ID=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --project) PROJECT="$2"; shift 2;;
    --run-id) RUN_ID="$2"; shift 2;;
    --help) usage;;
    *) echo "Unknown option: $1"; usage;;
  esac
done

[[ -z "$PROJECT" ]] && { echo "Error: --project required"; usage; }
[[ -z "$RUN_ID" ]] && { echo "Error: --run-id required"; usage; }

INFRA_DIR="$(cd "$(dirname "$0")/../terraform" && pwd)"
BUCKET=$(terraform -chdir="$INFRA_DIR" output -raw bucket_name)

# Download
DEST="./results/${PROJECT}/${RUN_ID}"
echo "==> Downloading gs://${BUCKET}/projects/${PROJECT}/${RUN_ID}/ → ${DEST}/"
mkdir -p "$DEST"
gsutil -m rsync -r -x "input/.*" "gs://${BUCKET}/projects/${PROJECT}/${RUN_ID}/" "$DEST/"

echo "==> Download complete: ${DEST}/"
