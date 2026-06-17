#!/usr/bin/env bash
set -euo pipefail

: "${S3_BUCKET:?S3_BUCKET required}"
: "${PROJECT_PATH:?PROJECT_PATH required}"
: "${RUN_ID:?RUN_ID required}"
: "${STAGE:=parse}"
: "${MODEL_ID:=claude-sonnet-4-20250514}"
: "${USE_BEDROCK:=1}"
: "${AWS_REGION:=eu-west-1}"

S3_PREFIX="projects/${PROJECT_PATH}/${RUN_ID}"

echo "==> Job: ${PROJECT_PATH}/${RUN_ID} stage=${STAGE}"

# 1. Download source code
echo "==> Downloading input from s3://${S3_BUCKET}/${S3_PREFIX}/input/"
mkdir -p /work/input
aws s3 sync "s3://${S3_BUCKET}/${S3_PREFIX}/input/" /work/input/ --quiet

# 2. If not parse, download previous step outputs
if [ "$STAGE" != "parse" ]; then
  echo "==> Downloading previous outputs"
  mkdir -p /work/output
  aws s3 sync "s3://${S3_BUCKET}/${S3_PREFIX}/" /work/output/ \
    --exclude "input/*" --quiet
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
echo "==> Uploading results to s3://${S3_BUCKET}/${S3_PREFIX}/"
aws s3 sync /work/output/ "s3://${S3_BUCKET}/${S3_PREFIX}/" --quiet

echo "==> Done. Results at s3://${S3_BUCKET}/${S3_PREFIX}/"
