---
name: work-data-analysis
description: 对 CSV/Excel/日志/文本数据做清洗、统计与结论分析，产出数据报告文件。当用户给出一份数据要求分析、统计、找规律时使用。
category: 办公效率
source: builtin
---

# 数据分析

用真实计算（不是目测）从用户数据里得出可靠结论。

## 触发时机

- 「分析一下这个表」「这份数据有什么规律」「统计一下」「帮我看看这个 CSV/Excel」

## 工作流

### 1. 摸清数据（先看后算）
- `list_dir` 确认文件位置；`read_file` 读前 30 行看结构（分隔符、表头、编码乱码与否）。
- Excel (.xlsx) 先转 CSV 再分析：
  `powershell -NoProfile -Command "$e=New-Object -ComObject Excel.Application; $wb=$e.Workbooks.Open('<绝对路径>'); $wb.Worksheets.Item(1).SaveAs('<工作区>\data.csv',62); $wb.Close(); $e.Quit()"`（62 = xlCSVUTF8）

### 2. 统计计算（PowerShell，禁止凭感觉报数）
把统计逻辑写成 .ps1（ASCII-only）再执行，典型模式：

```powershell
$rows = Import-Csv .\data.csv -Encoding UTF8
"总行数: $($rows.Count)"
# 分组聚合
$rows | Group-Object category | ForEach-Object {
  $amt = ($_.Group | Measure-Object amount -Sum).Sum
  "{0}: n={1}, sum={2}" -f $_.Name, $_.Count, $amt
}
# 数值列概览
$m = $rows | Measure-Object score -Min -Max -Average
"min=$($m.Minimum) max=$($m.Maximum) avg=$([math]::Round($m.Average,2))"
```

复杂统计（回归、相关性）超出 PowerShell 舒适区时：导出干净 CSV 后向用户说明局限，或生成可直接粘贴到 Excel 透视表的步骤说明。

### 3. 交叉验证
- 关键数字换一种算法复算一遍（如总数用两种分组路径核对）。
- 异常值（空值、重复行、离群点）单独列出并说明处理方式——不许静默丢弃。

### 4. 产出报告 `analysis_report.md`
```markdown
# 数据分析：<数据名>
## 一句话结论
## 数据概况（行数/字段/时间范围/缺失情况）
## 核心发现（每条 = 结论 + 支撑数字）
1. ...
## 异常与数据质量问题
## 建议行动
## 附录：关键统计明细表
```

### 5. 交付
回复中给出结论摘要（用户最关心的一句话结论放最前）+ 文件路径；需要图表时生成内嵌 SVG/HTML 图表的报告页并用 `operate_computer` 打开。

## 硬性约束

- 所有数字必须来自工具的真实输出；报告里的每个数字都能追溯到某次命令结果。
- bash 默认 30 秒超时：大数据集（>10 万行）改用 `run_background_job` 跑批 + `job_output` 取结果。
- 用户问的是业务问题（如「为什么销量跌了」）：先给数据侧能回答的部分，明确指出哪些原因需要数据之外的验证。
