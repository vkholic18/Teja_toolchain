# UUC Team Onboarding - Merge Pipeline

This directory contains the automated merge pipeline scripts for the UUC (Unified Underlay Cloud) team onboarding process.

## Overview

When a PR is merged to the `uuc-service-cicd-onboarding` repository, the merge pipeline automatically:

1. **Provisions Team Infrastructure** - Creates IBM Cloud resources
2. **Creates Compliance Repositories** - Sets up inventory and incident tracking repos
3. **Syncs Secrets Configuration** - Updates custom secrets in infrastructure repo

## Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Merge Pipeline Trigger                        │
│              (PR merged to main branch)                          │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   onboard_team.sh                                │
│              (Main Orchestrator Script)                          │
└────────────────────────┬────────────────────────────────────────┘
                         │
         ┌───────────────┼───────────────┐
         │               │               │
         ▼               ▼               ▼
┌────────────────┐ ┌──────────────┐ ┌─────────────────┐
│ Step 1:        │ │ Step 2:      │ │ Step 3:         │
│ Infrastructure │ │ Repositories │ │ Secrets Config  │
│ Provisioning   │ │ Creation     │ │ Sync            │
└────────────────┘ └──────────────┘ └─────────────────┘
         │               │               │
         ▼               ▼               ▼
┌────────────────┐ ┌──────────────┐ ┌─────────────────┐
│ Creates PR in  │ │ Creates      │ │ Creates PR in   │
│ infrastructure │ │ GitHub repos │ │ infrastructure  │
│ repo with:     │ │ with:        │ │ repo with:      │
│ • Team module  │ │ • README     │ │ • Custom secrets│
│ • team.tfvars  │ │ • Structure  │ │ • PSIRT IDs     │
│ • Access groups│ │ • Templates  │ │                 │
└────────────────┘ └──────────────┘ └─────────────────┘
```

## Scripts

### 1. `onboard_team.sh` (Main Orchestrator)

**Purpose**: Coordinates the entire onboarding process

**What it does**:
- Checks prerequisites (Python, dependencies, GitHub token)
- Executes all three onboarding steps sequentially
- Provides comprehensive status reporting
- Handles errors gracefully (continues even if one step fails)

**Usage**:
```bash
./onboard_team.sh
```

**Environment Variables Required**:
- `GITHUB_TOKEN` - GitHub Enterprise token
- `PATH_TO_GENCTL_CI` - Path to genctl-ci directory
- `PATH_TO_WORKSPACE_REPO` - Path to workspace repository

---

### 2. `provision_team_infrastructure.sh`

**Purpose**: Provisions IBM Cloud infrastructure for new teams

**What it does**:
- Detects changed onboarding.yaml files
- Extracts team information (name, slug, COS bucket config)
- Checks if team module already exists in main.tf
- For **new teams**:
  - Generates team module block in main.tf
  - Creates team directory: `teams/<team-slug>/`
  - Creates team.tfvars with basic structure
  - Creates PR in infrastructure repository

**Resources Provisioned** (via Terraform after PR merge):
- **Resource Group**: `UUC_<Team_Name>`
- **Secret Group**: `sg-uuc-<team-slug>`
- **Continuous Delivery Instance**: `Continuous Delivery-<Team Name>`
- **COS Bucket**: `uuc-<team-slug>-ci-storage` (if not using existing)
- **Access Groups**: Structure (configured later in team.tfvars)

**Example Output**:
```
🏗️  UUC Team Infrastructure Provisioning
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[INFO] Processing team: Core Services (core-services)
[INFO] New team detected - provisioning infrastructure
[SUCCESS] Added Core Services team module to main.tf
[SUCCESS] Created team directory and team.tfvars
[SUCCESS] Pull request created successfully!
PR #123: https://github.ibm.com/genctl-cicd/uuc-infrastructure-tf-module/pull/123
```

**Manual Actions Required After PR Merge**:
1. Add `module.<team-slug>` to `access_groups` module `depends_on` list in main.tf
2. Configure access groups in `teams/<team-slug>/team.tfvars`
3. Run `terraform plan` to preview changes
4. Run `terraform apply` to provision resources

---

### 3. `create_compliance_repos.sh`

**Purpose**: Creates inventory and incident repositories

**What it does**:
- Parses onboarding.yaml for repository configuration
- Checks `create: true/false` flags
- For each repository to create:
  - Checks if repository already exists
  - Creates private GitHub repository
  - Initializes with README and structure
  - Sets up directory templates

**Repositories Created**:

#### Inventory Repository
- **Purpose**: Compliance evidence storage
- **Structure**:
  ```
  inventory/
  ├── builds/          # Build metadata
  ├── scans/           # Security scan results
  ├── tests/           # Test results
  └── deployments/     # Deployment records
  evidence/
  └── compliance/      # Compliance evidence files
  ```

#### Incident Repository
- **Purpose**: Issue and incident tracking
- **Features**:
  - GitHub Issues integration
  - ServiceNow integration
  - PagerDuty integration
  - Automated incident creation from pipeline failures

**Example Output**:
```
📦 UUC Compliance Repository Creation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[INFO] Processing service: myservice (Core Services team)
[INFO] Inventory repository creation requested
[SUCCESS] Repository created: https://github.ibm.com/genctl-cicd/uuc-core-services-myservice-compliance-inventory
[SUCCESS] README.md created
[SUCCESS] Inventory directory structure created
```

---

### 4. `add_update_secrets.sh`

**Purpose**: Syncs custom secrets configuration to infrastructure repository

**What it does**:
- Detects changed onboarding.yaml files
- Groups files by team (multiple services per team)
- Extracts **custom secrets only** (mandatory: false)
- Extracts PSIRT IDs for Mend SAST secrets
- Combines and deduplicates secrets across services
- Updates team.tfvars files
- Creates PR in infrastructure repository

**What Gets Updated**:
```hcl
# PSIRT IDs for Mend SAST Secrets
psirt_ids = ["PSIRT_PRD0000420", "PSIRT_PRD0000421"]

