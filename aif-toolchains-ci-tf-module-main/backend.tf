

terraform {

  backend "remote" {
    hostname     = "na.artifactory.swg-devops.com"
    organization = "wcp-iaas-compops-team-terraformbackend-local"
    workspaces {
      prefix = "tf-ci-afi-"
    }
  }

}