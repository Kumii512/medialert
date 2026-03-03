import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class PushNotificationService {
  PushNotificationService._internal();

  static final PushNotificationService _instance =
      PushNotificationService._internal();

  factory PushNotificationService() => _instance;

  bool _isInitialized = false;
  StreamSubscription<User?>? _authSubscription;
  StreamSubscription<String>? _tokenRefreshSubscription;
  String? _lastKnownUserId;
  String? _lastKnownToken;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _isInitialized = true;

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) {
        unawaited(
          _removeTokenForUser(
            userId: _lastKnownUserId,
            tokenOverride: _lastKnownToken,
            deleteMessagingToken: true,
          ),
        );
        return;
      }

      _lastKnownUserId = user.uid;
      unawaited(syncTokenForCurrentUser());
    });

    _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh
        .listen((_) {
          syncTokenForCurrentUser();
        });

    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('Foreground push message: ${message.messageId}');
    });

    await syncTokenForCurrentUser();
  }

  Future<void> syncTokenForCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      final permissions = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (permissions.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await _currentFcmToken();
      if (token == null || token.isEmpty) {
        return;
      }

      _lastKnownUserId = user.uid;
      _lastKnownToken = token;

      final tokenDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('notificationTokens')
          .doc(token);

      await tokenDoc.set({
        'token': token,
        'platform': _platformLabel(),
        'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
        'timezoneName': DateTime.now().timeZoneName,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to sync FCM token: $e');
    }
  }

  Future<String?> _currentFcmToken() async {
    if (kIsWeb) {
      const vapidKey = String.fromEnvironment('FCM_WEB_VAPID_KEY');
      if (vapidKey.isNotEmpty) {
        return FirebaseMessaging.instance.getToken(vapidKey: vapidKey);
      }

      debugPrint(
        'FCM web VAPID key was not provided via --dart-define. Falling back to default Firebase web push key.',
      );
      return FirebaseMessaging.instance.getToken();
    }

    return FirebaseMessaging.instance.getToken();
  }

  Future<void> removeTokenForCurrentUser() async {
    await _removeTokenForUser(
      userId: FirebaseAuth.instance.currentUser?.uid,
      deleteMessagingToken: true,
    );
  }

  Future<void> _removeTokenForUser({
    required String? userId,
    String? tokenOverride,
    bool deleteMessagingToken = false,
  }) async {
    if (userId == null || userId.isEmpty) {
      return;
    }

    try {
      final token = tokenOverride ?? await _currentFcmToken();
      if (token != null && token.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('notificationTokens')
            .doc(token)
            .delete();
      }

      if (deleteMessagingToken) {
        await FirebaseMessaging.instance.deleteToken();
      }
    } catch (e) {
      debugPrint('Failed to remove FCM token: $e');
    } finally {
      if (userId == _lastKnownUserId) {
        _lastKnownToken = null;
      }
    }
  }

  String _platformLabel() {
    if (kIsWeb) {
      return 'web';
    }
    return defaultTargetPlatform.name;
  }
}
