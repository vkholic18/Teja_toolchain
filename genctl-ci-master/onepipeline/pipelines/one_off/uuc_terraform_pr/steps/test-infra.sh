#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

set -euo pipefail

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# this script is internal to devsecops/baseimage image
source "${COMMONS_PATH}/terraform/terraform-utilities.sh"

# Set the pipeline template type
export PIPELINE_TYPE="pr"

# Move to the CI temp dir
pushd "${CI_TEMP_DIR}"

# Convert & source pipeline params and override
convert_and_source_pipeline_params_and_overrides "${PATH_TO_GENCTL_CI}" \
"${PIPELINE_REPO_NAME}" "${PIPELINE_TYPE}"

# Come back
popd

# remove previous terraform installation - new installation defaults to 1.2.9
# "${COMMONS_PATH}/terraform/terraform-utilities.sh" has a function called terraform_install
# this function install by default terraform 1.2.9, or uses environment variable called terraform-version
# the variable terraform-version is also set on the pipeline and defaults to 1.2.9 in case the original default changes
if which terraform; then
  echo "removing old terraform version"
  rm -f $(which terraform)
fi

terraform_version="$(get_env terraform-version "1.10.2")"

curl https://releases.hashicorp.com/terraform/$terraform_version/terraform_${terraform_version}_linux_amd64.zip -o terraform.zip
unzip -o terraform.zip
chmod +x terraform
mv terraform /usr/bin/

if command -v terraform &>/dev/null; then
  terraform version
else
  echo "Terraform is NOT installed."
  exit 1
fi
rm -rf terraform.zip
# prepare terraform context (tfvars & TF_VAR export)
set +u
terraform_tfvars_setup
terraform_env_export
echo "there are cocoa image issues that should be fixed above that require us to loosen checks"
set -u

# Set pipeline environment
PATH_TO_ENVIRONMENT_DIR="${PATH_TO_PIPELINE}/environment"

# Prepare pipeline environment
prepare_pipeline_environment "${PATH_TO_ENVIRONMENT_DIR}"

cd ${PATH_TO_WORKSPACE}

