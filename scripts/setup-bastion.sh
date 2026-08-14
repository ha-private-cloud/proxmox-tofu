#!/usr/bin/env bash
# One-time bootstrap for the CI bastion VM (openSUSE Leap): installs the
# tooling `cluster-cli`/`tofu`/`helm` need (git, python3/uv, OpenTofu, Helm,
# kubectl), plus the GitHub Actions self-hosted runner binary. Does NOT
# register the runner against any repo , that needs a short-lived token
# from GitHub's own UI/API (Settings -> Actions -> Runners -> New
# self-hosted runner), which only you can generate; see proxmox-tofu's
# README for that step and everything else this script doesn't cover
# (copying the kubeconfig/tfvars over, cloning the app repos).
#
# GitHub's actions-runner isn't officially tested against openSUSE (its own
# installdependencies.sh only covers Ubuntu/Fedora/CentOS-family) , the
# icu/openssl packages below cover its known shared-library needs, but if
# `run.sh` fails to start, missing dependencies are the first thing to
# check (`ldd bin/Runner.Listener` for anything "not found").
#
# Run this on the bastion VM itself, e.g.:
#   ssh admin@<bastion-ip> 'sudo bash -s' < scripts/setup-bastion.sh
#
# Safe to re-run: every step below is idempotent.

set -euo pipefail

# openSUSE's default `sudo` secure_path excludes /usr/local/bin (unlike
# Debian's), which is exactly where the helm/kubectl installers below put
# their binaries , without this, root's own PATH can't see what it just
# installed and each installer's self-check fails right after succeeding.
export PATH="/usr/local/bin:${PATH}"

RUNNER_VERSION="2.321.0"
RUNNER_USER="${SUDO_USER:-admin}"
RUNNER_HOME="/home/${RUNNER_USER}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (e.g. via sudo)." >&2
  exit 1
fi

echo "==> Installing git, curl, tar, unzip, python3"
zypper --non-interactive refresh
zypper --non-interactive install --no-recommends \
  git curl ca-certificates tar unzip python3 python3-pip >/dev/null

echo "==> Installing actions-runner's shared-lib deps (best-effort , exact"
echo "    package names vary by openSUSE version, this is not fatal if it fails)"
zypper --non-interactive install --no-recommends libicu74_2 libopenssl3 krb5 2>&1 \
  || echo "    skipped/failed , if run.sh later fails with a missing .so, 'ldd bin/Runner.Listener' will show what's actually needed"

echo "==> Installing uv (for cluster-cli/clusterkeep-ui's uv-managed venvs)"
if ! command -v uv >/dev/null 2>&1; then
  sudo -u "$RUNNER_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
fi

echo "==> Installing OpenTofu"
if ! command -v tofu >/dev/null 2>&1; then
  curl -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-opentofu.sh
  chmod +x /tmp/install-opentofu.sh
  # standalone, not --install-method rpm/deb , works the same regardless of
  # the guest OS's packaging, no need to special-case zypper here.
  /tmp/install-opentofu.sh --install-method standalone
  rm -f /tmp/install-opentofu.sh
fi

echo "==> Installing Helm"
if ! command -v helm >/dev/null 2>&1; then
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

echo "==> Installing kubectl"
if ! command -v kubectl >/dev/null 2>&1; then
  curl -fsSL -o /usr/local/bin/kubectl "https://dl.k8s.io/release/$(curl -fsSL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x /usr/local/bin/kubectl
fi

echo "==> Installing GitHub Actions runner v${RUNNER_VERSION}"
RUNNER_DIR="${RUNNER_HOME}/actions-runner"
if [ ! -x "${RUNNER_DIR}/run.sh" ]; then
  sudo -u "$RUNNER_USER" mkdir -p "$RUNNER_DIR"
  sudo -u "$RUNNER_USER" bash -c "
    curl -fsSL -o /tmp/actions-runner.tar.gz \
      https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
    tar xzf /tmp/actions-runner.tar.gz -C '${RUNNER_DIR}'
    rm -f /tmp/actions-runner.tar.gz
  "
fi

echo "==> Creating ~/project (sibling repo layout cluster-cli expects)"
sudo -u "$RUNNER_USER" mkdir -p "${RUNNER_HOME}/project"

cat <<EOF

==> Done. Still needed (see proxmox-tofu/README.md's "CI bastion" section):
  1. Copy the non-git files this bastion needs, from your workstation:
       scp ../proxmox-tofu/_out/kubeconfig            ${RUNNER_USER}@<bastion-ip>:${RUNNER_HOME}/project/proxmox-tofu/_out/kubeconfig
       scp ~/.config/cluster-cli/config.toml           ${RUNNER_USER}@<bastion-ip>:${RUNNER_HOME}/.config/cluster-cli/config.toml
       scp <repo>/tofu/terraform.tfvars                ${RUNNER_USER}@<bastion-ip>:${RUNNER_HOME}/project/<repo>/tofu/terraform.tfvars
     (repeat the tfvars line for every repo under ~/project with one, e.g. cluster-config, clusterkeep-ui)
  2. Clone every ~/project repo the bastion needs (cluster-cli, cluster-ci,
     clusterkeep-ui, cluster-config, proxmox-tofu at minimum) into
     ${RUNNER_HOME}/project/, then \`uv tool install --editable cluster-cli\`.
  3. Register the runner against each repo needing it (Settings -> Actions
     -> Runners -> New self-hosted runner gives you the exact token/command):
       cd ${RUNNER_DIR} && sudo -u ${RUNNER_USER} ./config.sh --url <repo-url> --token <token>
       sudo ./svc.sh install && sudo ./svc.sh start
EOF
