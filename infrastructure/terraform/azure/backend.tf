terraform {
  backend "remote" {
    hostname     = "app.terraform.io"
    organization = "mcfaul-cloud"

    workspaces {
      name = "GitOps"
    }
  }
}
