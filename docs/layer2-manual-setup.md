# Layer 2: Kubernetes Platform Manual Setup

This guide covers manual installation of kubeadm-based Kubernetes cluster on OCI Always Free ARM instances.

Reference: [Kubernetes Official Docs](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/)

## Prerequisites

- 3 VMs running Ubuntu 24.04 ARM (control-plane + 2 workers)
- SSH access configured (`ssh oci-cp`, `ssh oci-worker-1`, `ssh oci-worker-2`)

---

## Step 1: Install Container Runtime (containerd)

**Run on ALL 3 nodes:**

```bash
# Load required kernel modules
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Configure sysctl for Kubernetes networking
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

# Install containerd
sudo apt-get update
sudo apt-get install -y containerd

# Generate default config and enable SystemdCgroup
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart and enable containerd
sudo systemctl restart containerd
sudo systemctl enable containerd

# Verify
sudo systemctl status containerd
```

---

## Step 2: Install kubeadm, kubelet, kubectl

**Run on ALL 3 nodes:**

```bash
# Install dependencies
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Add Kubernetes apt repository (v1.32)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Install kubeadm, kubelet, kubectl
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl

# Hold versions to prevent auto-upgrade
sudo apt-mark hold kubelet kubeadm kubectl

# Enable kubelet (it will wait for kubeadm init/join)
sudo systemctl enable kubelet

# Verify installation
kubeadm version
kubectl version --client
```

---

## Step 3: Initialize Control Plane

**Run on control-plane ONLY:**

```bash
# Initialize the cluster
# --pod-network-cidr is required for Flannel CNI
# --control-plane-endpoint uses private IP for internal communication
sudo kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --control-plane-endpoint=$(hostname -I | awk '{print $1}')

# Set up kubectl for current user
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify
kubectl get nodes
```

**IMPORTANT:** Save the `kubeadm join` command printed at the end! You'll need it for workers.

---

## Step 4: Remove Control Plane Taint

**Run on control-plane:**

By default, control plane doesn't run workloads. Remove the taint to allow scheduling (required for 3-node cluster):

```bash
kubectl taint nodes --all node-role.kubernetes.io/control-plane-
```

---

## Step 5: Install CNI (Flannel)

**Run on control-plane:**

```bash
# Install Flannel CNI
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml

# Wait for Flannel pods to be ready
kubectl get pods -n kube-flannel -w

# Verify node is Ready
kubectl get nodes
```

---

## Step 6: Join Worker Nodes

**Run on each worker node (oci-worker-1, oci-worker-2):**

Use the join command from Step 3 output. It looks like:

```bash
sudo kubeadm join <control-plane-ip>:6443 --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

If you lost the token, regenerate on control-plane:

```bash
kubeadm token create --print-join-command
```

**Verify on control-plane:**

```bash
kubectl get nodes
# Should show 3 nodes, all Ready
```

---

## Step 7: Install Ingress Controller (Nginx)

**Run on control-plane:**

```bash
# Install Nginx Ingress Controller
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.0/deploy/static/provider/baremetal/deploy.yaml

# Patch to use hostNetwork (required for NLB to reach pods)
kubectl patch deployment ingress-nginx-controller -n ingress-nginx \
  --type=json \
  -p='[{"op": "add", "path": "/spec/template/spec/hostNetwork", "value": true}]'

# Wait for deployment
kubectl get pods -n ingress-nginx -w

# Verify Ingress is listening on 80/443
kubectl get svc -n ingress-nginx
```

---

## Step 8: Install cert-manager

**Run on control-plane:**

```bash
# Install cert-manager
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.19.3/cert-manager.yaml

# Wait for cert-manager pods
kubectl get pods -n cert-manager -w

# Create Let's Encrypt ClusterIssuer (replace email)
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: YOUR_EMAIL@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: nginx
EOF
```

---

## Step 9: Install ArgoCD

**Run on control-plane:**

```bash
# Create namespace
kubectl create namespace argocd

# Install ArgoCD
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods
kubectl get pods -n argocd -w

# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo

# Optional: Install ArgoCD CLI via Homebrew
brew install argocd
```

---

## Step 10: Configure DNS

Point your domain to the NLB Reserved IP:

```bash
# Get the NLB public IP from Terraform
cd terraform && AWS_PROFILE=oci terraform output nlb_public_ip

# Then set DNS A records pointing to that IP:
# A record: your-domain.com -> <NLB-IP>
# A record: *.your-domain.com -> <NLB-IP>
```

---

## Verification Checklist

```bash
# All nodes ready
kubectl get nodes

# All system pods running
kubectl get pods -A

# Ingress controller ready
kubectl get pods -n ingress-nginx

# cert-manager ready
kubectl get pods -n cert-manager

# ArgoCD ready
kubectl get pods -n argocd
```

---

## Troubleshooting

### Node NotReady
```bash
kubectl describe node <node-name>
journalctl -u kubelet -f
```

### Pod stuck in Pending
```bash
kubectl describe pod <pod-name> -n <namespace>
```

### Reset and retry (nuclear option)
```bash
sudo kubeadm reset -f
sudo rm -rf /etc/cni/net.d
sudo rm -rf $HOME/.kube
```
