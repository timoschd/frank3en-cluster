# --- 1. macOS Management: Brew & Colima (Phase 1) ---
resource "null_resource" "mac_hardware_config" {
  count = var.nodes["mac-worker"].bootstrap_mode == "ssh" ? 1 : 0

  connection {
    type        = "ssh"
    user        = var.nodes["mac-worker"].ssh_user
    host        = var.nodes["mac-worker"].bootstrap_host
    port        = var.nodes["mac-worker"].ssh_port
    agent       = var.nodes["mac-worker"].ssh_auth == "key" ? var.use_ssh_agent : false
    private_key = var.nodes["mac-worker"].ssh_auth == "key" && !var.use_ssh_agent ? file(pathexpand(replace(var.nodes["mac-worker"].ssh_key_path != "" ? var.nodes["mac-worker"].ssh_key_path : var.default_ssh_key_path, "$HOME", "~"))) : null
    password    = var.nodes["mac-worker"].ssh_auth == "password" ? (var.nodes["mac-worker"].ssh_password != "" ? var.nodes["mac-worker"].ssh_password : var.default_ssh_password) : null
  }

  provisioner "remote-exec" {
    inline = [
      "if command -v colima >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then colima start --cpu ${var.nodes["mac-worker"].cpu} --memory ${var.nodes["mac-worker"].ram_gb} --disk 50 --kubernetes=false || true; brew services start colima; else echo 'Skipping mac_hardware_config on mac-worker: colima/brew not available'; fi"
    ]
  }
}

# --- 2. Tailscale Join Key ---
resource "tailscale_tailnet_key" "k3s_key" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  tags          = ["tag:k3s"]
}

locals {
  active_nodes = {
    for name, node in var.nodes : name => node
    if !(var.exclude_windows_worker && name == "windows-worker")
  }

  master_join_host = var.use_tailscale ? try(data.tailscale_device.node["pi-brain"].addresses[0], var.master_tailscale_ip) : var.nodes["pi-brain"].bootstrap_host

  remote_nodes = {
    for name, node in local.active_nodes : name => node
    if node.bootstrap_mode == "ssh"
  }

  k3s_remote_nodes = {
    for name, node in local.remote_nodes : name => node
    if name != "windows-worker"
  }

  tailscale_lookup_nodes = {
    for name, node in local.active_nodes : name => node
    if name != "mac-worker"
  }

  local_nodes = {
    for name, node in local.active_nodes : name => node
    if node.bootstrap_mode == "local"
  }
}

# --- 3. Node Information (Phase 2) ---
data "tailscale_device" "node" {
  for_each = local.tailscale_lookup_nodes
  name     = "${lookup(var.tailscale_device_names, each.key, each.key == "windows-worker" ? "windows-worker-wsl" : each.key)}.${var.tailnet_name}"
}

# --- 4. The Cluster Installation ---
resource "null_resource" "k3s_setup_remote" {
  for_each   = local.k3s_remote_nodes
  depends_on = [null_resource.mac_hardware_config]

  connection {
    type        = "ssh"
    user        = each.value.ssh_user
    host        = each.key == "mac-worker" ? each.value.bootstrap_host : (var.use_tailscale ? try(data.tailscale_device.node[each.key].addresses[0], each.value.bootstrap_host) : each.value.bootstrap_host)
    port        = each.value.ssh_port
    agent       = each.value.ssh_auth == "key" ? var.use_ssh_agent : false
    private_key = each.value.ssh_auth == "key" && !var.use_ssh_agent ? file(pathexpand(replace(each.value.ssh_key_path != "" ? each.value.ssh_key_path : var.default_ssh_key_path, "$HOME", "~"))) : null
    password    = each.value.ssh_auth == "password" ? (each.value.ssh_password != "" ? each.value.ssh_password : var.default_ssh_password) : null
  }

  provisioner "remote-exec" {
    inline = [
      each.key == "mac-worker" ? "echo 'Skipping host tailscale install for mac-worker (using Colima VM tailscale)'" : "curl -fsSL https://tailscale.com/install.sh | sh",
      each.key == "mac-worker" ? "echo 'Skipping host tailscale up for mac-worker (using Colima VM tailscale)'" : "sudo tailscale up --authkey=${tailscale_tailnet_key.k3s_key.key} --ssh --accept-routes",
      "sleep 5",

      # K3s Install: uses native Tailscale integration and manual hardware reserves
      each.value.is_master ?
      "curl -sfL https://get.k3s.io | sh -s - server --token=${var.k3s_token} --disable traefik --disable servicelb --vpn-auth='name=tailscale,joinKey=${tailscale_tailnet_key.k3s_key.key}' --node-ip=$(tailscale ip -4) --advertise-address=$(tailscale ip -4) --kubelet-arg='system-reserved=cpu=${each.value.res_cpu},memory=${each.value.res_ram}' ${join(" ", [for l in each.value.node_labels : "--node-label=${l}"])}" :

      each.key == "mac-worker" ?
      "if command -v colima >/dev/null 2>&1; then colima start --cpu ${each.value.cpu} --memory ${each.value.ram_gb} --disk 50 --kubernetes=false || true; colima ssh -- sudo sh -c 'curl -fsSL https://tailscale.com/install.sh | sh'; colima ssh -- sudo tailscale up --authkey=${tailscale_tailnet_key.k3s_key.key} --ssh --accept-routes; colima ssh -- sudo sh -c 'curl -sfL https://get.k3s.io | K3S_URL=https://${local.master_join_host}:6443 K3S_TOKEN=${var.k3s_token} sh -s - agent --node-name=${each.key} --node-ip=$(tailscale ip -4) --kubelet-arg=address=0.0.0.0 --kubelet-arg=system-reserved=cpu=${each.value.res_cpu},memory=${each.value.res_ram} ${join(" ", [for l in each.value.node_labels : "--node-label=${l}"])}'; else echo 'colima not available on mac-worker'; exit 1; fi" :

      "curl -sfL https://get.k3s.io | K3S_URL=https://${local.master_join_host}:6443 K3S_TOKEN=${var.k3s_token} sh -s - agent --vpn-auth='name=tailscale,joinKey=${tailscale_tailnet_key.k3s_key.key}' --node-ip=$(tailscale ip -4) --kubelet-arg='system-reserved=cpu=${each.value.res_cpu},memory=${each.value.res_ram}' ${join(" ", [for l in each.value.node_labels : "--node-label=${l}"])}"
    ]
  }
}

