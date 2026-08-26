#!/usr/bin/env bash
# =============================================================================
# terraform-review-preprocessor.sh
# Generates a token-optimised Markdown review input for BOB CLI.
#
# Design principles:
#   - Emit ONLY actionable changes (no-op entries are NEVER written to output)
#   - Use .address (full module path) to avoid duplicate logical names
#   - Emit actual field-level diffs for update actions (mask sensitive values)
#   - Mode flag drives scenario-specific categorical sections
#   - Target output: < 200 lines for a typical plan (vs 2000+ without filtering)
#
# Usage:
#   ./terraform-review-preprocessor.sh \
#       --plan        tfplan.json              \
#       --output      review_input.md          \
#       --mode        infrastructure|toolchain \
#       --workspace   "uuc-infra/observability" \
#       --environment production
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
PLAN_FILE="tfplan.json"
OUTPUT_FILE="review_input.md"
MODE="infrastructure"
WORKSPACE="unknown"
ENVIRONMENT="production"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan)        PLAN_FILE="$2";    shift 2 ;;
    --output)      OUTPUT_FILE="$2";  shift 2 ;;
    --mode)        MODE="$2";         shift 2 ;;
    --workspace)   WORKSPACE="$2";    shift 2 ;;
    --environment) ENVIRONMENT="$2";  shift 2 ;;
    *) echo "[ERROR] Unknown argument: $1"; exit 1 ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
    echo "[ERROR] jq is required but not found"; exit 1
fi
if [[ ! -f "$PLAN_FILE" ]]; then
    echo "[ERROR] Plan file not found: $PLAN_FILE"; exit 1
fi

