import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:malak/config/api_config.dart';
import 'package:malak/context/call_provider.dart';
import 'package:malak/context/socket_provider.dart';
import 'package:malak/services/storage_service.dart';
import 'package:malak/widgets/global_call_ui.dart';
import 'package:malak/widgets/patient_consultation_listener.dart';
import 'package:malak/widgets/push_notification_bridge.dart';
import 'package:malak/services/firebase_messaging_service.dart';
import 'package:provider/provider.dart';
import 'routes/app_routes.dart';

class MalakApp extends StatefulWidget {
  const MalakApp({super.key});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static MalakAppState? of(BuildContext context) {
    return context.findAncestorStateOfType<MalakAppState>();
  }

  @override
  State<MalakApp> createState() => MalakAppState();
}

class MalakAppState extends State<MalakApp> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  bool _disposed = false;

  final SocketNotifier _socketNotifier = SocketNotifier();

  Map<String, dynamic>? get user => _user;

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

  /// Call after sign-in so socket, CallProvider, and FCM token are ready.
  Future<void> refreshSession() => _fetchProfile();

  Future<void> _fetchProfile() async {
    final token = await StorageService.getToken();

    if (_disposed || !mounted) return;

    if (token == null) {
      setState(() {
        _user = null;
        _loading = false;
      });
      return;
    }

    try {
      final res = await http.get(
        Uri.parse('$API_BASE_URL/users/profile'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (_disposed || !mounted) return;

      if (res.statusCode == 200) {
        final user = json.decode(res.body) as Map<String, dynamic>;

        final userId = user['_id']?.toString() ?? '';
        if (userId.isNotEmpty && !_disposed) {
          await _socketNotifier.init(userId);
          if (!_disposed) {
            await FirebaseMessagingService.instance.syncAfterAuth();
          }
        }

        if (!_disposed && mounted) {
          setState(() => _user = user);
        }
      } else if (!_disposed && mounted) {
        setState(() => _user = null);
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

    final userId = _user?['_id']?.toString() ?? '';

    return SocketProvider(
      notifier: _socketNotifier,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            key: ValueKey(userId),
            create: (_) => CallProvider(
              userId: userId,
              userInfo: _user ?? {},
              socketNotifier: _socketNotifier,
            ),
          ),
        ],
        child: MaterialApp(
          navigatorKey: MalakApp.navigatorKey,
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
            return PushNotificationBridge(
              child: _CallOverlayWrapper(child: child ?? const SizedBox.shrink()),
            );
          },
        ),
      ),
    );
  }
}

class _CallOverlayWrapper extends StatelessWidget {
  final Widget child;
  const _CallOverlayWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return PatientConsultationListener(
      child: Material(
        child: Stack(
          children: [
            child,
            Consumer<CallProvider>(
              builder: (context, cp, _) {
                if (cp.callMode == CallMode.idle) {
                  return const SizedBox.shrink();
                }
                return const Positioned.fill(child: GlobalCallUI());
              },
            ),
          ],
        ),
      ),
    );
  }
}
