#!/bin/bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================

# Team Onboarding Orchestrator Script
# This is the main script that runs in the merge pipeline
# It orchestrates the complete onboarding process:
#   1. Provision team infrastructure (Resource Groups, Secret Groups, CD, COS, Access Groups, Secrets)
#   2. Create compliance repositories (inventory and incident repos)

set -e  # Exit on error

# Source common utilities
source "${PATH_TO_GENCTL_CI}/onepipeline/utils/onboarding_validation_utils.sh"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Initialize
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}                                                                            ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ${GREEN}🚀 UUC Team Onboarding Pipeline${NC}                                        ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                                            ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Check prerequisites
echo -e "${BLUE}[STEP 0/2]${NC} Checking prerequisites..."
check_python_available
check_python_dependencies
check_github_token
echo -e "${GREEN}✓${NC} Prerequisites check passed"
echo ""

# Track overall status
OVERALL_EXIT_CODE=0
INFRA_STATUS="⏭️  SKIPPED"
REPOS_STATUS="⏭️  SKIPPED"

# Step 1: Provision Team Infrastructure
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC} ${CYAN}[STEP 1/2]${NC} Provisioning Team Infrastructure & Secrets                   ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}[INFO]${NC} This step creates/updates:"
echo -e "  • Resource Groups"
echo -e "  • Secret Groups"
echo -e "  • Continuous Delivery Instances"
echo -e "  • COS Buckets"
echo -e "  • Access Groups (structure)"
echo -e "  • Custom Secrets Configuration"
echo -e "  • PSIRT IDs for Mend SAST"
echo ""

if [ -f "${SCRIPT_DIR}/provision_team_infrastructure.sh" ]; then
    if bash "${SCRIPT_DIR}/provision_team_infrastructure.sh"; then
        INFRA_STATUS="${GREEN}✓ SUCCESS${NC}"
        echo -e "${GREEN}✓${NC} Infrastructure provisioning completed"
    else
        INFRA_STATUS="${RED}✗ FAILED${NC}"
        echo -e "${RED}✗${NC} Infrastructure provisioning failed"
        OVERALL_EXIT_CODE=1
        # Continue with other steps even if this fails
    fi
else
    INFRA_STATUS="${YELLOW}⚠ NOT FOUND${NC}"
    echo -e "${YELLOW}[WARNING]${NC} provision_team_infrastructure.sh not found"
fi

echo ""
echo ""

# Step 2: Create Compliance Repositories
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC} ${CYAN}[STEP 2/2]${NC} Creating Compliance Repositories                               ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}[INFO]${NC} This step creates (if create: true):"
echo -e "  • Inventory repositories (compliance evidence storage)"
echo -e "  • Incident repositories (issue tracking)"
echo ""

if [ -f "${SCRIPT_DIR}/create_compliance_repos.sh" ]; then
    if bash "${SCRIPT_DIR}/create_compliance_repos.sh"; then
        REPOS_STATUS="${GREEN}✓ SUCCESS${NC}"
        echo -e "${GREEN}✓${NC} Repository creation completed"
    else
        REPOS_STATUS="${RED}✗ FAILED${NC}"
        echo -e "${RED}✗${NC} Repository creation failed"
        OVERALL_EXIT_CODE=1
        # Continue with other steps even if this fails
    fi
else
    REPOS_STATUS="${YELLOW}⚠ NOT FOUND${NC}"
    echo -e "${YELLOW}[WARNING]${NC} create_compliance_repos.sh not found"
fi

echo ""
echo ""

# Final Summary
echo -e "${BLUE}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║${NC}                                                                            ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}  ${CYAN}📊 Onboarding Pipeline Summary${NC}                                         ${BLUE}║${NC}"
echo -e "${BLUE}║${NC}                                                                            ${BLUE}║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Step 1:${NC} Infrastructure & Secrets       ${INFRA_STATUS}"
echo -e "  ${CYAN}Step 2:${NC} Compliance Repositories        ${REPOS_STATUS}"
echo ""

if [ $OVERALL_EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}                                                                            ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${GREEN}✓ Onboarding Pipeline Completed Successfully!${NC}                          ${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}                                                                            ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}[NEXT STEPS]${NC}"
    echo -e "  1. Review and merge the PR created in uuc-infrastructure-tf-module repository"
    echo -e "  2. Run terraform plan on the team branch to preview infrastructure and secrets changes"
    echo -e "  3. Run terraform apply to provision resources and secrets"
    echo -e "  4. Configure access groups in <team-slug>.auto.tfvars (if needed)"
    echo -e "  5. Verify secrets are provisioned in IBM Secrets Manager"
    echo ""
else
    echo -e "${RED}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${NC}                                                                            ${RED}║${NC}"
    echo -e "${RED}║${NC}  ${RED}✗ Onboarding Pipeline Completed with Errors${NC}                             ${RED}║${NC}"
    echo -e "${RED}║${NC}                                                                            ${RED}║${NC}"
    echo -e "${RED}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}[ACTION REQUIRED]${NC}"
    echo -e "  1. Review the error messages above"
    echo -e "  2. Check the pipeline logs for detailed error information"
    echo -e "  3. Fix any issues and re-run the pipeline"
    echo -e "  4. Contact the UUC platform team if you need assistance"
    echo ""
fi

echo -e "${BLUE}════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

exit $OVERALL_EXIT_CODE

# Made with Bob