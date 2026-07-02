class Feedback {
  const Feedback({
    this.id,
    required this.sessionId,
    required this.message,
    required this.feedbackType,
    this.createdAt,
  });

  final String? id;
  final String sessionId;
  final String message;
  final String feedbackType;
  final String? createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'session_id': sessionId,
      'message': message,
      'feedback_type': feedbackType,
      'created_at': createdAt,
    };
  }

  factory Feedback.fromMap(Map<String, dynamic> map) {
    return Feedback(
      id: map['id'] as String?,
      sessionId: map['session_id'] as String,
      message: map['message'] as String,
      feedbackType: map['feedback_type'] as String,
      createdAt: map['created_at'] as String?,
    );
  }
}
