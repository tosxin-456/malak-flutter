import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  StorageService._(); // private constructor

  static const _secure = FlutterSecureStorage();

  // 🔐 Tokens
  static Future<void> saveToken(String token) async {
    await _secure.write(key: 'token', value: token);
    await _secure.write(key: 'remember_token', value: token);
  }

  static Future<String?> getToken() async {
    return _secure.read(key: 'token');
  }

  static Future<void> clearSecure() async {
    await _secure.deleteAll();
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
