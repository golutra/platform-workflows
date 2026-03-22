#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/github/sync-central-compliance-workflows.sh <source-repo-path>

Description:
  Sync reusable compliance workflows from a source repository into this central
  workflow repository for organization-wide sharing.

Example:
  scripts/github/sync-central-compliance-workflows.sh ~/work/golutra
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
source_repo_path="$(cd "$1" && pwd)"

if [[ ! -d "${repo_root}/.git" ]]; then
  echo "Current directory is not a git repository: ${repo_root}" >&2
  exit 1
fi

if [[ ! -d "${source_repo_path}/.git" ]]; then
  echo "Source path is not a git repository: ${source_repo_path}" >&2
  exit 1
fi

mkdir -p "${repo_root}/.github/workflows"

cp "${source_repo_path}/.github/workflows/cla-reusable.yml" \
  "${repo_root}/.github/workflows/cla-reusable.yml"
cp "${source_repo_path}/.github/workflows/pr-compliance-reusable.yml" \
  "${repo_root}/.github/workflows/pr-compliance-reusable.yml"

echo "Synchronized reusable workflows into ${repo_root}"
echo "Next steps:"
echo "  1. Review changes in the central workflow repository."
echo "  2. Commit and push them."
echo "  3. In the central repository, enable Actions sharing for repositories in the organization."
