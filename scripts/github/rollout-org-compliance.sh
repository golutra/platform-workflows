#!/usr/bin/env bash

set -euo pipefail

supported_compliance_profiles=(
  "bsl-change-license-commercial"
  "apache-2.0"
  "mit"
  "bsd-3-clause"
  "gpl-2.0-or-later"
  "gpl-3.0-or-later"
)

usage() {
  cat <<'EOF'
Usage:
  scripts/github/rollout-org-compliance.sh \
    --org <github-org> \
    --central-workflow-repo <owner/repo> \
    [--compliance-profile <profile>] \
    [--workflow-ref <git-ref>] \
    [--repo <repo-name-or-owner/repo>]... \
    [--exclude <repo-name-or-owner/repo>]... \
    [--limit <count>] \
    [--signatures-branch <branch>] \
    [--list-compliance-profiles] \
    [--execute] \
    [--force]

Description:
  Create pull requests that install the shared CLA / PR compliance caller workflows,
  profile-specific legal documents, and PR template into repositories across a
  GitHub organization.

Options:
  --org                      GitHub organization name.
  --central-workflow-repo    Repository that hosts reusable workflows, such as
                             golutra/platform-workflows.
  --compliance-profile       Compliance profile to install. Default:
                             bsl-change-license-commercial.
  --workflow-ref             Git ref for the reusable workflow repository. Default: main.
  --repo                     Target repository. Can be repeated. If omitted, all repos
                             in the organization are selected.
  --exclude                  Repository to skip. Can be repeated.
  --limit                    Max repos fetched from GitHub when --repo is omitted.
                             Default: 200.
  --signatures-branch        Branch that stores CLA signatures. Default: cla-signatures.
  --list-compliance-profiles Print supported compliance profiles and exit.
  --execute                  Push branches and open PRs. Default is dry-run.
  --force                    Overwrite managed files even if they already exist.

Examples:
  scripts/github/rollout-org-compliance.sh \
    --org golutra \
    --central-workflow-repo golutra/platform-workflows \
    --compliance-profile apache-2.0 \
    --repo golutra/app \
    --repo golutra/cli

  scripts/github/rollout-org-compliance.sh \
    --org golutra \
    --central-workflow-repo golutra/platform-workflows \
    --compliance-profile bsl-change-license-commercial \
    --limit 50 \
    --execute
EOF
}

print_compliance_profiles() {
  cat <<'EOF'
Supported compliance profiles:
  - bsl-change-license-commercial
  - apache-2.0
  - mit
  - bsd-3-clause
  - gpl-2.0-or-later
  - gpl-3.0-or-later
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

is_supported_compliance_profile() {
  local profile="$1"
  local candidate

  for candidate in "${supported_compliance_profiles[@]}"; do
    if [[ "${candidate}" == "${profile}" ]]; then
      return 0
    fi
  done

  return 1
}

profile_usage_license_confirmation_label() {
  case "$1" in
    bsl-change-license-commercial)
      echo "I understand accepted contributions may be used under the repository's documented BSL, change-license, and commercial licensing model."
      ;;
    apache-2.0)
      echo "I understand accepted contributions may be distributed under the repository's documented Apache 2.0 licensing and distribution model and the contributor agreement terms described in CLA.md."
      ;;
    mit)
      echo "I understand accepted contributions may be distributed under the repository's documented MIT licensing and distribution model and the contributor agreement terms described in CLA.md."
      ;;
    bsd-3-clause)
      echo "I understand accepted contributions may be distributed under the repository's documented BSD-3-Clause licensing and distribution model and the contributor agreement terms described in CLA.md."
      ;;
    gpl-2.0-or-later)
      echo "I understand accepted contributions may be distributed under the repository's documented GPL-2.0-or-later licensing and distribution model and the contributor agreement terms described in CLA.md."
      ;;
    gpl-3.0-or-later)
      echo "I understand accepted contributions may be distributed under the repository's documented GPL-3.0-or-later licensing and distribution model and the contributor agreement terms described in CLA.md."
      ;;
    *)
      echo "Unsupported compliance profile: $1" >&2
      exit 1
      ;;
  esac
}

