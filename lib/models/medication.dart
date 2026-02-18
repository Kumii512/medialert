class Medication {
  final String id;
  final String name;
  final String dosage;
  final String medicationType; // Tablet, Capsule, Syrup, Injection
  final String frequency; // Daily, Weekly, Custom
  final String time; // Time to take (e.g., "09:00 AM")
  final String? description;
  final DateTime? lastTaken;
  final bool notificationsEnabled;
  final DateTime createdAt;
  final bool isActive;

  Medication({
    required this.id,
    required this.name,
    required this.dosage,
    required this.medicationType,
    required this.frequency,
    required this.time,
    this.description,
    this.lastTaken,
    this.notificationsEnabled = true,
    required this.createdAt,
    this.isActive = true,
  });

  factory Medication.fromJson(Map<String, dynamic> json, {String? docId}) {
    return Medication(
      id: docId ?? json['id'] ?? '',
      name: json['name'] ?? '',
      dosage: json['dosage'] ?? '',
      medicationType: json['medicationType'] ?? 'Tablet',
      frequency: json['frequency'] ?? 'Daily',
      time: json['time'] ?? '09:00 AM',
      description: json['description'],
      notificationsEnabled: json['notificationsEnabled'] ?? true,
      lastTaken: json['lastTaken'] != null
          ? DateTime.parse(json['lastTaken'])
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      isActive: json['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'dosage': dosage,
      'medicationType': medicationType,
      'frequency': frequency,
      'time': time,
      'description': description,
      'lastTaken': lastTaken?.toIso8601String(),
      'notificationsEnabled': notificationsEnabled,
      'createdAt': createdAt.toIso8601String(),
      'isActive': isActive,
    };
  }

  Medication copyWith({
    String? id,
    String? name,
    String? dosage,
    String? medicationType,
    String? frequency,
    String? time,
    String? description,
    DateTime? lastTaken,
    bool? notificationsEnabled,
    DateTime? createdAt,
    bool? isActive,
  }) {
    return Medication(
      id: id ?? this.id,
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      medicationType: medicationType ?? this.medicationType,
      frequency: frequency ?? this.frequency,
      time: time ?? this.time,
      description: description ?? this.description,
      lastTaken: lastTaken ?? this.lastTaken,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      createdAt: createdAt ?? this.createdAt,
      isActive: isActive ?? this.isActive,
    );
  }
}

class TakenLog {
  final String id;
  final String medicationId;
  final String medicationName;
  final DateTime takenAt;
  final String notes;

  TakenLog({
    required this.id,
    required this.medicationId,
    required this.medicationName,
    required this.takenAt,
    this.notes = '',
  });

  factory TakenLog.fromJson(Map<String, dynamic> json) {
    return TakenLog(
      id: json['id'] ?? '',
      medicationId: json['medicationId'] ?? '',
      medicationName: json['medicationName'] ?? '',
      takenAt: json['takenAt'] != null
          ? DateTime.parse(json['takenAt'])
          : DateTime.now(),
      notes: json['notes'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'medicationId': medicationId,
      'medicationName': medicationName,
      'takenAt': takenAt.toIso8601String(),
      'notes': notes,
    };
  }
}
