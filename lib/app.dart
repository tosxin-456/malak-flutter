import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/context/call_provider.dart';
import 'package:malak/services/storage_service.dart';
import 'package:malak/widgets/global_call_ui.dart'; // ← import the new file
import 'package:provider/provider.dart';
import 'routes/app_routes.dart';

class MalakApp extends StatefulWidget {
  const MalakApp({super.key});

  @override
  State<MalakApp> createState() => _MalakAppState();
}

class _MalakAppState extends State<MalakApp> {
  Map<String, dynamic>? _user;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final token = await StorageService.getToken();

    if (token == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/users/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (res.statusCode == 200) {
        setState(() => _user = json.decode(res.body));
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => CallProvider(
            userId: _user?['_id']?.toString() ?? '',
            userInfo: _user ?? {},
          ),
        ),
      ],
      child: MaterialApp(
        title: 'Malak',
        debugShowCheckedModeBanner: false,
        initialRoute: AppRoutes.signIn,
        routes: AppRoutes.routes,
        onGenerateRoute: AppRoutes.onGenerateRoute,
        theme: ThemeData(
          textTheme: GoogleFonts.montserratTextTheme().apply(
            bodyColor: Colors.black,
            displayColor: Colors.black,
          ),
          fontFamilyFallback: const ['Montserrat'],
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              textStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        // ── KEY: use builder to wrap every route's scaffold
        // with the GlobalCallUI overlay ──────────────────────────────────
        builder: (context, child) {
          return _CallOverlayWrapper(child: child ?? const SizedBox.shrink());
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CallOverlayWrapper
//
// Wraps the entire app in a Stack. GlobalCallUI renders on top of everything
// — including the bottom nav, app bar, and keyboard — on all screens,
// exactly like the React <GlobalCallUI /> rendered outside the router.
// ─────────────────────────────────────────────────────────────────────────────
class _CallOverlayWrapper extends StatelessWidget {
  final Widget child;
  const _CallOverlayWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        children: [
          // Normal app content
          child,

          // Global call UI — floats above everything
          Consumer<CallProvider>(
            builder: (context, cp, _) {
              if (cp.callMode == CallMode.idle) return const SizedBox.shrink();
              return const Positioned.fill(child: GlobalCallUI());
            },
          ),
        ],
      ),
    );
  }
}