# Custom Secrets Configuration (Team-Managed)
custom_secrets = [
  {
    name        = "artifactory-token"
    description = "artifactory token"
    group       = "common"  # ci, cd, or common (for metadata/labels)
    mandatory   = false
    type        = null
  }
]
```

**What's NOT Included**:
- Mandatory secrets (GARA, ServiceNow, FID credentials)
- These are automatically provisioned by the Terraform module

**Example Output**:
```
🔐 UUC Secrets Configuration Sync
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[INFO] Processing team: core-services
[INFO] Processing 2 service(s):
  - rhos-installation-onboarding.yaml
  - virtualization-operator-onboarding.yaml
[SUCCESS] Generated custom secrets configuration for core-services
[SUCCESS] Updated team.tfvars for core-services
[SUCCESS] Pull request created successfully!
PR #124: https://github.ibm.com/genctl-cicd/uuc-infrastructure-tf-module/pull/124
```

---

## Workflow

### For New Teams

1. **PR Created**: Team creates PR with onboarding.yaml in `uuc-service-cicd-onboarding`
2. **PR Validation**: PR pipeline validates mandatory files, YAML structure, etc.
3. **PR Merged**: Team merges PR to main branch
4. **Merge Pipeline Triggered**: Automatically runs onboard_team.sh
5. **Infrastructure PR Created**: PR created in infrastructure repo with team module
6. **Repositories Created**: Inventory and incident repos created (if requested)
7. **Secrets PR Created**: PR created with custom secrets configuration
8. **Manual Review**: Platform team reviews and merges infrastructure PRs
9. **Terraform Apply**: Resources provisioned in IBM Cloud
10. **Team Onboarded**: Team can start using CI/CD pipelines

### For Existing Teams (Updates)

1. **PR Created**: Team updates onboarding.yaml
2. **PR Validation**: Changes validated
3. **PR Merged**: Changes merged to main
4. **Merge Pipeline Triggered**: Runs onboard_team.sh
5. **Infrastructure Step**: Skipped (team already exists)
6. **Repositories Step**: Skipped (repos already exist)
7. **Secrets PR Created**: PR created with updated secrets
8. **Manual Review**: Platform team reviews and merges
9. **Terraform Apply**: Secrets updated in IBM Secrets Manager

---

## Configuration

### Environment Variables

| Variable | Description | Required | Example |
|----------|-------------|----------|---------|
| `GITHUB_TOKEN` | GitHub Enterprise token | Yes | `ghp_xxx...` |
| `PATH_TO_GENCTL_CI` | Path to genctl-ci directory | Yes | `/workspace/CI/genctl-ci` |
| `PATH_TO_WORKSPACE_REPO` | Path to workspace repo | Yes | `/workspace` |

### Repository Configuration

**Infrastructure Repository**:
- URL: `https://github.ibm.com/genctl-cicd/uuc-infrastructure-tf-module`
- Branch: `main`
- Access: Platform team

