variable "ibmcloud_api_key" {
  sensitive = true
  type      = string
}

variable "ibmcloud_iam_url" {
  type    = string
  default = "https://iam.cloud.ibm.com/identity/token"
}

variable "region" {
  type    = string
  default = "us-south"
}

variable "secret_manager_region" {
  type = string
  default = "us-south"
}

variable "global_toolchain_compliance_tag" {
  type    = string
  default = "v10.28.0"
}


variable "default_inventory_repo_url" {
  type    = string
  default = "https://github.ibm.com/iaas-automation-framework/afi-compliance-inventory.git"
}

variable "default_evidence_repo_url" {
  type    = string
  default = "https://github.ibm.com/iaas-automation-framework/afi-compliance-evidence.git"
}

variable "default_compliance_repo_url" {
  type    = string
  default = "https://github.ibm.com/one-pipeline/compliance-pipelines.git"
}

variable "default_worker" {
  type    = string
  default = "IBM-INTERNAL-WORKER"
}

variable "toolchain_source_repo_url" {
  type    = string
  default = "https://github.ibm.com/ibmcloud/projects-infrastructure.git"
}

variable "project_id" {
  type    = string
  default = "0"
}

variable "toolchain_region" {
  type    = string
  default = "dal"
}



variable "secrets_manager_data" {
  type = map(any)

  default = {
    "sm-name"         = "VPC-CD-SecretsManager",
    "sm-instance"     = "VPC-CD-SecretsManager",
    "sm-resource-grp" = "Continuous_deployment_Group"
    "sm-secret-ref"   = "secrets-manager.us-south.Continuous_deployment_Group.VPC-CD-SecretsManager"
  }
}

variable "toolchains" {
  type = list(object({
    guid                                      = string
    name                                      = string
    repo                                      = string
    repo_branch                               = optional(string, "master")
    repo_org                                  = optional(string, "genctl")
    inventory_repo_url                        = optional(string, null)
    enable_events_from_forks                  = optional(bool, null)
    contrast_sast_enablement_in_pr_to_dev_int = optional(bool, false)
    enable_sonarqube_integration     = optional(bool, false)
    ignore_evidence_repo_integration = optional(bool, false)
    evidence_repo_url                = optional(string, null)
    incident_repo_url                = optional(string, null)
    compliance_repo_url              = optional(string, null)
    pipeline_name                    = string
    tags                             = optional(list(string), [])
    #IMPORTANT NOTE: if not overriden by a workspace this default tag sets all the other pipeline tags
    toolchain_compliance_tag = optional(string, "")
    resource_grp             = optional(string, "afi-secrets-group")
    pipeline_types_trigger_data = map(list(object({
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
      timezone                 = optional(string, "UTC")
      filter                   = optional(string, "")
      max_concurrent_runs      = optional(number, 0)
      enable_events_from_forks = optional(bool, null)
      properties = optional(map(object({
        type         = string
        value        = string
        secret_group = string
      })), {})
    })))
    tc_env_props = map(object({
      type         = string
      value        = string
      secret_group = optional(string)
    }))

    pipeline_meta = map(object({
      worker                        = string
      environment_repo_integrations = list(string)
      env_props = map(object({
        type         = string
        value        = string
        secret_group = optional(string)
      }))
    }))

    slack_user_config = optional(object({
      channel       = string
      event_start   = bool
      event_success = bool
      event_fail    = bool
    }), null)


  }))

  default = [
    {
      guid                                      = "default"
      name                                      = "default"
      repo                                      = "default"
      pipeline_name                             = "default"
      enabled_pipelines_types                   = ["default"]
      tags                                      = []
      contrast_sast_enablement_in_pr_to_dev_int = false
      enable_events_from_forks                  = true
      pipeline_types_trigger_data = {
        "test" = [{
          "trigger_type"             = "test",
          "worker"                   = "test",
          "type"                     = "test",
          "cron"                     = "* * * * *"
          "key_name"                 = "test",
          "source"                   = "test",
          "trigger_branch"           = "test",
          "events"                   = ["test"],
          "event_listener"           = "test",
          "trigger_name"             = "test",
          "enabled"                  = true,
          "enable_events_from_forks" = true,
          "timezone"                 = "test"
          "filter"                   = "test"
          "properties" = { "test" = {
            "type"         = "secure",
            "value"        = "test_value",
            "secret_group" = "test_secret_group"
          } }
        }]
      }
      tc_env_props = { "test" = {
        "name"         = "test_name",
        "type"         = "secure",
        "value"        = "test_value",
        "secret_group" = "test_secret_group"
      } }

      pipeline_meta = {}

   
  
    }
  ]
}

