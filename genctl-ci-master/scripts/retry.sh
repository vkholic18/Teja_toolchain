#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2022
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# A retry function that accepts 3 optional variables, the function will re-run the given command
# for the amount of time and delay specified by the passed variables

set -o nounset

function fail {
  set -e
  echo $1 >&2
  exit 1
}

function retry {
  set +e
  local n=1
  local max=5
  local delay=3
  local verbosity=true
  while [[ $# -gt 0 ]]
  do
  key="$1"

  case $key in
      -s|--sleep)
      delay="$2"
      shift # past argument
      ;;
      -m|--max)
      max="$2"
      shift # past argument
      ;;
      -v|--verbosity)
      verbosity="$2"
      shift
      ;;
      -h|--help)
      echo """A retry command for bash.
Usage:
  retry [-s SLEEP_TIME] [-m MAX_RETRIES] [-v VERBOSITY] COMMAND_WITH_ARGUMENTS"""
      return 0
      ;;
      *)
      break # unknown option
      ;;
  esac
  shift # past argument or value
  done

  COMMAND=$(printf "%q " "$@")

  [ "$verbosity" == true ] && echo "Executing with retry: $COMMAND" || echo "Executing command with retry"

  while true; do
    "$@" && break || {
      if [[ $n -lt $max ]]; then
        ((n++))
        echo "Command failed. Attempt $n/$max:"
        sleep $delay;
      else
        fail "The command has failed after $n attempts."
      fi
    }
  done
  # return exit on error flag if successfull
  set -e
}
