/// BMI 计算页面：一比一复刻参考项目 BmiTab.jsx。
///
/// 功能：
/// - 首页：身高/体重输入 → 计算 BMI（体重kg / (身高m)²），结果卡 + 分类徽章
/// - 档案：多档案管理（新建/切换），当前档案标签
/// - 记录：柱状图（最近 12 次，最新一根紫色 #7c3aed）+ 记录列表
/// - 更多：自动保存开关、导出数据、导入数据
///
/// BMI 分类（对齐参考项目 bmiCategory/bmiColor）：
/// <18.5 偏瘦 #60a5fa | <24 正常 #34d399 | <28 超重 #f59e0b | ≥28 肥胖 #ef4444
/// 持久化键 bmi-app-profiles-v1（与参考项目一致）。
library;

import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 简单日期格式化（MM-dd HH:mm:ss / MM-dd HH:mm），避免引入 intl 依赖
String _fmt(DateTime d, {bool withSeconds = true}) {
  String two(int v) => v.toString().padLeft(2, '0');
  final base = '${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  return withSeconds ? '$base:${two(d.second)}' : base;
}

const String _kStorageKey = 'bmi-app-profiles-v1';
const String _kDefaultProfileName = '默认档案';

String _bmiCategory(double bmi) {
  if (bmi < 18.5) return '偏瘦';
  if (bmi < 24) return '正常';
  if (bmi < 28) return '超重';
  return '肥胖';
}

Color _bmiColor(double bmi) {
  if (bmi < 18.5) return const Color(0xFF60A5FA);
  if (bmi < 24) return const Color(0xFF34D399);
  if (bmi < 28) return const Color(0xFFF59E0B);
  return const Color(0xFFEF4444);
}

class _BmiRecord {
  final String id;
  final double height;
  final double weight;
  final double bmi;
  final String category;
  final DateTime computedAt;
  final DateTime addedAt;

  _BmiRecord({
    required this.id,
    required this.height,
    required this.weight,
    required this.bmi,
    required this.category,
    required this.computedAt,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? computedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'height': height,
        'weight': weight,
        'bmi': bmi,
        'category': category,
        'computedAt': computedAt.toIso8601String(),
        'addedAt': addedAt.toIso8601String(),
      };

  static _BmiRecord fromJson(Map<String, dynamic> j) => _BmiRecord(
        id: (j['id'] ?? '').toString(),
        height: (j['height'] as num?)?.toDouble() ?? 0,
        weight: (j['weight'] as num?)?.toDouble() ?? 0,
        bmi: (j['bmi'] as num?)?.toDouble() ?? 0,
        category: (j['category'] ?? '').toString(),
        computedAt: DateTime.tryParse((j['computedAt'] ?? '').toString()) ?? DateTime.now(),
        addedAt: DateTime.tryParse((j['addedAt'] ?? '').toString()) ?? DateTime.now(),
      );
}

class _BmiProfile {
  final String id;
  final String name;
  final List<_BmiRecord> records;
  final DateTime createdAt;

  _BmiProfile({required this.id, required this.name, List<_BmiRecord>? records, DateTime? createdAt})
      : records = records ?? [],
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'records': records.map((r) => r.toJson()).toList(),
        'createdAt': createdAt.toIso8601String(),
      };

  static _BmiProfile fromJson(Map<String, dynamic> j) {
    final rawRecords = (j['records'] as List?) ?? [];
    // 去重：修复旧数据中的重复 record.id（对齐参考项目 loadProfiles）
    final seen = <String>{};
    final records = <_BmiRecord>[];
    for (final r in rawRecords) {
      if (r is Map) {
        final rec = _BmiRecord.fromJson(r.cast<String, dynamic>());
        if (!seen.contains(rec.id)) {
          seen.add(rec.id);
          records.add(rec);
        }
      }
    }
    return _BmiProfile(
      id: (j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      records: records,
      createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()) ?? DateTime.now(),
    );
  }
}

String _uid() =>
    '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${DateTime.now().microsecond.toRadixString(36)}';

class BmiTabPage extends StatefulWidget {
  final VoidCallback? onBack;
  const BmiTabPage({super.key, this.onBack});

  @override
  State<BmiTabPage> createState() => _BmiTabPageState();
}

