/// 邮箱页面：账号管理 + 收件箱 + 邮件详情 + 写邮件
/// 视觉：大厂简约克制（企业蓝强调色 + 中性灰底），不做风格化点缀
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../services/mail_service.dart';
import '../theme_colors.dart';

/// 邮箱页面（作为更多功能入口打开）
class MailPage extends StatefulWidget {
  final int initialIndex; // 0=收件箱 1=账号设置
  const MailPage({super.key, this.initialIndex = 0});

  @override
  State<MailPage> createState() => _MailPageState();
}

class _MailPageState extends State<MailPage> {
  late List<MailAccountConfig> _accounts;
  int _tabIdx;
  MailAccountConfig? _activeAccount;
  List<MailItem>? _inbox;
  String? _inboxError;
  bool _loadingInbox = false;

  _MailPageState() : _tabIdx = 0;

  @override
  void initState() {
    super.initState();
    _tabIdx = widget.initialIndex;
    _accounts = MailService.loadFromStorage();
    if (_accounts.isNotEmpty) _activeAccount = _accounts.first;
  }

  Future<void> _reloadAccounts() async {
    final accs = MailService.loadFromStorage();
    setState(() {
      _accounts = accs;
      if (_activeAccount == null && accs.isNotEmpty) _activeAccount = accs.first;
      if (accs.isEmpty || !accs.any((a) => a.email == _activeAccount?.email)) {
        _activeAccount = accs.isNotEmpty ? accs.first : null;
      }
      _inbox = null;
      _inboxError = null;
    });
    if (_activeAccount != null && _tabIdx == 0) await _loadInbox();
  }

  Future<void> _loadInbox() async {
    final acc = _activeAccount;
    if (acc == null) return;
    setState(() {
      _loadingInbox = true;
      _inboxError = null;
    });
    try {
      final items = await MailService([acc]).fetchInbox(acc);
      if (!mounted) return;
      setState(() {
        _inbox = items;
        _loadingInbox = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inboxError = _friendlyError(e);
        _loadingInbox = false;
      });
    }
  }

