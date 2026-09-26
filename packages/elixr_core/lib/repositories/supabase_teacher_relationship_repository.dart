import 'package:supabase/supabase.dart';

import '../database/supabase_support.dart';
import '../models/coach_code.dart';
import '../models/teacher_relationship_exception.dart';
import '../models/teacher_roster_invite.dart';
import '../models/teacher_student_link.dart';
import 'teacher_relationship_repository.dart';

class SupabaseTeacherRelationshipRepository
    implements TeacherRelationshipRepository {
  SupabaseTeacherRelationshipRepository({SupabaseClient? client})
    : _clientOverride = client;

  final SupabaseClient? _clientOverride;

  SupabaseClient get _client => _clientOverride ?? ElixrSupabase.client;

  static TeacherRelationshipException? exceptionFor(Object error) {
    return switch (backendErrorCode(error)) {
      'malformed_code' => const TeacherRelationshipException(
        TeacherRelationshipError.malformedCode,
        'That roster code is not valid.',
      ),
      'invite_not_found' => const TeacherRelationshipException(
        TeacherRelationshipError.inviteNotFound,
        'No Teacher is using that roster code.',
      ),
      'already_linked' => const TeacherRelationshipException(
        TeacherRelationshipError.alreadyLinked,
        'This Teacher is already linked.',
      ),
      'already_pending' => const TeacherRelationshipException(
        TeacherRelationshipError.alreadyPending,
        'A request is already waiting for this Teacher.',
      ),
      'invalid_participant' => const TeacherRelationshipException(
        TeacherRelationshipError.invalidParticipant,
        'You cannot join your own roster.',
      ),
      'collision_exhausted' => const TeacherRelationshipException(
        TeacherRelationshipError.collisionExhausted,
        'Could not allocate a unique roster code.',
      ),
      'not_found' || 'forbidden' => const TeacherRelationshipException(
        TeacherRelationshipError.notFound,
      ),
      _ => null,
    };
  }

  Future<T> _mapped<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error) {
      throw exceptionFor(error) ?? error;
    }
  }

  static TeacherRosterInvite _invite(Map<String, dynamic> row) {
    final parsed = TeacherRosterInvite.tryFromMap(
      row,
      id: row['code'] as String,
    );
    if (parsed == null) throw const FormatException('Malformed roster code.');
    return parsed;
  }

  @override
  Future<TeacherRosterInvite> createOrRotateRosterInvite({
    required String teacherId,
    required String teacherDisplayName,
  }) async {
    final row = await _mapped(() => rpcMap(_client, 'rotate_roster_invite'));
    return _invite(row);
  }

  @override
  Future<TeacherRosterInvite?> getActiveRosterInvite({
    required String teacherId,
  }) async {
    final result = await _mapped(
      () => _client.rpc<dynamic>('get_active_roster_invite'),
    );
    if (result == null) return null;
    final invite = _invite(asRowMap(result));
    return invite.teacherId == teacherId ? invite : null;
  }

  @override
  Future<void> revokeRosterInvite({required String teacherId}) =>
      _mapped(() => _client.rpc<dynamic>('revoke_roster_invite'));

  @override
  Future<TeacherRosterInvite> resolveRosterCode(String code) async {
    final normalized = CoachCode.tryNormalize(code);
    if (normalized == null) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.malformedCode,
        'That roster code is not valid.',
      );
    }
    final row = await _mapped(
      () => rpcMap(_client, 'resolve_roster_code', {'p_code': normalized}),
    );
    return _invite(row);
  }

  @override
  Future<TeacherStudentLink> requestTeacherJoin({
    required String traineeId,
    required String traineeDisplayName,
    required String code,
  }) async {
    final normalized = CoachCode.tryNormalize(code);
    if (normalized == null) {
      throw const TeacherRelationshipException(
        TeacherRelationshipError.malformedCode,
        'That roster code is not valid.',
      );
    }
    final row = await _mapped(
      () => rpcMap(_client, 'request_teacher_join', {'p_code': normalized}),
    );
    final link = TeacherStudentLink.tryFromMap(row, id: row['id'] as String);
    if (link == null) throw const FormatException('Malformed roster link.');
    return link;
  }

  Future<void> _transition(String linkId, String action) => _mapped(
    () => _client.rpc<dynamic>(
      'transition_teacher_link',
      params: {'p_link_id': linkId, 'p_action': action},
    ),
  );

  @override
  Future<void> approveJoin({
    required String linkId,
    required String teacherId,
  }) => _transition(linkId, 'approve');

  @override
  Future<void> rejectJoin({
    required String linkId,
    required String teacherId,
  }) => _transition(linkId, 'reject');

  @override
  Future<void> cancelJoin({
    required String linkId,
    required String traineeId,
  }) => _transition(linkId, 'cancel');

  @override
  Future<void> revokeLink({
    required String linkId,
    required String traineeId,
  }) => _transition(linkId, 'revoke');

  Future<void> _setAccess(String linkId, String kind, bool granted) => _mapped(
    () => _client.rpc<dynamic>(
      'set_link_access',
      params: {'p_link_id': linkId, 'p_kind': kind, 'p_granted': granted},
    ),
  );

  @override
  Future<void> grantProgressAccess({
    required String linkId,
    required String traineeId,
  }) => _setAccess(linkId, 'progress', true);

  @override
  Future<void> removeProgressAccess({
    required String linkId,
    required String traineeId,
  }) => _setAccess(linkId, 'progress', false);

  @override
  Future<void> grantEvidenceAccess({
    required String linkId,
    required String traineeId,
  }) => _setAccess(linkId, 'evidence', true);

  @override
  Future<void> removeEvidenceAccess({
    required String linkId,
    required String traineeId,
  }) => _setAccess(linkId, 'evidence', false);

  @override
  Future<void> revokeAllEvidenceAccess({required String traineeId}) =>
      _mapped(() => _client.rpc<dynamic>('revoke_all_evidence_access'));

  @override
  Stream<List<TeacherStudentLink>> watchTraineeLinks({
    required String traineeId,
  }) => _client
      .from('teacher_student_links')
      .stream(primaryKey: ['id'])
      .eq('trainee_id', traineeId)
      .map(_links);

  @override
  Stream<List<TeacherStudentLink>> watchTeacherLinks({
    required String teacherId,
  }) => _client
      .from('teacher_student_links')
      .stream(primaryKey: ['id'])
      .eq('teacher_id', teacherId)
      .map(_links);

  @override
  Stream<TeacherStudentLinkSnapshot> watchLink({
    required String teacherId,
    required String traineeId,
  }) {
    final id = TeacherStudentLink.documentId(
      teacherId: teacherId,
      traineeId: traineeId,
    );
    // Stream events are delivered from the server, never a local cache.
    return _client
        .from('teacher_student_links')
        .stream(primaryKey: ['id'])
        .eq('id', id)
        .map(
          (rows) => TeacherStudentLinkSnapshot(
            link: rows.isEmpty
                ? null
                : TeacherStudentLink.tryFromMap(compactRow(rows.first), id: id),
            isServerVerified: true,
          ),
        );
  }

  static List<TeacherStudentLink> _links(List<Map<String, dynamic>> rows) {
    final result =
        rows
            .map(
              (row) => TeacherStudentLink.tryFromMap(
                compactRow(row),
                id: row['id'] as String,
              ),
            )
            .whereType<TeacherStudentLink>()
            .where((link) => !link.isPending || link.isV2Request)
            .toList()
          ..sort(
            (a, b) => (b.createdAt ?? DateTime(0)).compareTo(
              a.createdAt ?? DateTime(0),
            ),
          );
    return result;
  }
}
