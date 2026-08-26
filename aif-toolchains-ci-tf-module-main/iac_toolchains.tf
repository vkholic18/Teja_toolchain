# ---------------------------------------------------------------------------
# - This module serves as the main configuration for all toolchains/pipelines
# ---------------------------------------------------------------------------

module "toolchains" {

  source = "git::ssh://git@github.ibm.com/genctl-cicd/devops-toolchain-afi-infra-module.git//modules/toolchain"

  ibmcloud_api_key = var.ibmcloud_api_key
  region           = var.region

  # ---------------------------------------------------------------------------
  # - ENV PROPS (global) THAT WILL BE COPIED TO EACH PIPELINE OF EACH TOOLCHAIN
  # ---------------------------------------------------------------------------
  template_type = "afi"



  toolchains = [
    {
      guid = "afi-f458a058-82be-438e-878d-6ae3f0ec9fd5" # run something like 'uuidgen' to generate or online tool

      # toolchain name. note: all toolchains will get 'tc-' prepended to the name to help with sorting and denote
      # which toolchains were created with automation
      name        = "afi-ci-toolchain-tf-automation"
      repo        = "https://github.ibm.com/iaas-automation-framework/operations-metadata.git"
      repo_branch = "main"
      repo_org    = "iaas-automation-framework"
      # base name of the pipelines getting created
      pipeline_name = "afi"
      resource_grp  = "AFI" # we cannot use optional
      tags          = ["type:AFI", "toolchains:AFI"]
      # ---------------------------------------------------------------------------------
      # - ENV PROPS (toolchain) THAT WILL BE COPIED TO EACH PIPELINE OF A GIVEN TOOLCHAIN
      # ---------------------------------------------------------------------------------
      tc_env_props = var.iac_afi_tf_vars
      # pipeline_types_trigger_data = var.iac_afi_generic_pipeline_types_trigger_data
      pipeline_types_trigger_data = var.iac_afi_generic_pipeline_types_trigger_data
      # ---------------------------------------------------------------------------------
      # - PIPELINE SPECIFIC METADATA (pipeline) ie ENV PROPERTIES FOR A GIVEN PIPELINE
      # ---------------------------------------------------------------------------------
      pipeline_meta = local.iac_afi_pipeline_meta_default
    }

  ]
}
