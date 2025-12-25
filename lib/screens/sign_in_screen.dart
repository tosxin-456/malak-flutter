import 'package:flutter/material.dart';
import 'package:malak/components/fingerprint_login.dart';
import 'package:malak/components/signin_with_google.dart';
import '../routes/app_routes.dart';
import '../config/api_config.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _showPassword = false;
  String _error = "";
  bool _loading = false;

  Future<void> _handleLogin() async {
    setState(() {
      _error = "";
      _loading = true;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _error = "Please enter both email and password";
        _loading = false;
      });
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$API_BASE_URL/users/login'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "password": password}),
      );

      final data = jsonDecode(response.body);

      if (response.statusCode != 200) {
        setState(() {
          _error = data['message'] ?? "Login failed";
          _loading = false;
        });
        return;
      }

      // TODO: Save token, user info locally
      // e.g., SharedPreferences or secure storage

      // Navigate based on role or default
      Navigator.pushReplacementNamed(context, AppRoutes.home);
    } catch (e) {
      setState(() {
        _error = "An error occurred. Please try again.";
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB), // bg-gray-50
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 448), // max-w-md
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo + Heading
                  Column(
                    children: [
                      // Logo
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.favorite,
                            color: const Color(0xFF2563EB), // text-blue-600
                            size: 32,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Malak',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1F2937), // text-gray-800
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Title
                      const Text(
                        'Sign in to your account',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827), // text-gray-900
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Subtitle
                      const Text(
                        'Access your patient portal and medical records',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF4B5563), // text-gray-600
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                  // Login Card
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 32,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Error Message
                        if (_error.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2), // bg-red-50
                              border: Border.all(
                                color: const Color(
                                  0xFFFECACA,
                                ), // border-red-200
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              _error,
                              style: const TextStyle(
                                color: Color(0xFFB91C1C), // text-red-700
                                fontSize: 14,
                              ),
                            ),
                          ),

                        // Email Field
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Email address',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF374151), // text-gray-700
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                hintText: 'you@example.com',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF9CA3AF),
                                ),
                                prefixIcon: const Icon(
                                  Icons.mail_outline,
                                  color: Color(0xFF9CA3AF), // text-gray-400
                                  size: 20,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD1D5DB),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD1D5DB),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF3B82F6), // ring-blue-500
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Password Field
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Password',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF374151), // text-gray-700
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextField(
                              controller: _passwordController,
                              obscureText: !_showPassword,
                              decoration: InputDecoration(
                                hintText: '••••••••',
                                hintStyle: const TextStyle(
                                  color: Color(0xFF9CA3AF),
                                ),
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  color: Color(0xFF9CA3AF), // text-gray-400
                                  size: 20,
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _showPassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: const Color(0xFF6B7280),
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _showPassword = !_showPassword;
                                    });
                                  },
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD1D5DB),
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: Color(0xFFD1D5DB),
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(6),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF3B82F6), // ring-blue-500
                                    width: 2,
                                  ),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Forgot Password
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () {},
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: const Size(0, 0),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Forgot password?',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF2563EB), // text-blue-600
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Sign In Button
                        SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(
                                0xFF2563EB,
                              ), // bg-blue-600
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              elevation: 0,
                            ),
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Sign in',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Divider
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 1,
                                color: const Color(0xFFD1D5DB), // bg-gray-300
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF6B7280), // text-gray-500
                                ),
                              ),
                            ),
                            Expanded(
                              child: Container(
                                height: 1,
                                color: const Color(0xFFD1D5DB), // bg-gray-300
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Fingerprint Login Button
                        FingerprintLogin(
                          onSuccess: () {
                            Navigator.pushReplacementNamed(
                              context,
                              AppRoutes.home,
                            );
                          },
                        ),

                        const SizedBox(height: 12),

                        // Google Sign-In Button (full widget, not just the icon)
                        SignInWithGoogle(
                          rememberMe: false, // or true, depending on your logic
                        ),

                        // Sign Up Link
                        Center(
                          child: Wrap(
                            alignment: WrapAlignment.center,
                            children: [
                              const Text(
                                "Don't have an account? ",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF374151), // text-gray-700
                                ),
                              ),
                              GestureDetector(
                                onTap: () {
                                  Navigator.pushNamed(
                                    context,
                                    AppRoutes.signUp,
                                  );
                                },
                                child: const Text(
                                  'Create an account',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFF2563EB), // text-blue-600
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Footer
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        const Text(
                          'By signing in, you agree to our ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4B5563), // text-gray-600
                          ),
                        ),
                        GestureDetector(
                          onTap: () {},
                          child: const Text(
                            'Terms',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2563EB), // text-blue-600
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        const Text(
                          ' & ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF4B5563),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {},
                          child: const Text(
                            'Privacy Policy',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF2563EB), // text-blue-600
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
