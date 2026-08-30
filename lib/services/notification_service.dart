import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// 系统通知服务（课程提醒）
///
/// 仅在 **Android / iOS** 生效；桌面端（Windows/macOS/Linux）与 Web 全部安全 no-op，
/// 避免在不支持的平台上调用原生通道导致崩溃。
///
/// ## 为什么用"系统级定时通知"而不是 Dart Timer
/// 需求是"App 在后台时也要弹窗"。但 App 进入后台后：
/// - iOS 会冻结甚至回收进程，Dart `Timer` 不会执行；
/// - Android 的后台 Timer 同样会被 Doze / 厂商省电策略限制。
/// 因此正确做法是：**App 在前台时，把当天所有提醒一次性调度给操作系统**
/// （`zonedSchedule`），之后由系统在指定时刻弹出通知，
/// 即使 App 进程已被杀死也能按时弹出——与 QQ/微信的本地提醒机制一致。
///
/// ## 时区坑（已规避）
/// `timezone` 包在 Flutter 上 `initializeTimeZones()` 之后，
/// `tz.local` **并不等于设备真实时区**（它需要额外依赖 `flutter_native_timezone`
/// 才能拿到系统时区，否则默认 UTC）。若直接用 `TZDateTime.from(localTime, tz.local)`，
/// 中国用户（UTC+8）的通知会**晚 8 小时**才弹。
/// 本实现统一把本地时间转成 UTC 绝对时刻传入（`localTime.toUtc()` + `tz.UTC`），
/// 不依赖 `tz.local`，无需额外依赖，也不会出现时区偏移。
///
/// ## 注意：flutter_local_notifications 22.x 全部为命名参数
/// 老教程里的 `show(0, 'title', 'body', details)` 位置参数写法在 22.x 已失效。
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  // ===== 通知渠道（Android 8+ 必须；iOS 忽略）=====
  static const String _channelId = 'class_reminder';
  static const String _channelName = '课程提醒';
  static const String _channelDesc = '下节课即将开始的提醒通知';

  /// 通知 id 基数：避免与将来其它类型通知冲突
  static const int _idBase = 50000;

  /// 点击通知时回传的 payload（用于跳转到课程表页）
  static const String payloadTimetable = 'timetable';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _inited = false;

  /// 当前平台是否支持系统通知（仅移动端真机）
  bool get supported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 通知点击回调：由外部注册（例如跳到课程表页 / 把窗口提到前台）
  void Function(String? payload)? onTap;

  /// 统一的通知样式
  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          playSound: true,
          enableVibration: true,
          // 点击后自动从通知中心清除，与 QQ/微信消息行为一致
          autoCancel: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

  /// 初始化通知插件与渠道
  ///
  /// 可重复调用；桌面端直接返回。
  Future<void> init() async {
    if (!supported || _inited) return;

    tz_data.initializeTimeZones();

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (resp) => onTap?.call(resp.payload),
    );
    _inited = true;
  }

  /// 请求通知权限
  ///
  /// - Android 13+（API 33）需要运行时 `POST_NOTIFICATIONS` 权限
  /// - iOS 首次会弹出系统授权框
  /// 返回是否已授权（桌面端返回 false）
  Future<bool> requestPermission() async {
    if (!supported) return false;
    if (!_inited) await init();
    if (!_inited) return false;

    if (Platform.isAndroid) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? false;
    }
    if (Platform.isIOS) {
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return false;
  }

  /// 调度一条定时通知（系统级，App 被杀也能弹）
  ///
  /// [id] 相同则覆盖已有调度，重复调用不会堆叠。
  /// [localTime] 为**设备本地时间**；过去的时间会被忽略。
  Future<void> schedule({
    required int id,
    required DateTime localTime,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!supported || !_inited) return;
    // 已过去的时间点不调度（避免立刻弹出一条过期提醒）
    if (!localTime.isAfter(DateTime.now())) return;

    // 转成 UTC 绝对时刻，绕开 tz.local 在 Flutter 上不准确的问题
    final utc = tz.TZDateTime.from(localTime.toUtc(), tz.UTC);

    try {
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: utc,
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (_) {
      // 设备未授予 SCHEDULE_EXACT_ALARM（Android 12+ 用户可关闭）时，
      // 精确调度会抛异常 —— 降级为"允许延迟的不精确调度"，保证提醒仍能到达
      try {
        await _plugin.zonedSchedule(
          id: id,
          title: title,
          body: body,
          scheduledDate: utc,
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      } catch (_) {
        // 仍失败则静默放弃，不能因为通知问题影响主流程
      }
    }
  }

  /// 立即弹一条通知（用于"测试提醒"入口与调试）
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!supported || !_inited) return;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details,
      payload: payload,
    );
  }

  /// 取消指定 id 的调度通知
  Future<void> cancel(int id) async {
    if (!supported || !_inited) return;
    await _plugin.cancel(id: id);
  }

  /// 取消全部通知（课程表清空 / 关闭提醒开关时调用）
  Future<void> cancelAll() async {
    if (!supported || !_inited) return;
    await _plugin.cancelAll();
  }

  /// 生成稳定的通知 id：同一门课同一天始终映射到同一个 id，
  /// 这样重复调度只会覆盖，不会堆积重复通知。
  static int idFor(int weekday, int startPeriod) =>
      _idBase + weekday * 100 + startPeriod;
}
