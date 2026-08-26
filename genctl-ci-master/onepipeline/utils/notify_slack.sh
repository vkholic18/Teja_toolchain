#!/usr/bin/env bash
# =============================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of
# its trade secrets, irrespective of what has been deposited with the U.S.
# Copyright Office.
# =============================================================================
#
# notify_slack.sh
# Generic CI/CD Slack notification script.
# Posts a pipeline status notification to a Slack channel via Incoming Webhook.
# No go-notify, no SLACK_DIR state required.
# Works with any channel in the same Slack workspace as the webhook URL.
#
# Usage:
#   ./notify_slack.sh [OPTIONS]
#
# Required inputs (flag OR environment variable):
#   --webhook-url  URL    Slack incoming webhook URL        (or SLACK_WEBHOOK_URL)
#   --channel      NAME   Slack channel name, e.g. #alerts  (or SLACK_CHANNEL)
#
# Optional inputs:
#   --verdict      VALUE  APPROVE | NEEDS_REVIEW | BLOCK | SUCCESS | FAILURE | INFO
#                                                            (or BOB_VERDICT)
#   --pr-url       URL    Pull request URL                   (or PR_URL)
#   --pipeline-url URL    Tekton pipeline run URL            (or PIPELINE_RUN_URL)
#   --tag-group    ID     Slack group/team ID(s) to tag, space or comma separated
#                         e.g. "S012345" or "U0408DJ8K7D,S012345" (or SLACK_TAG_GROUP)
#   --mode         VALUE  Any free-text pipeline context label, e.g.:
#                           infrastructure | toolchain | onboarding | deploy | <custom>
#                         Displayed in the header and Mode field.  (or REVIEW_MODE)
#   --title        TEXT   Override the full Slack header title. When set, --mode
#                         is ignored for the header (but still shown in the fields).
#                         e.g. "My Pipeline · PR Check"       (or SLACK_TITLE)
#   --repo         NAME   Repository or branch name           (or WORKSPACE_REPO)
#   --workspace    NAME   Workspace / environment name        (or workspace_name)
#   --pipeline-type VALUE PR | Merge | Deploy | <custom>      (or PIPELINE_TYPE)
#   --plan-summary TEXT   One-line summary, e.g. "Plan: 2 to add" (or PLAN_SUMMARY)
#   --review-body  TEXT   Structured body text (BOB review format or plain REASON:
#                         text). Parsed into named Slack sections.  (or BOB_REVIEW_BODY)
#   --notification-kind VALUE
#                         terraform_review | follow_up_prs | generic (default: generic)
#                                                            (or SLACK_NOTIFICATION_KIND)
#   --tokens       NUM    Total tokens consumed by BOB        (or BOB_TOKENS)
#   --coins-this   NUM    BOB coins spent on this run only    (or BOB_COINS_THIS_RUN)
#   --coins-total  NUM    BOB cumulative coins spent          (or BOB_COINS_SPENT)
#   --coins-budget NUM    BOB total coin budget               (or BOB_COINS_BUDGET)
# =============================================================================

set -euo pipefail

# ── Defaults from environment ─────────────────────────────────────────────────
WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
CHANNEL="${SLACK_CHANNEL:-}"
VERDICT="${BOB_VERDICT:-N/A}"
PR_URL="${PR_URL:-N/A}"
PIPELINE_URL="${PIPELINE_RUN_URL:-N/A}"
TAG_GROUP="${SLACK_TAG_GROUP:-}"
WORKSPACE_LABEL="${workspace_name:-N/A}"
MODE="${REVIEW_MODE:-N/A}"
TITLE="${SLACK_TITLE:-}"
REPO="${WORKSPACE_REPO:-N/A}"
PLAN_SUMMARY="${PLAN_SUMMARY:-N/A}"
REVIEW_BODY="${BOB_REVIEW_BODY:-}"
TOKENS="${BOB_TOKENS:-}"
COINS_THIS_RUN="${BOB_COINS_THIS_RUN:-}"
COINS_SPENT="${BOB_COINS_SPENT:-}"
COINS_BUDGET="${BOB_COINS_BUDGET:-}"
PIPELINE_TYPE="${PIPELINE_TYPE:-}"
NOTIFICATION_KIND="${SLACK_NOTIFICATION_KIND:-generic}"

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --webhook-url)       WEBHOOK_URL="$2";       shift 2 ;;
    --channel)           CHANNEL="$2";           shift 2 ;;
    --verdict)           VERDICT="$2";           shift 2 ;;
    --pr-url)            PR_URL="$2";            shift 2 ;;
    --pipeline-url)      PIPELINE_URL="$2";      shift 2 ;;
    --tag-group)         TAG_GROUP="$2";         shift 2 ;;
    --workspace)         WORKSPACE_LABEL="$2";   shift 2 ;;
    --mode)              MODE="$2";              shift 2 ;;
    --title)             TITLE="$2";             shift 2 ;;
    --repo)              REPO="$2";              shift 2 ;;
    --plan-summary)      PLAN_SUMMARY="$2";      shift 2 ;;
    --review-body)       REVIEW_BODY="$2";       shift 2 ;;
    --tokens)            TOKENS="$2";            shift 2 ;;
    --coins-this)        COINS_THIS_RUN="$2";    shift 2 ;;
    --coins-spent)       COINS_SPENT="$2";       shift 2 ;;
    --coins-budget)      COINS_BUDGET="$2";      shift 2 ;;
    --pipeline-type)     PIPELINE_TYPE="$2";     shift 2 ;;
    --notification-kind) NOTIFICATION_KIND="$2"; shift 2 ;;
    *) echo "[ERROR] Unknown argument: $1"; exit 1 ;;
  esac
