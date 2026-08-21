---
name: glmv-prompt-gen
description: 分析图片/视频并为文生图/文生视频 AI 工具（Midjourney、Stable Diffusion、DALL-E、Sora、Runway、Kling、Pika）生成专业提示词。当用户想从参考图生成 prompt 或需要提示词工程建议时使用。
category: 智谱 GLM
source: zai-org/glmv-prompt-gen
---

# GLM-V 提示词生成技能

分析参考图像或视频，并为 AI 图像/视频生成工具生成专业提示词。

## 使用场景

- 为文生图工具（Midjourney、Stable Diffusion、DALL-E 等）生成提示词
- 为文生视频工具（Sora、Runway、Kling、Pika 等）生成提示词
- 用户提到"生成prompt"、"文生图prompt"、"文生视频prompt"、"prompt工程"、"参考图生成prompt"、"generate prompt"
- 用户提供图像/视频并希望复现或重新混制
- 从参考视觉内容中提取提示词创意

## 支持的输入类型

| 类型 | 格式 | 最大大小 | 最大数量 | Base64 |
|---|---|---|---|---|
| 图像 | jpg, png, jpeg | 5MB / 6000×6000px | 50 | ✅ |
| 视频 | mp4, mkv, mov | 200MB | — | ❌（仅支持 URL） |

⚠️ 图像和视频不能在同一请求中同时使用。视频仅支持 URL。

### 输出显示规则（强制要求）

脚本运行后，**必须完整显示返回的提示词输出内容**。不得摘要、截断，或仅说"已生成提示词"。用户需要完整的提示词（尤其是英文提示词）以便直接复制粘贴。

- 显示完整输出：内容分析 + 提示词 + 提示词解析
- 在 `auto` 模式下，需同时显示文生图和文生视频提示词
- 英文提示词是核心输出，必须完整显示

## 资源链接

| 资源 | 链接 |
|---|---|
| 获取 API Key | https://bigmodel.cn/usercenter/proj-mgmt/apikeys |
| API 文档 | https://docs.bigmodel.cn/api-reference/模型-api/对话补全 |

## 前置条件

此脚本从 `ZHIPU_API_KEY` 环境变量中读取密钥，并与其他智谱技能共享该密钥。

## 使用方法

### 图像 → 文生图提示词

```bash
python scripts/prompt_gen.py --images "https://example.com/photo.jpg"
python scripts/prompt_gen.py --images /path/to/photo.png
```

### 图像 → 文生视频提示词

```bash
python scripts/prompt_gen.py --images "https://example.com/scene.jpg" --mode video
```

### 图像 → 同时生成（图像 + 视频提示词）

```bash
python scripts/prompt_gen.py --images "https://example.com/photo.jpg" --mode auto
```

### 视频 → 文生视频提示词

```bash
python scripts/prompt_gen.py --videos "https://example.com/clip.mp4" --mode video
```

### 将结果保存到文件

```bash
python scripts/prompt_gen.py --images photo.jpg --mode image -o prompt.md
```

## 输出示例（图像模式）

```
### Content Analysis
A cyberpunk cityscape at night, with dense skyscrapers, glowing neon signs, and rain-wet streets reflecting colorful light.

### Prompt
Cyberpunk cityscape at night, towering skyscrapers with glowing neon signs,
rain-wet streets reflecting colorful lights, flying cars in the distance,
volumetric fog, dramatic lighting, ultra detailed, 8K, cinematic composition

### Prompt Breakdown
- **Subject**: Futuristic skyline with skyscrapers and neon lights
- **Style**: Cyberpunk, sci-fi
- **Color**: Cool/warm contrast with blue-purple dominance and neon accents
- **Lighting**: Neon glow, wet-surface reflections, volumetric fog
- **Composition**: Wide-angle perspective with layered depth
- **Mood**: Mysterious, futuristic, high-tech
```

## CLI 参考

```
python {baseDir}/scripts/prompt_gen.py (--images IMG [IMG...] | --videos VID [VID...]) [OPTIONS]
```

| 参数 | 是否必需 | 描述 |
|---|---|---|
| `--images`, `-i` | 二者选一 | 图像路径或 URL（支持 jpg/png/jpeg，base64 也可） |
| `--videos`, `-v` | 二者选一 | 视频 URL（支持 mp4/mkv/mov，仅限 URL） |
| `--mode`, `-m` | 否 | 输出模式：`image`（默认）、`video` 或 `auto` |
| `--model`, `-m` | 否 | 模型名称（默认：`glm-4.6v`） |
| `--temperature`, `-t` | 否 | 采样温度 0-1（默认：0.6） |
| `--max-tokens` | 否 | 最大输出 token 数（默认：2048） |
| `--thinking` | 否 | 启用思考/推理模式 |
| `--output`, `-o` | 否 | 将结果保存到文件 |

## 错误处理

**未配置 API 密钥**：→ 引导用户配置 `ZHIPU_API_KEY`
**认证失败（401/403）**：→ API 密钥无效或已过期 → 重新配置
**速率限制（429）**：→ 配额已用尽 → 稍后再试
**内容被过滤**：→ 存在 `warning` 字段 → 内容被安全审核拦截
**超时**：→ 视频处理可能耗时较长 → 增加超时时间或使用更小的文件
