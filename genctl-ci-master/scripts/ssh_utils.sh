#!/usr/bin/env bash

# we could probably scrape the list from the ~/.ssh/config file if we were guaranteed a
# singular naming convention but more importantly, we are soon pivoting to using teleport
# instead, and this will need to be changed (probably extensively)

declare -ar BASTIONS=('dal13-bastion1' 'dal10-bastion2')

declare -A DEPLOYERS
DEPLOYERS["1"]="dal10-qz2-deploy1b"
DEPLOYERS["2"]="dal12-qz2-deploy1b"
DEPLOYERS["3"]="dal13-qz2-deploy1a"
DEPLOYERS["4"]="dal4-qz2-deploy1b"

function launch_ssh_agent_if_necessary() {
    # find out if the agent is running
    # if the agent is running then just exit back and dont return the pid
    # as the user must have started it on their own
    # if we needed to start it, send it back to the user so they can close it
    # if they desire
    declare -n __result=$1

    declare sh_opts=$(set +o)

    set +e

    declare __agent_pid=

    if [[ -z ${SSH_AUTH_SOCK:-} ]]; then
        echo "Starting ssh-agent temporarily..."
        eval $(ssh-agent -s)

        __agent_pid=$( pgrep 'ssh-agent' )
    else
        echo "Using existing ssh agent..."
        __agent_pid=${SSH_AGENT_PID}
    fi

    # restore
    eval "$sh_opts"

    __result=${__agent_pid}
}

