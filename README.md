# 🚀 The Franken-Cluster: Multi-OS Mobile K3s

This repository automates the creation of a hybrid Kubernetes cluster spanning a **Raspberry Pi 4**, a **macOS machine (via Colima)**, and an **Ubuntu PC**. By leveraging **Tailscale**, the cluster remains connected securely even if the nodes move between different Wi-Fi networks (home, cafe, or transit).

## 🛠️ Key Features
* **Infrastructure as Code:** Powered by Terraform with Google Cloud Storage (GCS) for remote state management.
* **Hardware-Aware:** Custom resource reservations (6GB for Mac, 3GB for Ubuntu) to prevent OS crashes.
* **Zero-Config Networking:** Tailscale mesh allows nodes to find each other regardless of local IP changes.
* **Auto-Boot:** Mac nodes are configured via Homebrew to restart the K3s environment on system boot.

---

## 🏃 How to Run (4 Simple Steps)

Before starting, ensure your `.env` file is populated with your Tailscale API keys, Google Cloud credentials, and K3s tokens.

### 1. Initialize & Bootstrap (Phase 1)
Run this from your main machine while all nodes are on your **local home network**. This installs Tailscale and prepares the virtual hardware.
```bash
source .env
terraform init
terraform apply -var="use_tailscale=false"
```

### 2. Verify & Capture the "Brain's" IP
Once the first apply finishes, your nodes will appear in your Tailscale Admin Console.

1. Copy the Tailscale IP of your Raspberry Pi (`pi-brain`).
2. Update your `.env` file: `export TF_VAR_master_tailscale_ip="100.x.y.z"`.

### 3. Enable Travel Mode (Phase 2)
Flip the switch to transition the cluster to its permanent, encrypted Tailscale tunnel.

```bash
source .env
terraform apply -var="use_tailscale=true"
```

### 4. Take Control
Terraform will automatically pull the kubeconfig from the Pi and swap the internal IPs for you. To manage your cluster from anywhere in the world:

```bash
export KUBECONFIG=$(pwd)/k3s-config
kubectl get nodes -o wide
```
