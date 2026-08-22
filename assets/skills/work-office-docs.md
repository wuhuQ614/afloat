---
name: work-office-docs
description: 在 Windows 上生成真正的 Word(.docx)/Excel(.xlsx)/PPT(.pptx) 文件（PowerShell COM 自动化，未装 Office 时降级 CSV/HTML/Markdown）。当用户要求做文档、表格、PPT、报告文件时使用。
category: 办公效率
source: builtin
---

# 办公文档工厂

在用户的 Windows 电脑上生成可直接使用的办公文件。

## 触发时机

用户要求「做个 Word / 做个 PPT / 整理成 Excel 表格 / 生成 PDF 报告 / 把内容做成文档」等一切需要产出**真实文件**的场景。

## 工作流

1. **锁定交付物**：格式、文件名、保存位置、大致结构。用户没说保存位置时默认存到工作区根目录并在完成后告知路径；用户要求「放桌面」时用脚本取真实桌面路径（见下）。
2. **先写内容文件**：用 `write_file` 把正文/表格数据写成 UTF-8 文本或 CSV（中文内容绝不能直接写进 .ps1）。
3. **写生成脚本**：用 `write_file` 写 ASCII-only 的 .ps1 脚本；用 `bash` 执行：
   `powershell -NoProfile -ExecutionPolicy Bypass -File gen_doc.ps1`
4. **验证交付**：脚本输出生成的完整路径 → `read_file` 或脚本自检确认文件存在且非空 → 回复中给出路径 → 用 `operate_computer`(`open_file`) 帮用户打开。

## Word (.docx) —— COM 自动化

```powershell
$word = New-Object -ComObject Word.Application
$word.Visible = $false
$doc = $word.Documents.Add()
$sel = $word.Selection
# 中文正文从 UTF-8 文件读入，逐段写入
$lines = Get-Content -Encoding UTF8 .\content.txt
foreach ($line in $lines) {
  if ($line -match '^# ') { $sel.Style = 'Heading 1'; }
  elseif ($line -match '^## ') { $sel.Style = 'Heading 2'; }
  else { $sel.Style = 'Normal'; }
  $sel.TypeText($line); $sel.TypeParagraph()
}
$out = Join-Path (Get-Location) 'output.docx'
$doc.SaveAs([ref]$out, [ref]16)   # 16 = wdFormatDocumentDefault
$doc.Close(); $word.Quit()
Write-Output "DONE $out"
```

## Excel (.xlsx) —— COM 自动化

```powershell
$data = Import-Csv -Encoding UTF8 .\data.csv      # 数据源必须是 UTF-8 CSV
$excel = New-Object -ComObject Excel.Application
$excel.Visible = $false
$wb = $excel.Workbooks.Add()
$ws = $wb.Worksheets.Item(1)
# 表头
$cols = ($data | Get-Member -MemberType NoteProperty).Name
for ($c = 0; $c -lt $cols.Count; $c++) { $ws.Cells.Item(1, $c + 1) = $cols[$c] }
# 数据行
$r = 2
foreach ($row in $data) {
  for ($c = 0; $c -lt $cols.Count; $c++) { $ws.Cells.Item($r, $c + 1) = $row.$($cols[$c]) }
  $r++
}
$ws.Columns.AutoFit() | Out-Null
$out = Join-Path (Get-Location) 'output.xlsx'
$wb.SaveAs($out); $wb.Close(); $excel.Quit()
Write-Output "DONE $out"
```

## PPT (.pptx) —— COM 自动化

```powershell
$ppt = New-Object -ComObject PowerPoint.Application
$presentation = $ppt.Presentations.Add()
# 每张幻灯片：标题 + 正文（大纲从 UTF-8 大纲文件读取）
$slide = $presentation.Slides.Add(1, 2)            # 2 = ppLayoutText
$slide.Shapes.Title.TextFrame.TextRange.Text = '标题'
$slide.Shapes.Item(2).TextFrame.TextRange.Text = '要点'
$out = Join-Path (Get-Location) 'output.pptx'
$presentation.SaveAs($out); $presentation.Close(); $ppt.Quit()
Write-Output "DONE $out"
```

## 用户指定「放桌面」

```powershell
$desktop = [Environment]::GetFolderPath('Desktop')
$out = Join-Path $desktop 'output.docx'
```

注意：桌面通常在工作区之外，COM 脚本写它不受文件工具白名单限制（脚本进程自己落盘），但必须向用户如实说明保存位置。

## 未装 Office 的降级链

按顺序探测并降级，并向用户说明选择了哪种：

1. COM 可用（`New-Object -ComObject Word.Application` 不抛异常）→ 真正的 docx/xlsx/pptx；
2. 失败 → **表格类**给 CSV（Excel/WPS 双击即开）；**文档/PPT 类**给 HTML（自带样式，浏览器打开即可打印成 PDF）或 Markdown；
3. 用户机器装了 WPS 时 COM ProgID 可能仍可用（`KWPS.Application` / `KET.Application` / `KWPP.Application`），可作第二优先级尝试。

## 硬性约束

- bash 默认 30 秒超时：Office COM 首次启动可能慢，执行前把 `timeout_ms` 提到 60000；更长的批量任务改用 `run_background_job` + `job_output` 轮询。
- COM 对象用完必须 Quit() 并释放，否则残留 WINWORD.EXE/EXCEL.EXE 进程占用文件锁。
- 同名文件已存在时 SaveAs 会失败：脚本里先 `Remove-Item -ErrorAction SilentlyContinue` 或加时间戳后缀。
- 每轮 bash 都是全新 shell：不要依赖上一次的 cd / 变量；脚本内一律用绝对或工作区相对路径自行解析。
