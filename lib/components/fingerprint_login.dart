import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../routes/app_routes.dart';

class FingerprintLogin extends StatefulWidget {
  final VoidCallback? onSuccess;

  const FingerprintLogin({super.key, this.onSuccess});

  @override
  State<FingerprintLogin> createState() => _FingerprintLoginState();
}

class _FingerprintLoginState extends State<FingerprintLogin> {
  bool _loading = false;
  String _error = "";
  String _success = "";
  bool _requestInProgress = false;

  Future<void> _handleFingerprintAuth() async {
    if (_requestInProgress) {
      debugPrint("⏳ A fingerprint request is already in progress.");
      return;
    }

    setState(() {
      _requestInProgress = true;
      _error = "";
      _loading = true;
    });

    try {
      // TODO: Implement platform-specific biometric authentication
      // For Android: Use local_auth package
      // For iOS: Use local_auth package

      // Get stored token
      // final token = await _getStoredToken();

      // For now, simulate the flow
      await Future.delayed(const Duration(seconds: 2));

      // Mock success
      setState(() {
        _success = "✅ Fingerprint recognized! Logging in...";
      });

      await Future.delayed(const Duration(milliseconds: 900));

      if (mounted) {
        // Navigate based on user role
        Navigator.pushReplacementNamed(context, AppRoutes.home);
        widget.onSuccess?.call();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _requestInProgress = false;
        });
      }
    }
  }

  void _showErrorToast() {
    if (_error.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_error),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 3),
      ),
    );

    setState(() => _error = "");
  }

  void _showSuccessToast() {
    if (_success.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_success),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 2),
      ),
    );

    setState(() => _success = "");
  }

  @override
  void didUpdateWidget(FingerprintLogin oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_error.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showErrorToast());
    }

    if (_success.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showSuccessToast());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 384), // max-w-sm
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _loading ? null : _handleFingerprintAuth,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.black.withOpacity(0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: _loading
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text('Authenticating...', style: TextStyle(fontSize: 16)),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.fingerprint, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Sign in with Fingerprint',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// Enhanced version with actual biometric implementation
// Add to pubspec.yaml: local_auth: ^2.1.0

/*
import 'package:local_auth/local_auth.dart';

class FingerprintLoginWithBiometrics extends StatefulWidget {
  final VoidCallback? onSuccess;
  
  const FingerprintLoginWithBiometrics({
    super.key,
    this.onSuccess,
  });

  @override
  State<FingerprintLoginWithBiometrics> createState() => 
      _FingerprintLoginWithBiometricsState();
}

class _FingerprintLoginWithBiometricsState 
    extends State<FingerprintLoginWithBiometrics> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  bool _loading = false;
  String _error = "";
  String _success = "";

  Future<void> _handleFingerprintAuth() async {
    setState(() {
      _error = "";
      _loading = true;
    });

    try {
      // Check if device supports biometrics
      final canCheckBiometrics = await _localAuth.canCheckBiometrics;
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      
      if (!canCheckBiometrics || !isDeviceSupported) {
        throw Exception(
          "Fingerprint authentication is not supported on this device."
        );
      }

      // Get available biometrics
      final availableBiometrics = await _localAuth.getAvailableBiometrics();
      
      if (availableBiometrics.isEmpty) {
        throw Exception("No biometric authentication methods available.");
      }

      // Authenticate
      final didAuthenticate = await _localAuth.authenticate(
        localizedReason: 'Please authenticate to sign in',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!didAuthenticate) {
        throw Exception("Fingerprint authentication was cancelled or failed.");
      }

      // Get stored token
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('remember_token');
      
      if (token == null) {
        throw Exception("No saved authentication found. Please sign in first.");
      }

      // Get options from server
      final optionsRes = await http.get(
        Uri.parse('$API_BASE_URL/fingerprint/login/options'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (optionsRes.statusCode != 200) {
        throw Exception(
          "2FA or Fingerprint authentication has not been set up yet, "
          "or your session has expired"
        );
      }

      // Verify with server
      final verifyRes = await http.post(
        Uri.parse('$API_BASE_URL/fingerprint/login/verify'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'authenticated': true,
          'biometricType': availableBiometrics.first.toString(),
        }),
      );

      final data = jsonDecode(verifyRes.body);
      
      if (verifyRes.statusCode != 200) {
        throw Exception(data['message'] ?? "Fingerprint login failed.");
      }

      // Save new token
      await prefs.setString('token', data['token']);
      await prefs.setString('fullName', data['user'] ?? '');
      await prefs.setString('doctorType', data['doctorType'] ?? '');
      await prefs.setBool('fingerprint_enabled', true);

      setState(() {
        _success = "✅ Fingerprint recognized! Logging in...";
      });

      await Future.delayed(const Duration(milliseconds: 900));

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
        widget.onSuccess?.call();
      }
      
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same UI as above
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 384),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _loading ? null : _handleFingerprintAuth,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.black.withOpacity(0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: _loading
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text('Authenticating...', style: TextStyle(fontSize: 16)),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.fingerprint, size: 20),
                    SizedBox(width: 8),
                    Text('Sign in with Fingerprint', 
                         style: TextStyle(fontSize: 16)),
                  ],
                ),
        ),
      ),
    );
  }
}
*/
