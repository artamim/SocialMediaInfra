terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-south-1"
}

# ==================== IAM Role for K8s Nodes ====================
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "kube_nodes" {
  name = "kube-nodes-role"

  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Environment = "Staging"
    Project     = "Kubeadm"
  }
}

# Attach required policies
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.kube_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.kube_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.kube_nodes.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "kube_nodes" {
  name = "kube-nodes-instance-profile"
  role = aws_iam_role.kube_nodes.name
}