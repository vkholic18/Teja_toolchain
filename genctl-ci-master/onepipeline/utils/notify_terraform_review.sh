#!/usr/bin/env bash
# =============================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of
# its trade secrets, irrespective of what has been deposited with the U.S.
# Copyright Office.
# =============================================================================
#
# notify_terraform_review.sh
# Compatibility shim — delegates all arguments to notify_slack.sh.
#
# This script is preserved so that existing callers (terraform PR/merge
# pipelines, BOB review steps) continue to work without modification.
# New pipelines should call notify_slack.sh directly.
#
# All flags and environment variables are forwarded unchanged.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default notification-kind to terraform_review when not already set,
# so legacy callers that rely on that default keep their existing behaviour.
export SLACK_NOTIFICATION_KIND="${SLACK_NOTIFICATION_KIND:-terraform_review}"

exec bash "${SCRIPT_DIR}/notify_slack.sh" "$@"
