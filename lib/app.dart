import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/context/call_provider.dart';
import 'package:malak/context/socket_provider.dart';
import 'package:malak/services/storage_service.dart';
import 'package:malak/widgets/global_call_ui.dart';
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
  bool _disposed = false;

  final SocketNotifier _socketNotifier = SocketNotifier();

  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  @override
  void dispose() {
    _disposed = true;
    _socketNotifier.dispose();
    super.dispose();
  }

  Future<void> _fetchProfile() async {
    final token = await StorageService.getToken();

    // Guard after every await
    if (_disposed || !mounted) return;

    if (token == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/users/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );

      // Guard immediately after the http await before ANY usage
      if (_disposed || !mounted) return;

      if (res.statusCode == 200) {
        final user = json.decode(res.body) as Map<String, dynamic>;

        setState(() => _user = user);

        final userId = user['_id']?.toString() ?? '';
        if (userId.isNotEmpty) {
          // Guard right before init in case dispose() was called
          // between the setState and this point
          if (_disposed) return;
          await _socketNotifier.init(userId);
        }
      }
    } catch (e) {
      debugPrint('Error fetching profile: $e');
    } finally {
      if (!_disposed && mounted) {
        setState(() => _loading = false);
      }
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

    return SocketProvider(
      notifier: _socketNotifier,
      child: MultiProvider(
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
          builder: (context, child) {
            return _CallOverlayWrapper(child: child ?? const SizedBox.shrink());
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CallOverlayWrapper
// ─────────────────────────────────────────────────────────────────────────────
class _CallOverlayWrapper extends StatelessWidget {
  final Widget child;
  const _CallOverlayWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return Material(
      child: Stack(
        children: [
          child,
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
