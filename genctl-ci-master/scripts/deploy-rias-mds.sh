#!/usr/bin/env bash
##
## =============================================================================================
## IBM Confidential
## (C) Copyright IBM Corp. 2019
## The source code for this program is not published or otherwise divested of its trade secrets,
## irrespective of what has been deposited with the U.S. Copyright Office.
## =============================================================================================
##

set -eux

source $PATH_TO_GENCTL_CI/scripts/deployer_utils.sh
source $PATH_TO_GENCTL_CI/scripts/validate_razee_cluster_utils.sh
source $PATH_TO_GENCTL_CI/scripts/retry.sh


if [[ "${USE_QZ2_WORKER}" != true ]]; then
    if [[ "${APPLY_DMM_DEPLOY_PROCESS}" == false ]]; then
        # Declare the function
        RIAS_ETCD_RELEASE_TAG=$(yq -r '.version."rias-etcd-release"' $PATH_TO_VETTED_VERSIONS_REPO/${GENCTL_VETTED_VERSIONS})
        echo RIAS_ETCD_RELEASE_TAG: ${RIAS_ETCD_RELEASE_TAG} from $PATH_TO_VETTED_VERSIONS_REPO/${GENCTL_VETTED_VERSIONS}
        RIAS_RELEASE_TAG=$(yq -r '.version."rias-release"' $PATH_TO_VETTED_VERSIONS_REPO/${GENCTL_VETTED_VERSIONS})
        echo RIAS_RELEASE_TAG: ${RIAS_RELEASE_TAG} from $PATH_TO_VETTED_VERSIONS_REPO/${GENCTL_VETTED_VERSIONS}
    else
        source $PATH_TO_GENCTL_CI/scripts/ssh_utils.sh
        export MZONE_NAME=$(yq -r '.dmm_deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml | cut -d ',' -f2)
    fi

    function post_deploy_razee_logs() {
        orig_opts=$-
        set +x  # just to make this much easier on the eyes
        echo "=========rias remote resources list========="
        echo "kubectl -n rias get FeatureFlagSetLD/rias-ffs-ld -o json | jq -r '.data' "
        ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "KUBECONFIG=${RIAS_CLUSTER_DIR}/kubeconfig.yaml kubectl -n rias get FeatureFlagSetLD/rias-ffs-ld -o json | jq -r '.data' "
        set -${orig_opts}
    }

    function login_to_staging_artifactory() {
        # docker login to staging registry so that we can pull images
        set +x  # so we do not log the password
        echo "docker logging in to ${ARTIFACTORY_DOCKER_STAGING_URL}"
        echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_STAGING_URL} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
        set -x
    }

    function run_pod_readiness_checks() {

        set +x
        validate_pods_cluster_readiness_goku $PATH_TO_MDS_REPO "rias" $PATH_TO_GENCTL_CI "${RIAS_CLUSTER_DIR}/kubeconfig.yaml" ${RIAS_CLUSTER_DIR} \
        "${DAL_VAULT_KEY}" $PATH_TO_PLATFORM_INVENTORY_REPO \
        ${ART_URL} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN}
        set -x
    }

    case "$MZONE_NAME" in
    mzone7215)
        IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev05-etcd"
        ;;
    mzone7286)
        IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev06-etcd"
        ;;
    mzone7287)
        IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev07-etcd"
        ;;
    mzone7288)
        IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev08-etcd"
        ;;
    mzone7301)
        IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev24-etcd"
        ;;
    mzone7302)
        IBMCLOUD_IKS_CLUSTER_NAME="rias-ng-us-south-dal-dev25-etcd"
        ;;
    *)
        echo "${MZONE_NAME} is not supported for rias deploys"
        exit 1
        ;;
    esac
    export LAUNCH_DARKLY_RULE_TAG=${IBMCLOUD_IKS_CLUSTER_NAME}
    echo "LAUNCH_DARKLY_RULE_TAG=${LAUNCH_DARKLY_RULE_TAG}"
    if [[ "${APPLY_DMM_DEPLOY_PROCESS}" == true ]]; then
        set +x
        # Setup ssh to deployer
        if [[ $IS_ONE_PIPELINE_RUN == "true" ]]; then
            setup_ssh_to_deployer_one_pipeline ${MZONE_NAME} ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}"
        else
            setup_ssh_to_deployer ${MZONE_NAME} ${BASTION_USERNAME} "${BASTION_PRIVATE_KEY}" "${BASTION_PRIVATE_KEY_ECDSA}" "${BASTION_PRIVATE_KEY_RSA}"
        fi
        set -x
    fi
    # Prepare an mzone-specific directory on the deploy server where we can put MDS config
    export MZONE_DIR=/home/${BASTION_USERNAME}/${MZONE_NAME}
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "mkdir -p ${MZONE_DIR}"

    # Prepare an empty directory on the deploy server where we can put kubeconfig
    RIAS_CLUSTER_DIR=/home/${BASTION_USERNAME}/${IBMCLOUD_IKS_CLUSTER_NAME}
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "rm -rf ${RIAS_CLUSTER_DIR}"
    ssh ${SSH_CONFIG_PARAMS} ${DEPLOY_SERVER_TARGET} "mkdir -p ${RIAS_CLUSTER_DIR}"

    # export variables used for vault in MDS/deploy.py
    set +x; export IBMCLOUD_KEY=$(echo "$IBMCLOUD_KEY" | jq -r .apikey); set -x

    if [[ "${APPLY_DMM_DEPLOY_PROCESS}" == false ]]; then
        # initialize a EYAML specific to this mzone with known-good tags
        # This will also add nodelist to the eyaml if needed
        python3 $PATH_TO_GENCTL_CI/scripts/MDS/config_mds_eyaml.py \
            --input-file $PATH_TO_GENCTL_CI/hack/MDS/${MDS_CONFIG_TEMPLATE} \
            --output-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
            --vetted-versions $PATH_TO_VETTED_VERSIONS_REPO/${GENCTL_VETTED_VERSIONS} \
            --inventory-file $PATH_TO_PLATFORM_INVENTORY_REPO/region/${MZONE_NAME}.yml \
            --operation init

        # Support deploying both known-good and staging bundles
        RIAS_ETCD_RELEASE_REG_URL=${ARTIFACTORY_DOCKER_PROD_URL}
        RIAS_RELEASE_REG_URL=${ARTIFACTORY_DOCKER_PROD_URL}

        #if component type is genctl check if it is a shared component with rias release
        # if so override RIAS_ETCD_RELEASE_TAG from vetted version and use custom rias release bundle built for this component

        if [[ ${RIAS_DEPLOY_COMPONENT_TYPE:-} == 'genctl' && ! -z ${WORKSPACE_REPO_NAME:-} && ${HOTFIX} == 'false' ]]; then
            # check if the genctl component is a shared rias component
            set +e
            python3 $PATH_TO_GENCTL_CI/scripts/exist_in_inventory_json.py ${WORKSPACE_REPO_NAME} $PATH_TO_RIAS_RELEASE_REPO/component-input/inventory.json
            result=$?
            echo $result
            set -e
            if [[ ${result} == 0 ]]; then
                echo "component ${WORKSPACE_REPO_NAME} is a shared with rias-release component."
                RIAS_RELEASE_REG_URL=${ARTIFACTORY_DOCKER_STAGING_URL}
                RIAS_RELEASE_TAG=${COMPONENT_HASH}
                login_to_staging_artifactory
                python3 $PATH_TO_GENCTL_CI/scripts/MDS/config_mds_eyaml.py  \
                    --input-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
                    --output-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
                    --component 'rias' \
                    --package 'rias-release' \
                    --version ${COMPONENT_HASH} \
                    --operation prep
            fi

            # check if the genctl component is a shared rias-etcd component
            set +e
            python3 $PATH_TO_GENCTL_CI/scripts/exist_in_inventory_json.py ${WORKSPACE_REPO_NAME} $PATH_TO_RIAS_ETCD_RELEASE_REPO/component-input/inventory.json
            result=$?
            echo $result
            set -e
            if [[ ${result} == 0 ]]; then
                echo "component ${WORKSPACE_REPO_NAME} is a shared with rias-etcd-release component."
                RIAS_ETCD_RELEASE_REG_URL=${ARTIFACTORY_DOCKER_STAGING_URL}
                RIAS_ETCD_RELEASE_TAG=${COMPONENT_HASH}
                login_to_staging_artifactory
                python3 $PATH_TO_GENCTL_CI/scripts/MDS/config_mds_eyaml.py  \
                    --input-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
                    --output-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
                    --component 'rias' \
                    --package 'rias-etcd-release' \
                    --version ${COMPONENT_HASH} \
                    --operation prep
            fi
        fi

        #if rias component always override RIAS_RELEASE_TAG / RIAS_ETCD_RELEASE_TAG from vetted version and use custom rias release bundle built for this component
        if [[ ${RIAS_DEPLOY_COMPONENT_TYPE:-} == 'rias' ]]; then
            # setup to pull a new image we are testing from staging
            if [ ${PACKAGE} == 'rias-etcd-release' ]; then
                RIAS_ETCD_RELEASE_REG_URL=${ARTIFACTORY_DOCKER_STAGING_URL}
                RIAS_ETCD_RELEASE_TAG=${COMPONENT_HASH}
                python3 $PATH_TO_GENCTL_CI/scripts/MDS/config_mds_eyaml.py  \
                    --input-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
                    --output-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
                    --component 'rias' \
                    --package 'rias-etcd-release' \
                    --version ${COMPONENT_HASH} \
                    --operation prep
            elif [ ${PACKAGE} == 'rias-release' ]; then
                RIAS_RELEASE_REG_URL=${ARTIFACTORY_DOCKER_STAGING_URL}
                RIAS_RELEASE_TAG=${COMPONENT_HASH}
                python3 $PATH_TO_GENCTL_CI/scripts/MDS/config_mds_eyaml.py  \
                    --input-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
                    --output-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
                    --component 'rias' \
                    --package 'rias-release' \
                    --version ${COMPONENT_HASH} \
                    --operation prep
            else
                echo "${PACKAGE} is not a recognized RIAS release bundle"
                exit 1
            fi
            login_to_staging_artifactory
        fi

        cat $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml

        # Copy MDS to deploy server
        retry rsync -aq --delete -e "ssh ${SSH_CONFIG_PARAMS}" $PATH_TO_MDS_REPO/ ${DEPLOY_SERVER_TARGET}:${MZONE_DIR}/micro-deploy-server

        # docker login to prod registry so that we can pull images
        set +x  # so we do not log the password
        echo "docker logging in to ${ARTIFACTORY_DOCKER_PROD_URL}"
        echo ${CC_ARTIF_ACCESS_TOKEN} | docker login ${ARTIFACTORY_DOCKER_PROD_URL} -u ${WCP_ARTIFACTORY_USERNAME} --password-stdin
        set -x


        # Pull image and copy to the deployer
        # (This function is from deployer_utils, which at this point should have been sourced already)
        set +x
        pull_image_and_copy_to_deployer ${RIAS_ETCD_RELEASE_REG_URL} \
            ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} "rias/rias-etcd-release:${RIAS_ETCD_RELEASE_TAG}" \
            "true" "${ARTIFACTORY_DOCKER_PROD_URL}/rias/rias-etcd-release:${RIAS_ETCD_RELEASE_TAG}" \
            "rias-etcd-release-${RIAS_ETCD_RELEASE_TAG}" "${MZONE_DIR}"
        set -x
        # Pull image and copy to the deployer
        # (This function is from deployer_utils, which at this point should have been sourced already)
        set +x
        pull_image_and_copy_to_deployer ${RIAS_RELEASE_REG_URL} \
            ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} "rias/rias-release:${RIAS_RELEASE_TAG}" \
            "true" "${ARTIFACTORY_DOCKER_PROD_URL}/rias/rias-release:${RIAS_RELEASE_TAG}" \
            "rias-release-${RIAS_RELEASE_TAG}" "${MZONE_DIR}"
        set -x
    fi
    # Get kube config for RIAS cluster
    ibmcloud config --check-version=false
    set +x # so we do not log the api key
    echo "${IBMCLOUD_KEY}" > con_key_file
    set -x
    ibmcloud login --apikey @con_key_file -r us-south
    rm -f con_key_file

    # this will download and set the running config/context. since we're running in dind, we don't care if this is set globally
    # Try 5 times to download the IKS kubeconfig
    kubeconfig_success=false
    for i in {1..5};
    do
        ibmcloud ks cluster config --cluster ${IBMCLOUD_IKS_CLUSTER_NAME} && kubeconfig_success=true && break || sleep 5;
    done

    # fail if we cannot communicate with ibmcloud
    if [ "$kubeconfig_success" = false ]; then
        echo "Failed to download cluster context for ${IBMCLOUD_IKS_CLUSTER_NAME}. Exiting ..."
        exit 1
    fi

    # fail if the current context is not the target context
    CLUSTER_CONTEXT=$(kubectl config current-context)
    if [[ -z "${CLUSTER_CONTEXT:-}" ]]; then
        echo "Failed to download cluster context for ${IBMCLOUD_IKS_CLUSTER_NAME}. Exiting ..."
        exit 1
    fi

    kubectl config view --flatten > kubeconfig.yaml
    chmod 600 kubeconfig.yaml

    # Copy kube config to deploy server
    retry rsync -aq -e "ssh ${SSH_CONFIG_PARAMS}" kubeconfig.yaml ${DEPLOY_SERVER_TARGET}:${RIAS_CLUSTER_DIR}/

    if [[ "${APPLY_DMM_DEPLOY_PROCESS}" == false ]]; then
        # Deploy rias
        python3 $PATH_TO_GENCTL_CI/scripts/MDS/deploy.py \
            --release-bundles "rias" \
            --eyaml-file $PATH_TO_MDS_REPO/${MZONE_NAME}.yaml \
            --target-eyaml ${MZONE_NAME}.yaml
    fi

    # run readiness mtp check if razee is configured to be deploy on rias-release
    if [[ $(jq -c '[ .[] | select( .manifest_template_path | contains("rias-inception.yaml")) ]' $PATH_TO_RIAS_RELEASE_REPO/component-input/components.json ) != '[]' ]]; then
        echo "rias-inception is defined on the rias-release components, running MTP readiness checks..."
        python3 $PATH_TO_GENCTL_CI/scripts/razee_readiness/razee_mtp_readiness.py rias
    fi

    if [[ "${APPLY_DMM_DEPLOY_PROCESS}" == true ]]; then
        source $PATH_TO_MDS_REPO/.env
        artifactory_url=$(echo ${MDS_IMAGE_PATH} | awk -F "/" '{print $1}')
        repo_path=$(echo ${MDS_IMAGE_PATH} | awk -F "/" '{print $2}')
        mds_path=$(echo ${MDS_IMAGE_PATH} | awk -F "/" '{print $3}')
        mds_package=$(echo ${MDS_IMAGE_PATH} | awk -F "/" '{print $4}')
        set +x
        pull_image_and_copy_to_deployer ${artifactory_url} ${WCP_ARTIFACTORY_USERNAME} ${CC_ARTIF_ACCESS_TOKEN} \
        ${repo_path}/${mds_path}/${mds_package}:${MDS_IMAGE_VERSION} \
        "false" "None" mds-image-${MDS_IMAGE_VERSION} ${MZONE_DIR}
        set -x
    fi

    run_pod_readiness_checks
    post_deploy_razee_logs
