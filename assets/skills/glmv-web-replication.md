---
name: glmv-web-replication
description: 公共网站前端视觉复现（仅限已获授权的站点）：递归探索目标站的公开页面，复刻其前端视觉呈现。当用户说"复刻这个网站"、"把这个页面的样式抄下来"时使用。
category: 智谱 GLM
source: zai-org/glmv-web-replication
---

# Website Frontend Visual Replication

## Prerequisites

This workflow depends on either Playwright MCP or the agent-browser skill. As long as at least one of them is installed and available, the workflow can run normally. If neither is available in your environment, remind the user to install one.

Before proceeding, the agent **MUST** ask the user:

> "Do you own this website, or do you have explicit written permission from the owner to replicate it? Unauthorized replication may violate copyright, terms of service, or applicable law."

* If the user confirms authorization → proceed.
* If the user cannot confirm → **STOP**. Do not proceed with replication. Suggest alternatives (e.g., building an original design inspired by general layout patterns).

## Scope & Limitations

**This skill replicates FRONTEND VISUAL PRESENTATION only.**

| Included                           | NOT Included                       |
| ---------------------------------- | ---------------------------------- |
| Page layout & visual styling       | Backend / server-side logic        |
| Navigation structure               | Databases & data stores            |
| Publicly visible text & images     | Authentication systems / sessions  |
| CSS/design tokens                  | API business logic                 |
| Client-side interaction patterns   | Non-public or behind-login content |
| Static asset files (images, fonts) | Credentials, secrets, or API keys  |

**Data handling rules:**

1. **Never scrape behind a login wall.** Only capture publicly accessible pages.
2. **Never collect or store credentials**, API keys, session tokens, or personal data (PII).
3. **Never reproduce copyrighted content verbatim** (articles, copy text) unless the user holds rights.
4. **Respect robots.txt and rate limits.** If the site signals crawl restrictions, honor them.
5. **Output is for reference & mockup purposes** unless the user has confirmed full rights.

## Core Idea

1. Recursively explore every **public** page of the target website.
2. For each page, capture: rendered screenshot, DOM structure, computed styles, extracted design tokens (colors, fonts, spacing).
3. Rebuild the pages as static HTML/CSS with locally-saved assets.
4. Verify visual fidelity by side-by-side comparison.

## Workflow

### Phase 1 — Authorization Check

Ask the user for ownership/permission confirmation (see Prerequisites). Stop if not confirmed.

### Phase 2 — Site Exploration

* Start from the root URL; follow internal links recursively.
* Respect robots.txt; skip non-public pages.
* Limit depth and page count to a reasonable scope (confirm with user if site is large).
* Record the page map: URL → title → template type (home / article / listing / about...).

### Phase 3 — Asset & Style Extraction

For each page:

* Extract design tokens: color palette, typography (font families, sizes, weights), spacing rhythm, border radii, shadows.
* Download static assets (images, fonts) to local folders.
* Capture the DOM structure of key components (header, nav, footer, cards, buttons).

### Phase 4 — Rebuild

* Create static HTML/CSS per page, mirroring extracted tokens and structure.
* Use locally-saved assets with relative paths.
* Implement client-side interactions with vanilla JS where they're part of the visual experience (menus, accordions, carousels).

### Phase 5 — Fidelity Verification

* Screenshot your rebuilt page next to the original.
* Compare layout, colors, typography, spacing.
* Iterate on discrepancies until visual fidelity is achieved.

## Output Structure

```
replica/
├── index.html
├── pages/           ← replicated pages
├── assets/
│   ├── css/
│   ├── img/
│   └── fonts/
└── README.md        ← scope, authorization note, fidelity report
```
