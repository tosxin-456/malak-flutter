import 'package:flutter/material.dart';
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
      // Token exists → navigate to home
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } else {
      // No token → navigate to sign-in
      Navigator.pushReplacementNamed(context, AppRoutes.signIn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(), // Show loading while checking
      ),
    );
  }
}
