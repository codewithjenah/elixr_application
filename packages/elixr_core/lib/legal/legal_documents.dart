/// A navigable section in an ELIXR legal document.
class ElixrLegalSection {
  const ElixrLegalSection({
    required this.id,
    required this.title,
    required this.paragraphs,
  });

  /// Stable identifier used by readers to choose section-specific visuals.
  final String id;
  final String title;
  final List<String> paragraphs;
}

/// Canonical ELIXR Privacy Policy and Terms of Service copy.
///
/// Common sections stay shared so Windows Trainee and Android Teacher clients
/// cannot drift. Client-specific sections disclose only processing that client
/// actually performs.
enum ElixrLegalClient { traineeWindows, teacherAndroid }

abstract final class ElixrLegalDocuments {
  static const privacyPolicyTitle = 'Privacy Policy';
  static const privacyPolicySubtitle = 'Philippine Data Privacy Act (RA 10173)';
  static const privacyPolicyLastUpdated = 'September 2026';
  static const termsOfServiceTitle = 'Terms of Service';
  static const termsOfServiceSubtitle =
      'Please read before creating an account';
  static const termsOfServiceLastUpdated = 'September 2026';

  /// Privacy Policy sections for [client], common sections first.
  static List<ElixrLegalSection> privacyPolicySectionsFor(
    ElixrLegalClient client,
  ) {
    return [
      ...commonPrivacyPolicySections,
      ...switch (client) {
        ElixrLegalClient.traineeWindows => traineePrivacyPolicySections,
        ElixrLegalClient.teacherAndroid => teacherPrivacyPolicySections,
      },
    ];
  }

  /// Terms of Service sections for [client], common sections first.
  static List<ElixrLegalSection> termsOfServiceSectionsFor(
    ElixrLegalClient client,
  ) {
    return [
      ...commonTermsOfServiceSections,
      ...switch (client) {
        ElixrLegalClient.traineeWindows => traineeTermsOfServiceSections,
        ElixrLegalClient.teacherAndroid => teacherTermsOfServiceSections,
      },
    ];
  }

  /// Privacy Policy paragraphs for [client], common sections first.
  static List<String> privacyPolicyParagraphsFor(ElixrLegalClient client) {
    return _flattenSections(privacyPolicySectionsFor(client));
  }

  /// Terms of Service paragraphs for [client], common sections first.
  static List<String> termsOfServiceParagraphsFor(ElixrLegalClient client) {
    return _flattenSections(termsOfServiceSectionsFor(client));
  }

  /// Account, authentication, retention, and RA 10173 rights for every client.
  static const commonPrivacyPolicySections = <ElixrLegalSection>[
    ElixrLegalSection(
      id: 'account-and-sign-in',
      title: 'Account and Sign-in',
      paragraphs: [
        'Account data: ELIXR collects your email address and name to create and '
            'maintain your account. Sign-in is provided by Firebase Authentication, '
            'including email verification and password reset.',
      ],
    ),
    ElixrLegalSection(
      id: 'profile-storage',
      title: 'Profile Storage',
      paragraphs: [
        'Your ELIXR user profile (name, email, and role) is stored in Cloud '
            'Firestore. That document is readable and writable only by your own '
            'signed-in account.',
      ],
    ),
    ElixrLegalSection(
      id: 'finding-people',
      title: 'Finding People',
      paragraphs: [
        'Messages discoverability: all active registered Teachers and Trainees '
            'can find one another by a case-insensitive prefix of any display-name '
            'token. An exact email address may also be used privately to locate an '
            'account, but search results never reveal email addresses. Results show '
            'only display name, role, and profile avatar.',
        'Verified Teachers can open Faculties and see every active Teacher\'s '
            'display name, role, and avatar. Emails and users documents stay '
            'private.',
      ],
    ),
    ElixrLegalSection(
      id: 'direct-messages',
      title: 'Direct Messages',
      paragraphs: [
        'Direct messages are stored in Cloud Firestore and are readable only by '
            'the two conversation participants. Messages may be edited by their '
            'author or soft-deleted into a Message deleted tombstone. The app stores '
            'conversation previews, unread counts, read timestamps, and block '
            'records to provide inbox badges and Seen state. Blocking prevents both '
            'participants from sending new messages while preserving history.',
      ],
    ),
    ElixrLegalSection(
      id: 'data-retention',
      title: 'Data Retention',
      paragraphs: [
        'Data Retention: account profile data is kept while your account is '
            'active. When an account is deleted, we permanently remove associated '
            'direct identifiers and other personal data we hold for that account. '
            'Conversation bodies may be retained for the other participant after '
            'your identity and sender identifiers are replaced with Deleted user. '
            'If no active participant remains, the archived conversation is removed.',
      ],
    ),
    ElixrLegalSection(
      id: 'your-rights',
      title: 'Your Rights under RA 10173',
      paragraphs: [
        'Your Rights: Under the Philippine Data Privacy Act (RA 10173), you '
            'have the right to access, correct, or erase your personal data.',
      ],
    ),
  ];

