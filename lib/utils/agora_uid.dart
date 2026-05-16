/// Stable Agora numeric uid from app user id (1 .. 2^31-1).
int toAgoraUid(dynamic userId) {
  if (userId == null) return 1;

  if (userId is int) {
    final n = userId.abs();
    return (n % 2147483647).clamp(1, 2147483647);
  }

  final str = userId.toString();
  if (str.isEmpty) return 1;

  var hash = 0;
  for (var i = 0; i < str.length; i++) {
    hash = (hash * 31 + str.codeUnitAt(i)) & 0xFFFFFFFF;
  }
  final uid = hash % 2147483647;
  return uid == 0 ? 1 : uid;
}

/// Normalize to `voice` or `video`.
String normalizeCallType(dynamic callType) {
  final t = (callType?.toString() ?? 'voice').toLowerCase();
  if (t == 'video' || t == 'videocall') return 'video';
  return 'voice';
}
