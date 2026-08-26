#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# This script will query concourse to get a list of the pipelines and their ages.
# It will then delete the pipelines older than the requested/default retention threshold.
# It will also offer the user to delete pipelines which have no conclusive data from their latest build (aborted/pending)
#
# Assumptions: User is already logged into concourse (fly login)
#
# =============================================================================================

set -u

# Set some variables
fly_team="${1:-genctl}"
max_retention_period="${2:-30}"
pipelines_with_no_data='/tmp/pipelines-no-data.txt'
pipelines_with_data='/tmp/pipelines-data.txt'
count_older_than_max_retention=0
pipelines_older_than_max_retention=()

echo "Auto-backup of pipeline yamls to /tmp/backup_<pipeline_name>.yamls"
echo "Backing up is not obligatory and only retained for as long as the hosted system is running"

# Delete temporary files
[[ -f ${pipelines_with_no_data} ]] && rm -f ${pipelines_with_no_data}
[[ -f ${pipelines_with_data} ]] && rm -f ${pipelines_with_data}

function display_usage {
  echo "Make sure you are logged into concourse using the correct team name"
  echo
  echo "    Usage: ./delete-pipelines.sh <optional-cc-teamname> <optional-retention-threshold>"
  echo "    Example: ./delete-pipelines.sh   # (Default team = genctl, Default retention threshold = 30 days)"
  echo "    Example: ./delete-pipelines.sh pok_cc 60" 
}

all_pipelines=$(fly -t ${fly_team} pipelines | awk '{ print $1 }' | sort)
[[ -z ${all_pipelines} ]] && display_usage && exit 1
now=$(date +%s)

# Get pipelines and their ages
echo
echo "=========================== Pipelines and their ages (in days) ==========================="
for pipeline in ${all_pipelines}; do
    # Some aborted builds do not have a start timestamp
    last_build=$(fly -t ${fly_team} builds --pipeline "${pipeline}" | grep -vi "pending\|aborted" | head -n 1 | awk '{ print $5 }')
    if [[ -z ${last_build} ]]; then
        echo "${pipeline}" >> $pipelines_with_no_data
        continue
    fi
    epoch_last_build=$(date -j -f "%Y-%m-%d@%H:%M:%S%z" "${last_build}" +%s)
    secs_in_day=86400
    elapsed_secs=$(( now - epoch_last_build ))
    if [[ ${elapsed_secs} -ge ${secs_in_day} ]]; then
        days_old=$(( elapsed_secs / secs_in_day ))
        echo "${pipeline} ${days_old}" | tee -a ${pipelines_with_data}
    fi
done
echo "=========================================================================================="
echo

# Find which pipelines are older than the max threshold (default = 30 days)
while read -r pipe_line
do
    age=$(echo "${pipe_line}" | awk '{ print $2 }')
    pipeline=$(echo "${pipe_line}" | awk '{ print $1 }')

    if [[ ${age} -ge ${max_retention_period} ]]; then
        ((count_older_than_max_retention++))
        pipelines_older_than_max_retention+=("${pipeline}")
    fi
done < ${pipelines_with_data}

# Delete pipelines older than the threshold
echo "Following pipelines will be deleted"
echo
for pipeline in "${pipelines_older_than_max_retention[@]}"; do echo ${pipeline}; done
echo
read -t 10 -p "*** Hit Enter or wait 10s to continue. Ctrl-C to abort"
echo
echo "Continuing ..."
echo

for pipeline in "${pipelines_older_than_max_retention[@]}"; do
    
    # backup before delete. no need to save these for any length of time.
    fly -t $fly_team get-pipeline -p ${pipeline} > /tmp/backup_${pipeline}.yaml
    
    echo "Deleting ${pipeline}"
    fly -t $fly_team destroy-pipeline --non-interactive -p ${pipeline}
    echo
done

# Delete pipelines with no data from the latest build
echo "=========================================================================================="
echo
echo "Following pipelines have no timestamp data from the latest build"
echo
cat ${pipelines_with_no_data}
echo
read -p "Hit Enter to delete them or Ctrl-C to abort"
echo
echo "Continuing ..."
echo
while read -r pipeline
do
  echo "Deleting ${pipeline}"
  fly -t $fly_team destroy-pipeline --non-interactive -p ${pipeline}
  echo
done < ${pipelines_with_no_data}

echo "Done."