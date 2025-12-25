import 'package:flutter/material.dart';
import '../screens/home_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/sign_in_screen.dart';
import '../screens/sign_up_screen.dart';

class AppRoutes {
  static const String home = '/';
  static const String settings = '/settings';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';

  static final Map<String, WidgetBuilder> routes = {
    home: (context) => const HomeScreen(),
    settings: (context) => const SettingsScreen(),
    signIn: (context) => const SignInScreen(),
    signUp: (context) => const SignUpScreen(),
  };
}
