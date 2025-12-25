import 'package:flutter/material.dart';
import '../services/storage_service.dart';
import '../screens/sign_in_screen.dart';

class LogoutButton extends StatelessWidget {
  const LogoutButton({Key? key}) : super(key: key);

  Future<void> _logout(BuildContext context) async {
    // Clear secure storage (tokens)
    await StorageService.clearSecure();

    // Clear shared preferences (non-sensitive user data)
    await StorageService.clearPrefs();

    // Navigate to SignInScreen and remove all previous routes
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => _logout(context),
      icon: const Icon(Icons.logout, color: Colors.white),
      tooltip: 'Logout', // optional: shows on long press
    );
  }
}
