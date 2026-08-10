/// 暴力转盘数据模型与持久化。
///
/// 对齐参考项目：
/// - item: { label, weight }，weight 默认 1，最小 0.1
/// - collection: { id, name, items }
/// - 持久化键 violentDecision（与参考项目一致），存 { collections, activeCollectionId }
library;

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'wheel_data.dart';

/// 转盘项目
class WheelItem {
  String label;
  double weight;

  WheelItem({required this.label, this.weight = 1});

  Map<String, dynamic> toJson() => {'label': label, 'weight': weight};

  factory WheelItem.fromJson(Map<String, dynamic> j) => WheelItem(
        label: (j['label'] as String?) ?? '',
        weight: ((j['weight'] as num?) ?? 1).toDouble(),
      );
}

/// 转盘场景集合
class WheelCollection {
  String id;
  String name;
  List<WheelItem> items;

  WheelCollection({required this.id, required this.name, required this.items});

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'items': items.map((i) => i.toJson()).toList(),
      };

  factory WheelCollection.fromJson(Map<String, dynamic> j) => WheelCollection(
        id: (j['id'] as String?) ?? '',
        name: (j['name'] as String?) ?? '',
        items: ((j['items'] as List?) ?? [])
            .map((e) => WheelItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 内置默认场景（大胃袋 + 全国省份美食）
List<WheelCollection> builtinCollections() {
  return [
    WheelCollection(
      id: 'bigstomach',
      name: '大胃袋',
      items: kBigStomachItems
          .map((l) => WheelItem(label: l, weight: 1))
          .toList(),
    ),
    for (final (id, name, labels) in kProvincePresets)
      WheelCollection(
        id: id,
        name: name,
        items: labels.map((l) => WheelItem(label: l, weight: 1)).toList(),
      ),
  ];
}

/// 内置场景 id 集合（合并时用于去重）
Set<String> builtinIds() {
  return {'bigstomach', for (final (id, _, _) in kProvincePresets) id};
}

/// 省份预设 id 集合（对齐参考项目 PROVINCE_PRESET_IDS）
Set<String> provinceIds() {
  return {for (final (id, _, _) in kProvincePresets) id};
}

/// 转盘持久化
class WheelStorage {
  static const String _key = 'violentDecision';

  /// 加载 collections 与 activeCollectionId。
  /// 合并策略与参考项目一致：内置场景始终保留，用户自定义场景追加。
  static Future<(List<WheelCollection>, String)> load() async {
    final defaults = builtinCollections();
    var active = defaults.first.id;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        final savedList = (data['collections'] as List?) ?? [];
        final ids = builtinIds();
        final custom = savedList
            .map((e) => WheelCollection.fromJson(e as Map<String, dynamic>))
            .where((c) => !ids.contains(c.id))
            .toList();
        defaults.addAll(custom);
        final savedActive = data['activeCollectionId'] as String?;
        if (savedActive != null &&
            defaults.any((c) => c.id == savedActive)) {
          active = savedActive;
        }
      }
    } catch (_) {
      // 解析失败用默认
    }
    return (defaults, active);
  }

  /// 保存 collections 与 activeCollectionId（保留参考项目的键名）
  static Future<void> save(
      List<WheelCollection> collections, String activeCollectionId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'collections': collections.map((c) => c.toJson()).toList(),
        'activeCollectionId': activeCollectionId,
      };
      await prefs.setString(_key, jsonEncode(data));
    } catch (_) {
      // 存储失败不影响功能
    }
  }
}
