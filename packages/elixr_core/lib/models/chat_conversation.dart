import 'chat_user.dart';

class ChatConversation {
  const ChatConversation({
    required this.id,
    required this.participants,
    required this.updatedAt,
    required this.unreadCounts,
    required this.readAt,
    this.clearedAt = const {},
    required this.status,
    this.lastMessageId,
    this.lastMessageBody,
    this.lastMessageSenderId,
    this.lastMessageAt,
  });

  final String id;
  final Map<String, ChatUser> participants;
  final String? lastMessageId;
  final String? lastMessageBody;
  final String? lastMessageSenderId;
  final DateTime? lastMessageAt;
  final DateTime updatedAt;
  final Map<String, int> unreadCounts;
  final Map<String, DateTime?> readAt;
  final Map<String, DateTime?> clearedAt;
  final String status;

  bool get isArchived => status == 'archived';

  ChatUser? otherParticipant(String currentUserId) {
    for (final entry in participants.entries) {
      if (entry.key != currentUserId) return entry.value;
    }
    return null;
  }

  int unreadFor(String userId) => unreadCounts[userId] ?? 0;

  DateTime? clearedAtFor(String userId) => clearedAt[userId];

  bool isClearedFor(String userId) {
    final cleared = clearedAtFor(userId);
    final latest = lastMessageAt;
    return cleared != null && (latest == null || !latest.isAfter(cleared));
  }

  static ChatConversation? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
    required DateTime? Function(dynamic value) readDate,
  }) {
    final rawParticipants = map['participant_snapshots'];
    final updatedAt = readDate(map['updated_at']);
    final status = map['status'];
    if (id.trim().isEmpty ||
        rawParticipants is! Map ||
        updatedAt == null ||
        (status != 'active' && status != 'archived')) {
      return null;
    }
    final participants = <String, ChatUser>{};
    for (final entry in rawParticipants.entries) {
      if (entry.key is! String || entry.value is! Map) continue;
      final user = ChatUser.tryFromMap(
        Map<String, dynamic>.from(entry.value as Map),
        id: entry.key as String,
      );
      if (user != null) participants[user.id] = user;
    }
    if (participants.isEmpty) return null;
    final unread = <String, int>{};
    final rawUnread = map['unread_counts'];
    if (rawUnread is Map) {
      for (final entry in rawUnread.entries) {
        if (entry.key is String && entry.value is int && entry.value >= 0) {
          unread[entry.key as String] = entry.value as int;
        }
      }
    }
    final readAt = <String, DateTime?>{};
    final rawReadAt = map['read_at'];
    if (rawReadAt is Map) {
      for (final entry in rawReadAt.entries) {
        if (entry.key is String) {
          readAt[entry.key as String] = readDate(entry.value);
        }
      }
    }
    final clearedAt = <String, DateTime?>{};
    final rawClearedAt = map['cleared_at'];
    if (rawClearedAt is Map) {
      for (final entry in rawClearedAt.entries) {
        if (entry.key is String) {
          clearedAt[entry.key as String] = readDate(entry.value);
        }
      }
    }
    return ChatConversation(
      id: id,
      participants: participants,
      lastMessageId: map['last_message_id'] is String
          ? map['last_message_id'] as String
          : null,
      lastMessageBody: map['last_message_body'] is String
          ? map['last_message_body'] as String
          : null,
      lastMessageSenderId: map['last_message_sender_id'] is String
          ? map['last_message_sender_id'] as String
          : null,
      lastMessageAt: readDate(map['last_message_at']),
      updatedAt: updatedAt,
      unreadCounts: unread,
      readAt: readAt,
      clearedAt: clearedAt,
      status: status,
    );
  }
}

class ChatBlockState {
  const ChatBlockState({
    required this.blockedByMe,
    required this.blockedByOther,
  });

  const ChatBlockState.none() : blockedByMe = false, blockedByOther = false;

  final bool blockedByMe;
  final bool blockedByOther;
  bool get cannotSend => blockedByMe || blockedByOther;
}