class _BmiTabPageState extends State<BmiTabPage> {
  List<_BmiProfile> _profiles = [];
  String _activeProfileId = '';
  final TextEditingController _newProfileCtrl = TextEditingController();
  final TextEditingController _heightCtrl = TextEditingController(text: '170');
  final TextEditingController _weightCtrl = TextEditingController(text: '60');
  _BmiRecord? _lastResult;
  String _activeTab = 'home';
  bool _autoSave = false;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void dispose() {
    _newProfileCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kStorageKey);
      var loaded = <_BmiProfile>[];
      if (raw != null && raw.isNotEmpty) {
        final parsed = jsonDecode(raw);
        if (parsed is List) {
          loaded = parsed
              .whereType<Map>()
              .map((p) => _BmiProfile.fromJson(p.cast<String, dynamic>()))
              .toList();
        }
      }
      if (!mounted) return;
      if (loaded.isEmpty) {
        final def = _BmiProfile(id: _uid(), name: _kDefaultProfileName);
        setState(() {
          _profiles = [def];
          _activeProfileId = def.id;
        });
      } else {
        setState(() {
          _profiles = loaded;
          _activeProfileId = loaded.first.id;
        });
      }
    } catch (_) {
      if (!mounted) return;
      final def = _BmiProfile(id: _uid(), name: _kDefaultProfileName);
      setState(() {
        _profiles = [def];
        _activeProfileId = def.id;
      });
    }
  }

  Future<void> _saveProfiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kStorageKey, jsonEncode(_profiles.map((p) => p.toJson()).toList()));
    } catch (_) {}
  }

  _BmiProfile? get _activeProfile {
    for (final p in _profiles) {
      if (p.id == _activeProfileId) return p;
    }
    return null;
  }

  void _createProfile() {
    final name = _newProfileCtrl.text.trim();
    if (name.isEmpty) return;
    final profile = _BmiProfile(id: _uid(), name: name);
    setState(() {
      _profiles.insert(0, profile);
      _activeProfileId = profile.id;
      _newProfileCtrl.clear();
      _activeTab = 'profiles';
    });
    _saveProfiles();
  }

  String _ensureActiveProfile() {
    if (_activeProfileId.isNotEmpty) return _activeProfileId;
    final fallback = _BmiProfile(id: _uid(), name: _kDefaultProfileName);
    setState(() {
      _profiles.insert(0, fallback);
      _activeProfileId = fallback.id;
    });
    return fallback.id;
  }

  void _addRecordToProfile(_BmiRecord record) {
    final targetId = _ensureActiveProfile();
    setState(() {
      for (var i = 0; i < _profiles.length; i++) {
        if (_profiles[i].id == targetId) {
          final p = _profiles[i];
          _profiles[i] = _BmiProfile(
            id: p.id,
            name: p.name,
            records: [record, ...p.records],
            createdAt: p.createdAt,
          );
        }
      }
    });
    _saveProfiles();
  }

  void _calculateBmi() {
    final h = double.tryParse(_heightCtrl.text.trim());
    final w = double.tryParse(_weightCtrl.text.trim());
    if (h == null || w == null || h <= 0 || w <= 0) return;
    final bmi = w / ((h / 100) * (h / 100));
    final result = _BmiRecord(
      id: _uid(),
      height: h,
      weight: w,
      bmi: bmi,
      category: _bmiCategory(bmi),
      computedAt: DateTime.now(),
    );
    setState(() => _lastResult = result);
    if (_autoSave) {
      _addRecordToProfile(result);
    }
  }

  void _addToProfile() {
    final result = _lastResult;
    if (result == null) return;
    _addRecordToProfile(result);
    setState(() => _activeTab = 'history');
  }

  /// 导出数据：写 bmi-data.json 到下载目录（桌面端适配参考项目的浏览器下载）
  Future<void> _exportData() async {
    try {
      final data = const JsonEncoder.withIndent('  ')
          .convert(_profiles.map((p) => p.toJson()).toList());
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}bmi-data.json');
      await file.writeAsString(data, encoding: utf8);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导出到 ${file.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导出失败：$e')));
      }
    }
  }

  /// 导入数据：文件选择器选 json（桌面端适配参考项目的 file input）
  Future<void> _importData() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      final file = result?.files.first;
      if (file == null || file.bytes == null) return;
      final parsed = jsonDecode(utf8.decode(file.bytes!));
      if (parsed is List) {
        final profiles = parsed
            .whereType<Map>()
            .map((p) => _BmiProfile.fromJson(p.cast<String, dynamic>()))
            .toList();
        setState(() {
          _profiles = profiles;
          if (profiles.isNotEmpty) _activeProfileId = profiles.first.id;
        });
        await _saveProfiles();
      }
    } catch (_) {}
  }

  // ==================== UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 448), // max-w-md
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: _backButton(),
                ),
                Expanded(child: _buildTabContent()),
                _buildBottomTabBar(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _backButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton(
        onPressed: widget.onBack,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          minimumSize: const Size(0, 32),
        ),
        child: const Text('← 返回', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_activeTab) {
      case 'profiles':
        return _buildProfilesTab();
      case 'history':
        return _buildHistoryTab();
      case 'settings':
        return _buildSettingsTab();
      default:
        return _buildHomeTab();
    }
  }

  // ===== 首页 =====
  Widget _buildHomeTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _shellCard(
          padding: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('BMI 计算',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 16),
              _numberInput(_heightCtrl, '身高 cm'),
              const SizedBox(height: 12),
              _numberInput(_weightCtrl, '体重 kg'),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _calculateBmi,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4F46E5),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFC7D2FE),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text('计算 BMI',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _lastResult == null ? null : _addToProfile,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      alignment: Alignment.center,
                      child: Opacity(
                        opacity: _lastResult == null ? 0.4 : 1,
                        child: const Text('添加到当前档案',
                            style: TextStyle(fontWeight: FontWeight.w500, color: Color(0xFF0F172A))),
                      ),
                    ),
                  ),
                ),
              ]),
              if (_activeProfile != null) ...[
                const SizedBox(height: 8),
                Center(
                  child: Text('当前档案：${_activeProfile!.name}',
                      style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                ),
              ],
            ],
          ),
        ),
        if (_lastResult != null) ...[
          const SizedBox(height: 16),
          _shellCard(
            padding: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('BMI', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      const SizedBox(height: 4),
                      Text(_lastResult!.bmi.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 48, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                    ]),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: _bmiColor(_lastResult!.bmi),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(_lastResult!.category,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  '计算时间：${_fmt(_lastResult!.computedAt)}',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // ===== 档案 =====
  Widget _buildProfilesTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _shellCard(
          padding: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('档案管理',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _newProfileCtrl,
                    decoration: _inputDecoration('输入档案名称'),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _createProfile,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.add, color: Colors.white, size: 22),
                  ),
                ),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final profile in _profiles) ...[
          _shellCard(
            padding: 16,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _activeProfileId = profile.id),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                            child: Text(profile.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, color: Color(0xFF0F172A))),
                          ),
                          if (profile.id == _activeProfileId) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD1FAE5),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text('当前',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF047857))),
                            ),
                          ],
                        ]),
                        const SizedBox(height: 4),
                        Text('${profile.records.length} 条记录',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  const Text('切换', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  // ===== 记录 =====
  Widget _buildHistoryTab() {
    final records = _activeProfile?.records ?? [];
    // 图表数据：最近 12 次，倒序（旧→新），最新一根紫色
    final chartData = records.take(12).toList().reversed.toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _shellCard(
          padding: 16,
          child: Row(children: [
            const Text('记录',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
            const SizedBox(width: 8),
            const Text('图表仅显示最近12次记录',
                style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
          ]),
        ),
        const SizedBox(height: 12),
        _shellCard(
          padding: 16,
          child: SizedBox(
            height: 288, // h-72
            child: chartData.isEmpty
                ? const Center(child: Text('暂无数据', style: TextStyle(color: Color(0xFF94A3B8))))
                : CustomPaint(
                    size: const Size(double.infinity, 288),
                    painter: _BmiBarChartPainter(records: chartData),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        if (records.isEmpty)
          _shellCard(
            padding: 20,
            child: const Center(
              child: Text('当前没有历史记录',
                  style: TextStyle(fontSize: 14, color: Color(0xFF64748B))),
            ),
          )
        else
          for (final record in records) ...[
            _shellCard(
              padding: 16,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(record.bmi.toStringAsFixed(1),
                              style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A))),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: _bmiColor(record.bmi),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(record.category,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white)),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        Text('${record.height.toStringAsFixed(0)}cm / ${record.weight.toStringAsFixed(0)}kg',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  Text(_fmt(record.computedAt, withSeconds: false),
                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
      ],
    );
  }

  // ===== 更多（设置） =====
  Widget _buildSettingsTab() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _shellCard(
          padding: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('更多',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
              const SizedBox(height: 8),
              const Text('支持本地导入和导出 BMI 数据。',
                  style: TextStyle(fontSize: 14, color: Color(0xFF475569))),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text('计算BMI后自动保存至当前所选档案',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF334155))),
                  ),
                  Switch(
                    value: _autoSave,
                    activeColor: Colors.white,
                    activeTrackColor: const Color(0xFF4F46E5),
                    onChanged: (v) => setState(() => _autoSave = v),
                  ),
                ],
              ),
              if (_autoSave) ...[
                const Text('开启后，计算 BMI 会自动保存到当前档案',
                    style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: GestureDetector(
                    onTap: _exportData,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: const Text('导出数据',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: _importData,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      alignment: Alignment.center,
                      child: const Text('导入数据',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF334155))),
                    ),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  // ===== 底部标签栏 =====
  Widget _buildBottomTabBar() {
    const tabs = [('home', '首页'), ('profiles', '档案'), ('history', '记录'), ('settings', '更多')];
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.8),
        border: const Border(top: BorderSide(color: Color(0xB3FFFFFF))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          for (final (id, label) in tabs)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _activeTab = id),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _activeTab == id ? const Color(0xFF0F172A) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: _activeTab == id ? Colors.white : const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===== 公共小组件 =====

  Widget _shellCard({required Widget child, double padding = 16}) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32), // rounded-[2rem]
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: child,
    );
  }

  Widget _numberInput(TextEditingController ctrl, String hint) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _inputDecoration(hint),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      filled: true,
      fillColor: Colors.white,
      isCollapsed: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF818CF8)),
      ),
    );
  }
}