done

# ── Validate truly required inputs (webhook + channel only) ──────────────────
MISSING=()
[[ -z "$WEBHOOK_URL" ]] && MISSING+=("--webhook-url / SLACK_WEBHOOK_URL")
[[ -z "$CHANNEL"     ]] && MISSING+=("--channel / SLACK_CHANNEL")

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "[ERROR] Missing required inputs:"
    for m in "${MISSING[@]}"; do echo "  - $m"; done
    exit 1
fi

# Apply N/A defaults for optional display fields after flag parsing
[[ -z "$VERDICT"         ]] && VERDICT="N/A"
[[ -z "$PR_URL"          ]] && PR_URL="N/A"
[[ -z "$PIPELINE_URL"    ]] && PIPELINE_URL="N/A"
[[ -z "$WORKSPACE_LABEL" ]] && WORKSPACE_LABEL="N/A"
[[ -z "$MODE"            ]] && MODE="N/A"
[[ -z "$REPO"            ]] && REPO="N/A"
[[ -z "$PLAN_SUMMARY"    ]] && PLAN_SUMMARY="N/A"

# Normalise channel: ensure it starts with # for display, strip it for the API
CHANNEL_DISPLAY="#${CHANNEL##\#}"
CHANNEL_API="${CHANNEL##\#}"

# ── Verdict → colour, icon, label ────────────────────────────────────────────
case "$VERDICT" in
    APPROVE)
        COLOR="#2eb886"          # Slack green
        ICON=":white_check_mark:"
        VERDICT_LABEL="APPROVED"
        ;;
    NEEDS_REVIEW)
        COLOR="#f0a500"          # Slack amber
        ICON=":warning:"
        VERDICT_LABEL="NEEDS REVIEW"
        ;;
    BLOCK)
        COLOR="#e01e5a"          # Slack red
        ICON=":no_entry:"
        VERDICT_LABEL="BLOCKED"
        ;;
    SUCCESS)
        COLOR="#2eb886"          # Slack green
        ICON=":white_check_mark:"
        VERDICT_LABEL="SUCCESS"
        ;;
    FAILURE)
        COLOR="#e01e5a"          # Slack red
        ICON=":no_entry:"
        VERDICT_LABEL="FAILURE"
        ;;
    INFO)
        COLOR="#3b82d4"          # Slack blue
        ICON=":information_source:"
        VERDICT_LABEL="INFO"
        ;;
    N/A)
        COLOR="#cccccc"
        ICON=":information_source:"
        VERDICT_LABEL="N/A"
        ;;
    *)
        COLOR="#cccccc"
        ICON=":question:"
        VERDICT_LABEL="UNKNOWN (${VERDICT})"
        ;;
esac

# ── Build the header title ────────────────────────────────────────────────────
# If --title is provided it wins outright.
# Otherwise compose from --mode + --pipeline-type in the UUC convention:
#   "UUC <Mode Label> · <Pipeline Type>"
# Known mode values get a clean display label; any other free-text value is
# title-cased and prefixed with "UUC" so custom modes look consistent.
if [[ -n "$TITLE" ]]; then
    HEADER_TITLE="${TITLE}  ${ICON}  ${VERDICT_LABEL}"
