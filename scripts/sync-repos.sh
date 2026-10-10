#!/usr/bin/env bash
set -euo pipefail

exec 200>/tmp/sync-repos.lock
if ! flock -w 900 200; then
  echo "==> lock held (tofu run or another sync in progress), skipping this sync" >&2
  exit 0
fi

ALL_REPOS=(cluster-cli cluster-ci clusterkeep-ui cluster-config proxmox-tofu cluster-auth charts storage-ui auth-api)
PROJECT_DIR="${HOME}/project"

if [ "$#" -gt 0 ]; then
  REPOS=("$@")
  for repo in "${REPOS[@]}"; do
    found=0
    for known in "${ALL_REPOS[@]}"; do
      [ "$repo" = "$known" ] && found=1 && break
    done
    if [ "$found" -eq 0 ]; then
      echo "unknown repo: ${repo} (known: ${ALL_REPOS[*]})" >&2
      exit 1
    fi
  done
else
  REPOS=("${ALL_REPOS[@]}")
fi

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
for repo in "${ALL_REPOS[@]}"; do
  scripts_dir="${PROJECT_DIR}/${repo}/scripts"
  [ -d "$scripts_dir" ] || continue
  for script in "$scripts_dir"/*.sh; do
    [ -f "$script" ] || continue
    sudo install -m 755 "$script" "/usr/local/bin/$(basename "$script")"
  done
done