# setup artifactory backend creds
${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/setup_terraform.sh

# workspace_name is an alias for TF_WORKSPACE which is an environment variable used to pick backend workspace without using the CLI
echo "Selecting workspace name: $workspace_name"

# Set the SSH - needed for core module repo clone
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"
git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

# Pull common.auto.tfvars from main branch so all team branches share the same
# base variable values without duplicating them in every branch.
echo "------------------------ Fetching common.auto.tfvars from main ------------------------"
git show origin/main:common.auto.tfvars > "${PATH_TO_WORKSPACE}/common.auto.tfvars"

set +e
# running terraform init
echo "------------------------ Running: terraform init ------------------------"
terraform init && export INIT_STATUS="Success" || export INIT_STATUS="Failure"
echo "init status $INIT_STATUS"

export STATE_UNLOCK_ONLY=$(get_env "STATE_UNLOCK_ONLY")
if [[ ${STATE_UNLOCK_ONLY} -eq 1 ]]; then
    echo "Running state unlock only and exiting..."
    terraform force-unlock -force sys-wcp-genctl-team-1pl-tf-na-uuc-terraformbackend-local/tf-uuc-${workspace_name}
    exit 0
fi

echo "------------------------ Running: terraform output ------------------------"
terraform output

echo "------------------------ Running: terraform format and validate ------------------------"
terraform fmt -recursive -check -diff && export FMT_STATUS="Success" || export FMT_STATUS="Failure"
terraform validate -no-color && export VLDT_STATUS="Success" || export VLDT_STATUS="Failure"
echo "format status $FMT_STATUS, validate status $VLDT_STATUS"

echo "------------------------ Running: terraform plan ------------------------"
terraform plan -parallelism=3 -no-color -input=false -out ${PATH_TO_WORKSPACE}/plantf | tee ${PATH_TO_WORKSPACE}/plan_show.txt  && export PLAN_STATUS="Success" || export PLAN_STATUS="Failure"
echo "plan status $PLAN_STATUS"

set -e

# generate md5 from plan file
export MD5SUM=$(terraform show -no-color ${PATH_TO_WORKSPACE}/plantf | md5sum | cut -f 1 -d ' ')
echo "MD5 generated is: $MD5SUM"

# extract the plan summary line (e.g. "Plan: 28 to add, 0 to change, 0 to destroy.")
export PLAN_SUMMARY=$(grep -E '^Plan:' ${PATH_TO_WORKSPACE}/plan_show.txt || echo "Plan: N/A")
echo "Plan summary: $PLAN_SUMMARY"

echo "This is a PR pipeline, sending plan report"
python3 -m pip install -r ${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/requirements.txt
echo python3 ${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/add_comment.py -pn $PR_NUMBER
python3 ${PATH_TO_GENCTL_CI}/scripts/terraform_helper_funcs/add_comment.py -pn $PR_NUMBER

# =============================================================================
# BOB AI Review — Infrastructure mode
# Runs after plan + PR comment. Verdict drives auto-approval gate.
# Must execute while plantf binary still exists (terraform show -json reads it).
# =============================================================================
if [[ "$PLAN_STATUS" == "Success" ]]; then
    echo "------------------------ Running: BOB AI Review (infrastructure) ------------------------"

    UTILS_DIR="${PATH_TO_GENCTL_CI}/onepipeline/utils"
    BOB_REVIEW_INPUT="${PATH_TO_WORKSPACE}/review_input.md"
    BOB_REVIEW_OUTPUT="${PATH_TO_WORKSPACE}/bob_review_output.md"
    TF_PLAN_JSON="${PATH_TO_WORKSPACE}/tfplan.json"

    # Generate JSON plan for preprocessor (binary → JSON)
    terraform show -json "${PATH_TO_WORKSPACE}/plantf" > "${TF_PLAN_JSON}"

    # Run the token-optimised preprocessor in infrastructure mode
    bash "${UTILS_DIR}/terraform-review-preprocessor.sh" \
        --plan        "${TF_PLAN_JSON}" \
        --output      "${BOB_REVIEW_INPUT}" \
        --mode        infrastructure \
        --workspace   "${workspace_name}" \
        --environment "production"

    # Append the PR git diff so BOB can distinguish CODE_CHANGE from DRIFT_CANDIDATE.
    # Always diff origin/<base-branch>...origin/<head-branch> — fully resolved remote refs.
    # Using HEAD is wrong: the pipeline checks out a different branch than the PR source,
    # which pollutes the diff with unrelated commits from that branch.
    # OnePipeline PR trigger params: head-branch (source) and base-branch (target).
    _PR_BRANCH="$(get_env head-branch "")"
    _PR_BASEBRANCH="$(get_env base-branch "main")"
    echo "[BOB] --- Git diagnostics ---"
    echo "[BOB] PR branch: ${_PR_BRANCH} → base: ${_PR_BASEBRANCH}"
    echo "[BOB] Last 5 commits on origin/${_PR_BRANCH}:"
    git -C "${PATH_TO_WORKSPACE}" log --oneline "origin/${_PR_BRANCH}" -5 2>/dev/null || true
    echo "[BOB] Remote refs:"
    git -C "${PATH_TO_WORKSPACE}" branch -r 2>/dev/null | grep -E "${_PR_BASEBRANCH}|${_PR_BRANCH}|HEAD" | head -10 || true

    # Three-dot: commits on PR branch not reachable from base (pure PR changes only)
    _GIT_DIFF_FULL=$(git -C "${PATH_TO_WORKSPACE}" diff "origin/${_PR_BASEBRANCH}...origin/${_PR_BRANCH}" -- '*.tf' '*.tfvars' 2>/dev/null || true)
    if [[ -z "${_GIT_DIFF_FULL}" ]]; then
        echo "[BOB] Three-dot diff (origin/${_PR_BASEBRANCH}...origin/${_PR_BRANCH}) returned empty — trying two-dot"
        _GIT_DIFF_FULL=$(git -C "${PATH_TO_WORKSPACE}" diff "origin/${_PR_BASEBRANCH}..origin/${_PR_BRANCH}" -- '*.tf' '*.tfvars' 2>/dev/null || true)
    fi

    _DIFF_LINE_CAP=800
    _DIFF_TOTAL_LINES=$(echo "${_GIT_DIFF_FULL}" | wc -l)
    echo "[BOB] Full diff size: ${_DIFF_TOTAL_LINES} lines (cap: ${_DIFF_LINE_CAP})"

    if [[ -n "${_GIT_DIFF_FULL}" ]]; then
        GIT_DIFF_OUTPUT=$(echo "${_GIT_DIFF_FULL}" | head -${_DIFF_LINE_CAP})
        printf '\n## Git Diff (PR changes — source of truth for CODE_CHANGE classification)\n' >> "${BOB_REVIEW_INPUT}"
        if [[ "${_DIFF_TOTAL_LINES}" -gt "${_DIFF_LINE_CAP}" ]]; then
            printf '> ⚠️ **Diff truncated**: showing %d of %d lines. Entries not visible below may still exist in the PR — do NOT classify absent entries as DRIFT_CANDIDATE solely due to truncation.\n\n' \
                "${_DIFF_LINE_CAP}" "${_DIFF_TOTAL_LINES}" >> "${BOB_REVIEW_INPUT}"
            echo "[BOB] WARNING: Diff truncated — ${_DIFF_TOTAL_LINES} lines total, showing first ${_DIFF_LINE_CAP}"
        fi
        printf '```diff\n%s\n```\n' "${GIT_DIFF_OUTPUT}" >> "${BOB_REVIEW_INPUT}"
        echo "[BOB] Git diff appended: $(echo "${GIT_DIFF_OUTPUT}" | wc -l) lines"
    else
        printf '\n## Git Diff\n_No .tf or .tfvars changes detected in this PR._\n' >> "${BOB_REVIEW_INPUT}"
        echo "[BOB] WARNING: No git diff found for .tf/.tfvars files — BOB cannot verify CODE_CHANGE vs DRIFT."
    fi
    unset _GIT_DIFF_FULL _DIFF_TOTAL_LINES _DIFF_LINE_CAP _PR_BRANCH _PR_BASEBRANCH

    echo "[BOB] Review input: $(wc -l < "${BOB_REVIEW_INPUT}") lines"

    # ── No-op short-circuit ──────────────────────────────────────────────────
    ACTIONABLE=$(jq '[.resource_changes[] | select(.change.actions != ["no-op"])] | length' "${TF_PLAN_JSON}")
    echo "[BOB] Actionable resource changes: ${ACTIONABLE}"

    if [[ "${ACTIONABLE}" -eq 0 ]]; then
        echo "[BOB] Pure no-op plan — skipping AI review."
        export BOB_VERDICT="APPROVE"

        # Send Slack notification — no tagging on APPROVE (no-op plan, no human action needed)
        bash "${UTILS_DIR}/notify_terraform_review.sh" \
            --webhook-url    "${SLACK_WEBHOOK_URL:-}" \
            --channel        "${SLACK_CHANNEL:-}" \
            --verdict        "${BOB_VERDICT}" \
            --pr-url         "${PR_URL:+https://$(get_env GITHUB_API_URL | sed 's|https://||;s|/api/v3||')/${WORKSPACE_ORG}/${WORKSPACE_REPO}/pull/${PR_NUMBER}}" \
            --pipeline-url   "${PIPELINE_RUN_URL:-}" \
            --workspace      "${workspace_name}" \
            --mode           "infrastructure" \
            --pipeline-type  "PR" \
            --repo           "${WORKSPACE_REPO:-}" \
            --plan-summary   "${PLAN_SUMMARY:-}" || true

        echo "[BOB] Plan approved (no-op) — auto-merge may proceed."
    else
    # ── BOB AI review (plan has real changes) ────────────────────────────────

    # Auth — aligns with the pattern used in analyse_logs.sh on CION-2017.
    # BOBSHELL_API_KEY + BOBSHELL_BASE_URL are read by the BOB CLI when --auth-method api-key is set.
    # BOBSHELL_API_KEY is getting exported in secrets.sh file
    export BOBSHELL_BASE_URL="https://prod.ibm-bob-staging.cloud.ibm.com"

    # Invoke BOB CLI — stream-json format so we can extract both text and usage stats.
    # stderr is kept separate (bob_stderr.txt) so it never corrupts the JSON stream.
    BOB_STREAM="${PATH_TO_WORKSPACE}/bob_stream.jsonl"
    BOB_STDERR="${PATH_TO_WORKSPACE}/bob_stderr.txt"
    cat "${UTILS_DIR}/prompts/prompt_infrastructure.md" "${BOB_REVIEW_INPUT}" \
        | bob \
            --accept-license \
            --auth-method api-key \
            --hide-intermediary-output \
            --output-format stream-json \
        > "${BOB_STREAM}" 2>"${BOB_STDERR}" \
        && export BOB_STATUS="Success" || export BOB_STATUS="Failure"

    # Surface BOB stderr immediately so failures are diagnosable in pipeline logs
    if [[ -s "${BOB_STDERR}" ]]; then
        echo "[BOB] stderr output:"
        cat "${BOB_STDERR}"
    fi

    # Extract plain-text review output from the stream (attempt_completion result field)
    grep '^{' "${BOB_STREAM}" \
        | jq -r 'select(.type=="tool_use" and .tool_name=="attempt_completion") | .parameters.result' \
        2>/dev/null > "${BOB_REVIEW_OUTPUT}" || true

    # Extract usage stats from the final result line (grep filters out bare-text lines)
    BOB_TOTAL_TOKENS=$(grep '^{' "${BOB_STREAM}" | jq -r 'select(.type=="result") | .stats.total_tokens  | tostring' 2>/dev/null || true)
    BOB_COINS_THIS_RUN=$(grep '^{' "${BOB_STREAM}" | jq -r 'select(.type=="result") | .stats.session_costs | tostring' 2>/dev/null || true)
    BOB_COINS_SPENT=$(grep  '^{' "${BOB_STREAM}" | jq -r 'select(.type=="result") | .stats.budget_spend   | tostring' 2>/dev/null || true)
    BOB_COINS_BUDGET=$(grep '^{' "${BOB_STREAM}" | jq -r 'select(.type=="result") | .stats.max_budget     | tostring' 2>/dev/null || true)
    export BOB_TOTAL_TOKENS BOB_COINS_THIS_RUN BOB_COINS_SPENT BOB_COINS_BUDGET
    echo "[BOB] Review status: ${BOB_STATUS} | Tokens: ${BOB_TOTAL_TOKENS:-n/a} | This run: ${BOB_COINS_THIS_RUN:-n/a} coins | Total used: ${BOB_COINS_SPENT:-n/a} / ${BOB_COINS_BUDGET:-n/a}"

    # Extract the verdict (4-layer fallback, always produces APPROVE/NEEDS_REVIEW/BLOCK)
    BOB_VERDICT=$(bash "${UTILS_DIR}/extract_bob_verdict.sh" "${BOB_REVIEW_OUTPUT}") || true
    export BOB_VERDICT
    echo "[BOB] Verdict: ${BOB_VERDICT}"

    # Post BOB review as a PR comment (always fires, irrespective of verdict)
    if [[ -s "${BOB_REVIEW_OUTPUT}" ]]; then
        case "${BOB_VERDICT}" in
            APPROVE)      _VERDICT_BADGE="✅ **APPROVE**" ;;
            NEEDS_REVIEW) _VERDICT_BADGE="⚠️ **NEEDS_REVIEW**" ;;
            BLOCK)        _VERDICT_BADGE="🚫 **BLOCK**" ;;
            *)            _VERDICT_BADGE="❓ **${BOB_VERDICT}**" ;;
        esac
        _BOB_COMMENT_BODY="$(printf '##VERDICT_START##\nVERDICT: %s\n##VERDICT_END##\n\n## 🤖 BOB AI Terraform Review\n\n**Verdict:** %s | **Workspace:** `%s` | **Plan:** %s\n\n---\n\n%s' \
            "${BOB_VERDICT}" "${_VERDICT_BADGE}" "${workspace_name}" "${PLAN_SUMMARY:-N/A}" "$(cat "${BOB_REVIEW_OUTPUT}")")"
        _GH_API_BASE="$(get_env GITHUB_API_URL | sed 's|/$||')"
        curl -s -X POST \
            "${_GH_API_BASE}/repos/${WORKSPACE_ORG}/${WORKSPACE_REPO}/issues/${PR_NUMBER}/comments" \
            -H "Authorization: Bearer ${GITHUB_API_KEY}" \
            -H "Content-Type: application/json" \
            --data "$(jq -n --arg body "${_BOB_COMMENT_BODY}" '{"body": $body}')" \
            -o /dev/null && echo "[BOB] Review posted as PR comment." \
            || echo "[BOB] WARNING: Failed to post review as PR comment (non-fatal)."
    else
        echo "[BOB] No review output to post as PR comment."
    fi

    # Send Slack notification (always fires, irrespective of verdict).
    # Only tag the group when BOB verdict is not APPROVE — APPROVE means no human action needed.
    _SLACK_REVIEW_BODY=""
    [[ "${BOB_STATUS:-}" == "Success" ]] && _SLACK_REVIEW_BODY="$(cat "${BOB_REVIEW_OUTPUT}" 2>/dev/null || true)"
    _NOTIFY_TAG_ARG=()
    [[ "${BOB_VERDICT}" != "APPROVE" ]] && _NOTIFY_TAG_ARG=(--tag-group "${SLACK_TAG_GROUP:-}")
    bash "${UTILS_DIR}/notify_terraform_review.sh" \
        --webhook-url    "${SLACK_WEBHOOK_URL:-}" \
        --channel        "${SLACK_CHANNEL:-}" \
        --verdict        "${BOB_VERDICT}" \
        --pr-url         "${PR_URL:+https://$(get_env GITHUB_API_URL | sed 's|https://||;s|/api/v3||')/${WORKSPACE_ORG}/${WORKSPACE_REPO}/pull/${PR_NUMBER}}" \
        --pipeline-url   "${PIPELINE_RUN_URL:-}" \
        "${_NOTIFY_TAG_ARG[@]}" \
        --workspace      "${workspace_name}" \
        --mode           "infrastructure" \
        --pipeline-type  "PR" \
        --repo           "${WORKSPACE_REPO:-}" \
        --plan-summary   "${PLAN_SUMMARY:-}" \
        --review-body    "${_SLACK_REVIEW_BODY}" \
        --tokens         "${BOB_TOTAL_TOKENS:-}" \
        --coins-this     "${BOB_COINS_THIS_RUN:-}" \
        --coins-spent    "${BOB_COINS_SPENT:-}" \
        --coins-budget   "${BOB_COINS_BUDGET:-}" || true   # non-fatal

    # Enforce the gate
    case "${BOB_VERDICT}" in
        APPROVE)
            echo "[BOB] Plan approved — auto-merge may proceed."
            ;;
        NEEDS_REVIEW)
            echo "[BOB] Human review recommended — see PR comment. Pipeline continues."
            echo "[BOB] See PR comment for full BOB review."
            # Warning only — does not block the pipeline.
            # BOB review and Slack notification have already been posted above.
            ;;
        BLOCK)
            echo "[BOB] Plan flagged BLOCK by AI review — see PR comment. Pipeline continues."
            echo "[BOB] See PR comment for full BOB review."
            # Warning only — does not block the pipeline.
            # BOB review and Slack notification have already been posted above.
            ;;
    esac
    fi  # end ACTIONABLE > 0 branch

    # Persist verdict for the release stage auto-merge step
    set_env "bob-verdict" "${BOB_VERDICT}"
    echo "[BOB] Verdict persisted to pipeline env: ${BOB_VERDICT}"
else
    echo "[BOB] Skipping AI review — plan did not succeed."
fi

unset artifactory_token
rm -f "${TF_PLAN_JSON:-}" "${BOB_REVIEW_INPUT:-}" "${BOB_REVIEW_OUTPUT:-}" "${BOB_STREAM:-}" "${BOB_STDERR:-}"
rm -f ${PATH_TO_WORKSPACE}/plantf
rm -f ~/.terraform.d/credentials.tfrc.json

# cleanup
if [[ $PLAN_STATUS = "Failure" || $VLDT_STATUS = "Failure" || $INIT_STATUS = "Failure" || $FMT_STATUS = "Failure" ]]; then
  echo "Preliminary checks failed, exiting..."

  exit 1
fi