/// BMI 柱状图（对齐参考项目 recharts BarChart：圆角柱、顶部数值标签、最新一根紫色）
class _BmiBarChartPainter extends CustomPainter {
  final List<_BmiRecord> records; // 旧→新

  _BmiBarChartPainter({required this.records});

  @override
  void paint(Canvas canvas, Size size) {
    if (records.isEmpty) return;
    const labelH = 24.0; // 顶部数值标签空间
    const bottomH = 24.0; // 底部序号空间
    final chartH = size.height - labelH - bottomH;
    final n = records.length;
    final barAreaW = size.width;
    final slotW = barAreaW / n;
    final barW = (slotW * 0.55).clamp(12.0, 48.0);

    var maxBmi = 0.0;
    for (final r in records) {
      if (r.bmi > maxBmi) maxBmi = r.bmi;
    }
    if (maxBmi <= 0) maxBmi = 30;
    maxBmi *= 1.15; // 留顶部余量

    // 虚线网格（横向 4 条，对齐 CartesianGrid vertical={false} strokeDasharray）
    final gridPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    for (var g = 1; g <= 4; g++) {
      final y = labelH + chartH * g / 5;
      _drawDashLine(canvas, Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var i = 0; i < n; i++) {
      final r = records[i];
      final isLatest = i == n - 1;
      final barH = (r.bmi / maxBmi) * chartH;
      final cx = slotW * i + slotW / 2;
      final left = cx - barW / 2;
      final top = labelH + chartH - barH;

      final color = isLatest ? const Color(0xFF7C3AED) : _bmiColor(r.bmi);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, barW, barH),
        const Radius.circular(8),
      );
      canvas.drawRRect(rect, Paint()..color = color);

      // 顶部数值标签
      _paintText(
        canvas,
        r.bmi.toStringAsFixed(1),
        Offset(cx, top - 14),
        fontSize: 11,
        color: const Color(0xFF64748B),
      );

      // 底部序号
      _paintText(
        canvas,
        '${i + 1}',
        Offset(cx, labelH + chartH + 12),
        fontSize: 11,
        color: const Color(0xFF94A3B8),
      );
    }
  }

  void _drawDashLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dashW = 4.0, gapW = 4.0;
    var x = from.dx;
    while (x < to.dx) {
      final end = (x + dashW).clamp(x, to.dx);
      canvas.drawLine(Offset(x, from.dy), Offset(end, from.dy), paint);
      x += dashW + gapW;
    }
  }

  void _paintText(Canvas canvas, String text, Offset center,
      {required double fontSize, required Color color}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: color),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _BmiBarChartPainter oldDelegate) =>
      oldDelegate.records != records;
}
