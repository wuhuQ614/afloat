import 'dart:io' show Directory, exit, Platform, Process;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../services/update_service.dart';
import '../services/storage.dart' show Storage;
import '../theme_colors.dart' show AppColors;

/// 在线更新对话框（Windows / Android）
///
/// 展示新版本号与更新说明，点"立即更新"后下载安装包：
/// - Windows：下载 afloat-setup.exe → 启动安装器 → 退出应用让安装器接管（避免占用旧 exe）
/// - Android：下载 afloat.apk → 通过 MethodChannel 唤起系统安装器
class UpdateDialog extends StatefulWidget {
  final UpdateInfo info;
  const UpdateDialog({super.key, required this.info});

  /// 检查更新并弹出对话框。
  ///
  /// [manual] 为 false（启动自动检查）时受两条持久化规则约束，命中任一即不弹：
  /// - 用户点过"不再显示"（[Storage.loadUpdateReminderDisabled]）；
  /// - 当前版本被点过"关闭"（[Storage.loadIgnoredUpdateBuild] == 远端 build）。
  /// [manual] 为 true（设置页手动检查）时总是弹出（只要确有新版本）。
  /// [quiet] 为 false（手动检查）且无新版本时，给一句"已是最新版本"提示。
  static Future<void> checkAndShow(
    BuildContext context, {
    bool quiet = true,
    bool manual = false,
  }) async {
    final result = await UpdateService.checkEx();
    if (!context.mounted) return;
    final info = result.info;
    if (info == null) {
      if (!quiet) {
        // 区分"网络不可达"与"确实已最新"，避免把网络问题谎报成"已是最新版本"
        final msg = result.networkOk ? '已是最新版本' : '网络无法访问更新服务器，请检查网络后重试';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: const TextStyle(fontSize: 12.5)),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    if (UpdateService.urlFor(info) == null) return; // 本平台无可用安装包
    if (!manual) {
      // 自动检查：尊重"不再显示"与"忽略本版本"
      if (Storage.loadUpdateReminderDisabled()) return;
      if (Storage.loadIgnoredUpdateBuild() == info.build.toString()) return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: !info.force,
      builder: (_) => UpdateDialog(info: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  static const MethodChannel _installChannel = MethodChannel('com.smartenglish/updater');

  double? _progress; // null=未开始，0~1=下载中
  String? _error;

  Future<void> _startUpdate() async {
    setState(() {
      _progress = 0;
      _error = null;
    });
    final url = UpdateService.urlFor(widget.info);
    if (url == null) {
      setState(() {
        _progress = null;
        _error = '当前平台没有可用的安装包';
      });
      return;
    }
    try {
      final saveTo = await _savePath();
      await UpdateService.download(url, saveTo: saveTo, onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      await _install(saveTo);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _progress = null;
        _error = '$e';
      });
    }
  }

  Future<String> _savePath() async {
    if (Platform.isWindows) {
      final dir = Directory.systemTemp;
      return '${dir.path}\\afloat-update\\afloat-setup-v${widget.info.version}.exe';
    }
    final tmp = await getTemporaryDirectory();
    return '${tmp.path}/apk/update.apk';
  }

  Future<void> _install(String path) async {
    if (Platform.isWindows) {
      // 先关对话框，再启动安装器并退出自身（旧 exe 正被占用，不退出安装会失败）
      if (mounted) Navigator.of(context).pop();
      await Process.start(path, []);
      exit(0);
    }
    if (Platform.isAndroid) {
      final ok = await _installChannel
          .invokeMethod<bool>('installApk', {'apkPath': path});
      if (ok != true) throw Exception('无法唤起系统安装器');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final downloading = _progress != null;
    return PopScope(
      canPop: !widget.info.force,
      child: Dialog(
        backgroundColor: c.cardSolid,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.system_update_alt_rounded, size: 20, color: c.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '发现新版本 ${widget.info.version}',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, color: c.text),
                ),
              ),
            ]),
            if (widget.info.notes.isNotEmpty) ...[
              const SizedBox(height: 14),
              ...widget.info.notes.map(
                (n) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(Icons.circle, size: 4, color: c.textTertiary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(n, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 1.5)),
                    ),
                  ]),
                ),
              ),
            ],
            if (widget.info.force) ...[
              const SizedBox(height: 10),
              Text('本次为强制更新，更新后才能继续使用',
                  style: TextStyle(fontSize: 12, color: c.scoreLow)),
            ],
            if (downloading) ...[
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  backgroundColor: c.inputFill,
                  valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                (_progress ?? 0) >= 1
                    ? '下载完成，正在打开安装器…'
                    : '正在下载… ${((_progress ?? 0) * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: c.textTertiary),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text('更新失败：$_error', style: TextStyle(fontSize: 12, color: c.scoreLow)),
            ],
            const SizedBox(height: 18),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              if (!widget.info.force && !downloading) ...[
                TextButton(
                  onPressed: () {
                    // 关闭：本次不更新，且记住该版本不再自动弹窗（下次推送更高版本才重新提醒）
                    Storage.saveIgnoredUpdateBuild(widget.info.build.toString());
                    Navigator.of(context).pop();
                  },
                  child: Text('关闭', style: TextStyle(color: c.textTertiary)),
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: () {
                    // 不再显示：以后自动检查都不弹窗，设置页"在线更新"仍可手动检查更新
                    Storage.saveUpdateReminderDisabled(true);
                    Navigator.of(context).pop();
                  },
                  child: Text('不再显示', style: TextStyle(color: c.textTertiary)),
                ),
                const SizedBox(width: 4),
              ],
              FilledButton(
                onPressed: downloading ? null : _startUpdate,
                child: Text(_error == null ? (_progress == null ? '更新' : '重新下载') : '重试'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
