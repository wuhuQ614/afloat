---
name: glmv-pdf-to-ppt
description: 将 PDF（研究论文、报告或任何文档）转换为润色过的多页 HTML 演示文稿，附带结构化大纲 JSON 和摘要 markdown。当用户提到从 PDF 制作幻灯片或 PPT 时触发。
category: 智谱 GLM
source: zai-org/glmv-pdf-to-ppt
---

# PDF → HTML PPT 技能

将任意 PDF 转换为多页 HTML 演示文稿。页面以 DPI 120 转换为图像，按顺序阅读以理解内容，然后保存结构化的 `outline.json`，在本地裁剪图像（不上传至云端），逐页渲染幻灯片，最后生成 `summary.md`。

**脚本位于：** `{SKILL_DIR}/scripts/`

## 依赖项

Python 包（只需安装一次）：

```bash
pip install pymupdf pillow
```

系统工具：`curl`（macOS/Linux 已预装）。

## 使用时机

当用户要求从 PDF 制作幻灯片或演示文稿时触发——例如："make a PPT from a PDF"、"convert PDF to slides"、"create a presentation from this paper"、"根据pdf做ppt"、"根据论文做幻灯片"、"做PPT"、"做幻灯片"、"生成演示文稿"、"把这个pdf转成ppt"。

## 输出目录约定

所有输出均置于 `{WORKSPACE}/ppt/<pdf_stem>_<timestamp>/` 下：

```
ppt/
└── <pdf_stem>_<timestamp>/
    ├── outline.json        ← structured slide plan (SlidesPlan schema)
    ├── crops/              ← locally-saved cropped images
    │   ├── slide3_method_crop.png
    │   └── slide5_results_crop.png
    ├── slide_01.html
    ├── slide_02.html
    ├── ...
    └── summary.md          ← final summary document
```

- `<pdf_stem>` = 不含扩展名的 PDF 文件名
- `<timestamp>` = 格式为 `YYYYMMDD_HHMMSS`
- 每个幻灯片 HTML 通过相对路径 `crops/<name>.png` 引用图像

## 输入

`$ARGUMENTS` 是 PDF 文件（本地）路径或 HTTP/HTTPS URL。

- 如果用户提供了 **URL**：先用 curl 下载，再转换
- 如果用户提供了 **本地 PDF 路径**：直接转换

## Workflow

### Phase 0 — 创建输出目录

```python
import os, datetime
pdf_stem = os.path.splitext(os.path.basename(pdf_path))[0]
timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
out_dir = os.path.join(workspace, "ppt", f"{pdf_stem}_{timestamp}")
os.makedirs(os.path.join(out_dir, "crops"), exist_ok=True)
```

### Phase 1 — PDF 页面转图像（DPI 120）

```python
import fitz  # pymupdf
doc = fitz.open(pdf_path)
for page_idx, page in enumerate(doc):
    pix = page.get_pixmap(dpi=120)
    pix.save(os.path.join(out_dir, "crops", f"page_{page_idx+1:02d}.png"))
```

### Phase 2 — 逐页阅读理解内容

按顺序读取每页图像，理解内容结构：标题、关键论点、方法、图表、结论。

### Phase 3 — 保存 outline.json

构建结构化的幻灯片计划（SlidesPlan schema），包含：每页幻灯片的标题、要点、要引用的图像（裁剪坐标）。

### Phase 4 — 本地裁剪图像

从整页图像中裁剪出图表/插图/表格区域，保存到 `crops/`。

### Phase 5 — 渲染幻灯片 HTML

逐页渲染幻灯片：每页 slide_NN.html 引用 `crops/` 中的图像，排版美观（标题、要点、图像合理布局）。

### Phase 6 — 生成 summary.md

最终摘要文档：演示文稿的主题、页数、每页要点概述。

## 设计要求

- 幻灯片风格专业：清晰的层级、合理的字号、留白
- 图表优先：原文的图表是最有价值的内容，裁剪放大于幻灯片
- 每页幻灯片聚焦一个主题，避免信息堆叠
- 中文文档用中文幻灯片，英文文档用英文幻灯片
