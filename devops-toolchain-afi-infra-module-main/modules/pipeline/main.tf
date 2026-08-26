locals {
  generic_trigger_exists = contains([for pipeline in lookup(var.pipeline_types_trigger_data, var.pipeline_type, []) : pipeline.trigger_type], "generic")
  trigger_properties_overrides = flatten([
    for local_index, data in var.pipeline_types_trigger_data[var.pipeline_type] : [
      for prop_key, prop_data in data.properties != null && length(data.properties) > 0 ? data.properties : {} : {
        trigger_name = data.trigger_type == "scm" ? data.trigger_name : local_index
        key_name     = prop_key
        type         = prop_data.type
        value        = prop_data.value
        secret_group = prop_data.secret_group
      }
    ]
    if data.properties != null && length(data.properties) > 0
  ])
}

resource "random_password" "password" {
  count   = local.generic_trigger_exists ? 1 : 0
  length  = 32
  special = false
}


resource "ibm_cd_toolchain_tool_pipeline" "toolchain_tool_pipeline" {
  toolchain_id = var.toolchain_id
  parameters {
    # clean up the name and make it unique since this will be printed as part of the slack integration
    # message and also since the UI is limited on length before it ellipses and makes it difficult to read
    name = format("%s.%s", var.pipeline_name, replace(var.pipeline_type, "-pipeline-", "-"))
  }
}

resource "ibm_cd_tekton_pipeline" "pipeline_instance" {
  pipeline_id          = ibm_cd_toolchain_tool_pipeline.toolchain_tool_pipeline.tool_id
  enable_notifications = true
  worker {
    id = var.pipeline_worker_id
  }
}

resource "ibm_cd_tekton_pipeline_definition" "tekton_pipeline_definition" {
  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  source {
    type = "git"
    properties {
      path = "definitions"
      url  = "https://github.ibm.com/one-pipeline/compliance-pipelines.git"
      tag  = var.toolchain_compliance_tag
      # branch = "v9"
    }
  }
}

resource "ibm_cd_tekton_pipeline_property" "evidence_repo" {
  count       = contains(var.environment_repo_integrations, "evidence-repo") && var.ignore_evidence_repo_integration == false ? 1 : 0
  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  name        = "evidence-repo"
  type        = "integration"
  value       = var.evidence_repo_int_id
  path        = "parameters.repo_url"
}

resource "ibm_cd_tekton_pipeline_property" "inventory_repo" {
  count       = contains(var.environment_repo_integrations, "inventory-repo") ? 1 : 0
  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  name        = "inventory-repo"
  type        = "integration"
  value       = var.inventory_repo_int_id
  path        = "parameters.repo_url"
}

resource "ibm_cd_tekton_pipeline_property" "incident_repo" {
  count       = contains(var.environment_repo_integrations, "incident-repo") ? 1 : 0
  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  name        = "incident-repo"
  type        = "integration"
  value       = var.incident_repo_int_id
  path        = "parameters.repo_url"
}


# all pipelines will inherit the pipeline debug property and initially set to 0
# CI/development will encounter times where this needs to be enabled and this change should not trigger
# a delta against the TF deployment.
resource "ibm_cd_tekton_pipeline_property" "tekton_pipeline_property_debug" {

  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  enum        = ["0", "1"]
  name        = "pipeline-debug"
  type        = "single_select"
  value       = "0"

  lifecycle {
    ignore_changes = [value]
  }
}

resource "ibm_cd_tekton_pipeline_property" "tekton_pipeline_property_sm_secure_test" {
  for_each = var.pipeline_properties

  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  name        = each.key
  type        = each.value["type"]
  value       = each.value["type"] == "secure" ? format("ref://%s/%s/%s", var.sm_secret_ref, each.value["secret_group"], each.value["value"]) : each.value["value"]
}

resource "ibm_cd_tekton_pipeline_property" "tekton_pipeline_property_repo_branch" {
  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  name        = "repo_branch"
  type        = "text"
  value       = var.repo_branch
}

resource "ibm_cd_tekton_pipeline_property" "tekton_pipeline_property_repo_org" {
  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  name        = "repo_org"
  type        = "text"
  value       = var.repo_org
}

resource "ibm_cd_tekton_pipeline_property" "tekton_pipeline_property_subpipeline_hash" {
  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  count       = local.generic_trigger_exists ? 1 : 0
  name        = "subpipeline-webhook-token"
  type        = "secure"
  value       = element(random_password.password.*.result, 0)
}

