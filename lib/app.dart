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
        fontFamily: 'Montserrat', // ✅ Only sets the font family
        primarySwatch: Colors.blue,
      ),
    );
  }
}