  static String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('USERLOGGEDOUT') || s.contains('Invalid credentials') || s.contains('LOGIN failed')) {
      return '账号或授权码错误，请检查 IMAP/SMTP 授权码';
    }
    if (s.contains('SocketException') || s.contains('TimeoutException') || s.contains('not connected')) {
      return '网络连接失败，请检查网络或服务器地址';
    }
    return '收件失败：$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final rp = ReportPalette(isLight: c.isLight);
    return Scaffold(
      backgroundColor: rp.pageBg,
      appBar: AppBar(
        titleSpacing: 0,
        backgroundColor: rp.pageBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('邮箱', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        actions: [
          if (_activeAccount != null)
            TextButton.icon(
              onPressed: _loadingInbox ? null : _loadInbox,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('刷新', style: TextStyle(fontSize: 12.5)),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 19),
            tooltip: '写邮件',
            onPressed: _activeAccount == null
                ? () => setState(() => _tabIdx = 1)
                : () => _openCompose(),
          ),
          SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            height: 48,
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _tab('收件箱', 0),
                  const SizedBox(width: 20),
                  _tab('账号', 1),
                ]),
              ),
            ),
          ),
        ),
      ),
      body: _tabIdx == 0 ? _buildInbox(c, rp) : _buildAccounts(c, rp),
    );
  }

  Widget _tab(String label, int idx) {
    final c = AppColors.of(context);
    final rp = ReportPalette(isLight: c.isLight);
    final selected = _tabIdx == idx;
    return InkWell(
      onTap: () {
        setState(() => _tabIdx = idx);
        if (idx == 0 && _inbox == null && _activeAccount != null) _loadInbox();
      },
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: selected ? rp.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? rp.accent : c.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  // ---------- 收件箱 ----------
  Widget _buildInbox(AppColors c, ReportPalette rp) {
    if (_accounts.isEmpty) {
      return _EmptyAccounts(onSetup: () => setState(() => _tabIdx = 1));
    }
    if (_loadingInbox && _inbox == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_inboxError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline, size: 34, color: c.textTertiary),
            const SizedBox(height: 12),
            Text(_inboxError!, style: TextStyle(fontSize: 13, color: c.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 14),
            // 账号切换 & 重试
            if (_accounts.length > 1)
              DropdownButton<MailAccountConfig>(
                value: _activeAccount,
                underline: const SizedBox(),
                items: _accounts.map((a) => DropdownMenuItem(value: a, child: Text(a.email, style: const TextStyle(fontSize: 12.5)))).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _activeAccount = v);
                    _loadInbox();
                  }
                },
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _loadInbox,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
              style: FilledButton.styleFrom(backgroundColor: rp.accent),
            ),
          ]),
        ),
      );
    }
    final inbox = _inbox ?? <MailItem>[];
    return Column(children: [
      Expanded(
        child: inbox.isEmpty
            ? const Center(child: Text('收件箱为空', style: TextStyle(fontSize: 13, color: Colors.grey)))
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 12),
                itemCount: inbox.length,
                separatorBuilder: (_, __) => Divider(height: 1, thickness: 0.5, color: rp.barTrack),
                itemBuilder: (context, i) {
                  final item = inbox[i];
                  return _MailRow(item: item, rp: rp, c: c, onTap: () => _openDetail(item));
                },
              ),
      ),
    ]);
  }

  // ---------- 邮件列表行 ----------
  Widget _MailRow({required MailItem item, required ReportPalette rp, required AppColors c, required VoidCallback onTap}) {
    final time = item.date == null ? '' : _fmtDate(item.date!);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: item.isSeen ? Colors.transparent : rp.accentSoft,
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: item.isSeen ? rp.barTrack : rp.accent,
            ),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(
                    item.displayFrom.isEmpty ? '(未知发件人)' : item.displayFrom,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: item.isSeen ? FontWeight.w500 : FontWeight.w700,
                      color: c.text,
                    ),
                  ),
                ),
                if (time.isNotEmpty)
                  Text(time, style: TextStyle(fontSize: 11, color: c.textTertiary, fontFeatures: const [])),
              ]),
              const SizedBox(height: 3),
              Text(
                item.subject ?? '(无主题)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: item.isSeen ? c.textSecondary : c.text),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ---------- 账号管理 ----------
  Widget _buildAccounts(AppColors c, ReportPalette rp) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('邮箱账号', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 4),
        Text('使用邮箱的 IMAP/SMTP 授权码连接（不是登录密码）。在邮箱网页设置中开启 IMAP/SMTP 服务后获取。',
            style: TextStyle(fontSize: 12, color: c.textTertiary, height: 1.5)),
        const SizedBox(height: 14),
        if (_accounts.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(border: Border.all(color: rp.barTrack), borderRadius: BorderRadius.circular(10)),
            child: Text('尚未配置邮箱账号', style: TextStyle(fontSize: 13, color: c.textSecondary)),
          )
        else
          for (final acc in _accounts)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
              decoration: BoxDecoration(
                color: rp.cardBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: rp.barTrack),
              ),
              child: Row(children: [
                Icon(Icons.mark_email_read_outlined, size: 18, color: rp.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(acc.name, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.text)),
                    Text('${acc.email}', style: TextStyle(fontSize: 11.5, color: c.textTertiary)),
                  ]),
                ),
                if (_activeAccount?.email == acc.email)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.check_circle, size: 16, color: rp.green),
                  ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 17),
                  tooltip: '删除',
                  color: c.textTertiary,
                  onPressed: () => _deleteAccount(acc),
                ),
              ]),
            ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _openAddAccountDialog,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('添加邮箱账号', style: TextStyle(fontSize: 13)),
          style: OutlinedButton.styleFrom(
            foregroundColor: rp.accent,
            side: BorderSide(color: rp.accent, width: 0.8),
            padding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        const SizedBox(height: 20),
        Text('支持邮箱', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in MailServerPreset.all)
              Chip(
                label: Text(p.name, style: const TextStyle(fontSize: 11.5)),
                backgroundColor: rp.chip,
                side: BorderSide(color: rp.barTrack),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _deleteAccount(MailAccountConfig acc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账号', style: TextStyle(fontSize: 15)),
        content: Text('确定删除 ${acc.email} 吗？', style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    final svc = MailService([..._accounts]);
    svc.accounts.removeWhere((a) => a.email == acc.email);
    await svc.saveToStorage();
    await _reloadAccounts();
  }

  // ---------- 添加账号对话框 ----------
  Future<void> _openAddAccountDialog() async {
    final result = await showDialog<MailAccountConfig>(
      context: context,
      builder: (ctx) => AddAccountDialog(accounts: _accounts),
    );
    if (result != null) {
      final svc = MailService([..._accounts, result]);
      await svc.saveToStorage();
      await _reloadAccounts();
      if (mounted) _loadInbox();
    }
  }

  // ---------- 详情 ----------
  Future<void> _openDetail(MailItem item) async {
    final acc = _activeAccount;
    if (acc == null) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (ctx) => MailDetailDialog(account: acc, mail: item),
    );
  }

  // ---------- 写信 ----------
  Future<void> _openCompose() async {
    final acc = _activeAccount;
    if (acc == null) return;
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => ComposeDialog(account: acc),
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已发送（如未在“已发送”看到，请检查服务器）', style: const TextStyle(fontSize: 12.5)), behavior: SnackBarBehavior.floating),
      );
    }
  }

  String _fmtDate(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return DateFormat('HH:mm').format(d);
    }
    return DateFormat('MM-dd').format(d);
  }
}

