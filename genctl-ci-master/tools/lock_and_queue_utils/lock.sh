#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Utilities for git based locking

function acquire_lock () {
    # This function tries to acquire a lock
    # The final result of the function is expressed by the export var ACQUIRE_LOCK_RESULT
    # After running the function, the environment will have a var ACQUIRE_LOCK_RESULT which contains either NOT_ACQUIRED or the name of the acquired lock

    # Expected parameters:

    # $1 --> Path to base directory (This should be inside a git repo and should have unclaimed and claimed folders)
    # $2 --> Name of the lock (It is represented by a file) - If empty, we assume that can be any lock
    # $3 --> Who acquired lock (Used for git commit and output)
    # $4 --> Maximum number of attempts to acquire lock
    # $5 --> Sleep time between attempts

    # Put some friendly names
    PATH_TO_BASE_DIR=$1
    LOCK_NAME=$2
    LOCK_ACQUIRED_BY=$3
    MAX_ATTEMPTS=$4
    SLEEP_TIME=$5

    # Local vars
    ATTEMPTS=0
    RES="NOT_ACQUIRED"

    # Move to the base dir
    pushd ${PATH_TO_BASE_DIR}

    # If lock name is empty then pick randomly a lock 
    if [[ -z ${LOCK_NAME} ]]
    then
        LOCK_NAME=$(ls unclaimed | sort -R | tail -1)
    fi

    # Save the original branch
    original_branch=$(git rev-parse --abbrev-ref HEAD)

    # Fetch and check if there is a remote branch with the name of the lock we want to acquire
    # If there is then prefer it to the current one (Save to come back)
    git fetch
    git show-branch remotes/origin/${LOCK_NAME} > /dev/null 2>&1

    if [ $? -eq 0 ]
    then
        # Checkout to branch with name of lock
        git checkout ${LOCK_NAME}
    fi
    
    # First check that the lock does exists
    # For this, do a find and assume if we have something in the output from result
    lock_path=$(find . -name "${LOCK_NAME}")

    if [[ ! -z "${lock_path}" ]]
    then
        echo "Lock ${LOCK_NAME} exists; currently here: ${lock_path}"
    else
        echo "Lock ${LOCK_NAME} does not seem to exist..."
        echo "Will exit with error..."
        exit 1
    fi

    # Set the current branch for remote commands (Which will be either the original or one with the lock name)
    branch_for_remote_commands=$(git rev-parse --abbrev-ref HEAD)
    echo "Will be working against remote: ${branch_for_remote_commands}"

    # Loop will eventually exit in one of the break commands 
    # Either it managed to acquire the lock, or we reached the maximum number of attempts

    while true
    do
        # If we reach the maximum number of attempts, exit 1
        if [[ ${ATTEMPTS} -eq ${MAX_ATTEMPTS} ]]
        then
            echo "After ${ATTEMPTS} attempts, didn't manage to acquire lock ${LOCK_NAME}"
            break
        fi
        echo "Will make attempt ${ATTEMPTS} to acquire lock ${LOCK_NAME}"
        
        # Locally move the lock
        git mv unclaimed/${LOCK_NAME} claimed/
        
        if [[ $? -eq 0 ]]
        then
            # At this point we managed to locally "acquire the lock"
            # Note that another process might also reach this part in parallel and manage to update the remote before
            # This is checked on the push and we rely on Git for it
            echo "Succesfully local acquired ${LOCK_NAME}, proceed to try to update remote..."
            git commit -m "Lock ${LOCK_NAME} acquired by ${LOCK_ACQUIRED_BY}"
            git push origin HEAD:${branch_for_remote_commands}
            
            if [[ $? -eq 0 ]]
            then
                # At this point the remote was updated, therefore we can safely assume that we have the lock 
                # No other parallel process can acquire it until we release it
                echo "Lock ${LOCK_NAME} was succesfully acquired by ${LOCK_ACQUIRED_BY}"
                RES=${LOCK_NAME}
                break
            fi
                echo "Between the local acquire and the remote update, something changed"
        fi
        echo "Could not get the lock; will retry soon..."

        # Clean and update for next try - This is crucial in order to "see" the lock in unclaimed once it gets released
        git stash > /dev/null
        git fetch > /dev/null
        # We need to reset rather than rebase because if not, our local change will still be there and the move command won't work
        git reset --hard origin/${branch_for_remote_commands} > /dev/null
        
        # Wait and increment the number of attempts
        sleep ${SLEEP_TIME}
        ATTEMPTS=$((ATTEMPTS+1))
    done
    
    # Exporting the result to be used outside
    export ACQUIRE_LOCK_RESULT=${RES}

    # Before coming back move to original branch (If we changed)
    if [ "${original_branch}" != "${branch_for_remote_commands}" ]
    then
        # Checkout to branch with name of lock
        git checkout ${original_branch}
    fi

    # Move back
    popd

}
function release_lock_if_acquired() {
    # This function is a small wrapper for easier use in TRAP commands
    # Will release the lock if needed
    
    # Expected parameters:

    # $1 --> Name of the lock (It is represented by a file)
    # $2 --> Path to base directory (This should be inside a git repo and should have unclaimed and claimed folders)
    # $3 --> Who releases the lock (Used for git commit and output)
    # $4 --> Maximum number of attempts to release lock
    # $5 --> Sleep time between attempts

    # Put some friendly names
    LOCK_NAME=$1
    PATH_TO_BASE_DIR=$2
    LOCK_RELEASED_BY=$3
    MAX_ATTEMPTS=$4
    SLEEP_TIME=$5

    if [[ ${LOCK_NAME} != "NOT_ACQUIRED" ]]
    then
        # Release lock should not stop on error
        set +e
        release_lock ${PATH_TO_BASE_DIR} ${LOCK_NAME} "${LOCK_RELEASED_BY}" ${MAX_ATTEMPTS} ${SLEEP_TIME}
    else
        echo "No lock was acquired, so no need to release"
    fi
}
function release_lock () {
    # This function releases a lock

    # It is important to use this function only when we are sure that we are holding the lock

    # Expected parameters:

    # $1 --> Path to base directory (This should be inside a git repo and should have unclaimed and claimed folders)
    # $2 --> Name of the lock (It is represented by a file)
    # $3 --> Who releases the lock (Used for git commit and output)
    # $4 --> Maximum number of attempts to release lock
    # $5 --> Sleep time between attempts

    # Put some friendly names
    PATH_TO_BASE_DIR=$1
    LOCK_NAME=$2
    LOCK_RELEASED_BY=$3
    MAX_ATTEMPTS=$4
    SLEEP_TIME=$5

    # Local vars
    ATTEMPTS=0

    # Move to the base dir
    pushd ${PATH_TO_BASE_DIR}

    # Save the current branch
    original_branch=$(git rev-parse --abbrev-ref HEAD)

    # Fetch and check if there is a remote branch with the name of the lock we want to acquire
    # If there is then prefer it to the current one (Save to come back)
    git fetch
    git show-branch remotes/origin/${LOCK_NAME} > /dev/null 2>&1

    if [ $? -eq 0 ]
    then
        # Checkout to branch with name of lock
        git checkout ${LOCK_NAME}
    fi
    
    # Set the current branch for remote commands (Which will be either the original or one with the lock name)
    branch_for_remote_commands=$(git rev-parse --abbrev-ref HEAD)
    echo "Will be working against remote: ${branch_for_remote_commands}"

    # Loop will eventually exit in one of the break commands 
    # Either it managed to release the lock, or we reached the maximum number of attempts

    while true
    do
        # If we reach the maximum number of attempts, exit 1
        if [[ ${ATTEMPTS} -eq ${MAX_ATTEMPTS} ]]
        then
            echo "After ${ATTEMPTS} attempts, didn't manage to release lock ${LOCK_NAME}"
            break
        fi
        echo "Will make attempt ${ATTEMPTS} to release lock ${LOCK_NAME}"

        # Locally move the lock
        pwd
        
        git mv claimed/${LOCK_NAME} unclaimed/
        
        if [[ $? -eq 0 ]]
        then
            # At this point we managed to locally "release the lock"
            # Note that another process might also reach this part in parallel and manage to update the remote before
            # This is checked on the push and we rely on Git for it
            echo "Succesfully local released ${LOCK_NAME}, proceed to try to update remote..."
            git commit -m "Lock ${LOCK_NAME} released by ${LOCK_RELEASED_BY}"
            git push origin HEAD:${branch_for_remote_commands}
            
            if [[ $? -eq 0 ]]
            then
                # At this point the remote was updated, therefore we can safely assume that we released the lock 
                echo "Lock ${LOCK_NAME} was succesfully released by ${LOCK_RELEASED_BY}"
                break
            fi
                echo "Between the local release and the remote update, something changed"
        fi
        echo "Could not release the lock; will retry soon..."

        # Clean and update for next try - This is crucial in order to "see" the lock in unclaimed once it gets released
        git stash > /dev/null
        git fetch > /dev/null
        # We need to reset rather than rebase because if not, our local change will still be there and the move command won't work
        git reset --hard origin/${branch_for_remote_commands} > /dev/null
        
        # Wait and increment the number of attempts
        sleep ${SLEEP_TIME}
        ATTEMPTS=$((ATTEMPTS+1))
    done

    # Before coming back move to original branch (If we changed)
    if [ "${original_branch}" != "${branch_for_remote_commands}" ]
    then
        # Checkout to branch with name of lock
        git checkout ${original_branch}
    fi

    # Move back
    popd
}
function lock_is_still_mine() {
    # This function verifies if a specific lock is still held by a specific run
    # This is useful, for example, to avoid re-runs of BRT (Since they ran on a sub-pipeline but the lock is acquired in the parent pipeline)
    
    # The basic idea is to compare the commit message for a specific lock to the commit message we set when we acquired it for a specific run
    # If they are the same, then it means lock is still from the same run

    # Expected parameters:

    # $1 --> Path to base directory (This should be inside a git repo and should have unclaimed and claimed folders)
    # $2 --> Name of the lock (It is represented by a file)
    # $3 --> Message when the lock was acquired

    # Put some friendly names
    PATH_TO_BASE_DIR=$1
    LOCK_NAME=$2
    ACQUIRED_MESSAGE=$3

    # Set result as false
    LOCK_IS_STILL_MINE_RESULT="false"

    echo "Will check if lock ${LOCK_NAME} is still held by same run that was acquired with message: ${ACQUIRED_MESSAGE}"

    # Move to the base dir
    pushd "${PATH_TO_BASE_DIR}"

    # Save the current branch
    original_branch=$(git rev-parse --abbrev-ref HEAD)

    # Fetch and check if there is a remote branch with the name of the lock we want to acquire
    # If there is then prefer it to the current one (Save to come back)
    git fetch
    git show-branch remotes/origin/${LOCK_NAME} > /dev/null 2>&1

    if [ $? -eq 0 ]
    then
        # Checkout to branch with name of lock
        git checkout ${LOCK_NAME}
    fi
    
    # Set the branch for remote commands
    branch_for_remote_commands=$(git rev-parse --abbrev-ref HEAD)
    echo "Will be working against remote: ${branch_for_remote_commands}"

    # Move to the base dir, specifically to the claimed directory
    pushd "claimed"

    # Reset to get last updates from remote
    git fetch > /dev/null
    git reset --hard origin/${branch_for_remote_commands} > /dev/null

    # First check lock is in claimed folder, if not, then we already know that lock is not anymore "ours"
    if [ -f "${LOCK_NAME}" ]
    then
        # Now we should check that the reason that lock is on claimed folder is because it is still claimed from the specific run we want to check

        # First do some processing to extract the commit message
        RAW_GIT_LOG_RESULT=$(git log --oneline -- filename ${LOCK_NAME} | head -n 1)
        ONLY_SHA=$(echo ${RAW_GIT_LOG_RESULT} | cut -d ' ' -f 1)
        COMMIT_MESSAGE=${RAW_GIT_LOG_RESULT#"$ONLY_SHA "}

        # At this point we should have on COMMIT_MESSAGE the commit message
        # The claim lock of BRT in OnePipeline has the following format:
        # "${PIPELINE_RUN_NAME} run ${BUILD_NUMBER} - 1P_INFO: ${PIPELINE_ID}/${PIPELINE_RUN_ID}/${ENDPOINT}"

        # Example:
        # "riaas/regional-storage pr run 4 - 1P_INFO: ec6bf6da-5d3d-48f9-a4a1-93b291e20f6c/726b422f-ca0c-4ae7-aef3-a9e44077f7c8/us-south"

        echo "Current commit message for lock ${LOCK_NAME} is: ${COMMIT_MESSAGE}"

        # Check if message is still the one when we acquired the lock
        if [[ "${COMMIT_MESSAGE}" == "${ACQUIRED_MESSAGE}" ]]
        then
            echo "Lock is still mine..."
            LOCK_IS_STILL_MINE_RESULT="true"
        else
            echo "Lock is not mine anymore..."
        fi
    else
        echo "Lock is not mine anymore..."
    fi
    
    # First come back from claimed
    popd

    # Before coming back move to original branch (If we changed)
    if [ "${original_branch}" != "${branch_for_remote_commands}" ]
    then
        # Checkout to branch with name of lock
        git checkout ${original_branch}
    fi

    # Come back to folder
    popd

    # Compare in order to make this function "return" a boolean
    [[ "$LOCK_IS_STILL_MINE_RESULT" == "true" ]]
}
