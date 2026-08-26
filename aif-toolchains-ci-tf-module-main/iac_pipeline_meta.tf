locals {
  iac_afi_pipeline_meta_default = {
    "pipeline" = {
      worker                        = "IBM-INTERNAL-WORKER"
      environment_repo_integrations = var.iac_afi_integrations_pr_pipeline_master
      env_props                     = var.iac_afi_pr_master_pipeline_meta
    }
  }

}