import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/medication.dart';
import '../constants/app_theme.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _defaultReminderMessage =
      'Time to take your medication. Please take it now.';
  static const String _defaultReminderInterval = 'At exact time';
  static const List<String> _reminderIntervals = [
    'At exact time',
    '5 minutes before',
    '10 minutes before',
    '15 minutes before',
    '30 minutes before',
  ];

  final FirebaseService _firebaseService = FirebaseService();
  final NotificationService _notificationService = NotificationService();
  bool enableNotifications = true;
  bool dailyMotivationQuote = true;
  String reminderInterval = _defaultReminderInterval;
  bool _isSavingCustomMessage = false;
  bool _isSavingReminderTiming = false;
  bool _isSendingTestNotification = false;
  final TextEditingController notificationMessageController =
      TextEditingController(text: _defaultReminderMessage);

  @override
  void initState() {
    super.initState();
    _loadSettingsPreferences();
  }

  Future<void> _loadSettingsPreferences() async {
    final user = _firebaseService.getCurrentUser();
    if (user == null) {
      return;
    }

    try {
      final snapshot = await _settingsDocRef(user.uid).get();

      final data = snapshot.data();
      final customMessage = (data?['customReminderMessage'] as String?)?.trim();
      final savedReminderInterval = (data?['reminderInterval'] as String?)
          ?.trim();

      if (!mounted) {
        return;
      }

      if (customMessage != null && customMessage.isNotEmpty) {
        notificationMessageController.text = customMessage;
      }

      if (savedReminderInterval != null &&
          _reminderIntervals.contains(savedReminderInterval)) {
        setState(() {
          reminderInterval = savedReminderInterval;
        });
      }
    } catch (_) {}
  }

  DocumentReference<Map<String, dynamic>> _settingsDocRef(String userId) {
    return _firebaseService.firestore
        .collection('users')
        .doc(userId)
        .collection('settings')
        .doc('preferences');
  }

  Future<void> _saveCustomReminderMessage() async {
    final user = _firebaseService.getCurrentUser();
    if (user == null) {
      return;
    }

    final customMessage = notificationMessageController.text.trim();
    if (customMessage.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a reminder message.')),
      );
      return;
    }

    setState(() => _isSavingCustomMessage = true);

    try {
      await _settingsDocRef(user.uid).set({
        'customReminderMessage': customMessage,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final medicationsSnapshot = await _firebaseService.getUserDocuments(
        'medications',
      );
      final medications = medicationsSnapshot.docs
          .map(
            (doc) => Medication.fromJson(
              doc.data() as Map<String, dynamic>,
              docId: doc.id,
            ),
          )
          .toList();
      await _notificationService.rescheduleMedicationReminders(medications);

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Custom reminder message saved.')),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save message. Try again.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingCustomMessage = false);
      }
    }
  }

  Future<void> _saveReminderTiming() async {
    final user = _firebaseService.getCurrentUser();
    if (user == null) {
      return;
    }

    setState(() => _isSavingReminderTiming = true);

    try {
      await _settingsDocRef(user.uid).set({
        'reminderInterval': reminderInterval,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final medicationsSnapshot = await _firebaseService.getUserDocuments(
        'medications',
      );
      final medications = medicationsSnapshot.docs
          .map(
            (doc) => Medication.fromJson(
              doc.data() as Map<String, dynamic>,
              docId: doc.id,
            ),
          )
          .toList();
      await _notificationService.rescheduleMedicationReminders(
        medications,
        reminderIntervalOverride: reminderInterval,
      );

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Reminder timing saved.')));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save reminder timing.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingReminderTiming = false);
      }
    }
  }

  Future<void> _sendTestNotification() async {
    setState(() => _isSendingTestNotification = true);

    try {
      await _notificationService.requestPermissions();
      final hasPermission = await _notificationService
          .hasNotificationPermission();

      if (!hasPermission) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notification permission is blocked. Please allow it.',
            ),
          ),
        );
        return;
      }

      final customBody = notificationMessageController.text.trim();
      final sent = await _notificationService.sendTestNotification(
        body: customBody.isEmpty ? null : customBody,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sent
                ? 'Test notification sent.'
                : 'Could not send test notification.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to send test notification.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingTestNotification = false);
      }
    }
  }

  @override
  void dispose() {
    notificationMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.veryLightGreen,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Notifications Section
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                    ),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          color: AppColors.darkGreen,
                          size: 20,
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            'Free mode is active. Reminders are client-side only. On web, reminders work while this app tab is open.',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.lightText,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: SwitchListTile(
                      title: const Text('Enable Notifications'),
                      subtitle: const Text(
                        'Get reminders for your medications',
                      ),
                      value: enableNotifications,
                      activeColor: AppColors.primaryGreen,
                      onChanged: (value) {
                        setState(() => enableNotifications = value);
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: const [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.lightGreen,
                              child: Icon(
                                Icons.edit_notifications_rounded,
                                size: 18,
                                color: AppColors.darkGreen,
                              ),
                            ),
                            SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Custom Reminder Message',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.darkText,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'This message appears in your medication alert.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.lightText,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextField(
                          controller: notificationMessageController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            hintText: 'Ex: Time for your medicine 💊',
                            hintStyle: const TextStyle(
                              color: AppColors.lightText,
                              fontSize: 14,
                            ),
                            filled: true,
                            fillColor: AppColors.veryLightGreen,
                            contentPadding: const EdgeInsets.all(AppSpacing.md),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              borderSide: const BorderSide(
                                color: AppColors.borderColor,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              borderSide: const BorderSide(
                                color: AppColors.borderColor,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              borderSide: const BorderSide(
                                color: AppColors.primaryGreen,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton.icon(
                            onPressed: _isSavingCustomMessage
                                ? null
                                : _saveCustomReminderMessage,
                            icon: _isSavingCustomMessage
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_rounded, size: 18),
                            label: Text(
                              _isSavingCustomMessage ? 'Saving...' : 'Save',
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: _isSendingTestNotification
                                ? null
                                : _sendTestNotification,
                            icon: _isSendingTestNotification
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.notifications_active_rounded,
                                    size: 18,
                                  ),
                            label: Text(
                              _isSendingTestNotification
                                  ? 'Sending...'
                                  : 'Test Notification Now',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Wellness Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Wellness',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: SwitchListTile(
                      title: const Text('Daily Motivation Quote'),
                      subtitle: const Text(
                        'Show a short wellness quote each day',
                      ),
                      value: dailyMotivationQuote,
                      activeColor: AppColors.primaryGreen,
                      onChanged: (value) {
                        setState(() => dailyMotivationQuote = value);
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Reminder Section
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reminder Timing',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: DropdownButton<String>(
                      value: reminderInterval,
                      isExpanded: true,
                      underline: const SizedBox(),
                      items: _reminderIntervals
                          .map(
                            (interval) => DropdownMenuItem(
                              value: interval,
                              child: Text(interval),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(
                          () => reminderInterval =
                              value ?? _defaultReminderInterval,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: _isSavingReminderTiming
                          ? null
                          : _saveReminderTiming,
                      icon: _isSavingReminderTiming
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        _isSavingReminderTiming ? 'Saving...' : 'Save',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // About Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'About',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkText,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      title: const Text('Version'),
                      subtitle: const Text('1.0.0'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      title: const Text('Privacy Policy'),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Privacy Policy will open here'),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            // Logout Button
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Logout?'),
                        content: const Text('Are you sure you want to logout?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () async {
                              await FirebaseAuth.instance.signOut();
                              Navigator.of(context).pushNamedAndRemoveUntil(
                                '/welcome',
                                (route) => false,
                              );
                            },
                            child: const Text(
                              'Logout',
                              style: TextStyle(color: AppColors.errorRed),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.logout_rounded),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.errorRed,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  label: const Text('Logout', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
        onTap: (index) {
          if (index == 0) {
            Navigator.of(context).pushNamed('/home');
          } else if (index == 1) {
            Navigator.of(context).pushNamed('/history');
          }
        },
      ),
    );
  }
}
