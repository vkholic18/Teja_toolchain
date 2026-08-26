#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

### Inherited from CI templates ###

### Used in to clone goldi-locks fresh ###
export GIT_PRIVATE_KEY=$(get_env ghe-private-key)
