# AFloat Web（网页版）

Flutter 桌面版 AFloat 的 TypeScript 网页复刻：玻璃拟态 UI + AI 对话 + 二进制词库查询。

## 运行

```bash
npm install
npm run dev      # 开发（http://localhost:5173）
npm run build    # 构建到 dist/
npm run preview  # 预览构建产物
```

## 已复刻

- 玻璃拟态外壳（左重右淡光斑背景 + 呼吸光带 + 侧边栏 + 右侧 AI 对话面板）
- AI 对话：OpenAI 兼容流式（SSE）、markdown 排版、代码卡片（复制/下载/新窗口运行）、
  用户消息复制、会话快照与历史抽屉（置顶/删除）、上下文占用圆环、Max 模式开关、专注全屏
- 单词查询：与桌面版共用 dict.bin / zsb-dict.bin 二进制词库（TS 解析同格式）
- 学习页：题型选择/难度/题量/自定义要求，生成题目输出到对话

## 说明

- AI 能力需在 ⚙ 设置中填入 OpenAI 兼容 API；浏览器直连受服务商 CORS 策略限制
- 词库文件位于 public/（dict.bin 3MB，与桌面版 assets 同源）
