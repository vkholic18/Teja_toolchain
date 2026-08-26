variable "toolchain_id" {}

variable "toolchain_source_repo_url" {
  type    = string
  default = "https://github.ibm.com/open-toolchain/projects-toolchain.git"
}

variable "evidence_repo_int_id" {
  type = string
}

variable "incident_repo_int_id" {
  type = string
}

variable "inventory_repo_int_id" {
  type = string
}


variable "ibmcloud_api_key" {
  sensitive = true
  type      = string
}

variable "project_id" {
  type = string
}

variable "pipeline_properties" {
  type = map(object({
    type         = string
    value        = string
    secret_group = optional(string)
  }))
}

variable "toolchain_region" {
  type = string
}

variable "region" {
  type = string
}

variable "toolchain_compliance_tag" {
  type = string
}

variable "repo_build" {
  type = string
}

variable "sm_secret_ref" {
  type = string
}

variable "pipeline_worker_id" {
  type = string
}

variable "pipeline_type" {
  type = string
}

variable "repo_branch" {
  type = string
}

variable "repo_org" {
  type = string
}

variable "pipeline_name" {
  type = string
}

variable "worker_ids" {
  type = map(string)
}

variable "environment_repo_integrations" {
  type = list(string)
}

variable "pipeline_types_trigger_data" {
  type = map(list(object({
    trigger_type             = string
    worker                   = string
    type                     = string
    cron                     = string
    key_name                 = string
    source                   = string
    trigger_branch           = string
    events                   = list(string)
    event_listener           = string
    trigger_name             = string
    enabled                  = bool
    max_concurrent_runs      = number
    timezone                 = string
    filter                   = string
    enable_events_from_forks = bool
    properties = map(object({
      type         = string
      value        = string
      secret_group = optional(string)
    }))
  })))
}

variable "ignore_evidence_repo_integration" {
  type = bool
}
