import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/context/socket_provider.dart';
import 'package:malak/services/firebase_messaging_service.dart';
import 'package:malak/services/storage_service.dart';

/// Connects socket + FCM after the user authenticates.
class SessionBootstrap {
  static Future<Map<String, dynamic>?> connect(BuildContext context) async {
    final token = await StorageService.getToken();
    if (token == null || token.isEmpty) return null;

    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/users/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode != 200) return null;

      final user = json.decode(res.body) as Map<String, dynamic>;
      final userId = user['_id']?.toString() ?? '';
      if (userId.isEmpty) return null;

      final socket = SocketProvider.of(context);
      await socket.init(userId);
      await FirebaseMessagingService.instance.syncAfterAuth();

      return user;
    } catch (e) {
      debugPrint('SessionBootstrap error: $e');
      return null;
    }
  }
}