profile_root_license_overview() {
  case "$1" in
    bsl-change-license-commercial)
      echo '当前采用 [`Business Source License 1.1`](./LICENSE) 分发，并在 `LICENSE` 中声明未来切换到 `GPL-2.0-or-later`。'
      ;;
    apache-2.0)
      echo '当前按 [`Apache License 2.0`](./LICENSE) 分发。'
      ;;
    mit)
      echo '当前按 [`MIT License`](./LICENSE) 分发。'
      ;;
    bsd-3-clause)
      echo '当前按 [`BSD-3-Clause`](./LICENSE) 分发。'
      ;;
    gpl-2.0-or-later)
      echo '当前按 [`GPL-2.0-or-later`](./LICENSE) 分发。'
      ;;
    gpl-3.0-or-later)
      echo '当前按 [`GPL-3.0-or-later`](./LICENSE) 分发。'
      ;;
    *)
      echo "Unsupported compliance profile: $1" >&2
      exit 1
      ;;
  esac
}

profile_contribution_use_summary() {
  case "$1" in
    bsl-change-license-commercial)
      echo '被接收的贡献可能被用于当前 `BSL 1.1` 版本、未来 `GPL-2.0-or-later` 版本，以及项目维护者提供的商业授权版本。'
      ;;
    apache-2.0)
      echo '被接收的贡献可能被用于仓库文档所述的 `Apache 2.0` 许可与分发模型，以及 [`CLA.md`](./CLA.md) 中说明的贡献协议安排。'
      ;;
    mit)
      echo '被接收的贡献可能被用于仓库文档所述的 `MIT` 许可与分发模型，以及 [`CLA.md`](./CLA.md) 中说明的贡献协议安排。'
      ;;
    bsd-3-clause)
      echo '被接收的贡献可能被用于仓库文档所述的 `BSD-3-Clause` 许可与分发模型，以及 [`CLA.md`](./CLA.md) 中说明的贡献协议安排。'
      ;;
    gpl-2.0-or-later)
      echo '被接收的贡献可能被用于仓库文档所述的 `GPL-2.0-or-later` 许可与分发模型，以及 [`CLA.md`](./CLA.md) 中说明的贡献协议安排。'
      ;;
    gpl-3.0-or-later)
      echo '被接收的贡献可能被用于仓库文档所述的 `GPL-3.0-or-later` 许可与分发模型，以及 [`CLA.md`](./CLA.md) 中说明的贡献协议安排。'
      ;;
    *)
      echo "Unsupported compliance profile: $1" >&2
      exit 1
      ;;
  esac
}

profile_rejection_sentence() {
  case "$1" in
    bsl-change-license-commercial)
      echo '如果你不能接受贡献可能被用于 `BSL 1.1`、未来 `GPL-2.0-or-later` 或商业授权，请不要向本仓库提交贡献。'
      ;;
    apache-2.0)
      echo '如果你不能接受贡献按仓库文档所述的 `Apache 2.0` 分发模型和 [`CLA.md`](./CLA.md) 约定被使用，请不要向本仓库提交贡献。'
      ;;
    mit)
      echo '如果你不能接受贡献按仓库文档所述的 `MIT` 分发模型和 [`CLA.md`](./CLA.md) 约定被使用，请不要向本仓库提交贡献。'
      ;;
    bsd-3-clause)
      echo '如果你不能接受贡献按仓库文档所述的 `BSD-3-Clause` 分发模型和 [`CLA.md`](./CLA.md) 约定被使用，请不要向本仓库提交贡献。'
      ;;
    gpl-2.0-or-later)
      echo '如果你不能接受贡献按仓库文档所述的 `GPL-2.0-or-later` 分发模型和 [`CLA.md`](./CLA.md) 约定被使用，请不要向本仓库提交贡献。'
      ;;
    gpl-3.0-or-later)
      echo '如果你不能接受贡献按仓库文档所述的 `GPL-3.0-or-later` 分发模型和 [`CLA.md`](./CLA.md) 约定被使用，请不要向本仓库提交贡献。'
      ;;
    *)
      echo "Unsupported compliance profile: $1" >&2
      exit 1
      ;;
  esac
}

