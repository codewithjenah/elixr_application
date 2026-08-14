import 'package:cloud_firestore/cloud_firestore.dart';
import '../database/firestore_collections.dart';
import '../models/coaching_note.dart';
import '../models/coaching_note_exception.dart';
import '../models/teacher_student_link.dart';
import 'coaching_note_repository.dart';

class FirebaseCoachingNoteRepository implements CoachingNoteRepository {
  FirebaseCoachingNoteRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;
  CollectionReference<Map<String, dynamic>> get _notes =>
      _firestore.collection(FirestoreCollections.teacherCoachingNotes);
  DocumentReference<Map<String, dynamic>> _link(
    String teacherId,
    String traineeId,
  ) => _firestore
      .collection(FirestoreCollections.teacherStudentLinks)
      .doc(
        TeacherStudentLink.documentId(
          teacherId: teacherId,
          traineeId: traineeId,
        ),
      );
  void _draft(String body, String? movement) {
    final error = CoachingNote.validateDraft(
      body: body,
      movementName: movement,
    );
    if (error != null)
      throw CoachingNoteException(CoachingNoteError.invalidNote, error);
  }

  @override
  Future<CoachingNotePage> fetchForTeacher({
    required String teacherId,
    required String traineeId,
    int pageSize = CoachingNoteRepository.defaultPageSize,
    CoachingNoteCursor? startAfter,
  }) => _fetch(
    teacherId: teacherId,
    traineeId: traineeId,
    pageSize: pageSize,
    startAfter: startAfter,
    server: true,
  );
  @override
  Future<CoachingNotePage> fetchReceived({
    required String traineeId,
    int pageSize = CoachingNoteRepository.defaultPageSize,
    CoachingNoteCursor? startAfter,
  }) => _fetch(
    traineeId: traineeId,
    pageSize: pageSize,
    startAfter: startAfter,
    server: false,
  );
  Future<CoachingNotePage> _fetch({
    String? teacherId,
    required String traineeId,
    required int pageSize,
    CoachingNoteCursor? startAfter,
    required bool server,
  }) async {
    CoachingNoteRepository.validatePageSize(pageSize);
    Query<Map<String, dynamic>> query = _notes.where(
      'trainee_id',
      isEqualTo: traineeId,
    );
    if (teacherId != null)
      query = query.where('teacher_id', isEqualTo: teacherId);
    query = query
        .orderBy('created_at', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(pageSize + 1);
    if (startAfter != null) {
      if (startAfter is! _Cursor)
        throw ArgumentError('Cursor belongs to another repository');
      query = query.startAfterDocument(startAfter.document);
    }
    try {
      final result = server
          ? await query.get(const GetOptions(source: Source.server))
          : await query.get();
      final docs = result.docs.take(pageSize).toList();
      return CoachingNotePage(
        notes: docs
            .map((d) => CoachingNote.tryFromMap(d.data(), id: d.id))
            .whereType<CoachingNote>()
            .toList(),
        hasMore: result.docs.length > pageSize,
        nextCursor: result.docs.length > pageSize ? _Cursor(docs.last) : null,
      );
    } catch (e) {
      throw classifyError(e);
    }
  }

  @override
  Future<CoachingNote> createNote({
    required String teacherId,
    required String traineeId,
    required String body,
    String? movementName,
  }) async {
    _draft(body, movementName);
    final ref = _notes.doc();
    try {
      await _firestore.runTransaction((tx) async {
        final link = await tx.get(_link(teacherId, traineeId));
        final user = await tx.get(
          _firestore.collection(FirestoreCollections.users).doc(teacherId),
        );
        if (!link.exists || link.data()?['status'] != 'approved')
          throw const CoachingNoteException(
            CoachingNoteError.relationshipRequired,
          );
        final name = user.data()?['full_name'];
        if (name is! String || name.trim().isEmpty)
          throw const CoachingNoteException(CoachingNoteError.permissionDenied);
        tx.set(ref, {
          'teacher_id': teacherId,
          'trainee_id': traineeId,
          'teacher_display_name': name,
          'body': body.trim(),
          if (movementName != null) 'movement_name': movementName,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      });
      final saved = await ref.get(const GetOptions(source: Source.server));
      return CoachingNote.tryFromMap(saved.data() ?? const {}, id: saved.id) ??
          (throw const CoachingNoteException(CoachingNoteError.unknown));
    } catch (e) {
      throw classifyError(e);
    }
  }

  @override
  Future<CoachingNote> updateNote({
    required String noteId,
    required String teacherId,
    required String traineeId,
    required String body,
    String? movementName,
  }) async {
    _draft(body, movementName);
    final ref = _notes.doc(noteId);
    try {
      await _firestore.runTransaction((tx) async {
        final link = await tx.get(_link(teacherId, traineeId));
        final note = await tx.get(ref);
        if (!link.exists || link.data()?['status'] != 'approved')
          throw const CoachingNoteException(
            CoachingNoteError.relationshipRequired,
          );
        if (!note.exists)
          throw const CoachingNoteException(CoachingNoteError.notFound);
        final data = note.data()!;
        if (data['teacher_id'] != teacherId || data['trainee_id'] != traineeId)
          throw const CoachingNoteException(CoachingNoteError.permissionDenied);
        tx.update(ref, {
          'body': body.trim(),
          'movement_name': movementName ?? FieldValue.delete(),
          'updated_at': FieldValue.serverTimestamp(),
        });
      });
      final saved = await ref.get(const GetOptions(source: Source.server));
      return CoachingNote.tryFromMap(saved.data() ?? const {}, id: saved.id) ??
          (throw const CoachingNoteException(CoachingNoteError.unknown));
    } catch (e) {
      throw classifyError(e);
    }
  }

  @override
  Future<void> deleteNote({
    required String noteId,
    required String teacherId,
    required String traineeId,
  }) async {
    final ref = _notes.doc(noteId);
    try {
      await _firestore.runTransaction((tx) async {
        final link = await tx.get(_link(teacherId, traineeId));
        final note = await tx.get(ref);
        if (!link.exists || link.data()?['status'] != 'approved')
          throw const CoachingNoteException(
            CoachingNoteError.relationshipRequired,
          );
        if (!note.exists)
          throw const CoachingNoteException(CoachingNoteError.notFound);
        if (note.data()?['teacher_id'] != teacherId ||
            note.data()?['trainee_id'] != traineeId)
          throw const CoachingNoteException(CoachingNoteError.permissionDenied);
        tx.delete(ref);
      });
    } catch (e) {
      throw classifyError(e);
    }
  }

  static CoachingNoteException classifyError(Object error) {
    if (error is CoachingNoteException) return error;
    if (error is FirebaseException) {
      if (error.code == 'permission-denied')
        return const CoachingNoteException(CoachingNoteError.permissionDenied);
      if (error.code == 'not-found')
        return const CoachingNoteException(CoachingNoteError.notFound);
      if ([
        'unavailable',
        'deadline-exceeded',
        'network-request-failed',
      ].contains(error.code))
        return const CoachingNoteException(CoachingNoteError.network);
    }
    return CoachingNoteException(CoachingNoteError.unknown, '$error');
  }
}

class _Cursor extends CoachingNoteCursor {
  const _Cursor(this.document);
  final DocumentSnapshot<Map<String, dynamic>> document;
}
