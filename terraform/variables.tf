variable "nodes" {
  type = map(object({
    bootstrap_host = string
    bootstrap_mode = string # "ssh" or "local"
    ssh_port       = number
    ssh_user       = string
    ssh_auth       = string # "key" or "password"
    ssh_key_path   = string
    ssh_password   = string
    is_master      = bool
    cpu            = number
    ram_gb         = number
    res_cpu        = string # e.g., "200m"
    res_ram        = string # e.g., "512Mi"
    node_labels    = list(string)
  }))
  default = {
    "pi-brain" = {
      bootstrap_host = "raspberrypi.local"
      bootstrap_mode = "ssh"
      ssh_port       = 2222
      ssh_user       = "user"
      ssh_auth       = "key"
      ssh_key_path   = ""
      ssh_password   = ""
      is_master      = true
      cpu            = 2
      ram_gb         = 4
      res_cpu        = "200m"
      res_ram        = "500Mi"
      node_labels    = ["node-role.kubernetes.io/controller=true", "hardware=pi"]
    },
    "mac-worker" = {
      bootstrap_host = "Tim-Schendzielorz.local"
      bootstrap_mode = "ssh"
      ssh_port       = 22
      ssh_user       = "user"
      ssh_auth       = "key"
      ssh_key_path   = ""
      ssh_password   = ""
      is_master      = false
      cpu            = 4
      ram_gb         = 6
      res_cpu        = "1500m"
      res_ram        = "2000Mi"
      node_labels    = ["hardware=mac"]
    },
    "ubuntu-worker" = {
      bootstrap_host = "127.0.0.1"
      bootstrap_mode = "local"
      ssh_port       = 22
      ssh_user       = ""
      ssh_auth       = "key"
      ssh_key_path   = ""
      ssh_password   = ""
      is_master      = false
      cpu            = 2
      ram_gb         = 4
      res_cpu        = "750m"
      res_ram        = "1200Mi"
      node_labels    = ["hardware=ubuntu"]
    },
    "windows-worker" = {
      bootstrap_host = "win"
      bootstrap_mode = "ssh"
      ssh_port       = 22
      ssh_user       = "user"
      ssh_auth       = "password"
      ssh_key_path   = ""
      ssh_password   = ""
      is_master      = false
      cpu            = 4
      ram_gb         = 8
      res_cpu        = "2000m"
      res_ram        = "4000Mi"
      node_labels    = ["hardware=windows-gpu"]
    }
  }
}

# Values injected from your .env
variable "use_tailscale" {
  type    = bool
  default = true
}
variable "exclude_windows_worker" {
  type    = bool
  default = false
}
variable "tailnet_name" { type = string }
variable "master_tailscale_ip" { type = string }
variable "k3s_token" { type = string }
variable "default_ssh_key_path" { type = string }
variable "default_ssh_password" {
  type      = string
  sensitive = true
  default   = ""
}
