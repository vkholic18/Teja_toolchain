#!/usr/bin/env bash
# =============================================================================================
# IBM Confidential
# (C) Copyright IBM Corp. 2026
# The source code for this program is not published or otherwise divested of its trade secrets,
# irrespective of what has been deposited with the U.S. Copyright Office.
# ===========================

function fail() {
  echo "ERROR: $1"
  exit 1
}

function install_pkgs() {
  echo "Installing oc-mirror dependencies"
  if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get install -y \
      ca-certificates \
      curl \
      tar \
      gzip \
      zstd \
      file \
      jq \
      libgpgme11 \
      libassuan0 \
      libgpg-error0 \
      libseccomp2 \
      libselinux1

  elif command -v microdnf >/dev/null 2>&1; then
    microdnf install -y \
      ca-certificates \
      curl \
      tar \
      gzip \
      zstd \
      file \
      jq \
      gpgme \
      libassuan \
      libgpg-error \
      libseccomp \
      libselinux

  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y \
      ca-certificates \
      curl \
      tar \
      gzip \
      zstd \
      file \
      jq \
      gpgme \
      libassuan \
      libgpg-error \
      libseccomp \
      libselinux

  elif command -v yum >/dev/null 2>&1; then
    yum install -y \
      ca-certificates \
      curl \
      tar \
      gzip \
      zstd \
      file \
      jq \
      gpgme \
      libassuan \
      libgpg-error \
      libseccomp \
      libselinux

  else
    fail "No supported package manager found"
  fi
}

# function install_oc_cli() {
#   echo "Dependency installation completed"
#   echo ""

#   echo "Installed library check"
#   ldconfig -p | grep -E 'gpgme|assuan|gpg-error|seccomp|selinux|zstd' || true
#   echo ""

#   echo "Download oc-mirror binary"
#   echo "======================================"

#   curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/4.19.9/oc-mirror.tar.gz
#   tar -xzf oc-mirror.tar.gz
#   chmod +x oc-mirror

#   echo "Validate oc-mirror"
#   ldd ./oc-mirror | grep "not found" && fail "Missing shared libraries" || true
#   ./oc-mirror version
# }

function install_oc_cli() {
  set -euo pipefail

  OCP_VERSION="${OCP_VERSION:-4.20.0}"

  echo "Dependency installation completed"
  echo ""

  echo "Installed library check"
  ldconfig -p | grep -E 'gpgme|assuan|gpg-error|seccomp|selinux|zstd' || true
  echo ""

  echo "Download OpenShift client ${OCP_VERSION}"
  echo "======================================"

  curl -LO "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/openshift-client-linux.tar.gz"

  tar -xzf openshift-client-linux.tar.gz

  chmod +x oc kubectl

  mv oc /usr/local/bin/
  mv kubectl /usr/local/bin/

  echo ""
  echo "Install oc-mirror"
  echo "======================================"

  curl -LO "https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OCP_VERSION}/oc-mirror.tar.gz"

  tar -xzf oc-mirror.tar.gz

  chmod +x oc-mirror

  mv oc-mirror /usr/local/bin/

  echo ""
  echo "Validate binaries"
  echo "======================================"

  ldd /usr/local/bin/oc | grep "not found" && \
    fail "Missing shared libraries for oc" || true

  ldd /usr/local/bin/oc-mirror | grep "not found" && \
    fail "Missing shared libraries for oc-mirror" || true

  echo ""
  echo "oc version"
  oc version --client

  echo ""
  echo "oc-mirror version"
  oc-mirror version
}
