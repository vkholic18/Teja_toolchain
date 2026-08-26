#!/bin/bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021, 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Description:
# Script to check if any files in the PR are not tidy. E.g. contain keys in the wrong order, drift from using definitions out of common_globals, etc.
# If a common_globals file changes, then all files using it are also checked.

function check_all() {
    # Check all of the .yaml files in a given directory.
    # The first argument is the directory to check.
    pushd $1 >/dev/null 2>&1
    for f in *.yaml; do
        [ ! -f "$f" ] && continue
        echo "checking $1/$f"
        python3 ../scripts/validate.py -f $f
    done
    popd >/dev/null 2>&1
}

function check_list() {
    # Check a list of .yaml files
    # The first argument is the list of files to check.
    list=$1
    for f in $list; do
        [ ! -f "$f" ] && continue
        echo "checking $f"
        python3 ./scripts/validate.py -f $f
    done
}

failure() {
    local lineno=$1
    local cmd=$2
    echo "Failed at $lineno: $cmd"
}


workspace_directory=$1
pushd ${workspace_directory} >/dev/null 2>&1


# Determine which files changed (so we can only check them)
git log --name-only --pretty="format:" origin/master..HEAD | sort -u > /tmp/changed

# Subdivide from that into json files and yaml globals files
# which we should check. Can ignore other files, e.g. python scripts.
egrep '\.json$' /tmp/changed | egrep -v '^dev-ve/' >/tmp/jsonchanged
egrep '^dev.*\.yaml$|^integ.*\.yaml$|^stag.*\.yaml$|^prod.*\.yaml$' /tmp/changed >/tmp/yamlchanged


set -eE -o functrace
trap 'failure ${LINENO} "$BASH_COMMAND"' ERR


# Check any json files which changed
if [ ! -s /tmp/jsonchanged ]; then
    echo No json files changed
else
    echo json globals files which changed:
    cat /tmp/jsonchanged
    echo "------------"
    for f in $(cat /tmp/jsonchanged); do
        [ ! -f "$f" ] && continue
        echo "checking $f"
        python3 ./scripts/validate.py -f $f
    done
    echo "------------"
fi


# Check any yaml globals files which changed
if [ ! -s /tmp/yamlchanged ]; then
    echo No yaml globals files changed
else
    echo yaml globals files which changed:
    cat /tmp/yamlchanged
    echo "------------"

    # Loop through all directories with yaml globals, and if any had their common globals
    # updated check all the .yamls there, else only check the ones that changed.
    for d in $(cat /tmp/yamlchanged | sed s/\\/[0-9a-zA-Z-]*.yaml//g | sort -u); do
        [ ! -d "$d" ] && continue
        if [[ "$(cat /tmp/yamlchanged)" =~ "$d/common-globals.yaml" ]]; then
            check_all $d
        else
            list=$(egrep "^$d/.*\.yaml$" /tmp/yamlchanged)
            check_list "$list"
        fi
    done

    echo "------------"
fi

# Determine whether our validation scripts modified any files (indicating that tidyness changes are needed)
git status -s | egrep '^ M ' | sed -e 's:^ M ::' >/tmp/modified 2>/dev/null
popd >/dev/null 2>&1
if [ -s /tmp/modified ]; then
    echo "One or more files not tidy:"
    cat /tmp/modified
    echo "To fix this, pip install -r scripts/requirements.txt and then run ./scripts/tidy.sh from the main directory"
    exit 1
else
    echo "ok"
    exit 0
fi
