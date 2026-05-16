import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';

typedef PushDataHandler = void Function(Map<String, dynamic> data);

/// Background FCM handler (top-level required by Firebase).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('[FCM] Background: ${message.data['type']}');
}

class FirebaseMessagingService {
  FirebaseMessagingService._();
  static final FirebaseMessagingService instance = FirebaseMessagingService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  PushDataHandler? onPushReceived;
  PushDataHandler? onConsultationIncoming;
  bool _coreInitialized = false;

  Future<void> init() async {
    if (_coreInitialized) return;

    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('[FCM] Firebase.initializeApp failed: $e');
      return;
    }

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings),
      onDidReceiveNotificationResponse: _onLocalNotificationTapped,
    );

    const defaultChannel = AndroidNotificationChannel(
      'malak_default',
      'Malak notifications',
      description: 'Messages, appointments, and updates',
      importance: Importance.high,
    );
    const callsChannel = AndroidNotificationChannel(
      'malak_calls',
      'Incoming calls',
      description: 'Voice and video call alerts',
      importance: Importance.max,
      playSound: true,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(defaultChannel);
    await androidPlugin?.createNotificationChannel(callsChannel);

    await _requestPermission();

    FirebaseMessaging.instance.onTokenRefresh.listen(_uploadToken);

    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpened);

    final initial = await _messaging.getInitialMessage();
    if (initial != null) {
      _dispatch(initial.data);
    }

    _coreInitialized = true;
    await syncAfterAuth();
  }

  /// Call after login or when auth token becomes available.
  Future<void> syncAfterAuth() async {
    if (!_coreInitialized) return;
    try {
      final token = await _messaging.getToken();
      if (token != null) await _uploadToken(token);
    } catch (e) {
      debugPrint('[FCM] syncAfterAuth failed: $e');
    }
  }

  Future<void> unregisterToken() async {
    if (!_coreInitialized) return;
    try {
      final token = await _messaging.getToken();
      final authToken = await StorageService.getToken();
      if (token != null &&
          authToken != null &&
          authToken.isNotEmpty) {
        await http.delete(
          Uri.parse('$API_BASE_URL/users/fcm-token'),
          headers: {
            'Authorization': 'Bearer $authToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({'token': token}),
        );
      }
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('[FCM] unregisterToken error: $e');
    }
  }

  Future<void> _requestPermission() async {
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  Future<void> _uploadToken(String token) async {
    final authToken = await StorageService.getToken();
    if (authToken == null || authToken.isEmpty) return;

    try {
      final res = await http.post(
        Uri.parse('$API_BASE_URL/users/fcm-token'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'token': token,
          'platform': defaultTargetPlatform.name,
        }),
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        debugPrint('[FCM] Token registered');
      } else {
        debugPrint('[FCM] Token register failed: ${res.statusCode}');
      }
    } catch (e) {
      debugPrint('[FCM] Token upload error: $e');
    }
  }

  void _onForegroundMessage(RemoteMessage message) {
    final data = Map<String, dynamic>.from(message.data);
    final type = data['type']?.toString() ?? '';

    if (type == 'call_incoming' || type == 'consultation_incoming') {
      _dispatch(data);
      return;
    }

    final title =
        message.notification?.title ?? data['title']?.toString() ?? 'Malak';
    final body = message.notification?.body ??
        data['body']?.toString() ??
        'You have a new notification';

    _showLocalNotification(title, body, data);
    _dispatch(data);
  }

  void _onMessageOpened(RemoteMessage message) {
    _dispatch(message.data);
  }

  void _onLocalNotificationTapped(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      _dispatch(data);
    } catch (_) {}
  }

  void _dispatch(Map<String, dynamic> data) {
    if (data.isEmpty) return;
    onPushReceived?.call(Map<String, dynamic>.from(data));
  }

  Future<void> _showLocalNotification(
    String title,
    String body,
    Map<String, dynamic> data,
  ) async {
    final type = data['type']?.toString() ?? '';
    final channelId = type == 'call_incoming' ? 'malak_calls' : 'malak_default';
    final channelName =
        type == 'call_incoming' ? 'Incoming calls' : 'Malak notifications';

    await _localNotifications.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription: channelName,
          importance: type == 'call_incoming'
              ? Importance.max
              : Importance.high,
          priority: type == 'call_incoming' ? Priority.max : Priority.high,
        ),
      ),
      payload: jsonEncode(data),
    );
  }
}
