import 'package:flutter/material.dart';
import 'package:malak/services/firebase_messaging_service.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await FirebaseMessagingService.instance.init();
  } catch (e) {
    debugPrint('Firebase init skipped: $e');
  }
  runApp(const MalakApp());
}
