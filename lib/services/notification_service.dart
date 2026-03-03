import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'web_notification_helper_stub.dart'
    if (dart.library.html) 'web_notification_helper_web.dart';

import '../models/medication.dart';
import 'firebase_service.dart';

class NotificationService {
  NotificationService._internal();

  static const String _defaultReminderInterval = 'At exact time';
  static const Set<String> _supportedReminderIntervals = {
    'At exact time',
    '5 minutes before',
    '10 minutes before',
    '15 minutes before',
    '30 minutes before',
  };
  static const Duration _webReminderTriggerWindow = Duration(minutes: 1);

  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseService _firebaseService = FirebaseService();
  Timer? _webReminderTimer;
  bool _webReminderCheckInProgress = false;

  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    if (kIsWeb) {
      await requestPermissions();
      _startWebReminderLoop();
      _isInitialized = true;
      return;
    }

    tz.initializeTimeZones();

    try {
      final timezoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {}

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
    );

    await _plugin.initialize(initializationSettings);
    await requestPermissions();

    _isInitialized = true;
  }

  void _startWebReminderLoop() {
    _webReminderTimer?.cancel();
    _webReminderTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _runWebReminderCheck(),
    );
    unawaited(_runWebReminderCheck());
  }

  Future<void> _runWebReminderCheck() async {
    if (!kIsWeb || _webReminderCheckInProgress) {
      return;
    }

    if (_firebaseService.getCurrentUser() == null) {
      return;
    }

    _webReminderCheckInProgress = true;
    try {
      final snapshot = await _firebaseService.getUserDocuments('medications');
      final medications = snapshot.docs
          .map(
            (doc) => Medication.fromJson(
              doc.data() as Map<String, dynamic>,
              docId: doc.id,
            ),
          )
          .toList();

      await notifyDueMedicationsOnWeb(medications);
    } catch (_) {
      // no-op: web reminder checks should never crash the app loop
    } finally {
      _webReminderCheckInProgress = false;
    }
  }

  Future<void> requestPermissions() async {
    if (kIsWeb) {
      await requestBrowserNotificationPermission();
      return;
    }

    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidImplementation?.requestNotificationsPermission();

    final iosImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    await iosImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );

    final macOsImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    await macOsImplementation?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<bool> hasNotificationPermission() async {
    if (kIsWeb) {
      return canShowBrowserNotifications();
    }

    final androidImplementation = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final androidEnabled = await androidImplementation
        ?.areNotificationsEnabled();

    if (androidEnabled != null) {
      return androidEnabled;
    }

    return true;
  }

  Future<bool> sendTestNotification({
    String title = 'Medication Reminder (Test)',
    String? body,
  }) async {
    await initialize();

    final messageBody = (body?.trim().isNotEmpty ?? false)
        ? body!.trim()
        : await _getReminderMessageBody();

    if (kIsWeb) {
      return showBrowserNotification(title: title, body: messageBody);
    }

    const notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'medialert_medication_channel',
        'Medication Reminders',
        channelDescription: 'Daily medication reminder notifications',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      messageBody,
      notificationDetails,
    );

    return true;
  }

  Future<void> scheduleMedicationReminder(
    Medication medication, {
    String? reminderIntervalOverride,
  }) async {
    if (kIsWeb || medication.id.isEmpty) {
      return;
    }

    if (!medication.notificationsEnabled || !medication.isActive) {
      await cancelMedicationReminder(medication.id);
      return;
    }

    await initialize();

    final reminderInterval = reminderIntervalOverride == null
        ? await _getUserReminderInterval()
        : _normalizeReminderInterval(reminderIntervalOverride);
    final reminderBody = await _getReminderMessageBody();
    final scheduledDate = _nextReminderDateTimeForMedication(
      medication.time,
      reminderInterval,
    );

    const notificationDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'medialert_medication_channel',
        'Medication Reminders',
        channelDescription: 'Daily medication reminder notifications',
        importance: Importance.max,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      _notificationIdForMedication(medication.id),
      'Medication Reminder',
      reminderBody,
      scheduledDate,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: medication.id,
    );
  }

  Future<void> cancelMedicationReminder(String medicationId) async {
    if (kIsWeb || medicationId.isEmpty) {
      return;
    }

    await initialize();
    await _plugin.cancel(_notificationIdForMedication(medicationId));
  }

  Future<void> clearReminderStateOnLogout() async {
    if (kIsWeb) {
      removeBrowserStorageByPrefix('web_notified_');
      return;
    }

    await initialize();
    await _plugin.cancelAll();
  }

  Future<void> rescheduleMedicationReminders(
    Iterable<Medication> medications, {
    String? reminderIntervalOverride,
  }) async {
    for (final medication in medications) {
      await scheduleMedicationReminder(
        medication,
        reminderIntervalOverride: reminderIntervalOverride,
      );
    }
  }

  Future<void> notifyDueMedicationsOnWeb(List<Medication> medications) async {
    if (!kIsWeb || medications.isEmpty) {
      return;
    }

    await initialize();
    if (!await canShowBrowserNotifications()) {
      return;
    }

    final now = DateTime.now();
    final reminderOffset = _reminderOffset(await _getUserReminderInterval());
    final reminderBody = await _getReminderMessageBody();

    for (final medication in medications) {
      if (!medication.isActive ||
          !medication.notificationsEnabled ||
          medication.id.isEmpty) {
        continue;
      }

      if (medication.lastTaken != null &&
          _isSameDay(medication.lastTaken!, now)) {
        continue;
      }

      final parsed = _parseHourMinute(medication.time);
      final scheduledForToday = DateTime(
        now.year,
        now.month,
        now.day,
        parsed.$1,
        parsed.$2,
      ).subtract(reminderOffset);

      if (now.isBefore(scheduledForToday)) {
        continue;
      }

      if (now.difference(scheduledForToday) > _webReminderTriggerWindow) {
        continue;
      }

      final storageKey = _webStorageKey(
        medicationId: medication.id,
        now: now,
        scheduledForToday: scheduledForToday,
        reminderOffset: reminderOffset,
      );
      if (getBrowserStorageItem(storageKey) == '1') {
        continue;
      }

      final didShow = await showBrowserNotification(
        title: 'Medication Reminder',
        body: reminderBody,
      );
      if (didShow) {
        setBrowserStorageItem(storageKey, '1');
      }
    }
  }

  Future<Duration?> nextWebReminderDelay(List<Medication> medications) async {
    if (!kIsWeb || medications.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final reminderOffset = _reminderOffset(await _getUserReminderInterval());
    DateTime? nextScheduled;

    for (final medication in medications) {
      if (!medication.isActive ||
          !medication.notificationsEnabled ||
          medication.id.isEmpty) {
        continue;
      }

      if (medication.lastTaken != null &&
          _isSameDay(medication.lastTaken!, now)) {
        continue;
      }

      final parsed = _parseHourMinute(medication.time);
      final scheduledForToday = DateTime(
        now.year,
        now.month,
        now.day,
        parsed.$1,
        parsed.$2,
      ).subtract(reminderOffset);

      final storageKey = _webStorageKey(
        medicationId: medication.id,
        now: now,
        scheduledForToday: scheduledForToday,
        reminderOffset: reminderOffset,
      );
      final alreadyNotified = getBrowserStorageItem(storageKey) == '1';

      if (alreadyNotified) {
        continue;
      }

      if (!now.isBefore(scheduledForToday) &&
          now.difference(scheduledForToday) <= _webReminderTriggerWindow) {
        return Duration.zero;
      }

      final nextCandidate = now.isBefore(scheduledForToday)
          ? scheduledForToday
          : scheduledForToday.add(const Duration(days: 1));

      if (nextScheduled == null || nextCandidate.isBefore(nextScheduled)) {
        nextScheduled = nextCandidate;
      }
    }

    if (nextScheduled == null) {
      return null;
    }

    final delay = nextScheduled.difference(now);
    if (delay.isNegative) {
      return Duration.zero;
    }

    return delay;
  }

  Future<String> _getReminderMessageBody() async {
    final user = _firebaseService.getCurrentUser();
    final userName = _resolveUserName(user?.displayName, user?.email);
    final fallbackMessage =
        'Your health is calling... Pick up with your meds $userName';

    if (user == null) {
      return fallbackMessage;
    }

    try {
      final snapshot = await _firebaseService.firestore
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('preferences')
          .get();

      final customMessage =
          (snapshot.data()?['customReminderMessage'] as String?)?.trim();
      if (customMessage != null && customMessage.isNotEmpty) {
        return customMessage;
      }
    } catch (_) {}

    return fallbackMessage;
  }

  String _resolveUserName(String? displayName, String? email) {
    final trimmedDisplayName = displayName?.trim();
    if (trimmedDisplayName != null && trimmedDisplayName.isNotEmpty) {
      return trimmedDisplayName;
    }

    final trimmedEmail = email?.trim();
    if (trimmedEmail != null && trimmedEmail.isNotEmpty) {
      final username = trimmedEmail.split('@').first.trim();
      if (username.isNotEmpty) {
        return username;
      }
    }

    return 'there';
  }

  int _notificationIdForMedication(String medicationId) {
    return medicationId.hashCode & 0x7fffffff;
  }

  tz.TZDateTime _nextDateTimeForMedication(String timeValue) {
    final parsed = _parseHourMinute(timeValue);
    final now = tz.TZDateTime.now(tz.local);

    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      parsed.$1,
      parsed.$2,
    );

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  tz.TZDateTime _nextReminderDateTimeForMedication(
    String timeValue,
    String reminderInterval,
  ) {
    final now = tz.TZDateTime.now(tz.local);
    final offset = _reminderOffset(reminderInterval);
    var scheduled = _nextDateTimeForMedication(timeValue).subtract(offset);

    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    return scheduled;
  }

  Duration _reminderOffset(String reminderInterval) {
    final normalized = _normalizeReminderInterval(
      reminderInterval,
    ).toLowerCase();
    if (normalized == 'at exact time') {
      return Duration.zero;
    }

    final minuteMatch = RegExp(
      r'^(\d+)\s+minutes?\s+before$',
    ).firstMatch(normalized);
    if (minuteMatch != null) {
      final minutes = int.tryParse(minuteMatch.group(1)!);
      if (minutes != null && minutes > 0) {
        return Duration(minutes: minutes);
      }
    }

    return Duration.zero;
  }

  Future<String> _getUserReminderInterval() async {
    final user = _firebaseService.getCurrentUser();
    if (user == null) {
      return _defaultReminderInterval;
    }

    try {
      final snapshot = await _firebaseService.firestore
          .collection('users')
          .doc(user.uid)
          .collection('settings')
          .doc('preferences')
          .get();

      final interval = snapshot.data()?['reminderInterval'] as String?;
      return _normalizeReminderInterval(interval);
    } catch (_) {
      return _defaultReminderInterval;
    }
  }

  String _normalizeReminderInterval(String? interval) {
    final normalized = interval?.trim();
    if (normalized == null ||
        normalized.isEmpty ||
        !_supportedReminderIntervals.contains(normalized)) {
      return _defaultReminderInterval;
    }

    return normalized;
  }

  (int, int) _parseHourMinute(String timeValue) {
    final value = timeValue.replaceAll(RegExp(r'[\u00A0\u202F]'), ' ').trim();

    final amPm = RegExp(
      r'^(\d{1,2}):(\d{1,2})\s*([AaPp])\.?\s*([Mm])\.?$',
    ).firstMatch(value);
    if (amPm != null) {
      var hour = int.parse(amPm.group(1)!);
      final minute = int.parse(amPm.group(2)!);
      final period = '${amPm.group(3)}${amPm.group(4)}'.toUpperCase();

      if (period == 'PM' && hour < 12) {
        hour += 12;
      } else if (period == 'AM' && hour == 12) {
        hour = 0;
      }

      return (hour.clamp(0, 23), minute.clamp(0, 59));
    }

    final twentyFour = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(value);
    if (twentyFour != null) {
      final hour = int.parse(twentyFour.group(1)!);
      final minute = int.parse(twentyFour.group(2)!);
      return (hour.clamp(0, 23), minute.clamp(0, 59));
    }

    return (9, 0);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _todayKey(DateTime now) {
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _webStorageKey({
    required String medicationId,
    required DateTime now,
    required DateTime scheduledForToday,
    required Duration reminderOffset,
  }) {
    final scheduleFingerprint =
        '${scheduledForToday.hour.toString().padLeft(2, '0')}:${scheduledForToday.minute.toString().padLeft(2, '0')}_${reminderOffset.inMinutes}';
    return 'web_notified_${medicationId}_${_todayKey(now)}_$scheduleFingerprint';
  }
}
