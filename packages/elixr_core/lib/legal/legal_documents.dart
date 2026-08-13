/// Canonical ELIXR Privacy Policy and Terms of Service copy.
///
/// Shared so Windows Trainee and Android Teacher clients cannot drift.
abstract final class ElixrLegalDocuments {
  static const privacyPolicyTitle = 'Privacy Policy';
  static const privacyPolicySubtitle = 'Philippine Data Privacy Act (RA 10173)';

  static const privacyPolicyParagraphs = <String>[
    'Data Collected: email, name, profile photo, webcam video processed '
        'locally on your device for pose/hand landmark detection, session '
        'performance data.',
    'Video Storage: raw camera video is never uploaded to or stored on '
        'our servers. It is processed locally on your device during practice '
        'sessions only.',
    'Profile photos are stored in Cloud Storage for display across the app.',
    'Public Profile: by default, other signed-in players can view your '
        'detailed stats, claimed achievements, completed movements, and '
        'practice history. You can lock your profile at any time in '
        'Settings > Privacy. Basic leaderboard identity remains visible '
        'whether your profile is locked or unlocked.',
    'Data Retention: profile and training data are kept while your account '
        'is active. If you delete your account via Settings > Security, we '
        'permanently remove all associated data.',
    'Your Rights: Under the Philippine Data Privacy Act (RA 10173), you '
        'have the right to access, correct, or erase your personal data. '
        'Use Settings > Security > Delete Account to exercise your right to '
        'erasure.',
  ];

  static const termsOfServiceTitle = 'Terms of Service';
  static const termsOfServiceSubtitle =
      'Please read before creating an account';

  static const termsOfServiceParagraphs = <String>[
    'By using ELIXR, you agree to follow these terms. ELIXR is provided '
        'as-is for educational and training purposes.',
    'Your account is for your personal use only. Do not share credentials '
        'or abuse the service.',
    'Leaderboard scores reflect reported performance; we reserve the '
        'right to reset records if fraud is detected.',
    'ELIXR is not liable for interrupted service, data loss (beyond our '
        'control), or third-party systems.',
    'We reserve the right to update these terms. Changes will be posted '
        'here.',
  ];
}
