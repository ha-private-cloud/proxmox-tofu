#!/usr/bin/env bash
# Hard-resets every repo under ~/project to origin/main, then installs
# every scripts/*.sh into /usr/local/bin (git resets strip execute bit +
# SELinux label each time; /usr/local/bin isn't git-managed and defaults to
# an executable label, so run the installed copy, not the ~/project one).
# Run at the start of every pipeline and via sync-repos.timer. Safe to re-run.

set -euo pipefail

REPOS=(cluster-cli cluster-ci clusterkeep-ui cluster-config proxmox-tofu cluster-auth cluster-rbac)
PROJECT_DIR="${HOME}/project"

for repo in "${REPOS[@]}"; do
  dir="${PROJECT_DIR}/${repo}"
  if [ ! -d "${dir}/.git" ]; then
    echo "==> ${repo}: not cloned yet, skipping"
    continue
  fi
  echo "==> ${repo}: syncing to origin/main"
  git -C "$dir" fetch origin --tags
  git -C "$dir" reset --hard origin/main
done

echo "==> Reinstalling cluster-cli"
export PATH="/usr/local/bin:${HOME}/.local/bin:${PATH}"
uv tool install --editable "${PROJECT_DIR}/cluster-cli" --reinstall --quiet

echo "==> Installing scripts/*.sh from every repo into /usr/local/bin"
for repo in "${REPOS[@]}"; do
  scripts_dir="${PROJECT_DIR}/${repo}/scripts"
  [ -d "$scripts_dir" ] || continue
  for script in "$scripts_dir"/*.sh; do
    [ -f "$script" ] || continue
    sudo install -m 755 "$script" "/usr/local/bin/$(basename "$script")"
  done
done
