# --- 1. macOS Management: Brew & Colima (Phase 1) ---
resource "null_resource" "mac_hardware_config" {
  count = var.use_tailscale ? 0 : 1

  provisioner "local-exec" {
    command = <<EOT
      if command -v colima >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
        # Start Colima with explicit specs from variables
        colima start --cpu ${var.nodes["mac-worker"].cpu} --memory ${var.nodes["mac-worker"].ram_gb} --disk 50 --kubernetes=false

        # Ensure Colima restarts on system boot
        brew services start colima
      else
        echo "Skipping mac_hardware_config: colima/brew not available on this host"
      fi
    EOT
  }
}

# --- 2. Tailscale Join Key ---
resource "tailscale_tailnet_key" "k3s_key" {
  reusable      = true
  preauthorized = true
  tags          = ["tag:k3s"]
}

locals {
  active_nodes = {
    for name, node in var.nodes : name => node
    if !(var.exclude_windows_worker && name == "windows-worker")
  }

  remote_nodes = {
    for name, node in local.active_nodes : name => node
    if node.bootstrap_mode == "ssh"
  }

  local_nodes = {
    for name, node in local.active_nodes : name => node
    if node.bootstrap_mode == "local"
  }
}

# --- 3. Node Information (Phase 2) ---
data "tailscale_device" "node" {
  for_each = var.use_tailscale ? local.active_nodes : {}
  name     = "${each.key}.${var.tailnet_name}"
}

# --- 4. The Cluster Installation ---
resource "null_resource" "k3s_setup_remote" {
  for_each   = local.remote_nodes
  depends_on = [null_resource.mac_hardware_config]

  connection {
    type        = "ssh"
    user        = each.value.ssh_user
    host        = var.use_tailscale ? data.tailscale_device.node[each.key].addresses[0] : each.value.bootstrap_host
    port        = each.value.ssh_port
    private_key = each.value.ssh_auth == "key" ? file(each.value.ssh_key_path != "" ? each.value.ssh_key_path : var.default_ssh_key_path) : null
    password    = each.value.ssh_auth == "password" ? (each.value.ssh_password != "" ? each.value.ssh_password : var.default_ssh_password) : null
  }

  provisioner "remote-exec" {
    inline = [
      "curl -fsSL https://tailscale.com/install.sh | sh",
      "sudo tailscale up --authkey=${tailscale_tailnet_key.k3s_key.key} --ssh --accept-routes",
      "sleep 5",

      # K3s Install: uses native Tailscale integration and manual hardware reserves
      each.value.is_master ?
      "curl -sfL https://get.k3s.io | sh -s - server --token=${var.k3s_token} --disable traefik --disable servicelb --vpn-auth='name=tailscale,joinKey=${tailscale_tailnet_key.k3s_key.key}' --node-ip=$(tailscale ip -4) --advertise-address=$(tailscale ip -4) --kubelet-arg='system-reserved=cpu=${each.value.res_cpu},memory=${each.value.res_ram}' ${join(" ", [for l in each.value.node_labels : "--node-label=${l}"])}" :

      "curl -sfL https://get.k3s.io | K3S_URL=https://${var.master_tailscale_ip}:6443 K3S_TOKEN=${var.k3s_token} sh -s - agent --vpn-auth='name=tailscale,joinKey=${tailscale_tailnet_key.k3s_key.key}' --node-ip=$(tailscale ip -4) --kubelet-arg='system-reserved=cpu=${each.value.res_cpu},memory=${each.value.res_ram}' ${join(" ", [for l in each.value.node_labels : "--node-label=${l}"])}"
    ]
  }
}

resource "null_resource" "k3s_setup_local" {
  for_each   = local.local_nodes
  depends_on = [null_resource.mac_hardware_config]

  provisioner "local-exec" {
    command = each.value.is_master ? "curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --authkey=${tailscale_tailnet_key.k3s_key.key} --ssh --accept-routes && sleep 5 && curl -sfL https://get.k3s.io | sh -s - server --token=${var.k3s_token} --disable traefik --disable servicelb --vpn-auth='name=tailscale,joinKey=${tailscale_tailnet_key.k3s_key.key}' --node-ip=$(tailscale ip -4) --advertise-address=$(tailscale ip -4) --kubelet-arg='system-reserved=cpu=${each.value.res_cpu},memory=${each.value.res_ram}' ${join(" ", [for l in each.value.node_labels : "--node-label=${l}"])}" : "curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --authkey=${tailscale_tailnet_key.k3s_key.key} --ssh --accept-routes && sleep 5 && curl -sfL https://get.k3s.io | K3S_URL=https://${var.master_tailscale_ip}:6443 K3S_TOKEN=${var.k3s_token} sh -s - agent --vpn-auth='name=tailscale,joinKey=${tailscale_tailnet_key.k3s_key.key}' --node-ip=$(tailscale ip -4) --kubelet-arg='system-reserved=cpu=${each.value.res_cpu},memory=${each.value.res_ram}' ${join(" ", [for l in each.value.node_labels : "--node-label=${l}"])}"
  }
}

# --- 5. Mac Auto-Restart Setup (Phase 2) ---
# This runs after we have the master's Tailscale IP
resource "null_resource" "mac_k3s_autostart" {
  count      = var.use_tailscale ? 1 : 0
  depends_on = [null_resource.k3s_setup_remote, null_resource.k3s_setup_local]

  provisioner "local-exec" {
    command = <<EOT
      if command -v launchctl >/dev/null 2>&1; then
      # Create LaunchAgent plist for K3s auto-restart on Mac boot
      cat > ~/Library/LaunchAgents/com.franken.k3s.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>com.franken.k3s</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>-c</string>
      <string>
sleep 30
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey=${tailscale_tailnet_key.k3s_key.key} --ssh --accept-routes
sleep 5
curl -sfL https://get.k3s.io | K3S_URL=https://${var.master_tailscale_ip}:6443 K3S_TOKEN=${var.k3s_token} sh -s - agent --vpn-auth='name=tailscale,joinKey=${tailscale_tailnet_key.k3s_key.key}' --node-ip=$(tailscale ip -4)</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StartInterval</key>
    <integer>300</integer>
    <key>StandardOutPath</key>
    <string>/tmp/com.franken.k3s.out</string>
    <key>StandardErrorPath</key>
    <string>/tmp/com.franken.k3s.err</string>
  </dict>
</plist>
PLIST

      # Unload if already loaded (to refresh)
      launchctl unload ~/Library/LaunchAgents/com.franken.k3s.plist 2>/dev/null || true
      # Load the new plist
      launchctl load ~/Library/LaunchAgents/com.franken.k3s.plist
      else
        echo "Skipping mac_k3s_autostart: launchctl not available on this host"
      fi
    EOT
  }
}

# --- 6. Automated Kubeconfig Bridge ---
resource "null_resource" "get_kubeconfig" {
  depends_on = [null_resource.k3s_setup_remote, null_resource.k3s_setup_local]
  count      = var.use_tailscale ? 1 : 0

  provisioner "local-exec" {
    command = <<EOT
      scp ${var.nodes["pi-brain"].ssh_user}@${var.master_tailscale_ip}:/etc/rancher/k3s/k3s.yaml ./k3s-config
      sed -i.bak 's/127.0.0.1/${var.master_tailscale_ip}/g' ./k3s-config
      rm -f ./k3s-config.bak
    EOT
  }
}
