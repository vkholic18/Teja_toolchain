#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2019
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -u

if [[ $# -ne 1 ]]; then
	echo "usage: go-ast-scanning.sh workspace_dir"
	exit 1
fi
if [[ ! -d $1 ]]; then
	echo "workspace directory does not exist"
	exit 1
fi

WORKSPACE_REPO=$1

# Check if pipeline.yaml file exists
if [[ -f ${WORKSPACE_REPO}/hack/ci/pipeline.yaml ]]; then
	# Process only if go_ast_scan is defined and true
	GO_AST_SCAN=$(yq -r '.go_ast_scan| select(. != null)' ${WORKSPACE_REPO}/hack/ci/pipeline.yaml)
	if [[ ! -z "${GO_AST_SCAN}" ]] && [[ "${GO_AST_SCAN}" == "true" ]]; then
		echo "go_ast_scan enabled in ${WORKSPACE_REPO}/hack/ci/pipeline.yaml, processing ..."
		build_root="${PWD}"
		[[ ! -d metrics ]] && mkdir -p metrics
		pushd ${WORKSPACE_REPO}

		hash=$(git rev-parse --short=8 HEAD)
		comp=$(git remote get-url origin)
		comp=${comp##*/} # Strip off first part
		comp=${comp%.git*} # Strip off last part

		[[ ! -f .envrc ]] && echo "${WORKSPACE_REPO}/.envrc missing. Exiting ..." && exit 0
		source .envrc

		if [[ -d "src" ]]; then
			cd src
		fi

		timestamp=$(date +%Y%m%d-%H%M%S)
		results_path="${build_root}/metrics"
		results_file="gosec-${comp}-${hash}-${timestamp}.json"
		touch ${results_path}/${results_file}

		# Call gosec scanner
		gosec -fmt=json -out=${results_path}/${results_file} ./...
		echo "----------------------"

		# If the output file has contents, upload it to artifactory
		if [[ -s ${results_path}/${results_file} ]]; then
			curl --retry 5 --silent --output /dev/null --show-error --fail -X PUT -T "${results_path}/${results_file}" \
				-H "Authorization: Bearer ${CC_ARTIF_ACCESS_TOKEN}" \
				"${CC_ARTIFACTORY_HOST}/${CC_ARTIFACTORY_GENERIC_REPO_PATH}/go-ast-results/${comp}/${results_file}"
			rc=$?

			if [ $rc -ne 0 ]; then
				echo "ERROR: Could not upload scan results to artifactory. Return code = $rc"
				exit 1
			fi
			echo "Scan results uploaded to ${CC_ARTIFACTORY_HOST}/${CC_ARTIFACTORY_GENERIC_REPO_PATH}/go-ast-results/${comp}/${results_file}"

			# Determine if the scan failed or passed
			# Assuming success if nothing is returned in "Golang Errors" or "Issues" in the json response
			# This may need to be improved when we get the workspaces to opt-in and have some successful runs
			golang_errors=$(cat ${results_path}/${results_file} | jq '."Golang errors" | .[]')
			issues=$(cat ${results_path}/${results_file} | jq '.Issues[]')
			if [[ -z "${golang_errors}" ]] && [[ -z "${issues}" ]]; then
				echo "Scan successful"
			else
				echo "Gosec reported Golang Errors or Issues. Scan failed" && exit 1
			fi
		else
			echo "Scan successful, no results returned"
		fi
		popd
	else
		echo "go_ast_scan not enabled in ${WORKSPACE_REPO}/hack/ci/pipeline.yaml, exiting ..."
    fi
else
	echo "${WORKSPACE_REPO}/hack/ci/pipeline.yaml configuration does not exist, exiting ..."
fi
