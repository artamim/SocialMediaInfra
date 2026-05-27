output "iam_role_name" {
  value = aws_iam_role.kube_nodes.name
}

output "iam_instance_profile_name" {
  value = aws_iam_instance_profile.kube_nodes.name
}

output "iam_role_arn" {
  value = aws_iam_role.kube_nodes.arn
}