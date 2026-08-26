#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# This script will query concourse to:
# 1.) get a list of pipelines
# 2.) get the latest build of each pipeline
# 3.) log each one older than 90/180 days
# 4.) export a summary of the results
#
# Assumptions: user is already logged into concourse (fly login) and target is named 'genctl'
#
# =============================================================================================

set -eu

FN_PIPE_AGES='/tmp/pipelines-ages.txt'
FN_PIPE_NO_DATA='/tmp/pipelines-no-data.txt'

if [[ -f ${FN_PIPE_AGES} ]]; then
    rm -f ${FN_PIPE_AGES}
fi

if [[ -f ${FN_PIPE_NO_DATA} ]]; then
    rm -f ${FN_PIPE_NO_DATA}
fi

PIPELINES=$(fly -t genctl pipelines | awk '{ print $1 }' | sort)
NOW=$(date +%s)

for pipeline in ${PIPELINES}; do

    LAST_RUN=$(fly -t genctl builds --pipeline "${pipeline}" | head -n 1 | awk '{ print $5 }')

    if [[ -z ${LAST_RUN} ]]; then
        echo "${pipeline}" >> /tmp/pipelines-no-data.txt
        continue
    fi

    EPOCH_LAST=$(date -j -f "%Y-%m-%d@%H:%M:%S%z" "${LAST_RUN}" +%s)

    SECS_IN_DAY=86400

    ELAPSED_SECS=$(( NOW - EPOCH_LAST ))

    if [[ ${ELAPSED_SECS} -ge ${SECS_IN_DAY} ]]; then
        DAYS_OLD=$(( ELAPSED_SECS / SECS_IN_DAY ))

        echo "pipeline: ${pipeline} is ${DAYS_OLD}" | tee -a ${FN_PIPE_AGES}
    fi
done

##
# work on summary data
##

PIPE_NO_DATA=$( cat ${FN_PIPE_NO_DATA} | wc -l | xargs )

OLDER_THAN_90=0
OLDER_THAN_180=0

PIPE_OLDER_THAN_90=()
PIPE_OLDER_THAN_180=()

while read -r pipe_line
do
    age=$(echo "${pipe_line}" | awk '{ print $4 }')
    pipeline=$(echo "${pipe_line}" | awk '{ print $2 }')

    if [[ ${age} -ge 90 ]]; then
        ((OLDER_THAN_90++))
        PIPE_OLDER_THAN_90+=("${pipeline}")

        if [[ ${age} -ge 180 ]]; then
            ((OLDER_THAN_180++))
            PIPE_OLDER_THAN_180+=("${pipeline}")
        fi
    fi
done < ${FN_PIPE_AGES}

echo "Pipeline Scan Summary"
echo "---------------------"
echo
echo "Pipelines older than 90 days"
echo "----------------------------"
for pipeline in "${PIPE_OLDER_THAN_90[@]}"; do
    echo "  ${pipeline}"
done
echo
echo "Pipelines older than 180 days"
echo "-----------------------------"
for pipeline in "${PIPE_OLDER_THAN_180[@]}"; do
    echo "  ${pipeline}"
done
echo
echo "Pipelines not built in more than 90 days  : ${OLDER_THAN_90}"
echo "Pipelines not built in more than 180 days : ${OLDER_THAN_180}"
echo "Pipelines with no data (pending/no builds): ${PIPE_NO_DATA}"
echo
