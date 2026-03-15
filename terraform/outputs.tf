output "tailscale_ips" {
  value       = { for k, v in var.nodes : k => v.bootstrap_host if !(var.exclude_windows_worker && k == "windows-worker") }
  description = "Configured bootstrap hosts for each node."
}
