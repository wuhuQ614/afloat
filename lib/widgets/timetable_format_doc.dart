/// 课程表 JSON 格式说明弹窗（独立 widget，可被 EditTimetableDialog / 三点菜单复用）
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../theme_colors.dart' show AppColors;

class TimetableFormatDocDialog extends StatelessWidget {
  const TimetableFormatDocDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final isLight = c.isLight;
    return AlertDialog(
      // 实底不透明：文档页内容长、滚动频繁，半透明会让下层页面持续参与合成
      backgroundColor: c.cardSolid,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
      title: Row(children: [
        Icon(Icons.description_outlined, size: 20, color: c.primary),
        const SizedBox(width: 8),
        Text('课程表 JSON 格式（导入规范）',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
      ]),
      content: SizedBox(
        width: 560,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_kFormatIntro, style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.6)),
              _helpHead(c, '根字段', Icons.account_tree_outlined),
              _helpTable(c, ['字段', '必填', '说明'], _kRootFields),
              _helpHead(c, '课程字段（courses[]）', Icons.menu_book_outlined),
              _helpTable(c, ['字段', '必填', '说明'], _kCourseFields),
              _helpHead(c, 'weeks 周次写法', Icons.date_range_outlined),
              _helpTable(c, ['写法', '含义'], _kWeeksForms),
              _helpHead(c, '常见错误', Icons.warning_amber_rounded),
              _helpTable(c, ['错误', '结果'], _kCommonErrors),
              _helpHead(c, '功能实现原理', Icons.memory_rounded),
              _helpTable(c, ['环节', '实现'], _kPrinciples),
              _helpHead(c, '用 Agent 自动导入', Icons.auto_awesome_outlined),
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: isLight ? 0.07 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.primary.withValues(alpha: 0.3)),
                ),
                child: Text(_kAgentTip, style: TextStyle(fontSize: 12, color: c.textSecondary, height: 1.6)),
              ),
              _helpHead(c, 'Agent 工具提示词', Icons.construction_rounded),
              for (final t in _kAgentTools) _helpToolCard(c, t.$1, t.$2),
              _helpHead(c, '最小可工作示例', Icons.code_rounded),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isLight ? const Color(0xFFF6F7FA) : const Color(0xFF14151A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: SingleChildScrollView(
                  child: Text(_kTemplateJson,
                      style: TextStyle(fontSize: 11.5, fontFamily: 'Consolas', color: c.textSecondary, height: 1.5)),
                ),
              ),
            ]),
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: _formatDocText()));
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('已复制全部内容（含字段说明与示例）', style: TextStyle(fontSize: 13)),
              backgroundColor: AppColors.of(context).card,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
              margin: const EdgeInsets.all(16),
            ));
          },
          icon: const Icon(Icons.copy_all_rounded, size: 15),
          label: const Text('复制全部'),
          style: OutlinedButton.styleFrom(foregroundColor: c.textSecondary, side: BorderSide(color: c.border)),
        ),
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: _kTemplateJson));
            Navigator.pop(context);
          },
          icon: const Icon(Icons.copy_rounded, size: 15),
          label: const Text('复制示例'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context),
          style: FilledButton.styleFrom(backgroundColor: c.primary, foregroundColor: Colors.white),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

const String _kFormatIntro = '课程表完全由 JSON 文件决定：startDate（第 1 周周一）推算当前周次，'
    'periods（一天的节次时间分布）决定每节课的显示时间，courses 决定课程块。改 JSON 即可改整个课表。';

const List<List<String>> _kRootFields = [
  ['name', '否', '学期名，默认"我的课程表"'],
  ['startDate', '是', '第 1 周周一的日期，格式 yyyy-MM-dd'],
  ['totalWeeks', '否', '学期总周数；缺省按课程最大周次推算（至少 20）'],
  ['periods', '是', '一天的节次时间分布：[{index, start, end}, …]，课块显示时间完全由它决定'],
  ['courses', '是', '课程列表，可为空数组 []'],
];

