---
name: glm-master-skill
description: GLM 技能总览（仅指南）：提供智谱官方 GLM 技能目录、安装方法与源链接，用于发现和安装 GLM 生态技能。当用户想了解有哪些 GLM 技能可用或如何安装时使用。
category: 技能管理
source: zai-org/glm-master-skill
---

# GLM Master Skill (Guide Only) / GLM 技能总览（仅指南）

这是一个**仅用于文档说明**的主技能。

- ✅ **介绍** 可用的 GLM 技能
- ✅ **提供官方安装链接和命令**
- ❌ **不运行任何本地脚本**
- ❌ **不使用子进程**

本 Skill 只做导航与安装说明，不执行任何本地脚本。

## Official Skills Catalog / 官方技能目录

### GLM-Image

| Skill | Purpose | Link |
|---|---|---|
| `glm-image-gen` | 文生图（文本到图像生成） | https://github.com/zai-org/GLM-skills/tree/main/skills/glm-image-gen |

### GLM-V

| Skill | Purpose | Link |
|---|---|---|
| `glmv-caption` | 图像/视频/文件描述生成 | https://github.com/zai-org/GLM-skills/tree/main/skills/glmv-caption |
| `glmv-prompt-gen` | 基于视觉输入的提示词生成 | https://github.com/zai-org/GLM-skills/tree/main/skills/glmv-prompt-gen |
| `glmv-resume-screen` | 简历筛选 | https://github.com/zai-org/GLM-skills/tree/main/skills/glmv-resume-screen |
| `glmv-grounding` | 图像/视频目标定位与边界框可视化 | https://github.com/zai-org/GLM-skills/tree/main/skills/glmv-grounding |
| `glmv-doc-based-writing` | 基于文档的内容生成（PDF/DOCX） | https://github.com/zai-org/GLM-skills/tree/main/skills/glmv-doc-based-writing |
| `glmv-pdf-to-ppt` | PDF 转 HTML 演示文稿 | https://github.com/zai-org/GLM-skills/tree/main/skills/glmv-pdf-to-ppt |
| `glmv-pdf-to-web` | PDF 转学术项目网站 | https://github.com/zai-org/GLM-skills/tree/main/skills/glmv-pdf-to-web |
| `glmv-prd-to-app` | 根据 PRD 文档和原型构建全栈 Web 应用 | https://github.com/zai-org/GLM-skills/tree/main/skills/glmv-prd-to-app |
| `glmv-stock-analyst` | 多源股票分析与报告生成 | https://github.com/zai-org/GLM-skills/tree/main/skills/glmv-stock-analyst |
| `glmv-web-replication` | 公共网站前端视觉复现 | https://github.com/zai-org/GLM-skills/tree/main/skills/glmv-web-replication |

## Installation Methods / 安装方式

### Method A: Install from Clawhub (Recommended first)

```bash
npx clawhub@latest install <skill-name>
```

Example:

```bash
npx clawhub@latest install glmv-caption
npx clawhub@latest install glm-image-gen
```

You can also install multiple skills at once:

```bash
npx clawhub@latest install glm-image-gen glmv-caption glmv-prompt-gen glmv-resume-screen glmv-grounding glmv-doc-based-writing glmv-pdf-to-ppt glmv-pdf-to-web glmv-prd-to-app glmv-stock-analyst glmv-web-replication
```

### Method B: If Clawhub is rate-limited

You may see errors like:

```
✖ Rate limit exceeded (retry in 47s, remaining: 0/20, reset in 47s)
```

1. Wait and retry after reset time.
2. Install from the official GitHub skill directory directly.

### Method C: Install from GitHub source

Use each skill's official path (see catalog above), then follow the exact setup steps in that skill's own `SKILL.md` file.

## API 密钥设置（大多数下游技能所必需）

大多数 GLM 技能都需要环境变量 `ZHIPU_API_KEY`。此主技能本身**不会**读取或使用该密钥，但下游技能会使用。

**安全最佳实践：**

- 创建一个**权限受限**的 API 密钥，仅授予你计划使用的技能所需的权限
- 仅将密钥存储在环境变量中——**切勿硬编码**到源文件中，也**不要提交**到版本控制系统
- 如果将密钥保存在 `.env` 文件中，请将 `ZHIPU_API_KEY` 添加到你的 `.gitignore` 文件中
- 定期轮换密钥，并在 https://bigmodel.cn/usercenter/proj-mgmt/apikeys 撤销未使用的密钥

获取 API 密钥：https://bigmodel.cn/usercenter/proj-mgmt/apikeys

## Agent 应如何使用此主技能

当用户请求 GLM Image / GLM-V 功能时：

1. 将用户意图匹配到目录中的一个或多个技能
2. 首先建议通过 `npx clawhub@latest install <skill-name>` 进行安装
3. 如果遇到速率限制，请告知用户稍后重试或使用 GitHub 上的技能源码
4. 打开所选技能的官方 `SKILL.md` 文件并遵循其说明

## 资源链接

- GLM-5: https://github.com/zai-org/GLM-5
- GLM-OCR: https://github.com/zai-org/GLM-OCR
- GLM-Image: https://github.com/zai-org/GLM-Image
- GLM-V: https://github.com/zai-org/GLM-V
- API 文档: https://docs.bigmodel.cn/
- API 密钥: https://bigmodel.cn/usercenter/proj-mgmt/apikeys
