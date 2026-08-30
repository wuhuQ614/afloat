/// 在线更新逻辑验证脚本（纯 Dart，不依赖 Flutter 运行时）
///
/// 复刻 UpdateService 的解析与版本对比核心逻辑，验证：
/// 1. 仓库根 update.json 可解析且字段齐全
/// 2. build 号对比：本地 build >= 清单 build → 无更新；小于 → 有更新
/// 3. 各平台 URL 直链正确
///
/// 运行：dart run test/verify_update.dart
import 'dart:convert';
import 'dart:io';

class _Info {
  final String version;
  final int build;
  final List<String> notes;
  final bool force;
  final String? winExeUrl;
  final String? androidApkUrl;
  _Info(this.version, this.build, this.notes, this.force, this.winExeUrl, this.androidApkUrl);
}

int _assertions = 0;
void _check(bool cond, String msg) {
  _assertions++;
  if (!cond) {
    stderr.writeln('FAIL: $msg');
    exit(1);
  }
  stdout.writeln('PASS: $msg');
}

_Info _parse(Map<String, dynamic> j) {
  final win = j['win'] as Map<String, dynamic>?;
  final android = j['android'] as Map<String, dynamic>?;
  return _Info(
    (j['version'] as String?) ?? '',
    (j['build'] as num?)?.toInt() ?? 0,
    [
      for (final n in (j['notes'] as List?) ?? const [])
        if (n is String && n.trim().isNotEmpty) n.trim(),
    ],
    (j['force'] as bool?) ?? false,
    win?['exe_url'] as String?,
    android?['apk_url'] as String?,
  );
}

/// 是否有更新：本地 build < 远端 build
bool _hasUpdate(_Info remote, int localBuild) => remote.build > localBuild;

void main() {
  // 0. 从 pubspec.yaml 读本地版本 build 号（动态，不再写死）
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final m = RegExp(r'^version:\s*[\d.]+\+(\d+)\s*$', multiLine: true).firstMatch(pubspec);
  _check(m != null, 'pubspec.yaml version 行可解析（x.y.z+build）');
  final localBuild = int.parse(m!.group(1)!);

  // 1. 读取并解析真实 update.json
  final raw = File('update.json').readAsStringSync();
  final j = jsonDecode(raw) as Map<String, dynamic>;
  final info = _parse(j);
  _check(info.version.isNotEmpty, 'version 非空：${info.version}');
  _check(info.build > 0, 'build 为正整数：${info.build}');
  _check(info.androidApkUrl != null && info.androidApkUrl!.startsWith('https://'), 'android.apk_url 是 https 直链');
  _check(info.androidApkUrl!.contains('/releases/download/'), 'apk 走 GitHub Releases 直链');
  _check(info.androidApkUrl!.endsWith('.apk'), 'apk 文件名以 .apk 结尾');
  _check(info.force == false, '当前 force=false（非强制）');
  // win 节可选：存在时必须是合法直链
  if (info.winExeUrl != null) {
    _check(info.winExeUrl!.startsWith('https://') && info.winExeUrl!.contains('/releases/download/'), 'win.exe_url 是 Releases 直链');
  }

  // 2. 版本对比：锚点断言（对任意远端 build 成立）
  //    - v1.0.0 基线（build 1）必须能收到更新弹窗
  //    - 与远端 build 一致的版本不弹（不误弹/不循环）
  _check(_hasUpdate(info, 1), 'build=1（v1.0.0 基线）< ${info.build} → 有更新（会弹窗）');
  _check(!_hasUpdate(info, info.build), 'build=${info.build} 与远端一致 → 无更新（不误弹、不循环）');
  _check(!_hasUpdate(info, 999), '本地 build=999 > ${info.build} → 无更新');

  // 3. 版本号与 URL 一致性：URL 里的 tag 应包含清单 version
  final tag = info.androidApkUrl!.split('/releases/download/')[1].split('/')[0];
  _check(tag == 'v${info.version}', 'Release tag($tag) 与 version(${info.version}) 对应');

  stdout.writeln('\n全部 $_assertions 项断言通过（本地 build=$localBuild，远端 build=${info.build}）');
}
