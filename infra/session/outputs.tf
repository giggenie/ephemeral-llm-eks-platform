output "cluster_name" {
  value = aws_eks_cluster.session.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.session.endpoint
}

output "artifacts_bucket" {
  value = data.terraform_remote_state.foundation.outputs.artifacts_bucket
}

output "ecr_repository_url" {
  value = data.terraform_remote_state.foundation.outputs.ecr_repository_url
}

output "model_role_arn" {
  value = aws_iam_role.model.arn
}
