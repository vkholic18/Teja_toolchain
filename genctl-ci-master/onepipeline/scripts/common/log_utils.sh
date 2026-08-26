#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2025
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##
# COMMON_PATH=$(cd "$(dirname "${BASH_SOURCE[0]}")"; pwd)
COMMON_TRACING='true' #turn this off to allow scripts to dictate tracing

#**************************************************************************
#                                                 log_utils/log_set_logfile
#        NAME
#               log_set_logfile()
# DESCRIPTION
#               Set the logfile pathname messages will write to
#      INPUTS
#               pathname
#      RESULT
#               n/a
#**************************************************************************
log_set_logfile() {
    COMMON_LOG_FILE=$1
    export COMMON_LOG_FILE
} # end log_set_logfile()

#**************************************************************************
#                                                         log_utils/log
#        NAME
#               log()
# DESCRIPTION
#               log a line of text to a file with a date-stamp and echo
#                to the screen as well
#      INPUTS
#               text message
#      RESULT
#
#**************************************************************************
log() {
    echo "$1"
    if [[ -n "${COMMON_LOG_FILE}" ]]; then
       # only write to log file if a pathname is set
       DATE=$(date +"%Y/%m/%d %H:%M:%S")
       echo "${DATE} CI: $1" >> "${COMMON_LOG_FILE}"
    fi
}

log_banner() {
    log ""
	log "-------------------------------------------"
	log "--- $1"
	log "-------------------------------------------"
}

log_step_banner() {
    log ""
	log "--- $1"
    log "------"
    log ""
}

log_error() {
    log ""
	log "ERROR: $*"
    log ""
}

log_warning() {
	log "WARNING: $*"
}

log_trace_enter() {
    [[ -n "${COMMON_TRACING}" ]] && log_step_banner "ENTER $*"   #  - $(date -u +"%H:%M:%S") 
}

log_trace_exit() {
    [[ -n "${COMMON_TRACING}" ]] && log_step_banner "EXIT  $*"   #  - $(date -u +"%H:%M:%S") 
}

#**************************************************************************
#                                                         log_utils/log
#        NAME
#               log_debug()
# DESCRIPTION
#               log a line if debug is set
#      INPUTS
#               text message
#      RESULT
#               n/a
#**************************************************************************
log_debug() {
	if [[ -n "${COMMON_DEBUG}" ]]; then
		log "DEBUG: $1"
	fi
} # end log()

log_set_debug() {
	COMMON_DEBUG = "true"
	export COMMON_DEBUG
}

log_unset_debug() {
	unset COMMON_DEBUG
}

#**************************************************************************
#                                                 log_utils/log_run_command
#        NAME
#               log_run_command()
# DESCRIPTION
#               run a command and log output
#      INPUTS
#
#      RESULT
#
#**************************************************************************
log_run_command()
{
    log ""
    log "$*"
    TMPFILE="$(mktemp --dry-run --suffix _log_run_command.log)"

    oldopt=$-               # save active bash options (like set -e)
    set +e                  # make sure this function does not exit BEFORE displaying output!
    $* >${TMPFILE} 2>&1     # run the program and capture output to file
    rc=$?                   # capture the return code
    set -$oldopt            # restore previous bash options

    [[ -n "${COMMON_LOG_FILE}" ]] && cat "${TMPFILE}" >> "${COMMON_LOG_FILE}"
    cat "${TMPFILE}"
    rm "${TMPFILE}"
    return ${rc}            # return the return code the command alone would have returned
} # end log_run_command()


#=========================
# Initialize logfile name
#=========================
# Note: the +x here makes this work for "set -u" cases but it also means
# that this will not work for COMMON_LOG_FILE='' (so don't do that)
if [ -z ${COMMON_LOG_FILE+x} ] ; then
    MY_NAME="`basename \"$0\"`"
    log_set_logfile "/tmp/${MY_NAME%.*}.log"
fi