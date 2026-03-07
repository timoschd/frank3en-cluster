terraform {
  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.13.0"
    }
  }
}

provider "tailscale" {
  # Set these as Environment Variables:
  # TAILSCALE_OAUTH_CLIENT_ID and TAILSCALE_OAUTH_CLIENT_SECRET
}
