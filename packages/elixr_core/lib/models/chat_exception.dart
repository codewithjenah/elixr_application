enum ChatError {
  invalidMessage,
  invalidQuery,
  unauthenticated,
  permissionDenied,
  blocked,
  notFound,
  rateLimited,
  network,
  unknown,
}

class ChatException implements Exception {
  const ChatException(this.code, [this.detail]);

  final ChatError code;
  final String? detail;

  String get userMessage => switch (code) {
    ChatError.invalidMessage =>
      detail ?? 'Enter a message between 1 and 2,000 characters.',
    ChatError.invalidQuery =>
      detail ?? 'Enter at least two characters to search.',
    ChatError.unauthenticated => 'Sign in again to use Messages.',
    ChatError.permissionDenied => 'This conversation is unavailable.',
    ChatError.blocked => 'Message could not be sent.',
    ChatError.notFound => 'This conversation is no longer available.',
    ChatError.rateLimited => 'Too many searches. Wait a moment and try again.',
    ChatError.network => 'Messages could not connect. Check your connection.',
    ChatError.unknown => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => userMessage;
}
