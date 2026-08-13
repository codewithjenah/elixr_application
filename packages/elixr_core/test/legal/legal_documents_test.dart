import 'package:elixr_core/legal/legal_documents.dart';
import 'package:elixr_core/privacy/privacy_consent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String joined(List<String> paragraphs) => paragraphs.join('\n');

  group('Trainee Windows privacy', () {
    final text = joined(
      ElixrLegalDocuments.privacyPolicyParagraphsFor(
        ElixrLegalClient.traineeWindows,
      ),
    );

    test('includes common account and RA 10173 disclosures', () {
      expect(text, contains('Firebase Authentication'));
      expect(text, contains('email verification'));
      expect(text, contains('password reset'));
      expect(text, contains('Philippine Data Privacy Act (RA 10173)'));
    });

    test('retains Trainee-specific webcam, session, and profile copy', () {
      expect(text, contains('webcam video'));
      expect(text, contains('pose/hand landmark detection'));
      expect(text, contains('raw camera video is never uploaded'));
      expect(text, contains('practice sessions'));
      expect(text, contains('claimed achievements'));
      expect(text, contains('completed movements'));
      expect(text, contains('Settings > Privacy'));
      expect(text, contains('leaderboard identity'));
      expect(text, contains('Settings > Security'));
      expect(text, contains('Delete Account'));
      expect(text, contains('Teacher Access'));
      expect(text, contains('coach code'));
      expect(text, contains('does not share your practice sessions'));
    });
  });

  group('Teacher Android privacy', () {
    final text = joined(
      ElixrLegalDocuments.privacyPolicyParagraphsFor(
        ElixrLegalClient.teacherAndroid,
      ),
    );

    test(
      'discloses Teacher account, Firebase auth, and roster linking limits',
      () {
        expect(text, contains('Firebase Authentication'));
        expect(text, contains('Teacher-account'));
        expect(text, contains('email verification'));
        expect(text, contains('password reset'));
        expect(text, contains('Teacher↔Trainee relationship records'));
        expect(text, contains('explicitly approve'));
        expect(text, contains('revoke'));
        expect(text, contains('not exposed to Teachers in this version'));
        expect(text, isNot(contains('not yet active')));
      },
    );

    test('does not present Trainee-only processing as Teacher behavior', () {
      expect(text, isNot(contains('pose/hand landmark')));
      expect(text, isNot(contains('raw camera video is never uploaded')));
      expect(text, isNot(contains('Settings > Privacy')));
      expect(text, isNot(contains('Settings > Security')));
      expect(text, isNot(contains('claimed achievements')));
      expect(text, isNot(contains('completed movements')));
    });
  });

  group('Terms of Service', () {
    test('Trainee terms retain leaderboard disclosure', () {
      final text = joined(
        ElixrLegalDocuments.termsOfServiceParagraphsFor(
          ElixrLegalClient.traineeWindows,
        ),
      );
      expect(text, contains('Leaderboard scores'));
      expect(text, contains('educational and training purposes'));
    });

    test(
      'Teacher terms describe approved roster linking without progress access',
      () {
        final text = joined(
          ElixrLegalDocuments.termsOfServiceParagraphsFor(
            ElixrLegalClient.teacherAndroid,
          ),
        );
        expect(text, contains('approve a relationship'));
        expect(text, contains('not yet active in this version'));
        expect(text, isNot(contains('Leaderboard scores')));
      },
    );
  });

  test('registration privacy consent version remains v1', () {
    expect(RegistrationPrivacyConsent.policyVersion, 'v1');
  });
}
