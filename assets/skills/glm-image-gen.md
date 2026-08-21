---
name: glm-image-gen
description: 使用智谱 GLM-Image API 从文本提示生成高质量图像。当用户想要生成图像、创作 AI 艺术、文生图或将文本描述转换为视觉内容时使用。
category: 智谱 GLM
source: zai-org/glm-image-gen
---

# GLM-Image 图片生成技能

使用智谱 GLM-Image API 根据文本提示生成高质量图像。

## 使用场景

- 从文字描述生成图片
- 创作 AI 艺术、插画或概念图
- 用户提到"生图"、"文生图"、"AI 绘画"、"generate image"、"text-to-image"、"create image"
- 用户提供描述并想看到可视化效果

## 核心特性

- **高质量生成**：高清模式可生成更精细、细节更丰富的图像（约20秒）
- **多种宽高比**：支持正方形、纵向、横向格式
- **GLM-Image 模型**：最新模型，理解力与画质均有提升
- **擅长领域**：科学插图（科普插画）、高质量人像、社交媒体图文、商业海报
- **水印控制**：可启用/禁用水印（无水印需签署免责声明）
- **内容安全**：内置内容过滤机制，确保合规

## 资源链接

| 资源 | 链接 |
|---|---|
| 获取 API Key | https://bigmodel.cn/usercenter/proj-mgmt/apikeys |
| API 文档 | https://docs.bigmodel.cn/api-reference/模型-api/图像生成 |
| 模型文档 | https://docs.bigmodel.cn/cn/guide/models/image-generation/glm-image |

## 前置条件

### API Key 配置（必需）

脚本通过 `ZHIPU_API_KEY` 环境变量获取密钥，可与其他智谱技能复用同一个 key。

**配置方式（任选一种）：**

1. Shell 环境变量：`export ZHIPU_API_KEY="你的密钥"`（Windows: `set`）
2. 项目 `.env` 文件：`ZHIPU_API_KEY=你的密钥`

## 使用方法

### 基本生成

```bash
python scripts/generate_image.py --prompt "一只在太空中骑自行车的熊猫，电影级光效" --output panda.png
```

### 指定宽高比

```bash
python scripts/generate_image.py --prompt "..." --size 1440x720   # 横向
python scripts/generate_image.py --prompt "..." --size 720x1440   # 纵向
python scripts/generate_image.py --prompt "..." --size 1024x1024  # 正方形
```

### 高清模式（更精细，约20秒）

```bash
python scripts/generate_image.py --prompt "..." --hd --output hd.png
```

### 禁用水印

```bash
python scripts/generate_image.py --prompt "..." --no-watermark
```

## CLI 参考

```
python {baseDir}/scripts/generate_image.py --prompt PROMPT [OPTIONS]
```

| 参数 | 必需 | 说明 |
|---|---|---|
| `--prompt`, `-p` | ✅ | 图像生成的文本提示 |
| `--output`, `-o` | 否 | 输出图像文件路径 |
| `--size` | 否 | 图像尺寸，如 1024x1024 |
| `--hd` | 否 | 高清模式（更慢更精细） |
| `--no-watermark` | 否 | 禁用水印 |

## 提示词撰写建议

- **具体描述**：主体、场景、动作、环境、光线、色调、风格、质量
- **明确风格**：如"写实照片"、"水彩插画"、"3D 渲染"、"扁平设计"
- **质量词**：如"高清"、"细节丰富"、"8K"
- 示例：`"科普插画：植物细胞横截面示意图，线粒体和细胞核清晰可见，明亮的教科书风格，白色背景，高清"`

## 响应格式

```json
{
 "success": true,
 "image_path": "./outputs/panda.png",
 "usage": {...},
 "warning": null,
 "error": null
}
```

## 错误处理

**API 密钥未配置**：向用户显示确切错误，引导其访问 https://bigmodel.cn/usercenter/proj-mgmt/apikeys 配置。
**认证失败（401/403）**：密钥无效或已过期 → 重新配置。
**速率限制（429）**：配额耗尽 → 告知用户等待。
**内容被过滤**：提示词触发安全审查 → 建议用户调整提示词。
