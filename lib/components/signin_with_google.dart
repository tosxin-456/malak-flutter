import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/api_config.dart';
import '../routes/app_routes.dart';

// Google Icon Widget
class GoogleIcon extends StatelessWidget {
  const GoogleIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: GoogleIconPainter()),
    );
  }
}

class GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Blue section (top right)
    paint.color = const Color(0xFF4285F4);
    final bluePath = Path()
      ..moveTo(20.64, 12.2)
      ..cubicTo(20.64, 11.56, 20.59, 10.93, 20.49, 10.32)
      ..lineTo(12, 10.32)
      ..lineTo(12, 13.84)
      ..lineTo(16.96, 13.84)
      ..cubicTo(16.75, 14.96, 16.12, 15.95, 15.21, 16.62)
      ..lineTo(15.21, 18.82)
      ..lineTo(18.04, 18.82)
      ..cubicTo(19.66, 17.33, 20.64, 15.02, 20.64, 12.2)
      ..close();
    canvas.drawPath(_scalePath(bluePath, size, 24), paint);

    // Green section (bottom right)
    paint.color = const Color(0xFF34A853);
    final greenPath = Path()
      ..moveTo(12, 20.96)
      ..cubicTo(14.43, 20.96, 16.47, 20.19, 18.04, 18.82)
      ..lineTo(15.21, 16.62)
      ..cubicTo(14.46, 17.15, 13.49, 17.48, 12, 17.48)
      ..cubicTo(9.65, 17.48, 7.67, 15.98, 6.97, 13.93)
      ..lineTo(4.06, 13.93)
      ..lineTo(4.06, 16.21)
      ..cubicTo(5.62, 19.31, 8.58, 20.96, 12, 20.96)
      ..close();
    canvas.drawPath(_scalePath(greenPath, size, 24), paint);

    // Yellow section (bottom left)
    paint.color = const Color(0xFFFBBC04);
    final yellowPath = Path()
      ..moveTo(6.97, 13.93)
      ..cubicTo(6.72, 13.4, 6.58, 12.82, 6.58, 12.23)
      ..cubicTo(6.58, 11.64, 6.72, 11.06, 6.97, 10.53)
      ..lineTo(6.97, 8.25)
      ..lineTo(4.06, 8.25)
      ..cubicTo(3.39, 9.58, 3.04, 11.07, 3.04, 12.23)
      ..cubicTo(3.04, 13.39, 3.39, 14.88, 4.06, 16.21)
      ..lineTo(6.97, 13.93)
      ..close();
    canvas.drawPath(_scalePath(yellowPath, size, 24), paint);

    // Red section (top left)
    paint.color = const Color(0xFFEA4335);
    final redPath = Path()
      ..moveTo(12, 7.98)
      ..cubicTo(13.54, 7.98, 14.91, 8.51, 15.99, 9.54)
      ..lineTo(18.51, 7.02)
      ..cubicTo(16.46, 5.15, 13.83, 4, 12, 4)
      ..cubicTo(8.58, 4, 5.62, 5.65, 4.06, 8.25)
      ..lineTo(6.97, 10.53)
      ..cubicTo(7.67, 8.48, 9.65, 7.98, 12, 7.98)
      ..close();
    canvas.drawPath(_scalePath(redPath, size, 24), paint);
  }

  Path _scalePath(Path path, Size size, double viewBoxSize) {
    final scale = size.width / viewBoxSize;
    final matrix = Matrix4.identity()..scale(scale, scale);
    return path.transform(matrix.storage);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Main Google Sign-In Widget
class SignInWithGoogle extends StatefulWidget {
  final bool rememberMe;

  const SignInWithGoogle({super.key, this.rememberMe = false});

  @override
  State<SignInWithGoogle> createState() => _SignInWithGoogleState();
}

class _SignInWithGoogleState extends State<SignInWithGoogle> {
  String _error = "";
  bool _isLoading = false;

  void _clearError() {
    setState(() => _error = "");
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _error = "";
      _isLoading = true;
    });

    try {
      // TODO: Implement actual Google Sign-In
      // Add to pubspec.yaml: google_sign_in: ^6.1.0

      // For now, simulate the flow
      await Future.delayed(const Duration(seconds: 2));

      // This is where you'd get the access token from Google Sign-In
      // final googleSignIn = GoogleSignIn(scopes: ['email']);
      // final account = await googleSignIn.signIn();
      // final authentication = await account?.authentication;
      // final accessToken = authentication?.accessToken;

      // Mock access token for demonstration
      const mockAccessToken = "mock_token";

      // Send to backend
      final res = await http.post(
        Uri.parse('$API_BASE_URL/users/google-auth'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"access_token": mockAccessToken}),
      );

      if (res.statusCode != 200) {
        final errorData = jsonDecode(res.body);
        throw Exception(
          errorData['message'] ?? 'Server error: ${res.statusCode}',
        );
      }

      final data = jsonDecode(res.body);

      // TODO: Save token and user data using SharedPreferences
      // final prefs = await SharedPreferences.getInstance();
      // await prefs.setString('token', data['token']);
      // await prefs.setString('fullName', data['user'] ?? '');
      // await prefs.setString('doctorType', data['doctorType'] ?? '');

      // Apply Remember Me logic
      if (widget.rememberMe) {
        // await prefs.setString('remember_token', data['token']);
        // await prefs.setBool('fingerprint_enabled', true);
      } else {
        // await prefs.remove('remember_token');
        // await prefs.remove('fingerprint_enabled');
      }

      // Navigate based on role
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } catch (error) {
      debugPrint("❌ Google Sign-In error: $error");
      setState(() {
        _error =
            error.toString().replaceAll('Exception: ', '') ??
            "Sign-in failed. Please try again.";
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorToast() {
    if (_error.isEmpty) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Expanded(child: Text(_error)),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                _clearError();
              },
            ),
          ],
        ),
        backgroundColor: const Color(0xFFF87171), // red-400
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  void didUpdateWidget(SignInWithGoogle oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (_error.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showErrorToast());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 448), // max-w-md
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          onPressed: _isLoading ? null : _handleGoogleSignIn,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.transparent,
            side: const BorderSide(
              color: Color(0xFF3B82F6), // border-blue-500
              width: 2,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            foregroundColor: const Color(0xFF2563EB), // text-blue-600
            disabledForegroundColor: const Color(0xFF2563EB).withOpacity(0.5),
          ),
          child: _isLoading
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF2563EB),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Signing in...',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    GoogleIcon(),
                    SizedBox(width: 12),
                    Text(
                      'Sign in with Google',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// Enhanced version with actual Google Sign-In implementation
// Add to pubspec.yaml:
// google_sign_in: ^6.1.0
// shared_preferences: ^2.2.0

/*
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SignInWithGoogleEnhanced extends StatefulWidget {
  final bool rememberMe;

  const SignInWithGoogleEnhanced({
    super.key,
    this.rememberMe = false,
  });

  @override
  State<SignInWithGoogleEnhanced> createState() => 
      _SignInWithGoogleEnhancedState();
}

class _SignInWithGoogleEnhancedState extends State<SignInWithGoogleEnhanced> {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );
  
  String _error = "";
  bool _isLoading = false;

  Future<void> _handleGoogleSignIn() async {
    setState(() {
      _error = "";
      _isLoading = true;
    });

    try {
      // Sign in with Google
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      
      if (account == null) {
        throw Exception("Google login was cancelled or failed. Please try again.");
      }

      // Get authentication tokens
      final GoogleSignInAuthentication authentication = 
          await account.authentication;
      
      final accessToken = authentication.accessToken;
      
      if (accessToken == null) {
        throw Exception("Failed to get access token from Google.");
      }

      // Send to backend
      final res = await http.post(
        Uri.parse('$API_BASE_URL/users/google-auth'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"access_token": accessToken}),
      );

      if (res.statusCode != 200) {
        final errorData = jsonDecode(res.body);
        throw Exception(
          errorData['message'] ?? 'Server error: ${res.statusCode}'
        );
      }

      final data = jsonDecode(res.body);
      
      // Save token and user data
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', data['token']);
      await prefs.setString('fullName', data['user'] ?? '');
      await prefs.setString('doctorType', data['doctorType'] ?? '');
      
      // Apply Remember Me logic
      if (widget.rememberMe) {
        await prefs.setString('remember_token', data['token']);
        await prefs.setBool('fingerprint_enabled', true);
      } else {
        await prefs.remove('remember_token');
        await prefs.remove('fingerprint_enabled');
      }

      // Decode token to check role (you'll need jwt_decoder package)
      // final decodedToken = JwtDecoder.decode(data['token']);
      // final userRole = decodedToken['role'];
      
      // Navigate based on role
      if (mounted) {
        // if (userRole != 'patient') {
        //   Navigator.pushReplacementNamed(context, AppRoutes.loginType);
        // } else {
        //   final hasCart = prefs.getString('cart_before_login') != null;
        //   Navigator.pushReplacementNamed(
        //     context,
        //     hasCart ? AppRoutes.marketplace : AppRoutes.dashboard,
        //   );
        // }
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
      
    } catch (error) {
      debugPrint("❌ Google Sign-In error: $error");
      setState(() {
        _error = error.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Same UI as the basic version
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 448),
      padding: const EdgeInsets.all(24),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          onPressed: _isLoading ? null : _handleGoogleSignIn,
          style: OutlinedButton.styleFrom(
            backgroundColor: Colors.transparent,
            side: const BorderSide(color: Color(0xFF3B82F6), width: 2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            foregroundColor: const Color(0xFF2563EB),
          ),
          child: _isLoading
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF2563EB),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Signing in...',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    GoogleIcon(),
                    SizedBox(width: 12),
                    Text('Sign in with Google',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
        ),
      ),
    );
  }
}
*/
