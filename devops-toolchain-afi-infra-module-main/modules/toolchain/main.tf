locals {
  combined_workers = flatten([
    for tc in var.toolchains :
    [
      for worker in var.workers :
      {
        tc_guid      = tc.guid
        worker_name  = worker.name
        key_ref      = worker.token_ref
        secret_group = worker.secret_group
      }
    ]
  ])

  tc_common_global_env_props          = var.tc_global_env_props
  tc_global_env_props_afi           = merge(local.tc_common_global_env_props, var.tc_iac_env_props)
  general_workers_names               = [for worker in var.workers : worker.name]
  pipeline_matrix = flatten([
    for tc in var.toolchains :
    [
      for pipeline_type, _ in tc.pipeline_meta :
      merge(
        tc,
        {
          pipeline_type = pipeline_type,
          pipeline_properties = merge(
            var.template_type != null && var.template_type == "afi" ? local.tc_global_env_props_afi : {},
            tc.tc_env_props,
            try(tc.pipeline_meta[pipeline_type].env_props, {}),
          ),
          pipeline_worker_id               = contains(local.general_workers_names, try(tc.pipeline_meta[pipeline_type].worker, "")) ? "${tc.guid}-${tc.pipeline_meta[pipeline_type].worker}" : "${tc.guid}-${var.default_worker}",
          environment_repo_integrations    = try(tc.pipeline_meta[pipeline_type].environment_repo_integrations, {}),
          toolchain_compliance_tag         = tc.toolchain_compliance_tag != "" ? tc.toolchain_compliance_tag : var.global_toolchain_compliance_tag,
          enable_events_from_forks         = tc.enable_events_from_forks != null ? tc.enable_events_from_forks : var.global_enable_events_from_forks
          ignore_evidence_repo_integration = tc.ignore_evidence_repo_integration != null ? tc.ignore_evidence_repo_integration : var.global_ignore_evidence_repo_integration
      })
    ]
  ])
}

data "ibm_resource_group" "tc_resource_group" {
  for_each = { for tc in var.toolchains : tc.guid => tc }

  name = each.value.resource_grp
}

resource "ibm_cd_toolchain" "toolchain_instance" {
  for_each = { for tc in var.toolchains : tc.guid => tc }

  name              = "tc-${each.value.name}"
  resource_group_id = data.ibm_resource_group.tc_resource_group[each.value.guid].id
  tags              = each.value.tags
}

## ---------------------------------------------------------------------------------------------------------------------
## GHE INTEGRATIONS - BEGIN
## ---------------------------------------------------------------------------------------------------------------------

resource "ibm_cd_toolchain_tool_githubconsolidated" "inventory_repo" {
  for_each     = { for tc in var.toolchains : tc.guid => tc }
  depends_on   = [ibm_cd_toolchain_tool_secretsmanager.cd_toolchain_tool_secretsmanager]
  toolchain_id = ibm_cd_toolchain.toolchain_instance[each.value.guid].id
  name         = "inventory-repo"
  initialization {
    git_id       = "integrated"
    type         = "link"
    repo_url     = each.value.inventory_repo_url != null ? each.value.inventory_repo_url : var.default_inventory_repo_url
    private_repo = true
    repo_name    = "vpc-compliance-inventory"
  }
  parameters {
    auth_type                = "pat"
    api_token                = "ref://${var.secrets_manager_data["sm-secret-ref"]}/${local.tc_common_global_env_props["git-personal-access-token"]["secret_group"]}/${local.tc_common_global_env_props["git-personal-access-token"]["value"]}"
    integration_owner        = var.ghe_integration_owner
    toolchain_issues_enabled = false
    enable_traceability      = false
  }
}

resource "ibm_cd_toolchain_tool_githubconsolidated" "compliance_evidence_repo" {
  for_each     = { for tc in var.toolchains : tc.guid => tc }
  depends_on   = [ibm_cd_toolchain_tool_secretsmanager.cd_toolchain_tool_secretsmanager]
  toolchain_id = ibm_cd_toolchain.toolchain_instance[each.value.guid].id
  name         = "evidence-repo"
  initialization {
    git_id       = "integrated"
    type         = "link"
    repo_url     = each.value.evidence_repo_url != null ? each.value.evidence_repo_url : var.default_evidence_repo_url
    private_repo = true
    repo_name    = "vpc-compliance-evidence"
  }
  parameters {
    auth_type                = "pat"
    api_token                = "ref://${var.secrets_manager_data["sm-secret-ref"]}/${local.tc_common_global_env_props["git-personal-access-token"]["secret_group"]}/${local.tc_common_global_env_props["git-personal-access-token"]["value"]}"
    integration_owner        = var.ghe_integration_owner
    toolchain_issues_enabled = false
    enable_traceability      = false
  }
}

