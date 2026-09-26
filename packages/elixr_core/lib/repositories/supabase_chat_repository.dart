import 'dart:async';

import 'package:supabase/supabase.dart';

import '../database/supabase_support.dart';
import '../models/chat_conversation.dart';
import '../models/chat_exception.dart';
import '../models/chat_message.dart';
import '../models/chat_user.dart';
import 'chat_repository.dart';

/// Participant-scoped direct messages. Reads stream through Realtime under
/// RLS; sends and read-state changes are single-transaction RPCs.
class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository({SupabaseClient? client}) : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  String? get _currentUid => _client.auth.currentUser?.id;

  @override
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
    return sendMessage(
      sender: sender,
      recipient: recipient,
      body: ChatRepository.formatAssignmentResultBody(
        movementTitle: movementTitle,
        earnedScore: earnedScore,
        maxScore: maxScore,
        feedback: feedback,
        submissionId: submissionId,
        reviewRevision: reviewRevision,
      ),
      idempotencyKey: ChatRepository.assignmentResultIdempotencyKey(
        submissionId: submissionId,
        reviewRevision: reviewRevision,
      ),
    );
  }

  @override
  Future<List<ChatUser>> searchUsers(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2 || normalized.length > 80) {
      throw const ChatException(ChatError.invalidQuery);
    }
    final uid = _currentUid;
    if (uid == null) throw const ChatException(ChatError.unauthenticated);
    try {
      final response = await rpcMap(_client, 'search_chat_users', {
        'p_query': normalized,
      });
      final results = response['results'];
      if (results is! List) throw const ChatException(ChatError.unknown);
      return rowsFrom(results)
          .map((row) => ChatUser.tryFromMap(row, id: row['id'] as String?))
          .whereType<ChatUser>()
          .where((user) => user.id != uid)
          .take(20)
          .toList(growable: false);
    } catch (error) {
      throw _classify(error);
    }
  }

  @override
  Stream<List<ChatConversation>> watchInbox(String currentUserId) {
    // RLS limits the stream to conversations the caller participates in.
    return _client
        .from('chat_conversations')
        .stream(primaryKey: ['id'])
        .order('updated_at')
        .limit(100)
        .map(
          (rows) => rows
              .map(
                (row) => ChatConversation.tryFromMap(
                  compactRow(row),
                  id: row['id'] as String,
                  readDate: _date,
                ),
              )
              .whereType<ChatConversation>()
              .where((item) => !item.isClearedFor(currentUserId))
              .toList(growable: false),
        )
        .handleError((Object error) => throw _classify(error));
  }

  @override
  Stream<ChatMessagePage> watchMessages({
    required String conversationId,
    int pageSize = ChatRepository.defaultMessagePageSize,
  }) {
    _validatePageSize(pageSize);
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['conversation_id', 'id'])
        .eq('conversation_id', conversationId)
        .order('created_at')
        .limit(pageSize)
        .map((rows) {
          final sorted = [...rows]..sort(_newestFirst);
          return ChatMessagePage(
            messages: _messages(conversationId, sorted),
            hasMore: sorted.length == pageSize,
            nextCursor: sorted.isEmpty
                ? null
                : _SupabaseChatCursor.fromRow(sorted.last),
          );
        })
        .handleError((Object error) => throw _classify(error));
  }

  @override
  Future<ChatMessagePage> fetchOlderMessages({
    required String conversationId,
    required ChatMessageCursor startAfter,
    int pageSize = ChatRepository.defaultMessagePageSize,
  }) async {
    _validatePageSize(pageSize);
    if (startAfter is! _SupabaseChatCursor) {
      throw ArgumentError('Cursor belongs to another repository.');
    }
    try {
      final rows = await _client
          .from('chat_messages')
          .select()
          .eq('conversation_id', conversationId)
          .or(startAfter.keysetFilter)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .limit(pageSize + 1);
      final page = rows.take(pageSize).toList(growable: false);
      return ChatMessagePage(
        messages: _messages(conversationId, page),
        hasMore: rows.length > pageSize,
        nextCursor: rows.length > pageSize && page.isNotEmpty
            ? _SupabaseChatCursor.fromRow(page.last)
            : null,
      );
    } catch (error) {
      throw _classify(error);
    }
  }

  @override
  Future<ChatMessage> sendMessage({
    required ChatUser sender,
    required ChatUser recipient,
    required String body,
    String? idempotencyKey,
  }) async {
    final validation = ChatMessage.validateBody(body);
    if (validation != null) {
      throw ChatException(ChatError.invalidMessage, validation);
    }
    if (_currentUid != sender.id || sender.id == recipient.id) {
      throw const ChatException(ChatError.unauthenticated);
    }
    final key = idempotencyKey?.trim();
    if (key != null && (key.isEmpty || key.length > 256)) {
      throw const ChatException(ChatError.invalidMessage);
    }
    final trimmed = body.trim();
    try {
      final result = await rpcMap(_client, 'send_chat_message', {
        'p_recipient_id': recipient.id,
        'p_body': trimmed,
        'p_idempotency_key': key,
      });
      final messageId = result['message_id'];
      final conversationId = result['conversation_id'];
      if (messageId is! String || conversationId is! String) {
        throw const ChatException(ChatError.unknown);
      }
      return ChatMessage(
        id: messageId,
        conversationId: conversationId,
        senderId: sender.id,
        body: trimmed,
        createdAt: _date(result['created_at']) ?? DateTime.now().toUtc(),
      );
    } catch (error) {
      throw _classify(error);
    }
  }

  Future<void> _call(String function, Map<String, dynamic> params) async {
    try {
      await _client.rpc<dynamic>(function, params: params);
    } catch (error) {
      throw _classify(error);
    }
  }

  @override
  Future<void> editMessage({
    required String conversationId,
    required String messageId,
    required String currentUserId,
    required String body,
  }) {
    final validation = ChatMessage.validateBody(body);
    if (validation != null) {
      throw ChatException(ChatError.invalidMessage, validation);
    }
    return _call('edit_chat_message', {
      'p_conversation_id': conversationId,
      'p_message_id': messageId,
      'p_body': body.trim(),
    });
  }

  @override
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
    required String currentUserId,
  }) => _call('delete_chat_message', {
    'p_conversation_id': conversationId,
    'p_message_id': messageId,
  });

  @override
  Future<void> markRead({
    required String conversationId,
    required String currentUserId,
  }) => _call('update_chat_read_state', {
    'p_conversation_id': conversationId,
    'p_action': 'read',
  });

  @override
  Future<void> markUnread({
    required String conversationId,
    required String currentUserId,
  }) => _call('update_chat_read_state', {
    'p_conversation_id': conversationId,
    'p_action': 'unread',
  });

  @override
  Future<void> clearConversation({
    required String conversationId,
    required String currentUserId,
  }) => _call('update_chat_read_state', {
    'p_conversation_id': conversationId,
    'p_action': 'clear',
  });

  @override
  Stream<ChatBlockState> watchBlockState({
    required String currentUserId,
    required String otherUserId,
  }) {
    late StreamController<ChatBlockState> controller;
    StreamSubscription<List<Map<String, dynamic>>>? outgoing;
    StreamSubscription<List<Map<String, dynamic>>>? incoming;
    bool? byMe;
    bool? byOther;
    void emit() {
      if (controller.isClosed || byMe == null || byOther == null) return;
      controller.add(
        ChatBlockState(blockedByMe: byMe!, blockedByOther: byOther!),
      );
    }

    controller = StreamController<ChatBlockState>(
      onListen: () {
        outgoing = _client
            .from('chat_blocks')
            .stream(primaryKey: ['blocker_id', 'blocked_id'])
            .eq('blocker_id', currentUserId)
            .listen((rows) {
              byMe = rows.any((row) => row['blocked_id'] == otherUserId);
              emit();
            }, onError: controller.addError);
        incoming = _client
            .from('chat_blocks')
            .stream(primaryKey: ['blocker_id', 'blocked_id'])
            .eq('blocked_id', currentUserId)
            .listen((rows) {
              byOther = rows.any((row) => row['blocker_id'] == otherUserId);
              emit();
            }, onError: controller.addError);
      },
      onCancel: () async {
        await outgoing?.cancel();
        await incoming?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> blockUser({
    required String currentUserId,
    required String blockedUserId,
  }) async {
    if (currentUserId == blockedUserId) {
      throw const ChatException(ChatError.permissionDenied);
    }
    try {
      await _client.from('chat_blocks').upsert({
        'blocker_id': currentUserId,
        'blocked_id': blockedUserId,
      }, ignoreDuplicates: true);
    } catch (error) {
      throw _classify(error);
    }
  }

  @override
  Future<void> unblockUser({
    required String currentUserId,
    required String blockedUserId,
  }) async {
    try {
      await _client
          .from('chat_blocks')
          .delete()
          .eq('blocker_id', currentUserId)
          .eq('blocked_id', blockedUserId);
    } catch (error) {
      throw _classify(error);
    }
  }

  static int _newestFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byTime = (_date(b['created_at']) ?? DateTime(0)).compareTo(
      _date(a['created_at']) ?? DateTime(0),
    );
    if (byTime != 0) return byTime;
    return '${b['id']}'.compareTo('${a['id']}');
  }

  static List<ChatMessage> _messages(
    String conversationId,
    List<Map<String, dynamic>> rows,
  ) {
    return rows
        .map(
          (row) => ChatMessage.tryFromMap(
            // Keep explicit nulls: deleted/edited markers are nullable fields.
            row,
            id: row['id'] as String,
            conversationId: conversationId,
            readDate: _date,
            deliveryState: ChatDeliveryState.sent,
          ),
        )
        .whereType<ChatMessage>()
        .toList(growable: false);
  }

  static DateTime? _date(dynamic value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }

  static void _validatePageSize(int value) {
    if (value < 1 || value > 100) {
      throw ArgumentError.value(value, 'pageSize', 'must be 1..100');
    }
  }

  static ChatException _classify(Object error) {
    if (error is ChatException) return error;
    if (isBackendUnavailableError(error)) {
      return const ChatException(ChatError.network);
    }
    return switch (backendErrorCode(error)) {
      'blocked' => const ChatException(ChatError.blocked),
      'recipient_unavailable' => const ChatException(ChatError.notFound),
      'conversation_unavailable' ||
      'idempotency_conflict' ||
      'forbidden' => const ChatException(ChatError.permissionDenied),
      'not_found' => const ChatException(ChatError.notFound),
      'rate_limited' => const ChatException(ChatError.rateLimited),
      'invalid_query' => const ChatException(ChatError.invalidQuery),
      'invalid_payload' ||
      'invalid_message' => const ChatException(ChatError.invalidMessage),
      'unauthenticated' => const ChatException(ChatError.unauthenticated),
      _ when isPermissionDeniedError(error) => const ChatException(
        ChatError.permissionDenied,
      ),
      _ => const ChatException(ChatError.unknown),
    };
  }
}

class _SupabaseChatCursor extends ChatMessageCursor {
  const _SupabaseChatCursor(this.createdAtUtc, this.id);

  factory _SupabaseChatCursor.fromRow(Map<String, dynamic> row) =>
      _SupabaseChatCursor(
        DateTime.parse(row['created_at'] as String).toUtc().toIso8601String(),
        row['id'] as String,
      );

  final String createdAtUtc;
  final String id;

  String get keysetFilter =>
      'created_at.lt.$createdAtUtc,and(created_at.eq.$createdAtUtc,id.lt.$id)';
}
