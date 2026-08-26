#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2025
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# meta_util - functions to allow for calling rest api to submit metadata

function put_to_gbid() {

   # Arguments expected:
   # 1 - artifact abs file name - file name date/time format is important!!  example:  golang-ci-pkglist-2019-02-27T22:00:00.txt
   #     the date format listed above is required in order for the current gbid rest api to consume the file properly
   # 2 - create record - true or false
   # 3 - GBID API HOST TEST API_HOST="9.41.34.248"   PROD API_HOST="9.41.33.139"
   # 4 - job name - this value is used to help populate the meta data info - this will need to be passed by build job

   echo "*** - Start gbid put function - $( date -u +"%H:%M:%S" ) - ***"

   # Make sure required arguments were passed in
   if [ "$#" -ne 4 ]; then
      echo "ERROR: ${FUNCNAME[0]} requires 4 arguments but got $#. Please pass in the correct arguments."
      exit 1
   else
      artifact_file=$1
      create_record=$2
      gbid_api_host=$3
      job_name=$4
   fi

   # Check if the file exists. If not, exit
   if [[ -f "$artifact_file" ]]; then
      echo "Error:  invalid file:  $artifact_file - does not exist!"
      exit 1
   fi

   echo "artifact file:       $artifact_file"
   echo "gbid create new record:    $create_record"
   echo "gbid api host:          $gbid_api_host"
   echo "Build Job Name:         $job_name"

   # temp file to return record number for multiple appends to same record id if needed
   RECORD_ID_FILE="/tmp/gbid_record_id"
   # the contents of the file passed in are in abs_file
   abs_file=$(ls $artifact_file)
   filename=$(basename "$abs_file")
   # Setup the orda_lineage, get the filename without the hash to prep for next step
   orda_lineage="orda-lineage"
   filename_without_date=$(echo "$filename" | awk -F "-" '{print $1"-"$2}')

   # experimenting here with variables I may want to use in the near future
   JOB_NUMBER=$TRAVIS_JOB_NUMBER
   BUILD_ID=$TRAVIS_BUILD_ID

   # Check if the file we're looking at is an orda-lineage type, if so, set the GBID_RECORD_ID
   if [[ "$filename_without_date" == "$orda_lineage" ]]; then
      GBID_RECORD_ID=0
   # create gbid record
   elif [[ "$create_record" = true ]]; then
      echo "Create new record"
      # make curl call to request new record
      # parse response to get record id and assign to GBID_RECORD_ID
      # create record
      RESPONSE=$(curl -f --silent -X POST -F "pipeline=$job_name" http://$gbid_api_host:8080/api/gbid)
      check_last_cmd_error "curl failed on host $gbid_api_host!"
      echo "Response from curl create record: $RESPONSE"
      # store record somewhere /tmp?
      GBID_RECORD_ID=$(echo $RESPONSE | jq '.id')
   else
      echo "Appending to existing record"
      if [[ -f "$RECORD_ID_FILE" ]]; then
         cat $RECORD_ID_FILE
         GBID_RECORD_ID=$(cat $RECORD_ID_FILE | jq -r '.version.gbid_id')
      else
         echo "Error: gbid id $RECORD_ID_FILE file cannot be located"
         exit 1
      fi
   fi

   echo "gbid record: $GBID_RECORD_ID"
   echo "The file to be uploaded is: $abs_file"
   echo "Requesting meta upload..."

   # Check if orda-lineage file (If not, egrep will return error code of 1 since it didn't find anything, which is translated to false by the if statement.
   if echo "$filename" | egrep '^orda-lineage-.*'; then
      echo "Orda-lineage path"
      # orda lineage
      curl -i -f -F file=@$abs_file http://$gbid_api_host:8080/api/orda-lineage
      check_last_cmd_error "curl failed on host $gbid_api_host!"
   else
      # docker args, golangci, gopkg, artifacts json
      curl -i -f -F file=@$abs_file -F "pipeline=$job_name" http://$gbid_api_host:8080/api/gbid/$GBID_RECORD_ID
      check_last_cmd_error "curl failed on host $gbid_api_host!"
   fi

   # send record number to tmp file
   jq -n "{ \"version\": { \"gbid_id\": \"$GBID_RECORD_ID\" } }" > $RECORD_ID_FILE

   echo "*** - End gbid put function - $( date -u +"%H:%M:%S" ) - ***"

}

function compile_docker_args_json () {
   # This function compiles all the values for the json file
   # Values are required for docker args to be consumed by gbid (this format is in the process of changing 3-3-2019)

   # Get GBID docker args required data based on current workspace
   SUBMODULE=`git remote get-url --all origin | cut -d"/" -f2 | sed -e s/\.git$//`
   GIT_REPO_URL=$(git remote get-url --all origin | sed 's,:,/,g' | sed 's,git@,https://,g')
   GIT_ORG=`git remote get-url --all origin| egrep -o ':(.*)/' | cut -d ":" -f 2 | cut -d "/" -f 1`
   #CC_GIT_SHA=$(git show -s --pretty=format:"%H")
   OUTPUT_FILE=gbid-docker-args.json

   # Construct required json for the docker_args file to be consumed by gbid
   docker_args_body=$(cat <<EOC |
{ "GIT_PR_URL": "${GIT_REPO_URL}/commits/${CC_GIT_SHA}",
"BUILD_TIME": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
"GIT_REPO_URL": "$GIT_REPO_URL",
"GIT_SHA": "$CC_GIT_SHA",
"GIT_DATE": "$(git show -s --pretty=format:"%at")",
"GIT_AUTHOR": "$(git show -s --pretty=format:"%an")",
"HELM": {
"name: ": "$(cat hack/deploy/$SUBMODULE/Chart.yaml | sed -n -e '/^name: /p' | sed -e 's/^name: //')",
"version": "$(cat hack/deploy/$SUBMODULE/Chart.yaml | sed -n -e '/^version: /p' | sed -e 's/^version: //')"
},
"GIT_COMMIT_SUMMARY": "$(git log --pretty=format:'%s' -n 1 | sed -e 's/"/\\"/g')",
"GIT_REPO_NAME": "${SUBMODULE}"
}
EOC
jq -c '.')

# Output json to file to be consumed via build script
echo $docker_args_body > $OUTPUT_FILE
check_last_cmd_error "error when sending json to  $OUTPUT_FILE"
}

function get_build_arches() {
    ##
    # from a .travis.yml build yaml, parse out all the arches that are defined/enabled and return
    # as a string in the form of "<arch1> <arch2> <archN>"
    ##
    local __build_yaml=$1

    PY_SCRIPT="$(dirname ${BASH_SOURCE[0]})"/python/utils/get_travis_build_arches.py

    python3 "${PY_SCRIPT}" "${__build_yaml}"
}