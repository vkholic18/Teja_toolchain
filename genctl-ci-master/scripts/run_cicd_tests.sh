#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2024
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -u

source ${PATH_TO_GENCTL_CI}/scripts/retry.sh

# run all unit tests despite failure
set +e

test_pids=$(mktemp /tmp/pid.XXX)
test_results=$(mktemp /tmp/results.XXX)

# find unit tests (skip test_pipeline_builder.py and test_build_functional_tests.py until ready)
tests=$(find ${PATH_TO_GENCTL_CI} \( -name "test_*.py" -o -name "test_*.sh" \) -and ! -name "test_check_pr_title.py" -and ! -name "test_validate_remote_resource.py" -and ! -name "test_razee_check_duplicate_keys.py" -and ! -name "test_validate_data.py" )

# Before running tests install ci_python_tools package (Required in different tests)
retry python3 -m pip install -q ${PATH_TO_GENCTL_CI}/tools/ci_python_tools

# run tests and save the pids
for test in $tests; do
    echo "Running $test ..."
    
    # Extract the extension (Based on find command should be py or sh)
    extension="${test: -2}"
    
    # Execute accordingly
    case $extension in
        "py")
        # Extract from the full path to the file, the containing folder
        folder=$(dirname $test)
        
        # Set the potential requirements.txt file 
        requirements_file="$folder/requirements.txt"

        # Verify if there is requirements.txt file, if exists quietly install
        # If not just print a message
        if [ -f "$requirements_file" ]
        then
            pip3 install -q -r "$requirements_file"
        else
            echo "No requirements.txt file found next to $test"
        fi

        python3 $test 
        ;;
        "sh")
        chmod +x $test
        ./$test
        ;;
        *)
        # Default case just as a good practice since according to find command extension should be always one of the above
        echo "Don't know how to run extension $extension"
        ;;
    esac

    exit_status=$?
    [[ $exit_status == 0 ]] && test_status="success" || test_status="failure"
    echo "$test test_status: $test_status" >> $test_results

done

echo "Test results summary:"
cat $test_results

# fail task if any test failed
grep -q "failure" $test_results && exit 1 || exit 0