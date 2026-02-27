import 'package:flutter/material.dart';
import '../models/medication.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../constants/app_theme.dart';

class EditScreen extends StatefulWidget {
  final Medication? medication;

  const EditScreen({super.key, this.medication});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late TextEditingController nameController;
  late TextEditingController dosageController;
  late TextEditingController descriptionController;
  late String selectedType;
  late TimeOfDay selectedTime;
  final FirebaseService _firebaseService = FirebaseService();
  final NotificationService _notificationService = NotificationService();
  bool isSaving = false;
  final List<String> medicationTypes = [
    'Tablet',
    'Capsule',
    'Syrup',
    'Injection',
  ];

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.medication?.name ?? '');
    dosageController = TextEditingController(
      text: widget.medication?.dosage ?? '',
    );
    descriptionController = TextEditingController(
      text: widget.medication?.description ?? '',
    );
    selectedType = widget.medication?.medicationType ?? 'Tablet';

    // Parse the time from medication or use default 09:00
    if (widget.medication != null && widget.medication!.time.isNotEmpty) {
      final timeParts = widget.medication!.time.split(':');
      if (timeParts.length >= 2) {
        int hour = int.tryParse(timeParts[0]) ?? 9;
        int minute = int.tryParse(timeParts[1]) ?? 0;
        selectedTime = TimeOfDay(hour: hour, minute: minute);
      } else {
        selectedTime = const TimeOfDay(hour: 9, minute: 0);
      }
    } else {
      selectedTime = const TimeOfDay(hour: 9, minute: 0);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    dosageController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  void _saveMedication() async {
    if (nameController.text.isEmpty || dosageController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final timeString =
          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';

      final medicationData = {
        'name': nameController.text,
        'dosage': dosageController.text,
        'medicationType': selectedType,
        'frequency': widget.medication?.frequency ?? 'Daily',
        'description': descriptionController.text,
        'time': timeString,
        'notificationsEnabled': widget.medication?.notificationsEnabled ?? true,
        'createdAt':
            widget.medication?.createdAt.toIso8601String() ??
            DateTime.now().toIso8601String(),
        'isActive': true,
      };

      if (widget.medication == null) {
        final medicationId = await _firebaseService.addUserDocument(
          'medications',
          medicationData,
        );
        final newMedication = Medication.fromJson(
          medicationData,
          docId: medicationId,
        );
        await _notificationService.scheduleMedicationReminder(newMedication);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medication added successfully')),
        );
      } else {
        await _firebaseService.updateUserDocument(
          'medications',
          widget.medication!.id,
          medicationData,
        );

        final updatedMedication = widget.medication!.copyWith(
          name: nameController.text,
          dosage: dosageController.text,
          medicationType: selectedType,
          frequency: widget.medication?.frequency ?? 'Daily',
          description: descriptionController.text,
          time: timeString,
          notificationsEnabled: widget.medication?.notificationsEnabled ?? true,
          isActive: true,
        );

        await _notificationService.scheduleMedicationReminder(
          updatedMedication,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medication updated successfully')),
        );
      }

      Navigator.of(context).pushNamedAndRemoveUntil('/home', (route) => false);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error saving medication: $e')));
    } finally {
      setState(() => isSaving = false);
    }
  }

  void _deleteMedication() async {
    if (widget.medication == null) return;
    if (widget.medication!.id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete: medication ID is missing'),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Medication?'),
        content: const Text('Are you sure you want to delete this medication?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _notificationService.cancelMedicationReminder(
                  widget.medication!.id,
                );
                await _firebaseService.deleteUserDocument(
                  'medications',
                  widget.medication!.id,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Medication deleted')),
                );
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/home', (route) => false);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error deleting medication: $e')),
                );
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: selectedTime,
    );
    if (picked != null && picked != selectedTime) {
      setState(() {
        selectedTime = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.medication == null ? 'Add Medication' : 'Edit Medication',
        ),
        backgroundColor: AppColors.primaryGreen,
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                labelText: 'Medication Name *',
                hintText: 'e.g., Aspirin',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.medication),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: dosageController,
              decoration: InputDecoration(
                labelText: 'Dosage *',
                hintText: 'e.g., 500mg',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.straighten),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: selectedType,
              decoration: InputDecoration(
                labelText: 'Medication Type *',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.category),
              ),
              items: medicationTypes
                  .map(
                    (type) => DropdownMenuItem(value: type, child: Text(type)),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => selectedType = value);
                }
              },
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _selectTime,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.access_time),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Time to take *',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          selectedTime.format(context),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Notes/Description',
                hintText: 'Additional notes about this medication',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.notes),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: isSaving ? null : _saveMedication,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Save Medication',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
            if (widget.medication != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _deleteMedication,
                  icon: const Icon(Icons.delete),
                  label: const Text('Delete Medication'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.errorRed,
                    side: const BorderSide(color: AppColors.errorRed),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
