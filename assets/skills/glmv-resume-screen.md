---
name: glmv-resume-screen
description: 使用智谱 GLM-V 多模态模型批量阅读简历并按标准筛选候选人，输出 Markdown 对比表。当用户说"筛选简历"、"评估候选人"、"resume screening"时使用。
category: 智谱 GLM
source: zai-org/glmv-resume-screen
---

# GLM-V Resume Screening Skill

Batch-read resumes and screen candidates against your criteria using the ZhiPu GLM-V multimodal model.

## When to Use

* Filter/screen multiple resumes against specific criteria
* User mentions "筛选简历", "评估候选人", "简历筛选", "resume screening", "filter candidates"
* Compare candidates for a job position
* Batch-evaluate job applications

## Supported Input Types

| Type           | Formats        | Max Count        | Source     |
| -------------- | -------------- | ---------------- | ---------- |
| Resume (URL)   | pdf, docx, txt | 50               | URL        |
| Resume (Local) | pdf only       | pages ≤ 50 total | Local path |

> **Local PDF / 本地 PDF：** Local PDF files are converted page-by-page into images (base64) before sending to the model. `PyMuPDF` is required (`pip install PyMuPDF`). URL files support full formats including pdf/docx/txt.

### Output Display Rules (MANDATORY)

After running the script, **you must display the complete screening result (Markdown table) exactly as returned**. Do not summarize, truncate, or only say "screening completed". Users need each candidate's detailed analysis to decide.

* Show the full Markdown table (index, name, pass/fail, match level, reasoning)
* If output was saved (`-o`), provide the file path and show file content
* If screening output is empty, explain why

## Resource Links

| Resource        | Link |
| --------------- | ---- |
| **Get API Key** | https://bigmodel.cn/usercenter/proj-mgmt/apikeys |
| **API Docs**    | https://docs.bigmodel.cn/api-reference/模型-api/对话补全 |

## Prerequisites

This script reads the key from the `ZHIPU_API_KEY` environment variable and shares it with other Zhipu skills.

## How to Use

### Basic Screening

```bash
python scripts/resume_screen.py \
  --files "https://example.com/resume1.pdf" "https://example.com/resume2.docx" \
  --criteria "3年以上工作经验，有Python开发经验，有大型项目管理经验"
```

### Save as Markdown

```bash
python scripts/resume_screen.py \
  --files "https://example.com/resume1.pdf" "https://example.com/resume2.docx" \
  --criteria "本科以上学历，5年后端开发经验" \
  --output result.md
```

### Custom System Prompt

```bash
python scripts/resume_screen.py \
  --files "https://example.com/resume1.pdf" \
  --criteria "前端开发岗位，3年经验" \
  --system-prompt "你是一位资深技术面试官，特别关注候选人的项目深度和技术选型能力"
```

## Output Example

The model outputs a Markdown table like this:

| 序号 | 候选人姓名 | 是否符合 | 符合程度 | 原因分析 |
| ---- | ---------- | ----------- | -------- | ----------- |
| 1    | 张三       | ✅ 符合     | 高       | 5年后端经验，熟练使用Python和Django，主导过3个大型项目 |
| 2    | 李四       | ❌ 不符合   | 低       | 仅1年开发经验，主要使用Java，无Python经验 |
| 3    | 王五       | ⚠️ 部分符合 | 中       | 3年Python经验但无项目管理经验，技术栈匹配但缺乏大型项目经历 |

## CLI Reference

```
python {baseDir}/scripts/resume_screen.py --files FILE [FILE...] --criteria CRITERIA [OPTIONS]
```

| Parameter             | Required | Description |
| --------------------- | -------- | ----------- |
| --files, -f           | ✅ | Resume file URLs (pdf/docx/txt, max 50) |
| --criteria, -c        | ✅ | Screening criteria text |
| --model, -m           | No | Model name (default: glm-4.6v) |
| --system-prompt, -s   | No | Custom system prompt (default: professional HR assistant) |
| --temperature, -t     | No | Sampling temperature 0-1 (default: 0.3) |
| --max-tokens          | No | Max output tokens (default: 4096) |
| --output, -o          | No | Save result to file (.md for markdown, .json for JSON) |

## Error Handling

**API key not configured:** → Guide user to configure `ZHIPU_API_KEY`
**Authentication failed (401/403):** API key invalid/expired → reconfigure
**Rate limit (429):** Quota exhausted → wait and retry
**Local path provided (non-PDF):** → Error: only URLs supported for docx/txt
**Content filtered:** `warning` field present → content blocked by safety review
**Timeout:** Resumes too large or too many → reduce file count
