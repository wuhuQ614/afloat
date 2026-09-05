/// Windows 默认浏览器注册：让 AFloat 出现在系统「默认应用 → 浏览器」候选列表中，
/// 并接管 http/https 链接（用户在系统设置里选择后，外部链接会用 AFloat 打开）。
///
/// 采用 HKCU 用户级注册（免管理员提权）：
///  - HKCU\Software\Clients\StartMenuInternet\<ProgId>\Capabilities
///    声明浏览器能力（FriendlyAppName / URLAssociations / FileAssociations）
///  - HKCU\Software\RegisteredApplications 指向上述 Capabilities，
///    Windows 设置页据此把 AFloat 列为可选默认浏览器
///  - HKCU\Software\Classes\<ProgId> 的 shell\open\command 负责打开链接
///
/// 最终"设为默认"仍需用户在 系统设置 → 应用 → 默认应用 → 浏览器 中点选
/// （Windows 不开放第三方直接改写 http/https 的 UserChoice 哈希）。
///
/// 其他平台（Android/iOS/Web）本服务无操作。
library;

import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;

/// 默认浏览器注册服务
class BrowserRegister {
  static const String progId = 'AFloatBrowser';
  /// Windows 设置里显示的"浏览器"候选名
  static const String menuName = 'AFloat';

  static String get _root => r'HKCU:\Software\Clients\StartMenuInternet\AFloatBrowser';
  static String get _caps => r'HKCU:\Software\Clients\StartMenuInternet\AFloatBrowser\Capabilities';

  static bool get isWindows => !kIsWeb && Platform.isWindows;

  /// 是否已注册（检查 StartMenuInternet 键是否存在）
  static bool get isRegistered {
    if (!isWindows) return false;
    try {
      return _regExists(_root);
    } catch (_) {
      return false;
    }
  }

  /// 注册为候选默认浏览器（HKCU 用户级，无需管理员权限）
  /// 返回 null 表示成功，否则返回错误信息
  static String? register() {
    if (!isWindows) return '仅 Windows 支持设置为默认浏览器';
    try {
      final exe = Platform.resolvedExecutable.replaceAll('/', r'\');
      final openCmd = '"$exe" "%1"';

      // ---- StartMenuInternet 标准结构（Windows 识别浏览器的关键路径）----
      _regValue(_root, null, menuName);
      _regValue(_root, 'ApplicationDescription', 'AFloat 内置浏览器（基于 WebView2）');
      _regValue(_root, 'ApplicationName', menuName);
      _regValue(_root, 'ApplicationIcon', '"$exe",0');
      _regValue(_root, 'FriendlyAppName', menuName);
      _regPath('$_root\\shell\\open\\command', openCmd);
      _regPath('$_root\\DefaultIcon', '"$exe",0');

      // ---- Capabilities 段 ----
      _regValue(_caps, 'ApplicationName', menuName);
      _regValue(_caps, 'ApplicationDescription', 'AFloat 内置浏览器（基于 WebView2）');
      _regValue(_caps, 'FriendlyAppName', menuName);
      _regValue(_caps, 'ApplicationIcon', '"$exe",0');
      // URLAssociations
      for (final proto in ['http', 'https', 'mailto', 'ftp']) {
        _regValue('$_caps\\URLAssociations', proto, progId);
      }
      // FileAssociations（本地网页文件）
      for (final ext in ['htm', 'html', 'shtml', 'xhtml', 'mhtml', 'svg', 'pdf']) {
        _regValue('$_caps\\FileAssociations', '.$ext', progId);
      }

      // ---- 让 Windows 设置页把 AFloat 列为默认浏览器候选 ----
      _regValue(
        r'HKCU:\Software\RegisteredApplications',
        menuName,
        'Software\\Clients\\StartMenuInternet\\AFloatBrowser\\Capabilities',
      );

      // ---- ProgID 协议处理 ----
      _regPath(r'HKCU:\Software\Classes\AFloatBrowser\URL Protocol', '');
      _regPath(r'HKCU:\Software\Classes\AFloatBrowser\shell\open\command', openCmd);
      _regPath(r'HKCU:\Software\Classes\AFloatBrowser\DefaultIcon', '"$exe",0');
      // 兜底：http/https 用户级 shell\open\command（被系统 UserChoice 覆盖时无害）
      _regPath(r'HKCU:\Software\Classes\http\shell\open\command', openCmd);
      _regPath(r'HKCU:\Software\Classes\https\shell\open\command', openCmd);

      return null;
    } catch (e) {
      return '注册失败：$e';
    }
  }

  /// 取消注册（移除本应用相关键）
  static String? unregister() {
    if (!isWindows) return '仅 Windows 支持';
    try {
      _regDelete(r'HKCU:\Software\Clients\StartMenuInternet\AFloatBrowser');
      _regDelete(r'HKCU:\Software\Classes\AFloatBrowser');
      _regDelete(r'HKCU:\Software\Classes\http\shell\open\command');
      _regDelete(r'HKCU:\Software\Classes\https\shell\open\command');
      Process.runSync('reg', [
        'delete', r'HKCU:\Software\RegisteredApplications',
        '/v', menuName, '/f',
      ]);
      return null;
    } catch (e) {
      return '取消失败：$e';
    }
  }

  // ---- 底层注册表操作 ----
  static bool _regExists(String path) {
    final r = Process.runSync('reg', ['query', path]);
    return r.exitCode == 0;
  }

  /// 写入键（含默认值之外的普通值）
  static void _regValue(String path, String? name, String value) {
    final args = <String>['add', path];
    if (name == null) {
      args.add('/ve');
    } else {
      args.addAll(['/v', name]);
    }
    args.addAll(['/t', 'REG_SZ', '/d', value, '/f']);
    final r = Process.runSync('reg', args);
    if (r.exitCode != 0) {
      throw Exception('reg add 失败($path): ${r.stderr}');
    }
  }

  /// 写入键的默认值（name 可空则走 /ve）
  static void _regPath(String path, String defaultValue) {
    _regValue(path, null, defaultValue);
  }

  static void _regDelete(String path) {
    final r = Process.runSync('reg', ['delete', path, '/f']);
    if (r.exitCode != 0 && !r.stderr.toUpperCase().contains('UNABLE TO FIND')) {
      throw Exception('reg delete 失败($path): ${r.stderr}');
    }
  }
}