class _EmptyAccounts extends StatelessWidget {
  final VoidCallback onSetup;
  const _EmptyAccounts({required this.onSetup});

  @override
  Widget build(BuildContext context) {
    final rp = ReportPalette(isLight: Theme.of(context).brightness == Brightness.light);
    final c = AppColors.of(context);
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.mark_email_unread_outlined, size: 40, color: c.textTertiary),
        const SizedBox(height: 12),
        const Text('未配置邮箱账号', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        const Text('添加账号后即可收发邮件', style: TextStyle(fontSize: 12.5)),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onSetup,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('添加账号'),
          style: FilledButton.styleFrom(backgroundColor: rp.accent),
        ),
      ]),
    );
  }
}

/// 添加账号对话框
class AddAccountDialog extends StatefulWidget {
  final List<MailAccountConfig> accounts;
  const AddAccountDialog({super.key, required this.accounts});

  @override
  State<AddAccountDialog> createState() => _AddAccountDialogState();
}

class _AddAccountDialogState extends State<AddAccountDialog> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  MailServerPreset? _preset;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final rp = ReportPalette(isLight: c.isLight);
    return AlertDialog(
      title: const Text('添加邮箱账号', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('选择邮箱服务商（自动填入服务器地址）', style: TextStyle(fontSize: 12, color: c.textSecondary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in MailServerPreset.all)
                  ChoiceChip(
                    label: Text(p.name, style: const TextStyle(fontSize: 11.5)),
                    selected: _preset?.name == p.name,
                    onSelected: (_) => setState(() => _preset = p),
                    selectedColor: rp.accentSoft,
                    side: BorderSide(color: _preset?.name == p.name ? rp.accent : rp.barTrack),
                    labelStyle: TextStyle(color: _preset?.name == p.name ? rp.accent : c.text),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _emailCtrl,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: '邮箱地址',
                hintText: 'name@example.com',
                labelStyle: const TextStyle(fontSize: 12.5),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: (_) => setState(() {
                if (_preset == null) {
                  // 从邮箱域名猜测服务商
                  final host = _emailCtrl.text.trim().isEmpty ? '' : _emailCtrl.text.trim().split('@').last.toLowerCase();
                  for (final p in MailServerPreset.all) {
                    final imapDomain = p.imapHost.split('.').skip(1).join('.');
                    if (host.contains(imapDomain)) {
                      _preset = p;
                      break;
                    }
                  }
                }
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: '授权码（不是登录密码）',
                labelStyle: const TextStyle(fontSize: 12.5),
                hintText: '在邮箱网页端开启 IMAP/SMTP 后获取',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.red)),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消', style: TextStyle(fontSize: 13))),
        FilledButton(
          onPressed: _saving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: rp.accent),
          child: Text(_saving ? '验证中…' : '添加', style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();
    if (!email.contains('@') || pass.isEmpty) {
      setState(() => _error = '请填写完整的邮箱地址与授权码');
      return;
    }
    if (widget.accounts.any((a) => a.email == email)) {
      setState(() => _error = '该邮箱已添加');
      return;
    }
    final preset = _preset;
    if (preset == null) {
      setState(() => _error = '请选择邮箱服务商（如 QQ/163/Gmail）');
      return;
    }
    final nameHint = email.split('@').first;
    setState(() {
      _saving = true;
      _error = null;
    });
    final cfg = MailAccountConfig(
      name: '${preset.name} · $nameHint',
      email: email,
      password: pass,
      imapHost: preset.imapHost,
      imapPort: preset.imapPort,
      smtpHost: preset.smtpHost,
      smtpPort: preset.smtpPort,
    );
    // 校验连接
    try {
      await MailService([cfg]).fetchInbox(cfg, count: 1);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = '连接失败：请检查授权码与网络\n${e.toString().split('\n').first}';
      });
      return;
    }
    if (!mounted) return;
    Navigator.pop(context, cfg);
  }
}

/// 邮件详情对话框
class MailDetailDialog extends StatefulWidget {
  final MailAccountConfig account;
  final MailItem mail;
  const MailDetailDialog({super.key, required this.account, required this.mail});

  @override
  State<MailDetailDialog> createState() => _MailDetailDialogState();
}

class _MailDetailDialogState extends State<MailDetailDialog> {
  Map<String, dynamic>? _detail;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await MailService([widget.account]).fetchMessageDetail(widget.account, widget.mail.id);
      if (!mounted) return;
      setState(() {
        _detail = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final rp = ReportPalette(isLight: c.isLight);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
      child: SizedBox(
        width: 640,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 10, 12),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: rp.barTrack, width: 0.5))),
            child: Row(children: [
              Expanded(
                child: Text(
                  widget.mail.subject ?? '(无主题)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text),
                ),
              ),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 18)),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.error_outline, size: 30, color: c.textTertiary),
                            const SizedBox(height: 10),
                            Text(_error!, style: TextStyle(fontSize: 12.5, color: c.textSecondary), textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('重试'),
                              style: FilledButton.styleFrom(backgroundColor: rp.accent),
                            ),
                          ]),
                        ),
                      )
                    : _detail == null
                        ? const SizedBox()
                        : SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _infoRow('发件人', '${_detail!['fromName'] ?? ''} <${_detail!['fromEmail'] ?? ''}>'),
                              if ((_detail!['to'] as String? ?? '').isNotEmpty) _infoRow('收件人', _detail!['to'] as String),
                              if (_detail!['date'] != null)
                                _infoRow('时间', _fmtDetailDate(_detail!['date'] as String)),
                              if ((_detail!['attachments'] as List).isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text('附件：${(_detail!['attachments'] as List).map((a) => a['name']).join('、')}',
                                    style: TextStyle(fontSize: 12, color: c.textTertiary)),
                              ],
                              Divider(height: 24, thickness: 1, color: rp.barTrack),
                              SelectableText(
                                (_detail!['text'] as String? ?? '').trim().isEmpty
                                    ? '(此邮件无纯文本内容)'
                                    : _detail!['text'] as String,
                                style: TextStyle(fontSize: 13.5, height: 1.6, color: c.text),
                              ),
                            ]),
                          ),
          ),
        ]),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final c = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 52, child: Text(label, style: TextStyle(fontSize: 12, color: c.textTertiary))),
        Expanded(child: SelectableText(value, style: TextStyle(fontSize: 12.5, color: c.text))),
      ]),
    );
  }

  String _fmtDetailDate(String iso) {
    try {
      return DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }
}

