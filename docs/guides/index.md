# Setup Guides

從零到可運作的 K8s 叢集，依 layer 順序操作。

## Layer 1: Infrastructure (Terraform)

Terraform 自動化，不需手動操作。詳見 [CLAUDE.md](../../CLAUDE.md) 的 Commands 段落。

```bash
cd terraform/bootstrap && terraform init && terraform apply   # 一次性：建立 tfstate bucket
cd terraform && tf-oci init && tf-oci plan && tf-oci apply    # 主要基礎設施
```

## Layer 2: Kubernetes Platform

cloud-init 自動安裝基礎環境（containerd, kubeadm），接著手動執行腳本初始化叢集。

**快速流程：**
1. `terraform apply` 後等 cloud-init 完成（~10-15 分鐘）：`ssh ubuntu@<ip> 'cat /tmp/cloud-init-done'`
2. Control Plane：`./init-control-plane.sh`
3. 取得 join command：`sudo kubeadm token create --print-join-command`
4. Workers：`./join-cluster.sh <kubeadm-join-command>`
5. ArgoCD Ingress（DNS 設定後）：`./setup-argocd-ingress.sh <domain>`

**完整手動步驟紀錄：** [logging/layer2-manual-setup.md](logging/layer2-manual-setup.md)

## Layer 3: GitOps (ArgoCD)

ArgoCD App-of-Apps pattern，從 private `k8s-apps` repo 自動同步。

**關鍵步驟：**
1. 建立 private `k8s-apps` repo
2. 在 CP 上產生 SSH deploy key → 加到 GitHub Deploy Keys
3. 建立 ArgoCD repo Secret（帶 SSH key）
4. Apply 根 Application（app-of-apps）— 唯一的手動操作
5. 之後新增 app：`apps/<name>/` 放 manifests + `argocd/<name>.yaml` 放 Application → `git push`

**完整操作紀錄：** [logging/layer3-setup-log.md](logging/layer3-setup-log.md)

## Identity & SSO

PocketID (self-hosted OIDC) → OCI Console SSO，使用者首次登入會自動 JIT-provision 進 `PocketID-Users` 群組。

**完整操作紀錄：** [pocketid-oci-sso.md](pocketid-oci-sso.md)
