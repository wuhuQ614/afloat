/// 邮箱服务：账号配置 + 收件（IMAP）+ 发件（SMTP）
/// 基于本地 vendor 的 enough_mail，支持多数主流邮箱（QQ/163/Gmail/Outlook…）。
library;

import 'dart:async';

import 'package:enough_mail/enough_mail.dart';
import 'package:flutter/foundation.dart';

import 'storage.dart';

/// 预置的邮箱服务器模板
class MailServerPreset {
  final String name;
  final String imapHost;
  final int imapPort;
  final String smtpHost;
  final int smtpPort;
  const MailServerPreset(this.name, this.imapHost, this.imapPort, this.smtpHost, this.smtpPort);

  static const List<MailServerPreset> all = [
    MailServerPreset('QQ邮箱', 'imap.qq.com', 993, 'smtp.qq.com', 465),
    MailServerPreset('163邮箱', 'imap.163.com', 993, 'smtp.163.com', 465),
    MailServerPreset('126邮箱', 'imap.126.com', 993, 'smtp.126.com', 465),
    MailServerPreset('Gmail', 'imap.gmail.com', 993, 'smtp.gmail.com', 465),
    MailServerPreset('Outlook', 'outlook.office365.com', 993, 'smtp.office365.com', 587),
  ];
}

/// 邮箱账号配置
class MailAccountConfig {
  final String name; // 账号显示名，如 "QQ邮箱"
  final String email;
  final String password; // 授权码（IMAP/SMTP 通用）
  final String imapHost;
  final int imapPort;
  final String smtpHost;
  final int smtpPort;

  const MailAccountConfig({
    required this.name,
    required this.email,
    required this.password,
    required this.imapHost,
    this.imapPort = 993,
    required this.smtpHost,
    this.smtpPort = 465,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'password': password,
        'imapHost': imapHost,
        'imapPort': imapPort,
        'smtpHost': smtpHost,
        'smtpPort': smtpPort,
      };

  factory MailAccountConfig.fromJson(Map<String, dynamic> j) => MailAccountConfig(
        name: (j['name'] as String?) ?? '',
        email: (j['email'] as String?) ?? '',
        password: (j['password'] as String?) ?? '',
        imapHost: (j['imapHost'] as String?) ?? '',
        imapPort: (j['imapPort'] as num?)?.toInt() ?? 993,
        smtpHost: (j['smtpHost'] as String?) ?? '',
        smtpPort: (j['smtpPort'] as num?)?.toInt() ?? 465,
      );

  MailAccount toMailAccount() => MailAccount.fromManualSettings(
        name: name,
        email: email,
        userName: email,
        password: password,
        incomingHost: imapHost,
        incomingPort: imapPort,
        outgoingHost: smtpHost,
        outgoingPort: smtpPort,
        outgoingClientDomain: email.contains('@') ? email.split('@').last : 'localhost',
      );
}

/// 一封邮件的摘要（收件箱列表 / Agent 工具用）
@immutable
class MailItem {
  final int id;
  final String? subject;
  final String? fromName;
  final String? fromEmail;
  final DateTime? date;
  final bool isSeen;

  const MailItem({
    required this.id,
    this.subject,
    this.fromName,
    this.fromEmail,
    this.date,
    this.isSeen = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'subject': subject,
        'fromName': fromName,
        'fromEmail': fromEmail,
        'date': date?.toIso8601String(),
        'isSeen': isSeen,
      };

  String get displayFrom {
    if (fromName != null && fromName!.isNotEmpty) return fromName!;
    return fromEmail ?? '';
  }
}

/// 服务：账号持久化 + IMAP/SMTP 连接操作
class MailService {
  final List<MailAccountConfig> accounts;
  MailService(this.accounts);

  static List<MailAccountConfig> loadFromStorage() {
    return Storage.loadMailAccounts()
        .map(MailAccountConfig.fromJson)
        .where((a) => a.email.isNotEmpty)
        .toList();
  }