else
    # Mode → display label
    case "$MODE" in
        infrastructure) _MODE_LABEL="UUC Infrastructure" ;;
        toolchain)      _MODE_LABEL="UUC Toolchain"      ;;
        onboarding)     _MODE_LABEL="UUC Onboarding"     ;;
        terraform)      _MODE_LABEL="UUC Terraform"      ;;
        deploy)         _MODE_LABEL="UUC Deploy"         ;;
        N/A|"")         _MODE_LABEL="UUC CI/CD"          ;;
        *)              _MODE_LABEL="UUC $(echo "${MODE:0:1}" | tr '[:lower:]' '[:upper:]')${MODE:1}" ;;
    esac

    # Pipeline type → suffix
    case "$PIPELINE_TYPE" in
        PR)     _TYPE_SUFFIX=" \u00b7 PR Review"   ;;
        Merge)  _TYPE_SUFFIX=" \u00b7 Merge Apply" ;;
        Deploy) _TYPE_SUFFIX=" \u00b7 Deploy"      ;;
        "")     _TYPE_SUFFIX=""                    ;;
        *)      _TYPE_SUFFIX=" \u00b7 ${PIPELINE_TYPE}" ;;
    esac

    HEADER_TITLE="${_MODE_LABEL}${_TYPE_SUFFIX}  ${ICON}  ${VERDICT_LABEL}"
fi

# ── Tag line: supports multiple IDs/groups, space or comma separated ─────────
# User ID    (U...) → <@U...>           individual mention
# Subteam ID (S...) → <!subteam^S...>   group/team mention
# e.g. SLACK_TAG_GROUP="U0408DJ8K7D S012345,U999999"
TAG_LINE=""
if [[ -n "$TAG_GROUP" ]]; then
    IFS=' ,' read -ra _TAG_IDS <<< "${TAG_GROUP//,/ }"
    _MENTIONS=""
    for _id in "${_TAG_IDS[@]}"; do
        [[ -z "$_id" ]] && continue
        if [[ "$_id" == U* ]]; then
            _MENTIONS="${_MENTIONS} <@${_id}>"
        else
            _MENTIONS="${_MENTIONS} <!subteam^${_id}>"
        fi
    done
    _MENTIONS="${_MENTIONS# }"
    [[ -n "$_MENTIONS" ]] && TAG_LINE="${_MENTIONS} — please review"
fi

# ── Parse review body into named sections → individual Slack blocks ───────────
# Supports the structured BOB review format (REASON / RISK TABLE / FINDINGS /
# COMPLIANCE IMPACT / JUSTIFY BEFORE APPLY / SAFE) as well as plain free-text
# passed as a bare REASON: prefix or no prefix at all.
# Any section still longer than 2900 chars is sub-chunked to stay within
# Slack's block text limit.
CHUNK_SIZE=2900
REVIEW_CHUNKS_JSON="[]"

_slack_section() {
    local heading="$1" content="$2" text="" remaining=""
    if [[ -n "$heading" ]]; then
        text="${heading}"$'\n'
    fi
    text="${text}${content}"
    remaining="$text"
    local first_sub=true
    while [[ -n "$remaining" ]]; do
        local piece="${remaining:0:${CHUNK_SIZE}}"
        remaining="${remaining:${CHUNK_SIZE}}"
        if [[ "$first_sub" == "true" ]]; then
            first_sub=false
        else
            piece="_(continued)_"$'\n'"${piece}"
        fi
        REVIEW_CHUNKS_JSON=$(printf '%s' "$REVIEW_CHUNKS_JSON" \
            | jq --arg t "$piece" \
                '. + [{"type":"section","text":{"type":"mrkdwn","text":$t}}]')
    done
}

_fmt_severity() {
    printf '%s' "$1" | python3 -c "
import sys, re
text = sys.stdin.read()
rules = [
    (r'\*{0,3}\[CRITICAL\]\*{0,3}', ':rotating_light: *CRITICAL*'),
    (r'\*{0,3}\[HIGH\]\*{0,3}',     ':warning: *HIGH*'),
    (r'\*{0,3}\[MEDIUM\]\*{0,3}',   ':large_yellow_circle: *MEDIUM*'),
    (r'\*{0,3}\[LOW\]\*{0,3}',      ':large_blue_circle: *LOW*'),
    (r'\*{0,3}\[NONE\]\*{0,3}',     ':white_check_mark: *NONE*'),
]
for pattern, repl in rules:
    text = re.sub(pattern, repl, text)
print(text, end='')
"
}

