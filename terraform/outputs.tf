output "tailscale_ips" {
  value       = { for k, v in var.nodes : k => try(data.tailscale_device.node[k].addresses[0], v.bootstrap_host) if !(var.exclude_windows_worker && k == "windows-worker") }
  description = "Resolved Tailscale IPv4 per node when available, otherwise bootstrap host fallback."
}
