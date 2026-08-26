import 'package:elixr_core/legal/legal_documents.dart';
import 'package:elixr_core/privacy/privacy_consent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String joined(List<String> paragraphs) => paragraphs.join('\n');
  List<String> flatten(List<ElixrLegalSection> sections) {
    return [for (final section in sections) ...section.paragraphs];
  }

  void expectValidSections(List<ElixrLegalSection> sections) {
    expect(sections, isNotEmpty);
    final ids = <String>{};
    for (final section in sections) {
      expect(section.id.trim(), isNotEmpty);
      expect(ids.add(section.id), isTrue);
      expect(section.title.trim(), isNotEmpty);
      expect(section.paragraphs, isNotEmpty);
      for (final paragraph in section.paragraphs) {
        expect(paragraph.trim(), isNotEmpty);
      }
    }
  }

  for (final client in ElixrLegalClient.values) {
    test(
      'privacy sections preserve flat paragraph order for ${client.name}',
      () {
        final sections = ElixrLegalDocuments.privacyPolicySectionsFor(client);
        expect(
          flatten(sections),
          orderedEquals(ElixrLegalDocuments.privacyPolicyParagraphsFor(client)),
        );
      },
    );

    test('terms sections preserve flat paragraph order for ${client.name}', () {
      final sections = ElixrLegalDocuments.termsOfServiceSectionsFor(client);
      expect(
        flatten(sections),
        orderedEquals(ElixrLegalDocuments.termsOfServiceParagraphsFor(client)),
      );
    });

    test('privacy sections have valid unique metadata for ${client.name}', () {
      expectValidSections(ElixrLegalDocuments.privacyPolicySectionsFor(client));
    });

    test('terms sections have valid unique metadata for ${client.name}', () {
      expectValidSections(
        ElixrLegalDocuments.termsOfServiceSectionsFor(client),
      );
    });
  }

  test('legal documents expose non-empty last-updated labels', () {
    expect(ElixrLegalDocuments.privacyPolicyLastUpdated, 'September 2026');
    expect(ElixrLegalDocuments.privacyPolicyLastUpdated.trim(), isNotEmpty);
    expect(ElixrLegalDocuments.termsOfServiceLastUpdated, 'September 2026');
    expect(ElixrLegalDocuments.termsOfServiceLastUpdated.trim(), isNotEmpty);
  });

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
      expect(text, contains('durable group or legacy roster code'));
      expect(
        text,
        contains('approved classroom membership automatically shares'),
      );
      expect(text, contains('there is no separate classroom opt-out'));
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
        expect(text, contains('approve each group request'));
        expect(text, contains('available retained stills'));
        expect(text, contains('Legacy-only relationships'));
        expect(text, contains('sanitized progress'));
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
        expect(text, contains('read-only and is automatic'));
        expect(text, isNot(contains('Leaderboard scores')));
      },
    );
  });

  test('registration privacy consent version is v6', () {
    expect(RegistrationPrivacyConsent.policyVersion, 'v6');
  });
}
