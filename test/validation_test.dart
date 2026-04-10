// validation_test.dart
import 'package:flutter_test/flutter_test.dart';

// --- Validation Functions ---
bool isValidEmail(String email) {
  final trimmed = email.trim();
  // Final fix: robust regex for Gmail addresses with dots and plus addressing
  final emailRegex = RegExp(
    r'^[a-zA-Z0-9._%+-]+(\+[a-zA-Z0-9._%+-]+)?@gmail\.com$',
  );
  return emailRegex.hasMatch(trimmed);
}

bool isValidPassword(String password) {
  return password.trim().length >= 6;
}

void main() {
  group('Email Validation', () {
    test('should accept valid Gmail address', () {
      expect(isValidEmail('user@gmail.com'), isTrue);
      expect(isValidEmail('name.surname@gmail.com'), isTrue);
      expect(isValidEmail('name.surname+tag@gmail.com'), isTrue);
    });

    test('should reject email missing @', () {
      expect(isValidEmail('usergmail.com'), isFalse);
    });

    test('should reject email missing .com', () {
      expect(isValidEmail('user@gmail'), isFalse);
    });

    test('should reject email with multiple @', () {
      expect(isValidEmail('user@@gmail.com'), isFalse);
    });

    test('should reject empty email', () {
      expect(isValidEmail(''), isFalse);
    });
  });

  group('Password Validation', () {
    test('should accept password of exactly 6 characters', () {
      expect(isValidPassword('123456'), isTrue);
    });

    test('should accept password longer than 6 characters', () {
      expect(isValidPassword('1234567'), isTrue);
    });

    test('should reject password of exactly 5 characters', () {
      expect(isValidPassword('12345'), isFalse);
    });

    test('should reject empty password', () {
      expect(isValidPassword(''), isFalse);
    });

    test('should reject password with only spaces', () {
      expect(isValidPassword('      '), isFalse);
    });
  });
}
