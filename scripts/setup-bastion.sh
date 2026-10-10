#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/bin:${PATH}"

RUNNER_VERSION="2.321.0"
RUNNER_USER="${SUDO_USER:-admin}"
RUNNER_HOME="/home/${RUNNER_USER}"

RUNNER_COUNT="${RUNNER_COUNT:-3}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (e.g. via sudo)." >&2
  exit 1
fi

echo "==> Installing git, curl, tar, unzip, python3, podman"
zypper --non-interactive refresh
zypper --non-interactive install --no-recommends \
  git curl ca-certificates tar unzip python3 python3-pip podman >/dev/null

echo "==> Installing actions-runner's shared-lib deps (best-effort , exact"
echo "    package names vary by openSUSE version, this is not fatal if it fails)"
zypper --non-interactive install --no-recommends libicu77 libopenssl3 krb5 2>&1 \
  || zypper --non-interactive install --no-recommends libicu74_2 libopenssl3 krb5 2>&1 \
  || echo "    skipped/failed , if config.sh later refuses to run citing Dotnet Core/libicu, or run.sh fails with a missing .so, 'ldd bin/Runner.Listener' will show what's actually needed"

echo "==> Installing uv (for cluster-cli/clusterkeep-ui's uv-managed venvs)"
if ! command -v uv >/dev/null 2>&1; then
  sudo -u "$RUNNER_USER" bash -c 'curl -LsSf https://astral.sh/uv/install.sh | sh'
fi

echo "==> Installing OpenTofu"
if ! command -v tofu >/dev/null 2>&1; then
  curl -fsSL https://get.opentofu.org/install-opentofu.sh -o /tmp/install-opentofu.sh
  chmod +x /tmp/install-opentofu.sh
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

echo "==> Installing ${RUNNER_COUNT} GitHub Actions runner instance(s) v${RUNNER_VERSION}"
curl -fsSL -o /tmp/actions-runner.tar.gz \
  https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz
for i in $(seq 1 "$RUNNER_COUNT"); do
  RUNNER_DIR="${RUNNER_HOME}/actions-runner-${i}"
  if [ ! -x "${RUNNER_DIR}/run.sh" ]; then
    sudo -u "$RUNNER_USER" mkdir -p "$RUNNER_DIR"
    sudo -u "$RUNNER_USER" tar xzf /tmp/actions-runner.tar.gz -C "$RUNNER_DIR"
  fi
done
rm -f /tmp/actions-runner.tar.gz

echo "==> Creating ~/project (sibling repo layout cluster-cli expects)"
sudo -u "$RUNNER_USER" mkdir -p "${RUNNER_HOME}/project"

echo "==> Removing the sync-repos timer if present"
systemctl disable --now sync-repos.timer >/dev/null 2>&1 || true
rm -f /etc/systemd/system/sync-repos.timer /etc/systemd/system/sync-repos.service
systemctl daemon-reload

cat <<EOF

==> Done. Still needed:
  1. Copy the non-git files this bastion needs, from your workstation:
       scp ../proxmox-tofu/_out/kubeconfig            ${RUNNER_USER}@<bastion-ip>:${RUNNER_HOME}/project/proxmox-tofu/_out/kubeconfig
       scp ~/.config/cluster-cli/config.toml           ${RUNNER_USER}@<bastion-ip>:${RUNNER_HOME}/.config/cluster-cli/config.toml
       scp <repo>/tofu/terraform.tfvars                ${RUNNER_USER}@<bastion-ip>:${RUNNER_HOME}/project/<repo>/tofu/terraform.tfvars
     (repeat the tfvars line for every repo under ~/project with one)
  2. Clone every ~/project repo the bastion needs (cluster-cli, cluster-ci,
     clusterkeep-ui, cluster-config, proxmox-tofu, cluster-auth
     at minimum) into ${RUNNER_HOME}/project/, then
     \`uv tool install --editable cluster-cli\`.
  3. Register each of the ${RUNNER_COUNT} runner instances against the
     GitHub org (Settings -> Actions -> Runners -> New runner), reusing
     one token and giving each a distinct --name:
       for i in \$(seq 1 ${RUNNER_COUNT}); do
         cd ${RUNNER_HOME}/actions-runner-\$i
         sudo -u ${RUNNER_USER} ./config.sh --url https://github.com/<org> --token <token> --name ci-bastion-\$i --unattended
         sudo chcon -t bin_t runsvc.sh
         sudo ./svc.sh install ${RUNNER_USER}
         sudo ./svc.sh start
         cd -
       done
  4. Seed the initial /usr/local/bin copy of sync-repos.sh:
       sudo install -m 755 ~/project/proxmox-tofu/scripts/sync-repos.sh /usr/local/bin/sync-repos.sh
     Check it worked:
       sync-repos.sh cluster-cli
EOF