  Future<void> saveToStorage() async {
    await Storage.saveMailAccounts(accounts.map((a) => a.toJson()).toList());
  }

  MailClient _buildClient(MailAccountConfig account) => MailClient(
        account.toMailAccount(),
        downloadSizeLimit: 5 * 1024 * 1024,
      );

  /// 拉取收件箱最新 [count] 封邮件的摘要
  Future<List<MailItem>> fetchInbox(MailAccountConfig account, {int count = 30}) async {
    final client = _buildClient(account);
    try {
      await client.selectInbox();
      final msgs = await client.fetchMessages(
        count: count,
        page: 1,
        fetchPreference: FetchPreference.envelope,
      );
      final items = <MailItem>[];
      for (var i = 0; i < msgs.length; i++) {
        final m = msgs[i];
        final from = m.from?.isNotEmpty == true ? m.from!.first : null;
        items.add(MailItem(
          id: i + 1,
          subject: m.decodeSubject(),
          fromName: from?.personalName,
          fromEmail: from?.email,
          date: m.decodeDate(),
          isSeen: m.isSeen,
        ));
      }
      return items;
    } finally {
      await _disposeClient(client);
    }
  }

  /// 读取邮件全文（正文 + 附件信息），Agent 与分析用
  Future<Map<String, dynamic>> fetchMessageDetail(MailAccountConfig account, int id) async {
    final client = _buildClient(account);
    try {
      await client.selectInbox();
      final msgs = await client.fetchMessages(
        count: id + 5,
        page: 1,
        fetchPreference: FetchPreference.bodystructure,
      );
      if (id < 1 || id > msgs.length) throw Exception('邮件不存在');
      final m = msgs[id - 1];
      final full = await client.fetchMessageContents(m, markAsSeen: false);
      final from = full.from?.isNotEmpty == true ? full.from!.first : null;
      final to = (full.to ?? []).map((a) => a.email).join(', ');
      final attachments = <Map<String, dynamic>>[];
      try {
        final info = full.findContentInfo();
        for (final i in info) {
          attachments.add({
            'name': i.fileName ?? i.fetchId,
            'mediaType': i.mediaType?.sub.toString() ?? '',
          });
        }
      } catch (_) {}
      return {
        'id': id,
        'subject': full.decodeSubject(),
        'fromName': from?.personalName,
        'fromEmail': from?.email,
        'to': to,
        'date': full.decodeDate()?.toIso8601String(),
        'text': full.decodeTextPlainPart() ?? '',
        'html': full.decodeTextHtmlPart() ?? '',
        'attachments': attachments,
      };
    } finally {
      await _disposeClient(client);
    }
  }

  /// 发送邮件
  Future<void> sendMail(
    MailAccountConfig account, {
    required String to,
    required String subject,
    required String body,
  }) async {
    final client = _buildClient(account);
    try {
      final recipients = _parseAddresses(to);
      final message = MessageBuilder.buildSimpleTextMessage(
        MailAddress(account.name, account.email),
        recipients,
        body.trim(),
        subject: subject.trim(),
      );
      await client.sendMessage(message);
    } finally {
      await _disposeClient(client);
    }
  }

  List<MailAddress> _parseAddresses(String raw) {
    // 支持 "a@b.com"、"姓名 <a@b.com>"、逗号/分号分隔
    final result = <MailAddress>[];
    for (final seg in raw.split(RegExp(r'[,;]'))) {
      final s = seg.trim();
      if (s.isEmpty) continue;
      final m = RegExp(r'<([^>]+)>').firstMatch(s);
      if (m != null) {
        final email = m.group(1)!.trim();
        final name = s.replaceAll(m.group(0)!, '').replaceAll(RegExp(r'[<>"]'), '').trim();
        result.add(MailAddress(name.isEmpty ? null : name, email));
      } else {
        result.add(MailAddress(null, s));
      }
    }
    return result;
  }

  Future<void> _disposeClient(MailClient client) async {
    try {
      await client.disconnect();
    } catch (_) {}
  }
}