profile_icla_scope_block() {
  case "$1" in
    bsl-change-license-commercial)
      cat <<'EOF'
   - 当前采用的 `Business Source License 1.1`
   - [`LICENSE`](../../LICENSE) 中声明的未来 `GPL-2.0-or-later`
   - 项目维护者提供的商业授权、双重许可或其他后续分发安排
EOF
      ;;
    apache-2.0)
      cat <<'EOF'
   - 仓库当前文档所述的 `Apache License 2.0` 许可与分发模型
   - [`CLA.md`](../../CLA.md) 和本仓库贡献流程中声明的贡献协议安排
EOF
      ;;
    mit)
      cat <<'EOF'
   - 仓库当前文档所述的 `MIT` 许可与分发模型
   - [`CLA.md`](../../CLA.md) 和本仓库贡献流程中声明的贡献协议安排
EOF
      ;;
    bsd-3-clause)
      cat <<'EOF'
   - 仓库当前文档所述的 `BSD-3-Clause` 许可与分发模型
   - [`CLA.md`](../../CLA.md) 和本仓库贡献流程中声明的贡献协议安排
EOF
      ;;
    gpl-2.0-or-later)
      cat <<'EOF'
   - 仓库当前文档所述的 `GPL-2.0-or-later` 许可与分发模型
   - [`CLA.md`](../../CLA.md) 和本仓库贡献流程中声明的贡献协议安排
EOF
      ;;
    gpl-3.0-or-later)
      cat <<'EOF'
   - 仓库当前文档所述的 `GPL-3.0-or-later` 许可与分发模型
   - [`CLA.md`](../../CLA.md) 和本仓库贡献流程中声明的贡献协议安排
EOF
      ;;
    *)
      echo "Unsupported compliance profile: $1" >&2
      exit 1
      ;;
  esac
}

profile_icla_summary_point() {
  case "$1" in
    bsl-change-license-commercial)
      echo 'This grant explicitly covers the current `Business Source License 1.1`, the future `GPL-2.0-or-later` change license declared in [`LICENSE`](../../LICENSE), and commercial licensing or other downstream licensing arrangements.'
      ;;
    apache-2.0)
      echo 'This grant explicitly covers the repository''s documented `Apache License 2.0` licensing and distribution model, together with the contributor agreement terms described in [`CLA.md`](../../CLA.md).'
      ;;
    mit)
      echo 'This grant explicitly covers the repository''s documented `MIT` licensing and distribution model, together with the contributor agreement terms described in [`CLA.md`](../../CLA.md).'
      ;;
    bsd-3-clause)
      echo 'This grant explicitly covers the repository''s documented `BSD-3-Clause` licensing and distribution model, together with the contributor agreement terms described in [`CLA.md`](../../CLA.md).'
      ;;
    gpl-2.0-or-later)
      echo 'This grant explicitly covers the repository''s documented `GPL-2.0-or-later` licensing and distribution model, together with the contributor agreement terms described in [`CLA.md`](../../CLA.md).'
      ;;
    gpl-3.0-or-later)
      echo 'This grant explicitly covers the repository''s documented `GPL-3.0-or-later` licensing and distribution model, together with the contributor agreement terms described in [`CLA.md`](../../CLA.md).'
      ;;
    *)
      echo "Unsupported compliance profile: $1" >&2
      exit 1
      ;;
  esac
}

