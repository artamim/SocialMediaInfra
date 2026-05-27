output "master_ip" {
  description = "Public IP of the master node"
  value       = aws_instance.kube[0].public_ip
}

output "instance_ids" {
  value = aws_instance.kube[*].id
}

output "instance_public_ips" {
  value = aws_instance.kube[*].public_ip
}