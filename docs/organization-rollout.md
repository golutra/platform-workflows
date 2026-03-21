# Organization Rollout Guide

本文档说明如何把 `golutra` 的 `CLA + PR Compliance` 方案扩展到整个 GitHub 组织。

## 推荐架构

建议拆成两层：

1. 中央工作流仓库  
   只存放 reusable workflows 和组织级 rollout 工具，例如 `golutra/platform-workflows`
2. 业务仓库  
   存放 `CLA.md`、`docs/legal/*`、`pull_request_template.md` 和很薄的 caller workflows

这样做的好处：

- 合规逻辑只维护一份
- 各仓库仍然保留自己的 `CLA.md` 和法律文档副本，PR 页面上的链接始终指向当前仓库
- 组织级 ruleset 可以统一要求 `CLA` 和 `PR Compliance` 两个状态检查

## 第一步：同步 reusable workflows

在中央工作流仓库根目录执行：

```bash
scripts/github/sync-central-compliance-workflows.sh /Users/skyseek/Desktop/project/open/golutra
```

这会从源仓库复制：

- `.github/workflows/cla-reusable.yml`
- `.github/workflows/pr-compliance-reusable.yml`

然后提交并推送到中央工作流仓库。

## 第二步：批量向组织仓库发 PR

在中央工作流仓库根目录执行：

```bash
scripts/github/rollout-org-compliance.sh \
  --org golutra \
  --central-workflow-repo golutra/platform-workflows \
  --template-source /Users/skyseek/Desktop/project/open/golutra \
  --workflow-ref v1.0.1 \
  --execute
```

默认行为说明：

- 不传 `--repo` 时，会处理指定组织下的非归档仓库
- 不传 `--execute` 时，仅做 dry-run，不会推送分支或创建 PR
- 不传 `--force` 时，如果目标仓库已经存在这些文件，脚本会跳过，避免直接覆盖

只处理少量仓库时，可以显式指定：

```bash
scripts/github/rollout-org-compliance.sh \
  --org golutra \
  --central-workflow-repo golutra/platform-workflows \
  --template-source /Users/skyseek/Desktop/project/open/golutra \
  --repo golutra/app \
  --repo golutra/cli \
  --execute
```

## 脚本会下发哪些文件

- `CLA.md`
- `.github/pull_request_template.md`
- `.github/workflows/cla.yml`
- `.github/workflows/pr-compliance.yml`
- `docs/legal/ICLA.md`
- `docs/legal/CCLA.md`
- `docs/legal/corporate-authorizations.json`
- `docs/legal/corporate-authorizations.md`
- `docs/legal/BSD-3-Clause.txt`

注意：

- 脚本不会自动改写现有的 `CONTRIBUTING.md`
- 脚本会尝试为每个仓库创建 `cla-signatures` 分支
- caller workflows 会指向你指定的中央工作流仓库和 ref

## 第三步：组织级 GitHub 设置

所有 PR 合并前，建议完成这几项组织设置：

1. 在中央工作流仓库 `Settings -> Actions -> General` 中允许组织内仓库访问 reusable workflows
2. 在组织 ruleset 里把 `CLA` 和 `PR Compliance` 设为 required status checks
3. 先用 `Evaluate` 模式观察，再切换到 `Active`

## 企业贡献授权维护

每个业务仓库仍需自己维护：

- `docs/legal/corporate-authorizations.json`
- `docs/legal/corporate-authorizations.md`
- 对应仓库的线下 `CCLA` 授权存档

原因很简单：

- 企业授权是仓库级法律事实，不应该只在中央工作流仓库保存
- `PR Compliance` 读取的是当前仓库自己的 `corporate-authorizations.json`

## 建议的 rollout 顺序

1. 先在一个测试仓库验证整个流程
2. 再 rollout 到 2-3 个真实仓库
3. 确认 `cla-signatures` 分支、PR 评论、required checks 都正常
4. 最后再对整个组织执行批量 rollout
