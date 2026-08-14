#!/usr/bin/env bash
# Keeps every repo under ~/project in sync with GitHub's main branch , hard
# reset, not just fetch+merge, so tracked files always exactly match GitHub
# and can never accumulate local drift (a hand-edit applied directly on the
# bastion once left cluster-ci's checkout dirty enough to block a
# `cluster-cli tofu --tag` checkout with "uncommitted changes" , this makes
# that structurally impossible going forward). Gitignored files (tfstate,
# tfvars, kubeconfig, .terraform/) are untouched, since git ignores them.
#
# Run as the first step of every pipeline workflow (so cluster-config/
# cluster-auth/etc always run against current code, and cluster-cli , which
# has no workflow of its own , doesn't have to free-ride on some other
# repo's pull step), and on a systemd timer (sync-repos.timer) so it's also
# current between runs, e.g. for a human SSHed in running cluster-cli by
# hand. Each workflow's own precise checkout (exact commit SHA or tag) for
# the repo it's actually acting on still happens after this , this script
# only establishes a clean, current baseline.
#
# Safe to re-run.

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
