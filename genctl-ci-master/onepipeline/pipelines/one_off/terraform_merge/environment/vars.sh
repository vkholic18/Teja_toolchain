#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================


# overrides the terraform workspace to us in the pipeline
# https://developer.hashicorp.com/terraform/language/settings/backends/remote#workspaces
# very important variable that is defined in the toolchain, this is refered to a workspace in terraform backend
# which is artifactory, it allows us to pick the workspace we are working against
# This is not a reference to a git repository workspace!
export workspace_name=$(get_env "workspace_name")

# workspace information for python script
export WORKSPACE_ORG=$(get_env "WORKSPACE_REPO_ORG")
export WORKSPACE_REPO=$(get_env "WORKSPACE_REPO_NAME")
export GITHUB_API_URL=$(get_env "GITHUB_API_URL")

# used for terraform backend rc file
export artifactory_domain=$(get_env "ARTIFACTORY_DOMAIN")

# terraform cli args specific to action being performed
export TF_CLI_ARGS_apply=$(get_env "TF_CLI_ARGS_apply")
export TF_CLI_ARGS_plan=$(get_env "TF_CLI_ARGS_plan")
