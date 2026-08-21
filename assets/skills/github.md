---
name: github
description: 使用 gh CLI 与 GitHub 交互：查看 PR CI 状态、列出 workflow 运行、查看失败日志、用 API 做高级查询。当用户要求操作 GitHub 仓库、查看 PR/CI/Issue/workflow 状态时使用。
category: 开发工具
source: steipete/github
---

# GitHub CLI (gh) 使用指南

Use the `gh` CLI to interact with GitHub. Always specify `--repo owner/repo` when not in a git directory, or use URLs directly.

## Pull Requests

Check CI status on a PR:

```bash
gh pr checks 55 --repo owner/repo
```

List recent workflow runs:

```bash
gh run list --repo owner/repo --limit 10
```

View a run and see which steps failed:

```bash
gh run view <run-id> --repo owner/repo
```

View logs for failed steps only:

```bash
gh run view <run-id> --repo owner/repo --log-failed
```

## API for Advanced Queries

The `gh api` command is useful for accessing data not available through other subcommands.

Get PR with specific fields:

```bash
gh api repos/owner/repo/pulls/55 --jq '.title, .state, .user.login'
```

## JSON Output

Most commands support `--json` for structured output. Use `--jq` to filter:

```bash
gh issue list --repo owner/repo --json number,title --jq '.[] | "\(.number): \(.title)"'
```

## 常用命令速查

- `gh pr list --repo owner/repo` — 列出 PR
- `gh pr view 55 --repo owner/repo` — 查看 PR 详情
- `gh pr diff 55 --repo owner/repo` — 查看 PR 变更
- `gh issue list --repo owner/repo` — 列出 Issue
- `gh repo view owner/repo` — 查看仓库信息
- `gh repo clone owner/repo` — 克隆仓库
- `gh release list --repo owner/repo` — 列出发布版本
- `gh api repos/owner/repo/commits?per_page=5` — 查看最近提交

## 注意事项

- 不在 git 仓库目录中时，所有命令必须带 `--repo owner/repo`
- 需要认证的操作要求本机已 `gh auth login`
- 查询结果较长时用 `--limit` 或 `--jq` 截取关键信息
