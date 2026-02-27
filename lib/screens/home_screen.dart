import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  Timer? _webNotificationTimer;
  Timer? _nextWebDueTimer;
  List<Medication> medications = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _webNotificationTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        _notificationService.notifyDueMedicationsOnWeb(medications);
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureNotificationPermission();
      _scheduleNextWebDueCheck();
    });
  }

  @override
  void dispose() {
    _webNotificationTimer?.cancel();
    _nextWebDueTimer?.cancel();
    super.dispose();
  }

  Future<void> _scheduleNextWebDueCheck() async {
    if (!kIsWeb) {
      return;
    }

    _nextWebDueTimer?.cancel();
    final delay = await _notificationService.nextWebReminderDelay(medications);
    if (delay == null || !mounted) {
      return;
    }

    final timerDelay = delay < const Duration(seconds: 1)
        ? const Duration(seconds: 1)
        : delay;

    _nextWebDueTimer = Timer(timerDelay, () async {
      await _notificationService.notifyDueMedicationsOnWeb(medications);
      if (!mounted) {
        return;
      }
      await _scheduleNextWebDueCheck();
    });
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
        title: const Text('Today\'s Medication'),
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

          if (kIsWeb) {
            _notificationService.notifyDueMedicationsOnWeb(medications);
            _scheduleNextWebDueCheck();
          }

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
                      Text(
                        _getGreeting(),
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                      Text(
                        'Today - ${DateTime.now().day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][DateTime.now().month - 1]}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.lightText,
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
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.favorite_border_rounded,
                            size: 64,
                            color: AppColors.primaryGreen.withOpacity(0.5),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          const Text(
                            'No medications for today',
                            style: TextStyle(
                              fontSize: 16,
                              color: AppColors.lightText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.of(
                              context,
                            ).pushNamed('/edit', arguments: null),
                            icon: const Icon(Icons.add),
                            label: const Text('Add Your First Medication'),
                          ),
                        ],
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
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkText,
                        ),
                      ),
                      Text(
                        med.dosage,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.lightText,
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
                      med.time,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
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
                        fontWeight: FontWeight.w600,
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
                  color: AppColors.errorRed.withOpacity(0.1),
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
                        fontWeight: FontWeight.w600,
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
                label: const Text('Mark as Taken'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
