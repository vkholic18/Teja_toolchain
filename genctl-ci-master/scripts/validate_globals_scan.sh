#!/usr/bin/env bash
#
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2021, 2023
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# Description:
# This script validates the Mustache Template yaml files (See: https://github.com/razee-io/MustacheTemplate)
# found in the following directories of gentctl/rias-globals github repo:
# 	/cicd
# 	/dev
# 	/dev-szr
# 	/dev-mzr
#	/dev-dal1
#	/dev-dal2
#	/dev-dal3
#	/dev-pok
# 	/stage
# 	/integ
# 	/prod
#
# The validation performed is as follow:
#
# 	1. the script validates ALL the mustache template yaml files (region-globals or genctl-globals files), in each of the above directories,
# 	if the common-globals.yaml file changed.
#
# 	2. if the common-globals.yaml file in any of the directories above DID NOT change, the script then determines and validates ONLY
# 	the mustache template yaml files, in each of the above directories, that changed or are new.
#
# Note: The addition or change of a file is done by querying the github repo: genctl/rias-globals, and determining if the file is new or changed
# since the last commit on master

#-----------------------
# Script functions
#-----------------------

#
# validate_all_globals()
#
# Description:
#	Validates ALL the mustache template .yaml files (region-globals or genctl-globals files) in a given directory, against the common-globals.yaml file
# 	of that directory.
#
# Arguments:
#	- $1: the directory to validate.
#
validate_all_globals() {
	local dir="${1}"
	pushd ${dir} >/dev/null 2>&1
	log_info_msg "validate_all_globals(): current dir: $PWD"
	list=$(ls *.yaml 2>/dev/null)
	common=$(ls common?globals.yaml 2>/dev/null)

	# Does common-globals.yaml file exist in the specified dir ?
	if [ -z "${common}" ];
	then
		# We can't perform the validation if common-globals.yaml file doesn't exist in the specified dir ($1)
		popd >/dev/null 2>&1
		log_error_msg "validate_all_globals(): No common globals file found in ${dir}, exiting."
		exit 1
	fi

	# Loop through all the yaml files in the specified dir ($1) and validate them
	for file in ${list}; do
		[ "${file}" == "${common}" ] && continue
		log_info_msg "validate_all_globals(): validating ${dir}/${file}"
		python3 ../scripts/json-to-mustache-templates/validate_globals.py --commonGlobals ${common} --${global_type}Globals ${file} 2>&1
		if [ "$?" == "1" ];
		then
			# mark file $f as invalid
			invalid_files["${dir}/$file"]=1
		fi
	done
	popd >/dev/null 2>&1
}

#
# validate_list_of_globals()
#
# Description:
#	Validates a list of mustache template .yaml files (region-globals or genctl-globals files) in a given directory, against the common-globals.yaml file
# 	of that directory.
#
# Arguments:
#	- $1: the directory to validate.
# 	- $2: the list of files to validate.
#
validate_list_of_globals() {
	local dir=${1}
	local list=${2}
	common=$(ls ${dir}/common?globals.yaml 2>/dev/null)

	# Does common-globals.yaml file exist in the specified dir ?
	if [ -z "${common}" ];
	then
		# We can't perform the validation if common-globals.yaml file doesn't exist in the specified dir ($1)
		log_error_msg "validate_list_of_globals(): No common globals file found in ./${dir}, exiting."
		exit 1
	fi

	# Loop through the list of region-globals or genctl-globals files in the specified dir ($1) and validate them
	for file in ${list}; do
		[ ! -f "$file" ] && continue
		log_info_msg "validate_list_of_globals(): validating ${file}"
		python3 ./scripts/json-to-mustache-templates/validate_globals.py --commonGlobals ${common} --${global_type}Globals ${file} 2>&1
		if [ "$?" == "1" ];
		then
			# mark file $f as invalid
			invalid_files["${file}"]=1
		fi
	done
}

print_end() {
	log_info_msg ">>>>> END"
}

print_results_divider() {
	log_info_msg "****************************************** "
}

print_task_divider() {
	log_info_msg "-----"
}

log_msg() {
	local script_name=${1}
	local msg_type=${2}
	local msg=${3}
	echo "${msg_type} ${msg}"
}

log_info_msg() {
	local msg=${1}
	log_msg ${SCRIPT_NAME} $INFO_MSG_TYPE_ID "${msg}"
}

log_error_msg() {
	local msg=${1}
	log_msg ${SCRIPT_NAME} $ERROR_MSG_TYPE_ID "${msg}"
}

#
# install_third_party_libs()
#
# Description:
#	Installs the third party libraries required to run the gentctl/rias-globals/scripts/json-to-mustache-templates/validate_globals.py script
#
install_third_party_libs() {
	print_task_divider
	log_info_msg "Installing required libraries from: scripts/json-to-mustache-templates/requirements.txt"
	python3 -m pip install -r scripts/json-to-mustache-templates/requirements.txt
	if [ "$?" == "1" ];
	then
		log_error_msg "Failed to install script third-party libraries"
	fi
}

