import 'dart:async';

import 'package:supabase/supabase.dart';

import '../database/supabase_support.dart';
import '../models/classroom_announcement.dart';
import 'classroom_announcement_repository.dart';

class SupabaseClassroomAnnouncementRepository
    implements ClassroomAnnouncementRepository {
  SupabaseClassroomAnnouncementRepository({SupabaseClient? client})
    : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  @override
  Stream<ClassroomAnnouncementPage> watchAnnouncements({
    required String groupId,
    int pageSize = ClassroomAnnouncementRepository.defaultPageSize,
    bool includeUnpublished = false,
  }) {
    _validatePageSize(pageSize);
    return Stream<ClassroomAnnouncementPage>.multi((controller) {
      List<Map<String, dynamic>>? latestAnnouncements;
      Map<String, dynamic>? latestGroup;
      var groupLoaded = false;
      var generation = 0;
      var cancelled = false;

      Future<void> emit() async {
        final rows = latestAnnouncements;
        if (rows == null || !groupLoaded) return;
        final currentGeneration = ++generation;
        final groupData = latestGroup ?? const <String, dynamic>{};
        final pinnedId = _readPinnedId(groupData);
        final pinnedAt = _readDateTime(groupData['pinned_announcement_at']);
        final visible = [
          for (final row in rows)
            if (includeUnpublished || row['trainee_visible'] == true) row,
        ]..sort(_newestRowFirst);
        final page = visible.take(pageSize).toList(growable: false);
        final byId = <String, ClassroomAnnouncement>{
          for (final row in page)
            if (_parse(row) case final ClassroomAnnouncement item)
              item.id: item,
        };
        if (pinnedId != null && !byId.containsKey(pinnedId)) {
          try {
            final pinnedRow = await _client
                .from('group_announcements')
                .select()
                .eq('id', pinnedId)
                .maybeSingle();
            // A stale pointer can target an unpublished announcement, which
            // is intentionally unreadable by trainees.
            final pinned = pinnedRow == null ? null : _parse(pinnedRow);
            if (pinned != null) byId[pinned.id] = pinned;
          } on PostgrestException {
            // Treat an unreadable pinned row like a missing one.
          }
        }
        if (cancelled || currentGeneration != generation) return;
        final items = [
          for (final item in byId.values)
            item.copyWith(
              isPinned: item.id == pinnedId,
              pinnedAt: item.id == pinnedId ? pinnedAt : null,
              clearPinnedAt: item.id != pinnedId,
            ),
        ]..sort(_compareAnnouncements);
        controller.add(
          ClassroomAnnouncementPage(
            items: items,
            hasMore: visible.length > pageSize,
            nextCursor: page.isEmpty
                ? null
                : _SupabaseAnnouncementCursor.fromRow(page.last),
          ),
        );
      }

      // One extra row tells whether older history exists.
      final announcementsSub = _client
          .from('group_announcements')
          .stream(primaryKey: ['id'])
          .eq('group_id', groupId)
          .order('created_at')
          .limit(includeUnpublished ? pageSize + 1 : 100)
          .listen((rows) {
            latestAnnouncements = rows;
            unawaited(emit());
          }, onError: controller.addError);
      final groupSub = _client
          .from('groups')
          .stream(primaryKey: ['id'])
          .eq('id', groupId)
          .listen((rows) {
            latestGroup = rows.isEmpty ? null : rows.first;
            groupLoaded = true;
            unawaited(emit());
          }, onError: controller.addError);
      controller.onCancel = () async {
        cancelled = true;
        generation++;
        await Future.wait([announcementsSub.cancel(), groupSub.cancel()]);
      };
    });
  }

  @override
  Future<ClassroomAnnouncementPage> fetchOlderAnnouncements({
    required String groupId,
    required ClassroomAnnouncementCursor startAfter,
    int pageSize = ClassroomAnnouncementRepository.defaultPageSize,
    bool includeUnpublished = false,
  }) async {
    _validatePageSize(pageSize);
    if (startAfter is! _SupabaseAnnouncementCursor) {
      throw ArgumentError('Cursor belongs to another repository.');
    }
    var query = _client
        .from('group_announcements')
        .select()
        .eq('group_id', groupId);
    if (!includeUnpublished) query = query.eq('trainee_visible', true);
    final rows = await query
        .or(startAfter.keysetFilter)
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(pageSize + 1);
    final page = rows.take(pageSize).toList(growable: false);
    final groupRow = await _client
        .from('groups')
        .select('pinned_announcement_id, pinned_announcement_at')
        .eq('id', groupId)
        .maybeSingle();
    final pinnedId = _readPinnedId(groupRow ?? const {});
    final pinnedAt = _readDateTime(groupRow?['pinned_announcement_at']);
    final items =
        page
            .map(_parse)
            .whereType<ClassroomAnnouncement>()
            .map(
              (item) => item.copyWith(
                isPinned: item.id == pinnedId,
                pinnedAt: item.id == pinnedId ? pinnedAt : null,
                clearPinnedAt: item.id != pinnedId,
              ),
            )
            .toList()
          ..sort(_compareAnnouncements);
    return ClassroomAnnouncementPage(
      items: items,
      hasMore: rows.length > pageSize,
      nextCursor: rows.length > pageSize && page.isNotEmpty
          ? _SupabaseAnnouncementCursor.fromRow(page.last)
          : null,
    );
  }

  @override
  Future<ClassroomAnnouncement> createAnnouncement({
    required String groupId,
    required String teacherId,
    required String title,
    required String body,
    DateTime? publishAt,
  }) async {
    final row = await rpcMap(_client, 'create_announcement', {
      'p_group_id': groupId,
      'p_title': _validatedTitle(title),
      'p_body': _validatedBody(body),
      'p_publish_at': _validatePublishAt(publishAt)?.toIso8601String(),
    });
    final parsed = _parse(row);
    if (parsed == null) throw const FormatException('Malformed announcement.');
    return parsed;
  }

  @override
  Future<void> updateAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
    required String title,
    required String body,
    DateTime? publishAt,
  }) async {
    await _client.rpc<dynamic>(
      'update_announcement',
      params: {
        'p_announcement_id': announcementId,
        'p_title': _validatedTitle(title),
        'p_body': _validatedBody(body),
        'p_publish_at': _validatePublishAt(publishAt)?.toIso8601String(),
      },
    );
  }

  @override
  Future<void> deleteAnnouncement({
    required String groupId,
    required String announcementId,
    required String teacherId,
  }) async {
    await _client.rpc<dynamic>(
      'delete_announcement',
      params: {'p_announcement_id': announcementId},
    );
  }

  @override
  Future<void> setPinnedAnnouncement({
    required String groupId,
    required String teacherId,
    String? announcementId,
  }) async {
    try {
      await _client.rpc<dynamic>(
        'set_pinned_announcement',
        params: {
          'p_group_id': groupId,
          'p_announcement_id': announcementId?.trim(),
        },
      );
    } on PostgrestException catch (error) {
      throw StateError(switch (error.message) {
        'scheduled_announcement' =>
          'A scheduled announcement cannot be pinned.',
        'not_found' => 'Announcement is not available.',
        _ => 'Classroom is not available.',
      });
    }
  }

  static ClassroomAnnouncement? _parse(Map<String, dynamic> row) =>
      ClassroomAnnouncement.tryFromMap(
        // edited_at is an explicit nullable field of the announcement model.
        {...compactRow(row), 'edited_at': row['edited_at']},
        id: row['id'] as String,
      );

  static int _newestRowFirst(Map<String, dynamic> a, Map<String, dynamic> b) {
    final byTime = (_readDateTime(b['created_at']) ?? DateTime(0)).compareTo(
      _readDateTime(a['created_at']) ?? DateTime(0),
    );
    return byTime != 0 ? byTime : '${b['id']}'.compareTo('${a['id']}');
  }

  static int _compareAnnouncements(
    ClassroomAnnouncement a,
    ClassroomAnnouncement b,
  ) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final byTime = bTime.compareTo(aTime);
    return byTime != 0 ? byTime : b.id.compareTo(a.id);
  }

  static String? _readPinnedId(Map<String, dynamic> data) {
    final value = data['pinned_announcement_id'];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed.length > 128 ? null : trimmed;
  }

  static DateTime? _readDateTime(Object? value) {
    if (value is DateTime) return value.toUtc();
    if (value is String) return DateTime.tryParse(value)?.toUtc();
    return null;
  }

  static void _validatePageSize(int pageSize) {
    if (pageSize < 1 || pageSize > 100) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Must be 1 through 100.');
    }
  }

  static String _validatedTitle(String value) {
    final error = ClassroomAnnouncement.validateTitle(value);
    if (error != null) throw ArgumentError(error);
    return value.trim();
  }

  static String _validatedBody(String value) {
    final error = ClassroomAnnouncement.validateBody(value);
    if (error != null) throw ArgumentError(error);
    return value.trim();
  }

  static DateTime? _validatePublishAt(DateTime? value) {
    if (value == null) return null;
    final at = value.toUtc();
    if (!at.isAfter(DateTime.now().toUtc())) {
      throw ArgumentError('Publication time must be in the future.');
    }
    return at;
  }
}

class _SupabaseAnnouncementCursor extends ClassroomAnnouncementCursor {
  const _SupabaseAnnouncementCursor(this.createdAtUtc, this.id);

  factory _SupabaseAnnouncementCursor.fromRow(Map<String, dynamic> row) =>
      _SupabaseAnnouncementCursor(
        DateTime.parse(row['created_at'] as String).toUtc().toIso8601String(),
        row['id'] as String,
      );

  final String createdAtUtc;
  final String id;

  String get keysetFilter =>
      'created_at.lt.$createdAtUtc,and(created_at.eq.$createdAtUtc,id.lt.$id)';
}
