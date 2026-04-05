import 'package:flutter/material.dart';
import 'package:malak/screens/appointments_screen.dart';
import 'package:malak/screens/chat_screen.dart';
import 'package:malak/screens/doctor_availability.dart';
import 'package:malak/screens/login_type.dart';
import 'package:malak/screens/message_screen.dart';
import 'package:malak/screens/profile_screen.dart';
import '../screens/home_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/sign_in_screen.dart';
import '../screens/sign_up_screen.dart';
import '../screens/otp_screen.dart';
import '../screens/initial_screen.dart';
import '../layouts/navigation_layout.dart';

class AppRoutes {
  static const String initial = '/';
  static const String home = '/home';
  static const String settings = '/settings';
  static const String signIn = '/sign-in';
  static const String signUp = '/sign-up';
  static const String otpScreen = '/verify';
  static const String profile = '/profile';
  static const String appointments = '/appointments';
  static const String messages = '/messages';
  static const String doctorType = '/doctor-type';
  static const String loginType = '/login-type';
  static const String doctorAvailability = '/doctor-availability';
  static const String doctorDashboard = '/doctor-dashboard';
  static const String nurseDashboard = '/nurse-dashboard';

  static final Map<String, WidgetBuilder> routes = {
    // Auth / entry screens
    initial: (context) => const InitialScreen(),
    signIn: (context) => const SignInScreen(),
    signUp: (context) => const SignUpScreen(),
    otpScreen: (context) => const OtpVerificationPage(),
    profile: (context) => const ProfilePage(),
    loginType: (context) => const LoginTypeScreen(),
    doctorAvailability: (context) => const DoctorAvailabilityScreen(),

    // Screens with NavigationLayout
    home: (context) =>
        NavigationLayout(currentRoute: home, child: const HomeScreen()),
    appointments: (context) => NavigationLayout(
      currentRoute: appointments,
      child: const AppointmentsScreen(),
    ),

    settings: (context) =>
        NavigationLayout(currentRoute: settings, child: const SettingsScreen()),

    // Static messages list (all chats)
    messages: (context) =>
        NavigationLayout(currentRoute: messages, child: const MessageScreen()),
  };

  // Handles dynamic routes like /messages/:chatId
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final uri = Uri.parse(settings.name!);

    // Dynamic chat route: /messages/:chatId (plain ChatScreen, no layout)
    if (uri.pathSegments.length == 2 && uri.pathSegments[0] == 'messages') {
      final chatId = uri.pathSegments[1];
      return MaterialPageRoute(
        builder: (context) => ChatScreen(chatId: chatId),
        settings: settings,
      );
    }

    // Check static routes
    if (routes.containsKey(settings.name)) {
      return MaterialPageRoute(
        builder: routes[settings.name]!,
        settings: settings,
      );
    }

    // Unknown route fallback
    return MaterialPageRoute(
      builder: (context) =>
          const Scaffold(body: Center(child: Text('Route not found'))),
      settings: settings,
    );
  }
}
