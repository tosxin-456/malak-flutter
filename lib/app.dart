import 'package:flutter/material.dart';
import 'routes/app_routes.dart';

class MalakApp extends StatelessWidget {
  const MalakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Malak',
      debugShowCheckedModeBanner: false,
      initialRoute: AppRoutes.signIn,
      routes: AppRoutes.routes,
      theme: ThemeData(
        fontFamily: 'Montserrat',
        primarySwatch: Colors.blue,
        // Set a heavier default font weight
       textTheme: const TextTheme(
          bodyLarge: TextStyle(fontWeight: FontWeight.w600), // Semibold
          bodyMedium: TextStyle(fontWeight: FontWeight.w600), // Semibold
          bodySmall: TextStyle(fontWeight: FontWeight.w600), // Semibold
          titleLarge: TextStyle(fontWeight: FontWeight.w800), // Extra bold
          titleMedium: TextStyle(fontWeight: FontWeight.w700), // Bold
          titleSmall: TextStyle(fontWeight: FontWeight.w700), // Bold
          labelLarge: TextStyle(
            fontWeight: FontWeight.w700,
          ), // Bold for buttons
        ),
        // Also set default text button and elevated button styles
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            textStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
