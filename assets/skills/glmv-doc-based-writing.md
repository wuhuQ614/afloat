---
name: glmv-doc-based-writing
description: 使用智谱 GLM-V 多模态模型阅读文档（PDF/DOCX）并按要求撰写内容（文章/报告/简报/书评/提案/发言稿等）。当用户要求基于文档写作、文档解读、新闻稿撰写时使用。
category: 智谱 GLM
source: zai-org/glmv-doc-based-writing
---

# GLM-V 基于文档的写作技能

使用智谱 GLM-V 多模态模型，理解给定文档，并根据您的要求撰写文本内容（论文/文章/随笔/报告/评论/帖子/简报/提案/计划）。

## 使用场景

- 在阅读所提供文档后，根据指定要求撰写文本内容
- 用户提到"基于文档的写作"、"文章撰写"、"文档解读"、"新闻稿撰写"、"简报撰写"、"影评/书评撰写"、"内容总结"、"内容创作"、"评论写作"、"文档续写"、"文档翻译"、"方案策划"、"发言稿撰写"、"document-based writing"、"press release writing"、"speech writing"

## 支持的输入类型

| 类型 | 格式 | 最大数量 | 来源 |
|---|---|---|---|
| 文档（URL） | pdf, docx | 50 | URL |
| 文档（本地） | 仅 pdf | 总页数 ≤ 50 | 本地路径 |

**Local PDF / 本地 PDF：** 本地 PDF 文件在发送给模型前会逐页转换为图片（base64）。需要安装 `PyMuPDF`（`pip install PyMuPDF`）。URL 文件支持包括 pdf/docx/txt 在内的完整格式。

### 输出显示规则（强制要求）

脚本运行后，**必须原样显示返回的完整内容（Markdown 格式）**。不得进行摘要、截断、翻译、评论，或仅回复"写作完成！"。

## 资源链接

| 资源 | 链接 |
|---|---|
| 获取 API Key | https://bigmodel.cn/usercenter/proj-mgmt/apikeys |
| API 文档 | https://docs.bigmodel.cn/api-reference/模型-api/对话补全 |

## 先决条件

此脚本从 `ZHIPU_API_KEY` 环境变量中读取密钥，并与其他智谱技能共享该密钥。

**配置方式（任选一种）：**

1. Shell 环境变量：`export ZHIPU_API_KEY="你的密钥"`（Windows: `set`）
2. 项目 `.env` 文件：`ZHIPU_API_KEY=你的密钥`

## 使用方法

### 基础筛选

```bash
python scripts/doc_based_writing.py \
  --files "https://example.com/doucment1.pdf" "https://example.com/doucment2.docx" \
  --requirements "基于这篇论文撰写公众号文章，要求偏技术风格"
```

### 保存为 Markdown

```bash
python scripts/doc_based_writing.py \
  --files "https://example.com/doucment1.pdf" "https://example.com/doucment2.docx" \
  --requirements "总结文档主要内容和核心观点" \
  --output result.md
```

### 自定义系统提示词

```bash
python scripts/doc_based_writing.py \
  --files "https://example.com/doucment1.pdf" \
  --criteria "撰写新闻稿" \
  --system-prompt "你是一位拥有20年跨领域写作经验的资深写作专家，擅长撰写新闻稿"
```

## CLI 参考

```
python scripts/doc_based_writing.py --files FILE [FILE...] --requirements REQUIREMENTS [OPTIONS]
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `--files`, `-f` | ✅ | 文档文件 URL（pdf/docx，最多 50 个） |
| `--requirements`, `-c` | ✅ | 写作要求文本 |
| `--model`, `-m` | 否 | 模型名称（默认：`glm-4.6v`） |
| `--system-prompt`, `-s` | 否 | 自定义系统提示 |
| `--temperature`, `-t` | 否 | 采样温度 0-1（默认：0.6） |
| `--max-tokens` | 否 | 最大输出 token 数（默认：10000） |
| `--output`, `-o` | 否 | 将结果保存到文件（`.md` 表示 markdown，`.json` 表示 JSON） |
| `--pretty` | 否 | 美化打印 JSON 输出 |

## 错误处理

**未配置 API 密钥**：→ 引导用户配置 `ZHIPU_API_KEY`
**认证失败 (401/403)**：→ API 密钥无效或已过期 → 重新配置
**速率限制 (429)**：→ 配额已用尽 → 等待后重试
**提供了本地路径（非 PDF）**：→ 错误：仅支持 URL
**内容被过滤**：→ 存在 `warning` 字段 → 内容被安全审查拦截
**超时**：→ 文档过大或数量过多 → 减少文件数量
