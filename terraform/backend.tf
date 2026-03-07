terraform {
  backend "gcs" {
    bucket = "frank3en-cluster-state"
    prefix = "terraform/state"
    # Credentials are automatically picked up from your GOOGLE_APPLICATION_CREDENTIALS env var
  }
}
