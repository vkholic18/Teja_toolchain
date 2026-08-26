# uuc-service-cicd-onboarding

Configuration parameters and onboarding definitions for integrating services with the CI/CD infrastructure.

**Configuration Version:** 1.0

---

## Onboarding Process

Each team has a **dedicated branch** named `<team_slug>-onboarding` (e.g. `fabric-onboarding`, `cos-onboarding`). All onboarding work — adding a new service or updating an existing one — must be done through that branch.

Every team branch has **two types of files** at its root:

| File | Purpose |
|------|---------|
| `commons.yaml` | **One per team branch.** Holds all team-level data shared across every service: FIDs, PSIRT ID, IBM Cloud accounts, and all secrets. **All secrets must be declared here.** |
| `<service_name>-onboarding.yaml` | **One per service.** Service-specific data only: `service_name`, `cicd_profile`, `app_repo`, compliance repos, Slack IDs, mandatory/optional files, and deployment targets. |

> **Important:** Fields defined in `commons.yaml` (team-level fields and all secrets) **must not be duplicated** in service onboarding files. The validator will error if it detects commons-owned fields in a service file.

> **⛔ Pre-requisite:** `commons.yaml` **must exist and be fully populated** in your team branch before any `<service_name>-onboarding.yaml` file can be added or merged. The pipeline validation will fail for every service file if `commons.yaml` is missing. Complete step 3 below before creating any service file.

### Step-by-step

1. **Check out your team's branch** — never work directly on `main`.
   ```bash
   git checkout <team_slug>-onboarding
   # e.g. git checkout fabric-onboarding
   ```

2. **Create your working branch off the team branch.**
   Use any name that does **not** end with `-onboarding` — that suffix is reserved for team base branches.
   ```bash
   git checkout -b feat/<service-name>-onboarding-config
   ```

3. **⛔ Pre-requisite — set up `commons.yaml` before adding any service file.**
   `commons.yaml` must exist at the branch root and be fully populated before any service onboarding file is created or merged. This step only needs to be done once per team branch; subsequent service additions can skip it if `commons.yaml` is already in place.

   If `commons.yaml` does not yet exist, copy the latest template from `main`:
   ```bash
   git fetch origin main
   git checkout origin/main -- commons.yaml
   ```
   Edit `commons.yaml` to fill in your team's values. **Do not copy `commons.yaml` from another team's branch** — always start from the `main` branch template to pick up the latest platform-managed fields.

   > The pipeline rejects all service files in a PR if `commons.yaml` is absent or contains validation errors. Fix `commons.yaml` first, then proceed to add service files.

4. **Create your service onboarding file** at the branch root, named `<service_name>-onboarding.yaml`.

   > **⚠️ Always fetch the latest profile template from `main`** before creating your service file. The templates on `main` are the authoritative, up-to-date reference. Copying from an older branch risks missing recent platform-required fields.

   ```bash
   git fetch origin main
   # Copy the template that matches your cicd_profile:
   git checkout origin/main -- onboarding-ci_cd.yaml    # for ci_cd profile
   # or
   git checkout origin/main -- onboarding-ci_only.yaml  # for ci_only profile
   # or
   git checkout origin/main -- onboarding-cd_only.yaml  # for cd_only profile
   # or
   git checkout origin/main -- onboarding-minimal.yaml  # for minimal profile

   cp onboarding-<profile>.yaml <service_name>-onboarding.yaml
   ```

   | Profile | Reference template | Use case |
   |---|---|---|
   | `minimal` | `onboarding-minimal.yaml` | Documentation-only repos |
   | `ci_only` | `onboarding-ci_only.yaml` | Internal artifacts, no CD |
   | `ci_cd` | `onboarding-ci_cd.yaml` | Full production services |
   | `cd_only` | `onboarding-cd_only.yaml` | CD pipeline only (Special Case)|

   ```
   commons.yaml                          ← team-level file (one per branch)
   <service_name>-onboarding.yaml        ← your service file
   onboarding-minimal.yaml               ← reference template (do not modify or delete)
   onboarding-ci_only.yaml               ← reference template (do not modify or delete)
   onboarding-ci_cd.yaml                 ← reference template (do not modify or delete)
   onboarding-cd_only.yaml               ← reference template (do not modify or delete)
   ```

   The reference templates are platform-managed and must not be renamed, modified, or deleted in team PRs.
   Only DevOps-owned changes are allowed for those files, and those PRs must include the `uuc-devops` label.

5. **Open a PR** targeting your team's `<team_slug>-onboarding` branch (not `main`).

