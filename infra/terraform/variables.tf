variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "project_name" {
  type    = string
  default = "openant"
}

variable "default_model_id" {
  type    = string
  default = "claude-sonnet-4-20250514"
}

variable "task_cpu" {
  type    = string
  default = "4"
}

variable "task_memory" {
  type    = string
  default = "8Gi"
}
