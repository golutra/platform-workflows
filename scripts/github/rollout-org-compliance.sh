#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  scripts/github/rollout-org-compliance.sh \
    --org <github-org> \
    --central-workflow-repo <owner/repo> \
    --template-source <template-repo-path> \
    [--workflow-ref <git-ref>] \
    [--repo <repo-name-or-owner/repo>]... \
    [--exclude <repo-name-or-owner/repo>]... \
    [--limit <count>] \
    [--signatures-branch <branch>] \
    [--execute] \
    [--force]

Description:
  Create pull requests that install the golutra CLA / PR compliance caller workflows,
  legal documents, and PR template into repositories across a GitHub organization.

Options:
  --org                      GitHub organization name.
  --central-workflow-repo    Repository that hosts reusable workflows, such as
                             golutra/platform-workflows.
  --template-source          Local repository path that contains CLA.md, docs/legal/*
                             and the PR template used as rollout source.
  --workflow-ref             Git ref for the reusable workflow repository. Default: v1.0.0.
  --repo                     Target repository. Can be repeated. If omitted, all repos
                             in the organization are selected.
  --exclude                  Repository to skip. Can be repeated.
  --limit                    Max repos fetched from GitHub when --repo is omitted.
                             Default: 200.
  --signatures-branch        Branch that stores CLA signatures. Default: cla-signatures.
  --execute                  Push branches and open PRs. Default is dry-run.
  --force                    Overwrite managed files even if they already exist.

Examples:
  scripts/github/rollout-org-compliance.sh \
    --org golutra \
    --central-workflow-repo golutra/platform-workflows \
    --template-source ~/work/golutra \
    --repo golutra/app \
    --repo golutra/cli

  scripts/github/rollout-org-compliance.sh \
    --org golutra \
    --central-workflow-repo golutra/platform-workflows \
    --template-source ~/work/golutra \
    --limit 50 \
    --execute
EOF
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

matches_any() {
  local repo_name="$1"
  local repo_full_name="$2"
  shift 2
  local candidate

  if [[ $# -eq 0 ]]; then
    return 1
  fi

  for candidate in "$@"; do
    if [[ "${candidate}" == "${repo_name}" || "${candidate}" == "${repo_full_name}" ]]; then
      return 0
    fi
  done

  return 1
}

write_cla_caller() {
  local file_path="$1"
  local workflow_repo="$2"
  local workflow_ref="$3"

  cat >"${file_path}" <<EOF
name: CLA

on:
  issue_comment:
    types:
      - created
  pull_request_target:
    types:
      - opened
      - synchronize
      - reopened
      - ready_for_review
      - closed

permissions:
  actions: write
  contents: write
  pull-requests: write
  statuses: write

jobs:
  cla:
    uses: ${workflow_repo}/.github/workflows/cla-reusable.yml@${workflow_ref}
    secrets: inherit
    with:
      event-name: \${{ github.event_name }}
      issue-is-pr: \${{ github.event_name == 'issue_comment' && github.event.issue.pull_request != null }}
      comment-body: \${{ github.event.comment.body || '' }}
      default-branch: \${{ github.event.repository.default_branch }}
EOF
}

write_pr_compliance_caller() {
  local file_path="$1"
  local workflow_repo="$2"
  local workflow_ref="$3"

  cat >"${file_path}" <<EOF
name: PR Compliance

on:
  pull_request_target:
    types:
      - opened
      - edited
      - synchronize
      - reopened
      - ready_for_review

permissions:
  contents: read
  pull-requests: write

jobs:
  validate-pr-metadata:
    uses: ${workflow_repo}/.github/workflows/pr-compliance-reusable.yml@${workflow_ref}
    secrets: inherit
    with:
      pr-number: \${{ github.event.pull_request.number }}
      pr-body: \${{ github.event.pull_request.body }}
      pr-author-login: \${{ github.event.pull_request.user.login }}
      default-branch: \${{ github.event.repository.default_branch }}
EOF
}

sync_repository_files() {
  local source_root="$1"
  local target_root="$2"
  local workflow_repo="$3"
  local workflow_ref="$4"

  mkdir -p "${target_root}/.github/workflows" "${target_root}/docs/legal"

  cp "${source_root}/CLA.md" "${target_root}/CLA.md"
  cp "${source_root}/.github/pull_request_template.md" \
    "${target_root}/.github/pull_request_template.md"
  cp "${source_root}/docs/legal/ICLA.md" "${target_root}/docs/legal/ICLA.md"
  cp "${source_root}/docs/legal/CCLA.md" "${target_root}/docs/legal/CCLA.md"
  cp "${source_root}/docs/legal/corporate-authorizations.json" \
    "${target_root}/docs/legal/corporate-authorizations.json"
  cp "${source_root}/docs/legal/corporate-authorizations.md" \
    "${target_root}/docs/legal/corporate-authorizations.md"
  cp "${source_root}/docs/legal/BSD-3-Clause.txt" \
    "${target_root}/docs/legal/BSD-3-Clause.txt"

  write_cla_caller "${target_root}/.github/workflows/cla.yml" "${workflow_repo}" "${workflow_ref}"
  write_pr_compliance_caller \
    "${target_root}/.github/workflows/pr-compliance.yml" \
    "${workflow_repo}" \
    "${workflow_ref}"
}

create_signatures_branch_if_missing() {
  local repo_dir="$1"
  local default_branch="$2"
  local signatures_branch="$3"

  if git -C "${repo_dir}" ls-remote --exit-code --heads origin "${signatures_branch}" >/dev/null 2>&1; then
    return 0
  fi

  git -C "${repo_dir}" push origin "${default_branch}:refs/heads/${signatures_branch}"
}

org=""
central_workflow_repo=""
template_source=""
workflow_ref="v1.0.0"
limit="200"
signatures_branch="cla-signatures"
execute="false"
force="false"
declare -a include_repos=()
declare -a exclude_repos=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)
      org="$2"
      shift 2
      ;;
    --central-workflow-repo)
      central_workflow_repo="$2"
      shift 2
      ;;
    --template-source)
      template_source="$2"
      shift 2
      ;;
    --workflow-ref)
      workflow_ref="$2"
      shift 2
      ;;
    --repo)
      include_repos+=("$2")
      shift 2
      ;;
    --exclude)
      exclude_repos+=("$2")
      shift 2
      ;;
    --limit)
      limit="$2"
      shift 2
      ;;
    --signatures-branch)
      signatures_branch="$2"
      shift 2
      ;;
    --execute)
      execute="true"
      shift
      ;;
    --force)
      force="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${org}" || -z "${central_workflow_repo}" || -z "${template_source}" ]]; then
  usage
  exit 1
fi

if [[ ! -d "${template_source}/.git" ]]; then
  echo "Template source is not a git repository: ${template_source}" >&2
  exit 1
fi

require_command gh
require_command git
require_command jq

timestamp="$(date +%Y%m%d%H%M%S)"
managed_files=(
  "CLA.md"
  ".github/pull_request_template.md"
  ".github/workflows/cla.yml"
  ".github/workflows/pr-compliance.yml"
  "docs/legal/ICLA.md"
  "docs/legal/CCLA.md"
  "docs/legal/corporate-authorizations.json"
  "docs/legal/corporate-authorizations.md"
  "docs/legal/BSD-3-Clause.txt"
)

mapfile -t repo_rows < <(
  gh repo list "${org}" --limit "${limit}" --json name,nameWithOwner,isArchived,defaultBranchRef |
    jq -r '.[] | select(.isArchived | not) | [.name, .nameWithOwner, .defaultBranchRef.name] | @tsv'
)

if [[ ${#repo_rows[@]} -eq 0 ]]; then
  echo "No repositories found for organization ${org}" >&2
  exit 1
fi

for row in "${repo_rows[@]}"; do
  IFS=$'\t' read -r repo_name repo_full_name default_branch <<<"${row}"

  if [[ ${#include_repos[@]} -gt 0 ]] && ! matches_any "${repo_name}" "${repo_full_name}" "${include_repos[@]}"; then
    continue
  fi

  if matches_any "${repo_name}" "${repo_full_name}" "${exclude_repos[@]}"; then
    continue
  fi

  echo "==> Processing ${repo_full_name}"
  temp_dir="$(mktemp -d)"
  repo_dir="${temp_dir}/repo"
  branch_name="chore/org-compliance-${timestamp}"

  gh repo clone "${repo_full_name}" "${repo_dir}" -- --depth=1 >/dev/null
  git -C "${repo_dir}" switch "${default_branch}" >/dev/null

  if [[ "${force}" != "true" ]]; then
    existing_conflict="false"
    for managed_file in "${managed_files[@]}"; do
      if [[ -e "${repo_dir}/${managed_file}" ]]; then
        echo "    skip: ${managed_file} already exists in ${repo_full_name}. Use --force to overwrite."
        existing_conflict="true"
        break
      fi
    done
    if [[ "${existing_conflict}" == "true" ]]; then
      rm -rf "${temp_dir}"
      continue
    fi
  fi

  git -C "${repo_dir}" switch -c "${branch_name}" >/dev/null
  sync_repository_files "${template_source}" "${repo_dir}" "${central_workflow_repo}" "${workflow_ref}"

  if git -C "${repo_dir}" diff --quiet; then
    echo "    no changes"
    rm -rf "${temp_dir}"
    continue
  fi

  if [[ "${execute}" != "true" ]]; then
    echo "    dry-run: changes prepared but not pushed"
    rm -rf "${temp_dir}"
    continue
  fi

  create_signatures_branch_if_missing "${repo_dir}" "${default_branch}" "${signatures_branch}"

  git -C "${repo_dir}" add .
  git -C "${repo_dir}" commit -m "docs: add organization compliance workflows" >/dev/null
  git -C "${repo_dir}" push origin "${branch_name}" >/dev/null

  gh -R "${repo_full_name}" pr create \
    --base "${default_branch}" \
    --head "${branch_name}" \
    --title "docs: add organization compliance workflows" \
    --body "$(cat <<EOF
This PR installs the shared CLA and PR compliance rollout.

Included:
- CLA / ICLA / CCLA documents
- Corporate authorization registry
- PR template
- Caller workflows pointing to ${central_workflow_repo}@${workflow_ref}

After merge:
1. Ensure \`${signatures_branch}\` remains unprotected for CLA signature commits.
2. Add \`CLA\` and \`PR Compliance\` as required status checks in organization rulesets.
EOF
)" >/dev/null

  echo "    opened PR for ${repo_full_name}"
  rm -rf "${temp_dir}"
done
