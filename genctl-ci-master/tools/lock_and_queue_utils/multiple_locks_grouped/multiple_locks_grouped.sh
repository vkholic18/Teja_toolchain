#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Utilities for git based locking (Multiple locks grouped)

function acquire_multiple_locks () {
    # This function tries to acquire multiple locks at once
    # If not all the locks are available or there is git conflict on push; it retries until it manages to acquire or until we reach the maximum attempts

    # Expected parameters:

    # $1 --> Path to genctl ci directory (For calling python script)
    # $2 --> Path to the lock directory (This should be inside a git repo and should have a YAML file called locks.yaml)
    # $3 --> A space separated list of locks to acquire (Example: "onelock anotherlock")
    # $4 --> Who acquired locks (Used for git commit and output)
    # $5 --> Maximum number of attempts to acquire locks
    # $6 --> Sleep time between attempts

    # Put some friendly names
    PATH_TO_GENCTL_CI=$1
    PATH_TO_LOCKS_DIR=$2
    LOCKS_TO_ACQUIRE=$3
    LOCKS_ACQUIRED_BY=$4
    MAX_ATTEMPTS=$5
    SLEEP_TIME=$6
        
    # By default set branch to master
    BRANCH_FOR_ACQUIRE_MULTIPLE_LOCKS=${7:-"master"}

    # Local vars
    ATTEMPTS=0

    # Move to the base dir
    pushd ${PATH_TO_LOCKS_DIR}

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
        echo "Will make attempt ${ATTEMPTS} to acquire locks ${LOCKS_TO_ACQUIRE}"
        
        python3 ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/multiple_locks_grouped/acquire_multiple_locks.py \
        "${PATH_TO_LOCKS_DIR}/locks.yaml" "${LOCKS_TO_ACQUIRE}"

        if [[ $? -eq 0 ]]
        then
            # At this point we managed to locally "acquire the lock"
            # Note that another process might also reach this part in parallel and manage to update the remote before
            # This is checked on the push and we rely on Git for it
            git add locks.yaml
            git commit -m "Lock [${LOCKS_TO_ACQUIRE}] acquired by ${LOCKS_ACQUIRED_BY}"
            git push origin HEAD:${BRANCH_FOR_ACQUIRE_MULTIPLE_LOCKS}
            
            if [[ $? -eq 0 ]]
            then
                # At this point the remote was updated, therefore we can safely assume that we have the lock 
                # No other parallel process can acquire it until we release it
                echo "Locks [${LOCKS_TO_ACQUIRE}] were succesfully acquired by ${LOCKS_ACQUIRED_BY}"
                break
            fi
                echo "Between the local acquire and the remote update, something changed"
        fi
        echo "Could not get the locks; will retry soon..."

        # Clean and update for next try - This is crucial in order to "see" the lock in unclaimed once it gets released
        git stash > /dev/null
        git fetch > /dev/null
        # We need to reset rather than rebase because if not, our local change will still be there and the move command won't work
        git reset --hard origin/${BRANCH_FOR_ACQUIRE_MULTIPLE_LOCKS} > /dev/null
        
        # Wait and increment the number of attempts
        sleep ${SLEEP_TIME}
        ATTEMPTS=$((ATTEMPTS+1))
    done

    # Move back
    popd

}
function release_multiple_locks() {
    # This function tries to release multiple locks at once
    # If git history changes; it retries until it manages to succesfully push or until we reach the maximum attempts

    # Expected parameters:

    # $1 --> Path to genctl ci directory (For calling python script)
    # $2 --> Path to the lock directory (This should be inside a git repo and should have a YAML file called locks.yaml)
    # $3 --> A space separated list of locks to release (Example: "onelock anotherlock")
    # $4 --> Who is releasing the locks (Used for git commit and output)
    # $5 --> Maximum number of attempts to release locks
    # $6 --> Sleep time between attempts

    # Put some friendly names
    PATH_TO_GENCTL_CI=$1
    PATH_TO_LOCKS_DIR=$2
    LOCKS_TO_RELEASE=$3
    LOCKS_RELEASED_BY=$4
    MAX_ATTEMPTS=$5
    SLEEP_TIME=$6
        
    # By default set branch to master
    BRANCH_FOR_RELEASE_MULTIPLE_LOCKS=${7:-"master"}

    # Local vars
    ATTEMPTS=0

    # Move to the base dir
    pushd ${PATH_TO_LOCKS_DIR}

    # Loop will eventually exit in one of the break commands 
    # Either it managed to acquire the lock, or we reached the maximum number of attempts

    while true
    do
        # If we reach the maximum number of attempts, exit 1
        if [[ ${ATTEMPTS} -eq ${MAX_ATTEMPTS} ]]
        then
            echo "After ${ATTEMPTS} attempts, didn't manage to release locks ${LOCKS_TO_RELEASE}"
            break
        fi
        echo "Will make attempt ${ATTEMPTS} to release locks ${LOCK_NAME}"
        
        python3 ${PATH_TO_GENCTL_CI}/tools/lock_and_queue_utils/multiple_locks_grouped/release_multiple_locks.py \
        "${PATH_TO_LOCKS_DIR}/locks.yaml" "${LOCKS_TO_RELEASE}"

        if [[ $? -eq 0 ]]
        then
            # Check if there was any change 
            # (This is to support the cases in which we run this function but there is nothing to commit/push)

            if [[ -z "$(git status -s)" ]]
            then
                echo "Nothing changed on locks.yaml..."
                break
            else
                # At this point we managed to locally "acquire the lock"
                # Note that another process might also reach this part in parallel and manage to update the remote before
                # This is checked on the push and we rely on Git for it
                git add locks.yaml
                git commit -m "Locks [${LOCKS_TO_RELEASE}] released by ${LOCKS_RELEASED_BY}"
                git push origin HEAD:${BRANCH_FOR_RELEASE_MULTIPLE_LOCKS}
                
                if [[ $? -eq 0 ]]
                then
                    # At this point the remote was updated, therefore we can safely assume that locks were released 
                    echo "Locks [${LOCKS_TO_RELEASE}] were succesfully released by ${LOCKS_RELEASED_BY}"
                    break
                fi
                echo "Between the local acquire and the remote update, something changed"
            fi
            echo "Could not release the locks; will retry soon..."    
        fi
        # Clean and update for next try - This is crucial in order to "see" the lock in unclaimed once it gets released
        git stash > /dev/null
        git fetch > /dev/null
        # We need to reset rather than rebase because if not, our local change will still be there and the move command won't work
        git reset --hard origin/${BRANCH_FOR_RELEASE_MULTIPLE_LOCKS} > /dev/null
        
        # Wait and increment the number of attempts
        sleep ${SLEEP_TIME}
        ATTEMPTS=$((ATTEMPTS+1))
    done

    # Move back
    popd
}