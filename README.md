# Self-managed ArgoCD Kubernetes Cluster Setup
Production-grade Kubernetes cluster setup using **Kubeadm + ArgoCD** for a **FastAPI + PostgreSQL CRUD** infrastructure with GitOps.

## Architecture Overview
- Control Plane: Single control plane node (can be scaled later)
- Workers: Auto Scaling Group (ASG) with Launch Template
- Networking: Flannel (CNI)
- Storage: AWS EBS CSI Driver
- GitOps: ArgoCD
- Secrets Management: AWS ECR + Kubernetes Secrets
- Monitoring: Metrics Server

## Prerequisite:
Before working on kubernetes, we have to prepare the initial infra. The **infra/Kubeadm** module prepares 2 instances. Go to the folder and use the command below to launch the Database and Master instance.
```bash
cd infra/Kubeadm
terraform apply --auto-approve
```
Both instances will have similar configuration except the fact that the database instances will be of higher specification. After 4-5 minutes, the initial setup of the instances will be done. The image of the worker instances can now be made from the master instance that will be used to create the template for the ASG. Apply the Script below as the user data that will pull the join yaml and do necessary configuration for the metrics server to work properly.
### Worker Node User Data Script (ASG Launch Template)
```bash
#!/bin/bash
set -ex

sleep 20

apt-get update -y

mkdir -p /opt/SocialMediaInfra
cd /opt/SocialMediaInfra

git init
git remote add origin https://github.com/artamim/SocialMediaInfra.git

git sparse-checkout init --cone
git sparse-checkout set WorkerSetup

git pull origin main

cd WorkerSetup
chmod +x config.sh
bash config.sh > /var/log/workersetup.log 2>&1
```

## 1. Control Plane Setup
Run the following commands on the Control Plane node:
```bash
sudo kubeadm init \
  --apiserver-advertise-address="$(hostname -I | awk '{print $1}')" \
  --pod-network-cidr=10.244.0.0/16 \
  --upload-certs

# Setup kubeconfig
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Flannel CNI
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Install Helm
sudo apt-get install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm -y

# Add Helm Repositories
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo add postfinance https://postfinance.github.io/kubelet-csr-approver
helm repo update

# Install AWS EBS CSI Driver
helm upgrade --install aws-ebs-csi-driver \
  aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --create-namespace

# Install kubelet-csr-approver
helm install kubelet-csr-approver postfinance/kubelet-csr-approver \
  --namespace kube-system \
  --set logLevel=info

# Create ECR Pull Secret
kubectl create secret docker-registry ecr-secret \
  --docker-server=364420385429.dkr.ecr.ap-south-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-south-1)

# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

# Install Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```
Running these sets of commands will generate the Control Plane join command. The command can be copied now or generated later.

## 2. Database Node Configuration
After joining the database worker node, run these commands on that node so that the database pods are only deployed to this node with the help of Tolerations and Node affinity:

```bash
kubectl label nodes <worker-node-name> workload=postgres
kubectl taint nodes <worker-node-name> postgres=true:NoSchedule
```

## 3. Worker Node Join
### Generate Join Command (on Control Plane)
```bash
kubeadm token create --print-join-command
```
### Join Configuration (join.yml)
Update the following file with the correct token and CA hash:
```bash
apiVersion: kubeadm.k8s.io/v1beta4
kind: JoinConfiguration

discovery:
  bootstrapToken:
    apiServerEndpoint: "<IP>:6443"
    token: "<Token>"
    caCertHashes:
      - "sha256:<SHA String>"
```

After updating join.yml and fastapi-deployment.yml (with correct image tag), push the changes to GitHub.
Then launch the Auto Scaling Group:
```bash
cd infra/ASG
terraform apply --auto-approve
```

## 4. ArgoCD Application
Apply this Application manifest on the Control Plane node. It tells ArgoCD to monitor the KubeadmSetup folder in your repository.
```bash
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: fastapi-argo-application
  namespace: argocd
spec:
  project: default

  source:
    repoURL: https://github.com/artamim/SocialMediaInfra.git
    targetRevision: HEAD
    path: KubeadmSetup
  destination: 
    server: https://kubernetes.default.svc
    namespace: myapp

  syncPolicy:
    syncOptions:
    - CreateNamespace=true

    automated:
      selfHeal: true
      prune: true
```

## 5. Post-Installation Commands
### Get ArgoCD Admin Password
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d
```
### Port Forward ArgoCD UI
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0
```
### Restart Fastapi Pod
```bash
kubectl rollout restart deployment fastapi-app -n default
```
### View Logs of Fastapi Pod
```bash
kubectl logs -l app=fastapi-app -n default --tail=50 -f
```

# Important Notes
- Secrets: Make sure postgres-secret and appuser-secret have matching credentials (especially the password).
- ECR Secret: The ECR pull secret expires after 12 hours. Consider implementing automatic rotation in production.