const List<List<String>> _kCourseFields = [
  ['name', '是', '课程名'],
  ['day', '是', '星期：1=周一 … 7=周日'],
  ['startPeriod', '是', '当日第几节开始（对应 periods[].index）'],
  ['endPeriod', '是', '当日第几节结束（含）'],
  ['teacher', '否', '教师姓名'],
  ['room', '否', '教室 / 地点'],
  ['weeks', '否', '上课周次，见下方说明；缺省 = 每周都有'],
];

const List<List<String>> _kWeeksForms = [
  ['"1-16"', '第 1 至 16 周连续'],
  ['"1-8,10,12-16"', '逗号组合任意周次'],
  ['"all"', '每周都有'],
  ['[1,2,3]', '数组形式，等价"1,2,3"'],
];

const List<List<String>> _kCommonErrors = [
  ['缺 startDate', '解析失败——周次无法推算'],
  ['缺 periods 或为空', '解析失败——课程没有时间可显示'],
  ['day 不在 1~7', '格式错误'],
  ['时间不是 HH:mm（如 "8-30"）', '格式错误；"8:30" 缺前导 0 合法，推荐 08:30'],
];

const List<List<String>> _kPrinciples = [
  ['JSON 解析', '导入时由 TimetableData.parse 校验结构，字段缺失/格式错误直接报错并提示原因'],
  ['周次推算', 'startDate 所在周的周一为锚点 + 系统日期 → weekOf() 算出当前第几周，进入页面自动跳到本周'],
  ['节次时间轴', '左侧 1..20 节由 periods 决定起止时间（未定义只显示节次号）；课程块纵向位置/高度由 startPeriod~endPeriod 映射'],
  ['课程定位', 'courses 的 day 决定星期列（1~7 固定对应周一~周日），weeks 决定该课在哪些周显示；同天时间冲突自动分列'],
  ['实时联动', '系统时间落在某节区间 → 该课整块变绿"上课中"、下一节变红；跨天/跨周自动跟随刷新'],
];

const String _kAgentTip = '不需要手动写文件：在对话框中告诉 Agent"导入我的课表"，把课表文字或图片发过去，'
    'Agent 会按本规范自动生成 JSON，经过两道校验（机器校验 + 逐条复核）后导入（仅学习模式下可用）。';

const List<(String, String)> _kAgentTools = [
  ('import_timetable',
      '把用户提供的 JSON 课表解析并导入到本地。导入后整个应用会切到课程表模式，周视图立即按新数据显示。'
      'JSON 必须符合课程表 schema：name（学期名）+ startDate（第 1 周周一的 yyyy-MM-dd）+ periods（一整天的节次时间分布，'
      '每个含 index/start/end）+ courses（每门课含 day 1-7、startPeriod、endPeriod、name，可选 teacher/room/weeks）。'
      'weeks 支持 "1-16"、"1-8,10,12-16"、"all"、数字数组，缺省=全周。'
      '返回 {"ok":true, "name":"...", "totalWeeks":N, "courseCount":M, "firstDay":"..."} 或 {"ok":false,"reason":"格式错误详情"}。'
      '本工具仅在学习模式下生效（应用处于课程表模式时拒绝调用）。'),
  ('get_timetable_summary',
      '获取当前课程表（如果已导入）的摘要：学期名、开学日期、总周数、节次时间分布、课程总数与前几门示例。'
      '用于让 Agent 在导入前先确认应用当前是否有课表、在导入后向用户报告生效情况。本工具仅在学习模式下生效。'),
  ('validate_timetable',
      '第 1 道校验：干跑校验课表 JSON（只解析统计，不写入、不切模式）。'
      '检查：JSON 合法性、必填字段(startDate/periods/courses)、节次时间是否倒挂或重叠、'
      '课程是否引用了未定义的节次、周次是否超出 totalWeeks、同一天是否有节次冲突。'
      '返回 checks（各项 pass/warn）、统计（课程数/每日分布/最大周次/开学日星期）与 issues 问题清单。'
      '本工具仅在学习模式下生效。注意：调用它之后还必须做第 2 道校验——'
      '逐条对照用户原始课表核对课程名/星期/节次/周次/地点/教师是否完全一致，两道都通过后才可调用 import_timetable。'),
];

