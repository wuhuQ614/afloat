/// 系统全局代理：通过 Windows 注册表设置/还原系统代理（HKCU\...\Internet Settings）。
/// 启用时将系统代理指向 mihomo 混合端口，禁用/退出时还原原值。
library;

import 'dart:ffi';
import 'dart:io';

/// WinINet: 通知系统“代理设置已变更”，使更改立即生效（无需重启浏览器）
final DynamicLibrary _wininet = Platform.isWindows
    ? DynamicLibrary.open('wininet.dll')
    : DynamicLibrary.process();

typedef _InternetSetOptionNative = Int32 Function(
    Pointer hInternet, Int32 dwOption, Pointer lpBuffer, Int32 dwBufferLength);
typedef _InternetSetOptionDart = int Function(
    Pointer hInternet, int dwOption, Pointer lpBuffer, int dwBufferLength);

final _InternetSetOptionDart _internetSetOption = _wininet
    .lookupFunction<_InternetSetOptionNative, _InternetSetOptionDart>(
        'InternetSetOptionA');

/// 注册表读取（读回当前用户 Internet Settings 下的值）
class SystemProxy {
  static const String _keyPath =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';

  /// 备份/还原用的原代理设置
  static String? _savedEnable;
  static String? _savedServer;
  static bool _backupTaken = false;

  /// 是否运行在 Windows（非 Windows 平台直接返回 false，保持无害）
  static bool get isSupported => Platform.isWindows;

  /// 读取单个注册表值（返回字符串，不存在返回 null）
  static String? _readValue(String valueName) {
    if (!isSupported) return null;
    try {
      final r = Process.runSync('reg', ['query', _keyPath, '/v', valueName],
          runInShell: true);
      final out = (r.stdout as String) ?? '';
      // 输出形如 "    ProxyServer    REG_SZ    127.0.0.1:7890"
      for (final line in out.split('\n')) {
        if (line.contains(valueName) && line.contains('REG_')) {
          final parts = line.trim().split(RegExp(r'\s{2,}'));
          if (parts.length >= 3) return parts.sublist(2).join(' ').trim();
        }
      }
    } catch (_) {}
    return null;
  }

  /// 写入注册表并广播变更通知
  static void _writeValue(String valueName, String value, {String type = 'REG_SZ'}) {
    if (!isSupported) return;
    try {
      Process.runSync('reg', [
        'add', _keyPath, '/v', valueName, '/t', type, '/d', value, '/f'
      ], runInShell: true);
    } catch (_) {}
  }

  static void _deleteValue(String valueName) {
    if (!isSupported) return;
    try {
      Process.runSync('reg', ['delete', _keyPath, '/v', valueName, '/f'],
          runInShell: true);
    } catch (_) {}
  }

  /// 通知系统代理设置已变更
  static void _notifyChanged() {
    if (!isSupported) return;
    try {
      // INTERNET_OPTION_SETTINGS_CHANGED = 39，INTERNET_OPTION_REFRESH = 37
      _internetSetOption(nullptr, 39, nullptr, 0);
      _internetSetOption(nullptr, 37, nullptr, 0);
    } catch (_) {}
  }

  /// 启用系统全局代理，指向 host:port。返回是否成功。
  static bool enable(String host, int port) {
    if (!isSupported) return false;
    try {
      // 首次启用前备份原设置
      if (!_backupTaken) {
        _savedEnable = _readValue('ProxyEnable');
        _savedServer = _readValue('ProxyServer');
        _backupTaken = true;
      }
      _writeValue('ProxyEnable', '1', type: 'REG_DWORD');
      _writeValue('ProxyServer', '$host:$port');
      _notifyChanged();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 还原系统代理为原始设置。未启用过时直接关闭代理。
  static void restore() {
    if (!isSupported) return;
    try {
      if (_backupTaken && _savedEnable != null && _savedServer != null) {
        _writeValue('ProxyEnable', _savedEnable!, type: 'REG_DWORD');
        _writeValue('ProxyServer', _savedServer!);
      } else {
        _writeValue('ProxyEnable', '0', type: 'REG_DWORD');
        // 保留 ProxyServer，仅关闭开关，避免误删用户其它配置
      }
      _backupTaken = false;
      _savedEnable = null;
      _savedServer = null;
      _notifyChanged();
    } catch (_) {}
  }

  /// 仅关闭系统代理开关（不还原 ProxyServer，用于临时直连）
  static void disable() {
    if (!isSupported) return;
    try {
      _writeValue('ProxyEnable', '0', type: 'REG_DWORD');
      _notifyChanged();
    } catch (_) {}
  }
}