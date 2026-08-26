#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2020
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -u

function run_linter() {
    ##
    # run the golang linter and return the exit code
    ##
    local __deadline="$1"
    local __extra_advisory_args="$2"
    local __extra_lint_args="$3"
    local __packages_to_scan="$4"
    local __num_concurrency="$5"
    echo -e "\033[0;37mRunning advisory checks ...\033[m"
    golangci-lint run \
        --disable-all \
        --deadline="${__deadline}" \
        --enable=goimports \
        --enable=errcheck \
        --enable=deadcode \
        --enable=ineffassign \
        --enable=goconst  \
        --enable=staticcheck \
        --enable=vetshadow \
        --enable=gas \
        ${__extra_advisory_args} \
        ${__extra_lint_args} \
        --tests \
        --concurrency ${__num_concurrency} \
        --verbose ${__packages_to_scan}
    
    return $?
}
# By default we do NOT skip
# If want to skip, need to export this variable before calling this script
SKIP_GO_VETTING=${SKIP_GO_VETTING:="false"} 

if [[ "${SKIP_GO_VETTING}" == "true" ]]
then
    echo "Skipping go vetting..."
    exit 0
fi

START=$(date +%s)
if [ $# -ne 1 ]; then
    echo "usage: go-vetting.sh workspace_dir"
    echo
    echo "Environmental variables used:"
    echo " PACKAGES              directory for 'go list' (default 'github.ibm.com/...')"
    echo " DEADLINE              golangci-lint --deadline value (default '60m')"
    echo " EXTRA_MANDATORY_ARGS  extra arguments for first golangci-lint call"
    echo " EXTRA_ADVISORY_ARGS   extra arguments for the second golangci-lint call"
    echo " EXTRA_LINT_ARGS       extra arguments for both golangci-lint calls"
    echo " NUM_CONCURRENCY       number of concurrent proceses (numCPU)"
    exit 1
fi

if [[ ! -d "${1}" ]]; then
    echo "workspace directory needs to be passed as the first argument. $1 is not a valid directory"
    exit 1
else
    pushd "${1}" || exit 1
fi

# go setup env - exit if missing
if [[ ! -f .envrc ]]; then
    echo "#################################################"
    echo "# WARNING: .envrc file does not exist!"
    echo "# WARNING: Skipping go vetting scans"
    echo "#################################################"
    exit 0
fi

# enable sideload of go
# NOTE: These may be modified by .envrc
export GO_SIDELOAD_PATH=/root/go-lint/go
export PATH=${GO_SIDELOAD_PATH}/bin:${PATH}
export GOPATH=${GO_SIDELOAD_PATH}:${GOPATH}

# devs can control where their packages are located
source .envrc
echo "Running go version is: $(go version)"

git config --global --add url."git@github.ibm.com:".insteadOf "https://github.ibm.com"
eval "$(ssh-agent -s)"
ssh-add - <<< "${GIT_PRIVATE_KEY}"

# https://stackoverflow.com/questions/59144120/gopath-go-mod-exists-but-should-not-in-aws-elastic-beanstalk
# tldr; When GOPATH is set go get installs the requested module to the path provided in GOPATH but if you use .mod file, it uses the working directory.
if [[ -f "go.mod" ]]; then
    echo "go.mod exists unsetting GOPATH"
    unset GOPATH
fi

# get a list of paths that are also submodules to filter out of go list
# Must do this before we switch to src dir
if [ -f ".gitmodules" ]; then
    SKIP_PATHS_WITH_SUBMODULES=$(git config --file .gitmodules --name-only --get-regexp . | sed -nE 's/^submodule\.src\/(.*)\.path$/\1/pi')
fi

if [ -d "src/github.ibm.com" ]; then
    # this is for old-style repos, before go mods
    cd src || exit 1
    PACKAGES="github.ibm.com/..."
elif [[ -d "pkg" ]]; then
    PACKAGES="$PWD/pkg/..."
else
    PACKAGES="..."
fi

# set default values for used variables
PACKAGES=${PACKAGES:=github.ibm.com/...}
PACKAGES=${GO_PACKAGES_DIR:=${PACKAGES}} # devs ultimately control the path (by setting this in their .envrc file)
DEADLINE=${DEADLINE:=60m}
EXTRA_MANDATORY_ARGS=${EXTRA_MANDATORY_ARGS:=}
EXTRA_ADVISORY_ARGS=${EXTRA_ADVISORY_ARGS:=}
EXTRA_LINT_ARGS=${EXTRA_LINT_ARGS:=}
NUM_CONCURRENCY=${NUM_CONCURRENCY:=4}

# get a list of paths that are also submodules as we will filter these out of go list - do this before we switch to 'src' dir
SKIP_PATHS_WITH_SUBMODULES=$(git config --file .gitmodules --name-only --get-regexp . | sed -nE 's/^submodule\.src\/(.*)\.path$/\1/pi')

echo "Packages val passed: ${PACKAGES}"


if [[ ! -z "$SKIP_PATHS_WITH_SUBMODULES" ]]; then
    echo "Skipping submodule packages: ${SKIP_PATHS_WITH_SUBMODULES}"
    PACKAGES_TO_SCAN=$(go list ${PACKAGES} | grep -v -e "${SKIP_PATHS_WITH_SUBMODULES}")  
else
    PACKAGES_TO_SCAN=${PACKAGES}
fi

if [[ -z "$PACKAGES_TO_SCAN" ]]; then
    echo "There are no packages to scan - exiting."
    exit 0
fi

# echo -e "\033[0;37mRunning mandatory checks...\033[m"
# golangci-lint run \
# 	--disable-all \
# 	--deadline=${DEADLINE} \
# 	--enable=gofmt \
# 	--enable=goimports \
# 	--enable=vet \
# 	${EXTRA_MANDATORY_ARGS} \
# 	${EXTRA_LINT_ARGS} \
# 	--tests \
# 	--verbose ${PACKAGES_TO_SCAN}

# if [ "$?" -ne 0 ]; then
# 	echo "Mandatory checks have failed. exiting."
# 	# these will begin failing immediately
# 	# we can tweak them - or fix the code
# 	# --max-issues-per-linter int   Maximum issues count per one linter. Set to 0 to disable (default 50)
#     # --max-same-issues int         Maximum count of issues with the same text. Set to 0 to disable (default 3)
# 	#exit 1
# fi

run_linter "${DEADLINE}" "${EXTRA_ADVISORY_ARGS}" "${EXTRA_LINT_ARGS}" "${PACKAGES_TO_SCAN}" "${NUM_CONCURRENCY}"
result=$?

# related to cigc-335, if we receive ret code =3, there is a ~/root/.cache/go-build that gets built on the 1st
# execution and if you subsequently run the scan a second time, the linter will run as expected.
# 
# there are a number of issues related to "context loading failed" - the message you get when receiving ret code 3
# https://github.com/golangci/golangci-lint/issues/395
#
if [ "${result}" -eq 3 ]; then
    echo "restarting linter pertaining to issue: https://github.com/golangci/golangci-lint/issues/395"
    echo "and tracked on cigc-335"
    echo
    run_linter "${DEADLINE}" "${EXTRA_ADVISORY_ARGS}" "${EXTRA_LINT_ARGS}" "${PACKAGES_TO_SCAN}" "${NUM_CONCURRENCY}"
    result=$?
fi

if [ "${result}" -ne 0 ]; then
    echo "Advisory checks have failed. exiting."
    # these will begin failing immediately
    # we can tweak them - or fix the code
    # --max-issues-per-linter int   Maximum issues count per one linter. Set to 0 to disable (default 50)
    # --max-same-issues int         Maximum count of issues with the same text. Set to 0 to disable (default 3)
    #exit 1
fi

echo "Go checks have completed."

END=$(date +%s)
DIFF=$(( $END - $START ))
echo -e "\033[1;33mGo Vetting took `date -d@$DIFF -u +%Hh:%Mm:%Ss` to complete.............\033[0m"
# even if we cd'd into src, this returns us to the previous directory we were in
popd || exit 1