resource "ibm_cd_toolchain_tool_githubconsolidated" "incident_repo" {
  for_each     = { for tc in var.toolchains : tc.guid => tc if tc.incident_repo_url != null }
  depends_on   = [ibm_cd_toolchain_tool_secretsmanager.cd_toolchain_tool_secretsmanager]
  toolchain_id = ibm_cd_toolchain.toolchain_instance[each.value.guid].id
  name         = "incident-repo"
  initialization {
    git_id       = "integrated"
    type         = "link"
    repo_url     = each.value.incident_repo_url
    private_repo = true
    repo_name    = "vpc-compliance-incident"
  }
  parameters {
    auth_type                = "pat"
    api_token                = "ref://${var.secrets_manager_data["sm-secret-ref"]}/${local.tc_common_global_env_props["git-personal-access-token"]["secret_group"]}/${local.tc_common_global_env_props["git-personal-access-token"]["value"]}"
    integration_owner        = var.ghe_integration_owner
    toolchain_issues_enabled = false
    enable_traceability      = false
  }
}

resource "ibm_cd_toolchain_tool_githubconsolidated" "repository_compliance_pipelines" {
  for_each     = { for tc in var.toolchains : tc.guid => tc }
  depends_on   = [ibm_cd_toolchain_tool_secretsmanager.cd_toolchain_tool_secretsmanager]
  toolchain_id = ibm_cd_toolchain.toolchain_instance[each.value.guid].id

  initialization {
    git_id   = "integrated"
    type     = "link"
    repo_url = each.value.compliance_repo_url != null ? each.value.compliance_repo_url : var.default_compliance_repo_url
  }
  parameters {
    auth_type                = "pat"
    api_token                = "ref://${var.secrets_manager_data["sm-secret-ref"]}/${local.tc_common_global_env_props["git-personal-access-token"]["secret_group"]}/${local.tc_common_global_env_props["git-personal-access-token"]["value"]}"
    integration_owner        = var.ghe_integration_owner
    enable_traceability      = false
    toolchain_issues_enabled = false
  }
}

resource "ibm_cd_toolchain_tool_githubconsolidated" "tc_build_repo" {
  for_each     = { for tc in var.toolchains : tc.guid => tc }
  depends_on   = [ibm_cd_toolchain_tool_secretsmanager.cd_toolchain_tool_secretsmanager]
  toolchain_id = ibm_cd_toolchain.toolchain_instance[each.value.guid].id
  name         = "app-repo"

  initialization {
    git_id   = "integrated"
    type     = "link"
    repo_url = each.value.repo
  }

  parameters {
    auth_type                = "pat"
    api_token                = "ref://${var.secrets_manager_data["sm-secret-ref"]}/${local.tc_common_global_env_props["git-personal-access-token"]["secret_group"]}/${local.tc_common_global_env_props["git-personal-access-token"]["value"]}"
    integration_owner        = var.ghe_integration_owner
    enable_traceability      = false
    toolchain_issues_enabled = false
  }
}

## ---------------------------------------------------------------------------------------------------------------------
## GHE INTEGRATIONS - END
## ---------------------------------------------------------------------------------------------------------------------

#
# Pipeline definitions per toolchain
#

data "ibm_resource_group" "resource_group" {
  name = var.secrets_manager_data["sm-resource-grp"]
}

data "ibm_resource_instance" "sm_instance" {
  name              = var.secrets_manager_data["sm-name"]
  resource_group_id = data.ibm_resource_group.resource_group.id
  location = var.secret_manager_region
}

##
# integrate secrets manager
##
resource "ibm_iam_authorization_policy" "s2sAuth1" {
  for_each = { for tc in var.toolchains : tc.guid => tc }

  source_service_name         = "toolchain"
  source_resource_instance_id = ibm_cd_toolchain.toolchain_instance[each.value.guid].id

  target_service_name         = "secrets-manager"
  target_resource_instance_id = data.ibm_resource_instance.sm_instance.guid
  roles                       = ["Viewer", "SecretsReader"]
}

resource "ibm_cd_toolchain_tool_secretsmanager" "cd_toolchain_tool_secretsmanager" {
  for_each = { for tc in var.toolchains : tc.guid => tc }

  parameters {
    name                = var.secrets_manager_data["sm-name"]
    resource_group_name = var.secrets_manager_data["sm-resource-grp"]
    location            = var.region
    instance_name       = var.secrets_manager_data["sm-instance"]
  }
  toolchain_id = ibm_cd_toolchain.toolchain_instance[each.value.guid].id
}

resource "ibm_cd_toolchain_tool_devopsinsights" "cd_toolchain_tool_devopsinsights_instance" {
  for_each     = { for tc in var.toolchains : tc.guid => tc }
  toolchain_id = ibm_cd_toolchain.toolchain_instance[each.value.guid].id
}


