import 'package:flutter/material.dart';
import '../models/medication.dart';
import '../services/firebase_service.dart';
import '../constants/app_theme.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  List<TakenLog> logs = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  void _loadLogs() async {
    try {
      final docs = await _firebaseService.getDocuments('takenLogs');
      setState(() {
        logs = docs.docs
            .map((doc) => TakenLog.fromJson(doc.data() as Map<String, dynamic>))
            .toList();
        // Sort by date descending
        logs.sort((a, b) => b.takenAt.compareTo(a.takenAt));
        isLoading = false;
      });
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading history: $e')));
    }
  }

  void _markMedicationAsTaken() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Medication as Taken'),
        content: TextField(
          decoration: InputDecoration(
            labelText: 'Medication Name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Add log entry
              final logsData = {
                'medicationId': 'temp_id',
                'medicationName': 'Medication',
                'takenAt': DateTime.now().toIso8601String(),
                'notes': '',
              };
              await _firebaseService.addDocument('takenLogs', logsData);
              _loadLogs();
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.veryLightGreen,
      appBar: AppBar(
        title: const Text('Medication History'),
        backgroundColor: AppColors.primaryGreen,
        elevation: 0,
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            )
          : logs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.history_rounded,
                    size: 64,
                    color: AppColors.primaryGreen.withOpacity(0.5),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'No medication history yet',
                    style: TextStyle(fontSize: 16, color: AppColors.lightText),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.md,
              ),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
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
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                              ),
                              child: const Icon(
                                Icons.check_circle_rounded,
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
                                    log.medicationName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.darkText,
                                    ),
                                  ),
                                  Text(
                                    _formatDate(log.takenAt),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.lightText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppColors.errorRed,
                              ),
                              onPressed: () async {
                                await _firebaseService.deleteDocument(
                                  'takenLogs',
                                  log.id,
                                );
                                _loadLogs();
                              },
                            ),
                          ],
                        ),
                        if (log.notes.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Notes: ${log.notes}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.lightText,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _markMedicationAsTaken,
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 1,
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
          } else if (index == 2) {
            Navigator.of(context).pushNamed('/settings');
          }
        },
      ),
    );
  }
}
