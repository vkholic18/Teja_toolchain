#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2021
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
## This script 
## - clones the genctl_release and rias_release components/repos
## - finds all the Dockerfile files in all the cloned repos
## - finds all the git submodules in all the cloned repos
## - finds the third-party dependencies in all the Dockerfiles
##
## Usage: ./find_security_info.sh 2>&1 | tee output.txt
##

set -e

function clone_components {
  echo "********** CLONE COMPONENT REPOS - START **********"
  release_repo=$1
  [[ -d $release_repo ]] || git clone git@github.ibm.com:genctl/$release_repo.git
  cd $release_repo/component-input
  grep url inventory.json | sed 's/^ *//g' | awk '{ print $2}' | sed 's/"//g' | while read line
  do
    basename=$(basename $line)
    reponame=${basename%.*}
    [[ -d $home_dir/$reponame ]] || git clone "$line" $home_dir/$reponame
  done
  cd $home_dir
  echo "********** CLONE COMPONENT REPOS - DONE **********"
  echo
}

function find_dockerfile {
  echo "********** FIND DOCKERFILE - START **********"
  release_repo=$1
  cd $release_repo/component-input
  grep url inventory.json | sed 's/^ *//g' | awk '{ print $2}' | sed 's/"//g' | while read line
  do
    basename=$(basename $line)
    reponame=${basename%.*}
    echo "Processing $line"
    find $home_dir/$reponame -name '*ockerfile*'
    echo
  done
  cd $home_dir
  echo "********** FIND DOCKERFILE - DONE **********"
  echo
}

function find_git_submodules {
  echo "********** FIND GIT SUBMODULES - START **********"
  release_repo=$1
  cd $release_repo/component-input
  grep url inventory.json | sed 's/^ *//g' | awk '{ print $2}' | sed 's/"//g' | while read line
  do
    basename=$(basename $line)
    reponame=${basename%.*}
    echo "Processing $line"
    grep url $home_dir/$reponame/.gitmodules | sed 's/.*url = //g'
    echo
  done
  cd $home_dir
  echo "********** FIND GIT SUBMODULES - DONE **********"
  echo
}

function find_third_party_dependencies {
  echo "********** FIND THIRD PARTY DEPENDENCIES - START **********"
  egrep -ir --include=Dockerfile "alpine:|ubuntu:|redhat.com|centos.org|golang:|redis:|https://github.com/|https://alpine-pkgs.sgerrand.com|busybox:|googleapis.com|https://sourceforge.net|debian:"
  cd $home_dir
  echo "********** FIND THIRD PARTY DEPENDENCIES - DONE **********"
  echo
}
###############
# Main function
###############

# Everything will be cloned in 'cloned_repos' in your current directory
[[ -d cloned_repos ]] || mkdir cloned_repos
cd cloned_repos
export home_dir=$PWD

clone_components genctl-release
clone_components rias-release
find_dockerfile genctl-release
find_dockerfile rias-release
find_git_submodules genctl-release
find_git_submodules rias-release
find_third_party_dependencies
