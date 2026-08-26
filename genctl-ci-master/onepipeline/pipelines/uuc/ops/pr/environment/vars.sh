#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Used in auto-merge ###
export APPROVE_BEFORE_MERGE="true"
export PR_NUMBER=$(get_env "PR_URL" | grep -o '[^/]*$')

export MERGE_METHOD="squash"

# Slack notification settings for auto-merge alerts
# SLACK_WEBHOOK_URL  — Incoming webhook URL (set in secrets.sh)
# SLACK_CHANNEL      — Target channel name, e.g. my-alerts (no # prefix needed)
# SLACK_TAG_GROUP    — Slack subteam/group ID to tag, e.g. S012345 (optional)
export SLACK_CHANNEL=$(get_env "slack-channel" "")
export SLACK_TAG_GROUP=$(get_env "slack-tag-group" "")
