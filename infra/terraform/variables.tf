variable "aws_region" {
  type    = string
  default = "eu-west-1"
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
  type    = number
  default = 4096
}

variable "task_memory" {
  type    = number
  default = 8192
}