fi

if [[ "${USE_QZ2_WORKER}" == true ]]; then
    echo "Use QZ2 tekton workers for validations"
    source ${PATH_TO_GENCTL_CI}/scripts/validate_razee_cluster_utils.sh

    #source icr related utils
    source ${PATH_TO_GENCTL_CI}/scripts/ibmcloud_utils.sh
    set +x

    export BRT_ENVIRONMENT_NAME=$(yq -r '.dmm_deployment.rule_tag | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml | cut -d ',' -f1)

    echo "${BRT_ENVIRONMENT_NAME} is a rias cluster"

     # so we do not log the key
    validate_razee_cluster_rias ${BRT_ENVIRONMENT_NAME} "${IBMCLOUD_KEY}" ${PATH_TO_GENCTL_CI}

    if [[ $(jq -c '[ .[] | select( .manifest_template_path | contains("rias-inception.yaml")) ]' $PATH_TO_RIAS_RELEASE_REPO/component-input/components.json ) != '[]' ]]; then
        echo "rias-inception is defined on the rias-release components, running MTP readiness checks..."
        python3 $PATH_TO_GENCTL_CI/scripts/razee_readiness/razee_mtp_readiness.py rias
    fi

    echo "Will validate pod readiness for rias cluster ${BRT_ENVIRONMENT_NAME}"
    validate_pods_cluster_readiness_rias ${BRT_ENVIRONMENT_NAME} "${IBMCLOUD_KEY}" ${PATH_TO_GENCTL_CI}

    set -x
fi
