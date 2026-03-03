import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/medication.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../constants/app_theme.dart';

class _MedicationDisplayItem {
  final Medication medication;
  final DateTime scheduledDate;
  final bool isMissed;

  const _MedicationDisplayItem({
    required this.medication,
    required this.scheduledDate,
    required this.isMissed,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final NotificationService _notificationService = NotificationService();
  List<Medication> medications = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureNotificationPermission();
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _markMedicationAsTaken(
    Medication med, {
    required DateTime scheduledDate,
    required bool wasMissed,
  }) async {
    final TextEditingController notesController = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark as taken'),
        content: TextField(
          controller: notesController,
          decoration: const InputDecoration(
            labelText: 'Notes (optional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, notesController.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return; // cancelled

    try {
      final now = DateTime.now();
      final logData = {
        'medicationId': med.id,
        'medicationName': med.name,
        'takenAt': now.toIso8601String(),
        'notes': result,
        'scheduledFor': scheduledDate.toIso8601String(),
        'wasMissed': wasMissed,
      };
      await _firebaseService.addUserDocument('takenLogs', logData);
      // persist lastTaken on medication document
      if (med.id.isNotEmpty) {
        await _firebaseService.updateUserDocument('medications', med.id, {
          'lastTaken': now.toIso8601String(),
        });
      }
      // update local list to reflect persisted lastTaken
      setState(() {
        final i = medications.indexWhere((m) => m.id == med.id);
        if (i != -1) {
          medications[i] = medications[i].copyWith(lastTaken: now);
        }
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Marked as taken')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error marking taken: $e')));
    }
  }

  bool _isTakenToday(DateTime? lastTaken) {
    if (lastTaken == null) return false;
    return _isSameDay(lastTaken, DateTime.now());
  }

  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Future<void> _ensureNotificationPermission() async {
    final hasPermission = await _notificationService
        .hasNotificationPermission();
    if (hasPermission || !mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Enable notifications to receive medication alerts.',
        ),
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Enable',
          onPressed: () async {
            await _notificationService.requestPermissions();
            final granted = await _notificationService
                .hasNotificationPermission();
            if (!mounted) {
              return;
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  granted
                      ? 'Notifications enabled.'
                      : 'Notification permission still blocked. Please allow it in browser/app settings.',
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatMedicationTime(String timeValue) {
    final value = timeValue.trim();

    final amPmMatch = RegExp(
      r'^(\d{1,2}):(\d{1,2})\s*([AaPp][Mm])$',
    ).firstMatch(value);
    if (amPmMatch != null) {
      final hour = int.tryParse(amPmMatch.group(1) ?? '') ?? 0;
      final minute = int.tryParse(amPmMatch.group(2) ?? '') ?? 0;
      final period = (amPmMatch.group(3) ?? 'AM').toUpperCase();
      return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    }

    final twentyFourMatch = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(value);
    if (twentyFourMatch != null) {
      final hour24 = int.tryParse(twentyFourMatch.group(1) ?? '') ?? 0;
      final minute = int.tryParse(twentyFourMatch.group(2) ?? '') ?? 0;
      final period = hour24 >= 12 ? 'PM' : 'AM';
      final hour12 = (hour24 % 12 == 0) ? 12 : hour24 % 12;
      return '${hour12.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')} $period';
    }

    return timeValue;
  }

  List<_MedicationDisplayItem> _getTodayMedicationItems() {
    final today = _startOfDay(DateTime.now());
    final items = <_MedicationDisplayItem>[];

    for (final med in medications) {
      if (!med.isActive) {
        continue;
      }

      final createdDay = _startOfDay(med.createdAt);
      if (createdDay.isAfter(today)) {
        continue;
      }

      final lastTakenDay = med.lastTaken != null
          ? _startOfDay(med.lastTaken!)
          : null;

      // Already taken today -> should be in History, not in Today's Medication.
      if (lastTakenDay != null && _isSameDay(lastTakenDay, today)) {
        continue;
      }

      final nextDueDate = lastTakenDay == null
          ? createdDay
          : lastTakenDay.add(const Duration(days: 1));

      if (nextDueDate.isAfter(today)) {
        continue;
      }

      final isMissed = nextDueDate.isBefore(today);
      final scheduledDate = nextDueDate;

      items.add(
        _MedicationDisplayItem(
          medication: med,
          scheduledDate: scheduledDate,
          isMissed: isMissed,
        ),
      );
    }

    items.sort((a, b) {
      if (a.isMissed != b.isMissed) {
        return a.isMissed ? 1 : -1;
      }
      return a.scheduledDate.compareTo(b.scheduledDate);
    });

    return items;
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _getAccountName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return 'Friend';
    }

    final displayName = user.displayName?.trim();
    if (displayName != null && displayName.isNotEmpty) {
      return displayName;
    }

    final email = user.email?.trim();
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }

    return 'Friend';
  }

  Stream<List<Medication>> _medicationStream() async* {
    await for (final snapshot in _firebaseService.streamUserDocuments(
      'medications',
    )) {
      final items = <Medication>[];
      for (final doc in snapshot.docs) {
        try {
          items.add(
            Medication.fromJson(
              doc.data() as Map<String, dynamic>,
              docId: doc.id,
            ),
          );
        } catch (e) {
          debugPrint('Skipping invalid medication ${doc.id}: $e');
        }
      }

      yield items;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.veryLightGreen,
      appBar: AppBar(
        title: Text(
          'Today\'s Medication',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
      ),
      body: StreamBuilder<List<Medication>>(
        stream: _medicationStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            final errorText = error.toString().toLowerCase();
            final isPermissionDenied =
                (error is FirebaseException &&
                    error.code == 'permission-denied') ||
                errorText.contains('permission-denied') ||
                errorText.contains('insufficient permissions');

            if (isPermissionDenied) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 48,
                        color: AppColors.lightText,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const Text(
                        'Please sign in again to load your medications.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.darkText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      const Text(
                        'Your data is protected and only available to your account.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.lightText),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(
                            context,
                          ).pushNamedAndRemoveUntil('/auth', (route) => false);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryGreen,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Go to Sign In'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Could not load medications right now. Please try again.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.darkText),
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            );
          }

          medications = snapshot.data!;

          final todayItems = _getTodayMedicationItems();

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Greeting Section
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.darkText,
                                ),
                                children: [
                                  TextSpan(
                                    text:
                                        '${_getGreeting()}, ${_getAccountName()} ',
                                  ),
                                  const WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Icon(
                                      Icons.sentiment_satisfied_alt_rounded,
                                      size: 22,
                                      color: AppColors.darkGreen,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Row(
                        children: [
                          const Icon(
                            Icons.event_note_rounded,
                            size: 16,
                            color: AppColors.lightText,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            'Today - ${DateTime.now().day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][DateTime.now().month - 1]}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.lightText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                          vertical: AppSpacing.sm,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome_rounded,
                              size: 18,
                              color: AppColors.darkGreen,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              'Stay on track today ✨',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.darkText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Medications List or Empty State
                if (todayItems.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.xl,
                        horizontal: AppSpacing.lg,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: AppColors.lightGreen,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.lg,
                                ),
                              ),
                              child: const Icon(
                                Icons.medication_liquid_rounded,
                                size: 40,
                                color: AppColors.darkGreen,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              'No medications for today',
                              style: const TextStyle(
                                fontSize: 19,
                                color: AppColors.darkText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              'Add one now to start your daily reminders 💊',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.lightText,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            ElevatedButton.icon(
                              onPressed: () => Navigator.of(
                                context,
                              ).pushNamed('/edit', arguments: null),
                              icon: const Icon(
                                Icons.add_circle_outline_rounded,
                              ),
                              label: const Text(
                                'Add Medication',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: todayItems.length,
                      itemBuilder: (context, index) {
                        final item = todayItems[index];
                        return _medicationCard(item);
                      },
                    ),
                  ),

                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            Navigator.of(context).pushNamed('/edit', arguments: null),
        tooltip: 'Add Medication',
        child: const Icon(Icons.add, size: 28),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
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
          if (index == 1) {
            Navigator.of(context).pushNamed('/history');
          } else if (index == 2) {
            Navigator.of(context).pushNamed('/settings');
          }
        },
      ),
    );
  }

  Widget _medicationCard(_MedicationDisplayItem item) {
    final med = item.medication;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(
                    Icons.favorite_rounded,
                    color: AppColors.primaryGreen,
                    size: 24,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.darkText,
                        ),
                      ),
                      Text(
                        med.dosage,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.lightText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/edit', arguments: med),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.lightGreen,
                    elevation: 0,
                  ),
                  child: const Icon(
                    Icons.edit_rounded,
                    color: AppColors.primaryGreen,
                    size: 18,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Time',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _formatMedicationTime(med.time),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkGreen,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Frequency',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.lightText,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      med.medicationType,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.darkText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (item.isMissed) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.errorRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: AppColors.errorRed,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Missed • Scheduled on ${_formatDate(item.scheduledDate)}',
                      style: const TextStyle(
                        color: AppColors.errorRed,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _markMedicationAsTaken(
                  med,
                  scheduledDate: item.scheduledDate,
                  wasMissed: item.isMissed,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text(
                  'Mark as Taken',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
