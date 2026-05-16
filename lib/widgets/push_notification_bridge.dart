import 'package:flutter/material.dart';
import 'package:malak/app.dart';
import 'package:malak/context/call_provider.dart';
import 'package:malak/services/firebase_messaging_service.dart';
import 'package:provider/provider.dart';

/// Routes FCM payloads to call UI, consultation modal, or chat screens.
class PushNotificationBridge extends StatefulWidget {
  final Widget child;

  const PushNotificationBridge({super.key, required this.child});

  @override
  State<PushNotificationBridge> createState() => _PushNotificationBridgeState();
}

class _PushNotificationBridgeState extends State<PushNotificationBridge> {
  @override
  void initState() {
    super.initState();
    FirebaseMessagingService.instance.onPushReceived = _onPush;
  }

  @override
  void dispose() {
    if (FirebaseMessagingService.instance.onPushReceived == _onPush) {
      FirebaseMessagingService.instance.onPushReceived = null;
    }
    super.dispose();
  }

  void _onPush(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type']?.toString() ?? '';
    final nav = MalakApp.navigatorKey.currentState;
    if (nav == null) return;

    switch (type) {
      case 'call_incoming':
        try {
          context.read<CallProvider>().handleIncomingFromPush(data);
        } catch (e) {
          debugPrint('Call push handler error: $e');
        }
        break;

      case 'consultation_incoming':
        FirebaseMessagingService.instance.onConsultationIncoming?.call(data);
        break;

      case 'chat_message':
        final chatId = data['chatId']?.toString();
        if (chatId != null && chatId.isNotEmpty) {
          nav.pushNamed('/messages/$chatId');
        }
        break;

      case 'consult_message':
        final consultId = data['consultId']?.toString();
        if (consultId != null && consultId.isNotEmpty) {
          nav.pushNamed('/consultation-room/$consultId/live');
        }
        break;

      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
