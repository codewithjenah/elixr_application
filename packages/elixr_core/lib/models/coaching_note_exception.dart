enum CoachingNoteError {
  invalidNote,
  relationshipRequired,
  permissionDenied,
  notFound,
  network,
  unknown,
}

class CoachingNoteException implements Exception {
  const CoachingNoteException(this.code, [this.message]);
  final CoachingNoteError code;
  final String? message;

  @override
  String toString() =>
      'CoachingNoteException($code${message == null ? '' : ': $message'})';
}
