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
    'Messages discoverability: all active registered Teachers and Trainees '
        'can find one another by a case-insensitive prefix of any display-name '
        'token. An exact email address may also be used privately to locate an '
        'account, but search results never reveal email addresses. Results show '
        'only display name, role, and profile avatar.',
    'Verified Teachers can open Faculties and see every active Teacher\'s '
        'display name, role, and avatar. Emails and users documents stay '
        'private.',
    'Direct messages are stored in Cloud Firestore and are readable only by '
        'the two conversation participants. Messages may be edited by their '
        'author or soft-deleted into a Message deleted tombstone. The app stores '
        'conversation previews, unread counts, read timestamps, and block '
        'records to provide inbox badges and Seen state. Blocking prevents both '
        'participants from sending new messages while preserving history.',
    'Data Retention: account profile data is kept while your account is '
        'active. When an account is deleted, we permanently remove associated '
        'direct identifiers and other personal data we hold for that account. '
        'Conversation bodies may be retained for the other participant after '
        'your identity and sender identifiers are replaced with Deleted user. '
        'If no active participant remains, the archived conversation is removed.',
    'Your Rights: Under the Philippine Data Privacy Act (RA 10173), you '
        'have the right to access, correct, or erase your personal data.',
  ];

  /// Windows training-app processing: webcam/CV, sessions, photos, profiles.
  static const traineePrivacyPolicyParagraphs = <String>[
    'The Windows training application also processes webcam video locally on '
        'your device for pose/hand landmark detection and records session '
        'performance data from practice sessions.',
    'Ordinary training and practice webcam video stays on your device and is '
        'not uploaded. The only exception is when you explicitly choose Record '
        'Submission for a Teacher-created assignment and then confirm Submit to '
        'Teacher. In that case ELIXR uploads one short assignment clip '
        '(about 20 seconds or less) so the assigning Teacher can review it. '
        'That clip is not public-profile content, is not leaderboard content, '
        'and is not granted through General Evidence Access. Clips are kept '
        'only for bounded classroom review under the current retention policy, '
        'and account deletion removes them. Windows Teachers using this same '
        'application can review clips they assigned.',
    'Profile photos are stored in Cloud Storage for display across the app.',
    'Confirmed movement images: if you opt in, ELIXR stores one private, '
        'annotated still image from the camera frame that confirmed a Guided '
        'Practice movement. It is not video, is not shared to public profiles, '
        'leaderboards, and is accessible only to your account unless you '
        'separately grant one linked Teacher saved-image access. That '
        'per-Teacher permission covers retained historical and future stills '
        'while progress sharing remains active, and can be revoked at any time. '
        'You can disable this in Settings > Privacy to delete saved images and '
        'their session references; account deletion also removes them.',
    'Public Profile: by default, other signed-in players can view your '
        'detailed stats, claimed achievements, completed movements, and '
        'practice history. You can lock your profile at any time in '
        'Settings > Privacy. Basic leaderboard identity remains visible '
        'whether your profile is locked or unlocked.',
    'Training and session data are kept while your account is active. If you '
        'delete your account via Settings > Security, we permanently remove '
        'all associated data.',
    'Teacher Access: a Teacher can create a durable roster code. You may enter '
        'that exact code to request to join, and the Teacher may approve or '
        'reject the request. Linking alone does not share progress. You can separately '
        'enable sanitized, read-only summary and practice/assessment history '
        'for each linked Teacher. Messaging is separate from classroom and '
        'progress permissions: any registered Teacher or Trainee may send text '
        'messages, including users who are not linked through a classroom. '
        'Messages exclude raw video and protected assessment internals. Assignment '
        'submission clips are a separate classroom authorization for the assigning '
        'Teacher only; they are not shared through Public Profile, Progress Access, '
        'or General Evidence Access. You can stop sharing or revoke that Teacher at '
        'any time. Credentials, private settings, feedback internals, '
        'achievements, and unrestricted account data are never shared. Each '
        'per-relationship Share Progress and Share Saved Images confirmations '
        'are independent consent events.',
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
    'Roster linking: the Teacher application may store Teacher↔Trainee '
        'relationship records after you create a durable roster code and a '
        'Trainee intentionally requests to join. You must approve each request. '
        'Linking alone does not share progress. A Trainee may '
        'separately authorize sanitized, read-only progress summary and '
        'practice/assessment history, then stop sharing or revoke the '
        'relationship at any time. Raw video, credentials, private settings, '
        'feedback internals, achievements, and unrestricted account data are '
        'not shared. If the Trainee separately enables saved-image access, the '
        'Teacher may lazily view retained annotated stills for sanitized session '
        'rows until permission is revoked. The Teacher app cannot create or edit '
        'Trainee sessions or scores.',
    'The Teacher application does not currently include in-app account '
        'deletion. You retain the right under RA 10173 to request access, '
        'correction, or erasure of your Teacher account data.',
  ];

  static const commonTermsOfServiceParagraphs = <String>[
    'By using ELIXR, you agree to follow these terms. ELIXR is provided '
        'as-is for educational and training purposes.',
    'Your account is for your personal use only. Do not share credentials '
        'or abuse the service.',
    'Use direct messages respectfully. Do not use user search or messaging for '
        'harassment, impersonation, spam, unlawful content, or attempts to '
        'collect another user’s private information. You may block another '
        'participant at any time.',
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
        'A Teacher roster lists only Trainees whose join request the Teacher approves. '
        'Student progress review is read-only when separately authorized by '
        'the Trainee. Direct messaging is available independently of roster or '
        'progress authorization; progress review remains read-only and separately '
        'consented.',
  ];
}
