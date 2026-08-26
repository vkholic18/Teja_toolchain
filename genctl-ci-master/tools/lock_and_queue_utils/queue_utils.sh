#!/usr/bin/env bash
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2020-2023
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
## Functions
## =============================================================================================

function getUnclaimedEnv {
    local  __resultvar=$1
    eval $__resultvar="$(ls $UNCLAIMED_DIR | tail -1)"
}

function getFirstInQueue {
    local  __resultvar=$1
    eval $__resultvar="$(ls $QUEUE_FILES_FOLDERS | sort -n | head -1)"
}

function getId {
    local  __idvar=$1
    eval $__idvar="${pipelineName}-${jobName}-${buildName}-${buildId}-${serverName}"
    if [ ! -z $mzonesStr ]; then
        id="${id}_envs_${mzonesStr}"
    fi
}

function containsPipelineAttributes {
    if [ ! -f "$PIPELINE_FILE" ]; then
        echo "$PIPELINE_FILE not found."
    elif [ "$(yq -r ".mzone_attributes" $PIPELINE_FILE)" == "null" ]; then
        echo "CI attributes not found"
    else
        echo "$PIPELINE_FILE with CI attributes found."
        return 0;
    fi
    return 1;
}

function pipelineContainsName {
    mzoneName=$(yq -r ".mzone_attributes.name" $PIPELINE_FILE)
    if [[ $mzoneName == "null" ]]; then
        echo "No mzone requested by name"
        return 1;
    else
        echo "$mzoneName requested."
        return 0;
    fi
}

function getEnvByName {
    mzoneName=$(yq -r .mzone_attributes.name $PIPELINE_FILE)
    for f in $UNCLAIMED_PATH $CLAIMED_PATH; do
        if [[ ! -z "$(ls -A ${f%/*} | grep -v ".gitkeep")" ]]; then
        mzone=$(cat $f)
        if [[ $mzone == $mzoneName ]]; then
            echo "${mzonesStr}_${f##*/}"
            return
        fi
        fi
    done
}

function getEnvsByAttributes {
    # Run over all yaml files of pool mzones and look for the requested attributes.
    # Attributes can be at top level of mzone yaml file or nested within other attributes.
    for f in $UNCLAIMED_PATH $CLAIMED_PATH; do
        if [[ ! -z "$(ls -A ${f%/*} | grep -v ".gitkeep")" ]]; then
        mzone=$(cat $f)
        echo checking mzone: $mzone
        addMzoneToList=false
        pipelineMzoneAtrributes=$(yq -r .mzone_attributes <<< ${pipeline_content})
        MZONE_FILE="platform-inventory-repo/region/$mzone.yml"
        if [ -f "$MZONE_FILE" ]; then
            echo mzone yml file found for $mzone
            # compare requested attributes to mzone attributes
            mzone_content=$(cat $MZONE_FILE)
            for attrKey in $(yq -r keys[] <<< ${pipelineMzoneAtrributes}); do
            addMzoneToList=false
            # Check for the key and value of the attribute at the top level
            attrVal=$(yq -r .mzone_attributes.${attrKey} <<< ${pipeline_content})
            if [ $(yq -r .$attrVal <<< ${mzone_content}) == $attrVal ]; then
                addMzoneToList=true
                continue;
            else
                #Check for the key and value of the attribute inside other attributes
                mzoneAtrs=$(yq -r keys[] <<< ${mzone_content})
                for mzoneAtr in $mzoneAtrs; do
                str=.$mzoneAtr[0]?.$attrKey
                if [[ $(yq -r $str <<< ${mzone_content}) == $attrVal ]]; then
                    echo found nested atr
                    addMzoneToList=true
                    break;
                fi
                done
                # If arrived here, it means attribute not found in mzone yaml, no need to iterate it anymore
                if [[ $addMzoneToList == "false" ]]; then
                echo didnt find atr: $attrKey in mzone $mzone. Skipping to next mzone.
                break;
                fi
            fi
            done
            echo addMzoneToList for $f is $addMzoneToList
            if [ $addMzoneToList == "true" ]; then
            echo adding $mzone to list
            mzonesStr="${mzonesStr}_${f##*/}"
            # echo mzonesStr: $mzonesStr
            fi
        else
            echo mzone yml file not found for $mzone
        fi
        fi
    done
}

function availableMzoneFits {
    echo checking if $nextId fits $envFile>&2
    if [[ $nextId == *"_envs_"* ]]; then
        echo pipeline requires specifc mzone>&2
        for file in $UNCLAIMED_PATH; do
        # Skip the hidden files (needed when the folder is empty)
        if [[ $file == *"*"* ]]; then
            continue
        fi
        file=${file##*/}
        echo next: $nextId>&2
        if [[ $nextId == *"_$file"* ]]; then
            echo "mzone $file fits! ">&2
            envFile=$file
            echo $file
            break
        fi
        done
        echo ""
    else
        echo $envFile
    fi
}

function swapTurnWithNextRelevantPipeline {
    numberOfFiles=$(ls queue | wc -l)
    echo numberOfFiles: $numberOfFiles
    if (( $numberOfFiles>1 )); then
        nextPlaceInQueueCandidate=2;
        while (( $nextPlaceInQueueCandidate<=$numberOfFiles )); do
        echo nextPlaceInQueueCandidate: $nextPlaceInQueueCandidate
        nextId=$(ls queue | sort -n | head -$nextPlaceInQueueCandidate | tail -1)
        echo checking next to swap: $nextId
        if availableMzoneFits; then
            # Change order in queue by copying timestamps parts in the queue file names and adding them A and B.
            newFirst=$timestamp'a':$(echo $nextId | cut -d ":" -f 2)
            prevFirst=$timestamp'b':$(echo $id | cut -d ":" -f 2)
            echo newFirst: $newFirst
            echo prevFirst: $prevFirst
            git mv $QUEUE_FILES_FOLDERS/$timestamp:$id $QUEUE_FILES_FOLDERS/$prevFirst
            git mv $QUEUE_FILES_FOLDERS/$nextId $QUEUE_FILES_FOLDERS/$newFirst
            commitAndPush "Give the mzone to aonther pipeline"
            timestamp=$timestamp'b'
            break;
        else
            nextPlaceInQueueCandidate=$((nextPlaceInQueueCandidate+1))
        fi
        done
    fi
}