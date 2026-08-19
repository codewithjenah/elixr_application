import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> validMap({Object? movement = 'Hand Stall'}) {
  final data = <String, dynamic>{
    'teacher_id': 'teacher',
    'trainee_id': 'trainee',
    'teacher_display_name': 'Teacher Name',
    'body': 'Keep your wrist steady.',
    'created_at': DateTime.utc(2026, 8, 14, 10),
    'updated_at': DateTime.utc(2026, 8, 14, 10),
  };
  if (movement != null) {
    data['movement_name'] = movement;
  }
  return data;
}

void main() {
  group('CoachingNote draft validation', () {
    test('accepts a valid body with optional recognized movement', () {
      expect(
        CoachingNote.validateDraft(
          body: 'Great control.',
          movementName: 'Bottle in a tin',
        ),
        isNull,
      );
      expect(CoachingNote.validateDraft(body: 'General coaching.'), isNull);
    });

    test(
      'rejects empty, whitespace-only, over-limit, and invalid movement drafts',
      () {
        expect(CoachingNote.validateDraft(body: ''), isNotNull);
        expect(CoachingNote.validateDraft(body: '  \n\t '), isNotNull);
        expect(
          CoachingNote.validateDraft(
            body: 'a' * CoachingNote.maximumBodyLength,
          ),
          isNull,
        );
        expect(
          CoachingNote.validateDraft(
            body: 'a' * (CoachingNote.maximumBodyLength + 1),
          ),
          isNotNull,
        );
        expect(
          CoachingNote.validateDraft(
            body: 'Valid',
            movementName: 'Bottle in a Tin',
          ),
          isNotNull,
        );
      },
    );
  });

  group('CoachingNote.tryFromMap', () {
    test('parses valid immutable data and recognizes edited state', () {
      final note = CoachingNote.tryFromMap({
        ...validMap(),
        'updated_at': DateTime.utc(2026, 8, 14, 11),
      }, id: 'note');
      expect(note, isNotNull);
      expect(note!.movementName, 'Hand Stall');
      expect(note.isEdited, isTrue);
    });

    test('accepts absent movement and ignores unknown fields', () {
      final note = CoachingNote.tryFromMap({
        ...validMap(movement: null),
        'unrelated_field': 'ignored by the parser',
      }, id: 'note');
      expect(note, isNotNull);
      expect(note!.movementName, isNull);
    });

    test('parses optional immutable group_id for classroom-backed notes', () {
      final note = CoachingNote.tryFromMap({
        ...validMap(movement: null),
        'group_id': 'group-1',
      }, id: 'note');
      expect(note, isNotNull);
      expect(note!.groupId, 'group-1');
    });

    test('fails safely for malformed required data', () {
      final invalidMaps = <Map<String, dynamic>>[
        {...validMap(), 'teacher_id': ''},
        {...validMap(), 'teacher_id': 'a' * 129},
        {...validMap(), 'trainee_id': 'teacher'},
        {...validMap(), 'teacher_display_name': 'a' * 81},
        {...validMap(), 'body': ' '},
        {...validMap(), 'body': 'a' * 1001},
        {...validMap(), 'movement_name': 'Bottle in a Tin'},
        {...validMap(), 'created_at': 'not-a-date'},
        {...validMap(), 'updated_at': DateTime.utc(2026, 8, 14, 9)},
      ];
      for (final map in invalidMaps) {
        expect(CoachingNote.tryFromMap(map, id: 'note'), isNull);
      }
      expect(CoachingNote.tryFromMap(validMap(), id: '   '), isNull);
    });
  });
}
