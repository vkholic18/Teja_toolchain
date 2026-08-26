#!/bin/bash
##
## =============================================================================================
## IBM Confidential
## © Copyright IBM Corp. 2025
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

# parameter_util - functions to allow for reading back variables from pipeline parameter file
# this function will be useful in the situations where many varibles need to be read
# or we don't want to be limited with variables that have to be passed into via concourse but still want
# a single source of truth
# We could adapt this function to other sources of truths in the future if needed

function get_source_of_truth() {

   # Clone and checkout only if it isn't already cloned
   if [ ! -d "${CC_SOURCE_NAME}" ]; then
      echo "Cloning ${CC_SOURCE_ORG}/${CC_SOURCE_NAME} repo..."
      git clone -b $CC_SOURCE_BRANCH git@github.ibm.com:${CC_SOURCE_ORG}/${CC_SOURCE_NAME}.git

      # cd into the cloned repo directory
      cd ${CC_SOURCE_NAME}
      # Sync git hash of source at the time concourse was triggerred
      checkout_git_hash $CC_SOURCE_GIT_REF
      # Return to working directory
      cd ..
   fi
}

function process_file() {

    # Set file variables
    sourceFile=${CC_SOURCE_NAME}/params/pipeline-params.yaml
    cachedFile=test_file.txt
    processedFile=processed_file.txt

    # Check to make sure source file exists
    if [ ! -f $sourceFile ]; then
        echo "Source of truth parameter file is not found!"
        exit 1
    fi

    # Check to make sure file doesn't already exist
    if [ -f $processedFile ]; then
        echo "Remove if $processedFile file already exists"
        rm $processedFile
    fi

    echo "Process source of truth ${sourceFile} and source to set all values to env variables..."
    # Process file with one line - remove unecessary lines, add quotes, add CC_ to beginning of variable name
    cat ${sourceFile} | sed -e 's/---//g' | awk 'NF' | sed -e 's/^/CC_/' | sed -e 's/: /="/g' | grep -v "#" | sed 's/$/"/' > $cachedFile

    # Loop to process file - need to handle value versus variable name differently in each line
    while read LINE; do

       # Need to process variable name to get to bash standards
       var_name=$(echo $LINE | cut -f1 -d= | sed 's/-/_/g' | tr '[:lower:]' '[:upper:]')

       # Keep value used for each variable - remove any single quotes if they exist
       var_value=$(echo $LINE | cut -f2 -d= | sed "s/'//g")

       # Combine variables
       echo "export ${var_name}=${var_value}" >> $processedFile

       #echo "This is a line: $LINE"
       #echo "Processed line: ${var_name}=${var_value}"

    done < $cachedFile

    # Cache file no longer needed
    rm $cachedFile

    # Cat source file for reference in logs
    # cat $processedFile

}

function set_env_variables_from_source() {
    # Set variables based on parameters passed in from build/test/manifest repo travis scripts

    # Make sure required arguments were passed in
    if [ "$#" -eq 0 ]; then
        echo "ERROR: ${FUNCNAME[0]} requires at least 1 argument but got $#. Please pass in the correct arguments."
        exit 1
    fi

    # File used to set selective variables from the all encompassing processed file
    envSetFile="env_set_file.txt"

    # Check to make sure file doesn't already exist
    if [ -f $envSetFile ]; then
        echo "Remove if $envSetFile file already exists"
        rm $envSetFile
    fi

    # Get the source of truth to be used to set variables
    get_source_of_truth

    # Process source of truth file to be used for setting CC_ variables
    process_file

    # Set specific variables to be set based on keywords being passed in
    for cc_keyword in "$@"
    do
       # echo "$cc_keyword"
       grep $cc_keyword $processedFile >> $envSetFile
    done

    # Show all env variable to be set for reference in logs
    cat $envSetFile

    # Source the file so available to travis code
    source $envSetFile


}