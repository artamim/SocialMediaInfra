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

# ==================== Existing Resources ====================
data "aws_vpc" "default" {
  default = true
}

data "aws_security_group" "allow_all_demo" {
  name   = "allow-all-traffic"
  vpc_id = data.aws_vpc.default.id
}

data "aws_ssm_parameter" "ubuntu_2404_ami" {
  name = "/aws/service/canonical/ubuntu/server/noble/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# Reference the IAM Instance Profile created in the first step
data "aws_iam_instance_profile" "kube_nodes" {
  name = "kube-nodes-instance-profile"
}

# ==================== EC2 Instances ====================
resource "aws_instance" "kube" {
  count = 2

  ami           = data.aws_ssm_parameter.ubuntu_2404_ami.value
  instance_type = count.index == 1 ? "c7i-flex.large" : "t3.small"

  associate_public_ip_address = true
  key_name                    = "redhat"

  vpc_security_group_ids = [data.aws_security_group.allow_all_demo.id]
  iam_instance_profile   = data.aws_iam_instance_profile.kube_nodes.name

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
  }

    user_data = <<-EOF
      #!/bin/bash
      set -ex
      sleep 30

      apt-get update -y
      apt-get install -y apt-transport-https ca-certificates curl gnupg unzip

      # Kubernetes repo
      curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
      echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list

      apt-get update -y
      apt-get install -y kubelet kubeadm kubectl
      apt-mark hold kubelet kubeadm kubectl

      # Containerd setup
      apt-get remove -y containerd || true
      wget -q https://github.com/containerd/containerd/releases/download/v2.2.2/containerd-2.2.2-linux-amd64.tar.gz
      tar Cxzvf /usr/local containerd-2.2.2-linux-amd64.tar.gz
      rm containerd-2.2.2-linux-amd64.tar.gz

      wget -q https://github.com/opencontainers/runc/releases/download/v1.2.4/runc.amd64 -O /usr/local/bin/runc
      chmod +x /usr/local/bin/runc

      mkdir -p /etc/containerd
      containerd config default | tee /etc/containerd/config.toml >/dev/null
      sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

      curl -L https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -o /etc/systemd/system/containerd.service
      systemctl daemon-reload
      systemctl enable --now containerd

      # Kernel modules + sysctl
      cat <<EOT | tee /etc/modules-load.d/k8s.conf >/dev/null
      overlay
      br_netfilter
      EOT

      cat <<EOT | tee /etc/sysctl.d/k8s.conf >/dev/null
      net.bridge.bridge-nf-call-iptables = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward = 1
      EOT

      modprobe overlay || true
      modprobe br_netfilter || true
      sysctl --system

      swapoff -a
      sed -i '/ swap / s/^/#/' /etc/fstab

      # Enable Kubelet TLS Bootstrap for Metrics Server
      cat <<EOKUBE | sudo tee -a /var/lib/kubelet/config.yaml >/dev/null
      serverTLSBootstrap: true
      EOKUBE

      sudo systemctl restart kubelet

      echo "Bootstrap completed at $(date)" > /var/log/kube-bootstrap.log
      apt-get install -y vim

      # AWS CLI
      curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
      unzip awscliv2.zip
      sudo ./aws/install
      rm awscliv2.zip
    EOF

  tags = {
    Name = count.index == 0 ? "Master" : (
      count.index == 1 ? "Database" : "Slave-${count.index - 1}"
    )
    Environment = "Staging"
    Project     = "Kubeadm"
    Role        = count.index == 0 ? "master" : "worker"
  }
}