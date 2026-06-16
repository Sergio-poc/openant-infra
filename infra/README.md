# OpenAnt — ECS Fargate Infrastructure

Déploiement du pipeline OpenAnt (`parse → enhance → analyze → verify → build-output → report`) sur AWS ECS Fargate avec output S3 par step et exécution indépendante de chaque étape.

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────────┐
│  run.sh     │────▶│  ECS Fargate │────▶│  S3 Bucket      │
│  (local)    │     │  (task)      │     │  results/step   │
└─────────────┘     └──────┬───────┘     └─────────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  Bedrock /   │
                    │  Vertex AI   │
                    └──────────────┘
```

### Structure S3

```
s3://<bucket>/projects/<org>/<repo>/<run-id>/
├── input/              # Code source uploadé
├── parse/              # Résultats du parsing
├── enhance/            # Contexte enrichi
├── analyze/            # Vulnérabilités détectées
├── verify/             # Vérification attaquant (Stage 2)
├── build-output/       # pipeline_output.json
└── report/             # Rapport final
```

## Prérequis

- AWS CLI configuré
- Terraform >= 1.5
- Docker
- Accès à Amazon Bedrock (modèles Claude activés dans la région)

## Déploiement

```bash
# 1. Provisionner l'infra
cd infra/terraform
terraform init
terraform apply

# 2. Build et push de l'image Docker
./infra/scripts/build-and-push.sh
```

## Usage

### Lancer un scan complet (step par step)

```bash
# Parse (upload le code + lance le parsing)
./infra/scripts/run.sh --project myorg/myrepo --code ./path/to/code --stage parse

# Enhance (ajoute le contexte de sécurité via LLM)
./infra/scripts/run.sh --project myorg/myrepo --stage enhance

# Analyze (détection de vulnérabilités — Stage 1)
./infra/scripts/run.sh --project myorg/myrepo --stage analyze

# Verify (simulation d'attaque — Stage 2)
./infra/scripts/run.sh --project myorg/myrepo --stage verify

# Build output (génère pipeline_output.json)
./infra/scripts/run.sh --project myorg/myrepo --stage build-output

# Report (rapport final)
./infra/scripts/run.sh --project myorg/myrepo --stage report
```

### Reprendre depuis un run spécifique

```bash
./infra/scripts/run.sh --project myorg/myrepo --stage verify --from-run run-20260616T120000-abcd1234
```

### Télécharger les résultats

```bash
# Attend la fin du task + download
./infra/scripts/download.sh --project myorg/myrepo --run-id run-20260616T120000-abcd1234

# Avec task ARN (skip la recherche)
./infra/scripts/download.sh --project myorg/myrepo --run-id run-xxx --task-arn arn:aws:ecs:...
```

### Suivre les logs

```bash
aws logs tail /ecs/openant --follow
```

## Configuration LLM

Le client LLM supporte 3 backends via variables d'environnement :

| Backend | Env vars | Auth |
|---------|----------|------|
| **Bedrock** (défaut) | `USE_BEDROCK=1`, `AWS_REGION` | IAM role du task ECS |
| **Vertex AI** | `USE_VERTEX=1`, `VERTEX_REGION`, `VERTEX_PROJECT_ID` | Service account GCP |
| **API directe** | `ANTHROPIC_API_KEY` | Clé API |

Pour changer de modèle :

```bash
./infra/scripts/run.sh --project myorg/myrepo --stage analyze --model claude-opus-4-20250514
```

## Structure du projet

```
infra/
├── docker/
│   ├── Dockerfile          # Image Python 3.11 + AWS CLI + openant-core
│   └── entrypoint.sh       # Orchestration : S3 sync → run step → upload
├── terraform/
│   ├── providers.tf
│   ├── variables.tf        # region, model, cpu/memory
│   ├── main.tf             # S3, ECR, ECS, IAM (Bedrock + S3)
│   └── outputs.tf
└── scripts/
    ├── run.sh              # Lance un step sur ECS Fargate
    ├── download.sh         # Attend + télécharge les résultats
    └── build-and-push.sh   # Build image → push ECR
```

## Variables Terraform

| Variable | Défaut | Description |
|----------|--------|-------------|
| `aws_region` | `eu-west-1` | Région AWS |
| `project_name` | `openant` | Préfixe des ressources |
| `default_model_id` | `claude-sonnet-4-20250514` | Modèle par défaut |
| `task_cpu` | `4096` | CPU du task (vCPU × 1024) |
| `task_memory` | `8192` | Mémoire du task (MB) |