  /// Windows training-app processing: webcam/CV, sessions, photos, profiles.
  static const traineePrivacyPolicySections = <ElixrLegalSection>[
    ElixrLegalSection(
      id: 'camera-and-on-device-vision',
      title: 'Camera and On-device Vision',
      paragraphs: [
        'The Windows training application also processes webcam video locally on '
            'your device for pose/hand landmark detection and records session '
            'performance data from practice sessions.',
      ],
    ),
    ElixrLegalSection(
      id: 'assignment-submission-clips',
      title: 'Assignment Submission Clips',
      paragraphs: [
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
      ],
    ),
    ElixrLegalSection(
      id: 'photos-and-saved-images',
      title: 'Photos and Saved Images',
      paragraphs: [
        'Profile photos are stored in Cloud Storage for display across the app.',
        'Confirmed movement images: if you opt in, ELIXR stores one private, '
            'annotated still image from the camera frame that confirmed a Guided '
            'Practice movement. It is not video and is not shared to public profiles '
            'or leaderboards. While you are an approved member of a classroom, the '
            'owning Teacher automatically receives read-only access to sanitized '
            'progress and available retained stills; Teacher reads of stills also '
            'require your session-evidence setting to remain enabled. Legacy-only '
            'linked Teachers use separate per-Teacher saved-image permission. You '
            'can disable image saving in Settings > Privacy to delete saved images '
            'and their session references; account deletion also removes them.',
      ],
    ),
    ElixrLegalSection(
      id: 'public-profile',
      title: 'Public Profile',
      paragraphs: [
        'Public Profile: by default, other signed-in Trainees and Teachers can '
            'view your detailed stats, claimed achievements, completed movements, '
            'and practice history. You can lock your profile at any time in '
            'Settings > Privacy. Locked profiles hide those details from signed-in '
            'Trainees and Teachers, including other faculty. Basic leaderboard '
            'identity remains visible whether your profile is locked or unlocked.',
      ],
    ),
    ElixrLegalSection(
      id: 'training-and-session-data',
      title: 'Training and Session Data',
      paragraphs: [
        'Training and session data are kept while your account is active. If you '
            'delete your account via Settings > Security, we permanently remove '
            'all associated data.',
      ],
    ),
    ElixrLegalSection(
      id: 'teacher-access-and-sharing',
      title: 'Teacher Access and Sharing',
      paragraphs: [
        'Teacher Access: a Teacher can create a durable group or legacy roster code. '
            'You can enter that exact code to request to join, and the Teacher may '
            'approve or reject the request. An approved classroom membership '
            'automatically shares sanitized, read-only summary and practice/assessment '
            'history plus available retained movement stills while the membership '
            'remains approved; there is no separate classroom opt-out. Removing the '
            'membership immediately blocks those classroom reads. Legacy-only linked '
            'Teachers retain the separate per-Teacher Share Progress and Share Saved '
            'Images confirmations. Messaging is separate from classroom and progress '
            'permissions. Credentials, private settings, raw video, feedback '
            'internals, achievements, and unrestricted account data are never shared.',
      ],
    ),
    ElixrLegalSection(
      id: 'deleting-your-account',
      title: 'Deleting Your Account',
      paragraphs: [
        'Use Settings > Security > Delete Account to exercise your right to '
            'erasure.',
      ],
    ),
  ];

