// Generates Teacher access codes for manual bootstrap in Firebase Console.
//
// Run from the repository root:
//   dart run scripts/generate_teacher_access_code.dart
//   dart run scripts/generate_teacher_access_code.dart 5
//
// Then create one document per normalized id in the `teacher_access_codes`
// collection (snake_case, matching `teacher_invites` / `group_invites`):
//
//   Collection: teacher_access_codes
//   Document ID: the 12-character normalized value (no hyphens)
//   Fields:
//     consumed: false
//     created_at: (timestamp, set in Console)
//     note: (optional string, e.g. "capstone bootstrap")
//
// Do not invent a different code alphabet. These values use CoachCode.
//
// Existing Teachers can also mint codes in Faculties → Invite a faculty member.
// This script remains the admin bootstrap path until the first Teacher exists.
//
// ignore_for_file: avoid_print

import 'package:elixr_core/models/coach_code.dart';

void main(List<String> args) {
  final count = args.isEmpty ? 1 : int.tryParse(args.first) ?? 1;
  if (count < 1) {
    stderrWriteln('Count must be a positive integer.');
    return;
  }

  print('Create each document in Firestore collection teacher_access_codes');
  print(
    'Document ID = normalized code. Fields: consumed=false, created_at, optional note.',
  );
  print('');
  for (var i = 0; i < count; i++) {
    final normalized = CoachCode.generateNormalized();
    final display = CoachCode.format(normalized);
    print('Code ${i + 1}:');
    print('  display:    $display');
    print('  documentId: $normalized');
    print('  fields:     consumed: false');
    print('              created_at: <now>');
    print('              note: (optional)');
    print('');
  }
}

void stderrWriteln(String message) {
  print(message);
}
