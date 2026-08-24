import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../database/firestore_collections.dart';
import '../models/chat_conversation.dart';
import '../models/chat_exception.dart';
import '../models/chat_message.dart';
import '../models/chat_user.dart';
import 'chat_repository.dart';

class FirebaseChatRepository implements ChatRepository {
  FirebaseChatRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    Uri? apiBaseUri,
    HttpClient Function()? httpClientFactory,
    this.requestTimeout = const Duration(seconds: 10),
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance,
       apiBaseUri = apiBaseUri ?? Uri.parse(_configuredApiBaseUrl),
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  static const _configuredApiBaseUrl = String.fromEnvironment(
    'ELIXR_CHAT_API_BASE_URL',
    defaultValue: 'https://asia-southeast1-elixr-app-2026.cloudfunctions.net/',
  );

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final Uri apiBaseUri;
  final HttpClient Function() _httpClientFactory;
  final Duration requestTimeout;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _firestore.collection(FirestoreCollections.chatConversations);

  @override
  Future<List<ChatUser>> searchUsers(String query) async {
    final normalized = query.trim();
    if (normalized.length < 2 || normalized.length > 80) {
      throw const ChatException(ChatError.invalidQuery);
    }
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) {
      throw const ChatException(ChatError.unauthenticated);
    }

