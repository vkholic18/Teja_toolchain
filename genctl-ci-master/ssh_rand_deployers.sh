#!/usr/bin/env bash

#
# Summary of tests
#
##
# TEST: kill single bastion, region 3 dal13-bastion1
# TEST: kill single bastion, region 1 dal10-bastion2
# TEST: kill both bastions, region 1
# TEST: kill single deployer, region 1 dal10-qz2-deploy1a
# TEST: kill single deployer, region 1 dal10-qz2-deploy1b
# TEST: kill both deployers, region 1
# TEST: kill single deployer, region 2 dal12-qz2-deploy1b
# TEST: kill single deployer, region 3 dal13-qz2-deploy1a
# TEST: unobstructed access - no blocks - random access should pass
##

set -u

# With the assumption that the ssh_utils.sh is always next to this script, this is safe
dir_of_current_script="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
. $dir_of_current_script/ssh_utils.sh

function check_deploy_pair {
    # check if any entry is null
    declare -n __bastion=$1
    declare -n __deployer=$2

    if [[ -z ${ssh_bastion} || -z ${ssh_deployer} ]]; then
        echo "unable to locate a working bastion/deployer"
        return 1
    else
        echo "working bastion/deployer pair located: ${ssh_bastion}/${ssh_deployer}"
    fi

    return 0
}

function test_kill_bas_dep_pair {
    # start blocking bastion/deployer pairs and attempt to ssh through them
    # return pass/fail
    declare -n __bastions=$1
    declare -n __deployers=$2
    declare -r __user=$3
    declare -r __key=$4
    declare -r __key_ecdsa=$5
    declare -r __key_rsa=$6
    declare -ri __region=$7

    cp ~/.ssh/config ~/.ssh/config.bak

    # send the hosts to the hole
    for bastion in "${__bastions[@]}"; do
        echo "killing host: ${bastion}"
        sed -i "/Host ${bastion}/{n;s/.*/  HostName 1.2.3.4/}" ~/.ssh/config
    done
    # send the hosts to the hole
    for deployer in "${__deployers[@]}"; do
        echo "killing host: ${deployer}"
        sed -i "/Host ${deployer}/{n;s/.*/  HostName 1.2.3.4/}" ~/.ssh/config
    done

    get_deployer_conn_path ssh_bastion ssh_deployer ${__user} ${__key} ${__key_ecdsa} ${__key_rsa} ${__region}

    check_deploy_pair ssh_bastion ssh_deployer

    local rc=$?

    # restore ssh config
    cp ~/.ssh/config.bak ~/.ssh/config

    return ${rc}
}

# user and priv key, if passed
ssh_user=${1:-"clconc"}
ssh_key=${2:-"/tmp/priv_key"}

declare -r ssh_user
declare -r ssh_key

##
# TEST: kill single bastion, region 3 dal13-bastion1
# expected result: pass
##
declare -a KILLED_BASTIONS=('dal13-bastion1')
declare -a KILLED_DEPLOYERS=()

echo "** Unit test: kill bastion: dal13-bastion1"
test_kill_bas_dep_pair KILLED_BASTIONS KILLED_DEPLOYERS ${ssh_user} ${ssh_key} 1

[[ $? -ne 0 ]] && exit 1

##
# TEST: kill single bastion, region 1 dal10-bastion2
# expected result: pass
##
declare -a KILLED_BASTIONS=('dal10-bastion2')
declare -a KILLED_DEPLOYERS=()

echo "** Unit test: kill bastion: dal10-bastion2"
test_kill_bas_dep_pair KILLED_BASTIONS KILLED_DEPLOYERS ${ssh_user} ${ssh_key} 1

[[ $? -ne 0 ]] && exit 1

##
# TEST: kill both bastions, region 1
# expected result: fail
##
declare -a KILLED_BASTIONS=('dal13-bastion1' 'dal10-bastion2')
declare -a KILLED_DEPLOYERS=('dal10-qz2-deploy1a dal10-qz2-deploy1b')

echo "** Unit test: kill both bastions: dal13-bastion1 and dal10-bastion2"
test_kill_bas_dep_pair KILLED_BASTIONS KILLED_DEPLOYERS ${ssh_user} ${ssh_key} 1

[[ $? -eq 0 ]] && exit 1

##
# TEST: kill single deployer, region 1 dal10-qz2-deploy1a
# expected result: pass
##
declare -a KILLED_BASTIONS=()
declare -a KILLED_DEPLOYERS=('dal10-qz2-deploy1a')

echo "** Unit test: kill deployer: dal10-qz2-deploy1a"
test_kill_bas_dep_pair KILLED_BASTIONS KILLED_DEPLOYERS ${ssh_user} ${ssh_key} 1

[[ $? -ne 0 ]] && exit 1

##
# TEST: kill single deployer, region 1 dal10-qz2-deploy1b
# expected result: pass
##
declare -a KILLED_BASTIONS=()
declare -a KILLED_DEPLOYERS=('dal10-qz2-deploy1b')

echo "** Unit test: kill deployer: dal10-qz2-deploy1b"
test_kill_bas_dep_pair KILLED_BASTIONS KILLED_DEPLOYERS ${ssh_user} ${ssh_key} 1

[[ $? -ne 0 ]] && exit 1

##
# TEST: kill both deployers, region 1
# expected result: fail
##
declare -a KILLED_BASTIONS=()
declare -a KILLED_DEPLOYERS=('dal10-qz2-deploy1a' 'dal10-qz2-deploy1b')

echo "** Unit test: kill both deployers: dal10-qz2-deploy1a dal10-qz2-deploy1b"
test_kill_bas_dep_pair KILLED_BASTIONS KILLED_DEPLOYERS ${ssh_user} ${ssh_key} 1

[[ $? -eq 0 ]] && exit 1

##
# TEST: kill single deployer, region 2 dal12-qz2-deploy1b
# expected result: pass
##
declare -a KILLED_BASTIONS=()
declare -a KILLED_DEPLOYERS=('dal12-qz2-deploy1b')

echo "** Unit test: kill deployer: dal12-qz2-deploy1b"
test_kill_bas_dep_pair KILLED_BASTIONS KILLED_DEPLOYERS ${ssh_user} ${ssh_key} 2

[[ $? -ne 0 ]] && exit 1

##
# TEST: kill single deployer, region 3 dal13-qz2-deploy1a
# expected result: pass
##
declare -a KILLED_BASTIONS=()
declare -a KILLED_DEPLOYERS=('dal13-qz2-deploy1a')

echo "** Unit test: kill deployer: dal13-qz2-deploy1a"
test_kill_bas_dep_pair KILLED_BASTIONS KILLED_DEPLOYERS ${ssh_user} ${ssh_key} 3

[[ $? -ne 0 ]] && exit 1

##
# TEST: unobstructed access - no blocks - random access should pass
# expected result: pass
##
declare -a KILLED_BASTIONS=()
declare -a KILLED_DEPLOYERS=()

echo "** Unit test: unobstructed access - no blocks - random access should pass"
test_kill_bas_dep_pair KILLED_BASTIONS KILLED_DEPLOYERS ${ssh_user} ${ssh_key} 3

[[ $? -ne 0 ]] && exit 1

echo "All tests have completed successfully"

exit 0
