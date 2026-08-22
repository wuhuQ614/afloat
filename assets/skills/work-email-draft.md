---
name: work-email-draft
description: 撰写专业英文商务邮件（求职、跟进、请假、投诉、道歉、合作邀约等），中英对照+语气分级。当用户要求写英文邮件、回复外方邮件时使用。
category: 办公效率
source: builtin
---

# 英文商务邮件助手

写出可以直接复制发送的专业英文邮件，并帮助用户理解每处措辞。

## 触发时机

- 「帮我写一封英文邮件」「回复这封邮件」「用英文跟客户说…」
- 用户粘贴了一封英文来信，要求起草回复
- 求职信、感谢信、催促回复、会议改期等涉外沟通

## 工作流

1. **补齐关键信息**（缺什么问什么，用 `ask_user_question` 一次性问完，最多 4 问）：
   - 收件人是谁、与你的关系（上级/同事/客户/学校/陌生人）
   - 目的（请求/拒绝/道歉/催办/通知）与期望对方做什么
   - 语气偏好：formal / neutral / friendly
   - 是否有截止日期或附件
2. **产出三件套**（直接在回复中给出 + 用 `write_file` 落盘为 `email_draft.md`）：
   - **英文正文**：主题行（Subject）+ 称呼 + 正文 + 结束语 + 署名
   - **中文对照翻译**：逐段对照，方便用户确认语义
   - **措辞要点**：3-5 条「为什么这样写」——关键短语的功能（softener、hedging、call to action）与可替换的更强硬/更委婉说法
3. **用户要求存档或继续编辑** → 文件已落盘，可用 `edit_file` 精确修改；需要 Word 版走 work-office-docs 技能。

## 结构模板

```
Subject: <动宾短语，≤10 词，含关键信息如日期/单号>

Dear Mr./Ms. <姓>,

<开头一句说明来意：I am writing to ... / Thank you for your email about ...>

<背景 1-2 句 → 核心诉求 1-2 句 → 具体行动与时间点>

<结尾礼貌句：Please let me know if ... / I look forward to hearing from you.>

Best regards,
<姓名>
<职务/单位/联系方式（可选）>
```

## 常见场景速查

| 场景 | 开头句式 | 关键技巧 |
|---|---|---|
| 求职/自荐 | I am writing to express my interest in ... | 首段点明职位来源；一段一个卖点 |
| 催促回复 | I am following up on my email dated ... | 不指责；给对方台阶（I understand you are busy） |
| 请假 | I would like to request leave from X to Y ... | 说明交接安排，弱化原因细节 |
| 投诉 | I am writing to report an issue with ... | 陈述事实+订单号；明确希望补偿方案 |
| 道歉 | Thank you for your patience regarding ... | 承认影响→补救措施→防再发 |
| 改期 | Would it be possible to reschedule our meeting ... | 主动给出 2-3 个备选时段 |

## 质量标准

- 语气词分级准确：请求用 could / would；强硬诉求用 must / by <date>；委婉拒绝加 unfortunately / regrettably
- 避免 Chinglish：不写 "I very want to..."；中式客套（"Sorry to trouble you"）改为 "Thank you for your time"
- 一件事一封邮件；段落 ≤4 行；全文 ≤180 词（除非用户要求详述）
- 时态与敬语一致；收件人姓名拼写原样保留来信中的写法
