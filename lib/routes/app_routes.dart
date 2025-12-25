import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/sign_in_screen.dart';
import '../screens/sign_up_screen.dart';
import '../screens/otp_screen.dart';
import '../screens/initial_screen.dart'; // <- new

class AppRoutes {
  static const String initial = '/';
  static const String home = '/home';
  static const String settings = '/settings';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String otpScreen = '/verify';

  static final Map<String, WidgetBuilder> routes = {
    initial: (context) => const InitialScreen(), // first screen
    home: (context) => const HomeScreen(),
    settings: (context) => const SettingsScreen(),
    signIn: (context) => const SignInScreen(),
    signUp: (context) => const SignUpScreen(),
    otpScreen: (context) => const OtpVerificationPage(),
  };
}