_md_to_mrkdwn() {
    printf '%s' "$1" | python3 -c "
import sys, re
text = sys.stdin.read()
text = re.sub(r'\*{3}([^*]+)\*{3}', r'*\1*', text)
text = re.sub(r'\*{2}([^*]+)\*{2}', r'*\1*', text)
print(text, end='')
"
}

if [[ -n "$REVIEW_BODY" ]]; then
    # Strip the machine-readable verdict block
    body=$(printf '%s' "$REVIEW_BODY" \
        | sed '/^##VERDICT_START##$/,/^##VERDICT_END##$/d' \
        | sed '/^```$/d')

    declare -A SECTIONS
    current_section="REASON"
    current_content=""
    _body_tmp=$(mktemp)
    printf '%s' "$body" > "$_body_tmp"
    while IFS= read -r line; do
        case "$line" in
            "RISK TABLE"|"CHANGE CLASSIFICATION"|"FINDINGS"|"COMPLIANCE IMPACT"|"JUSTIFY BEFORE APPLY"|"SAFE")
                SECTIONS["$current_section"]="$current_content"
                current_section="$line"; current_content="" ;;
            "RAISED PRS"|"SKIPPED BRANCHES")
                if [[ "$NOTIFICATION_KIND" == "follow_up_prs" ]]; then
                    SECTIONS["$current_section"]="$current_content"
                    current_section="$line"; current_content=""
                else
                    current_content="${current_content}${line}"$'\n'
                fi ;;
            *)
                current_content="${current_content}${line}"$'\n' ;;
        esac
    done < "$_body_tmp"
    rm -f "$_body_tmp"
    SECTIONS["$current_section"]="$current_content"

    REVIEW_CHUNKS_JSON=$(printf '%s' "$REVIEW_CHUNKS_JSON" \
        | jq '. + [{"type":"divider"}]')

    _trim() { printf '%s' "$1" | awk 'NF{found=1} found{print}' | awk '{lines[NR]=$0} NF{last=NR} END{for(i=1;i<=last;i++) print lines[i]}'; }

    reason_text=$(_trim "${SECTIONS[REASON]:-}")
    reason_text=$(printf '%s' "$reason_text" | sed 's/^REASON:[[:space:]]*//')
    reason_text=$(_trim "$reason_text")
    if [[ "$NOTIFICATION_KIND" != "follow_up_prs" ]] && [[ -n "${reason_text// }" ]]; then
        _slack_section ":memo: *Reason*" "$reason_text"
    fi

    risk_text=$(_trim "${SECTIONS[RISK TABLE]:-}")
    if [[ -n "${risk_text// }" ]]; then
        _slack_section ":bar_chart: *Risk Table*" $'```\n'"${risk_text}"$'\n```'
    fi

    cc_text=$(_trim "${SECTIONS[CHANGE CLASSIFICATION]:-}")
    cc_text=$(_md_to_mrkdwn "$cc_text")
    if [[ "$NOTIFICATION_KIND" != "follow_up_prs" ]] && [[ -n "${cc_text// }" ]]; then
        _slack_section ":label: *Change Classification*" "$cc_text"
    fi

    findings_text=$(_trim "${SECTIONS[FINDINGS]:-}")
    findings_text=$(_md_to_mrkdwn "$findings_text")
    findings_text=$(_fmt_severity "$findings_text")
    if [[ -n "${findings_text// }" ]]; then
        _slack_section ":mag: *Findings*" "$findings_text"
    fi

    if [[ "$NOTIFICATION_KIND" == "follow_up_prs" ]]; then
        raised_prs_text=$(printf '%s' "${SECTIONS[RAISED PRS]:-}" | sed '/^_END_OF_RAISED_PRS_$/d')
        raised_prs_text=$(_md_to_mrkdwn "$raised_prs_text")
        raised_prs_text+=$'\n'
        if [[ -n "${raised_prs_text// }" ]]; then
            _slack_section ":git: *Raised PRs*" "$raised_prs_text"
        fi

        skipped_branches_text=$(_trim "${SECTIONS[SKIPPED BRANCHES]:-}")
        skipped_branches_text=$(_md_to_mrkdwn "$skipped_branches_text")
        if [[ -n "${skipped_branches_text// }" ]]; then
            _slack_section ":fast_forward: *Skipped Branches*" "$skipped_branches_text"
        fi
    fi

    ci_text=$(_trim "${SECTIONS[COMPLIANCE IMPACT]:-}")
    ci_text=$(_md_to_mrkdwn "$ci_text")
    if [[ -n "${ci_text// }" ]]; then
        _slack_section ":shield: *Compliance Impact*" "$ci_text"
    fi

    jba_text=$(_trim "${SECTIONS[JUSTIFY BEFORE APPLY]:-}")
    jba_text=$(_md_to_mrkdwn "$jba_text")
    if [[ -n "${jba_text// }" ]]; then
        _slack_section ":pencil: *Justify Before Apply*" "$jba_text"
    fi

    safe_text=$(_trim "${SECTIONS[SAFE]:-}")
    safe_text=$(_md_to_mrkdwn "$safe_text")
    if [[ -n "${safe_text// }" ]]; then
        _slack_section ":white_check_mark: *Safe Changes*" "$safe_text"
    fi