    final token = await firebaseUser.getIdToken(true);
    if (token == null || token.isEmpty) {
      throw const ChatException(ChatError.unauthenticated);
    }
    final endpoint = apiBaseUri
        .resolve('searchChatUsers')
        .replace(queryParameters: {'q': normalized});
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(endpoint).timeout(requestTimeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(requestTimeout);
      final payload = await utf8.decoder
          .bind(response)
          .join()
          .timeout(requestTimeout);
      if (response.statusCode == HttpStatus.tooManyRequests) {
        throw const ChatException(ChatError.rateLimited);
      }
      if (response.statusCode == HttpStatus.unauthorized) {
        throw const ChatException(ChatError.unauthenticated);
      }
      if (response.statusCode != HttpStatus.ok) {
        throw const ChatException(ChatError.network);
      }
      final decoded = jsonDecode(payload);
      final results = decoded is Map<String, dynamic>
          ? decoded['results']
          : null;
      if (results is! List) throw const ChatException(ChatError.unknown);
      return results
          .whereType<Map>()
          .map((value) => ChatUser.tryFromMap(Map<String, dynamic>.from(value)))
          .whereType<ChatUser>()
          .where((user) => user.id != firebaseUser.uid)
          .take(20)
          .toList(growable: false);
    } on ChatException {
      rethrow;
    } on TimeoutException {
      throw const ChatException(ChatError.network);
    } on SocketException {
      throw const ChatException(ChatError.network);
    } on FormatException {
      throw const ChatException(ChatError.unknown);
    } finally {
      client.close(force: true);
    }
  }

  @override
  Stream<List<ChatConversation>> watchInbox(String currentUserId) {
    return _conversations
        .where('participant_ids', arrayContains: currentUserId)
        .orderBy('updated_at', descending: true)
        .limit(100)
        .snapshots(includeMetadataChanges: true)
        .map(
          (snapshot) => snapshot.docs
              .map(_conversationFromDocument)
              .whereType<ChatConversation>()
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
    return _conversations
        .doc(conversationId)
        .collection(FirestoreCollections.chatMessages)
        .orderBy('created_at', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(pageSize)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
          final messages = snapshot.docs
              .map((doc) => _messageFromDocument(conversationId, doc))
              .whereType<ChatMessage>()
              .toList(growable: false);
          return ChatMessagePage(
            messages: messages,
            hasMore: snapshot.docs.length == pageSize,
            nextCursor: snapshot.docs.isEmpty
                ? null
                : _FirestoreChatCursor(snapshot.docs.last),
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
    if (startAfter is! _FirestoreChatCursor) {
      throw ArgumentError('Cursor belongs to another repository.');
    }
    try {
      final snapshot = await _conversations
          .doc(conversationId)
          .collection(FirestoreCollections.chatMessages)
          .orderBy('created_at', descending: true)
          .orderBy(FieldPath.documentId, descending: true)
          .startAfterDocument(startAfter.document)
          .limit(pageSize + 1)
          .get();
      final docs = snapshot.docs.take(pageSize).toList(growable: false);
      return ChatMessagePage(
        messages: docs
            .map((doc) => _messageFromDocument(conversationId, doc))
            .whereType<ChatMessage>()
            .toList(growable: false),
        hasMore: snapshot.docs.length > pageSize,
        nextCursor: snapshot.docs.length > pageSize && docs.isNotEmpty
            ? _FirestoreChatCursor(docs.last)
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
  }) async {
    final validation = ChatMessage.validateBody(body);
    if (validation != null) {
      throw ChatException(ChatError.invalidMessage, validation);
    }
    if (_auth.currentUser?.uid != sender.id || sender.id == recipient.id) {
      throw const ChatException(ChatError.unauthenticated);
    }
    final trimmedBody = body.trim();
    final conversationId = ChatRepository.conversationIdFor(
      sender.id,
      recipient.id,
    );
    final conversationRef = _conversations.doc(conversationId);
    final messageRef = conversationRef
        .collection(FirestoreCollections.chatMessages)
        .doc();

    try {
      await _firestore.runTransaction((transaction) async {
        final senderProfileRef = _firestore
            .collection(FirestoreCollections.users)
            .doc(sender.id);
        final recipientProfileRef = _firestore
            .collection(FirestoreCollections.users)
            .doc(recipient.id);
        final outgoingBlockRef = _blockRef(sender.id, recipient.id);
        final incomingBlockRef = _blockRef(recipient.id, sender.id);

        final senderProfile = await transaction.get(senderProfileRef);
        final recipientProfile = await transaction.get(recipientProfileRef);
        final outgoingBlock = await transaction.get(outgoingBlockRef);
        final incomingBlock = await transaction.get(incomingBlockRef);
        final existing = await transaction.get(conversationRef);

        if (!_isSupportedProfile(senderProfile.data()) ||
            !_isSupportedProfile(recipientProfile.data())) {
          throw const ChatException(ChatError.permissionDenied);
        }
        if (outgoingBlock.exists || incomingBlock.exists) {
          throw const ChatException(ChatError.blocked);
        }

        final current = existing.data();
        if (current != null && current['status'] != 'active') {
          throw const ChatException(ChatError.permissionDenied);
        }
        final unread = _intMap(current?['unread_counts']);
        unread[sender.id] = 0;
        unread[recipient.id] = (unread[recipient.id] ?? 0) + 1;
        final readAt = _dynamicMap(current?['read_at']);
        readAt.putIfAbsent(sender.id, () => FieldValue.serverTimestamp());
        readAt.putIfAbsent(recipient.id, () => null);

        transaction.set(messageRef, {
          'sender_id': sender.id,
          'body': trimmedBody,
          'created_at': FieldValue.serverTimestamp(),
          'edited_at': null,
          'deleted_at': null,
        });

        final conversationData = <String, dynamic>{
          'participant_ids': [sender.id, recipient.id]..sort(),
          'participant_snapshots': {
            sender.id: _snapshotForProfile(sender.id, senderProfile.data()!),
            recipient.id: _snapshotForProfile(
              recipient.id,
              recipientProfile.data()!,
            ),
          },
          'last_message_id': messageRef.id,
          'last_message_body': trimmedBody,
          'last_message_sender_id': sender.id,
          'last_message_at': FieldValue.serverTimestamp(),
          'unread_counts': unread,
          'read_at': readAt,
          'status': 'active',
          'updated_at': FieldValue.serverTimestamp(),
          if (!existing.exists) 'created_at': FieldValue.serverTimestamp(),
          'schema_version': 1,
        };
        transaction.set(
          conversationRef,
          conversationData,
          SetOptions(merge: true),
        );
      });
      return ChatMessage(
        id: messageRef.id,
        conversationId: conversationId,
        senderId: sender.id,
        body: trimmedBody,
        createdAt: DateTime.now().toUtc(),
      );
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
  }) async {
    final validation = ChatMessage.validateBody(body);
    if (validation != null) {
      throw ChatException(ChatError.invalidMessage, validation);
    }
    final conversationRef = _conversations.doc(conversationId);
    final messageRef = conversationRef
        .collection(FirestoreCollections.chatMessages)
        .doc(messageId);
    try {
      await _firestore.runTransaction((transaction) async {
        final conversation = await transaction.get(conversationRef);
        final message = await transaction.get(messageRef);
        if (!message.exists) throw const ChatException(ChatError.notFound);
        final data = message.data()!;
        if (data['sender_id'] != currentUserId || data['deleted_at'] != null) {
          throw const ChatException(ChatError.permissionDenied);
        }
        transaction.update(messageRef, {
          'body': body.trim(),
          'edited_at': FieldValue.serverTimestamp(),
        });
        if (conversation.data()?['last_message_id'] == messageId) {
          transaction.update(conversationRef, {
            'last_message_body': body.trim(),
          });
        }
      });
    } catch (error) {
      throw _classify(error);
    }
  }

  @override
  Future<void> deleteMessage({
    required String conversationId,
    required String messageId,
    required String currentUserId,
  }) async {
    final conversationRef = _conversations.doc(conversationId);
    final messageRef = conversationRef
        .collection(FirestoreCollections.chatMessages)
        .doc(messageId);
    try {
      await _firestore.runTransaction((transaction) async {
        final conversation = await transaction.get(conversationRef);
        final message = await transaction.get(messageRef);
        if (!message.exists) throw const ChatException(ChatError.notFound);
        final data = message.data()!;
        if (data['sender_id'] != currentUserId || data['deleted_at'] != null) {
          throw const ChatException(ChatError.permissionDenied);
        }
        transaction.update(messageRef, {
          'body': null,
          'deleted_at': FieldValue.serverTimestamp(),
          'edited_at': null,
        });
        if (conversation.data()?['last_message_id'] == messageId) {
          transaction.update(conversationRef, {
            'last_message_body': 'Message deleted',
          });
        }
      });
    } catch (error) {
      throw _classify(error);
    }
  }

  @override
  Future<void> markRead({
    required String conversationId,
    required String currentUserId,
  }) async {
    final ref = _conversations.doc(conversationId);
    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);
        if (!snapshot.exists) return;
        final participants = snapshot.data()?['participant_ids'];
        if (participants is! List || !participants.contains(currentUserId)) {
          throw const ChatException(ChatError.permissionDenied);
        }
        final unread = _intMap(snapshot.data()?['unread_counts']);
        unread[currentUserId] = 0;
        final readAt = _dynamicMap(snapshot.data()?['read_at']);
        readAt[currentUserId] = FieldValue.serverTimestamp();
        transaction.update(ref, {'unread_counts': unread, 'read_at': readAt});
      });
    } catch (error) {
      throw _classify(error);
    }
  }

  @override
  Stream<ChatBlockState> watchBlockState({
    required String currentUserId,
    required String otherUserId,
  }) {
    late StreamController<ChatBlockState> controller;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? outgoing;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? incoming;
    var byMe = false;
    var byOther = false;
    void emit() {
      if (!controller.isClosed) {
        controller.add(
          ChatBlockState(blockedByMe: byMe, blockedByOther: byOther),
        );
      }
    }

    controller = StreamController<ChatBlockState>(
      onListen: () {
        outgoing = _blockRef(currentUserId, otherUserId).snapshots().listen((
          snapshot,
        ) {
          byMe = snapshot.exists;
          emit();
        }, onError: controller.addError);
        incoming = _blockRef(otherUserId, currentUserId).snapshots().listen((
          snapshot,
        ) {
          byOther = snapshot.exists;
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
      await _blockRef(currentUserId, blockedUserId).set({
        'blocker_id': currentUserId,
        'blocked_id': blockedUserId,
        'created_at': FieldValue.serverTimestamp(),
      });
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
      await _blockRef(currentUserId, blockedUserId).delete();
    } catch (error) {
      throw _classify(error);
    }
  }

  DocumentReference<Map<String, dynamic>> _blockRef(
    String blockerId,
    String blockedId,
  ) => _firestore
      .collection(FirestoreCollections.chatBlocks)
      .doc(blockerId)
      .collection(FirestoreCollections.chatBlockedUsers)
      .doc(blockedId);

  static bool _isSupportedProfile(Map<String, dynamic>? data) =>
      data != null && (data['role'] == 'Teacher' || data['role'] == 'Trainee');

  static Map<String, dynamic> _snapshotForProfile(
    String id,
    Map<String, dynamic> profile,
  ) => {
    'id': id,
    'display_name': profile['full_name'],
    'role': profile['role'],
    if (profile['profile_picture_url'] is String)
      'avatar_url': profile['profile_picture_url'],
  };

  static ChatConversation? _conversationFromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) => ChatConversation.tryFromMap(
    document.data(),
    id: document.id,
    readDate: _date,
  );

  static ChatMessage? _messageFromDocument(
    String conversationId,
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) => ChatMessage.tryFromMap(
    document.data(),
    id: document.id,
    conversationId: conversationId,
    readDate: _date,
    deliveryState: document.metadata.hasPendingWrites
        ? ChatDeliveryState.sending
        : ChatDeliveryState.sent,
  );

  static DateTime? _date(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc();
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }

  static Map<String, int> _intMap(dynamic value) {
    final result = <String, int>{};
    if (value is Map) {
      for (final entry in value.entries) {
        if (entry.key is String && entry.value is int && entry.value >= 0) {
          result[entry.key as String] = entry.value as int;
        }
      }
    }
    return result;
  }

  static Map<String, dynamic> _dynamicMap(dynamic value) {
    if (value is! Map) return <String, dynamic>{};
    return {for (final entry in value.entries) '${entry.key}': entry.value};
  }

  static void _validatePageSize(int value) {
    if (value < 1 || value > 100) {
      throw ArgumentError.value(value, 'pageSize', 'must be 1..100');
    }
  }

  static ChatException _classify(Object error) {
    if (error is ChatException) return error;
    if (error is FirebaseException) {
      return switch (error.code) {
        'permission-denied' => const ChatException(ChatError.permissionDenied),
        'not-found' => const ChatException(ChatError.notFound),
        'unauthenticated' => const ChatException(ChatError.unauthenticated),
        'unavailable' ||
        'deadline-exceeded' ||
        'network-request-failed' => const ChatException(ChatError.network),
        _ => const ChatException(ChatError.unknown),
      };
    }
    return const ChatException(ChatError.unknown);
  }
}

class _FirestoreChatCursor extends ChatMessageCursor {
  const _FirestoreChatCursor(this.document);
  final DocumentSnapshot<Map<String, dynamic>> document;
}
