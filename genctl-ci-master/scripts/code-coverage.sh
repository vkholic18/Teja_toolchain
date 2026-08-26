#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2019
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -eu

BYellow='\033[1;33m'
NC='\033[0m'
START=$(date +%s)

DIR_SOURCE=$1
DIR_COVERAGE=$2
DIR_OUTPUT=$3

mkdir -p $DIR_OUTPUT
# pr resource expects this file to exist and there are several execution paths below
# where we would exit before creating this file
echo "." > ${DIR_OUTPUT}/comment.txt

if [ $# -ne 3 ]; then
    echo "usage: code-coverage.sh source_dir coverage_dir ouput_dir" | tee ${DIR_OUTPUT}/comment.txt
    exit 1
fi

if [ ! -d $1 -o ! -d $2 ]; then
    echo 'Source or coverage directory does not exist' | tee ${DIR_OUTPUT}/comment.txt
    exit 1
fi

SKIP_FILE_NAME=hack/ci/codecoverage.skip
if [ -f ${DIR_SOURCE}/${SKIP_FILE_NAME} ]; then
	echo ${SKIP_FILE_NAME} file found - skipping code coverage
	exit 0
fi

reports=(${DIR_COVERAGE}/report*.txt)
if [ ! -f ${reports[0]} ]; then
    echo "No valid coverage reports exist in ${DIR_COVERAGE}" | tee ${DIR_OUTPUT}/comment.txt
    exit 1
fi

failed=false
for report in ${DIR_COVERAGE}/report*.txt; do
    echo -e "\nEvaluating ${report}\n"
    name=$(echo $report | sed 's/.*\/\(.*\).txt/\1/' | sed 's/report-\(.*\)$/\1/') # Extracts short name from report path
    if [ "$name" == "report" ]; then name=""; fi # If this is default report.txt file, set name to empty string

    threshold=""
    if [ -f ${DIR_COVERAGE}/coverageThreshold.config ]; then
        echo "Attempting to fetch threshold for ${name} report from coverageThreshold config file"
        echo "To update a code coverage threshold percentage modify src/test/unit_test/coverageThreshold.config config file"

        # Determine the name of the var in coverageThreshold.config we should look as based on report name
        if [ -n "$name" ]; then
            # If not the default report, prepend short name in all caps
            upper_name=$(tr '[a-z]' '[A-Z]' <<< $name) # converts name to all caps
            threshold_var="${upper_name}_REQUIRED_COVERAGE_PERCENT"
        else
            # If default report.txt, use default var
            threshold_var="REQUIRED_COVERAGE_PERCENT"
        fi

        # Grep coverageThreshold.config for the threshold percent
        threshold=$(grep "^$threshold_var" ${DIR_COVERAGE}/coverageThreshold.config | awk '{ print $2}' | tr -d '%')
    fi

    # Set the threshold to value in coverageThreshold.config otherwise set to default
    if [ ! -z "$threshold" ]; then
        echo "The threshold for code coverage tests is **${threshold}%**"
        REQUIRED_COVERAGE_PERCENT=$threshold
    else
        echo "Using default threshold: ${REQUIRED_COVERAGE_PERCENT}%"
    fi

    echo -e "\n--- ${name} Code Coverage Report ---"
    cat $report
    echo -e "\n------------------------------------------------------------------------------------------------------"

    percentage=$(
        grep -Eo 'Total coverage: [0-9]+(\.[0-9]+)?%' ${report} 2>/dev/null \
            | tail -1 \
            | grep -Eo '[0-9]+(\.[0-9]+)?' \
        || true
    )

    if [ -z "$percentage" ]; then
        percentage=$(
            awk '/^total:[[:space:]]+/ { gsub("%","",$NF); print $NF }' ${report} \
                | tail -1 \
            || true
        )
    fi

    if ! echo "$percentage" | grep -Eq '^[0-9]+(\.[0-9]+)?$'; then
        commit=$(cat ${DIR_SOURCE}/.git/head_sha 2> /dev/null || echo "unknown") # Find commit sha or set to 'unknown'
        fail_msg="Unable to determine code coverage percentage from ${report} for commit ${commit}"

        echo $fail_msg
        failed=true
        continue
    fi

    if (( $(echo "${percentage} >= ${REQUIRED_COVERAGE_PERCENT}" | bc -l ) )); then
        echo "Code coverage test PASSED with the percentage threshold of **${REQUIRED_COVERAGE_PERCENT}%**"

    else
        commit=$(cat ${DIR_SOURCE}/.git/head_sha 2> /dev/null || echo "unknown") # Find commit sha or set to 'unknown'
        fail_msg="Code coverage of **${percentage}%** falls below the required threshold of **${REQUIRED_COVERAGE_PERCENT}%** for commit ${commit}"

        echo $fail_msg

        {
            echo $fail_msg
            echo "\`\`\`"
            echo "--- ${name} Code Coverage Report for ${commit} ---"
            echo "$(cat $report)"
            echo -e "\`\`\`\n"
        } > ${DIR_OUTPUT}/comment.txt
        
        # This should truncate the comment.txt file
        content=$(cat < "${DIR_OUTPUT}/comment.txt" && echo .)
        content=${content%.}
        printf %s "${content:0:65500}" > "${DIR_OUTPUT}/comment.txt"

        failed=true
    fi
done
END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "${BYellow}Code Coverage took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete............. ${NC}"
if $failed; then exit 1; fi