const String _kTemplateJson = '''{
  "name": "2025-2026 第1学期",
  "startDate": "2025-09-01",
  "periods": [
    {"index": 1, "start": "08:30", "end": "09:15"},
    {"index": 2, "start": "09:20", "end": "10:05"},
    {"index": 3, "start": "10:25", "end": "11:10"},
    {"index": 4, "start": "11:15", "end": "12:00"},
    {"index": 5, "start": "14:30", "end": "15:15"},
    {"index": 6, "start": "15:20", "end": "16:05"},
    {"index": 7, "start": "16:25", "end": "17:10"},
    {"index": 8, "start": "17:15", "end": "18:00"}
  ],
  "courses": [
    {"name": "人工智能导论", "teacher": "李教授", "room": "@校本部机大楼212", "day": 4, "startPeriod": 1, "endPeriod": 3, "weeks": "1-16"},
    {"name": "机械设计基础", "teacher": "张老师", "room": "@校本部机电大楼304", "day": 1, "startPeriod": 3, "endPeriod": 4, "weeks": "1-16"}
  ]
}''';

Widget _helpHead(AppColors c, String t, IconData icon) {
  return Padding(
    padding: const EdgeInsets.only(top: 10, bottom: 6),
    child: Row(children: [
      Icon(icon, size: 14, color: c.primary),
      const SizedBox(width: 5),
      Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.text)),
    ]),
  );
}

Widget _helpTable(AppColors c, List<String> headers, List<List<String>> rows) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: c.isLight ? const Color(0xFFF6F7FA) : const Color(0xFF14151A),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.border),
    ),
    child: Table(
      columnWidths: headers.length == 3
          ? const {0: FixedColumnWidth(92), 1: FixedColumnWidth(42), 2: FlexColumnWidth()}
          : const {0: FixedColumnWidth(118), 1: FlexColumnWidth()},
      border: TableBorder(horizontalInside: BorderSide(color: c.divider, width: 0.6)),
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(children: [
          for (final h in headers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Text(h, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.primary)),
            ),
        ]),
        for (final row in rows)
          TableRow(children: [
            for (var i = 0; i < row.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Text(row[i],
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400,
                        color: c.textSecondary)),
              ),
          ]),
      ],
    ),
  );
}

Widget _helpToolCard(AppColors c, String name, String description) {
  return Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: c.isLight ? const Color(0xFFF6F7FA) : const Color(0xFF14151A),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.border),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.build_rounded, size: 13, color: c.primary),
        const SizedBox(width: 5),
        Text(name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.primary, fontFamily: 'Consolas')),
      ]),
      const SizedBox(height: 5),
      Text(description, style: TextStyle(fontSize: 11.5, color: c.textSecondary, height: 1.55)),
    ]),
  );
}

String _formatDocText() {
  String table(String title, List<String> headers, List<List<String>> rows) {
    final b = StringBuffer('\n【$title】\n');
    b.writeln(headers.join(' | '));
    for (final r in rows) {
      b.writeln(r.join(' | '));
    }
    return b.toString();
  }

  final b = StringBuffer('课程表 JSON 格式（导入规范）\n\n$_kFormatIntro\n');
  b.write(table('根字段', ['字段', '必填', '说明'], _kRootFields));
  b.write(table('课程字段（courses[]）', ['字段', '必填', '说明'], _kCourseFields));
  b.write(table('weeks 周次写法', ['写法', '含义'], _kWeeksForms));
  b.write(table('常见错误', ['错误', '结果'], _kCommonErrors));
  b.write(table('功能实现原理', ['环节', '实现'], _kPrinciples));
  b.write('\n【用 Agent 自动导入】\n$_kAgentTip\n');
  b.write('\n【Agent 工具提示词】\n');
  for (final t in _kAgentTools) {
    b.writeln('· ${t.$1}：${t.$2}\n');
  }
  b.write('\n【最小可工作示例】\n$_kTemplateJson\n');
  return b.toString();
}
