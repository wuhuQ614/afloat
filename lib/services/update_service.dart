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

/// 更新检查结果：区分"无更新"与"网络不可达"（后者不能误导用户说已是最新）
class UpdateCheckResult {
  /// 非 null 表示有可用新版本
  final UpdateInfo? info;
  /// 至少有一个清单源成功返回（true 时才可信"已是最新"）
  final bool networkOk;
  const UpdateCheckResult({required this.info, required this.networkOk});
}

/// 在线更新服务：检查 GitHub Releases 上的新版本并下载安装包。
///
/// 远端约定：
/// - 仓库根目录放 `update.json`（raw 直链：https://raw.githubusercontent.com/wuhuQ614/afloat/main/update.json）
/// - GitHub Release 的 tag 形如 `v1.1.0`，资产为 `afloat-setup.exe`（Windows）与 `afloat.apk`（Android）
class UpdateService {
  UpdateService._();

  /// 更新清单候选源（按序尝试）。
  /// 国内网络 raw.githubusercontent.com 直链常不可达，jsdelivr CDN / ghproxy 镜像通常可达；
  /// 首个成功返回的源生效。
  static const List<String> manifestUrls = [
    'https://raw.githubusercontent.com/wuhuQ614/afloat/main/update.json',
    'https://cdn.jsdelivr.net/gh/wuhuQ614/afloat@main/update.json',
    'https://ghproxy.net/https://raw.githubusercontent.com/wuhuQ614/afloat/main/update.json',
  ];

  /// 兼容旧引用：首选清单源
  static const String manifestUrl = manifestUrls.first;

  /// 安装包下载镜像前缀：直连 GitHub Releases 失败时依次尝试
  static const List<String> downloadMirrors = [
    'https://ghproxy.net/',
    'https://gh-proxy.com/',
  ];

  /// 当前平台（Windows / Android / 其它）
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// 检查是否有新版本（简化版：不区分"无更新"与"网络不可达"）。
  /// 返回 `UpdateInfo`：远端 build 高于本地 → 有新版本；`null`：无更新或检查失败。
  static Future<UpdateInfo?> check({String? manifestUrl}) async {
    final r = await checkEx();
    return r.info;
  }

  /// 检查是否有新版本（完整结果）。
  /// - [UpdateCheckResult.info] 非 null：远端 build 高于本地 → 有新版本；
  /// - info 为 null 且 networkOk 为 true：已是最新；
  /// - networkOk 为 false：所有清单源均不可达（网络问题，**不能**谎报"已是最新"）。
  static Future<UpdateCheckResult> checkEx() async {
    final client = http.Client();
    try {
      final local = await PackageInfo.fromPlatform();
      final localBuild = int.tryParse(local.buildNumber) ?? 0;

      // 依次尝试所有清单源
      Object? lastErr;
      for (final url in manifestUrls) {
        try {
          final resp = await client
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 8));
          if (resp.statusCode != 200) continue;
          final info = UpdateInfo.fromJson(
              jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>);
          if (info.build <= localBuild) {
            return UpdateCheckResult(info: null, networkOk: true);
          }
          return UpdateCheckResult(info: info, networkOk: true);
        } catch (e) {
          lastErr = e; // 记录最后一个错误，继续尝试下一个源
        }
      }
      return UpdateCheckResult(info: null, networkOk: false);
    } catch (_) {
      return UpdateCheckResult(info: null, networkOk: false);
    } finally {
      client.close();
    }
  }

  /// 下载文件到 [saveTo]，带进度回调 [onProgress]（0.0~1.0）。
  /// 直连 [url] 失败时自动尝试镜像前缀（国内网络 GitHub Releases 直链常不可达）。
  /// 返回最终文件路径；全部失败抛异常。
  static Future<String> download(
    String url, {
    required void Function(double progress) onProgress,
    required String saveTo,
  }) async {
    final candidates = [url, for (final m in downloadMirrors) '$m$url'];
    Object? lastErr;
    for (final u in candidates) {
      try {
        onProgress(0); // 每次换源重置进度
        return await _downloadOne(u, onProgress: onProgress, saveTo: saveTo);
      } catch (e) {
        lastErr = e;
      }
    }
    throw lastErr ?? HttpException('所有下载源均失败');
  }

  static Future<String> _downloadOne(
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