/// 写邮件对话框
class ComposeDialog extends StatefulWidget {
  final MailAccountConfig account;
  const ComposeDialog({super.key, required this.account});

  @override
  State<ComposeDialog> createState() => _ComposeDialogState();
}

class _ComposeDialogState extends State<ComposeDialog> {
  final _toCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _toCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final rp = ReportPalette(isLight: c.isLight);
    return AlertDialog(
      title: Text('写邮件 · ${widget.account.email}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _toCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              labelText: '收件人',
              hintText: 'name@example.com，多个用逗号分隔',
              labelStyle: const TextStyle(fontSize: 12.5),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _subjectCtrl,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(labelText: '主题', labelStyle: const TextStyle(fontSize: 12.5), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _bodyCtrl,
            maxLines: 9,
            minLines: 6,
            style: const TextStyle(fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              hintText: '邮件正文…',
              hintStyle: TextStyle(fontSize: 13, color: c.hintText),
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(fontSize: 12, color: Colors.red)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消', style: TextStyle(fontSize: 13))),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          style: FilledButton.styleFrom(backgroundColor: rp.accent),
          icon: const Icon(Icons.send, size: 15),
          label: Text(_sending ? '发送中…' : '发送', style: const TextStyle(fontSize: 13)),
        ),
      ],
    );
  }

  Future<void> _send() async {
    final to = _toCtrl.text.trim();
    if (to.isEmpty) {
      setState(() => _error = '请填写收件人');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await MailService([widget.account]).sendMail(
        widget.account,
        to: to,
        subject: _subjectCtrl.text.trim(),
        body: _bodyCtrl.text,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = '发送失败：${e.toString().split('\n').first}';
      });
    }
  }
}