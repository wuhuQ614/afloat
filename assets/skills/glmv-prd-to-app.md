---
name: glmv-prd-to-app
description: 根据 PRD 文档和 UI 原型图构建完整、可部署的全栈 Web 应用。当用户说"根据PRD做应用"、"按原型图实现"、"把这个产品设计做出来"时使用。
category: 智谱 GLM
source: zai-org/glmv-prd-to-app
---

# GLM-V PRD-to-App: Full-Stack Application Builder

Build a complete, deployed web application from PRD + prototypes + resources. The result must be fully reproducible via a single `bash /workspace/start.sh`.

**Language**: Respond in the same language the user uses. Code comments should match.

---

## Phase 0: Material Discovery & Analysis

Before anything else, understand what you're working with.

### 0a. Locate all inputs

```
/workspace/prd.md              ← Product requirement document
/workspace/prototypes/*.jpg    ← UI prototype images (the visual truth)
/workspace/resources/**/*      ← Images, videos, icons, and other assets
```

If the materials are in a different location, adapt accordingly. Read the PRD fully.

### 0b. Deep prototype analysis

For **every** prototype image:

1. **Read each image** — you are multimodal, examine them directly.
2. For each image, document:
   * **Page identity**: which page/view this represents
   * **Layout structure**: header, sidebar, main content, footer, modals
   * **Component inventory**: every button, form, card, table, list, nav element
   * **Content inventory**: all visible text, numbers, labels, placeholder content
   * **Color extraction**: primary, secondary, accent, background, text colors (hex values)
   * **Typography**: font sizes, weights, hierarchy observed
   * **Interactive states**: hover effects, active tabs, selected items, toggles
   * **Data patterns**: what data populates lists/tables/cards — this drives seed data
3. Build a **page map** showing navigation flow between prototype pages.

### 0c. Resource inventory

List all files in `/workspace/resources/` and map each to where it appears in the prototypes. Every resource file must be used in the final application where relevant.

---

## Phase 1: System Design Document

Produce a comprehensive design document at `/workspace/docs/design.md`.

### 1a. Data Model

For each entity, specify:
* Table/collection name
* All fields with types, constraints, defaults
* Relationships (foreign keys)
* Seed data plan (from prototype data patterns)

### 1b. API Design

For each endpoint: method, path, request/response schema, error codes, auth requirement.

### 1c. Component Architecture

* Component tree per page
* Shared/reusable components
* State management strategy
* Routing plan

---

## Phase 2: Backend Implementation

1. Initialize the project (choose stack per PRD; default: Node.js + Express or Python + FastAPI, SQLite for persistence)
2. Implement data models & migrations
3. Implement all API endpoints
4. Seed the database with realistic data matching prototype content
5. Write tests for critical paths

---

## Phase 3: Frontend Implementation

1. Build layout shells for every page in the page map
2. Implement each component per prototype analysis:
   * **Pixel-faithful colors**: use the exact hex values extracted in Phase 0
   * **Typography hierarchy**: match observed sizes/weights
   * **Spacing & layout**: match prototype proportions
3. Wire up API calls
4. Implement all interactive states (loading, empty, error, hover, active)

---

## Phase 4: Integration & Polish

1. End-to-end flow testing: every page reachable, every button functional
2. Responsive behavior (desktop first per prototypes; degrade gracefully)
3. Error handling on all API failures
4. Loading states on all async operations

---

## Phase 5: Deployment Package

Create `/workspace/start.sh` that:

```bash
#!/bin/bash
# Installs deps, seeds DB if needed, starts server, opens browser
set -e
# ... install steps ...
# ... migrate/seed ...
# ... start ...
```

The app must be fully reproducible: clone → `bash start.sh` → working app.

---

## Quality Checklist

- [ ] Every prototype page implemented and reachable
- [ ] Colors match extracted hex values
- [ ] All CRUD operations work end-to-end
- [ ] Seed data matches prototype content patterns
- [ ] `start.sh` reproduces the app from clean state
- [ ] No placeholder/TODO text visible in UI
- [ ] All resources from /workspace/resources/ used appropriately
