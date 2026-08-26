#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

# Source bash tools
source ${PATH_TO_GENCTL_CI}/tools/ci_bash_tools/tools.sh

# Source one-pipeline utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/one_pipeline_utils.sh

# Source colors
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/colors.sh

# Source runners
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/ci_logic_runners.sh

# Source rhos utils
source ${PATH_TO_GENCTL_CI}/onepipeline/utils/uuc_rhos_utils.sh

CUSTOM_IMAGE_MAPPING_SCRIPT="${PATH_TO_WORKSPACE_REPO}/hack/ci/create-custom-image-mapping.sh"

echo "SM prerequisites"
source "${PATH_TO_WORKSPACE_REPO}/hack/ci/pull_secret.sh"

# Skip this validation flow entirely when the workspace does not provide custom image mapping logic.
if [[ ! -f "${CUSTOM_IMAGE_MAPPING_SCRIPT}" ]]; then
    echo "Custom image mapping script not found at ${CUSTOM_IMAGE_MAPPING_SCRIPT}. Skipping validation."
    exit 0
fi

# Skip this validation flow when explicitly disabled through environment configuration.
if [[ "${SKIP_VALIDATE_THIRD_PARTY_IMAGES:-false}" == "true" ]]; then
    echo "SKIP_VALIDATE_THIRD_PARTY_IMAGES is true. Skipping validation."
    exit 0
fi

# Read the OCP release version used by the workspace mirror/build flow.
export OCP_RELEASE_VERSION=$(yq -r '.deployment.ocp_release_version | select(. != null)' ${PATH_TO_WORKSPACE_REPO}/hack/ci/pipeline.yaml)

# Docker auth for oc/oc-mirror is generated into a temporary config directory.
export DOCKER_CONFIG="${PATH_TO_WORKSPACE_REPO}/temp_sec_artifactory"

# Create DOCKER_CONFIG directory
echo "Creating DOCKER_CONFIG directory: ${DOCKER_CONFIG}"
mkdir -p "${DOCKER_CONFIG}"

# Generate registry authentication config used by the mirror/build steps.
echo "Generating authentication configuration..."
${PATH_TO_GENCTL_CI}/onepipeline/jobs/generate_auth_json.sh

# Ensure Docker auth was created before continuing.
if [[ ! -f "${DOCKER_CONFIG}/config.json" ]]; then
    echo "Error: Failed to create ${DOCKER_CONFIG}/config.json"
    exit 1
fi

# Create the local oc-mirror workspace directory if it does not already exist.
echo "Create working directory"
mkdir -p ocp_mirror_work_dir

# Install required tooling and run the workspace build/mirror logic.
echo "Running OCP mirror for release"
install_pkgs
install_oc_cli

${CUSTOM_IMAGE_MAPPING_SCRIPT}

MAPPING_FILE="${PATH_TO_GENCTL_CI}/final-ci-mapping.txt"
THIRD_PARTY_YAML="${PATH_TO_WORKSPACE_REPO}/hack/ci/third-party-images.yaml"
WORKSPACE_REPO="${WORKSPACE_REPO:-}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# Check if mapping file exists
if [[ ! -f "${MAPPING_FILE}" ]]; then
    log_error "Mapping file not found: ${MAPPING_FILE}"
    exit 1
fi

# Check if WORKSPACE_REPO is set
if [[ -z "${WORKSPACE_REPO}" ]]; then
    log_error "WORKSPACE_REPO environment variable is not set"
    log_info "WORKSPACE_REPO should be set to the component name (e.g., metallb-operator, kyverno-operator)"
    exit 1
fi

log_info "Reading mapping file: ${MAPPING_FILE}"
log_info "Repository name: ${WORKSPACE_REPO}"

# Extract image paths from mapping file
declare -a EXPECTED_IMAGES=()

