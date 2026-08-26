# VPC CI – Frequently Asked Questions (FAQ)

This document provides quick references and step-by-step guidance for common CI/CD pipeline configurations and troubleshooting within the **VPC CI** ecosystem.

---

## 📚 Table of Contents

- [VPC CI – Frequently Asked Questions (FAQ)](#vpc-ci--frequently-asked-questions-faq)
  - [📚 Table of Contents](#-table-of-contents)
  - [1. How to enable Mend SAST scans in PR pipeline](#1-how-to-enable-mend-sast-scans-in-pr-pipeline)
  - [2. How to get access to ICR images (Step-by-Step Guide)](#2-how-to-get-access-to-icr-images-step-by-step-guide)
  - [3. Process to unlock BRT environments](#3-process-to-unlock-brt-environments)
  - [4. How to enable Mend SAST in VPC CI workspaces](#4-how-to-enable-mend-sast-in-vpc-ci-workspaces)
  - [5. How to audit issues detected by the Detect Secrets tool](#5-how-to-audit-issues-detected-by-the-detect-secrets-tool)
  - [6. How to get access to the OnePipelineCloud account](#6-how-to-get-access-to-the-onepipelinecloud-account)
  - [7. How to omit vulnerabilities detected by CRA (Code Risk Analyzer)](#7-how-to-omit-vulnerabilities-detected-by-cra-code-risk-analyzer)
  - [8. Migration process from Travis CI to OnePipeline](#8-migration-process-from-travis-ci-to-onepipeline)
  - [9. How to resolve “Check Vetted Files Failure” in PR to master pipeline](#9-how-to-resolve-check-vetted-files-failure-in-pr-to-master-pipeline)
    - [🧩 Additional Information](#-additional-information)

---

## 1. How to enable Mend SAST scans in PR pipeline

<details open>
<summary>Show answer</summary>

You can refer to the following Slack discussions for setup details:

- **Setup Guidance:** https://ibm-cloudplatform.slack.com/archives/C03981DA3HR/p1747633597583649  

</details>

---

## 2. How to get access to ICR images (Step-by-Step Guide)

<details open>
<summary>Show answer</summary>

Follow the guide shared in this Slack message:  
https://ibm-cloudplatform.slack.com/archives/C03981DA3HR/p1742918554512279

It includes authentication setup, IAM access configuration, and image pull permissions for IBM Cloud Container Registry (ICR).

</details>

---

## 3. Process to unlock BRT environments

<details open>
<summary>Show answer</summary>

Detailed steps are documented in this Slack post:  
https://ibm-cloudplatform.slack.com/archives/C03981DA3HR/p1742822329456729

Includes validation checks, required approvals, and automation triggers for unlocking environments.

</details>

---

## 4. How to enable Mend SAST in VPC CI workspaces

<details open>
<summary>Show answer</summary>

Configuration guidance is available here:  
https://ibm-cloudplatform.slack.com/archives/C03981DA3HR/p1741620290838559

Covers configuration changes, YAML updates, and environment setup steps.

</details>

---

## 5. How to audit issues detected by the Detect Secrets tool

<details open>
<summary>Show answer</summary>

Refer to this Slack thread for the audit process:  
https://ibm-cloudplatform.slack.com/archives/C03981DA3HR/p1685458863511249

Learn how to audit, mark, and track secrets, handle false positives, and maintain repository compliance.

</details>

---

## 6. How to get access to the OnePipelineCloud account

<details open>
<summary>Show answer</summary>

Access steps are detailed in the migration guide:  
https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/onepipeline/Documentation/OnePLMigrationGuide.md#getting-access-to-the-toolchains

Includes IAM role requests, entitlement steps, and validation instructions.

</details>

---

## 7. How to omit vulnerabilities detected by CRA (Code Risk Analyzer)

<details open>
<summary>Show answer</summary>

Check this documentation section for omitting vulnerabilities:  
https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/onepipeline/Documentation/OnePLMigrationGuide.md#dealing-with-security-vulnerabilities

Explains how to add CRA ignore files, justify known issues, and ensure compliance.

</details>

---

## 8. Migration process from Travis CI to OnePipeline

<details open>
<summary>Show answer</summary>

Migration guide:  
https://github.ibm.com/genctl-cicd/genctl-ci/blob/master/onepipeline/Documentation/Travis_CI_to_OnePipeline_Migration.md

Covers:
- Environment and variable mapping  
- YAML conversion steps  
- Common migration issues and solutions

</details>

---

## 9. How to resolve “Check Vetted Files Failure” in PR to master pipeline

<details open>
<summary>Show answer</summary>

This failure usually occurs in the `CHECK_INVENTORY_VETTED_FILES` step due to one of the following:

**Possible Reasons:**
- The **merge to `dev-integration` pipeline** hasn’t finished yet → vetted files aren’t available.  
- The **merge to `dev-integration` pipeline** completed but some stages failed → vetted files weren’t generated.

**Resolution Steps:**
1. Check your most recent **merge to dev-integration** pipeline.  
2. Ensure that it **completed successfully**.  
3. Once complete, **retrigger your PR to master/main** pipeline.

✅ After successful completion, the vetted files will be available for use.

</details>

---

### 🧩 Additional Information
- **Maintained by:** VPC CI Team  
- **Slack Channel:** https://ibm-cloudplatform.slack.com/archives/C03981DA3HR  
- **Last Updated:** October 2025

---
