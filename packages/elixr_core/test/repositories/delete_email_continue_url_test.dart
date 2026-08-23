import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses authDomain when Firebase still exposes it', () {
    expect(
      continueUrlHostForDeleteEmail(
        authDomain: 'elixr-app-2026.firebaseapp.com',
        projectId: 'elixr-app-2026',
      ),
      'elixr-app-2026.firebaseapp.com',
    );
  });

  test('falls back to projectId when Windows drops authDomain', () {
    expect(
      continueUrlHostForDeleteEmail(
        authDomain: '',
        projectId: 'elixr-app-2026',
      ),
      'elixr-app-2026.firebaseapp.com',
    );
    expect(
      continueUrlHostForDeleteEmail(
        authDomain: null,
        projectId: 'elixr-app-2026',
      ),
      'elixr-app-2026.firebaseapp.com',
    );
  });

  test('refuses when neither authDomain nor projectId is available', () {
    expect(
      () => continueUrlHostForDeleteEmail(authDomain: '  ', projectId: ''),
      throwsA(
        predicate(
          (error) => error.toString().contains(
            cannotSendDeleteConfirmationEmailMessage,
          ),
        ),
      ),
    );
  });
}
