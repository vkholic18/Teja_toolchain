

variable "iac_afi_generic_pipeline_types_trigger_data" {
  type = map(list(object({
    trigger_type             = string
    worker                   = optional(string, "")
    type                     = optional(string, "")
    cron                     = optional(string, "")
    key_name                 = optional(string, "")
    source                   = optional(string, "")
    trigger_branch           = optional(string, "")
    events                   = optional(list(string), [])
    event_listener           = string
    trigger_name             = string
    enabled                  = bool
    max_concurrent_runs      = optional(number, 0)
    enable_events_from_forks = optional(bool)
    filter                   = optional(string, "")
    properties = optional(map(object({
      type         = string
      value        = string
      secret_group = optional(string, "afi-secrets-group")
    })), {})
  })))
  default = {
    "pipeline" = [{
      "trigger_type"        = "scm",
      "filter"              = " header['x-github-event'] == 'issues' &&  body.action == 'opened' ",
      "event_listener"      = "dev-mode-cd-listener",
      "trigger_name"        = "AFI",
      "enabled"             = true,
      "max_concurrent_runs" = 15
      },
      {
        "trigger_type"   = "generic",
        "worker"         = "ngdc-afi-dal10-qz5",
        "trigger_name"   = "dal10-qz5",
        "type"           = "token_matches",
        "key_name"       = "x-async-stage-token",
        "source"         = "header"
        "events"         = [""],
        "event_listener" = "async-stage-listener",
        "enabled"        = true,
        "properties" = {
          "test-param" = {
            type  = "text",
            value = "test"
          }

        },
      },
      {
        "trigger_type"   = "generic",
        "worker"         = "ngdc-afi-dal09-qz4",
        "trigger_name"   = "dal09-qz4",
        "type"           = "token_matches",
        "key_name"       = "x-async-stage-token",
        "source"         = "header"
        "events"         = [""],
        "event_listener" = "async-stage-listener",
        "enabled"        = true,
        "properties" = {
          "test-param" = {
            type  = "text",
            value = "test"
          }

        },


      }
    ],
  }
}



variable "iac_afi_integrations_pr_pipeline_master" {
  type    = list(any)
  default = ["evidence-repo", "inventory-repo", "incident-repo"]
}

variable "iac_afi_pr_master_pipeline_meta" {
  type = map(object({
    type  = string
    value = string
  }))
  default = {
    "STATE_UNLOCK_ONLY" = {
      "type"  = "text",
      "value" = "0"
    },
    "pipeline-config" = {
      "type"  = "text",
      "value" = ".afi-pipeline-config.yaml"
    }
  }
}



variable "iac_afi_tf_vars" {
  type = map(object({
    type  = string
    value = string
  }))
  default = {

  }
}


