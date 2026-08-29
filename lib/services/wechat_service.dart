/// 微信 ClawBot 接入（weixin_clawbot 包）：
/// 扫码绑定 → 长轮询收消息 → 交给 agent 自动应答 → sendText 回复微信。
///
/// 速率限制约 7 条 / 5 分钟（SendResult.error 含 "-2" 为限频，等 5–10 秒重试；
/// "-14" 表示会话过期需重新扫码绑定）。前置要求：OpenClaw 微信插件已完成一次
/// 命令行登录（npx -y @tencent-weixin/openclaw-weixin-cli@latest install）。
library;

import 'dart:async';

import 'package:flutter/widgets.dart' show BuildContext;
import 'package:weixin_clawbot/weixin_clawbot.dart';

import 'storage.dart';

class WeChatService {
  WeChatService._();
  static final WeixinClawbot _bot = WeixinClawbot();

  static ClawBotAccount? account;
  static bool bound = false;
  static bool autoReply = false;
  static String? lastError;

  static StreamSubscription<WeixinMessage>? _sub;

  /// R35: 收到微信消息时的处理器（由 AppState 注入：跑 agent 并返回回复文本）
  static Future<String?> Function(String text)? onIncoming;

  /// 扫码绑定（[context] 提供扫码弹窗；已绑定过则直接恢复账号并连接）
  static Future<bool> bind({BuildContext? context}) async {
    try {
      account = context != null ? await showQrLoginDialog(context: context, clawbot: _bot) : null;
      account ??= await _bot.loadAccount();
      if (account == null) {
        lastError = '未完成扫码绑定';
        return false;
      }
      await connect();
      lastError = null;
      Storage.saveWeChatBound(true);
      return true;
    } catch (e) {
      lastError = '$e';
      return false;
    }
  }

  /// 启动长轮询：收到的用户消息经 onIncoming 跑 agent，回复回传微信
  static Future<void> connect() async {
    final acc = account;
    if (acc == null) return;
    await _sub?.cancel();
    _sub = _bot.connect(acc).listen((msg) {
      if (!msg.isFromUser) return;
      final text = (msg.textContent ?? '').trim();
      if (text.isEmpty || !autoReply) return;
      final from = msg.fromUserId;
      onIncoming?.call(text)?.then((reply) {
        if (reply != null && reply.isNotEmpty) send(reply, to: from);
      });
    });
    bound = true;
  }

  static Future<void> send(String text, {String? to}) async {
    if (account == null) return;
    final r = await _bot.sendText(text: text, toUserId: to ?? account!.defaultTo);
    if (!r.ok) lastError = r.error;
  }

  static void unbind() {
    _sub?.cancel();
    _sub = null;
    try {
      _bot.disconnect(account?.id ?? '');
      _bot.logout();
    } catch (_) {}
    bound = false;
    account = null;
    autoReply = false;
    Storage.saveWeChatBound(false);
    Storage.saveWeChatAutoReply(false);
  }

  static void dispose() {
    _sub?.cancel();
    _bot.dispose();
  }
}
