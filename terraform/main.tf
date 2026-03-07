# --- 1. macOS Management: Brew & Colima ---
resource "null_resource" "mac_hardware_config" {
  count = var.use_tailscale ? 0 : 1

  provisioner "local-exec" {
    command = <<EOT
      # Start Colima with explicit specs from variables
      colima start --cpu ${var.nodes["mac-worker"].cpu} --memory ${var.nodes["mac-worker"].ram_gb} --disk 50 --kubernetes=false
      # Ensure Colima restarts on system boot
      brew services start colima
    EOT
  }
}

# --- 2. Tailscale Join Key ---
resource "tailscale_tailnet_key" "k3s_key" {
  reusable      = true
  preauthorized = true
  tags          = ["tag:k3s"]
}

# --- 3. Node Information (Phase 2) ---
data "tailscale_device" "node" {
  for_each = var.use_tailscale ? var.nodes : {}
  name     = "${each.key}.${var.tailnet_name}"
}

# --- 4. The Cluster Installation ---
resource "null_resource" "k3s_setup" {
  for_each   = var.nodes
  depends_on = [null_resource.mac_hardware_config]

  connection {
    type        = "ssh"
    user        = var.ssh_user
    private_key = file(var.ssh_key_path)
    host        = var.use_tailscale ? data.tailscale_device.node[each.key].addresses[0] : each.value.local_ip
  }

  provisioner "remote-exec" {
    inline = [
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "sudo tailscale up --authkey=${tailscale_tailnet_key.k3s_key.key} --ssh --accept-routes",
      "sleep 5",

      # K3s Install: uses native Tailscale integration and manual hardware reserves
      each.value.is_master ?
      "curl -sfL https://get.k3s.io | sh -s - server --token=${var.k3s_token} --disable traefik --disable servicelb --vpn-auth='name=tailscale,joinKey=${tailscale_tailnet_key.k3s_key.key}' --node-ip=$(tailscale ip -4) --advertise-address=$(tailscale ip -4) --kubelet-arg='system-reserved=cpu=${each.value.res_cpu},memory=${each.value.res_ram}'" :

      "curl -sfL https://get.k3s.io | K3S_URL=https://${var.master_tailscale_ip}:6443 K3S_TOKEN=${var.k3s_token} sh -s - agent --vpn-auth='name=tailscale,joinKey=${tailscale_tailnet_key.k3s_key.key}' --node-ip=$(tailscale ip -4) --kubelet-arg='system-reserved=cpu=${each.value.res_cpu},memory=${each.value.res_ram}'"
    ]
  }
}

# --- 5. Automated Kubeconfig Bridge ---
resource "null_resource" "get_kubeconfig" {
  depends_on = [null_resource.k3s_setup]
  count      = var.use_tailscale ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      scp ${var.ssh_user}@${var.master_tailscale_ip}:/etc/rancher/k3s/k3s.yaml ./k3s-config
      sed -i '' 's/127.0.0.1/${var.master_tailscale_ip}/g' ./k3s-config
    EOT
  }
}