write_cla_caller() {
  local file_path="$1"
  local workflow_repo="$2"
  local workflow_ref="$3"
  local compliance_profile="$4"

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
      compliance-profile: ${compliance_profile}
EOF
}

write_pr_compliance_caller() {
  local file_path="$1"
  local workflow_repo="$2"
  local workflow_ref="$3"
  local compliance_profile="$4"

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
      compliance-profile: ${compliance_profile}
EOF
}

write_pull_request_template() {
  local file_path="$1"
  local compliance_profile="$2"
  local usage_label

  usage_label="$(profile_usage_license_confirmation_label "${compliance_profile}")"

  cat >"${file_path}" <<EOF
## Contribution Capacity

- [ ] This contribution is submitted in my personal capacity.
- [ ] This contribution is submitted on behalf of an organization that already has a signed CCLA on file.

Organization name: None
Authorization reference: None

## Required Declarations

- [ ] I have the legal right to submit this contribution.
- [ ] ${usage_label}
- [ ] I have disclosed below any third-party, copied, or adapted code and the relevant source/license details.
- [ ] I have reviewed any AI-assisted output included in this PR and confirmed that I have the right to submit it.
- [ ] I understand that undisclosed or incompatible third-party code may cause this PR to be rejected or later removed.

## Third-Party / Copied / Adapted Code Disclosure

None.

## AI Assistance Disclosure

None.

## Co-author Disclosure

None.
EOF
}

write_cla_overview() {
  local file_path="$1"
  local repo_name="$2"
  local compliance_profile="$3"
  local license_overview
  local use_summary
  local rejection_sentence
  local why_need_first_point
  local inbound_purpose

  license_overview="$(profile_root_license_overview "${compliance_profile}")"
  use_summary="$(profile_contribution_use_summary "${compliance_profile}")"
  rejection_sentence="$(profile_rejection_sentence "${compliance_profile}")"

  case "${compliance_profile}" in
    bsl-change-license-commercial)
      why_need_first_point="\`${repo_name}\` 不只是一个普通开源仓库；贡献可能被用于当前 \`BSL 1.1\` 版本、未来 \`GPL-2.0-or-later\` 版本，以及项目维护者提供的商业授权版本。"
      inbound_purpose="这样做的目的不是替代本仓库的项目许可证，而是降低未来在再许可、版本迁移、商业授权和代码捐赠中的权利不确定性。"
      ;;
    *)
      why_need_first_point="即使仓库采用标准开源许可证，维护者仍需确认贡献者拥有完整授权，尤其是雇佣关系、第三方代码拷贝、AI 生成代码来源不清这些场景。"
      inbound_purpose="这样做的目的不是替代本仓库的项目许可证，而是降低未来在许可证兼容处理、下游分发和代码捐赠中的权利不确定性。"
      ;;
  esac

  cat >"${file_path}" <<EOF
# ${repo_name} CLA Overview

