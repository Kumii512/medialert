import 'package:flutter/material.dart';
import '../models/medication.dart';
import '../services/firebase_service.dart';
import '../constants/app_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  List<Medication> medications = [];
  bool isLoading = true;
  // persisted lastTaken on medication will determine taken state

  @override
  void initState() {
    super.initState();
    _loadMedications();
  }

  void _loadMedications() async {
    try {
      final docs = await _firebaseService.getDocuments('medications');
      setState(() {
        medications = docs.docs
            .map(
              (doc) => Medication.fromJson(
                doc.data() as Map<String, dynamic>,
                docId: doc.id,
              ),
            )
            .toList();
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> _markMedicationAsTaken(Medication med) async {
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
      };
      await _firebaseService.addDocument('takenLogs', logData);
      // persist lastTaken on medication document
      if (med.id.isNotEmpty) {
        await _firebaseService.updateDocument('medications', med.id, {
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
    final now = DateTime.now();
    return lastTaken.year == now.year &&
        lastTaken.month == now.month &&
        lastTaken.day == now.day;
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
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
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            )
          : SingleChildScrollView(
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
                  if (medications.isEmpty)
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
                              'No medications yet',
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
                        itemCount: medications.length,
                        itemBuilder: (context, index) {
                          final med = medications[index];
                          return _medicationCard(med);
                        },
                      ),
                    ),

                  const SizedBox(height: AppSpacing.lg),
                ],
              ),
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

  Widget _medicationCard(Medication med) {
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
                      med.frequency,
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
            const SizedBox(height: AppSpacing.md),
            if (_isTakenToday(med.lastTaken))
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.lightGreen,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(
                        Icons.check,
                        size: 16,
                        color: AppColors.primaryGreen,
                      ),
                      SizedBox(width: AppSpacing.xs),
                      Text(
                        'Taken',
                        style: TextStyle(
                          color: AppColors.darkText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _markMedicationAsTaken(med),
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