# ── Helper: field-level diff for a single resource address ───────────────────
# Emits only fields that changed, masks any sensitive value.
# Skips computed-only fields that carry no user intent (id, crn, etag, href).
emit_field_diff() {
    local address="$1"
    jq -r --arg addr "$address" '
      .resource_changes[]
      | select(.address == $addr)
      | (.change.before        // {}) as $b
      | (.change.after         // {}) as $a
      | (.change.after_sensitive // {}) as $s
      | ([$b, $a] | map(keys) | add | unique[]) as $k
      | select(
            $b[$k] != $a[$k]
          and ($k | test("^(id|crn|etag|href|created_at|updated_at|version|resource_id|state)$") | not)
        )
      | if ($s[$k] == true) then
          "  \($k): \($b[$k] // "null") → [redacted]"
        else
          "  \($k): \($b[$k] // "null") → \($a[$k] // "null")"
        end
    ' "$PLAN_FILE" 2>/dev/null || true
}

# ── Count helpers (only actionable = not no-op) ───────────────────────────────
count_action() {
    # $1 = jq filter expression that selects resource_changes entries
    jq "[.resource_changes[] | $1] | length" "$PLAN_FILE"
}

CREATES=$(count_action 'select(.change.actions == ["create"])')
UPDATES=$(count_action 'select(.change.actions == ["update"])')
DELETES=$(count_action 'select(.change.actions == ["delete"])')
REPLACES=$(count_action 'select(.change.actions == ["delete","create"] or .change.actions == ["create","delete"])')
NOOPS=$(count_action   'select(.change.actions == ["no-op"])')
TOTAL=$(jq '.resource_changes | length' "$PLAN_FILE")
ACTIONABLE=$(( CREATES + UPDATES + DELETES + REPLACES ))

# ── Write output (single subshell → single file write) ───────────────────────
{

# ── Header block ─────────────────────────────────────────────────────────────
cat <<EOF
# Terraform Plan Review
**Workspace:** ${WORKSPACE} | **Environment:** ${ENVIRONMENT} | **Mode:** ${MODE} | **Date:** $(date -u '+%Y-%m-%dT%H:%M:%SZ')

## Plan Statistics
| Action | Count |
|--------|-------|
| Create | ${CREATES} |
| Update | ${UPDATES} |
| Delete | ${DELETES} |
| Replace | ${REPLACES} |
| No-op (skipped) | ${NOOPS} |
| **Actionable total** | **${ACTIONABLE}** |

EOF

# Early exit path: nothing to review
if [[ "$ACTIONABLE" -eq 0 ]]; then
    echo "_No actionable changes. Plan is a pure no-op._"
    exit 0
fi

# ── Section 1: Destructive operations (delete + replace) ─────────────────────
DEST_COUNT=$(( DELETES + REPLACES ))
echo "## Destructive Operations (${DEST_COUNT})"
echo ""
if [[ "$DEST_COUNT" -eq 0 ]]; then
    echo "_None._"
    echo ""
else
    while IFS= read -r address; do
        action=$(jq -r --arg a "$address" '.resource_changes[] | select(.address==$a) | .change.actions | join("+")' "$PLAN_FILE")
        echo "### \`${address}\` — ${action}"
        diff_out=$(emit_field_diff "$address")
        if [[ -n "$diff_out" ]]; then
            echo "Changed fields:"
            echo "$diff_out"
        fi
        echo ""
    done < <(jq -r '
        .resource_changes[]
        | select(.change.actions == ["delete"]
              or .change.actions == ["delete","create"]
              or .change.actions == ["create","delete"])
        | .address
    ' "$PLAN_FILE")
fi

# ── Section 2: Creates ────────────────────────────────────────────────────────
echo "## Creates (${CREATES})"
echo ""
if [[ "$CREATES" -eq 0 ]]; then
    echo "_None._"
    echo ""
else
    jq -r '.resource_changes[] | select(.change.actions == ["create"]) | "- `\(.address)`"' "$PLAN_FILE"
    echo ""
fi

# ── Section 3: Updates with field-level diff ──────────────────────────────────
echo "## Updates (${UPDATES})"
echo ""
if [[ "$UPDATES" -eq 0 ]]; then
    echo "_None._"
    echo ""
else
    while IFS= read -r address; do
        diff_out=$(emit_field_diff "$address")
        if [[ -n "$diff_out" ]]; then
            echo "### \`${address}\`"
            echo "$diff_out"
            echo ""
        else
            # Only emit the address — no diff means computed-only churn, low signal
            echo "- \`${address}\` (computed fields only — no user-intent change)"
        fi
    done < <(jq -r '.resource_changes[] | select(.change.actions == ["update"]) | .address' "$PLAN_FILE")
    echo ""
fi

# ── Section 4: IAM changes (active only) ─────────────────────────────────────
IAM_ACTIVE=$(jq '[.resource_changes[] | select(.type | test("iam|access_group|authorization_policy|custom_role")) | select(.change.actions != ["no-op"])] | length' "$PLAN_FILE")
echo "## IAM Changes (${IAM_ACTIVE} active)"
echo ""
if [[ "$IAM_ACTIVE" -eq 0 ]]; then
    echo "_No active IAM changes._"
    echo ""
else
    jq -r '
      .resource_changes[]
      | select(.type | test("iam|access_group|authorization_policy|custom_role"))
      | select(.change.actions != ["no-op"])
      | "- `\(.address)` — \(.change.actions | join("+"))"
    ' "$PLAN_FILE"
    echo ""
fi

# ── Section 5: Secrets Manager changes (active only) ─────────────────────────
SM_ACTIVE=$(jq '[.resource_changes[] | select(.type | test("secret|sm_")) | select(.change.actions != ["no-op"])] | length' "$PLAN_FILE")
echo "## Secrets Manager Changes (${SM_ACTIVE} active)"
echo ""
if [[ "$SM_ACTIVE" -eq 0 ]]; then
    echo "_No active Secrets Manager changes._"
    echo ""
else
    jq -r '
      .resource_changes[]
      | select(.type | test("secret|sm_"))
      | select(.change.actions != ["no-op"])
      | "- `\(.address)` — \(.change.actions | join("+"))"
    ' "$PLAN_FILE"
    echo ""
fi

# ── Section 6: Mode-specific sections ────────────────────────────────────────

if [[ "$MODE" == "infrastructure" ]]; then

    # Resource groups, COS, CD instances, resource instances
    INFRA_ACTIVE=$(jq '[.resource_changes[] | select(.type | test("ibm_resource_group|ibm_cos_bucket|ibm_resource_instance")) | select(.change.actions != ["no-op"])] | length' "$PLAN_FILE")
    echo "## Infrastructure Resource Changes (${INFRA_ACTIVE} active)"
    echo ""
    if [[ "$INFRA_ACTIVE" -eq 0 ]]; then
        echo "_None._"
        echo ""
    else
        jq -r '
          .resource_changes[]
          | select(.type | test("ibm_resource_group|ibm_cos_bucket|ibm_resource_instance"))
          | select(.change.actions != ["no-op"])
          | "- `\(.address)` — \(.change.actions | join("+"))"
        ' "$PLAN_FILE"
        echo ""
    fi

elif [[ "$MODE" == "toolchain" ]]; then

    # Triggers — highest blast radius
    TRIG_ACTIVE=$(jq '[.resource_changes[] | select(.type | test("tekton_pipeline_trigger$")) | select(.change.actions != ["no-op"])] | length' "$PLAN_FILE")
    echo "## Trigger Changes (${TRIG_ACTIVE} active)"
    echo ""
    if [[ "$TRIG_ACTIVE" -eq 0 ]]; then
        echo "_No trigger changes._"
        echo ""
    else
        while IFS= read -r address; do
            echo "### \`${address}\`"
            diff_out=$(emit_field_diff "$address")
            [[ -n "$diff_out" ]] && echo "$diff_out" || echo "  (diff unavailable)"
            echo ""
        done < <(jq -r '.resource_changes[] | select(.type | test("tekton_pipeline_trigger$")) | select(.change.actions != ["no-op"]) | .address' "$PLAN_FILE")
    fi

    # Pipeline properties
    PROP_ACTIVE=$(jq '[.resource_changes[] | select(.type == "ibm_cd_tekton_pipeline_property") | select(.change.actions != ["no-op"])] | length' "$PLAN_FILE")
    echo "## Pipeline Property Changes (${PROP_ACTIVE} active)"
    echo ""
    if [[ "$PROP_ACTIVE" -eq 0 ]]; then
        echo "_No pipeline property changes._"
        echo ""
    else
        while IFS= read -r address; do
            echo "### \`${address}\`"
            diff_out=$(emit_field_diff "$address")
            [[ -n "$diff_out" ]] && echo "$diff_out" || echo "  (computed only)"
            echo ""
        done < <(jq -r '.resource_changes[] | select(.type == "ibm_cd_tekton_pipeline_property") | select(.change.actions != ["no-op"]) | .address' "$PLAN_FILE")
    fi

    # Compliance definitions
    DEF_ACTIVE=$(jq '[.resource_changes[] | select(.type | test("tekton_pipeline_definition")) | select(.change.actions != ["no-op"])] | length' "$PLAN_FILE")
    echo "## Compliance Definition Changes (${DEF_ACTIVE} active)"
    echo ""
    if [[ "$DEF_ACTIVE" -eq 0 ]]; then
        echo "_No compliance definition changes._"
        echo ""
    else
        jq -r '
          .resource_changes[]
          | select(.type | test("tekton_pipeline_definition"))
          | select(.change.actions != ["no-op"])
          | "- `\(.address)` — \(.change.actions | join("+"))"
        ' "$PLAN_FILE"
        echo ""
    fi

    # Tool integrations
    TOOL_ACTIVE=$(jq '[.resource_changes[] | select(.type | test("ibm_cd_toolchain_tool_")) | select(.change.actions != ["no-op"])] | length' "$PLAN_FILE")
    echo "## Tool Integration Changes (${TOOL_ACTIVE} active)"
    echo ""
    if [[ "$TOOL_ACTIVE" -eq 0 ]]; then
        echo "_No tool integration changes._"
        echo ""
    else
        jq -r '
          .resource_changes[]
          | select(.type | test("ibm_cd_toolchain_tool_"))
          | select(.change.actions != ["no-op"])
          | "- `\(.address)` — \(.change.actions | join("+"))"
        ' "$PLAN_FILE"
        echo ""
    fi

    # Trigger property overrides
    TPROP_ACTIVE=$(jq '[.resource_changes[] | select(.type | test("tekton_pipeline_trigger_property")) | select(.change.actions != ["no-op"])] | length' "$PLAN_FILE")
    echo "## Trigger Property Override Changes (${TPROP_ACTIVE} active)"
    echo ""
    if [[ "$TPROP_ACTIVE" -eq 0 ]]; then
        echo "_No trigger property override changes._"
        echo ""
    else
        jq -r '
          .resource_changes[]
          | select(.type | test("tekton_pipeline_trigger_property"))
          | select(.change.actions != ["no-op"])
          | "- `\(.address)` — \(.change.actions | join("+"))"
        ' "$PLAN_FILE"
        echo ""
    fi

fi

# ── Section 7: Cost impact (active only) ──────────────────────────────────────
COST_ACTIVE=$(jq '[.resource_changes[] | select(.type == "ibm_resource_instance" or .type == "ibm_cos_bucket" or .type == "ibm_cd_toolchain") | select(.change.actions != ["no-op"])] | length' "$PLAN_FILE")
echo "## Cost Impact Resources (${COST_ACTIVE} active)"
echo ""
if [[ "$COST_ACTIVE" -eq 0 ]]; then
    echo "_No cost-impacting resource changes._"
    echo ""
else
    jq -r '
      .resource_changes[]
      | select(.type == "ibm_resource_instance" or .type == "ibm_cos_bucket" or .type == "ibm_cd_toolchain")
      | select(.change.actions != ["no-op"])
      | "- `\(.address)` — \(.change.actions | join("+"))"
    ' "$PLAN_FILE"
    echo ""
fi

echo "---"
echo "_Review input generated. Actionable changes: ${ACTIONABLE} of ${TOTAL} total resources._"

} > "${OUTPUT_FILE}"

echo "[OK] Generated ${OUTPUT_FILE} — $(wc -l < "${OUTPUT_FILE}") lines, $(wc -c < "${OUTPUT_FILE}") bytes"
echo "[INFO] Mode=${MODE} | Creates=${CREATES} | Updates=${UPDATES} | Deletes=${DELETES} | Replacements=${REPLACES} | Skipped no-ops=${NOOPS}"
