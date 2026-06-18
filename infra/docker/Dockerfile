FROM --platform=linux/amd64 python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl build-essential && \
    curl -sSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir=/opt && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

ENV PATH="/opt/google-cloud-sdk/bin:${PATH}"

COPY libs/openant-core/ /app/
COPY config/ /config/
WORKDIR /app
RUN pip install --no-cache-dir -r requirements.txt && pip install --no-cache-dir -e .

WORKDIR /work
COPY infra/docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
