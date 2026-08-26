#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# max wait time in minutes for downstream merge pipelines
export MERGE_PIPELINE_TIMEOUT_MINS="360"
# seconds between Tekton polls for downstream merge pipelines
export MERGE_PIPELINE_POLL_INTERVAL_SECS="60"
# max wait time in minutes for downstream PR pipelines to merge
export PR_MONITOR_TIMEOUT_MINS="360"
# seconds between Tekton polls for downstream PR pipelines to merge
export PR_POLL_INTERVAL_SECS="60"
