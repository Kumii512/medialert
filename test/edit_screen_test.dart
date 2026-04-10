import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medialert_project/models/medication.dart';
import 'package:medialert_project/screens/edit_screen.dart';

void main() {
  group('EditScreen Widget Tests', () {
    testWidgets('shows error if required fields are whitespace only', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: EditScreen()));
      final nameField = find.widgetWithText(TextField, 'Medication Name *');
      final dosageField = find.widgetWithText(TextField, 'Dosage *');
      final saveButton = find.byKey(const Key('save_medication_button'));
      await tester.enterText(nameField, '   ');
      await tester.enterText(dosageField, '\t\t');
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // This will likely fail: the SnackBar should appear, but current logic only checks isEmpty, not trim().isEmpty
      expect(find.text('Please fill all required fields'), findsOneWidget);
    });
    testWidgets('displays Add Medication when no medication is provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: EditScreen()));
      expect(find.text('Add Medication'), findsOneWidget);
      expect(find.text("Let's add your medication 💊"), findsOneWidget);
      expect(find.text('Save Medication'), findsOneWidget);
    });

    testWidgets('displays Edit Medication when medication is provided', (
      WidgetTester tester,
    ) async {
      final medication = Medication(
        id: '1',
        name: 'Aspirin',
        dosage: '500mg',
        medicationType: 'Tablet',
        frequency: 'Daily',
        description: 'Painkiller',
        time: '09:00',
        notificationsEnabled: true,
        createdAt: DateTime.now(),
        isActive: true,
      );
      await tester.pumpWidget(
        MaterialApp(home: EditScreen(medication: medication)),
      );
      expect(find.text('Edit Medication'), findsOneWidget);
      expect(find.text('Update your medication details ✨'), findsOneWidget);
      expect(find.text('Delete Medication'), findsOneWidget);
    });

    testWidgets('shows error if required fields are empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MaterialApp(home: EditScreen()));
      final saveButton = find.byKey(const Key('save_medication_button'));
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Please fill all required fields'), findsOneWidget);
    });
  });
}