fi

# ── Build Slack Block Kit payload ─────────────────────────────────────────────
if [[ "$NOTIFICATION_KIND" == "follow_up_prs" ]]; then
    PAYLOAD=$(jq -cn \
        --arg channel      "$CHANNEL_API" \
        --arg color        "$COLOR" \
        --arg icon         "$ICON" \
        --arg verdict      "$VERDICT_LABEL" \
        --arg header_title "$HEADER_TITLE" \
        --arg tag_line     "$TAG_LINE" \
        --arg repo         "$REPO" \
        --arg workspace    "$WORKSPACE_LABEL" \
        --arg pipe_url     "$PIPELINE_URL" \
        --arg plan_summary "$PLAN_SUMMARY" \
        --argjson review_chunks "$REVIEW_CHUNKS_JSON" \
    '{
        "channel": $channel,
        "attachments": [
            {
                "color": $color,
                "blocks": (
                    [
                    {
                        "type": "header",
                        "text": {
                            "type": "plain_text",
                            "text": $header_title,
                            "emoji": true
                        }
                    },
                    {
                        "type": "section",
                        "fields": [
                            {
                                "type": "mrkdwn",
                                "text": ("*Repository*\n`" + $repo + "`")
                            },
                            {
                                "type": "mrkdwn",
                                "text": ("*Workspace*\n`" + $workspace + "`")
                            },
                            {
                                "type": "mrkdwn",
                                "text": ("*Status*\n" + $icon + " *" + $verdict + "*")
                            }
                        ]
                    },
                    (if $plan_summary != "" and $plan_summary != "N/A" then
                        {
                            "type": "section",
                            "text": {
                                "type": "mrkdwn",
                                "text": ("*Summary*\n" + $plan_summary)
                            }
                        }
                    else
                        null
                    end)
                    ] +
                    $review_chunks +
                    [
                    {
                        "type": "actions",
                        "elements": ([
                            (if $pipe_url != "N/A" and $pipe_url != "" then
                            {
                                "type": "button",
                                "text": {
                                    "type": "plain_text",
                                    "text": ":pipeline: View Pipeline Run",
                                    "emoji": true
                                },
                                "url": $pipe_url,
                                "action_id": "view_pipeline"
                            } else null end)
                        ] | map(select(. != null)))
                    },
                    (if $tag_line != "" then
                        {
                            "type": "section",
                            "text": {
                                "type": "mrkdwn",
                                "text": $tag_line
                            }
                        }
                    else
                        null
                    end),
                    {
                        "type": "divider"
                    }
                    ] | map(select(. != null))
                )
            }
        ]
    }')