6. **The pipeline validates automatically** — see [Rules enforced by the pipeline](#rules-enforced-by-the-pipeline) below.

### Team branches

| Team | Branch |
|---|---|
| Fabric | `fabric-onboarding` |
| DCMS | `dcms-onboarding` |
| SLAD | `slad-onboarding` |
| Core Services | `core-services-onboarding` |
| COS | `cos-onboarding` |
| File Block | `file-block-onboarding` |
| Network Underlay | `network-underlay-onboarding` |
| Network Services | `network-services-onboarding` |
| Observability | `observability-onboarding` |
| PAG | `pag-onboarding` |
| Pentest | `pentest-onboarding` |
| Seceng | `seceng-onboarding` |
| VPC | `vpc-onboarding` |

### Rules enforced by the pipeline

| Rule | Detail |
|---|---|
| Filename format | Must be `<service_name>-onboarding.yaml` |
| `commons.yaml` required | Every team branch must have exactly one `commons.yaml` at the root |
| Commons fields in service files | `team_name`, `service_fid_dev/prod`, `service_fid_dev/prod_github_username`, `psirt_id`, `ibm_cloud_account_dev/prod`, and `secrets` must **only** appear in `commons.yaml` — the validator errors if they are found in a service file |
| Secrets location | All secrets (CI, CD, common) must be declared exclusively in `commons.yaml`. Service files must not contain a `secrets` block |
| Template protection | `onboarding-minimal.yaml`, `onboarding-ci_only.yaml`, `onboarding-ci_cd.yaml`, `onboarding-cd_only.yaml`, and `commons.yaml` must not be modified or deleted in team PRs; DevOps-only changes require the `uuc-devops` label |
| Branch ownership | `team_name` slug in `commons.yaml` must match the base branch — a COS file cannot be merged into `fabric-onboarding` |
| Working branch name | Must **not** end with `-onboarding` — that suffix is reserved for base branches |

---

## Table of Contents
- [uuc-service-cicd-onboarding](#uuc-service-cicd-onboarding)
  - [Onboarding Process](#onboarding-process)
    - [Step-by-step](#step-by-step)
    - [Team branches](#team-branches)
    - [Rules enforced by the pipeline](#rules-enforced-by-the-pipeline)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [File Structure](#file-structure)
    - [commons.yaml](#commonsyaml)
    - [Service onboarding files](#service-onboarding-files)
  - [CI/CD Profiles](#cicd-profiles)
  - [Configuration Sections](#configuration-sections)
    - [commons.yaml Fields](#commonsyaml-fields)
      - [team\_name](#team_name)
      - [service\_fid\_dev](#service_fid_dev)
      - [service\_fid\_prod](#service_fid_prod)
      - [service\_fid\_dev\_github\_username](#service_fid_dev_github_username)
      - [service\_fid\_prod\_github\_username](#service_fid_prod_github_username)
      - [psirt\_id](#psirt_id)
      - [ibm\_cloud\_account\_dev](#ibm_cloud_account_dev)
      - [ibm\_cloud\_account\_prod](#ibm_cloud_account_prod)
      - [Secrets Configuration](#secrets-configuration)
    - [Service File Fields](#service-file-fields)
      - [service\_name](#service_name)
      - [cicd\_profile](#cicd_profile)
      - [inventory\_repo](#inventory_repo)
      - [incident\_repo](#incident_repo)
      - [compliance\_bucket](#compliance_bucket)
      - [app\_repo](#app_repo)
      - [servicenow\_crn](#servicenow_crn)
    - [Slack Notifications for Secrets Management](#slack-notifications-for-secrets-management)
      - [Overview](#overview-1)
      - [Configuration](#configuration)
      - [How It Works](#how-it-works)
      - [How to Find Your Slack Member ID](#how-to-find-your-slack-member-id)
      - [Slack Channel Configuration](#slack-channel-configuration)
      - [Example Configuration](#example-configuration)
      - [Best Practices](#best-practices)
      - [Troubleshooting](#troubleshooting)
      - [Integration with Secrets Configuration](#integration-with-secrets-configuration)
    - [Secrets Configuration Detail](#secrets-configuration-detail)
      - [Available Keys for Secret Configuration](#available-keys-for-secret-configuration)
      - [Secret Groups](#secret-groups)
      - [Example Secret Configuration](#example-secret-configuration)
      - [Generic Secrets Provided by CI/CD Team](#generic-secrets-provided-by-cicd-team)
      - [Secret Label Format for Zonal/Regional Secrets](#secret-label-format-for-zonalregional-secrets)
    - [Deployment Targets Configuration \& Secret Provisioning](#deployment-targets-configuration--secret-provisioning)
      - [Structure](#structure)
      - [CI Deployment Targets](#ci-deployment-targets)
      - [CD Deployment Targets \& Secret Provisioning](#cd-deployment-targets--secret-provisioning)
      - [Trigger Strategy](#trigger-strategy)
      - [Deployment Types](#deployment-types)
      - [Development Environments — OTC1 \& OTC2](#development-environments--otc1--otc2)
      - [OTC1 Manual Test CD Deployment Trigger](#otc1-manual-test-cd-deployment-trigger)
      - [Complete Example](#complete-example)
  - [Mandatory and Optional Files Configuration](#mandatory-and-optional-files-configuration)
    - [Optional Files Configuration](#optional-files-configuration)
    - [Repository Properties](#repository-properties)
    - [File Properties](#file-properties)
      - [Understanding `can_be_empty`](#understanding-can_be_empty)
  - [Additional Resources](#additional-resources)

---

## Overview

This repository contains:
- **`commons.yaml`** — the team-level template that holds all shared team data and **all secrets**. One file per team branch. Copy the latest version from `main` when setting up a new branch.
- **Profile-specific service templates** (`onboarding-minimal.yaml`, `onboarding-ci_only.yaml`, `onboarding-ci_cd.yaml`, `onboarding-cd_only.yaml`) — reference templates for creating service onboarding files. **Always copy the latest template from `main`** before creating a new service file to ensure you have all current platform-required fields.

The configuration includes team information, service-specific deployment targets, Slack notification settings, file validation rules, and compliance repo configuration.

---

## File Structure

### commons.yaml

`commons.yaml` is the **single source of truth for all team-level configuration** and must exist at the root of every team branch. There is exactly **one** `commons.yaml` per branch — do not create per-service copies.

**Fields owned exclusively by `commons.yaml`:**

| Field | Description |
|-------|-------------|
| `team_name` | Team owning this branch |
| `service_fid_dev` | Dev functional ID email (shared by all services in the branch) |
| `service_fid_prod` | Prod functional ID email (shared by all services in the branch) |
| `service_fid_dev_github_username` | GitHub username for dev FID |
| `service_fid_prod_github_username` | GitHub username for prod FID |
| `psirt_id` | PSIRT ID for Mend SAST (shared across all services) |
| `ibm_cloud_account_dev` | Dev IBM Cloud account |
| `ibm_cloud_account_prod` | Prod IBM Cloud account |
| `secrets` | **All secrets** — CI, CD, and common secret groups |

> **Secrets rule:** All secrets (platform-managed and custom) for the team's secret group must be declared in `commons.yaml`. Service files must **not** contain a `secrets` block. Adding a secret in a service file will cause a validation error.

### Service onboarding files

Service files (`<service_name>-onboarding.yaml`) contain only **service-specific data**:

| Field | Description |
|-------|-------------|
| `service_name` | Unique service identifier |
| `cicd_profile` | Pipeline profile for this service |
| `app_repo` | Application code repositories |
| `inventory_repo` | Compliance inventory repo (`ci_cd` and `cd_only` only) |
| `incident_repo` | Incident tracking repo (`ci_only` and `ci_cd` only) |
| `compliance_bucket` | COS bucket for compliance evidence |
| `servicenow_crn` | ServiceNow CRN (`ci_cd` and `cd_only` only) |
| `slack_member_ids` | Slack IDs to notify on secret lifecycle events |
| `slack_channel` | Optional Slack channel for notifications |
| `mandatory_files` | Files that must exist in the app repo |
| `optional_files` | Optional files (e.g. Mend suppressions) |
| `deployment_targets` | CI/CD deployment environments |

---

## CI/CD Profiles

The `cicd_profile` value controls which pipeline capabilities are provisioned and which fields are required.

| Profile | Reference template | Use case | What is provisioned |
|---------|-------------------|----------|---------------------|
| `minimal` | `onboarding-minimal.yaml` | Documentation repositories only (e.g. product docs, user guides) | PR-based publishing. No CI scanning, no inventory, no CD pipeline. |
| `ci_only` | `onboarding-ci_only.yaml` | Internal artifacts not deployed to production (e.g. SDKs, libraries) | PR + CI pipeline with SAST, compliance checks, unit tests, and release process. No inventory and no CD pipeline. |
| `ci_cd` | `onboarding-ci_cd.yaml` | Deployable production artifacts (e.g. microservices, operators, applications) | Full end-to-end PR + CI (SAST, image scanning, signing) + compliance inventory + CD pipeline. |
| `cd_only` | `onboarding-cd_only.yaml` | Deployable artifacts using an external CI system | CD pipeline only: compliance inventory + CD deployment workflow. No CI scanning (handled externally). |

**Required fields per profile:**

| Field | `minimal` | `ci_only` | `ci_cd` | `cd_only` |
|-------|-----------|-----------|---------|-----------|
| `service_name` | ✅ | ✅ | ✅ | ✅ |
| `cicd_profile` | ✅ | ✅ | ✅ | ✅ |
| `app_repo` | ✅ | ✅ | ✅ | ✅ |
| `compliance_bucket` | ✅ | ✅ | ✅ | ✅ |
| `slack_member_ids` | ✅ | ✅ | ✅ | ✅ |
| `inventory_repo` | ❌ | ❌ | ✅ | ✅ |
| `incident_repo` | ❌ | ✅ | ✅ | ❌ |
| `servicenow_crn` | ❌ | ❌ | ✅ | ✅ |
| `mandatory_files.CI` | `build.sh` only | All 4 files | All 4 files | ❌ |
| `mandatory_files.CD` | ❌ | ❌ | All 3 files | All 3 files |
| `optional_files.mend` | ❌ | ✅ | ✅ | ❌ |
| `deployment_targets.CI` | ❌ | ✅ | ✅ | ❌ |
| `deployment_targets.CD` | ❌ | ❌ | ✅ | ✅ |

**In `commons.yaml` (shared by all profiles):**

| Field | `minimal` | `ci_only` | `ci_cd` | `cd_only` |
|-------|-----------|-----------|---------|-----------|
| `team_name` | ✅ | ✅ | ✅ | ✅ |
| `service_fid_dev` | ✅ | ✅ | ✅ | ✅ |
| `service_fid_prod` | ❌ | ✅ | ✅ | ✅ |
| `service_fid_*_github_username` | dev only | ✅ | ✅ | ✅ |
| `psirt_id` | ❌ | ✅ | ✅ | ❌ |
| `ibm_cloud_account_dev` | ✅ | ✅ | ✅ | ✅ |
| `ibm_cloud_account_prod` | ❌ | ✅ | ✅ | ✅ |
| `secrets.CI` | ❌ | ✅ | ✅ | ❌ |
| `secrets.CD` | ❌ | ❌ | ✅ | ✅ |
| `secrets.common` | 4 mandatory | ✅ | ✅ | ✅ |

---

## Configuration Sections

### commons.yaml Fields

The following fields must be defined in `commons.yaml`. They must **not** appear in service onboarding files.

#### team_name
**File:** `commons.yaml`
**Required:** Yes

**Description:** Name of the team owning this branch. Must be selected from the available teams list. The team slug derived from this value must match the base branch name (e.g., `Core Services` → `core-services-onboarding`).

**Available Teams:**
- Fabric
- DCMS
- SLAD
- Core Services
- COS
- File Block
- Network Underlay
- Network Services
- Observability
- PAG
- Pentest
- Seceng
- VPC

**Example:**
```yaml
team_name: Core Services
```

#### service_fid_dev
**File:** `commons.yaml`
**Required:** Yes

**Description:** Service Functional ID (email) for dev/development environment operations including deployments, repository access, and ServiceNow integration. Shared by all services in the branch.

**IMPORTANT:** This FID must have appropriate permissions on all repositories (app, inventory, incident) for every service in this team branch. See [inventory\_repo](#inventory_repo) and [incident\_repo](#incident_repo) for the exact access requirements per `create` mode.

**Example:**
```yaml
service_fid_dev: my_service_dev@ibm.com
```

#### service_fid_prod
**File:** `commons.yaml`
**Required:** Yes (not required for `minimal` profile)

**Description:** Service Functional ID (email) for production environment operations. Shared by all services in the branch.

**Example:**
```yaml
service_fid_prod: my_service_prod@ibm.com
```

#### service_fid_dev_github_username
**File:** `commons.yaml`
**Required:** Yes *(MANDATORY)*

**Description:** The GitHub Enterprise username corresponding to `service_fid_dev`. Used for GitHub repository access verification in CI/CD toolchains.

> **How to find your GitHub username:** Visit [https://github.ibm.com/settings/profile](https://github.ibm.com/settings/profile) and copy the username shown under your profile.

**Example:**
```yaml
service_fid_dev_github_username: my_fid_github_username
```

#### service_fid_prod_github_username
**File:** `commons.yaml`
**Required:** Yes *(MANDATORY)*

**Description:** The GitHub Enterprise username corresponding to `service_fid_prod`. Used for GitHub repository access verification in CI/CD toolchains.

**Example:**
```yaml
service_fid_prod_github_username: my_fid_prod_github_username
```

#### psirt_id
**File:** `commons.yaml`
**Required:** Yes (not required for `minimal` or `cd_only` profiles)

**Description:** PSIRT (Product Security Incident Response Team) ID for Mend SAST configuration. Used to configure security scanning across all CI services in the branch.

**Format:** `PSIRT_PRD` followed by 7 digits (e.g., `PSIRT_PRD0001234`)

**Example:**
```yaml
psirt_id: PSIRT_PRD0004567
```

**Note:** If you don't have a PSIRT ID, contact the security team to obtain one for your service.

#### ibm_cloud_account_dev
**File:** `commons.yaml`
**Required:** No (Optional)

**Description:** IBM Cloud account ID or name where test/development deployments and related services reside. Shared across all services in the team branch.

**Example:**
```yaml
ibm_cloud_account_dev: dev-account-12345
```

#### ibm_cloud_account_prod
**File:** `commons.yaml`
**Required:** No (Optional)

**Description:** IBM Cloud account ID or name where production deployments and related services reside. Shared across all services in the team branch.

**Example:**
```yaml
ibm_cloud_account_prod: prod-account-67890
```

#### Secrets Configuration

**File:** `commons.yaml`
**Required:** Yes

All secrets for this team's secret group (`sg-uuc-<team-slug>`) are declared in `commons.yaml`. One secret group is shared across all services in the team. **Service files must not contain a `secrets` block** — the validator errors if it finds one.

See [Secrets Configuration Detail](#secrets-configuration-detail) for the full reference.

---

### Service File Fields

The following fields belong exclusively in `<service_name>-onboarding.yaml`.

#### service_name
**File:** `<service_name>-onboarding.yaml`
**Required:** Yes

**Description:** Name of the service. Must match the filename: `<service_name>-onboarding.yaml`. This value is used to create access groups, resource groups, and secrets labels throughout the CI/CD infrastructure.

**Example:**
```yaml
service_name: my-awesome-service
```

#### cicd_profile
**File:** `<service_name>-onboarding.yaml`
**Required:** Yes

**Description:** Defines the set of pipeline capabilities provisioned for this service. See [CI/CD Profiles](#cicd-profiles) for the full comparison table.

**Allowed values:** `minimal` | `ci_only` | `ci_cd` | `cd_only`

**Example:**
```yaml
cicd_profile: ci_cd
```

> **Note:** The `cicd_profile` value also controls which mandatory files are enforced. See [File Properties](#file-properties) for details.

#### inventory_repo
**File:** `<service_name>-onboarding.yaml`
**Required:** Yes for `ci_cd` and `cd_only` profiles — skipped for `minimal` and `ci_only`

**Description:** GitHub repository configuration for compliance inventory tracking. You can either use an existing repository or have the platform create a new one.

**IMPORTANT - Naming Format:** Inventory repository name must follow the format: `uuc-<team_name>-<repo_name>-compliance-inventory`
- `team_name`: Lowercase with spaces replaced by hyphens (e.g., "Core Services" → "core-services")
- `repo_name`: Extracted from app_repo URL (e.g., from `https://github.ibm.com/myorg/myrepo` → "myrepo")
- Example: For team "Core Services" with app_repo "myrepo" → `uuc-core-services-myrepo-compliance-inventory`

**Properties:**
- `repo`: Repository URL (must follow naming format above)
- `branch`: Branch name (optional if creating new repo)
- `create`: Boolean flag — `true` to create new repo, `false` to use existing

**Access requirements:**

| Mode | Who | Required access |
|------|-----|-----------------|
| `create: false` (existing repo) | `onepipelineci@ibm.com` | At least `write` |
| `create: false` (existing repo) | `service_fid_dev` | `admin` |
| `create: false` (existing repo) | `service_fid_prod` | `admin` |
| `create: true` (new repo) | `service_fid_dev` | Org-level permission to create repositories |
| `create: true` (new repo) | `service_fid_dev` + `service_fid_prod` | Must request `admin` via **Access Hub** before merge |

**Example with existing repository:**
```yaml
inventory_repo:
  repo: https://github.ibm.com/myorg/uuc-core-services-myservice-compliance-inventory
  branch: main
  create: false
```

**Example to create new repository:**
```yaml
inventory_repo:
  repo: https://github.ibm.com/myorg/uuc-fabric-myapp-compliance-inventory
  branch: main
  create: true
```

#### incident_repo
**File:** `<service_name>-onboarding.yaml`
**Required:** Yes for `ci_only` and `ci_cd` profiles — skipped for `minimal` and `cd_only`

**Description:** GitHub repository configuration for incident tracking and management.

**Properties:**
- `repo`: Repository URL
- `branch`: Branch name (default: main)
- `create`: Boolean flag — `false` to use existing repo (recommended), `true` to create new repo

**Access requirements:**

| Mode | Who | Required access |
|------|-----|-----------------|
| `create: false` (existing repo) | `onepipelineci@ibm.com` | `admin` |
| `create: false` (existing repo) | `service_fid_dev` | `admin` |
| `create: false` (existing repo) | `service_fid_prod` | `admin` |
| `create: true` (new repo) | `service_fid_dev` | Org-level permission to create repositories |
| `create: true` (new repo) | `service_fid_dev` + `service_fid_prod` | Must request `admin` via **Access Hub** before merge |

> **Note:** When `create: true`, the repository does not exist at PR time so neither FID can be verified against it directly. Access Hub approval must be in place before the merge pipeline runs.

**Example with existing repository (recommended):**
```yaml
incident_repo:
  repo: https://github.ibm.com/myorg/myservice-incidents
  branch: main
  create: false
```

**Example to create new repository:**
```yaml
incident_repo:
  repo: https://github.ibm.com/myorg/myservice-incidents
  branch: main
  create: true
```

#### compliance_bucket
**File:** `<service_name>-onboarding.yaml`
**Required:** Yes

**Description:** Cloud Object Storage (COS) bucket configuration for storing compliance evidence. You can either use your own existing bucket or use the bucket created by CI/CD for your team. **Note:** Only COS buckets are supported, not GitHub repositories.

**Properties:**
- `endpoint`: COS endpoint URL (required when `use_existing: true`)
- `name`: Bucket name (required when `use_existing: true`)
- `use_existing`: Boolean flag
  - `true`: Use your existing bucket (requires custom endpoint and bucket name)
  - `false`: Use the bucket created by CI/CD for your team (endpoint and name are automatically set as `uuc-<team-name-with-spaces-replaced-by-hyphens>-ci-storage`)

**IMPORTANT:** When using your existing bucket (`use_existing: true`), ensure `onepipelineci@ibm.com` has write access to your custom compliance bucket.

**Example with your existing bucket:**
```yaml
compliance_bucket:
  endpoint: https://s3.us-south.cloud-object-storage.appdomain.cloud
  name: my-existing-compliance-bucket
  use_existing: true
```
**Note:** Remember to grant write access to `onepipelineci@ibm.com` for your custom bucket.

**Example to use CI/CD managed bucket:**
```yaml
compliance_bucket:
  endpoint: https://s3.eu-gb.cloud-object-storage.appdomain.cloud
  name: my_bucket
  use_existing: false
```
**Note:** When `use_existing: false`, the endpoint and name values are ignored. The bucket will be automatically created with the name format: `uuc-<team-name-with-spaces-replaced-by-hyphens>-ci-storage`

#### app_repo
**File:** `<service_name>-onboarding.yaml`
**Required:** Yes

**Description:** List of service/microservice/application code repositories to be cloned during CI/CD operations.

**Properties:**
- `repo`: Repository URL
- `branch`: Branch name to use

> **⚠️ Required Access:** Before submitting your onboarding file, ensure the following FIDs have been granted access to every repository listed under `app_repo`:
> - **onepipelineci@ibm.com** (`OnePipeLineCI`) — **Admin** access
> - **clconc@us.ibm.com** (`clconc`) — at least **Write** access
>
> Access is verified automatically by the PR pipeline. Missing permissions will cause the pipeline to fail.

**Example:**
```yaml
app_repo:
  - repo: https://github.ibm.com/myorg/myservice-backend
    branch: main
  - repo: https://github.ibm.com/myorg/myservice-frontend
    branch: main
```

#### servicenow_crn
**File:** `<service_name>-onboarding.yaml`
**Required:** Yes for `ci_cd` and `cd_only` profiles

**Description:** The **SF CRN service name** for this specific service. Used by the CD pipeline when constructing change requests in ServiceNow. This is the short identifier registered with your service's PSIRT / ServiceNow record — **do not** provide a full CRN or include `location` here. The pipeline assembles the full CRN at runtime using the active deployment target's region and the account type (`staging` for non-production; `bluemix` for production).

**Example:**
```yaml
servicenow_crn: ul-fabric-platform
```

> Each service in a team has its own value. Check with your team lead or PSIRT contact to confirm the correct name for your service.

### Slack Notifications for Secrets Management

Slack configuration is **service-specific** and belongs in each `<service_name>-onboarding.yaml` file. All listed members will be notified about secret lifecycle events for this service's secrets in the shared team secret group.

#### Overview

Team members will automatically receive notifications for all secret lifecycle events:
- **about_to_expire**: Secrets approaching expiration (typically 30, 15, and 7 days before)
- **rotated**: Secrets that have been rotated/updated
- **deleted**: Secrets that have been removed
- **created**: New secrets that have been added

#### Configuration

**Property:** `slack_member_ids`

**File:** `<service_name>-onboarding.yaml`

**Required:** Yes

**Type:** List of strings

**Description:** List of Slack member IDs to receive notifications. The example IDs in the template (`U01234ABCDE`, `U56789FGHIJ`) are placeholders — replace them with your actual team's Slack member IDs.

Each entry should be a Slack member ID in the format: `U` or `W` followed by alphanumeric characters (e.g., `U01234ABCDE`, `W4DKC67RN`)

#### How It Works

The Slack member IDs and channel configured in this section will be automatically added as **metadata** to each secret in Secrets Manager during provisioning:

```json
{
  "owner_slack_id": [
    "U0408DJ8K7D",
    "W4DKC67RN"
  ],
  "team": "<team_name>",
  "slack_channel": "#your-channel"
}
```

This metadata enables the notification system to identify which Slack members should be notified and which channel to use when secret lifecycle events occur.

#### How to Find Your Slack Member ID

1. **In Slack Desktop/Web:**
   - Click on your profile picture
   - Select "Profile"
   - Click "More" (three dots)
   - Select "Copy member ID"

2. **Alternative Method:**
   - Right-click on your name in any channel
   - Select "Copy member ID"

The member ID format is: `U` followed by alphanumeric characters (e.g., `U01234ABCDE`)

#### Slack Channel Configuration

**Property:** `slack_channel`

**File:** `<service_name>-onboarding.yaml`

**Required:** No

**Type:** String

**Description:** Service-specific Slack channel for secret notifications. If not provided, notifications will be sent to the default channel: **#uuc-secrets-manager-notifications**

**Format:** Channel name (e.g., `#my-team-alerts`)

**Example:**
```yaml
slack_channel: "#platform-team-alerts"
```

#### Example Configuration

**Single Member with Custom Channel:**
```yaml
slack_member_ids:
  - U01234ABCDE
slack_channel: "#core-services-alerts"
```

**Multiple Members with Default Channel:**
```yaml
slack_member_ids:
  - U01234ABCDE
  - U56789FGHIJ
  - W4DKC67RN
# slack_channel not specified - will use default #uuc-secrets-manager-notifications
```

**No Notifications:**
```yaml
slack_member_ids: []
```

#### Best Practices

1. **Include Multiple Team Members**: Add at least 2-3 team members to ensure notifications are seen
2. **Specify Team Channel**: Provide a service-specific channel to keep notifications organized
3. **Keep List Updated**: Regularly review and update the member list as team composition changes
4. **Verify Member IDs**: Double-check member IDs are correct before committing

#### Troubleshooting

**Not Receiving Notifications?**
- Verify your Slack member ID is correct (format: U followed by alphanumeric)
- Ensure you have the Slack app installed and notifications enabled
- Check that you're part of the organization's Slack workspace

**Wrong Person Receiving Notifications?**
- Double-check the member IDs in the configuration
- Ensure member IDs are not duplicated
- Verify the member is still part of the organization

#### Integration with Secrets Configuration

The Slack member IDs are added as metadata to all secrets defined in the team's secret groups in `commons.yaml`, including both platform-managed and custom secrets.

---

### Secrets Configuration Detail

Secrets labels to be created in Secrets Manager for CI/CD purposes (not runtime purposes). The service owner is responsible for populating and maintaining the actual secret values.

> **File:** `commons.yaml` — all secrets must be declared here. Service files must not contain a `secrets` block.

**Important Notes:**
- The secret group name (`sg-uuc-<team-slug>`) is automatically added as a prefix to all secret names during provisioning
- Secrets marked with `mandatory: true` are **PLATFORM-MANAGED** and **cannot be modified**
- Only secrets with `mandatory: false` can be customized by service teams
- **All custom secrets created by service teams MUST have `mandatory: false`**
- **Runtime secrets should NOT be declared here — fetch them from the vault at runtime**
- One secret group is shared across **all services** in the team branch

#### Available Keys for Secret Configuration

| Key | Required | Default | Description |
|-----|----------|---------|-------------|
| `description` | Yes | - | Human-readable description of the secret |
| `name` | Yes | - | Secret name/label (prefix will be added automatically) |
| `mandatory` | Yes | - | Boolean — `true` for platform-managed, `false` for customizable |
| `type` | No | `global` | Scope: `zonal`, `regional`, or `global` (default) |
| `unique_per_cluster` | No | `false` | Custom secrets only — `true` provisions a separate instance per cluster |

#### Secret Groups

Secrets are organized into three groups:

**1. CI (Continuous Integration)**
- Platform-managed secrets for build and security scanning
- Examples: GARA signing credentials, GARA signing key, Mend SAST tokens (organization, user key, product token)
- Required for `ci_only` and `ci_cd` profiles

**2. CD (Continuous Deployment)**
- Platform-managed secrets for deployment operations
- Examples: ServiceNow tokens (production and test IAM tokens), GARA code signing certificate
- Required for `ci_cd` and `cd_only` profiles

**3. common**
- Mix of platform-managed and custom secrets
- Platform-managed: Service functional ID IBM Cloud API keys (dev and production), Service functional ID GitHub Enterprise PATs (dev and production)
- Custom: Add your own secrets as needed (must have `mandatory: false`)

#### Example Secret Configuration

```yaml
# In commons.yaml
secrets:
  - name: CI
    items:
      # PLATFORM-MANAGED - DO NOT MODIFY
      - description: GARA code signing credentials
        name: gara-signing-credentials
        mandatory: true

      # PLATFORM-MANAGED - DO NOT MODIFY
      - description: GARA code signing key
        name: gara-signing-key
        mandatory: true

      # PLATFORM-MANAGED - DO NOT MODIFY
      - description: Mend SAST organization token
        name: PSIRT_PRD0000000-mend-org-token
        mandatory: true

      # PLATFORM-MANAGED - DO NOT MODIFY
      - description: Mend SAST user key
        name: PSIRT_PRD0000000-mend-user-key
        mandatory: true

      # PLATFORM-MANAGED - DO NOT MODIFY
      - description: Mend SAST product token
        name: PSIRT_PRD0000000-mend-product-token
        mandatory: true

      # OPTIONAL — add custom CI secrets below
      # - description: <your_secret_description>
      #   name: <your_secret_name>
      #   mandatory: false
      #   type: <zonal|regional|global>
      #   unique_per_cluster: false  # optional — default: false

  - name: CD
    items:
      # PLATFORM-MANAGED - DO NOT MODIFY
      - description: ServiceNow production IAM token
        name: service-now-prod-iam-token
        mandatory: true

      # PLATFORM-MANAGED - DO NOT MODIFY
      - description: ServiceNow test IAM token
        name: service-now-test-iam-token
        mandatory: true

      # PLATFORM-MANAGED - DO NOT MODIFY
      - description: GARA code signing certificate
        name: gara-code-signing-certificate
        mandatory: true

      # OPTIONAL — add custom CD secrets below
      # - description: <your_secret_description>
      #   name: <your_secret_name>
      #   mandatory: false
      #   type: <zonal|regional|global>
      #   unique_per_cluster: false  # optional — default: false

  - name: common
    items:
      # PLATFORM-MANAGED - DO NOT MODIFY
      - description: Service functional ID dev IBM Cloud API key
        name: service-functional-id-dev-cloud-apikey
        mandatory: true

      # PLATFORM-MANAGED - DO NOT MODIFY
      - description: Service functional ID production IBM Cloud API key
        name: service-functional-id-prod-cloud-apikey
        mandatory: true

      # PLATFORM-MANAGED - DO NOT MODIFY
      - description: Service functional ID dev GitHub Enterprise personal access token
        name: service-functional-id-dev-ghe-pat
        mandatory: true

      # PLATFORM-MANAGED - DO NOT MODIFY
      - description: Service functional ID production GitHub Enterprise personal access token
        name: service-functional-id-prod-ghe-pat
        mandatory: true

      # OPTIONAL — add custom common secrets below
      # - description: <your_secret_description>
      #   name: <your_secret_name>
      #   mandatory: false
      #   type: <zonal|regional|global>
      #   unique_per_cluster: false  # optional — default: false
```

**Available Values for Custom Secrets:**
- `description`: Any descriptive text for your secret
- `name`: Your secret name (will be prefixed with secret group name automatically — do **not** include the group prefix)
- `mandatory`: Must be `false` for all custom secrets
- `type`: Choose from:
  - `zonal`: One secret per zone — label format: `<secret_group>-<environment_code>-<name>` (e.g. `sg-uuc-myteam-us-south-int01-dal10-zone1-my-secret`)
  - `regional`: One secret per region — label format: `<secret_group>-<short_region>-<deployment_id>-<name>` (e.g. `sg-uuc-myteam-us-east-int01-my-secret`)
  - `global`: Single global secret — label format: `<secret_group>-<name>` — **default if not specified**
- `unique_per_cluster`: `true` to provision a separate secret instance per cluster; appends `<cluster>` between `<environment_code>` and `<name>` (default: `false`)

#### Generic Secrets Provided by CI/CD Team

The following generic environment properties are provided by the CI/CD team for UUC pipelines.

| Exported Variable | Env Property In Pipeline | Description | PR Pipeline | CI Pipeline | Promotion Validation | CD Pipeline |
|-------------------|--------------------------|-------------|-------------|-------------|----------------------|-------------|
| `PIPELINE_NAMESPACE` | `pipeline_namespace` | Identifies the current pipeline type | pr | ci | promotion | cd |
| `SM_ENDPOINT_URL` | `secrets-manager-endpoint-url` | Secrets Manager instance endpoint URL | ✅ | ✅ | ✅ | ✅ |
| `SCOPED_ENV` | `scoped-environment` | ⚠️ **Deprecated** — see note below. Scoped environment identifier (`dev`, `int`, `stage`, `prod`). Removed **September 1, 2026**. | dev | dev | int | int |
| `SERVICE_FID_EMAIL` | `service-functional-id-email` | Email of the service functional ID in use | ✅ | ✅ | ✅ | ✅ |
| `SERVICE_FID_GHE_PAT` | `service-functional-id-ghe-pat` | GitHub Enterprise PAT for the service FID | ✅ | ✅ | ✅ | ✅ |
| `SERVICE_FID_CLOUD_APIKEY` | `service-functional-id-cloud-apikey` | IBM Cloud API key for the service FID | ✅ | ✅ | ✅ | ✅ |
| `SECRET_GROUP` | `secret-group` | Name of the team's Secrets Manager secret group | ✅ | ✅ | ✅ | ✅ |
| `COS_BUCKET_NAME` | `cos-bucket-name` | COS bucket name for compliance evidence storage | ✅ | ✅ | ✅ | ✅ |
| `RESOURCE_GROUP` | `resource-group` | IBM Cloud resource group for the team | ✅ | ✅ | ✅ | ✅ |
| `NETBOX_URL` | `netbox-url` | NetBox instance URL for network source of truth | ✅ | ✅ | ✅ | ✅ |
| `TARGET_ENVIRONMENT` | `target-environment` | Target deployment environment identifier — **preferred replacement for `scoped-environment`** | ❌ | ❌ | ✅ | ✅ |
| `SOURCE_ENVIRONMENT` | `source-environment` | Source environment for promotion pipelines | ❌ | ❌ | ✅ | ❌ |

> ⚠️ **`scoped-environment` deprecation — action required before September 1, 2026**
>
> The `scoped-environment` property (`dev`, `int`, `stage`, `prod`) will be **removed from all UUC CI/CD pipelines on September 1, 2026**. The environment type is already encoded in the `target-environment` value (e.g. `eu-gb-dev01-cloud-zone1-undercloud`), so a separate scoped value is no longer needed.
>
> **What to use instead:**
> - **CD pipelines:** Use `target-environment` — it is already available and carries the full environment code.
> - **CI pipelines:** `target-environment` is not provided in CI. Read the environment code from `/hack/ci/pipeline.yaml` under the `deployment` section:
>   ```yaml
>   deployment:
>     env_code: <your_env_code>
>   ```
>   This value is automatically propagated to downstream/sub-pipelines — no changes are required from the CI/CD team for this propagation.
>
> **Action:** Review any scripts, pipeline logic, or application configuration that currently consumes `scoped-environment` and update them to use the above alternatives before **September 1, 2026**.

#### Secret Label Format for Zonal/Regional Secrets

Secret labels are constructed from the zone's **`environment_code`** (the full value from the env-code YAML, e.g. `eu-gb-dev01-cloud-zone1`) rather than a short Universal Name. This guarantees uniqueness across all tiers and environments.

| Type | `unique_per_cluster` | Label format | Example |
|------|----------------------|-------------|---------|
| `zonal` | `false` (default) | `<secret_group>-<environment_code>-<secret_name>` | `sg-uuc-myteam-us-south-int01-dal10-zone1-kube-config` |
| `zonal` | `true` | `<secret_group>-<environment_code>-<cluster>-<secret_name>` | `sg-uuc-myteam-us-south-int01-dal10-zone1-undercloud-kube-config` |
| `regional` | `false` (default) | `<secret_group>-<short_region>-<deployment_id>-<secret_name>` | `sg-uuc-dcms-us-east-int01-my-secret` |
| `regional` | `true` | `<secret_group>-<short_region>-<deployment_id>-<cluster>-<secret_name>` | `sg-uuc-dcms-us-east-int01-roks-goal-my-secret` |
| `global` | n/a | `<secret_group>-<secret_name>` | `sg-uuc-myteam-kube-config` |

**Where:**
- `<environment_code>` — full value from `undercloud_environment_code.yaml` (e.g. `us-south-int01-dal10-zone1`, `eu-gb-dev01-cloud-zone1`)
- `<short_region>` — first two hyphen-segments of the env_code (e.g. `us-east`, `eu-gb`)
- `<deployment_id>` — third hyphen-segment of the env_code (e.g. `int01`, `prod01`, `dev01`)
- `<cluster>` — cluster name from the env-code YAML (e.g. `undercloud`, `undercloud-otc2`)

**Example — zonal secret without `unique_per_cluster`:**
```yaml
# In commons.yaml
- description: NetBox API token
  name: netbox-token
  mandatory: false
  type: zonal
```

For integration with `targets: all`, this generates one label per zone:
```
sg-uuc-myteam-us-south-int01-dal10-zone1-netbox-token
sg-uuc-myteam-us-south-int01-dal10-zone2-netbox-token
sg-uuc-myteam-us-south-int01-dal10-zone3-netbox-token
...
```

**Example — zonal secret with `unique_per_cluster: true`:**
```yaml
# In commons.yaml
- description: FAST IBM IAM Token
  name: fast-ibm-paas-token
  mandatory: false
  type: zonal
  unique_per_cluster: true
```

For a zone with clusters `undercloud` and `tekton`, this generates one label per cluster per zone:
```
sg-uuc-myteam-us-south-int01-dal10-zone1-undercloud-fast-ibm-paas-token
sg-uuc-myteam-us-south-int01-dal10-zone1-tekton-fast-ibm-paas-token
```

**Example — OTC1 & OTC2 development environments:**
```
sg-uuc-myteam-eu-gb-dev01-cloud-zone1-netbox-token        ← OTC1
sg-uuc-myteam-eu-gb-dev02-cloud-zone1-netbox-token        ← OTC2
sg-uuc-myteam-eu-gb-dev01-cloud-zone1-undercloud-fast-ibm-paas-token      ← OTC1 (unique_per_cluster)
sg-uuc-myteam-eu-gb-dev02-cloud-zone1-undercloud-otc2-fast-ibm-paas-token ← OTC2 (unique_per_cluster)
```

> **Account boundary for prod-only secrets:**
> Secrets whose names contain `prod` (e.g. `service-functional-id-prod-cloud-apikey`, `service-now-prod-iam-token`) are automatically skipped on the dev account (`ACCOUNT_TYPE=dev`) and only provisioned on the prod account (`ACCOUNT_TYPE=prod`).

---

### Deployment Targets Configuration & Secret Provisioning

The `deployment_targets` section is **service-specific** and belongs in `<service_name>-onboarding.yaml`. It specifies all data centres, availability zones, and regions where the service is deployed.

Zone names, region names, and environment codes (`env_code`) are sourced from the [**IaaS Architecture Naming Conventions**](https://github.ibm.com/ibmcloud/iaas-architecture/blob/main/architecture/undercloud/naming_conventions.md) — the single source of truth.

**IMPORTANT:**
- Update the details you know and leave placeholder data where you don't have details yet.
- **DO NOT REMOVE** any sections from `deployment_targets`. Keep placeholder values if you don't have details yet.
- Removing entries from `deployment_targets` will result in validation errors.

#### Structure

Deployment targets are organized by pipeline type (CI/CD) and environment (integration, staging, production).

**Datacenter Types (CI only):**
- `vpc_ng`: VPC Next Generation datacenters (MANDATORY)
- `ngdc`: Next Generation Data Centers (OPTIONAL)

**Strict Validation Rules:**
- **CI**: ONLY `vpc_ng` (mandatory) and `ngdc` (optional) are allowed.
- **CD**: ONLY `integration`, `staging`, and `production` environments are allowed.
- **All CD environments must be present** — keep placeholders if you don't have values yet.
- **Placeholder Detection**: The validation script will warn (not error) for placeholder values like `zone1`, `myspecialzone`, etc.

#### CI Deployment Targets

CI targets define where continuous integration pipelines run.

**Properties:**
- `name`: Zone/region identifier
- `default_size`: Default deployment size (`small`, `medium`, `large`)

```yaml
deployment_targets:
  CI:
    vpc_ng:
      - name: env_code
        default_size: small
    ngdc:
      - name: env_code
        default_size: small
```

---

#### CD Deployment Targets & Secret Provisioning

CD targets control **per-environment secret expansion**. Region names, zone names, and `env_code` values must be sourced from the [IaaS Architecture Undercloud Naming Conventions doc](https://github.ibm.com/ibmcloud/iaas-architecture/blob/main/architecture/undercloud/naming_conventions.md).

**Account boundary:**
| Environment | Account | `ACCOUNT_TYPE` value |
|-------------|---------|----------------------|
| `integration` | Dev account | `dev` (default) |
| `staging` | Prod account | `prod` |
| `production` | Prod account | `prod` |

**Properties:**

| Property | Required | Values | Description |
|----------|----------|--------|-------------|
| `targets` | Yes | `all` or `[list]` | Regions to provision. Defaults to `all` if omitted. |
| `type` | Yes | `zonal` \| `regional` | `zonal` = one trigger per zone; `regional` = one trigger per region. |
| `default_size` | Yes | `small` \| `medium` \| `large` | Given size applied to all targets unless overridden. |
| `exclude` | No | `[list]` | Region names or zone Universal Names to skip. |
| `override_size` | No | `[list of {target, size}]` | Per-zone or per-region size overrides. |
| `trigger_strategy` | No | `per_vm` \| `per_tenant` \| `per_tenant_vm` | Controls how many inventory branches and triggers are created. Omit for default (1 per env). See [Trigger Strategy](#trigger-strategy). |
| `vm_names` | No | `[list of strings]` | Required when `trigger_strategy` is `per_vm` or `per_tenant_vm`. Unique VM names; each becomes an inventory branch suffix. |
| `tenant_names` | No | `[list of strings]` | Required when `trigger_strategy` is `per_tenant` or `per_tenant_vm`. Unique tenant names; each becomes an inventory branch suffix. |

**`exclude` rules:**
- Works in all three environments (integration, staging, production).
- For `type: zonal` — you can exclude a **region name** (skips all its zones) or a **zone Universal Name** (skips that zone only).
- For `type: regional` — only **region names** are valid in `exclude`. Using a zone Universal Name here has no effect (pipeline will warn).

**`override_size` rules:**
- For `type: zonal` — use the zone **Universal Name** as `target` (e.g. `us-south-dal10-int-a`).
- For `type: regional` — use the **region name** as `target` (e.g. `us-south-7x1`).

> **Zone, region & env_code reference:** For the full list of valid zone names, region names, and environment codes, refer to the
> [**IaaS Architecture Naming Conventions**](https://github.ibm.com/ibmcloud/iaas-architecture/blob/main/architecture/undercloud/naming_conventions.md)
> — the single source of truth.

---

#### Trigger Strategy

By default, a **single trigger per environment** is created — this is correct for the vast majority of services and requires no extra fields.

For services that upgrade VMs or deploy tenants independently across **separate CD runs**, set `trigger_strategy` to one of three values. The value determines which companion list fields become required:

| Case | `trigger_strategy` | Required list fields | Triggers created | Inventory branch pattern |
|---|---|---|---|---|
| 1 — Environment | *(omit — default)* | — | `M` | `{env}` |
| 2 — VM + Environment | `per_vm` | `vm_names` | `N × M` | `{vm}-{env}` |
| 3 — Tenant + Environment | `per_tenant` | `tenant_names` | `K × M` | `{tenant}-{env}` |
| 4 — Tenant + VM + Environment | `per_tenant_vm` | `tenant_names` + `vm_names` | `K × N × M` | `{tenant}-{vm}-{env}` |

Where `M` = number of environments, `N` = number of VMs, `K` = number of tenants.

**Rules:**
- `trigger_strategy` is **optional** — omit it entirely for Case 1 (default). Most services never need it.
- When set, the corresponding list field(s) become **required** — the validator will error if they are missing.
- Each name in `vm_names` / `tenant_names` must be **unique** within the list; duplicates will cause validation errors.
- Names become **inventory branch suffixes** directly — keep them short, lowercase, and hyphen-separated (e.g. `jh1`, `util1`, `tenant-a`).
- `trigger_strategy` can be set independently per environment block — e.g. `per_vm` on `staging` while `integration` and `production` remain single-trigger (default).

**Field definitions:**

```yaml
trigger_strategy:
  # Allowed values:
  # - per_vm
  # - per_tenant
  # - per_tenant_vm
  # Defaults to environment-level triggering when omitted.

vm_names:
  # Required for per_vm and per_tenant_vm.
  # Each name identifies a VM for trigger/inventory generation.

tenant_names:
  # Required for per_tenant and per_tenant_vm.
  # Each name identifies a tenant for trigger/inventory generation.
```

**Examples:**

```yaml
# Case 1 — default
# No trigger_strategy required.
# One trigger and inventory branch per environment.

# Case 2 — per VM
trigger_strategy: per_vm

vm_names:
  - vm1
  - vm2

# Case 3 — per tenant
trigger_strategy: per_tenant

tenant_names:
  - tenant1
  - tenant2

# Case 4 — per tenant + VM
trigger_strategy: per_tenant_vm

tenant_names:
  - tenant1
  - tenant2

vm_names:
  - vm1
  - vm2
```

This gives you the exact combinations needed without adding unnecessary configuration for the majority of services.

---

#### Deployment Types

| Type | Description | Secrets generated per secret-name |
|------|-------------|-----------------------------------|
| `zonal` | One secret per zone | 13 (integration), 13 (staging), 42 (production) |
| `regional` | One secret per region | 4 (integration), 4 (staging), 14 (production) |

---

#### Development Environments — OTC1 & OTC2

> ⚠️ **Temporary / opt-in only.** Development secrets are not provisioned by the automated pipeline under normal circumstances.

Zonal secrets declared in `commons.yaml` are also provisioned for the two OTC over-the-cloud development environments when `INCLUDE_DEVELOPMENT=true` is set on the pipeline:

| Environment | `environment_code` | Cluster(s) |
|-------------|-------------------|------------|
| **OTC1** | `eu-gb-dev01-cloud-zone1` | `undercloud` |
| **OTC2** | `eu-gb-dev02-cloud-zone1` | `undercloud-otc2` |

**Scope is intentionally narrow** — only `eu-gb` zones within `dev01` and `dev02` are included. All other development deployments (`dev03`, `dev06`, `dev07`, `dev08`) and the `us-south` entries within dev01/dev02 are excluded.

**No changes to your onboarding files are required.** The pipeline applies a default `targets: all, type: zonal` expansion for the development tier when no explicit `deployment_targets.CD.development` block is present.

**Generated secret labels follow the same naming convention:**

```
# unique_per_cluster: false (default)
sg-uuc-<team>-eu-gb-dev01-cloud-zone1-<secret_name>    ← OTC1
sg-uuc-<team>-eu-gb-dev02-cloud-zone1-<secret_name>    ← OTC2

# unique_per_cluster: true
sg-uuc-<team>-eu-gb-dev01-cloud-zone1-undercloud-<secret_name>       ← OTC1
sg-uuc-<team>-eu-gb-dev02-cloud-zone1-undercloud-otc2-<secret_name>  ← OTC2
```

**Pipeline flags:**

| Flag | Default | Effect |
|------|---------|--------|
| `INCLUDE_DEVELOPMENT` | `false` | Set to `true` to enable OTC1+OTC2 secret provisioning |
| `ENABLE_SECRETS_CREATION` | `false` | Set to `true` to enable integration env secret provisioning |

#### OTC1 Manual Test CD Deployment Trigger

A dedicated manual CD deployment trigger is available for **OTC1** to test application deployments without running through the full CI process.

**How it works:**
- Uses the `test-cd-deploy` branch from your application repository
- Directly runs the **pre-deploy**, **deploy**, and **post-deploy** checks
- Does **not** require a full CI run

**Prerequisites — inventory branch:**

Before starting the CD pipeline, create a branch in your inventory repository named with the OTC1 environment code:

```
eu-gb-dev01-cloud-zone1-undercloud
```

> **Note:** The inventory branch is required to initiate the CD pipeline. The inventory content itself is not used by this trigger — only the branch name matters.

**Steps to trigger a test CD deployment on OTC1:**

1. Ensure your application repository has a `test-cd-deploy` branch with the code to deploy.
2. Create the inventory branch `eu-gb-dev01-cloud-zone1-undercloud` in your inventory repository (if it doesn't exist).
3. Trigger the manual CD pipeline — it will pick up `test-cd-deploy` and run against OTC1.

---

#### Complete Example

```yaml
deployment_targets:
  CI:
    # env_code: sourced from https://github.ibm.com/ibmcloud/iaas-architecture/blob/main/architecture/undercloud/naming_conventions.md
    vpc_ng:
      - name: env_code
        default_size: small
    ngdc:
      - name: env_code
        default_size: small

  CD:
    # Source of truth for env_code, zone names, and region names:
    #   https://github.ibm.com/ibmcloud/iaas-architecture/blob/main/architecture/undercloud/naming_conventions.md
    # type:          zonal | regional
    # targets:       all | [list of zone or region names from naming conventions doc]
    # exclude:       [list of env_code values to exclude]
    # default_size:  Default deployment size — allowed values: small | medium | large
    # override_size: Per-target size override

    # DEV account (ACCOUNT_TYPE=dev)
    integration:
      targets: all
      type: zonal
      default_size: small
      override_size:
        - target: env_code
          size: large

    # PROD account (ACCOUNT_TYPE=prod)
    # Example with per-VM trigger strategy (Case 2):
    #   trigger_strategy: per_vm → creates 1 trigger per vm × env
    #   inventory branch pattern: {vm}-staging (e.g. jh1-staging, util1-staging)
    staging:
      targets: all
      type: regional
      default_size: medium
      override_size:
        - target: myspecialregion
          size: small
      # trigger_strategy: per_vm   # omit for default single-trigger behaviour
      # vm_names:
      #   - jh1
      #   - util1

    # PROD account (ACCOUNT_TYPE=prod)
    production:
      targets: all
      type: zonal
      exclude:
        - env_code
      default_size: small
      override_size:
        - target: env_code
          size: large
```

---

## Mandatory and Optional Files Configuration

The `mandatory_files` and `optional_files` sections are **service-specific** and belong in `<service_name>-onboarding.yaml`.

**IMPORTANT:** All mandatory files are **PLATFORM-MANAGED** and their file list plus `executable` settings cannot be modified. These files and their validation rules are enforced by the platform to ensure CI/CD pipeline functionality.

**Note:** Teams should only provide repository URL and branch information. Teams may set `can_be_empty: true` when needed, but the pipeline emits a warning when a platform default is changed from `false` to `true`.

### Optional Files Configuration

**IMPORTANT:** Remove the entire `optional_files` section if you don't need optional files. If you add any files here, ensure those files are present in the specified repository. Optional files are not applicable to `cd_only` or `minimal` profiles.

### Repository Properties

Each repository configuration supports the following properties:

| Property | Required | Default | Description |
|----------|----------|---------|-------------|
| `name` | Yes | - | Name identifier for the file group (e.g., CI, CD) |
| `repo` | Yes | - | Repository URL |
| `branch` | No | `default` | Branch name to validate files from |

**Example:**
```yaml
mandatory_files:
  - name: CI
    repo: https://github.ibm.com/myorg/myrepo
    branch: main
    files:
      # ... file definitions
```

### File Properties

Each file within a repository configuration supports the following properties:

| Property | Required | Default | Description |
|----------|----------|---------|-------------|
| `path` | Yes | - | File path relative to repository root |
| `can_be_empty` | No | `false` | Whether the file can be empty |
| `executable` | No | `false` | Whether the file must be executable |
| `applies_to` | No | all profiles | List of `cicd_profile` values for which this file is enforced. Allowed values: `minimal`, `ci_only`, `ci_cd`. If a service's `cicd_profile` is not in this list, the file check is skipped entirely. |

> **Note:** `applies_to` is **PLATFORM-MANAGED** — do not modify it. Teams may only remove profiles from the list when the file genuinely does not apply to their service type.

#### Understanding `can_be_empty`

- **`false` (default)**: File MUST exist AND must have content. This is the default behavior for mandatory files.
- **`true`**: File MUST exist but CAN be empty. Useful for placeholder files.

**Important Note:** All files under `mandatory_files` MUST exist. The `can_be_empty` flag only controls whether the file content can be empty or not. If you want a file to be truly optional (may or may not exist), use the `optional_files` section instead.

**Example:**
```yaml
files:
  # DO NOT MODIFY - PLATFORM MANAGED: Build script for CI pipeline
  - path: hack/ci/build.sh
    can_be_empty: false
    executable: true
    applies_to: [minimal, ci_only, ci_cd]

  # DO NOT MODIFY - PLATFORM MANAGED: Unit test execution script
  - path: hack/ci/run-unit-tests.sh
    can_be_empty: false
    executable: true
    applies_to: [ci_only, ci_cd]

  # DO NOT MODIFY - PLATFORM MANAGED: Build metadata (must contain either images or packages section)
  - path: hack/ci/build-meta.yaml
    can_be_empty: false
    executable: false
    applies_to: [ci_only, ci_cd]

  # DO NOT MODIFY - PLATFORM MANAGED: Pipeline configuration (mend_sast_info is mandatory)
  - path: hack/ci/pipeline.yaml
    can_be_empty: false
    executable: false
    applies_to: [ci_only, ci_cd]
```

---

## Additional Resources

For more information about the complete onboarding configuration, refer to the profile-specific reference templates in this directory. **Always copy templates from `main`** to ensure you have the latest platform-required fields:

```bash
git fetch origin main

# Team-level commons template (one per branch — contains all secrets)
git checkout origin/main -- commons.yaml

# Profile-specific service templates
git checkout origin/main -- onboarding-minimal.yaml   # documentation-only services
git checkout origin/main -- onboarding-ci_only.yaml   # internal artifacts, no CD
git checkout origin/main -- onboarding-ci_cd.yaml     # full production services
git checkout origin/main -- onboarding-cd_only.yaml   # external CI, CD pipeline only
```

| Template | Profile | When to use |
|----------|---------|-------------|
| `commons.yaml` | — | Shared team data and **all secrets** (one per branch) |
| `onboarding-minimal.yaml` | `minimal` | Documentation-only repositories |
| `onboarding-ci_only.yaml` | `ci_only` | Internal artifacts with no CD pipeline |
| `onboarding-ci_cd.yaml` | `ci_cd` | Production services with full CI + CD pipeline |
| `onboarding-cd_only.yaml` | `cd_only` | Production services using an external CI system |
