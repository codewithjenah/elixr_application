/// Pure planner for historical legacy coaching-note provenance backfill.
///
/// Does not talk to Firestore. Callers supply note and link maps.
class LegacyCoachingProvenancePlanner {
  static const notesCollection = 'teacher_coaching_notes';
  static const linksCollection = 'teacher_student_links';
  static const authorizationSourceField = 'authorization_source';
  static const authorizationSourceLegacyLink = 'legacy_link';
  static const groupIdField = 'group_id';
  static const teacherIdField = 'teacher_id';
  static const traineeIdField = 'trainee_id';
  static const statusField = 'status';
  static const approvedStatus = 'approved';

  /// Firestore WriteBatch limit. Writes use a smaller chunk for headroom.
  static const firestoreBatchLimit = 500;
  static const writeBatchSize = 400;

  static String linkDocumentId({
    required String teacherId,
    required String traineeId,
  }) => '${teacherId}_$traineeId';

  static bool isValidParticipantId(Object? value) {
    if (value is! String) return false;
    final trimmed = value.trim();
    return trimmed.isNotEmpty && trimmed.length <= 128;
  }

  static bool hasGroupId(Map<String, Object?> data) =>
      data.containsKey(groupIdField);

  static bool hasAuthorizationSource(Map<String, Object?> data) =>
      data.containsKey(authorizationSourceField);

  static LegacyCoachingProvenanceDecision evaluate({
    required String noteId,
    required Map<String, Object?> note,
    Map<String, Object?>? link,
  }) {
    if (hasGroupId(note)) {
      return LegacyCoachingProvenanceDecision.skipped(
        noteId: noteId,
        reason: LegacyCoachingProvenanceSkipReason.groupBacked,
      );
    }
    if (hasAuthorizationSource(note)) {
      return LegacyCoachingProvenanceDecision.skipped(
        noteId: noteId,
        reason: LegacyCoachingProvenanceSkipReason.alreadyProvenanced,
      );
    }

    final teacherId = note[teacherIdField];
    final traineeId = note[traineeIdField];
    if (!isValidParticipantId(teacherId) ||
        !isValidParticipantId(traineeId) ||
        (teacherId as String).trim() == (traineeId as String).trim()) {
      return LegacyCoachingProvenanceDecision.skipped(
        noteId: noteId,
        reason: LegacyCoachingProvenanceSkipReason.invalidIdentity,
      );
    }

    final trimmedTeacherId = teacherId.trim();
    final trimmedTraineeId = traineeId.trim();
    if (link == null) {
      return LegacyCoachingProvenanceDecision.skipped(
        noteId: noteId,
        reason: LegacyCoachingProvenanceSkipReason.missingRelationship,
      );
    }

    final linkTeacherId = link[teacherIdField];
    final linkTraineeId = link[traineeIdField];
    if (linkTeacherId != trimmedTeacherId ||
        linkTraineeId != trimmedTraineeId) {
      return LegacyCoachingProvenanceDecision.skipped(
        noteId: noteId,
        reason: LegacyCoachingProvenanceSkipReason.identityMismatch,
      );
    }

    if (link[statusField] != approvedStatus) {
      return LegacyCoachingProvenanceDecision.skipped(
        noteId: noteId,
        reason: LegacyCoachingProvenanceSkipReason.relationshipNotApproved,
      );
    }

    return LegacyCoachingProvenanceDecision.eligible(
      noteId: noteId,
      teacherId: trimmedTeacherId,
      traineeId: trimmedTraineeId,
    );
  }

  static Map<String, Object> provenancePatch() => const {
    authorizationSourceField: authorizationSourceLegacyLink,
  };

  static List<List<String>> chunkNoteIds(Iterable<String> noteIds) {
    final ids = noteIds.toList(growable: false);
    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += writeBatchSize) {
      final end = (i + writeBatchSize < ids.length)
          ? i + writeBatchSize
          : ids.length;
      chunks.add(ids.sublist(i, end));
    }
    return chunks;
  }
}

enum LegacyCoachingProvenanceSkipReason {
  groupBacked,
  alreadyProvenanced,
  invalidIdentity,
  missingRelationship,
  relationshipNotApproved,
  identityMismatch,
}

