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
    String? idempotencyKey,
  });

  /// Sends the canonical teacher-review result message.
  ///
  /// The submission id and review revision form an idempotency key, so a
  /// retry after a network or Firestore acknowledgement failure cannot create
  /// a second result message for the same revision.
  Future<ChatMessage> sendAssignmentResult({
    required ChatUser sender,
    required ChatUser recipient,
    required String movementTitle,
    required int earnedScore,
    required int maxScore,
    String? feedback,
    required String submissionId,
    required int reviewRevision,
  }) {
    final messageBody = formatAssignmentResultBody(
      movementTitle: movementTitle,
      earnedScore: earnedScore,
      maxScore: maxScore,
      feedback: feedback,
      submissionId: submissionId,
      reviewRevision: reviewRevision,
    );
    return sendMessage(
      sender: sender,
      recipient: recipient,
      body: messageBody,
      idempotencyKey: assignmentResultIdempotencyKey(
        submissionId: submissionId,
        reviewRevision: reviewRevision,
      ),
    );
  }

  static String formatAssignmentResultBody({
    required String movementTitle,
    required int earnedScore,
    required int maxScore,
    String? feedback,
    required String submissionId,
    required int reviewRevision,
  }) {
    if (movementTitle.trim().isEmpty || submissionId.trim().isEmpty) {
      throw ArgumentError('Assignment result identity is required.');
    }
    if (maxScore < 1 ||
        maxScore > 100 ||
        earnedScore < 0 ||
        earnedScore > maxScore) {
      throw ArgumentError('Assignment result score is outside its bounds.');
    }
    if (reviewRevision < 1) {
      throw ArgumentError.value(reviewRevision, 'reviewRevision');
    }
    final normalizedFeedback = feedback?.trim();
    final body = StringBuffer()
      ..writeln(movementTitle.trim())
      ..write('Score: $earnedScore/$maxScore');
    if (normalizedFeedback != null && normalizedFeedback.isNotEmpty) {
      body
        ..writeln()
        ..write('Feedback: $normalizedFeedback');
    }
    final messageBody = body.toString();
    final validation = ChatMessage.validateBody(messageBody);
    if (validation != null) throw ArgumentError(validation);
    return messageBody;
  }

  static String assignmentResultIdempotencyKey({
    required String submissionId,
    required int reviewRevision,
  }) {
    if (submissionId.trim().isEmpty || reviewRevision < 1) {
      throw ArgumentError('Assignment result idempotency identity is invalid.');
    }
    return '${submissionId.trim()}:$reviewRevision';
  }

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
