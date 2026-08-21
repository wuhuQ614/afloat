---
name: alipay-aipay
description: 支付宝 AI 付（AI Pay）技能启动器：确定本轮使用的 Skill 版本并路由到运行时入口。当用户要求通过支付宝完成 AI 付款、扫码支付、发起交易时使用。
category: 生活服务
source: Alipay/alipay-aipay
---

# 支付宝 AI 付 Skill 启动器

本文件只负责在加载业务规则前确定本轮实际使用的 Skill 版本。禁止在完成启动协议前读取 `references/runtime-entry.md`、任一 flow、模块、消息目录或业务脚本。

## 前置版本检查

本次 Agent 对话首次使用 `alipay-aipay` 时，先把本文件所在目录解析为规范化绝对路径 `<SKILL_DIR>`，记录一次性事实 `ALIPAY_AIPAY_SELF_UPDATE_CHECKED=true`，再执行以下单条命令。`<SKILL_DIR>` 是执行时替换的路径占位符；禁止用 shell 变量赋值、命令替换或依赖特定 shell：

```bash
node "<SKILL_DIR>/references/normal/scripts/runtime.mjs" self-update check --skill-dir "<SKILL_DIR>"
```

`SKILL_DIR` 必须绑定刚触发且正在执行本命令的 Skill 规范化绝对路径，不得换成 Agent 启动目录、用户项目目录、用户 Home、npm 包源码根或另一份 Skill 副本。`VERSION` 缺失/非法或 `references/runtime-entry.md` 缺失时由本命令尝试精确修复；命令失败或 marker 无法唯一解析时按 `SELF_UPDATE:CHECK_FAILED`。

stderr 只允许出现以下一个内部终态；不得向用户展示 marker 或 npm/npx 原始输出：

* `SELF_UPDATE:UPDATED=<合法 SemVer>`：当前 Skill 目录已原子切换到新版。
* `SELF_UPDATE:CURRENT=<合法 SemVer>`：继续当前版本。
* `SELF_UPDATE:RETRY_WITH_NETWORK`：registry 或安装阶段网络不可达；可申请联网后原样重试本命令一次。
* `SELF_UPDATE:SKIPPED_NETWORK_RESTRICTED|CHECK_FAILED|INSTALL_FAILED|VERIFY_FAILED`：静默继续当前可用版本，不重试、不申请权限。

除 `RETRY_WITH_NETWORK` 的一次原样重试外，只完整读取同一 `SKILL_DIR` 的 `references/runtime-entry.md`，在当前上下文记录 `ALIPAY_AIPAY_RUNTIME_ENTRY_LOADED=true` 和规范化路径，再按原请求路由。`UPDATED` 后先废弃旧 loaded 事实，禁止继续读取更新前版本的任何业务文档；其他终态同样不再读取本启动器或 `self-update.md` 补充规则。

同一对话后续确认、补材料、候选选择、恢复、中断继续、重复触发和 Full Process 衔接，两项事实存在、路径未变且入口规则仍在时，跳过版本检查和入口重读。仅 `UPDATED`、路径变化或上下文压缩导致规则不可用时重读并刷新；事实不落盘。

## 环境不可用时

若当前环境未安装该技能的运行时（runtime.mjs 不存在或 node 不可用），如实告知用户：AI 付技能需要完整技能包（含 references/runtime-entry.md 与 scripts），当前环境仅内置了启动器说明，无法直接发起支付宝交易。引导用户通过支付宝 App 扫码完成支付。
