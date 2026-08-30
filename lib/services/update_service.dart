import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// 远端更新清单（update.json）解析结果
class UpdateInfo {
  /// 新版本号（如 "1.1.0"），仅用于展示
  final String version;
  /// 新版本 build 号（如 2），用于与本地比较
  final int build;
  /// 更新说明（逐条显示）
  final List<String> notes;
  /// 是否强制更新（true 时对话框不可关闭、无"稍后"）
  final bool force;
  /// Windows 安装包直链（afloat-setup.exe）
  final String? winExeUrl;
  /// Android APK 直链（afloat.apk）
  final String? androidApkUrl;

  const UpdateInfo({
    required this.version,
    required this.build,
    required this.notes,
    required this.force,
    this.winExeUrl,
    this.androidApkUrl,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> j) {
    final win = j['win'] as Map<String, dynamic>?;
    final android = j['android'] as Map<String, dynamic>?;
    return UpdateInfo(
      version: (j['version'] as String?) ?? '',
      build: (j['build'] as num?)?.toInt() ?? 0,
      notes: [
        for (final n in (j['notes'] as List?) ?? const [])
          if (n is String && n.trim().isNotEmpty) n.trim(),
      ],
      force: (j['force'] as bool?) ?? false,
      winExeUrl: win?['exe_url'] as String?,
      androidApkUrl: android?['apk_url'] as String?,
    );
  }
}

/// 在线更新服务：检查 GitHub Releases 上的新版本并下载安装包。
///
/// 远端约定：
/// - 仓库根目录放 `update.json`（raw 直链：https://raw.githubusercontent.com/wuhuQ614/afloat/main/update.json）
/// - GitHub Release 的 tag 形如 `v1.1.0`，资产为 `afloat-setup.exe`（Windows）与 `afloat.apk`（Android）
class UpdateService {
  UpdateService._();

  /// 更新清单默认直链（仓库根目录，改版本号无需发新 Release）
  static const String manifestUrl =
      'https://raw.githubusercontent.com/wuhuQ614/afloat/main/update.json';

  /// 当前平台（Windows / Android / 其它）
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// 检查是否有新版本。
  /// - 返回 `UpdateInfo`：远端 build 高于本地 → 有新版本；
  /// - 返回 `null`：已是最新，或网络失败 / 清单损坏（静默当无更新，不打断用户）。
  static Future<UpdateInfo?> check({String? manifestUrl}) async {
    final client = http.Client();
    try {
      final resp = await client
          .get(Uri.parse(manifestUrl ?? UpdateService.manifestUrl))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final info = UpdateInfo.fromJson(
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
      final local = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(local.buildNumber) ?? 0;
      if (info.build <= localBuild) return null;
      return info;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// 下载文件到 [saveTo]，带进度回调 [onProgress]（0.0~1.0）。
  /// 返回最终文件路径；失败抛异常。
  static Future<String> download(
    String url, {
    required void Function(double progress) onProgress,
    required String saveTo,
  }) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      final resp = await client.send(req);
      if (resp.statusCode != 200) {
        throw HttpException('下载失败（HTTP ${resp.statusCode}）');
      }
      final total = resp.contentLength;
      final file = File(saveTo);
      await file.parent.create(recursive: true);
      final sink = file.openWrite();
      var received = 0;
      try {
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          if (total != null && total > 0) {
            onProgress(received / total);
          }
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      onProgress(1.0);
      return saveTo;
    } finally {
      client.close();
    }
  }

  /// 当前平台对应的下载地址；本平台不支持更新时返回 null
  static String? urlFor(UpdateInfo info) {
    if (isWindows) return info.winExeUrl;
    if (isAndroid) return info.androidApkUrl;
    return null;
  }
}
