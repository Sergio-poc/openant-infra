#!/usr/bin/env bash
set -euo pipefail

: "${GCS_BUCKET:?GCS_BUCKET required}"
: "${PROJECT_PATH:?PROJECT_PATH required}"
: "${RUN_ID:?RUN_ID required}"
: "${STAGE:=parse}"
: "${MODEL_ID:=claude-sonnet-4-20250514}"
: "${USE_VERTEX_AI:=1}"
: "${GCP_REGION:=europe-west1}"
: "${GCP_PROJECT:=}"

GCS_PREFIX="projects/${PROJECT_PATH}/${RUN_ID}"

echo "==> Job: ${PROJECT_PATH}/${RUN_ID} stage=${STAGE}"

# 1. Download source code
echo "==> Downloading input from gs://${GCS_BUCKET}/${GCS_PREFIX}/input/"
mkdir -p /work/input
gsutil -m -q rsync -r "gs://${GCS_BUCKET}/${GCS_PREFIX}/input/" /work/input/

# 2. If not parse, download previous step outputs
if [ "$STAGE" != "parse" ]; then
  echo "==> Downloading previous outputs"
  mkdir -p /work/output
  gsutil -m -q rsync -r -x "input/.*" "gs://${GCS_BUCKET}/${GCS_PREFIX}/" /work/output/
fi

# 3. Run the step
mkdir -p /work/output
echo "==> Running: python -m openant ${STAGE} (model=${MODEL_ID})"
cd /app
case "$STAGE" in
  parse)
    MODEL_ID="$MODEL_ID" python -m openant parse /work/input --output /work/output --level all || true
    ;;
  enhance)
    MODEL_ID="$MODEL_ID" python -m openant enhance /work/output/dataset.json --output /work/output --analyzer-output /work/output/analyzer_output.json || true
    ;;
  analyze)
    MODEL_ID="$MODEL_ID" python -m openant analyze /work/output/dataset.json --output /work/output --analyzer-output /work/output/analyzer_output.json || true
    ;;
  verify)
    MODEL_ID="$MODEL_ID" python -m openant verify /work/output/results.json --output /work/output --analyzer-output /work/output/analyzer_output.json --repo-path /work/input || true
    ;;
  build-output)
    MODEL_ID="$MODEL_ID" python -m openant build-output /work/output/results_verified.json --output /work/output/pipeline_output.json --repo-name "${PROJECT_PATH}" || true
    ;;
  *)
    echo "Unknown stage: $STAGE" && exit 1
    ;;
esac

# 4. Upload outputs
echo "==> Uploading results to gs://${GCS_BUCKET}/${GCS_PREFIX}/"
gsutil -m -q rsync -r /work/output/ "gs://${GCS_BUCKET}/${GCS_PREFIX}/"

echo "==> Done. Results at gs://${GCS_BUCKET}/${GCS_PREFIX}/"
