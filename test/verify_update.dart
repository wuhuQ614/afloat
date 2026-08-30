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
  // 1. 读取并解析真实 update.json
  final raw = File('update.json').readAsStringSync();
  final j = jsonDecode(raw) as Map<String, dynamic>;
  final info = _parse(j);
  _check(info.version.isNotEmpty, 'version 非空：${info.version}');
  _check(info.build > 0, 'build 为正整数：${info.build}');
  _check(info.winExeUrl != null && info.winExeUrl!.startsWith('https://'), 'win.exe_url 是 https 直链');
  _check(info.androidApkUrl != null && info.androidApkUrl!.startsWith('https://'), 'android.apk_url 是 https 直链');
  _check(info.winExeUrl!.contains('/releases/download/'), 'exe 走 GitHub Releases 直链');
  _check(info.androidApkUrl!.contains('/releases/download/'), 'apk 走 GitHub Releases 直链');
  _check(info.winExeUrl!.endsWith('.exe'), 'exe 文件名以 .exe 结尾');
  _check(info.androidApkUrl!.endsWith('.apk'), 'apk 文件名以 .apk 结尾');
  _check(info.force == false, '当前 force=false（非强制）');

  // 2. 版本对比（本地 = pubspec version 1.0.0+1 → build=1）
  _check(!_hasUpdate(info, 1), '本地 build=1 == 清单 build=${info.build} → 无更新（不误弹）');
  _check(_hasUpdate(info, 0), '本地 build=0 < ${info.build} → 有更新');
  _check(!_hasUpdate(info, 999), '本地 build=999 > ${info.build} → 无更新');

  // 3. 版本号与 URL 一致性：URL 里的 tag 应包含清单 version
  final tag = info.winExeUrl!.split('/releases/download/')[1].split('/')[0];
  _check(tag == 'v${info.version}', 'Release tag(v$tag) 与 version(${info.version}) 对应');

  stdout.writeln('\n全部 $_assertions 项断言通过');
}