variable "workers" {
  type = list(object({
    name         = string
    token_ref    = optional(string)
    secret_group = optional(string, "afi-secrets-group")
  }))
  default = [
   {
      name      = "ngdc-afi-dal10-qz5"
      token_ref = "vpc-afi-dal10-qz5-iks-tekton-private-worker-dal"
    },
 
    {
      name      = "ngdc-afi-dal09-qz4"
      token_ref = "vpc-afi-dal09-qz4-iks-tekton-private-worker-dal"
    },
/* 
    {
      name      = "NGDC-WORKER"
      token_ref = "vpc-ci-prod-ngdc-tekton-private-worker-qz4-01"
    },
*/    
    {
      name = "IBM-INTERNAL-WORKER"
    }
  ]
}

variable "tc_global_env_props" {
  type = map(object({
    type         = string
    value        = string
    secret_group = optional(string, "afi-secrets-group")
  }))
  default = {
    "ibmcloud-api-key" = {
      "type"  = "secure",
      "value" = "onepipelineci-cloud-api-key"
    },
    "git-personal-access-token" = {
      "type"  = "secure",
      "value" = "ghe-pat-1pl-ci" # GHE Personal Access Token for OnePipelineCI functional id
    },
    # not mentioned, but additionally used here https://github.ibm.com/one-pipeline/core-baseimage/blob/2ccbfa8a92d7c8ffc9ed0bb826a59f9ffd368f9a/one-pipeline/git/README.md#clone_repo
    # overall, this would be removed as a result of https://github.ibm.com/genctl-cicd/genctl-ci/issues/3544
    "git-token" = { # this is a variable that is automatically created and used when GHE auth is oauth (default)
      "type"  = "secure",
      "value" = "ghe-pat-1pl-ci"
    },
    "pipeline-config-repo" = {
      "type"  = "text",
      "value" = "https://github.ibm.com/genctl-cicd/afi"
    },
    "pipeline-config-branch" = {
      "type"  = "text",
      "value" = "main"
    },
    "one-pipeline-dockerconfigjson" = {
      "type"  = "secure",
      "value" = "one-pipeline-dockerconfigjson-token"
    }
  }
}

# https://registry.terraform.io/providers/IBM-Cloud/ibm/1.50.0-beta0/docs/resources/cd_toolchain_tool_githubconsolidated#integration_owner
variable "ghe_integration_owner" {
  type = string

  default = "IBMid-697000FI8R" # this is the IAM ID of the 'Afi1@ibm.com' user. 
}

variable "template_type" {
  type = string
}

variable "base_image_props" {
  type = map(object({
    type         = string
    value        = string
    secret_group = optional(string, "afi-secrets-group")
  }))
  default = {
    "baseimage-auth-user" = {
      "type"  = "secure",
      "value" = "wcp-genctl-docker-local-artifactory-username"
    },
    "baseimage-auth-email" = {
      "type"  = "secure",
      "value" = "wcp-genctl-docker-local-artifactory-username"
    },
    "baseimage-auth-host" = {
      "type"  = "text",
      "value" = "docker-na-public.artifactory.swg-devops.com/wcp-genctl-docker-local"
    },
    "baseimage-auth-password" = {
      "type"  = "secure",
      "value" = "wcp-genctl-docker-local-artifactory-token"
    }
  }
}

variable "tc_contrast_sast_env_props" {
  type = map(object({
    type         = string
    value        = string
    secret_group = optional(string, "afi-secrets-group")
  }))
  default = {
    "contrast-sast-api-key" = {
      "type"  = "secure",
      "value" = "contrast-sast-api-key"
    },
    "contrast-sast-artifactory-token" = {
      "type"  = "secure",
      "value" = "onepipelineci-artifactory-token"
    },
    "contrast-sast-artifactory-user" = {
      "type"  = "secure",
      "value" = "contrast-sast-artifactory-user"
    },
    "contrast-sast-org-id" = {
      "type"  = "secure",
      "value" = "contrast-sast-org-id"
    },
    "contrast-sast-print-scan-results" = {
      "type"  = "text",
      "value" = "true"
    },
    "contrast-sast-rbac-group" = {
      "type"  = "text",
      "value" = "is.vpc"
    },
    "contrast-sast-service-key" = {
      "type"  = "secure",
      "value" = "contrast-sast-service-key"
    },
    "contrast-sast-username" = {
      "type"  = "secure",
      "value" = "contrast-sast-artifactory-user"
    },
    "contrast-sast-jar-url" = {
      "type"  = "text",
      "value" = "https://na.artifactory.swg-devops.com/artifactory/css-whitesource-team-java-contrast-agent-maven-local/sast-local-scan-runner-latest.jar"
    },
    "contrast-sast-scan-timeout" = {
      "type"  = "text",
      "value" = "120"
    }
  }
}

