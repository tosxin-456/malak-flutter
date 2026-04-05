import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

class SignUpWithGoogle extends StatefulWidget {
  const SignUpWithGoogle({super.key});

  @override
  State<SignUpWithGoogle> createState() => _SignUpWithGoogleState();
}

class _SignUpWithGoogleState extends State<SignUpWithGoogle> {
  bool isLoading = false;
  String error = "";

  final GoogleSignIn _googleSignIn = GoogleSignIn(scopes: ['email', 'profile']);

  Future<void> signUpWithGoogle() async {
    setState(() {
      isLoading = true;
      error = "";
    });

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        setState(() {
          error = "Google signup was cancelled.";
          isLoading = false;
        });
        return;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      final accessToken = googleAuth.accessToken;

      final response = await http.post(
        Uri.parse("YOUR_API_BASE_URL/users/google-auth"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"access_token": accessToken}),
      );

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData["message"] ?? "Server error");
      }

      final data = jsonDecode(response.body);
      final token = data["token"];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("token", token);
      await prefs.setString("fullName", data["user"]);

      Map<String, dynamic> decodedToken = JwtDecoder.decode(token);
      final role = decodedToken["role"];

      if (!mounted) return;

      if (role != "patient") {
        Navigator.pushReplacementNamed(context, "/login-type");
        return;
      }

      final hasCartBeforeLogin = prefs.getString("cart_before_login");

      if (hasCartBeforeLogin != null) {
        Navigator.pushReplacementNamed(context, "/market-place");
      } else {
        await Future.delayed(const Duration(seconds: 1));
        Navigator.pushReplacementNamed(context, "/dashboard");
      }
    } catch (e) {
      setState(() {
        error = e.toString().replaceAll("Exception: ", "");
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (error.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(error, style: const TextStyle(color: Colors.red)),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.red),
                  onPressed: () {
                    setState(() => error = "");
                  },
                ),
              ],
            ),
          ),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: isLoading ? null : signUpWithGoogle,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.blue,
              side: const BorderSide(color: Colors.blue),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.login),
                      SizedBox(width: 10),
                      Text("Sign up with Google"),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