resource "ibm_cd_toolchain_tool_privateworker" "cd_toolchain_tool_privateworker_instance" {
  for_each   = { for worker in local.combined_workers : "${worker.tc_guid}-${worker.worker_name}" => worker if worker.worker_name != "IBM-INTERNAL-WORKER" }
  depends_on = [ibm_cd_toolchain_tool_secretsmanager.cd_toolchain_tool_secretsmanager]
  parameters {
    name                     = each.value.worker_name
    worker_queue_credentials = "ref://${var.secrets_manager_data["sm-secret-ref"]}/${each.value.secret_group}/${each.value.key_ref}"
  }
  toolchain_id = ibm_cd_toolchain.toolchain_instance[each.value.tc_guid].id
}

##
# integrate slack
##

resource "ibm_cd_toolchain_tool_slack" "cd_toolchain_tool_slack_instance" {
  for_each   = { for tc in var.toolchains : tc.guid => tc }
  depends_on = [ibm_cd_toolchain_tool_secretsmanager.cd_toolchain_tool_secretsmanager]
  parameters {
    # eventually we will allow development to override this with their own channel and events. For phase 1, per gh-4198,
    # we are posting to a singular channel with prescribed events
    channel_name     = "afi"
    pipeline_start   = true
    pipeline_success = true
    pipeline_fail    = true
    toolchain_bind   = false
    toolchain_unbind = false
    webhook          = "ref://${var.secrets_manager_data["sm-secret-ref"]}/afi-secrets-group/slack-webhook"
    team_name        = "ibm.enterprise"
  }
  toolchain_id = ibm_cd_toolchain.toolchain_instance[each.value.guid].id
}

#------------------------------------------------------------------------------
# Pipelines included in this toolchain
#------------------------------------------------------------------------------

module "pipeline" {
  for_each = { for tc in local.pipeline_matrix : "${tc.guid}-${tc.pipeline_type}" => tc }
  source   = "../pipeline"
  depends_on = [
    ibm_cd_toolchain_tool_privateworker.cd_toolchain_tool_privateworker_instance, 
    ibm_cd_toolchain_tool_githubconsolidated.compliance_evidence_repo,
    ibm_cd_toolchain_tool_githubconsolidated.inventory_repo,
    ibm_cd_toolchain_tool_githubconsolidated.tc_build_repo,
    ibm_cd_toolchain_tool_secretsmanager.cd_toolchain_tool_secretsmanager
  ]
  toolchain_id                     = ibm_cd_toolchain.toolchain_instance[each.value.guid].id
  environment_repo_integrations    = each.value.environment_repo_integrations
  evidence_repo_int_id             = each.value.ignore_evidence_repo_integration == false ? ibm_cd_toolchain_tool_githubconsolidated.compliance_evidence_repo[each.value.guid].tool_id : null
  inventory_repo_int_id            = ibm_cd_toolchain_tool_githubconsolidated.inventory_repo[each.value.guid].tool_id
  incident_repo_int_id             = each.value.incident_repo_url != null ? ibm_cd_toolchain_tool_githubconsolidated.incident_repo[each.value.guid].tool_id : ibm_cd_toolchain_tool_githubconsolidated.tc_build_repo[each.value.guid].tool_id
  pipeline_type                    = each.value.pipeline_type
  toolchain_source_repo_url        = var.toolchain_source_repo_url
  ibmcloud_api_key                 = var.ibmcloud_api_key
  project_id                       = var.project_id # is this even used?
  region                           = var.region
  toolchain_region                 = var.toolchain_region
  repo_build                       = each.value.repo
  repo_branch                      = each.value.repo_branch
  toolchain_compliance_tag         = each.value.toolchain_compliance_tag
  repo_org                         = each.value.repo_org
  sm_secret_ref                    = var.secrets_manager_data["sm-secret-ref"]
  pipeline_name                    = each.value.pipeline_name
  ignore_evidence_repo_integration = each.value.ignore_evidence_repo_integration
   pipeline_worker_id               = can(regex("IBM-INTERNAL", each.value.pipeline_worker_id)) ? "internal" : ibm_cd_toolchain_tool_privateworker.cd_toolchain_tool_privateworker_instance["${each.value.pipeline_worker_id}"].tool_id
  worker_ids = merge({
    for worker in var.workers :
    worker.name => ibm_cd_toolchain_tool_privateworker.cd_toolchain_tool_privateworker_instance["${each.value.guid}-${worker.name}"].tool_id if worker.name != "IBM-INTERNAL-WORKER"
  }, { "IBM-INTERNAL-WORKER" = "internal" }) 
  # we add hotfix branch trigger set to stable-X.X.X if hotfix_params is set to true and there is a hotfix pipeline
  pipeline_types_trigger_data =  each.value.pipeline_types_trigger_data 
  #attach the env properties
  pipeline_properties = each.value.pipeline_properties
}
