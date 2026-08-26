# !/usr/bin/env bash
# # =============================================================================================
# # IBM Confidential
# # (C) Copyright IBM Corp. 2025
# # The source code for this program is not published or otherwise divested of its trade secrets,
# # irrespective of what has been deposited with the U.S. Copyright Office.
# # =============================================================================================

source "$PATH_TO_GENCTL_CI/scripts/ibmcloud_utils.sh"
set -x
ibmcloud_login "${ONE_PIPELINE_CI_IBM_CLOUD_API_KEY}"
set +x
TARGET_FILE_PATH="ICR_Cleanup/${TEMPLATE}-images.yaml"
INPUT_YAML="${TEMPLATE}-images.yaml"
TARGET_BRANCH=main

# --- Download YAML from GitHub ---
echo " Downloading $TARGET_FILE_PATH from $TARGET_REPO"
curl -s -H "Authorization: token $GITHUB_TOKEN" \
     -H "Accept: application/vnd.github.v3.raw" \
     "$GHE_API_URL/repos/$TARGET_REPO/contents/$TARGET_FILE_PATH?ref=$TARGET_BRANCH" \
     -o "$INPUT_YAML"

# --- File Existence + CRLF cleanup ---
if [[ ! -s "$INPUT_YAML" ]]; then
  echo " ERROR: YAML file '$INPUT_YAML' is missing or empty."
  exit 1
fi

# Remove any CRLF line endings (just in case Tekton shell sees \r)
sed -i 's/\r$//' "$INPUT_YAML"

# --- Cutoff Date Calculation ---
if date -d "200 days ago" +%s >/dev/null 2>&1; then
  CUTOFF_DATE=$(date -d "$THRESHOLD_DAYS days ago" +%s)
elif command -v gdate >/dev/null 2>&1; then
  CUTOFF_DATE=$(gdate -d "$THRESHOLD_DAYS days ago" +%s)
else
  echo " ERROR: GNU date or gdate not found."
  exit 1
fi
echo " Checking for images older than $THRESHOLD_DAYS days (Epoch: $CUTOFF_DATE)"

inside_images=false
current_repo=""
current_arch=""

while IFS= read -r line || [[ -n "$line" ]]; do
  echo " Line: $line"

  # Repo name
  if [[ "$line" =~ ^([a-zA-Z0-9._-]+):[[:space:]]*$ ]]; then
    current_repo="${BASH_REMATCH[1]}"
    echo "Current Repo: $current_repo"
    inside_images=false
    continue
  fi

  # Architecture block
  if [[ "$line" =~ ^[[:space:]]*(multi_arch|amd64):[[:space:]]*$ ]]; then
    current_arch="${BASH_REMATCH[1]}"
    echo " Architecture block: $current_arch"
    inside_images=true
    continue
  fi

  # Skip comments or blank lines
  if [[ "$line" =~ ^[[:space:]]*# || -z "$line" ]]; then
    echo " Skipping comment/blank: '$line'"
    continue
  fi

  # Process image lines inside arch block
  if $inside_images && [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.*)$ ]]; then
    raw="${BASH_REMATCH[1]}"
    echo "Raw image line: $raw"

    cleaned=$(echo "$raw" | sed -E 's/^["'\''\[\],-]+//; s/["'\''\[\],]+$//' | xargs)
    echo "Cleaned image: $cleaned"

    if [[ -z "$cleaned" || "$cleaned" == "[" || "$cleaned" == "]" ]]; then
      echo "Skipping invalid line"
      continue
    fi

    cleaned=$(echo "$cleaned" | sed -E "s|^(us\.icr\.io/)?$NAMESPACE/||" | tr -d ',')
    full_repo="$NAMESPACE/$cleaned"
    echo "Checking images for: $full_repo"

    if ! response=$(ibmcloud cr image-list --restrict "$full_repo" --output json 2>&1); then
      echo "ERROR: Failed to fetch images for $full_repo"

      continue
  fi

    if echo "$response" | jq empty 2>/dev/null; then
      images=$(echo "$response" | jq -r --argjson cutoff "$CUTOFF_DATE" '
        .[]?
        | select(.Repository and .Tag and (.Created | type == "number" or type == "string"))
        | (.Created | tonumber) as $created
        | select($created > 0 and $created < $cutoff)
        | "Old Image (raw): Namespace=\(.Namespace) Repository=\(.Repository) Tag=\(.Tag) Created=\(if ($created | type == "number") then ($created | strftime("%Y-%m-%d")) else "unknown" end)"
      ')

      if [[ -n "$images" ]]; then
        echo "Total old images found: $(echo "$images" | wc -l)"
        echo "$response" | jq -r --argjson cutoff "$CUTOFF_DATE" '
          .[]?
      | select(.Repository and .Tag and (.Created | type == "number" or type == "string"))
      | (.Created | tonumber) as $created
      | select($created > 0 and $created < $cutoff)
      | "\(.Namespace) \(.Repository) \(.Tag) \($created | strftime("%Y-%m-%d"))"
    ' | while read -r ns repo tag created; do

        if [[ "$repo" == "$ICR_REGISTRY"/* ]]; then
          full_image="${repo}:$tag"
        elif [[ "$repo" == "$ns/"* ]]; then
          full_image="$ICR_REGISTRY/$repo:$tag"
        else
          full_image="$ICR_REGISTRY/$ns/$repo:$tag"
        fi
        #echo " Constructed full image path: $full_image"
        echo "Old Image is  $full_image (Created: $created)"

        if [[ "$DRY_RUN" == true ]]; then
          echo " [DRY RUN] Would delete image tag: $full_image"
        else
          echo " Deleting image tag: $full_image"
        fi

          # Get manifest digest for deletion
      echo " Inspecting image manifest for: $full_image"
      manifest_json=$(ibmcloud cr image-inspect "$full_image" --output json 2>/dev/null | sed -n '/^{/,/^}/p')

        # Check if we got valid JSON
        if echo "$manifest_json" | jq empty >/dev/null 2>&1; then
        digest=$(echo "$manifest_json" | jq -r '.Id')
    
        if [[ -z "$digest" || "$digest" == "null" ]]; then
        echo " Could not get digest for $full_image, skipping manifest deletion"
        else
        manifest_path="$full_image@$digest"
        if [[ "$DRY_RUN" == true ]]; then
            echo "[DRY RUN] Would delete manifest: $manifest_path"
        else
            echo "Deleting manifest: $manifest_path"
        fi
      fi
      else
            echo "Invalid JSON from ibmcloud cr image-inspect for $full_image, skipping manifest deletion"
      fi
      done
      else
      echo "No images older than $THRESHOLD_DAYS days found"
      fi
      else
      echo "Failed to fetch images or invalid JSON response"
    fi
  fi
done < "$INPUT_YAML"
