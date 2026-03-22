# Repository Compliance Onboarding

本文档用于说明一个新仓库如何接入组织统一的 `CLA + PR Compliance` 流程。

## 最小接入步骤

1. 使用 `rollout-org-compliance.sh` 向目标仓库下发：
   - `CLA.md`
   - `docs/legal/*`
   - `.github/pull_request_template.md`
   - `.github/workflows/cla.yml`
   - `.github/workflows/pr-compliance.yml`
2. 为目标仓库创建未受保护的 `cla-signatures` 分支。
3. 为目标仓库配置 GitHub App 凭据：
   - repository variable `CLA_APP_ID`
   - repository secret `CLA_APP_PRIVATE_KEY`
4. 如需兼容旧流程，可临时保留仓库 secret `CLA_BOT_TOKEN` 作为回退。
5. 在默认分支保护规则中把 `CLA` 和 `PR Compliance` 设为 required checks。
6. 发起一个真实测试 PR，验证：
   - `PR Compliance` 自动触发
   - `CLA` 自动触发
   - 评论签署文本后，签名记录被写入 `cla-signatures`
   - 评论作者与账本写入使用 GitHub App 身份
   - 两个检查都能通过

## 常见失败点

- 没有 `cla-signatures` 分支，导致签署记录无法写入。
- workflow 调用里没有传 `app-id`，或仓库没有配置 `CLA_APP_ID` / `CLA_APP_PRIVATE_KEY`。
- 组织层把 workflow token 限制为只读，同时仓库里既没有 GitHub App 私钥，也没有 `CLA_BOT_TOKEN` 兜底。
- 默认分支没有 required checks，导致工作流虽然跑了，但不能真正阻塞合并。
- PR 没有按模板填写，导致 `PR Compliance` 一直失败。

## 建议维护规则

- `master/main` 使用受保护分支规则。
- `cla-signatures` 不要开启严格保护，避免机器人写入失败。
- `corporate-authorizations.json` 只由维护者更新。
- 新增 `compliance-profile` 时，先修改中央 profile 配置，再通过自测 workflow 验证生成结果。