resource "ibm_cd_tekton_pipeline_trigger" "tekton_pipeline_trigger" {
  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  for_each = {
    for trigger in var.pipeline_types_trigger_data[var.pipeline_type] :
    trigger.trigger_type == "scm" ? trigger.trigger_name : null => trigger
    if trigger.trigger_type == "scm"
  }
  type           = "scm"
  name           = each.value.trigger_name
  event_listener = each.value.event_listener
  filter         = each.value.filter
  source {
    type = "git"
    properties {
      url    = var.repo_build
     # branch = each.value.trigger_branch != "" ? each.value.trigger_branch : var.repo_branch
    }
  }
  worker {
    id = try(var.worker_ids[each.value.worker], var.pipeline_worker_id)
  }
  events                   = each.value.events
  enabled                  = each.value.enabled
  max_concurrent_runs      = try(each.value.max_concurrent_runs, 0)
  enable_events_from_forks = each.value.enable_events_from_forks
}

resource "ibm_cd_tekton_pipeline_trigger" "timer_tekton_pipeline_trigger" {
  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  for_each = {
    for idx, pipeline in var.pipeline_types_trigger_data[var.pipeline_type] :
    pipeline.trigger_type == "timer" ? idx : null => pipeline
    if pipeline.trigger_type == "timer"
  }
  type           = "timer"
  name           = each.value.trigger_name
  cron           = each.value.cron
  event_listener = each.value.event_listener
  worker {
    id = try(var.worker_ids[each.value.worker], var.pipeline_worker_id)
  }
  timezone            = each.value.timezone
  enabled             = each.value.enabled
  max_concurrent_runs = try(each.value.max_concurrent_runs, 0)
}

resource "ibm_cd_tekton_pipeline_trigger_property" "trigger_properties_overrides" {
  count       = length(local.trigger_properties_overrides)
  name        = local.trigger_properties_overrides[count.index].key_name
  type        = local.trigger_properties_overrides[count.index].type
  value       = local.trigger_properties_overrides[count.index].type == "secure" ? format("ref://%s/%s/%s}", var.sm_secret_ref, local.trigger_properties_overrides[count.index].secret_group, local.trigger_properties_overrides[count.index].value) : local.trigger_properties_overrides[count.index].value
  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  trigger_id = try(ibm_cd_tekton_pipeline_trigger.tekton_pipeline_trigger[local.trigger_properties_overrides[count.index].trigger_name].trigger_id,
    ibm_cd_tekton_pipeline_trigger.sub_tekton_pipeline_trigger[local.trigger_properties_overrides[count.index].trigger_name].trigger_id,
    ibm_cd_tekton_pipeline_trigger.timer_tekton_pipeline_trigger[local.trigger_properties_overrides[count.index].trigger_name].trigger_id,
    ibm_cd_tekton_pipeline_trigger.manual_tekton_pipeline_trigger[local.trigger_properties_overrides[count.index].trigger_name].trigger_id
  )
}


resource "ibm_cd_tekton_pipeline_trigger" "sub_tekton_pipeline_trigger" {
  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  for_each = {
    for idx, pipeline in var.pipeline_types_trigger_data[var.pipeline_type] :
    pipeline.trigger_type == "generic" ? idx : null => pipeline
    if pipeline.trigger_type == "generic"
  }
  type           = "generic"
  name           = each.value.trigger_name
  enabled        = each.value.enabled
  event_listener = each.value.event_listener
  worker {
    id = try(var.worker_ids[each.value.worker], var.pipeline_worker_id)
  } 
  secret {
    type     = each.value.type
    key_name = each.value.key_name
    value    = element(random_password.password.*.result, 0)
    source   = each.value.source
  }
}

resource "ibm_cd_tekton_pipeline_trigger" "manual_tekton_pipeline_trigger" {
  pipeline_id = ibm_cd_tekton_pipeline.pipeline_instance.id
  for_each = {
    for idx, pipeline in var.pipeline_types_trigger_data[var.pipeline_type] :
    pipeline.trigger_type == "manual" ? idx : null => pipeline
    if pipeline.trigger_type == "manual"
  }
  type           = "manual"
  name           = each.value.trigger_name
  enabled        = each.value.enabled
  event_listener = each.value.event_listener
  worker {
    id = try(var.worker_ids[each.value.worker], var.pipeline_worker_id)
  } 
  max_concurrent_runs = try(each.value.max_concurrent_runs, 0)
}



