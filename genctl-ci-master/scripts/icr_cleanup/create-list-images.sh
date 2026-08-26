#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2025
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

source "$PATH_TO_GENCTL_CI/scripts/ibmcloud_utils.sh"
TARGET_BRANCH=main
set -x
ibmcloud_login "${IBM_CLOUD_KEY}"
set +x
DATA_LIST=(
    "genctl-cicd razee-toolchains-ci-tf-module razee_toolchains.tf main razee"
    "genctl-cicd prod-artifacts-toolchains-ci-tf-module prod_artifacts_toolchains.tf main prod_artifacts"
    "genctl-cicd release-bundles-toolchains-ci-tf-module release_bundles_toolchains.tf main release_bundles"
)

for ITEM in "${DATA_LIST[@]}"; do
    read -r OWNER REPO FILE_PATH BRANCH TEMPLATE <<< "$ITEM"
    OUTPUT_FILE="${TEMPLATE}-images.yaml"
    TARGET_FILE_PATH="ICR_Cleanup/${TEMPLATE}-images.yaml"
    echo "# Combined build-meta.yaml image list" > "$OUTPUT_FILE"
    echo " Processing module: $OWNER/$REPO ($TEMPLATE)"

    API_URL="$GHE_API_URL/repos/$OWNER/$REPO/contents/$FILE_PATH?ref=$BRANCH"
    RESPONSE=$(curl -s -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.raw" "$API_URL")


    if [ -z "$RESPONSE" ]; then
        echo " Failed to fetch $REPO/$FILE_PATH"
        continue
    fi

    REPO_LIST=$(echo "$RESPONSE" | sed -nE 's/^[[:space:]]*repo[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p')

    echo "list of $REPO_LIST"

    if [[ -z "$REPO_LIST" ]]; then
        echo "  No repositories found in $REPO/$BRANCH"
        continue
    fi

    IFS=$'\n' read -d '' -r -a REPO_URLS < <(printf '%s\n' "$REPO_LIST")

    for REPO_URL in "${REPO_URLS[@]}"; do
        echo "Checking repo $REPO_URL"
        CLEAN_URL=$(echo "$REPO_URL" | sed -E 's|.git$||')
        REPO_PATH=$(echo "$CLEAN_URL" | awk -F '/' '{print $(NF-1) "/" $NF}')
        REPO_NAME=$(echo "$REPO_PATH" | awk -F '/' '{print $2}')

        FOUND=0
        for BR in master main; do
            TREE_API="$GHE_API_URL/repos/$REPO_PATH/git/trees/$BR?recursive=1"
            MATCH=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$TREE_API" |
                jq -r --arg path "$BUILD_META_PATH" '.tree[]? | select(.path == $path) | .path')

            if [[ "$MATCH" == "$BUILD_META_PATH" ]]; then
                echo " Found build-meta.yaml in $REPO_PATH on branch $BR"

                FILE_API="$GHE_API_URL/repos/$REPO_PATH/contents/$BUILD_META_PATH?ref=$BR"
                YAML_CONTENT=$(curl -s -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.raw" "$FILE_API")

                if [[ -n "$YAML_CONTENT" ]]; then
                    echo "$REPO_NAME:" >> "$OUTPUT_FILE"

                    # Extract and write multi_arch images
                    MULTI_ARCH_RAW=$(echo "$YAML_CONTENT" | yq -r '.images.multi_arch')
                    if echo "$MULTI_ARCH_RAW" | grep -q '^-'; then
                    MULTI_ARCH_IMAGES=$(echo "$MULTI_ARCH_RAW" | grep -v '^null$')
                    else
                    MULTI_ARCH_IMAGES=$(echo "$MULTI_ARCH_RAW" | tr ' ' '\n' | grep -v '^null$')
                    fi

                    if [[ -n "$MULTI_ARCH_IMAGES" ]]; then
                    echo "  multi_arch:" >> "$OUTPUT_FILE"
                    while IFS= read -r image; do
                        if [[ -n "$image" ]]; then
                        echo "    - \"$image\"" >> "$OUTPUT_FILE"
                        fi
                    done <<< "$MULTI_ARCH_IMAGES"
                    else
                    echo "  # No multi_arch images found" >> "$OUTPUT_FILE"
                    fi

                    # Extract and write amd64 images
                    AMD64_RAW=$(echo "$YAML_CONTENT" | yq -r '.images.amd64')
                    if echo "$AMD64_RAW" | grep -q '^-'; then
                    AMD64_IMAGES=$(echo "$AMD64_RAW" | grep -v '^null$')
                    else
                    AMD64_IMAGES=$(echo "$AMD64_RAW" | tr ' ' '\n' | grep -v '^null$')
                    fi

                    if [[ -n "$AMD64_IMAGES" ]]; then
                    echo "  amd64:" >> "$OUTPUT_FILE"
                    while IFS= read -r image; do
                        if [[ -n "$image" ]]; then
                        echo "    - \"$image\"" >> "$OUTPUT_FILE"
                        fi
                    done <<< "$AMD64_IMAGES"
                    else
                    echo "  # No amd64 images found" >> "$OUTPUT_FILE"
                    fi
                fi

                FOUND=1
                break
            fi
        done

        if [[ $FOUND -eq 0 ]]; then
            echo "$REPO_NAME: # build-meta.yaml not found or inaccessible" >> "$OUTPUT_FILE"
            echo >> "$OUTPUT_FILE"
        fi
    done

    echo " Completed processing $REPO. Total repos scanned: ${#REPO_URLS[@]}"
done

# Upload to GitHub

ENCODED_CONTENT=$(base64 -w 0 < "$OUTPUT_FILE" 2>/dev/null || base64 < "$OUTPUT_FILE" | tr -d '\n')

# Get latest SHA if file already exists
EXISTING_FILE_INFO=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
  "$GHE_API_URL/repos/$TARGET_REPO/contents/$TARGET_FILE_PATH?ref=$TARGET_BRANCH")

SHA=$(echo "$EXISTING_FILE_INFO" | jq -r '.sha // empty')

echo " Pushing $OUTPUT_FILE to $TARGET_REPO at $TARGET_FILE_PATH"

# Build JSON payload
if [[ -n "$SHA" ]]; then
  echo " Updating existing file..."
  PAYLOAD=$(jq -n \
    --arg msg "$COMMIT_MESSAGE" \
    --arg content "$ENCODED_CONTENT" \
    --arg path "$TARGET_FILE_PATH" \
    --arg branch "$TARGET_BRANCH" \
    --arg sha "$SHA" \
    '{message: $msg, content: $content, branch: $branch, sha: $sha}')
else
  echo " Creating new file in GitHub repo..."
  PAYLOAD=$(jq -n \
    --arg msg "$COMMIT_MESSAGE" \
    --arg content "$ENCODED_CONTENT" \
    --arg path "$TARGET_FILE_PATH" \
    --arg branch "$TARGET_BRANCH" \
    '{message: $msg, content: $content, branch: $branch}')
fi

# Push the file to GitHub
RESPONSE=$(curl -s -X PUT -H "Authorization: token $GITHUB_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$GHE_API_URL/repos/$TARGET_REPO/contents/$TARGET_FILE_PATH")

# Check for success
if echo "$RESPONSE" | grep -q '"content"'; then
  echo " Successfully pushed to $TARGET_REPO/$TARGET_FILE_PATH"
else
  echo " Failed to push file. Response:"
  echo "$RESPONSE"
fi