variable "tc_iac_env_props" {
  type = map(object({
    type         = string
    value        = string
    secret_group = optional(string, "afi-secrets-group")
  }))
  default = {
    "ARTIFACTORY_DOMAIN" = {
      "type"  = "text",
      "value" = "na.artifactory.swg-devops.com"
    },
    "GITHUB_API_URL" = {
      "type"  = "text",
      "value" = "https://github.ibm.com/api/v3"
    },
    "terraform-version" = {
      "type"  = "text",
      "value" = "1.10.2"
    },
     "COS_SERVICE_CREDENTIALS" = {
      "type"  = "secure",
      "value" = "cos-credentials-json"
    },
     "DNF_NO_CHECK_CERTIFICATES" = {
      "type"  = "text",
      "value" = "1"
    },
    "artifactory-docker-url" = {
      "type"  = "text",
      "value" = "docker-na-public.artifactory.swg-devops.com"
    },
     "artifactory_reader" = {
      "type"  = "text",
      "value" = "afi1@ibm.com"
    },
      "artifactory_token" = {
      "type"  = "secure",
      "value" = "artifactory_token"
    },
     "assignedto" = {
      "type"  = "text",
      "value" = "afi1@ibm.com"
    },
     "cos-bucket-name" = {
      "type"  = "text",
      "value" = "afi"
    },
      "cos-endpoint" = {
      "type"  = "text",
      "value" = "https://s3.jp-tok.cloud-object-storage.appdomain.cloud/"
    },
      "cpap_trigger" = {
      "type"  = "text",
      "value" = "cpap_trigger"
    },
       "iam-test-cloud-api" = {
      "type"  = "text",
      "value" = "https://iam.test.cloud.ibm.com"
    },
      "max-attempts-busy-wait" = {
      "type"  = "text",
      "value" = "240"
    },
     "max_retries" = {
      "type"  = "text",
      "value" = "3"
    },
      "ops-repo" = {
      "type"  = "text",
      "value" = "https://github.ibm.com/iaas-automation-framework/operations-metadata.git"
    },
      "ops-repo-branch" = {
      "type"  = "text",
      "value" = "main"
    },
      "sample-operations-branch" = {
      "type"  = "text",
      "value" = "main"
    },
       "servicenow-api-base-url" = {
      "type"  = "text",
      "value" = "https://pnp-api-oss.test.cloud.ibm.com"
    },
      "servicenow-crn-mask" = {
      "type"  = "text",
      "value" = "is.vpc"
    },
      "sleep-time-busy-wait" = {
      "type"  = "text",
      "value" = "30"
    },
      "smotainer-version" = {
      "type"  = "text",
      "value" = "20240821T115608Z_7468de2a0013e4ddc0746c53f6b66a3cbc74d922"
    },
      "upload-to-git" = {
      "type"  = "text",
      "value" = "GitHub"
    },
      "validate_exported_var" = {
      "type"  = "text",
      "value" = "ENVIRONMENT,REGION"
    },
    "pnp-ibmcloud-api-key" = {
      "type"  = "secure",
      "value" = "servicenow-apikey"
    },
    "merge-cra-sbom" = {
      "type"  = "text",
      "value" = "1"
    },
     "pok_cert" = {
      "type"  = "secure",
      "value" = "pok-cert"
    },
       "pok_vault_url" = {
      "type"  = "text",
      "value" = "https://9.114.87.48:8200"
    },
        "staging" = {
      "type"  = "text",
      "value" = "staging"
    },
     "version" = {
      "type"  = "text",
      "value" = "v1"
    },
      "account-id" = {
      "type"  = "text",
      "value" = "ed2dc269480f4b2ebe9d6c90e01d9099"
    },
      "ONE_PIPELINE_CONFIG_DIRECTORY_NAME" = {
      "type"  = "text",
      "value" = "one-pipeline-config-repo"
    },
       "target-environment" = {
      "type"  = "text",
      "value" = "prod"
    },
       "target-environment-detail" = {
      "type"  = "text",
      "value" = "prod"
    },
       "target-environment-purpose" = {
      "type"  = "text",
      "value" = "production"
    },
       "force-redeploy" = {
      "type"  = "text",
      "value" = "false"
    },
       "cluster-namespace" = {
      "type"  = "text",
      "value" = "default"
    },
      "ibmcloud-mascd-api-key" = {
      "type"  = "secure",
      "value" = "mascd-api-key"
    },
      "secret-group-name" = {
      "type"  = "text",
      "value" = "default"
    },
      "service-url-secret-manager" = {
      "type"  = "text",
      "value" = "https://ee181c2a-078f-481b-892a-a43b31a544fe.us-south.secrets-manager.appdomain.cloud"
    },
      "ibmcloud-fabric-api-key" = {
      "type"  = "secure",
      "value" = "fabric-api-key"
    },
   
  
  }
}

variable "tc_razee_env_props" {
  type = map(object({
    type         = string
    value        = string
    secret_group = optional(string, "afi-secrets-group")
  }))
  default = {
    "git-personal-access-token" = {
      "type"  = "secure",
      "value" = "ghe-pat-1pl-razee-ci"
    },
    "git-token" = {
      "type"  = "secure",
      "value" = "ghe-pat-1pl-razee-ci"
    }
  }
}

# Default secret group
variable "secret_group" {
  type    = string
  default = "afi-secrets-group"
}

variable "global_enable_events_from_forks" {
  type    = bool
  default = true
}

variable "global_ignore_evidence_repo_integration" {
  type    = bool
  default = false
}

