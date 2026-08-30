---
name: api-preset-config
description: 一键配置应用内 API 预设：把用户提供的订阅地址、API Key、模型名写入应用配置。当用户要求配置 API、填写订阅地址/Key/模型、切换 API 服务商时使用。
category: 开发工具
source: builtin
---

# API 预设配置

把用户提供的订阅地址（Base URL）、API Key、模型名自动写入应用配置，立即生效。

## 触发时机

- 「帮我配置 API」「填一下 Key」「设置模型」「配置订阅地址」
- 用户给出订阅地址（如 https://api.example.com/v1）+ Key + 模型名，要求写入应用
- 用户要切换或新增一套 API 供应渠道（预设）

## 工作流

1. **收集三要素**（缺哪个问哪个，用 `ask_user_question` 一次问完）：
   - `url` 订阅地址：OpenAI 兼容的 API 基础地址（通常以 `/v1` 结尾，如 `https://api.example.com/v1`）
   - `key` API Key：用户订阅获得的密钥字符串
   - `model` 模型名：用户要使用的模型（可带供应商前缀，如 `deepseek-chat`、`glm-4-flash`）；缺省保留当前模型

2. **调用工具** `config_api_preset`：
   - `url`、`key` 必填；`model`、`name`（预设名称）、`applyToChat`（是否同时应用到对话助手）可选。
   - 用户给的是完整接口地址（以 `/chat/completions` 结尾）时，工具会自动识别为完整地址，无需手动处理。
   - 用户说明「对话助手也用这个」或希望 AI 用新配置继续聊天时，传 `applyToChat: true`。

3. **确认结果**：配置成功后告知用户已写入应用（地址、模型），并说明可在「设置」的多配置库中查看与切换。

## 注意

- **Key 是敏感信息**：只写入配置，不要在回复中回显完整 Key（可打码展示末尾 4 位）。
- 订阅地址是 API 接口地址，不是需要登录输入 Key 的网页控制台地址。
- 本技能只做写入配置，不做联网连通性测试；用户明确要求验证时再考虑用目标服务发一次最小请求。