\`${repo_name}\` ${license_overview} 为了降低外部贡献的授权链风险，本仓库采用分层贡献协议：

1. 个人贡献者通过 [\`ICLA\`](./docs/legal/ICLA.md) 进行签署。
2. 代表公司、团队或其他组织提交贡献时，除个人签署 \`ICLA\` 外，还需要由有权签字人提供 [\`CCLA\`](./docs/legal/CCLA.md) 或等效书面授权。
3. 已批准的企业授权会登记在 [\`corporate-authorizations.json\`](./docs/legal/corporate-authorizations.json) 中，并在 PR 中通过授权编号引用；[\`corporate-authorizations.md\`](./docs/legal/corporate-authorizations.md) 用于说明维护规则。

## 为什么需要这套流程

- ${why_need_first_point}
- 仅有“提了 PR”不足以说明贡献者拥有完整授权，尤其是雇佣关系、第三方代码拷贝、AI 生成代码来源不清这些场景。
- 因此，本仓库要求在 PR 阶段明确贡献者身份、授权来源、第三方来源披露和 AI 辅助披露。

## 入站贡献模型

除 \`ICLA\` / \`CCLA\` 中约定的额外授权外，提交到本仓库并被接收的代码贡献，还应视为按 [\`BSD-3-Clause\`](./docs/legal/BSD-3-Clause.txt) 入站提交，不附加额外限制。

${inbound_purpose}

## 贡献前请阅读

- [\`docs/legal/ICLA.md\`](./docs/legal/ICLA.md)
- [\`docs/legal/CCLA.md\`](./docs/legal/CCLA.md)
- [\`docs/legal/corporate-authorizations.json\`](./docs/legal/corporate-authorizations.json)
- [\`docs/legal/corporate-authorizations.md\`](./docs/legal/corporate-authorizations.md)

${use_summary}

${rejection_sentence}
EOF
}

write_icla() {
  local file_path="$1"
  local repo_name="$2"
  local compliance_profile="$3"
  local scope_block
  local summary_point

  scope_block="$(profile_icla_scope_block "${compliance_profile}")"
  summary_point="$(profile_icla_summary_point "${compliance_profile}")"

  cat >"${file_path}" <<EOF
# ${repo_name} Individual Contributor License Agreement

本文档用于个人贡献者签署。你在 PR 评论区回复指定签署文本时，即表示你已阅读并同意本协议。

本模板用于工程落地，不构成法律意见。正式启用前，建议由你或律师结合项目实际商业模式审阅确认。

## 中文条款

当你以个人身份，或经雇主/组织授权以个人 GitHub 账号向 \`${repo_name}\` 提交代码、文档、测试、资源文件或其他贡献时，你确认并同意：

1. 你有权提交该贡献，并且该贡献不会违反你与雇主、客户、前雇主、前客户或任何第三方之间的合同、保密义务、知识产权限制或其他法律义务。
2. 该贡献为你的原创作品，或你已经取得足够授权，可将该贡献按本协议和本仓库贡献流程授予项目维护者使用。
3. 你保留自己原本拥有的版权；但你同意该贡献在被项目接收时，也按 [\`BSD-3-Clause\`](./BSD-3-Clause.txt) 入站提交，不附加额外限制。
4. 此外，你授予 \`${repo_name}\` 项目维护者、版权持有人及其被授权方一项全球范围、永久、不可撤销、非独占、可再许可的许可，用于复制、修改、分发、公开展示、公开表演、再许可及以其他方式利用该贡献。
5. 上述授权明确覆盖：
${scope_block}
6. 如果你代表公司、团队或其他组织提交贡献，你确认自己已经获得足够授权；如果仓库要求企业授权登记，你还需要确保对应 \`CCLA\` 或等效书面授权已在项目侧备案。
7. 你必须在 PR 中如实披露任何第三方代码、复制或改编片段、AI 辅助生成内容，以及共同作者 \`Co-authored-by\` 信息和这些内容的来源与许可证状态。未披露的高风险来源内容可以导致 PR 被拒绝或后续移除。
8. 贡献按“现状”提供；在适用法律允许范围内，你不对适销性、特定用途适用性或不侵权提供任何明示或默示保证。

如果你不同意这些条款，请不要向本仓库提交贡献。

## English Summary

By signing this \`ICLA\`, you confirm that:

1. You have the legal right to submit the contribution.
2. The contribution is original to you, or you have sufficient rights to submit it.
3. Accepted code contributions are also submitted inbound under [\`BSD-3-Clause\`](./BSD-3-Clause.txt), without additional restrictions.
4. You grant the \`${repo_name}\` maintainers and rights holders a perpetual, irrevocable, worldwide, non-exclusive, sublicensable license to use, modify, distribute, relicense, and otherwise exploit the contribution.
5. ${summary_point}
6. If you contribute on behalf of an organization, you confirm that you are authorized to do so and that any required corporate authorization is already on file.
7. You will truthfully disclose any third-party, copied, adapted, AI-assisted, or co-authored content in the pull request.

## GitHub 签署方式

在 Pull Request 评论区回复下面这句完整文本，即视为你签署并接受本协议：

\`I have read the ICLA and I hereby sign this agreement.\`
EOF
}

write_ccla() {
  local file_path="$1"
  local repo_name="$2"
  local compliance_profile="$3"
  local scope_block

  scope_block="$(profile_icla_scope_block "${compliance_profile}")"

  cat >"${file_path}" <<EOF
# ${repo_name} Corporate Contributor License Agreement

本文档是 \`${repo_name}\` 的企业贡献授权模板，适用于员工、承包商或其他代表组织提交贡献的场景。

本模板用于工程落地，不构成法律意见。正式启用前，建议由有权签字人或律师审阅。

## 使用方式

1. 由组织的有权签字人填写并确认本模板，或提供内容等效的企业授权文件。
2. 将签字版发送给仓库维护者，供线下留档。
3. 维护者审核后，在 [\`corporate-authorizations.json\`](./corporate-authorizations.json) 中登记授权编号。
4. 之后，获授权的贡献者在 PR 中填写对应授权编号，并仍需完成个人 \`ICLA\` 签署。

## 授权模板

### 授权主体信息

- Organization Name:
- Registration Number:
- Jurisdiction:
- Registered Address:
- Authorized Signatory Name:
- Authorized Signatory Title:
- Authorized Signatory Email:

### 授权贡献者范围

- Authorized GitHub Usernames:
- Authorized Emails:
- Authorized Email Domains:
- Effective Date:
- Expiration Date:

### 授权声明

作为上述组织的有权签字人，我方确认并同意：

1. 我方有权允许上述授权贡献者向 \`${repo_name}\` 提交贡献。
2. 上述贡献者在授权范围内提交的贡献，不违反我方对第三方承担的合同、保密义务或知识产权限制。
3. 我方保留自己原本拥有的版权；但对于被 \`${repo_name}\` 接收的贡献，我方同意这些代码贡献也按 [\`BSD-3-Clause\`](./BSD-3-Clause.txt) 入站提交，不附加额外限制。
4. 我方进一步授予 \`${repo_name}\` 项目维护者、版权持有人及其被授权方一项全球范围、永久、不可撤销、非独占、可再许可的许可，用于复制、修改、分发、公开展示、公开表演、再许可及以其他方式利用这些贡献。
5. 上述授权明确覆盖：
${scope_block}
6. 我方理解并接受：若贡献中包含第三方代码、复制或改编内容、\`Co-authored-by\` 共同作者信息、或来源不明确的 AI 生成内容，贡献者必须在 PR 中如实披露；项目维护者有权拒绝接收或移除相关内容。

### 签字区

- Signature:
- Name:
- Title:
- Date:

## 说明

- \`CCLA\` 不替代个人签署的 \`ICLA\`，两者用途不同。
- 维护者可以要求补充更多授权材料，以降低企业代码误提或内部授权不足的风险。
EOF
}

write_corporate_authorizations_json() {
  local file_path="$1"

  cat >"${file_path}" <<'EOF'
{
  "version": 1,
  "authorizations": []
}
EOF
}

write_corporate_authorizations_md() {
  local file_path="$1"

  cat >"${file_path}" <<'EOF'
# Corporate Authorization Registry

本文件用于说明企业贡献授权的维护规则。

机器可读的授权源文件位于：

- [`corporate-authorizations.json`](./corporate-authorizations.json)

## 规则

- 授权编号建议采用 `CCA-YYYY-NNN` 格式，例如 `CCA-2026-001`。
- 只有维护者确认收到有效 `CCLA` 或等效书面授权后，才应在 `corporate-authorizations.json` 中新增记录。
- PR 中如果声明“代表组织贡献”，必须填写这里已有的授权编号。
- `authorizedGitHubUsernames` 用于声明该授权覆盖的 GitHub 用户名。
- `authorizedEmails` 用于声明该授权覆盖的共同作者邮箱；如果 PR 中存在 `Co-authored-by:`，这些邮箱也必须被覆盖。
- `status` 建议使用 `Active`、`Expired`、`Revoked` 这类明确状态值；只有 `Active` 会被工作流放行。
- 授权过期、撤销或范围变更时，应及时更新状态与备注。

## JSON 结构示例

```json
{
  "version": 1,
  "authorizations": [
    {
      "authorizationReference": "CCA-2026-001",
      "organization": "Example Corp",
      "authorizedGitHubUsernames": ["alice", "bob"],
      "authorizedEmails": ["alice@example.com", "bob@example.com"],
      "effectiveDate": "2026-03-21",
      "expirationDate": "2027-03-21",
      "status": "Active",
      "notes": "Optional notes"
    }
  ]
}
```
EOF
}

write_bsd_3_clause() {
  local file_path="$1"

  cat >"${file_path}" <<'EOF'
BSD 3-Clause License

Copyright (c) <year>, <owner>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
EOF
}

sync_repository_files() {
  local target_root="$1"
  local workflow_repo="$2"
  local workflow_ref="$3"
  local compliance_profile="$4"
  local repo_name="$5"

  mkdir -p "${target_root}/.github/workflows" "${target_root}/docs/legal"

  write_cla_overview "${target_root}/CLA.md" "${repo_name}" "${compliance_profile}"
  write_pull_request_template "${target_root}/.github/pull_request_template.md" "${compliance_profile}"
  write_cla_caller "${target_root}/.github/workflows/cla.yml" "${workflow_repo}" "${workflow_ref}" "${compliance_profile}"
  write_pr_compliance_caller "${target_root}/.github/workflows/pr-compliance.yml" "${workflow_repo}" "${workflow_ref}" "${compliance_profile}"
  write_icla "${target_root}/docs/legal/ICLA.md" "${repo_name}" "${compliance_profile}"
  write_ccla "${target_root}/docs/legal/CCLA.md" "${repo_name}" "${compliance_profile}"
  write_corporate_authorizations_json "${target_root}/docs/legal/corporate-authorizations.json"
  write_corporate_authorizations_md "${target_root}/docs/legal/corporate-authorizations.md"
  write_bsd_3_clause "${target_root}/docs/legal/BSD-3-Clause.txt"
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
compliance_profile="bsl-change-license-commercial"
workflow_ref="main"
limit="200"
signatures_branch="cla-signatures"
list_compliance_profiles="false"
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
    --compliance-profile)
      compliance_profile="$2"
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
    --list-compliance-profiles)
      list_compliance_profiles="true"
      shift
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

if [[ "${list_compliance_profiles}" == "true" ]]; then
  print_compliance_profiles
  exit 0
fi

if [[ -z "${org}" || -z "${central_workflow_repo}" ]]; then
  usage
  exit 1
fi

if ! is_supported_compliance_profile "${compliance_profile}"; then
  echo "Unsupported compliance profile: ${compliance_profile}" >&2
  print_compliance_profiles >&2
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
  sync_repository_files \
    "${repo_dir}" \
    "${central_workflow_repo}" \
    "${workflow_ref}" \
    "${compliance_profile}" \
    "${repo_name}"

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
- Profile-specific CLA / ICLA / CCLA documents
- Corporate authorization registry
- PR template
- Caller workflows pointing to ${central_workflow_repo}@${workflow_ref}
- Compliance profile: ${compliance_profile}

After merge:
1. Ensure \`${signatures_branch}\` remains unprotected for CLA signature commits.
2. Add \`CLA\` and \`PR Compliance\` as required status checks in organization rulesets.
EOF
)" >/dev/null

  echo "    opened PR for ${repo_full_name}"
  rm -rf "${temp_dir}"
done
