---
name: glmv-pdf-to-web
description: 将 PDF（研究论文、技术报告）转换为精美的单页学术/项目网站（NeurIPS/CVPR 论文主页风格）。当用户说"做项目主页"、"根据pdf做网页"、"论文主页"时使用。
category: 智谱 GLM
source: zai-org/glmv-pdf-to-web
---

# PDF → Academic Project Website Skill

Convert a research paper or technical document PDF into a polished single-page project website — the kind used for NeurIPS/CVPR/ICLR paper releases. Pages are converted locally at DPI 120, a structured `outline.json` is saved, images are cropped locally, and the final page is saved as `index.html`.

**Scripts are in:** `{SKILL_DIR}/scripts/`

## Dependencies

Python packages (install once):

```bash
pip install pymupdf pillow
```

System tools: `curl` (pre-installed on macOS/Linux).

## When to Use

Trigger when the user asks to create a webpage or project page from a PDF — phrases like: "make a project page from a PDF", "create a paper website", "build an academic website for this paper", "论文主页", "做项目主页", "根据pdf做网页", "把论文做成主页".

## Output Directory Convention

All output goes under `{WORKSPACE}/web/<pdf_stem>_<timestamp>/`:

```
web/
└── <pdf_stem>_<timestamp>/
    ├── outline.json        ← structured web plan (WebPlan schema)
    ├── crops/              ← locally-saved cropped images
    │   ├── fig_arch_crop.png
    │   ├── table_results_crop.png
    │   └── ...
    └── index.html          ← the website
```

- `<pdf_stem>` = PDF filename without extension
- `<timestamp>` = format `YYYYMMDD_HHMMSS`
- HTML references images via relative path `crops/<name>_crop.png`

## Input

`$ARGUMENTS` is the path to the PDF file (local) or an HTTP/HTTPS URL.

- If user provides a **URL**: download with curl first, then convert
- If user provides a **local PDF path**: convert directly

## Workflow

### Phase 0 — Create Output Directory

```python
import os, datetime
pdf_stem = os.path.splitext(os.path.basename(pdf_path))[0]
timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
out_dir = os.path.join(workspace, "web", f"{pdf_stem}_{timestamp}")
os.makedirs(os.path.join(out_dir, "crops"), exist_ok=True)
```

### Phase 1 — Convert PDF Pages to Images (DPI 120)

```python
import fitz  # pymupdf
doc = fitz.open(pdf_path)
for page_idx, page in enumerate(doc):
    pix = page.get_pixmap(dpi=120)
    pix.save(os.path.join(out_dir, "crops", f"page_{page_idx+1:02d}.png"))
```

### Phase 2 — Read and Understand Content

Read pages in order: title, authors, abstract, method figure, results tables, conclusions.

### Phase 3 — Save outline.json

Structure the web plan (WebPlan schema): hero section (title/authors/affiliation/links), abstract, method overview with architecture figure, results with tables/figures, conclusion, BibTeX citation block.

### Phase 4 — Crop Key Images Locally

Crop the architecture figure, results tables, qualitative comparisons from page images.

### Phase 5 — Build index.html

Render the single-page website: hero, abstract, method, results, conclusion, BibTeX. Academic style: clean typography, generous whitespace, figures centered with captions.

## Design Guidelines

- Follow the conventions of NeurIPS/CVPR paper pages: centered title, author list with affiliations, linked buttons (PDF/Code/ArXiv), sectioned single-page layout
- Figures are the centerpiece: crop them large and sharp
- Include a BibTeX citation block at the bottom
- Keep it a single self-contained HTML file with relative image paths
