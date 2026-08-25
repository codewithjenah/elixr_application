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
      expect(text, contains('Faculties'));
      expect(
        text,
        contains(
          'Verified Teachers can open Faculties and see every active Teacher\'s display name, role, and avatar.',
        ),
      );
      expect(text, contains('Emails and users documents stay private'));
    });

    test('retains Trainee-specific webcam, session, and profile copy', () {
      expect(text, contains('webcam video'));
      expect(text, contains('pose/hand landmark detection'));
      expect(text, contains('Record Submission'));
      expect(text, contains('Submit to Teacher'));
      expect(text, contains('assigning Teacher'));
      expect(text, contains('General Evidence Access'));
      expect(text, contains('practice sessions'));
      expect(text, contains('claimed achievements'));
      expect(text, contains('completed movements'));
      expect(text, contains('Settings > Privacy'));
      expect(text, contains('leaderboard identity'));
      expect(text, contains('other signed-in Trainees and Teachers'));
      expect(text, contains('including other faculty'));
      expect(text, contains('Settings > Security'));
      expect(text, contains('Delete Account'));
      expect(text, contains('Teacher Access'));
      expect(text, contains('durable roster code'));
      expect(text, contains('Linking alone does not share progress'));
      expect(text, contains('Share Progress and Share Saved Images'));
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
        expect(text, contains('approve each request'));
        expect(text, contains('saved-image access'));
        expect(text, contains('revoke'));
        expect(text, contains('sanitized, read-only progress summary'));
        expect(
          text,
          contains('cannot create or edit Trainee sessions or scores'),
        );
      },
    );

    test('does not present Trainee-only processing as Teacher behavior', () {
      expect(text, isNot(contains('pose/hand landmark')));
      expect(text, isNot(contains('raw camera video is never uploaded')));
      expect(text, isNot(contains('Record Submission')));
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
      'Teacher terms describe separately authorized, read-only progress access',
      () {
        final text = joined(
          ElixrLegalDocuments.termsOfServiceParagraphsFor(
            ElixrLegalClient.teacherAndroid,
          ),
        );
        expect(text, contains('Teacher approves'));
        expect(text, contains('read-only when separately authorized'));
        expect(text, isNot(contains('Leaderboard scores')));
      },
    );
  });

  test('registration privacy consent version is v5', () {
    expect(RegistrationPrivacyConsent.policyVersion, 'v5');
  });
}