else
    PAYLOAD=$(jq -cn \
        --arg channel        "$CHANNEL_API" \
        --arg color          "$COLOR" \
        --arg icon           "$ICON" \
        --arg verdict        "$VERDICT_LABEL" \
        --arg header_title   "$HEADER_TITLE" \
        --arg tag_line       "$TAG_LINE" \
        --arg repo           "$REPO" \
        --arg workspace      "$WORKSPACE_LABEL" \
        --arg mode           "$MODE" \
        --arg pipeline_type  "$PIPELINE_TYPE" \
        --arg pr_url         "$PR_URL" \
        --arg pipe_url       "$PIPELINE_URL" \
        --arg plan_summary   "$PLAN_SUMMARY" \
        --arg tokens         "$TOKENS" \
        --arg coins_this_run "$COINS_THIS_RUN" \
        --arg coins_spent    "$COINS_SPENT" \
        --arg coins_budget   "$COINS_BUDGET" \
        --argjson review_chunks "$REVIEW_CHUNKS_JSON" \
    '{
        "channel": $channel,
        "attachments": [
            {
                "color": $color,
                "blocks": (
                    [
                    {
                        "type": "header",
                        "text": {
                            "type": "plain_text",
                            "text": $header_title,
                            "emoji": true
                        }
                    },
                    {
                        "type": "section",
                        "fields": (
                            [
                            (if $repo != "N/A" and $repo != "" then
                                {
                                    "type": "mrkdwn",
                                    "text": ("*Repository*\n`" + $repo + "`")
                                }
                            else null end),
                            (if $workspace != "N/A" and $workspace != "" then
                                {
                                    "type": "mrkdwn",
                                    "text": ("*Workspace*\n`" + $workspace + "`")
                                }
                            else null end),
                            (if $mode != "N/A" and $mode != "" then
                                {
                                    "type": "mrkdwn",
                                    "text": ("*Mode*\n`" + $mode + "`")
                                }
                            else null end),
                            {
                                "type": "mrkdwn",
                                "text": ("*Verdict*\n" + $icon + " *" + $verdict + "*")
                            },
                            (if $pipeline_type != "" then
                                {
                                    "type": "mrkdwn",
                                    "text": ("*Pipeline*\n`" + $pipeline_type + "`")
                                }
                            else null end)
                            ] | map(select(. != null))
                        )
                    },
                    (if $plan_summary != "" and $plan_summary != "N/A" then
                        {
                            "type": "section",
                            "text": {
                                "type": "mrkdwn",
                                "text": ("*Plan Summary*\n`" + $plan_summary + "`")
                            }
                        }
                    else
                        null
                    end)
                    ] +
                    $review_chunks +
                    [
                    (if $tokens != "" or $coins_this_run != "" then
                        {
                            "type": "context",
                            "elements": [
                                {
                                    "type": "mrkdwn",
                                    "text": (
                                        "*Tokens:* " + (if $tokens != "" then $tokens else "—" end) +
                                        "  |  *This run:* " + (if $coins_this_run != "" then $coins_this_run + " coins" else "—" end) +
                                        "  |  *Total used:* " + (if $coins_spent != "" then $coins_spent else "—" end) +
                                        (if $coins_budget != "" and $coins_spent != "" then "  |  *Remaining:* " + (($coins_budget | tonumber) - ($coins_spent | tonumber) | tostring) else "" end)
                                    )
                                }
                            ]
                        }
                    else
                        null
                    end),
                    {
                        "type": "actions",
                        "elements": ([
                            (if $pr_url != "N/A" and $pr_url != "" then
                            {
                                "type": "button",
                                "text": {
                                    "type": "plain_text",
                                    "text": ":git: View Pull Request",
                                    "emoji": true
                                },
                                "url": $pr_url,
                                "action_id": "view_pr"
                            } else null end),
                            (if $pipe_url != "N/A" and $pipe_url != "" then
                            {
                                "type": "button",
                                "text": {
                                    "type": "plain_text",
                                    "text": ":pipeline: View Pipeline Run",
                                    "emoji": true
                                },
                                "url": $pipe_url,
                                "action_id": "view_pipeline"
                            } else null end)
                        ] | map(select(. != null)))
                    },
                    (if $tag_line != "" then
                        {
                            "type": "section",
                            "text": {
                                "type": "mrkdwn",
                                "text": $tag_line
                            }
                        }
                    else
                        null
                    end),
                    {
                        "type": "divider"
                    }
                    ] | map(select(. != null))
                )
            }
        ]
    }')
fi

# ── Send to Slack ─────────────────────────────────────────────────────────────
echo "[SLACK] Posting verdict ${VERDICT} to ${CHANNEL_DISPLAY}..."

HTTP_STATUS=$(curl -s -o /tmp/slack_response.json -w "%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    --data "$PAYLOAD" \
    "$WEBHOOK_URL")

SLACK_RESPONSE=$(cat /tmp/slack_response.json 2>/dev/null || echo "")

if [[ "$HTTP_STATUS" == "200" ]] && [[ "$SLACK_RESPONSE" == "ok" ]]; then
    echo "[SLACK] Notification sent successfully to ${CHANNEL_DISPLAY} — verdict: ${VERDICT}"
    rm -f /tmp/slack_response.json
    exit 0
else
    echo "[ERROR] Slack notification failed."
    echo "[ERROR] HTTP status: ${HTTP_STATUS}"
    echo "[ERROR] Slack response: ${SLACK_RESPONSE}"
    rm -f /tmp/slack_response.json
    # Non-fatal: don't fail the pipeline because Slack is down
    exit 0
fi
