import 'package:flutter/material.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import '../services/storage_service.dart';
import '../routes/app_routes.dart';

class InitialScreen extends StatefulWidget {
  const InitialScreen({super.key});

  @override
  State<InitialScreen> createState() => _InitialScreenState();
}

class _InitialScreenState extends State<InitialScreen> {
  @override
  void initState() {
    super.initState();
    checkToken();
  }

  Future<void> checkToken() async {
    final token = await StorageService.getToken();

    if (token != null && token.isNotEmpty) {
      try {
        final isExpired = JwtDecoder.isExpired(token);

        if (!isExpired) {
          // ✅ Valid token → go to home
          Navigator.pushReplacementNamed(context, AppRoutes.home);
          return;
        } else {
          // ❌ Expired → clear it
          await StorageService.clearToken();
        }
      } catch (e) {
        // ❌ Invalid token format → clear it
        await StorageService.clearToken();
      }
    }

    // ❌ No token or invalid/expired → go to login
    Navigator.pushReplacementNamed(context, AppRoutes.signIn);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
