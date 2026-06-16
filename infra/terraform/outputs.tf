output "bucket_name" {
  value = aws_s3_bucket.data.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.agent.repository_url
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.main.name
}

output "task_definition_arn" {
  value = aws_ecs_task_definition.agent.arn
}

output "subnet_id" {
  value = data.aws_subnets.public.ids[0]
}

output "security_group_id" {
  value = data.aws_security_group.default.id
}
