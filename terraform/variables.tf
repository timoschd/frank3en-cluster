variable "nodes" {
  type = map(object({
    local_ip  = string
    is_master = bool
    cpu       = number
    ram_gb    = number
    res_cpu   = string # e.g., "200m"
    res_ram   = string # e.g., "512Mi"
  }))
  default = {
    "pi-brain" = {
      local_ip  = "192.168.1.10" # Change to your Pi's Local IP
      is_master = true
      cpu       = 4
      ram_gb    = 4
      res_cpu   = "200m"
      res_ram   = "400Mi"
    },
    "mac-worker" = {
      local_ip  = "127.0.0.1"
      is_master = false
      cpu       = 2
      ram_gb    = 6
      res_cpu   = "200m"
      res_ram   = "800Mi"
    },
    "ubuntu-worker" = {
      local_ip  = "192.168.1.12" # Change to your PC's Local IP
      is_master = false
      cpu       = 2
      ram_gb    = 3
      res_cpu   = "200m"
      res_ram   = "512Mi"
    }
  }
}

# Values injected from your .env
variable "use_tailscale" { type = bool }
variable "tailnet_name" { type = string }
variable "master_tailscale_ip" { type = string }
variable "ssh_user" { type = string }
variable "ssh_key_path" { type = string }
variable "k3s_token" { type = string }
