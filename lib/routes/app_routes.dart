import 'package:flutter/material.dart';
import 'package:malak/screens/profile_screen.dart';
import '../screens/home_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/sign_in_screen.dart';
import '../screens/sign_up_screen.dart';
import '../screens/otp_screen.dart';
import '../screens/initial_screen.dart'; // <- new
import '../layouts/navigation_layout.dart';


class AppRoutes {
  static const String initial = '/';
  static const String home = '/home';
  static const String settings = '/settings';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String otpScreen = '/verify';
  static const String profile = '/profile';

 static final Map<String, WidgetBuilder> routes = {
    // ❌ No layout (auth / entry)
    initial: (context) => const InitialScreen(),
    signIn: (context) => const SignInScreen(),
    signUp: (context) => const SignUpScreen(),
    otpScreen: (context) => const OtpVerificationPage(),
    profile: (context) => const ProfilePage(),

    // ✅ With NavigationLayout
    home: (context) => NavigationLayout(
      currentRoute: AppRoutes.home,
      child: const HomeScreen(),
    ),

    settings: (context) => NavigationLayout(
      currentRoute: AppRoutes.settings,
      child: const SettingsScreen(),
    ),
  };

}
