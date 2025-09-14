import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'storage_service.dart';

class PushNotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // Keys for storage
  static const String _pushAssistEnabledKey = 'push_assist_enabled';
  
  // Vibration pattern for notifications - distinct triple vibration
  static final Int64List _vibrationPattern = Int64List(6)
    ..[0] = 0      // Start delay
    ..[1] = 300    // Buzz 1
    ..[2] = 200    // Pause 1
    ..[3] = 300    // Buzz 2
    ..[4] = 200    // Pause 2
    ..[5] = 300;   // Buzz 3

  static Future<void> initialize() async {
    if (_initialized) return;

    // Initialize timezone database
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Create notification channels with proper vibration settings
    await _createNotificationChannels();

    _initialized = true;
  }

  static Future<void> _createNotificationChannels() async {
    // PushAssist channel with vibration
    const pushAssistChannel = AndroidNotificationChannel(
      'push_assist_channel',
      'PushAssist Benachrichtigungen',
      description: 'Benachrichtigungen vor Schulstunden',
      importance: Importance.high,
      enableVibration: true,
      enableLights: true,
      playSound: true,
    );

    // Test channel with vibration
    const testChannel = AndroidNotificationChannel(
      'test_channel',
      'Test Benachrichtigungen',
      description: 'Test Benachrichtigung für PushAssist',
      importance: Importance.high,
      enableVibration: true,
      enableLights: true,
      playSound: true,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(pushAssistChannel);

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(testChannel);

    debugPrint('Notification channels created with vibration enabled');
  }

  static void _onNotificationTapped(NotificationResponse response) {
    // Handle notification tap - could navigate to specific page
    debugPrint('Notification tapped: ${response.payload}');
  }

  // Request permissions for notifications
  static Future<bool> requestPermissions() async {
    if (!_initialized) await initialize();

    if (Platform.isAndroid) {
      // Request basic notification permission
      final androidPermission = await Permission.notification.request();

      // For Android 12+, also request exact alarm permission
      if (androidPermission.isGranted) {
        try {
          final exactAlarmPermission = await Permission.scheduleExactAlarm.request();
          if (!exactAlarmPermission.isGranted) {
            debugPrint('⚠️ Exact alarm permission denied - notifications may be delayed');
          }
        } catch (e) {
          debugPrint('⚠️ Failed to request exact alarm permission: $e');
        }
      }

      return androidPermission.isGranted;
    } else if (Platform.isIOS) {
      final result = await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      return result ?? false;
    }
    return true;
  }

  // Check if permissions are granted
  static Future<bool> arePermissionsGranted() async {
    if (Platform.isAndroid) {
      final basicPermission = await Permission.notification.isGranted;

      // Check exact alarm permission for Android 12+
      try {
        final exactAlarmPermission = await Permission.scheduleExactAlarm.isGranted;
        if (!exactAlarmPermission) {
          debugPrint('⚠️ Exact alarm permission not granted - notifications may be inexact');
        }
        return basicPermission; // Return basic permission status
      } catch (e) {
        debugPrint('⚠️ Could not check exact alarm permission: $e');
        return basicPermission;
      }
    } else if (Platform.isIOS) {
      final result = await _notifications
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.checkPermissions();
      return result?.isEnabled ?? false;
    }
    return true;
  }

  // PushAssist specific settings
  static Future<void> setPushAssistEnabled(bool enabled) async {
    final storage = FlutterSecureStorage();
    await storage.write(
      key: _pushAssistEnabledKey, 
      value: enabled.toString(),
    );
    
    if (!enabled) {
      // Cancel all scheduled notifications when disabled
      await cancelAllNotifications();
    }
  }

  static Future<bool> isPushAssistEnabled() async {
    final storage = FlutterSecureStorage();
    final value = await storage.read(key: _pushAssistEnabledKey);
    return value?.toLowerCase() == 'true'; // Default to false
  }

  // Schedule a notification for a specific agenda item
  static Future<void> scheduleAgendaNotification({
    required int id,
    required String subject,
    required String room,
    required String teacher,
    required DateTime startTime,
  }) async {
    if (!_initialized) await initialize();
    
    // Check if general notifications are enabled
    if (!await StorageService.getPushNotificationsEnabled()) return;
    
    // Check if agenda notifications are specifically enabled
    final agendaEnabled = await StorageService.getNotificationEnabled('agenda') ?? true;
    if (!agendaEnabled) return;

    // Check if permissions are granted
    if (!await arePermissionsGranted()) return;

    // Get advance time from settings (default 2 minutes)
    final advanceMinutes = await StorageService.getNotificationAdvanceMinutes() ?? 2;
    final notificationTime = startTime.subtract(Duration(minutes: advanceMinutes));
    
    // Don't schedule notifications for past events
    if (notificationTime.isBefore(DateTime.now())) return;

    final androidDetails = AndroidNotificationDetails(
      'push_assist_channel',
      'PushAssist Benachrichtigungen',
      channelDescription: 'Benachrichtigungen vor Schulstunden',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      vibrationPattern: _vibrationPattern,
      icon: '@mipmap/ic_launcher',
      category: AndroidNotificationCategory.alarm,
      timeoutAfter: 30000, // Show for 30 seconds
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final title = 'Nächste Stunde: $subject';
    final body = 'Raum: $room${teacher.isNotEmpty ? ' • Lehrer: $teacher' : ''}';

    try {
      await _notifications.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(notificationTime, tz.local),
        notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );

      debugPrint('Scheduled notification for $subject at ${notificationTime.toString()}');
    } catch (e) {
      // If exact scheduling fails, try with inexact scheduling
      if (e.toString().contains('exact_alarms_not_permitted')) {
        debugPrint('⚠️ Exact alarms not permitted, trying inexact scheduling for $subject');
        try {
          await _notifications.zonedSchedule(
            id,
            title,
            body,
            tz.TZDateTime.from(notificationTime, tz.local),
            notificationDetails,
            androidScheduleMode: AndroidScheduleMode.alarmClock,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          debugPrint('✅ Scheduled (inexact) notification for $subject');
        } catch (e2) {
          debugPrint('❌ Failed to schedule notification for $subject: $e2');
          rethrow;
        }
      } else {
        debugPrint('❌ Failed to schedule notification for $subject: $e');
        rethrow;
      }
    }
  }

  // Schedule notifications for multiple agenda items
  static Future<void> scheduleAgendaNotifications(List<dynamic> agendaItems) async {
    debugPrint('📅 Starting to schedule ${agendaItems.length} agenda notifications...');

    // Check if general notifications are enabled
    if (!await StorageService.getPushNotificationsEnabled()) {
      debugPrint('⏭️ Push notifications disabled - skipping scheduling');
      return;
    }

    // Check if agenda notifications are specifically enabled
    final agendaEnabled = await StorageService.getNotificationEnabled('agenda') ?? true;
    if (!agendaEnabled) {
      debugPrint('⏭️ Agenda notifications disabled - skipping scheduling');
      return;
    }

    // Cancel existing notifications first
    await cancelAllNotifications();

    int notificationId = 1000; // Start with a high number to avoid conflicts
    int scheduledCount = 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final item in agendaItems) {
      try {
        final startDateStr = item.startDate?.toString() ?? '';
        if (startDateStr.isEmpty) {
          debugPrint('⚠️ Skipping agenda item with empty start date');
          continue;
        }

        final startDateTime = DateTime.tryParse(startDateStr);
        if (startDateTime == null) {
          debugPrint('⚠️ Failed to parse date: $startDateStr');
          continue;
        }

        // Only schedule for today and future dates
        if (startDateTime.isBefore(today)) {
          debugPrint('⏭️ Skipping past event: ${item.text} at $startDateStr');
          continue;
        }

        // Get advance time from settings (default 2 minutes)
        final advanceMinutes = await StorageService.getNotificationAdvanceMinutes() ?? 2;
        final notificationTime = startDateTime.subtract(Duration(minutes: advanceMinutes));

        // Don't schedule notifications for events that would notify in the past
        if (notificationTime.isBefore(now)) {
          debugPrint('⏭️ Notification time is in the past for: ${item.text}');
          continue;
        }

        // Get teacher names if available
        final teachers = item.teachers as List<dynamic>? ?? [];
        final teacherStr = teachers.isNotEmpty ? teachers.first.toString() : '';

        await scheduleAgendaNotification(
          id: notificationId++,
          subject: item.text?.toString() ?? 'Unbekannt',
          room: item.roomToken?.toString() ?? 'Unbekannt',
          teacher: teacherStr,
          startTime: startDateTime,
        );

        scheduledCount++;
        debugPrint('✅ Scheduled: ${item.text} at ${startDateTime.toString()}');
      } catch (e) {
        // Continue with other notifications even if one fails
        if (e.toString().contains('exact_alarms_not_permitted')) {
          debugPrint('⚠️ Exact alarm permission issue for: ${item.text}');
        } else {
          debugPrint('❌ Error scheduling notification for agenda item: $e');
          debugPrint('   Item data: ${item.toString()}');
        }
      }
    }

    debugPrint('🎯 Successfully scheduled $scheduledCount notifications out of ${agendaItems.length} agenda items');
  }

  // Cancel all notifications
  static Future<void> cancelAllNotifications() async {
    if (!_initialized) await initialize();
    await _notifications.cancelAll();
    debugPrint('All notifications cancelled');
  }

  // Cancel a specific notification
  static Future<void> cancelNotification(int id) async {
    if (!_initialized) await initialize();
    await _notifications.cancel(id);
  }

  // Get pending notifications (for debugging)
  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    if (!_initialized) await initialize();
    return await _notifications.pendingNotificationRequests();
  }

  // Show a test notification
  static Future<void> showTestNotification() async {
    if (!_initialized) await initialize();

    debugPrint('🔔 Showing test notification...');

    final androidDetails = AndroidNotificationDetails(
      'test_channel',
      'Test Benachrichtigungen',
      channelDescription: 'Test Benachrichtigung für PushAssist',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      vibrationPattern: _vibrationPattern,
      ticker: 'Test Notification',
      autoCancel: true,
      ongoing: false,
      category: AndroidNotificationCategory.alarm,
      timeoutAfter: 10000, // Show for 10 seconds
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    try {
      await _notifications.show(
        0,
        '🔔 PushAssist Vibration Test',
        'Diese Benachrichtigung sollte vibrieren! Prüfen Sie Ihre Geräteeinstellungen falls nicht.',
        notificationDetails,
      );
      debugPrint('✅ Test notification shown successfully');
    } catch (e) {
      debugPrint('❌ Failed to show test notification: $e');
    }
  }
}