while IFS= read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Determine format and extract destination image
    if [[ "$line" =~ ^docker:// ]]; then
        # Format 1: docker://source=docker://destination
        # Extract destination (after =)
        dest_image=$(echo "$line" | sed 's/.*=//')
        # Remove docker:// prefix
        dest_image=$(echo "$dest_image" | sed 's|^docker://||')
    else
        # Format 2: source destination (space-separated)
        # Get second column
        dest_image=$(echo "$line" | awk '{print $2}')
    fi

    # Skip if destination contains localhost (but only if it's the actual destination)
    if [[ "$dest_image" =~ localhost: ]]; then
        log_info "Skipping localhost entry: $line"
        continue
    fi

    # Extract image path: WORKSPACE_REPO/path/to/image (without tag/digest)
    # Look for WORKSPACE_REPO in the path and extract everything after registry until : or @
    if [[ "$dest_image" =~ ${WORKSPACE_REPO}/([^:@]+) ]]; then
        image_path="${WORKSPACE_REPO}/${BASH_REMATCH[1]}"
        EXPECTED_IMAGES+=("$image_path")
    else
        log_warn "Could not extract ${WORKSPACE_REPO} path from: $dest_image"
    fi

done < "${MAPPING_FILE}"

# Remove duplicates and sort
EXPECTED_IMAGES=($(printf '%s\n' "${EXPECTED_IMAGES[@]}" | sort -u))

log_info "Found ${#EXPECTED_IMAGES[@]} unique images in mapping file"

if [[ ${#EXPECTED_IMAGES[@]} -eq 0 ]]; then
    log_error "No images found in mapping file for repository: ${WORKSPACE_REPO}"
    log_info "Check that WORKSPACE_REPO matches the component name in the destination images"
    exit 1
fi

# Check if third-party-images.yaml exists
if [[ ! -f "${THIRD_PARTY_YAML}" ]]; then
    log_warn "File does not exist: ${THIRD_PARTY_YAML}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "ACTION REQUIRED: Create the following file"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "File: ${THIRD_PARTY_YAML}"
    echo ""
    echo "Content:"
    echo "---"
    echo "images:"
    for img in "${EXPECTED_IMAGES[@]}"; do
        echo "  - ${img}"
    done
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
fi

log_info "Reading third-party-images.yaml: ${THIRD_PARTY_YAML}"

# Extract images from YAML file (lines starting with "  - ")
declare -a YAML_IMAGES=()
while IFS= read -r line; do
    # Match lines like "  - component/image"
    if [[ "$line" =~ ^[[:space:]]*-[[:space:]]+(.*) ]]; then
        image="${BASH_REMATCH[1]}"
        YAML_IMAGES+=("$image")
    fi
done < "${THIRD_PARTY_YAML}"

# Sort YAML images
YAML_IMAGES=($(printf '%s\n' "${YAML_IMAGES[@]}" | sort -u))

log_info "Found ${#YAML_IMAGES[@]} images in third-party-images.yaml"

# Compare the two lists
declare -a MISSING_IN_YAML=()
declare -a EXTRA_IN_YAML=()

# Find images in mapping but not in YAML
for img in "${EXPECTED_IMAGES[@]}"; do
    found=0
    for yaml_img in "${YAML_IMAGES[@]}"; do
        if [[ "$img" == "$yaml_img" ]]; then
            found=1
            break
        fi
    done
    if [[ $found -eq 0 ]]; then
        MISSING_IN_YAML+=("$img")
    fi
done

# Find images in YAML but not in mapping
for yaml_img in "${YAML_IMAGES[@]}"; do
    found=0
    for img in "${EXPECTED_IMAGES[@]}"; do
        if [[ "$yaml_img" == "$img" ]]; then
            found=1
            break
        fi
    done
    if [[ $found -eq 0 ]]; then
        EXTRA_IN_YAML+=("$yaml_img")
    fi
done

# Report results
VALIDATION_FAILED=0

if [[ ${#MISSING_IN_YAML[@]} -gt 0 ]]; then
    VALIDATION_FAILED=1
    echo ""
    log_error "Missing entries in third-party-images.yaml (${#MISSING_IN_YAML[@]} images)"
    echo ""
    echo "The following images are in the mapping file but NOT in third-party-images.yaml:"
    for img in "${MISSING_IN_YAML[@]}"; do
        echo "  - ${img}"
    done
fi

if [[ ${#EXTRA_IN_YAML[@]} -gt 0 ]]; then
    VALIDATION_FAILED=1
    echo ""
    log_error "Extra entries in third-party-images.yaml (${#EXTRA_IN_YAML[@]} images)"
    echo ""
    echo "The following images are in third-party-images.yaml but NOT in the mapping file:"
    for img in "${EXTRA_IN_YAML[@]}"; do
        echo "  - ${img}"
    done
fi

if [[ $VALIDATION_FAILED -eq 1 ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "ACTION REQUIRED: Update third-party-images.yaml"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "File: ${THIRD_PARTY_YAML}"
    echo ""
    echo "Expected content (complete file):"
    echo "---"
    echo "images:"
    for img in "${EXPECTED_IMAGES[@]}"; do
        echo "  - ${img}"
    done
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [[ ${#MISSING_IN_YAML[@]} -gt 0 ]]; then
        log_warn "Add these ${#MISSING_IN_YAML[@]} entries to third-party-images.yaml"
    fi

    if [[ ${#EXTRA_IN_YAML[@]} -gt 0 ]]; then
        log_warn "Remove these ${#EXTRA_IN_YAML[@]} entries from third-party-images.yaml"
    fi

    exit 1
else
    echo ""
    log_success "✓ Validation passed!"
    log_success "✓ All ${#EXPECTED_IMAGES[@]} images from mapping file are present in third-party-images.yaml"
    log_success "✓ No extra entries found in third-party-images.yaml"
    echo ""
fi
