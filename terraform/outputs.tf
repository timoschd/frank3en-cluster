output "tailscale_ips" {
  value       = { for k, v in var.nodes : k => v.local_ip }
  description = "The nodes are now connected via Tailscale."
}
