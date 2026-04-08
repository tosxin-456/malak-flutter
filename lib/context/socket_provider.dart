import 'dart:async';
import 'package:flutter/material.dart';
import 'package:malak/config/api_config.dart';
import 'package:malak/services/storage_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

// ─── SocketNotifier (ChangeNotifier equivalent of React SocketContext) ────────

class SocketNotifier extends ChangeNotifier {
  IO.Socket? _socket;
  bool _isConnected = false;
  String? _userId;
  final Set<String> _onlineUsers = {};

  IO.Socket? get socket => _socket;
  bool get isConnected => _isConnected;
  String? get userId => _userId;
  Set<String> get onlineUsers => Set.unmodifiable(_onlineUsers);

  /// Call this once after the user is authenticated (pass in the userId).
  Future<void> init(String userId) async {
    if (_socket != null && _userId == userId) return; // already initialised

    _userId = userId;

    final token = await StorageService.getToken();
    if (token == null || token.isEmpty) {
      debugPrint('SocketNotifier: no token, skipping socket connection');
      return;
    }

    // Tear down any previous socket before creating a new one
    await dispose();
    _userId = userId; // restore after dispose

    final socketInstance = IO.io(
      SOCKET_IO,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setTimeout(20000)
          .setAuth({'token': token})
          .build(),
    );

    socketInstance.onConnect((_) {
      debugPrint('Socket connected: ${socketInstance.id}');
      _isConnected = true;
      socketInstance.emit('user:online', userId);
      notifyListeners();
    });

    socketInstance.onDisconnect((reason) {
      debugPrint('Socket disconnected: $reason');
      _isConnected = false;
      notifyListeners();
    });

    socketInstance.onConnectError((err) {
      debugPrint('Socket connect error: $err');
      _isConnected = false;
      notifyListeners();
    });

    socketInstance.onError((err) {
      debugPrint('Socket error: $err');
    });

    socketInstance.on('user_status_update', (data) {
      if (data is Map) {
        final uid = data['userId'] as String?;
        final status = data['status'] as String?;
        if (uid == null) return;
        if (status == 'online') {
          _onlineUsers.add(uid);
        } else {
          _onlineUsers.remove(uid);
        }
        notifyListeners();
      }
    });

    _socket = socketInstance;
    notifyListeners();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void joinChat(String chatId) => _emit('join_chat', chatId);
  void leaveChat(String chatId) => _emit('leave_chat', chatId);

  void sendMessage(String chatId, String text, {String messageType = 'text'}) =>
      _emit('send_message', {
        'chatId': chatId,
        'text': text,
        'messageType': messageType,
      });

  void joinConsultation(String consultId) => _emit('consult:join', consultId);

  void sendConsultMessage(
    String consultId,
    String text, {
    String messageType = 'text',
  }) => _emit('consult:send_message', {
    'consultId': consultId,
    'text': text,
    'messageType': messageType,
  });

  void checkUserOnline(String targetUserId, void Function(bool) callback) {
    if (_socket == null || !_isConnected) {
      callback(false);
      return;
    }
    _socket!.emitWithAck(
      'user:isOnline',
      targetUserId,
      ack: (data) => callback(data == true),
    );
  }

  bool isUserOnline(String targetUserId) => _onlineUsers.contains(targetUserId);

  void emit(String event, dynamic data) => _emit(event, data);

  void _emit(String event, dynamic data) {
    if (_socket == null || !_isConnected) {
      debugPrint('SocketNotifier: not connected, cannot emit "$event"');
      return;
    }
    _socket!.emit(event, data);
  }

  @override
  Future<void> dispose() async {
    _socket?.disconnect();
    _socket?.destroy();
    _socket = null;
    _isConnected = false;
    super.dispose();
  }
}

// ─── SocketProvider widget ────────────────────────────────────────────────────

/// Wrap your app (or the subtree that needs socket access) with this widget.
///
/// ```dart
/// SocketProvider(
///   notifier: socketNotifier,   // created once, e.g. in main.dart
///   child: MaterialApp(...),
/// )
/// ```
class SocketProvider extends InheritedNotifier<SocketNotifier> {
  const SocketProvider({
    Key? key,
    required SocketNotifier notifier,
    required Widget child,
  }) : super(key: key, notifier: notifier, child: child);

  /// Access the notifier from any descendant widget.
  static SocketNotifier of(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<SocketProvider>();
    assert(
      provider != null,
      'No SocketProvider found in context. Wrap your widget tree with SocketProvider.',
    );
    return provider!.notifier!;
  }
}
