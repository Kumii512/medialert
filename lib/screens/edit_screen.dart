import 'package:flutter/material.dart';
import '../models/medication.dart';
import '../services/firebase_service.dart';
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
  late TextEditingController frequencyController;
  late TextEditingController descriptionController;
  final FirebaseService _firebaseService = FirebaseService();
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.medication?.name ?? '');
    dosageController = TextEditingController(
      text: widget.medication?.dosage ?? '',
    );
    frequencyController = TextEditingController(
      text: widget.medication?.frequency ?? '',
    );
    descriptionController = TextEditingController(
      text: widget.medication?.description ?? '',
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    dosageController.dispose();
    frequencyController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  void _saveMedication() async {
    if (nameController.text.isEmpty ||
        dosageController.text.isEmpty ||
        frequencyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final medicationData = {
        'name': nameController.text,
        'dosage': dosageController.text,
        'frequency': frequencyController.text,
        'description': descriptionController.text,
        'createdAt':
            widget.medication?.createdAt.toIso8601String() ??
            DateTime.now().toIso8601String(),
        'isActive': true,
      };

      if (widget.medication == null) {
        // Add new medication
        await _firebaseService.addDocument('medications', medicationData);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Medication added successfully')),
        );
      } else {
        // Update existing medication
        await _firebaseService.updateDocument(
          'medications',
          widget.medication!.id,
          medicationData,
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
                await _firebaseService.deleteDocument(
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.medication == null ? 'Add Medication' : 'Edit Medication',
        ),
        backgroundColor: AppColors.primaryGreen,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
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
            TextField(
              controller: frequencyController,
              decoration: InputDecoration(
                labelText: 'Frequency *',
                hintText: 'e.g., Twice daily',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                prefixIcon: const Icon(Icons.schedule),
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
