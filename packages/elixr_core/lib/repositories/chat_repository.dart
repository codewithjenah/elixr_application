import '../models/chat_conversation.dart';
import '../models/chat_message.dart';
import '../models/chat_user.dart';

abstract class ChatMessageCursor {
  const ChatMessageCursor();
}

class ChatMessagePage {
  const ChatMessagePage({
    required this.messages,
    required this.hasMore,
    this.nextCursor,
  });

  final List<ChatMessage> messages;
  final bool hasMore;
  final ChatMessageCursor? nextCursor;
}

abstract class ChatRepository {
  static const defaultMessagePageSize = 40;

  static String conversationIdFor(String firstUserId, String secondUserId) {
    if (firstUserId.isEmpty ||
        secondUserId.isEmpty ||
        firstUserId == secondUserId) {
      throw ArgumentError('Conversation participants must be distinct.');
    }
    final ids = [firstUserId, secondUserId]..sort();
    return '${ids[0]}__${ids[1]}';
  }

  Future<List<ChatUser>> searchUsers(String query);
  Stream<List<ChatConversation>> watchInbox(String currentUserId);
  Stream<ChatMessagePage> watchMessages({
    required String conversationId,
    int pageSize = defaultMessagePageSize,
  });
  Future<ChatMessagePage> fetchOlderMessages({
    required String conversationId,
    required ChatMessageCursor startAfter,
    int pageSize = defaultMessagePageSize,
  });
  Future<ChatMessage> sendMessage({
    required ChatUser sender,
    required ChatUser recipient,
    required String body,
  });
  Future<void> editMessage({
    required String conversationId,
    required String messageId,
    required String currentUserId,
    required String body,
  });
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
    required String currentUserId,
  });
  Future<void> markRead({
    required String conversationId,
    required String currentUserId,
  });
  Future<void> markUnread({
    required String conversationId,
    required String currentUserId,
  });
  Future<void> clearConversation({
    required String conversationId,
    required String currentUserId,
  });
  Stream<ChatBlockState> watchBlockState({
    required String currentUserId,
    required String otherUserId,
  });
  Future<void> blockUser({
    required String currentUserId,
    required String blockedUserId,
  });
  Future<void> unblockUser({
    required String currentUserId,
    required String blockedUserId,
  });
}
