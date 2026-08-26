#!/usr/bin/env bash
#
# NAME : setup_branch-protection.sh - setup expected branch protection on the saved repositories listed using [list_repos](https://cloud.ibm.com/docs/devsecops?topic=devsecops-devsecops-pipelinectl#list_repos)
# USAGE : setup_branch-protection.sh
# DESCRIPTION :
#   Setup expected branch protection on the saved repositories listed using [list_repos](https://cloud.ibm.com/docs/devsecops?topic=devsecops-devsecops-pipelinectl#list_repos)
# PROPERTIES :
#   branch-protection-status-check-prefix : prefix of the status checks to set for branch protection. (Default to `tekton`)
# OUTCOME :
#   branch protection settings have been set appropriately
#

set -euo pipefail

# shellcheck disable=SC1090
source "${ONE_PIPELINE_PATH}"/tools/get_repo_params
source "${ONE_PIPELINE_PATH}"/tools/pipeline_utils

APP_TOKEN_PATH="./app-token"

# RUN Branch protection
#
# Iterate over repos that were registered to the pipeline
# by the save_repo of the pipelinectl tool.
while read -r repo; do
  echo "Applying branch protection setup to repository: $repo - $(load_repo "$repo" url)"
  read -r APP_REPO_NAME APP_REPO_OWNER APP_SCM_TYPE APP_API_URL < <(get_repo_params "$(load_repo "$repo" url)" "$APP_TOKEN_PATH")

  if [[ $APP_SCM_TYPE == "gitlab" ]]; then
    disable_debug
    curl --location --request PUT "${APP_API_URL}/projects/$(echo "${APP_REPO_OWNER}/${APP_REPO_NAME}" | jq -rR @uri)" \
      --header "PRIVATE-TOKEN: $(cat $APP_TOKEN_PATH)" \
      --header 'Content-Type: application/json' \
      --data-raw '{"only_allow_merge_if_pipeline_succeeds": true}'
    enable_debug
  else
    # If PR, then target branch of the PR is the branch to protect
    branch=$(get_env base-branch "")
    if [ -z "$branch" ]; then
      branch="$(cat /config/git-branch)"
    fi
    status_check_context_prefix="$(get_env branch-protection-status-check-prefix "tekton")"
    
    # Define old and new check mappings
    # Old checks (with prefix applied)
    old_checks='["code-branch-protection", "code-unit-tests", "code-cis-check", "code-detect-secrets"]'
    
    # New checks - dynamically fetch from custom_required_checks_razee.json
    custom_checks_file="${PATH_TO_GENCTL_CI}/hack/ci/custom_required_checks_razee.json"
    if [ -f "$custom_checks_file" ]; then
      # Extract checks array from JSON file and remove 'tekton/' prefix
      new_checks=$(jq -c '.[0].params.checks | map(sub("^tekton/"; ""))' "$custom_checks_file")
      echo "Loaded new checks from $custom_checks_file: $new_checks"
    else
      # Fallback to hardcoded checks if file not found (without tekton/ prefix)
      echo "Warning: $custom_checks_file not found, using fallback checks"
      new_checks='["pr-code-checks/code-detect-secrets", "pr-code-checks-4/code-branch-protection", "pr-code-checks-4/code-cis-check", "pr-code-build/code-unit-tests"]'
    fi
    
    branch_protection_content=$(mktemp)
    disable_debug
    curl -L -H "Authorization: Bearer $(cat ${APP_TOKEN_PATH})" -H "Accept: application/vnd.github+json" "${APP_API_URL}/repos/${APP_REPO_OWNER}/${APP_REPO_NAME}/branches/$branch/protection" > "$branch_protection_content"
    enable_debug

    if jq -e '.required_status_checks' "$branch_protection_content" > /dev/null 2>&1; then
      # branch protection exists - update it by replacing old checks with new ones
      # align content with expected input schema
      jq --arg context_prefix "$status_check_context_prefix" --argjson old_checks "$old_checks" --argjson new_checks "$new_checks" 'del(.url) | del(.required_status_checks.url) | del(.required_status_checks.checks) | del(.required_status_checks.contexts_url) | del(.required_pull_request_reviews.url) | del(.required_signatures.url) | del(.enforce_admins.url)' "${branch_protection_content}" > "${branch_protection_content}_tmp" && mv -f "${branch_protection_content}_tmp" "${branch_protection_content}"
      # Handle restrictions: convert user/team objects to username/slug strings, or set to null if empty
      jq --arg context_prefix "$status_check_context_prefix" --argjson old_checks "$old_checks" --argjson new_checks "$new_checks" '
        if has("restrictions") and .restrictions != null then
          .restrictions |= {
            users: (if .users then [.users[] | .login] else [] end),
            teams: (if .teams then [.teams[] | .slug] else [] end),
            apps: (if .apps then [.apps[] | .slug] else [] end)
          } |
          # If all arrays are empty, set restrictions to null
          if (.restrictions.users | length) == 0 and (.restrictions.teams | length) == 0 and (.restrictions.apps | length) == 0 then
            .restrictions = null
          else
            .
          end
        else
          .restrictions = null
        end
      ' "${branch_protection_content}" > "${branch_protection_content}_tmp" && mv -f "${branch_protection_content}_tmp" "${branch_protection_content}"
      # Ensure required_pull_request_reviews exists and set default required settings
      jq --arg context_prefix "$status_check_context_prefix" --argjson old_checks "$old_checks" --argjson new_checks "$new_checks" '
        if (.required_pull_request_reviews | type) == "object" then
          # Preserve existing required_approving_review_count if >= 1, otherwise set to 1
          .required_pull_request_reviews.required_approving_review_count = (
            if (.required_pull_request_reviews.required_approving_review_count // 0) >= 1
            then .required_pull_request_reviews.required_approving_review_count
            else 1
            end
          ) |
          # Always set dismiss_stale_reviews to true
          .required_pull_request_reviews.dismiss_stale_reviews = true
        else
          # Initialize with defaults if not present
          .required_pull_request_reviews = {
            "dismiss_stale_reviews": true,
            "required_approving_review_count": 1
          }
        end
      ' "${branch_protection_content}" > "${branch_protection_content}_tmp" && mv -f "${branch_protection_content}_tmp" "${branch_protection_content}"
      jq --arg context_prefix "$status_check_context_prefix" --argjson old_checks "$old_checks" --argjson new_checks "$new_checks" '.required_signatures=.required_signatures.enabled | .enforce_admins=.enforce_admins.enabled | .required_linear_history=.required_linear_history.enabled | .allow_force_pushes=.allow_force_pushes.enabled' "${branch_protection_content}" > "${branch_protection_content}_tmp" && mv -f "${branch_protection_content}_tmp" "${branch_protection_content}"
      jq --arg context_prefix "$status_check_context_prefix" --argjson old_checks "$old_checks" --argjson new_checks "$new_checks" '.allow_deletions=.allow_deletions.enabled | .block_creations=.block_creations.enabled | .required_conversation_resolution=.required_conversation_resolution.enabled | .lock_branch=.lock_branch.enabled | .allow_fork_syncing=.allow_fork_syncing.enabled' "${branch_protection_content}" > "${branch_protection_content}_tmp" && mv -f "${branch_protection_content}_tmp" "${branch_protection_content}"
      
      # Ensure required_status_checks has strict mode disabled and replace old checks with new checks
      # 1. Build array of old checks with prefix
      # 2. Remove old checks from existing contexts
      # 3. Add new checks with prefix to contexts
      # 4. Keep contexts unique
      # 5. Ensure strict mode is disabled (do not require branches to be up to date)
      jq --arg context_prefix "$status_check_context_prefix" --argjson old_checks "$old_checks" --argjson new_checks "$new_checks" '
        # Build old checks with prefix
        ($old_checks | map($context_prefix + "/" + .)) as $old_checks_with_prefix |
        # Build new checks with prefix - add prefix only to checks that do not start with a known custom prefix
        ($new_checks | map(
          if startswith("tekton-vpc-ci/") or startswith("tekton-") then .
          else $context_prefix + "/" + .
          end
        )) as $new_checks_with_prefix |
        # Remove old checks from existing contexts
        .required_status_checks.contexts = (.required_status_checks.contexts - $old_checks_with_prefix) |
        # Add new checks with prefix
        .required_status_checks.contexts += $new_checks_with_prefix |
        # Make unique
        .required_status_checks.contexts |= unique |
        # Ensure strict mode is disabled (do not require branches to be up to date before merging)
        .required_status_checks.strict = false
      ' "${branch_protection_content}" > "${branch_protection_content}_tmp" && mv -f "${branch_protection_content}_tmp" "${branch_protection_content}"
      
      # Ensure enforce_admins is set to true (do not allow bypassing settings)
      jq --arg context_prefix "$status_check_context_prefix" --argjson old_checks "$old_checks" --argjson new_checks "$new_checks" '
        .enforce_admins = true
      ' "${branch_protection_content}" > "${branch_protection_content}_tmp" && mv -f "${branch_protection_content}_tmp" "${branch_protection_content}"
    else
      # branch protection not set - initialize one with new checks and default settings
      jq -n --arg context_prefix "$status_check_context_prefix" --argjson new_checks "$new_checks" '
        # Build new checks with prefix - add prefix only to checks that do not start with a known custom prefix
        ($new_checks | map(
          if startswith("tekton-vpc-ci/") or startswith("tekton-") then .
          else $context_prefix + "/" + .
          end
        )) as $new_checks_with_prefix |
        # Set required pull request reviews with defaults
        .required_pull_request_reviews = {
          "dismiss_stale_reviews": true,
          "required_approving_review_count": 1
        } |
        # Do not allow bypassing settings
        .enforce_admins = true |
        .restrictions = null |
        # Require status checks to pass before merging with strict mode disabled (branches do not need to be up to date)
        .required_status_checks = {
          "strict": false,
          "contexts": $new_checks_with_prefix
        }
      ' > "$branch_protection_content"
    fi

    # update the branch protection
    disable_debug
    curl -L \
      -X PUT \
      -H "Authorization: Bearer $(cat ${APP_TOKEN_PATH})" \
      -H "Accept: application/vnd.github+json" \
      "${APP_API_URL}/repos/${APP_REPO_OWNER}/${APP_REPO_NAME}/branches/$branch/protection" \
      --data "@${branch_protection_content}"
    enable_debug
  fi
done < <(list_repos)