function get_deployer_conn_path() {
    # we will attempt a random bastion/deployer pair and return if successful
    # if unsuccessful, we will iterate sequentially until one is found (and return that).
    # if we cannot find anything, return empty handed to the caller.
    # note: we require the region digit as we cannot use a deployer that is not in the same
    # region as the mzone. The resources for a mzone are dictated by the undercloud yaml file
    # and trying to use, for instance, vault that is from another region does not work.
    declare -n __result1=$1
    declare -n __result2=$2
    declare -r __ssh_user=$3
    declare -r __ssh_key_file=$4
    declare -r __ssh_key_ecdsa_file=$5
    declare -r __ssh_key_rsa_file=$6
    declare -ri __region=$7

    declare __bastion=
    declare __deployer=
    declare __apid=

    declare sh_opts=$(set +o)

    set +ex

    launch_ssh_agent_if_necessary __apid

    echo "agent pid: ${__apid}"

    # add the keyfiles - does not matter if already exists
    ssh-add "${__ssh_key_file}"
    ssh-add "${__ssh_key_ecdsa_file}"
    ssh-add "${__ssh_key_rsa_file}"

    # dump the existing keys
    ssh-add -l

    declare -r SSH_CONNECTION_TIMEOUT="ConnectTimeout=10"

    # first thing we'll do is try a random pair - if that does not work, then something is afoot
    # and we'll just iterate through each one sequentially and pass back the first successfully pairing
    declare -a DEPS_IN_REG=(${DEPLOYERS[${__region}]})
    declare -r rand_bastion=${BASTIONS[ (( (RANDOM % ${#BASTIONS[@]}) )) ]}
    declare -r rand_deployer=${DEPS_IN_REG[ (( (RANDOM % ${#DEPS_IN_REG[@]}) )) ]}

    echo "Attempting random bastion/deployer: ${rand_bastion}/${rand_deployer}..."
    ssh -o ${SSH_CONNECTION_TIMEOUT} -J ${__ssh_user}@${rand_bastion} ${__ssh_user}@${rand_deployer} uname >/tmp/rand_picker.output 2>&1
    rc=$?
    if [[ ${rc} -eq 0 ]]; then
        __bastion=${rand_bastion}
        __deployer=${rand_deployer}
    else
        echo "Picking a random bastion/deployer failed. We will iterate them all and return first successful pairing."
        cat /tmp/rand_picker.output
    fi

    # start looping sequentially, if we were previously unsuccessful
    if [[ -z ${__bastion} || -z ${__deployer} ]]; then
        for bastion in "${BASTIONS[@]}"; do
            for deployer in "${DEPS_IN_REG[@]}"; do
                echo "Attempting bastion/deployer: ${bastion}/${deployer}..."
                ssh -o ${SSH_CONNECTION_TIMEOUT} -J ${__ssh_user}@${bastion} ${__ssh_user}@${deployer} uname >/tmp/sequential_picker.output 2>&1
                rc=$?

                if [[ ${rc} -eq 0 ]]; then
                    __bastion=${bastion}
                    __deployer=${deployer}
                    break 2
                else
                    echo "Attempt failed for bastion/deployer: ${bastion}/${deployer}..."
                    cat /tmp/sequential_picker.output
                    # also dump the existing ssh keys
                    echo "Dumping loaded ssh keys..."
                    ssh-add -l

                    sleep 1
                fi
            done
        done
    fi

    # restore
    eval "$sh_opts"

    if [[ -z ${__bastion} || -z ${__deployer} ]]; then
        echo "We were unable to find a suitable bastion/deployer pair"
    fi

    __result1=${__bastion}
    __result2=${__deployer}
}

#This will attempt to pick a random deployer for OnePipeLine
function get_deployer_conn_path_one_pipeline() {
    # we will attempt a random deployer and return if successful
    # if unsuccessful, we will iterate sequentially until one is found (and return that).
    # if we cannot find anything, return empty handed to the caller.
    # note: we require the region digit as we cannot use a deployer that is not in the same
    # region as the mzone. The resources for a mzone are dictated by the undercloud yaml file
    # and trying to use, for instance, vault that is from another region does not work.    
    declare -n __result=$1
    declare -r __ssh_user=$2
    declare -r __ssh_key_file=$3
    declare -r __ssh_key_ecdsa_file=$4
    declare -r __ssh_key_rsa_file=$5
    declare -ri __region=$6
    
    declare __deployer=
    declare __apid=

    declare sh_opts=$(set +o)

    set +ex

    launch_ssh_agent_if_necessary __apid

    echo "agent pid: ${__apid}"

    # add the keyfiles - does not matter if already exists
    ssh-add "${__ssh_key_file}"
    ssh-add "${__ssh_key_ecdsa_file}"
    ssh-add "${__ssh_key_rsa_file}"

    # dump the existing keys
    ssh-add -l

    declare -r SSH_CONNECTION_TIMEOUT="ConnectTimeout=10"

    # first thing we'll do is try a random deployer - if that does not work, then something is afoot
    # and we'll just iterate through each one sequentially and pass back the first successfully deployer
    declare -a DEPS_IN_REG=(${DEPLOYERS[${__region}]})    
    declare -r rand_deployer=${DEPS_IN_REG[ (( (RANDOM % ${#DEPS_IN_REG[@]}) )) ]}

    echo "Attempting random deployer: ${rand_deployer}..."
    ssh -o ${SSH_CONNECTION_TIMEOUT} ${__ssh_user}@${rand_deployer} "ls -l" >/tmp/rand_picker.output 2>&1
    rc=$?
    if [[ ${rc} -eq 0 ]]; then
        __deployer=${rand_deployer}
    else
        echo "Picking a random deployer failed. We will iterate them all and return first successful pairing."
        cat /tmp/rand_picker.output
    fi

    # start looping sequentially, if we were previously unsuccessful
    if [[ -z ${__deployer} ]]; then        
        for deployer in "${DEPS_IN_REG[@]}"; do
            echo "Attempting deployer: ${deployer}..."
            ssh -o ${SSH_CONNECTION_TIMEOUT} ${__ssh_user}@${deployer} uname >/tmp/sequential_picker.output 2>&1
            rc=$?
            if [[ ${rc} -eq 0 ]]; then                
                __deployer=${deployer}
                break 2
            else
                echo "Attempt failed for deployer: ${deployer}..."
                cat /tmp/sequential_picker.output
                # also dump the existing ssh keys
                echo "Dumping loaded ssh keys..."
                ssh-add -l
                sleep 1
            fi
        done
    fi

    # restore
    eval "$sh_opts"

    if [[ -z ${__deployer} ]]; then
        echo "We were unable to find a suitable deployer"
    fi
    
    __result=${__deployer}
}
