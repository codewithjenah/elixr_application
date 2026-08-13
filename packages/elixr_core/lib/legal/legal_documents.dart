/// Canonical ELIXR Privacy Policy and Terms of Service copy.
///
/// Common sections stay shared so Windows Trainee and Android Teacher clients
/// cannot drift. Client-specific sections disclose only processing that client
/// actually performs.
enum ElixrLegalClient { traineeWindows, teacherAndroid }

abstract final class ElixrLegalDocuments {
  static const privacyPolicyTitle = 'Privacy Policy';
  static const privacyPolicySubtitle = 'Philippine Data Privacy Act (RA 10173)';
  static const termsOfServiceTitle = 'Terms of Service';
  static const termsOfServiceSubtitle =
      'Please read before creating an account';

  /// Privacy Policy paragraphs for [client], common sections first.
  static List<String> privacyPolicyParagraphsFor(ElixrLegalClient client) {
    return [
      ...commonPrivacyPolicyParagraphs,
      ...switch (client) {
        ElixrLegalClient.traineeWindows => traineePrivacyPolicyParagraphs,
        ElixrLegalClient.teacherAndroid => teacherPrivacyPolicyParagraphs,
      },
    ];
  }

  /// Terms of Service paragraphs for [client], common sections first.
  static List<String> termsOfServiceParagraphsFor(ElixrLegalClient client) {
    return [
      ...commonTermsOfServiceParagraphs,
      ...switch (client) {
        ElixrLegalClient.traineeWindows => traineeTermsOfServiceParagraphs,
        ElixrLegalClient.teacherAndroid => teacherTermsOfServiceParagraphs,
      },
    ];
  }

  /// Account, authentication, retention, and RA 10173 rights for every client.
  static const commonPrivacyPolicyParagraphs = <String>[
    'Account data: ELIXR collects your email address and name to create and '
        'maintain your account. Sign-in is provided by Firebase Authentication, '
        'including email verification and password reset.',
    'Your ELIXR user profile (name, email, and role) is stored in Cloud '
        'Firestore. That document is readable and writable only by your own '
        'signed-in account.',
    'Data Retention: account profile data is kept while your account is '
        'active. When an account is deleted, we permanently remove associated '
        'personal data we hold for that account.',
    'Your Rights: Under the Philippine Data Privacy Act (RA 10173), you '
        'have the right to access, correct, or erase your personal data.',
  ];

  /// Windows training-app processing: webcam/CV, sessions, photos, profiles.
  static const traineePrivacyPolicyParagraphs = <String>[
    'The Windows training application also processes webcam video locally on '
        'your device for pose/hand landmark detection and records session '
        'performance data from practice sessions.',
    'Video Storage: raw camera video is never uploaded to or stored on '
        'our servers. It is processed locally on your device during practice '
        'sessions only.',
    'Profile photos are stored in Cloud Storage for display across the app.',
    'Public Profile: by default, other signed-in players can view your '
        'detailed stats, claimed achievements, completed movements, and '
        'practice history. You can lock your profile at any time in '
        'Settings > Privacy. Basic leaderboard identity remains visible '
        'whether your profile is locked or unlocked.',
    'Training and session data are kept while your account is active. If you '
        'delete your account via Settings > Security, we permanently remove '
        'all associated data.',
    'Use Settings > Security > Delete Account to exercise your right to '
        'erasure.',
  ];

  /// Android Teacher-app processing currently implemented in this version.
  static const teacherPrivacyPolicyParagraphs = <String>[
    'The Android Teacher application uses your account identity (name and '
        'email) and Teacher-account profile information. It does not capture '
        'webcam video, run computer-vision processing, store practice-session '
        'data, publish a public player profile, or maintain a leaderboard in '
        'this application.',
    'Linked-student and roster data are not collected or stored in this '
        'version. Features for linking trainees to a Teacher roster are not '
        'yet active.',
    'The Teacher application does not currently include in-app account '
        'deletion. You retain the right under RA 10173 to request access, '
        'correction, or erasure of your Teacher account data.',
  ];

  static const commonTermsOfServiceParagraphs = <String>[
    'By using ELIXR, you agree to follow these terms. ELIXR is provided '
        'as-is for educational and training purposes.',
    'Your account is for your personal use only. Do not share credentials '
        'or abuse the service.',
    'ELIXR is not liable for interrupted service, data loss (beyond our '
        'control), or third-party systems.',
    'We reserve the right to update these terms. Changes will be posted '
        'here.',
  ];

  static const traineeTermsOfServiceParagraphs = <String>[
    'Leaderboard scores reflect reported performance; we reserve the '
        'right to reset records if fraud is detected.',
  ];

  static const teacherTermsOfServiceParagraphs = <String>[
    'Teacher accounts are for instructor use of the Teacher application. '
        'Trainee roster linking, student progress, teacher notes, and '
        'assignments are not yet active in this version.',
  ];
}
