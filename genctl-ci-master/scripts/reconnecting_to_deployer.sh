#!/bin/bash

# Attempt SSH connection to deployer
attempting_ssh_connection() {
    local MZONE=$1
    local IMG_TO_RUN=$2
    local retries=$3
    local CONTAINER_NAME=$4
    local MZONE_DIR=$5
    local LOG_FILE="/tmp/ssh_connection.log"  # Temporary log file

    echo "Identifying if the attempted connection is a retry #$retries"
    echo "Container name: ${CONTAINER_NAME}"
    echo "MZONE DIR: ${MZONE_DIR}"
    echo "Image: ${IMG_TO_RUN}"
    echo "Command inside the container: ${COMMAND_INSIDE_CONTAINER}"
    echo "docker run --rm --name=${CONTAINER_NAME} --network host -v ${MZONE_DIR}:${MZONE_DIR} ${IMG_TO_RUN} /bin/bash -c \"${COMMAND_INSIDE_CONTAINER}\""

    # Clear the log file before starting
    > "$LOG_FILE"

    set +x
    if [ "$retries" -eq 1 ]; then
        ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "
            docker run --rm --name=${CONTAINER_NAME} --network host -v ${MZONE_DIR}:${MZONE_DIR} ${IMG_TO_RUN} /bin/bash -c \"${COMMAND_INSIDE_CONTAINER}\"
        " 2>&1 | tee -a "$LOG_FILE"
        EXIT_CODE=${PIPESTATUS[0]}  # Capture the exit code of the ssh command
    else
        ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "
            docker attach ${CONTAINER_NAME}
        " 2>&1 | tee -a "$LOG_FILE"
        EXIT_CODE=${PIPESTATUS[0]}  # Capture the exit code of the ssh command
    fi

    echo "Exit status of the reconnecting to deployer: $EXIT_CODE"

    # Extract specific message if present
    local DISCONNECT_MSG=$(grep "Connection to" "$LOG_FILE")
    
    echo "Disconnection message: $DISCONNECT_MSG"
}

connect() {
    local retries=1
    local RETRY_INTERVAL=10  # Wait before retrying again
    local MAX_RETRIES=10  # Number of retries
    local MZONE="$1"
    local IMG_TO_RUN="$2"
    local MZONE_DIR="$3"
    export EXIT_CODE=$?
    local CONTAINER_NAME="validate_razee_cluster_${MZONE}_$(date -u +%s)"
    echo "Now we are connecting to ${MZONE}"
    echo "Using image: ${IMG_TO_RUN}"

    while [ "$retries" -le "$MAX_RETRIES" ]; do
        echo "Attempting to connect to $DEPLOY_SERVER_TARGET (Attempt $retries of $MAX_RETRIES)..."
        attempting_ssh_connection "$MZONE" "$IMG_TO_RUN" "$retries" "$CONTAINER_NAME" "$MZONE_DIR"
        #EXIT_CODE=$?  # Capture the exit code from attempting_ssh_connection
        
        # Read the disconnection message
        local DISCONNECT_MSG=$(grep "Connection to" /tmp/ssh_connection.log)

        echo "############### Exit code of the deployer: $EXIT_CODE ###############"
        echo "Disconnection message: $DISCONNECT_MSG"

        if [ "$EXIT_CODE" -eq 255 ] && [ -n "$DISCONNECT_MSG" ]; then
            echo "The connection to the remote host was terminated. Retrying in $RETRY_INTERVAL seconds."
            sleep "$RETRY_INTERVAL"
            retries=$((retries + 1))
        elif [ "$EXIT_CODE" -ne 0 ] && [ "$EXIT_CODE" -ne 255 ]; then
            exit "$EXIT_CODE"
        else 
            return $EXIT_CODE
        fi
    done

    echo "Failed to connect after $MAX_RETRIES attempts."
    exit 1
}
