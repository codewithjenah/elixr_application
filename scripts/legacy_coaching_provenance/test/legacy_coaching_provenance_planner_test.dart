import 'package:legacy_coaching_provenance/legacy_coaching_provenance_planner.dart';
import 'package:test/test.dart';

void main() {
  const teacherId = 'teacher-1';
  const traineeId = 'trainee-1';
  const noteId = 'note-historical';

  Map<String, Object?> historicalNote() => {
    'teacher_id': teacherId,
    'trainee_id': traineeId,
    'teacher_display_name': 'Teacher One',
    'body': 'Keep the pour tight.',
    'created_at': DateTime.utc(2026, 1, 2),
    'updated_at': DateTime.utc(2026, 1, 2),
  };

  Map<String, Object?> approvedLink({
    String teacher = teacherId,
    String trainee = traineeId,
    String status = 'approved',
  }) => {'teacher_id': teacher, 'trainee_id': trainee, 'status': status};

  test('historical legacy note + approved link is eligible', () {
    final decision = LegacyCoachingProvenancePlanner.evaluate(
      noteId: noteId,
      note: historicalNote(),
      link: approvedLink(),
    );
    expect(decision.eligible, isTrue);
    expect(decision.reason, isNull);
    expect(LegacyCoachingProvenancePlanner.provenancePatch(), {
      'authorization_source': 'legacy_link',
    });
  });

  test('note with group_id is skipped', () {
    final decision = LegacyCoachingProvenancePlanner.evaluate(
      noteId: noteId,
      note: {...historicalNote(), 'group_id': 'group-a'},
      link: approvedLink(),
    );
    expect(decision.eligible, isFalse);
    expect(decision.reason, LegacyCoachingProvenanceSkipReason.groupBacked);
  });

  test('note already authorization_source == legacy_link is skipped', () {
    final decision = LegacyCoachingProvenancePlanner.evaluate(
      noteId: noteId,
      note: {...historicalNote(), 'authorization_source': 'legacy_link'},
      link: approvedLink(),
    );
    expect(decision.eligible, isFalse);
    expect(
      decision.reason,
      LegacyCoachingProvenanceSkipReason.alreadyProvenanced,
    );
  });

  test('historical note + missing link is skipped', () {
    final decision = LegacyCoachingProvenancePlanner.evaluate(
      noteId: noteId,
      note: historicalNote(),
      link: null,
    );
    expect(decision.eligible, isFalse);
    expect(
      decision.reason,
      LegacyCoachingProvenanceSkipReason.missingRelationship,
    );
  });

  test('historical note + pending/rejected/revoked link is skipped', () {
    for (final status in ['pending', 'rejected', 'revoked', 'cancelled']) {
      final decision = LegacyCoachingProvenancePlanner.evaluate(
        noteId: noteId,
        note: historicalNote(),
        link: approvedLink(status: status),
      );
      expect(decision.eligible, isFalse, reason: status);
      expect(
        decision.reason,
        LegacyCoachingProvenanceSkipReason.relationshipNotApproved,
        reason: status,
      );
    }
  });

  test('identity mismatch is skipped', () {
    final decision = LegacyCoachingProvenancePlanner.evaluate(
      noteId: noteId,
      note: historicalNote(),
      link: approvedLink(teacher: 'other-teacher'),
    );
    expect(decision.eligible, isFalse);
    expect(
      decision.reason,
      LegacyCoachingProvenanceSkipReason.identityMismatch,
    );
  });

  test('repeated run is idempotent', () {
    final first = LegacyCoachingProvenancePlanner.evaluate(
      noteId: noteId,
      note: historicalNote(),
      link: approvedLink(),
    );
    expect(first.eligible, isTrue);
    final second = LegacyCoachingProvenancePlanner.evaluate(
      noteId: noteId,
      note: {
        ...historicalNote(),
        ...LegacyCoachingProvenancePlanner.provenancePatch(),
      },
      link: approvedLink(),
    );
    expect(second.eligible, isFalse);
    expect(
      second.reason,
      LegacyCoachingProvenanceSkipReason.alreadyProvenanced,
    );
  });

  test('write chunks stay under the Firestore batch limit', () {
    final ids = List.generate(850, (i) => 'note-$i');
    final chunks = LegacyCoachingProvenancePlanner.chunkNoteIds(ids);
    expect(chunks, hasLength(3));
    expect(chunks[0], hasLength(400));
    expect(chunks[1], hasLength(400));
    expect(chunks[2], hasLength(50));
    for (final chunk in chunks) {
      expect(
        chunk.length,
        lessThanOrEqualTo(LegacyCoachingProvenancePlanner.firestoreBatchLimit),
      );
      expect(
        chunk.length,
        lessThanOrEqualTo(LegacyCoachingProvenancePlanner.writeBatchSize),
      );
    }
  });

  test('report counts skip buckets without mutating notes', () {
    final report = LegacyCoachingProvenanceReport();
    report.add(
      LegacyCoachingProvenancePlanner.evaluate(
        noteId: 'eligible',
        note: historicalNote(),
        link: approvedLink(),
      ),
    );
    report.add(
      LegacyCoachingProvenancePlanner.evaluate(
        noteId: 'group',
        note: {...historicalNote(), 'group_id': 'g1'},
        link: approvedLink(),
      ),
    );
    report.add(
      LegacyCoachingProvenancePlanner.evaluate(
        noteId: 'provenanced',
        note: {...historicalNote(), 'authorization_source': 'legacy_link'},
        link: approvedLink(),
      ),
    );
    report.add(
      LegacyCoachingProvenancePlanner.evaluate(
        noteId: 'missing',
        note: historicalNote(),
        link: null,
      ),
    );
    expect(report.notesScanned, 4);
    expect(report.eligible, 1);
    expect(report.skippedGroupBacked, 1);
    expect(report.skippedAlreadyProvenanced, 1);
    expect(report.skippedMissingOrNonApproved, 1);
    expect(report.wouldUpdateIds, ['eligible']);
    final dry = report.format(dryRun: true);
    expect(dry, contains('DRY RUN (no writes)'));
    expect(dry, contains('documents that WOULD be updated: 1'));
  });
}
