# Run this block of code in the ControlPlane first.

```bash
sudo kubeadm init \
  --apiserver-advertise-address="$(hostname -I | awk '{print $1}')" \
  --pod-network-cidr=10.244.0.0/16 \
  --upload-certs
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
sudo apt-get install curl gpg apt-transport-https --yes
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get update
sudo apt-get install helm

# Add both repositories
helm repo add aws-ebs-csi-driver https://kubernetes-sigs.github.io/aws-ebs-csi-driver
helm repo add postfinance https://postfinance.github.io/kubelet-csr-approver

helm repo update

# Install/Upgrade EBS CSI Driver
helm upgrade --install aws-ebs-csi-driver \
  aws-ebs-csi-driver/aws-ebs-csi-driver \
  --namespace kube-system \
  --create-namespace

# Install kubelet-csr-approver
helm install kubelet-csr-approver postfinance/kubelet-csr-approver \
  --namespace kube-system \
  --set logLevel=info

kubectl create secret docker-registry ecr-secret \
  --docker-server=364420385429.dkr.ecr.ap-south-1.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ap-south-1)

kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl patch svc argocd-server -n argocd -p '{"spec": {"type": "LoadBalancer"}}'

kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

# Label and Taint the database node after joining it:

```bash
kubectl label nodes <worker> workload=postgres
kubectl taint nodes <worker> postgres=true:NoSchedule
```

# Update the token in SocialMediaInfra/NodeSetup/join.yml using the join token

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

# Launch worker nodes.

# Apply ArgoCD

```bash
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-argo-application
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





kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0


kubectl rollout restart deployment fastapi-app -n default
kubectl apply -f application.yml
kubectl logs -l app=fastapi-app -n default --tail=50



