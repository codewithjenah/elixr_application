class ChatMessage {
  static const maximumBodyLength = 2000;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.createdAt,
    this.body,
    this.editedAt,
    this.deletedAt,
    this.legacyMovementName,
    this.isMigratedCoaching = false,
    this.deliveryState = ChatDeliveryState.sent,
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String? body;
  final DateTime createdAt;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final String? legacyMovementName;
  final bool isMigratedCoaching;
  final ChatDeliveryState deliveryState;

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null && deletedAt == null;

  static String? validateBody(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.length > maximumBodyLength) {
      return 'Message must be 1 to $maximumBodyLength characters.';
    }
    return null;
  }

  static ChatMessage? tryFromMap(
    Map<String, dynamic> map, {
    required String id,
    required String conversationId,
    required DateTime? Function(dynamic value) readDate,
    ChatDeliveryState deliveryState = ChatDeliveryState.sent,
  }) {
    final senderId = map['sender_id'];
    final createdAt = readDate(map['created_at']);
    final body = map['body'];
    final deletedAt = readDate(map['deleted_at']);
    if (id.trim().isEmpty ||
        conversationId.trim().isEmpty ||
        senderId is! String ||
        senderId.trim().isEmpty ||
        createdAt == null ||
        (deletedAt == null &&
            (body is! String ||
                body.trim().isEmpty ||
                body.length > maximumBodyLength)) ||
        (deletedAt != null && body != null)) {
      return null;
    }
    final editedAt = readDate(map['edited_at']);
    if (editedAt != null && editedAt.isBefore(createdAt)) return null;
    if (deletedAt != null && deletedAt.isBefore(createdAt)) return null;
    final legacy = map['legacy_coaching'];
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      body: body as String?,
      createdAt: createdAt,
      editedAt: editedAt,
      deletedAt: deletedAt,
      legacyMovementName: legacy is Map && legacy['movement_name'] is String
          ? legacy['movement_name'] as String
          : null,
      isMigratedCoaching: legacy is Map,
      deliveryState: deliveryState,
    );
  }

  ChatMessage copyWith({ChatDeliveryState? deliveryState}) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    body: body,
    createdAt: createdAt,
    editedAt: editedAt,
    deletedAt: deletedAt,
    legacyMovementName: legacyMovementName,
    isMigratedCoaching: isMigratedCoaching,
    deliveryState: deliveryState ?? this.deliveryState,
  );

  ChatMessage withEditedBody(String value, DateTime timestamp) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    body: value,
    createdAt: createdAt,
    editedAt: timestamp,
    deletedAt: null,
    legacyMovementName: legacyMovementName,
    isMigratedCoaching: isMigratedCoaching,
    deliveryState: deliveryState,
  );

  ChatMessage asDeleted(DateTime timestamp) => ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    createdAt: createdAt,
    editedAt: null,
    deletedAt: timestamp,
    legacyMovementName: legacyMovementName,
    isMigratedCoaching: isMigratedCoaching,
    deliveryState: deliveryState,
  );
}

enum ChatDeliveryState { sending, sent, error }
