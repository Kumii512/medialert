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

  IconData _iconForMedicationType(String type) {
    switch (type) {
      case 'Capsule':
        return Icons.medication_rounded;
      case 'Syrup':
        return Icons.local_drink_rounded;
      case 'Injection':
        return Icons.vaccines_rounded;
      case 'Tablet':
      default:
        return Icons.medication_liquid_rounded;
    }
  }

  Widget _buildFunInputCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: AppColors.veryLightGreen,
      appBar: AppBar(
        title: Text(
          widget.medication == null ? 'Add Medication' : 'Edit Medication',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: AppColors.primaryGreen,
      ),
      body: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(16, 16, 16, 20 + bottomInset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.lightGreen, AppColors.veryLightGreen],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                      color: AppColors.white,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: AppColors.darkGreen,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      widget.medication == null
                          ? 'Let\'s add your medication 💊'
                          : 'Update your medication details ✨',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.darkText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildFunInputCard(
              child: TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Medication Name *',
                  hintText: 'e.g., Aspirin',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.favorite_rounded),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildFunInputCard(
              child: TextField(
                controller: dosageController,
                decoration: InputDecoration(
                  labelText: 'Dosage *',
                  hintText: 'e.g., 500mg',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.science_rounded),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildFunInputCard(
              child: DropdownButtonFormField<String>(
                initialValue: selectedType,
                decoration: InputDecoration(
                  labelText: 'Medication Type *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: Icon(_iconForMedicationType(selectedType)),
                ),
                items: medicationTypes
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Row(
                          children: [
                            Icon(
                              _iconForMedicationType(type),
                              size: 18,
                              color: AppColors.darkGreen,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(type),
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => selectedType = value);
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _selectTime,
              child: _buildFunInputCard(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.borderColor),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 16,
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.alarm_rounded,
                        color: AppColors.darkGreen,
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Time to take *',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.lightText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            selectedTime.format(context),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.darkText,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildFunInputCard(
              child: TextField(
                controller: descriptionController,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: 'Notes/Description',
                  hintText: 'Additional notes about this medication',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.sticky_note_2_rounded),
                ),
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
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'Save Medication',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
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
