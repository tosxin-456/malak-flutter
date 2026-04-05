import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService._(); // private constructor

  // 🔐 Tokens using SharedPreferences
  static Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('remember_token', token);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('remember_token');
  }

  // 📦 Non-sensitive
  static Future<void> saveUserData({
    required String fullName,
    required String doctorType,
    required bool fingerprintEnabled,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fullName', fullName);
    await prefs.setString('doctorType', doctorType);
    await prefs.setBool('fingerprint_enabled', fingerprintEnabled);
  }

  static Future<void> clearPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  // ✅ Convenience getter for full name
  static Future<String> getSavedFullName() async {
    final prefs = await SharedPreferences.getInstance();
    final fullName = prefs.getString('fullName') ?? '';
    return capitalizeWords(fullName);
  }
}

// Example capitalizeWords function
String capitalizeWords(String input) {
  if (input.isEmpty) return '';
  return input
      .split(' ')
      .map(
        (word) => word.isEmpty
            ? ''
            : word[0].toUpperCase() + word.substring(1).toLowerCase(),
      )
      .join(' ');
}