class LegacyCoachingProvenanceDecision {
  const LegacyCoachingProvenanceDecision._({
    required this.noteId,
    required this.eligible,
    this.reason,
    this.teacherId,
    this.traineeId,
  });

  factory LegacyCoachingProvenanceDecision.eligible({
    required String noteId,
    required String teacherId,
    required String traineeId,
  }) => LegacyCoachingProvenanceDecision._(
    noteId: noteId,
    eligible: true,
    teacherId: teacherId,
    traineeId: traineeId,
  );

  factory LegacyCoachingProvenanceDecision.skipped({
    required String noteId,
    required LegacyCoachingProvenanceSkipReason reason,
  }) => LegacyCoachingProvenanceDecision._(
    noteId: noteId,
    eligible: false,
    reason: reason,
  );

  final String noteId;
  final bool eligible;
  final LegacyCoachingProvenanceSkipReason? reason;
  final String? teacherId;
  final String? traineeId;
}

class LegacyCoachingProvenanceReport {
  int notesScanned = 0;
  int historicalCandidates = 0;
  int eligible = 0;
  int skippedGroupBacked = 0;
  int skippedAlreadyProvenanced = 0;
  int skippedInvalidIdentity = 0;
  int skippedMissingRelationship = 0;
  int skippedRelationshipNotApproved = 0;
  int skippedIdentityMismatch = 0;
  final List<String> wouldUpdateIds = [];
  final List<String> writeFailures = [];

  int get skippedMissingOrNonApproved =>
      skippedMissingRelationship + skippedRelationshipNotApproved;

  void add(LegacyCoachingProvenanceDecision decision) {
    notesScanned += 1;
    if (decision.eligible) {
      historicalCandidates += 1;
      eligible += 1;
      wouldUpdateIds.add(decision.noteId);
      return;
    }
    switch (decision.reason) {
      case LegacyCoachingProvenanceSkipReason.groupBacked:
        skippedGroupBacked += 1;
      case LegacyCoachingProvenanceSkipReason.alreadyProvenanced:
        skippedAlreadyProvenanced += 1;
      case LegacyCoachingProvenanceSkipReason.invalidIdentity:
        historicalCandidates += 1;
        skippedInvalidIdentity += 1;
      case LegacyCoachingProvenanceSkipReason.missingRelationship:
        historicalCandidates += 1;
        skippedMissingRelationship += 1;
      case LegacyCoachingProvenanceSkipReason.relationshipNotApproved:
        historicalCandidates += 1;
        skippedRelationshipNotApproved += 1;
      case LegacyCoachingProvenanceSkipReason.identityMismatch:
        historicalCandidates += 1;
        skippedIdentityMismatch += 1;
      case null:
        break;
    }
  }

  String format({required bool dryRun}) {
    final mode = dryRun ? 'DRY RUN (no writes)' : 'WRITE';
    final buffer = StringBuffer()
      ..writeln('Legacy coaching provenance backfill — $mode')
      ..writeln('notes scanned: $notesScanned')
      ..writeln(
        'historical notes (no group_id, no authorization_source): $historicalCandidates',
      )
      ..writeln('eligible: $eligible')
      ..writeln('skipped Group-backed notes: $skippedGroupBacked')
      ..writeln('skipped already-provenanced notes: $skippedAlreadyProvenanced')
      ..writeln(
        'skipped missing/non-approved relationships: $skippedMissingOrNonApproved',
      )
      ..writeln('skipped identity mismatch: $skippedIdentityMismatch')
      ..writeln('skipped invalid identity: $skippedInvalidIdentity')
      ..writeln(
        dryRun
            ? 'documents that WOULD be updated: ${wouldUpdateIds.length}'
            : 'documents targeted: ${wouldUpdateIds.length}',
      );
    for (final id in wouldUpdateIds) {
      buffer.writeln('  - $id');
    }
    if (writeFailures.isNotEmpty) {
      buffer.writeln('write failures: ${writeFailures.length}');
      for (final failure in writeFailures) {
        buffer.writeln('  - $failure');
      }
    }
    return buffer.toString();
  }
}