**Onboarding Repository**:
- URL: `https://github.ibm.com/genctl-cicd/uuc-service-cicd-onboarding`
- Branch: `main`
- Access: All teams

---

## Error Handling

The pipeline is designed to be resilient:

- **Step Failures**: If one step fails, others continue
- **Idempotency**: Scripts can be re-run safely
- **Validation**: Checks prerequisites before execution
- **Logging**: Detailed logs for troubleshooting
- **Status Reporting**: Clear success/failure indicators

### Common Issues

#### Issue: "GitHub token not found"
**Solution**: Set `GITHUB_TOKEN` environment variable
```bash
export GITHUB_TOKEN=<your_token>
```

#### Issue: "Team module already exists"
**Solution**: This is expected for existing teams. The infrastructure provisioning step will be skipped.

#### Issue: "Repository already exists"
**Solution**: This is expected if repos were created previously. The repository creation step will skip existing repos.

#### Issue: "Failed to create pull request"
**Solution**: 
- Check GitHub token has write access
- Verify repository URLs are correct
- Check network connectivity

---

## Testing

### Local Testing

Each script can be tested individually:

```bash
# Test infrastructure provisioning
./provision_team_infrastructure.sh

# Test repository creation
./create_compliance_repos.sh

# Test secrets sync
./add_update_secrets.sh

# Test full pipeline
./onboard_team.sh
```

### Prerequisites for Local Testing

1. Set environment variables:
   ```bash
   export GITHUB_TOKEN=<your_token>
   export PATH_TO_GENCTL_CI=$(pwd)/CI/genctl-ci
   export PATH_TO_WORKSPACE_REPO=$(pwd)
   ```

2. Install dependencies:
   ```bash
   pip3 install pyyaml
   ```

3. Ensure changed onboarding files exist

---

## Monitoring

### Pipeline Logs

Check pipeline logs for:
- Step execution status
- PR URLs created
- Error messages
- Warnings

### Pull Requests

Monitor PRs in infrastructure repository:
- Review changes before merging
- Verify Terraform plans
- Check for manual action items

### Resources

After Terraform apply, verify:
- Resource groups created
- Secret groups created
- CD instances provisioned
- COS buckets created
- Secrets provisioned

---

## Maintenance

### Adding New Steps

To add a new step to the pipeline:

1. Create new script in `steps/` directory
2. Make it executable: `chmod +x new_script.sh`
3. Add step to `onboard_team.sh` orchestrator
4. Update this README

### Modifying Existing Steps

1. Update the script
2. Test locally
3. Update documentation
4. Create PR for review

---

## Support

For issues or questions:
- Check pipeline logs
- Review error messages
- Contact UUC platform team
- Create issue in onboarding repository

---

## Related Documentation

- [Onboarding Guide](https://github.ibm.com/genctl-cicd/uuc-service-cicd-onboarding/blob/main/README.md)
- [Infrastructure Repository](https://github.ibm.com/genctl-cicd/uuc-infrastructure-tf-module)
- [Secrets Management](../../../../../../UUC/uuc-infrastructure-tf-module/scripts/secrets/README.md)
- [How to Run add_update_secrets.sh](../../../../../../HOW_TO_RUN_ADD_UPDATE_SECRETS.md)

---

**Last Updated**: 2026-06-22  
**Maintained By**: UUC Platform Team  
**Version**: 1.0.0