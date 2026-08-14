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

# How many separate runner instances to install , each is its own directory
# + its own systemd service, so this many jobs can run concurrently on this
# one VM. The work itself is lightweight (git/tofu/helm CLI calls; actual
# image builds happen in-cluster via cluster-ci's Kaniko Jobs), so several
# instances fit comfortably on one small VM , see proxmox-tofu's
# bastion_cpu_cores/bastion_memory, sized to match this default. Bump both
# together if you need more parallelism.
RUNNER_COUNT="${RUNNER_COUNT:-3}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Run as root (e.g. via sudo)." >&2
  exit 1
fi

echo "==> Installing git, curl, tar, unzip, python3, podman"
zypper --non-interactive refresh
zypper --non-interactive install --no-recommends \
  git curl ca-certificates tar unzip python3 python3-pip podman >/dev/null
# podman (not docker): daemonless, ships with openSUSE Leap , used by
# cluster-ci/scripts/rebuild-runner.sh to rebuild the ci-runner image
# directly on the bastion rather than via an in-cluster Kaniko Job.

echo "==> Installing actions-runner's shared-lib deps (best-effort , exact"
echo "    package names vary by openSUSE version, this is not fatal if it fails)"
# libicu's package name has already moved once between Leap versions
# (74_2 -> 77 on Leap 16) , try both rather than guess wrong and silently
# skip. Neither being available isn't fatal (see the fallback message),
# but confirmed needed on Leap 16 specifically (config.sh refuses to run
# without it: "Libicu's dependencies is missing for Dotnet Core 6.0").
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

echo "==> Installing ${RUNNER_COUNT} GitHub Actions runner instance(s) v${RUNNER_VERSION}"
# Each instance needs its own directory , the runner binary refuses to
# share one directory between two registrations. actions-runner-1,
# actions-runner-2, ... rather than a single actions-runner, so
# RUNNER_COUNT can be bumped later just by re-running this script (already
#-installed instances are skipped via the run.sh check, same as before).
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

echo "==> Installing sync-repos timer (keeps ~/project current with GitHub"
echo "    even between pipeline runs , see scripts/sync-repos.sh)"
cat > /etc/systemd/system/sync-repos.service <<SERVICEEOF
[Unit]
Description=Sync ~/project repos with GitHub

[Service]
Type=oneshot
User=${RUNNER_USER}
ExecStart=${RUNNER_HOME}/project/proxmox-tofu/scripts/sync-repos.sh
SERVICEEOF
cat > /etc/systemd/system/sync-repos.timer <<TIMEREOF
[Unit]
Description=Run sync-repos.service every 5 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
TIMEREOF
systemctl daemon-reload
# Not started here , sync-repos.sh needs cluster-cli actually cloned first
# (step 4 below), which hasn't happened yet on a fresh bastion. Enable it
# once that's done: `sudo systemctl enable --now sync-repos.timer`.
systemctl enable sync-repos.timer

cat <<EOF

==> Done. Still needed (see proxmox-tofu/README.md's "CI bastion" section):
  1. Copy the non-git files this bastion needs, from your workstation:
       scp ../proxmox-tofu/_out/kubeconfig            ${RUNNER_USER}@<bastion-ip>:${RUNNER_HOME}/project/proxmox-tofu/_out/kubeconfig
       scp ~/.config/cluster-cli/config.toml           ${RUNNER_USER}@<bastion-ip>:${RUNNER_HOME}/.config/cluster-cli/config.toml
       scp <repo>/tofu/terraform.tfvars                ${RUNNER_USER}@<bastion-ip>:${RUNNER_HOME}/project/<repo>/tofu/terraform.tfvars
     (repeat the tfvars line for every repo under ~/project with one, e.g. cluster-config, clusterkeep-ui)
  2. Clone every ~/project repo the bastion needs (cluster-cli, cluster-ci,
     clusterkeep-ui, cluster-config, proxmox-tofu, cluster-auth, cluster-rbac
     at minimum) into ${RUNNER_HOME}/project/, then
     \`uv tool install --editable cluster-cli\`.
  3. Register each of the ${RUNNER_COUNT} runner instances (actions-runner-1
     .. actions-runner-${RUNNER_COUNT}) against the GitHub **org**, not any
     one repo , org Settings -> Actions -> Runners -> New runner gives a
     token good for all of them (reuse the same token across instances,
     it's not single-use). Give each instance a distinct --name so they
     don't collide in the org's runner list:
       for i in \$(seq 1 ${RUNNER_COUNT}); do
         cd ${RUNNER_HOME}/actions-runner-\$i
         sudo -u ${RUNNER_USER} ./config.sh --url https://github.com/<org> --token <token> --name ci-bastion-\$i --unattended
         sudo chcon -t bin_t runsvc.sh   # see note below , needed before svc.sh install on SELinux-enforcing systems (Leap 16 default)
         sudo ./svc.sh install ${RUNNER_USER}
         sudo ./svc.sh start
         cd -
       done
     If \`systemctl status\` on the resulting service shows a 203/EXEC
     failure ("Permission denied" spawning runsvc.sh) even with the chcon
     above, SELinux is enforcing and blocking init from executing a
     user_home_t-labeled file (Leap 16 ships SELinux enforcing by default ,
     check with \`getenforce\`/\`cat /sys/fs/selinux/enforce\`); the chcon
     line re-labels runsvc.sh to bin_t, which init_t is allowed to exec ,
     confirmed via \`sudo journalctl\` showing an AVC \`denied { execute }\`
     otherwise. This isn't persisted through \`semanage fcontext\` (this
     image doesn't ship a working \`semanage\` binary, only its Python
     module) , it survives normal operation fine, but a full \`restorecon -R /\`
     or SELinux autorelabel would need it re-run.
     Every repo's \`runs-on: [self-hosted]\` workflow picks up whichever
     instance is free , no per-repo registration needed any more.
  4. Start the sync-repos timer now that the repos above are cloned:
       sudo chcon -t bin_t ~/project/proxmox-tofu/scripts/sync-repos.sh   # same SELinux fix as runsvc.sh above , the file doesn't exist until step 2's clone, so it can't be done earlier
       sudo systemctl start sync-repos.timer
     (it's already enabled to start on boot; this just kicks off the first
     run instead of waiting up to a minute for OnBootSec). Check it worked:
       sudo systemctl status sync-repos.timer
       sudo journalctl -u sync-repos.service -n 20
EOF
