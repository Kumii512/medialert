import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// Medication model (adapted for test)
class Medication {
  final int id;
  final String name;
  final String time;
  Medication({required this.id, required this.name, required this.time});

  factory Medication.fromJson(Map<String, dynamic> json) =>
      Medication(id: json['id'], name: json['name'], time: json['time']);
}

// ApiClient interface (for test)
abstract class ApiClient {
  Future<Map<String, dynamic>> getMedications();
}

// MedicationService that depends on ApiClient
class MedicationService {
  final ApiClient apiClient;
  MedicationService(this.apiClient);

  Future<List<Medication>> fetchMedications() async {
    final json = await apiClient.getMedications();
    final meds = json['meds'] as List;
    return meds.map((e) => Medication.fromJson(e)).toList();
  }
}

// Mock for ApiClient
class MockApiClient extends Mock implements ApiClient {}

void main() {
  group('MedicationService', () {
    test('should parse medications from mocked API client', () async {
      final mockApiClient = MockApiClient();
      // Arrange: stub the getMedications method
      when(() => mockApiClient.getMedications()).thenAnswer(
        (_) async => {
          "meds": [
            {"id": 1, "name": "Aspirin", "time": "08:00"},
          ],
        },
      );

      final service = MedicationService(mockApiClient);

      // Act
      final meds = await service.fetchMedications();

      // Assert
      expect(meds.length, 1);
      expect(meds.first.name, "Aspirin");
      expect(meds.first.time, "08:00");
      verify(() => mockApiClient.getMedications()).called(1);
    });

    test('should fail if JSON format is wrong', () async {
      final mockApiClient = MockApiClient();
      // Arrange: stub with wrong JSON format
      when(
        () => mockApiClient.getMedications(),
      ).thenAnswer((_) async => {"wrong_key": []});

      final service = MedicationService(mockApiClient);

      // Act & Assert
      expect(
        () async => await service.fetchMedications(),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
