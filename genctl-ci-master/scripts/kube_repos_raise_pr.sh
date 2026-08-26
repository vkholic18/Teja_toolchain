#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2024
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# This script raises a PR for the relevant kube release bundles
# This script is intended to be run at the end of the merge pipeline for individual kube repos

# The following environment variables need to be set before executing the script:
# PATH_TO_GENCTL_CI

# By default we skip this whole process
# For kube repos an override flag is set in order to NOT skip
SKIP_KUBE_REPOS_RAISE_PR=${SKIP_KUBE_REPOS_RAISE_PR:-"true"}

if [[ $SKIP_KUBE_REPOS_RAISE_PR == "true" ]]; then
  echo "Skipping kube repos raise PR process"
  exit 0
else
  PR_BRANCH_NAME="cicd-pr-$(date +%Y-%m-%d_%H-%M-%S)" # Name the new branch with title and unique ID to avoid PRs on same branch.
  RELS="" # Release bundle or list of release bundles
  TAG=""
  
  case $PIPELINE_REPO_NAME in
    $KUBE_BASE_DEPLOYER_REPO_NAME)
    
    # For kube-base-deployer, we should have a file in ${CI_NON_STANDARD_NAMING_IMAGES_DIR} which content is the IMG_URL, for example something like:
    # docker-na-public.artifactory.swg-devops.com/wcp-genctl-docker-local/kubedeploy:12.0.0_20240122T101707Z_e868d447c
    IMG_URL=$(cat "${CI_NON_STANDARD_NAMING_IMAGES_DIR}/${PIPELINE_REPO_ORG}_${PIPELINE_REPO_NAME}")
    
    # Then, we remove the $ARTIFACTORY_URL, the result is something like: kubedeploy:12.0.0_20240122T101707Z_e868d447c
    ARTIFACT_NAME=${IMG_URL//"$ARTIFACTORY_URL"/}

    echo "Artifact name is ${ARTIFACT_NAME}"

    RELS="$KUBE_BASE_RELEASE_REPO_NAME $KUBE_DEFINE_RELEASE_REPO_NAME $KUBE_ADDON_RELEASE_REPO_NAME $ETCD_BASE_RELEASE_REPO_NAME"
    TAG=$(cut -d ":" -f 2 <<< $ARTIFACT_NAME)
    SED_CMD=(sed -i 's/tool_version:.*/tool_version: '${TAG}'/g' manifest.yml)
    # Run the cmd above later with "${SED_CMD[@]}"
    ;;
    $KUBE_DEFINE_REPO_NAME)
    ARTIFACT_NAME=$(ls ${CI_ARTIFACTS_TO_UPLOAD_DIR})
    RELS="$KUBE_DEFINE_RELEASE_REPO_NAME"
    TAG=$(cut -d "_" -f 2 <<< $ARTIFACT_NAME)
    SED_STR=(sed -i 's/ version:.*/ version: '${TAG}'/g' manifest.yml)
    ;;
    $KUBE_BOOTSTRAP_REPO_NAME)
    ARTIFACT_NAME=$(ls ${CI_ARTIFACTS_TO_UPLOAD_DIR})
    RELS="$KUBE_BASE_RELEASE_REPO_NAME"
    TAG=$(cut -d "_" -f 2 <<< $ARTIFACT_NAME)
    SED_CMD=(sed -i "1,/ version.*/{s/ version:.*/ version: ${TAG}/;}" manifest.yml)
    ;;
  esac

  if [[ ! -z "$HOTFIX_BRANCH" ]]; then
    PR_BASE=$HOTFIX_BRANCH
  fi

  if [[ ! -z "$HOTFIX_MAJOR_COMPONENT" && ! -z "$HOTFIX_BRANCH" ]]; then
    HOTFIX_MAJOR_REPO="${HOTFIX_MAJOR_COMPONENT}-release"
    echo "Executing as a hotfix. Only opening a PR against ${HOTFIX_MAJOR_REPO}:${HOTFIX_BRANCH}"
    RELS=$HOTFIX_MAJOR_REPO
    PR_BRANCH_NAME="${HOTFIX_BRANCH}-staging"
    LABEL="HOTFIX"
  fi

  echo Replace tags in: $RELS to TAG:$TAG

  eval "$(ssh-agent -s)"
  ssh-add - <<< "${GIT_PRIVATE_KEY}"
  mkdir -p ~/.ssh
  ssh-keyscan github.ibm.com >> ~/.ssh/known_hosts
  git config --global user.email "${VAULT_GIT_CONFIG_USER_EMAIL}"
  git config --global user.name "${VAULT_GIT_CONFIG_USERNAME}"

  pushd ${PATH_TO_WORKSPACE_REPO}
  GIT_SHA=$(git rev-parse HEAD)
  PR_TITLE=$(git show-branch --no-name $GIT_SHA)
  echo PR title: $PR_TITLE
  popd

  # Create a new directory that will hold the cloned repos and move to it
  CLONED_REPOS_DIR="${CI_TEMP_DIR}/tmp_clone_repos_for_kube_raise_pr"
  mkdir -p "${CLONED_REPOS_DIR}"
  pushd "${CLONED_REPOS_DIR}"

  #MAKE FOR ALL RELEASES
  for REL in $RELS
  do
    # Clone repo
    git clone --branch "${PIPELINE_RUN_BRANCH}" ${IBM_GITHUB_URI_BASE}:${KUBE_BASE_RELEASE_ORG_NAME}/${REL}.git
    pushd $REL
    echo path:$PWD
    git config --global --add hub.host $IBM_GITHUB_URL
    git remote add upstream https://$IBM_GITHUB_URL/$KUBE_BASE_RELEASE_ORG_NAME/$REL.git
    git remote set-url upstream "$IBM_GITHUB_URI_BASE:$KUBE_BASE_RELEASE_ORG_NAME/$REL.git"
    git checkout -b $PR_BRANCH_NAME

    # Bump release version - increment the release version in the manifest file
    CURR=$(grep -F "release_version" manifest.yml | awk '{print $2}')
    BUMPED=$(echo $CURR | awk -F. -v OFS=. 'NF==1{print ++$NF}; NF>1{if(length($NF+1)>length($NF))$(NF-1)++; $NF=sprintf("%0*d", length($NF), ($NF+1)%(10^length($NF))); print}')
    echo release version changed from: $CURR to $BUMPED
    sed -i 's/release_version:.*/release_version: '$BUMPED'/g' manifest.yml
    TAG=$(cut -d ":" -f 2 <<< "$ARTIFACT_NAME")
    "${SED_CMD[@]}"
    echo tool version changed to $TAG
    git add . && git commit -m "$PR_TITLE - updating tool/payload version in manifest file"
    git push --force upstream

    # Create PR if one does not already exist
    if [[ $(hub pr list -h ${PR_BRANCH_NAME} | wc -l) -eq 0 ]]; then
      echo Creating PR
      if [[ -z ${LABEL+x} ]]; then #LABEL not set
        PR_URL=$(hub pull-request -m "$PR_TITLE" -b "$PR_BASE")
      else # Pass -l if LABEL is configured set
        PR_URL=$(hub pull-request -m "$PR_TITLE" -b "$PR_BASE" -l "$LABEL")
      fi
      echo $PR_URL
    else
      echo PR already exists
    fi
    popd
  done

  # Come back
  popd
fi