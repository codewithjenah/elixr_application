import '../models/chat_user.dart';

/// Sanitized Teacher rows from `chat_user_directory` for the Faculties page.
abstract class FacultyDirectoryRepository {
  /// Active Teacher directory rows. Implementations query `role == Teacher`
  /// and omit malformed or inactive documents.
  Stream<List<ChatUser>> watchTeachers();
}