resource "null_resource" "windows_k3d_setup" {
  count = contains(keys(local.active_nodes), "windows-worker") ? 1 : 0

  connection {
    type        = "ssh"
    user        = var.nodes["windows-worker"].ssh_user
    host        = var.use_tailscale ? try(data.tailscale_device.node["windows-worker"].addresses[0], var.nodes["windows-worker"].bootstrap_host) : var.nodes["windows-worker"].bootstrap_host
    port        = var.nodes["windows-worker"].ssh_port
    agent       = var.nodes["windows-worker"].ssh_auth == "key" ? var.use_ssh_agent : false
    private_key = var.nodes["windows-worker"].ssh_auth == "key" && !var.use_ssh_agent ? file(pathexpand(replace(var.nodes["windows-worker"].ssh_key_path != "" ? var.nodes["windows-worker"].ssh_key_path : var.default_ssh_key_path, "$HOME", "~"))) : null
    password    = var.nodes["windows-worker"].ssh_auth == "password" ? (var.nodes["windows-worker"].ssh_password != "" ? var.nodes["windows-worker"].ssh_password : var.default_ssh_password) : null
  }

  provisioner "remote-exec" {
    inline = [
      "command -v tailscale >/dev/null 2>&1 || (curl -fsSL https://tailscale.com/install.sh | sh)",
      "SUDO_PASS='${var.nodes["windows-worker"].ssh_password != "" ? var.nodes["windows-worker"].ssh_password : var.default_ssh_password}'; echo \"$SUDO_PASS\" | sudo -S tailscale status >/dev/null 2>&1 || true",
      "SUDO_PASS='${var.nodes["windows-worker"].ssh_password != "" ? var.nodes["windows-worker"].ssh_password : var.default_ssh_password}'; echo \"$SUDO_PASS\" | sudo -S bash -c 'curl -sfL https://get.k3s.io | K3S_URL=https://${local.master_join_host}:6443 K3S_TOKEN=${var.k3s_token} sh -s - agent --node-name=windows-worker --node-ip=$(tailscale ip -4) ${join(" ", [for l in var.nodes["windows-worker"].node_labels : "--node-label=${l}"])} --kubelet-arg=system-reserved=cpu=${var.nodes["windows-worker"].res_cpu},memory=${var.nodes["windows-worker"].res_ram}'"
    ]
  }
}

resource "null_resource" "k3s_setup_local" {
  for_each   = local.local_nodes
  depends_on = [null_resource.mac_hardware_config]

  provisioner "local-exec" {
    command = each.value.is_master ? "curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --authkey=${tailscale_tailnet_key.k3s_key.key} --ssh --accept-routes && sleep 5 && curl -sfL https://get.k3s.io | sh -s - server --token=${var.k3s_token} --disable traefik --disable servicelb --vpn-auth='name=tailscale,joinKey=${tailscale_tailnet_key.k3s_key.key}' --node-ip=$(tailscale ip -4) --advertise-address=$(tailscale ip -4) --kubelet-arg='system-reserved=cpu=${each.value.res_cpu},memory=${each.value.res_ram}' ${join(" ", [for l in each.value.node_labels : "--node-label=${l}"])}" : "curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --authkey=${tailscale_tailnet_key.k3s_key.key} --ssh --accept-routes && sleep 5 && curl -sfL https://get.k3s.io | K3S_URL=https://${local.master_join_host}:6443 K3S_TOKEN=${var.k3s_token} sh -s - agent --vpn-auth='name=tailscale,joinKey=${tailscale_tailnet_key.k3s_key.key}' --node-ip=$(tailscale ip -4) --kubelet-arg='system-reserved=cpu=${each.value.res_cpu},memory=${each.value.res_ram}' ${join(" ", [for l in each.value.node_labels : "--node-label=${l}"])}"
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
curl -sfL https://get.k3s.io | K3S_URL=https://${local.master_join_host}:6443 K3S_TOKEN=${var.k3s_token} sh -s - agent --vpn-auth='name=tailscale,joinKey=${tailscale_tailnet_key.k3s_key.key}' --node-ip=$(tailscale ip -4)</string>
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
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
      set -euo pipefail
      ssh ${var.nodes["pi-brain"].ssh_user}@${local.master_join_host} 'sudo cat /etc/rancher/k3s/k3s.yaml' > ./k3s-config
      sed -i.bak 's/127.0.0.1/${local.master_join_host}/g' ./k3s-config
      rm -f ./k3s-config.bak
    EOT
  }
}
