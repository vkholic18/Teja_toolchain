#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade  s,
# irrespective of what has been deposited with the U.S. Copyright Office.
# =============================================================================================
#
# bob_setup.sh - Shared helper that configures the Bob AI shell for use in CI/CD pipelines.
#
# Expected env vars (sourced from  s.sh before this file):
#   BOB_API_KEY   - API key for Bob authentication
#   GITHUB_TOKEN  - Personal access token for the GitHub MCP server
#
# After sourcing this file BOBSHELL_API_KEY, BOBSHELL_BASE_URL and the bob
# command will be available to the calling script.

echo "=========================================="
echo "Bob Setup"
echo "=========================================="

# ---------------------------------------------------------------------------
# 1. Export Bob authentication variables
# ---------------------------------------------------------------------------
export BOBSHELL_API_KEY="${BOB_API_KEY}"
export BOBSHELL_BASE_URL="https://prod.ibm-bob-staging.cloud.ibm.com"

echo "BOBSHELL_BASE_URL: ${BOBSHELL_BASE_URL}"
if [ -z "${BOBSHELL_API_KEY}" ]; then
    echo "WARNING: BOBSHELL_API_KEY is not set"
else
    echo "BOBSHELL_API_KEY: [SET - ${#BOBSHELL_API_KEY} chars]"
fi

# ---------------------------------------------------------------------------
# 2. Ensure Node / pnpm are on PATH
# ---------------------------------------------------------------------------
export NVM_DIR="/root/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

NODE_DIR="$(cat /node_version.txt 2>/dev/null || echo 'v22.15.1')"
export PATH="/root/.nvm/versions/node/${NODE_DIR}/bin:${PATH}"

export PNPM_HOME="/root/.local/share/pnpm"
export PATH="${PNPM_HOME}/bin:${PATH}"

# Bob is pre-installed in the CI image — no upgrade step needed.
# @ibm/bob-shell is an internal package not available on the public npm registry.
if ! command -v bob &> /dev/null; then
    echo "ERROR: bob command not found in PATH. Ensure the CI image includes @ibm/bob-shell."
    exit 1
fi

echo "Bob version: $(bob --version 2>/dev/null || echo 'unknown')"

# ---------------------------------------------------------------------------
# 3. Write Bob configuration files
# ---------------------------------------------------------------------------
mkdir -p /root/.bob/settings

cat > /root/.bob/settings.json <<EOF
{
  "ibm": {
    "isNotFirstTime": true,
    "licenseConsent": true,
    "instanceId": "ci-pipeline-instance",
    "teamId": "00000000-0000-0000-0000-000000000001",
    "baseUrl": "${BOBSHELL_BASE_URL}"
  },
  "security": {
    "auth": {
      "selectedType": "api-key",
      "baseUrl": "${BOBSHELL_BASE_URL}"
    }
  },
  "general": {
    "disableAutoUpdate": true
  },
  "tools": {
    "allowed": ["*"]
  }
}
EOF

cat > /root/.bob/settings/mcp_settings.json <<EOF
{
  "mcpServers": {
    "github": {
      "command": "docker",
      "args": [
        "run", "-i", "--rm",
        "-e", "GITHUB_PERSONAL_ACCESS_TOKEN=${GITHUB_TOKEN}",
        "-e", "GITHUB_TOOLSETS=",
        "-e", "GITHUB_READ_ONLY=",
        "-e", "GITHUB_HOST=https://github.ibm.com",
        "ghcr.io/github/github-mcp-server"
      ],
      "disabled": false,
      "alwaysAllow": []
    }
  }
}
EOF

echo "✅ Bob setup complete"