  /// Android Teacher-app processing currently implemented in this version.
  static const teacherPrivacyPolicySections = <ElixrLegalSection>[
    ElixrLegalSection(
      id: 'teacher-account-and-processing',
      title: 'Teacher Account and Processing',
      paragraphs: [
        'The Android Teacher application uses your account identity (name and '
            'email) and Teacher-account profile information. It does not capture '
            'webcam video, run computer-vision processing, store practice-session '
            'data, publish a public player profile, or maintain a leaderboard in '
            'this application.',
      ],
    ),
    ElixrLegalSection(
      id: 'roster-linking-and-sharing',
      title: 'Roster Linking and Sharing',
      paragraphs: [
        'Roster linking: the Teacher application may store group membership and '
            'legacy Teacher↔Trainee relationship records after a Trainee requests '
            'to join. You must approve each group request. An approved classroom '
            'membership automatically permits read-only access to the Trainee’s '
            'sanitized progress and available retained stills while it remains '
            'approved. Legacy-only relationships use the Trainee’s separate sharing '
            'controls. Raw video, credentials, private settings, feedback internals, '
            'achievements, and unrestricted account data are not shared. The Teacher '
            'app cannot create or edit Trainee sessions or scores.',
      ],
    ),
    ElixrLegalSection(
      id: 'teacher-data-rights',
      title: 'Teacher Data Rights',
      paragraphs: [
        'The Teacher application does not currently include in-app account '
            'deletion. You retain the right under RA 10173 to request access, '
            'correction, or erasure of your Teacher account data.',
      ],
    ),
  ];

  static const commonTermsOfServiceSections = <ElixrLegalSection>[
    ElixrLegalSection(
      id: 'acceptance-and-purpose',
      title: 'Acceptance and Purpose',
      paragraphs: [
        'By using ELIXR, you agree to follow these terms. ELIXR is provided '
            'as-is for educational and training purposes.',
      ],
    ),
    ElixrLegalSection(
      id: 'your-account',
      title: 'Your Account',
      paragraphs: [
        'Your account is for your personal use only. Do not share credentials '
            'or abuse the service.',
      ],
    ),
    ElixrLegalSection(
      id: 'messaging-conduct',
      title: 'Messaging Conduct',
      paragraphs: [
        'Use direct messages respectfully. Do not use user search or messaging for '
            'harassment, impersonation, spam, unlawful content, or attempts to '
            'collect another user’s private information. You may block another '
            'participant at any time.',
      ],
    ),
    ElixrLegalSection(
      id: 'service-limitations',
      title: 'Service Limitations',
      paragraphs: [
        'ELIXR is not liable for interrupted service, data loss (beyond our '
            'control), or third-party systems.',
      ],
    ),
    ElixrLegalSection(
      id: 'changes-to-these-terms',
      title: 'Changes to These Terms',
      paragraphs: [
        'We reserve the right to update these terms. Changes will be posted '
            'here.',
      ],
    ),
  ];

  static const traineeTermsOfServiceSections = <ElixrLegalSection>[
    ElixrLegalSection(
      id: 'leaderboard-integrity',
      title: 'Leaderboard Integrity',
      paragraphs: [
        'Leaderboard scores reflect reported performance; we reserve the '
            'right to reset records if fraud is detected.',
      ],
    ),
  ];

  static const teacherTermsOfServiceSections = <ElixrLegalSection>[
    ElixrLegalSection(
      id: 'teacher-accounts',
      title: 'Teacher Accounts',
      paragraphs: [
        'Teacher accounts are for instructor use of the Teacher application. '
            'A Teacher roster lists only Trainees whose join request the Teacher approves. '
            'Student progress review is read-only and is automatic for an approved '
            'classroom membership; legacy-only relationships remain separately '
            'authorized by the Trainee. Direct messaging is available independently '
            'of roster or progress authorization.',
      ],
    ),
  ];

  /// Backward-compatible flat common privacy copy.
  static List<String> get commonPrivacyPolicyParagraphs =>
      _flattenSections(commonPrivacyPolicySections);

  /// Backward-compatible flat Trainee privacy copy.
  static List<String> get traineePrivacyPolicyParagraphs =>
      _flattenSections(traineePrivacyPolicySections);

  /// Backward-compatible flat Teacher privacy copy.
  static List<String> get teacherPrivacyPolicyParagraphs =>
      _flattenSections(teacherPrivacyPolicySections);

  /// Backward-compatible flat common terms copy.
  static List<String> get commonTermsOfServiceParagraphs =>
      _flattenSections(commonTermsOfServiceSections);

  /// Backward-compatible flat Trainee terms copy.
  static List<String> get traineeTermsOfServiceParagraphs =>
      _flattenSections(traineeTermsOfServiceSections);

  /// Backward-compatible flat Teacher terms copy.
  static List<String> get teacherTermsOfServiceParagraphs =>
      _flattenSections(teacherTermsOfServiceSections);

  static List<String> _flattenSections(List<ElixrLegalSection> sections) {
    return [for (final section in sections) ...section.paragraphs];
  }
}