#
# get_new_modified_globals_files()
#
# Description:
#	Gets the list of new and modified region globals or genctl-globals files and save them in the temporary file: /tmp/interesting
#
get_new_modified_globals_files(){
	print_task_divider
	log_info_msg "Getting all new and modified files since the last commit on master..."
	# Store all the files listed as changed in the git log of the master branch, starting from the current revision up to the latest revision (HEAD)
	# diff-filter=d --- Ignore the deleted files
	git log --diff-filter=d --name-only origin/master..HEAD | grep / | sort -u > /tmp/changed

	log_info_msg "Filtering out all new and modified ${global_type}-globals yaml files since the last commit on master..."
	# Search and filter out the files of interest have been modified stores them in the /tmp/interesting
	egrep '^cicd.*\.yaml$|^dev.*\.yaml$|^integ.*\.yaml$|^stage.*\.yaml$|^staging.*\.yaml$|^prod.*\.yaml$' /tmp/changed >/tmp/interesting

	# Do nothing and exit if there aren't new/modified files of interest
	if [ ! -s /tmp/interesting ]; then
		popd >/dev/null 2>&1
		log_info_msg "No files of interest changed, exiting..."
		print_end
		exit 0
	fi
}

#
# print_validation_results_and_exit()
#
# Description:
#	Prints out the validation results
#
# Arguments:
# 	- $1: the list of files that failed the validation.
#
print_validation_results_and_exit(){
	local -n failed_files=${1}
	log_info_msg ""
	print_results_divider
	log_info_msg "> Validation results:"
	log_info_msg ">   Number of errors: ${#failed_files[@]}"

	if [ ${#failed_files[@]} -gt 0 ]; then
		popd >/dev/null 2>&1
		log_info_msg ">   Status: ERROR"
		log_info_msg ">   Please check the following globals files: "
		for i in "${!failed_files[@]}"; do
			log_info_msg ">     ${i}"
		done
		log_info_msg ">"
		log_info_msg ">   Check this link to learn more about how to run the globals validation process locally:"
		log_info_msg ">     https://confluence.swg.usma.ibm.com:8445/pages/viewpage.action?pageId=169345242"
		print_results_divider
		log_info_msg ""
		print_end
		exit 1
	else
		popd >/dev/null 2>&1
		log_info_msg ">   Status: OK"
		print_results_divider
		print_end
		exit 0
	fi
}


#----------------------------
# Script variables
#----------------------------

# Stores name of current script
readonly SCRIPT_NAME=${0##*/}

# INFO msg label
readonly INFO_MSG_TYPE_ID="INFO:"

# ERROR msg label
readonly ERROR_MSG_TYPE_ID="ERROR:"

# Array that stores the directories that have been validated
declare -A validated_dir

# Array that stores the files that failed the validation
declare -A invalid_files

# Store the directory passed as argument to this script
workspace_directory=${1}

# Globals type check - region or genctl
if [ -d "${workspace_directory}/dev-dal1" ]; then
  global_type="genctl"
  global_dirs="dev-dal1 dev-dal2 dev-dal3 dev-dal4 dev-pok integ stage prod"
else
  global_type="region"
  global_dirs="cicd dev dev-mzr dev-szr integ stage prod"
fi
# Change dir
pushd ${workspace_directory} >/dev/null 2>&1




#----------------------------
# Script main body
#----------------------------

log_info_msg ">>>>> STARTING...."
log_info_msg "Current dir: ${PWD}"

install_third_party_libs

get_new_modified_globals_files

# Prints to stdout the new/modified files found
cat /tmp/interesting

#
# Loop through all the directories we care about and if any had their common globals
# updated, then validate all the region-globals or genctl-globals mtp yaml files in that directory.
#
for d in ${global_dirs}; do
	egrep "^${d}/common.globals\.yaml$" /tmp/interesting >/dev/null
	if [ "$?" == "0" ]; then
		log_info_msg "${d}/common-globals.yaml changed, starting validation of all ${global_type}-globals yaml files in dir: ./${d}"
		# remembers which dirs were validated
		validated_dir[${d}]="yes"
		validate_all_globals "${d}"
	else
		# remembers which dirs were NOT validated
		validated_dir[${d}]="no"
	fi
done

#
# Loop through all the keys in the validated_dir array and
# call validate_list_of_globals() with all the directories that
# that were not previously validated.
#
for dir in "${!validated_dir[@]}"
do
	if [ "${validated_dir[$dir]}" == "no" ]
	then
		print_task_divider
		log_info_msg "Validating files in dir: ${dir}"
		list=$(egrep "^${dir}/.*\.yaml$" /tmp/interesting | egrep -v 'common.globals.yaml$')
		if [ -z "${list}" ];
		then
			log_info_msg "No changes detected in dir: ./$dir, ignoring ..."
			continue
		fi
		log_info_msg "Changes detected in dir: ./${dir}, New/Modified files: ${list}, starting validation..."
		validate_list_of_globals "${dir}" "${list}"
	fi
done

print_validation_results_and_exit invalid_files
