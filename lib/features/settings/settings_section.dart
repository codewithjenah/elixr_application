import 'package:fluent_ui/fluent_ui.dart';

/// Top-level Settings navigation sections.
enum SettingsSection {
  accountProfile,
  security,
  appearance,
  practice,
  privacy,
  teacherAccess,
}

extension SettingsSectionX on SettingsSection {
  String get title => switch (this) {
    SettingsSection.accountProfile => 'Account & Profile',
    SettingsSection.security => 'Security',
    SettingsSection.appearance => 'Appearance',
    SettingsSection.practice => 'Practice',
    SettingsSection.privacy => 'Privacy',
    SettingsSection.teacherAccess => 'Teacher Access',
  };

  String get description => switch (this) {
    SettingsSection.accountProfile =>
      'Update your photo, name, and sign-in email.',
    SettingsSection.security =>
      'Update your password and protect access to your Elixr account.',
    SettingsSection.appearance => 'Customize how Elixr looks on this device.',
    SettingsSection.practice =>
      'Camera, mirroring, Live Practice setlist, pace, and music.',
    SettingsSection.privacy =>
      'Control who can see your detailed player profile activity.',
    SettingsSection.teacherAccess =>
      'Join a Teacher roster and manage what linked Teachers can access.',
  };

  IconData get icon => switch (this) {
    SettingsSection.accountProfile => FluentIcons.contact,
    SettingsSection.security => FluentIcons.lock,
    SettingsSection.appearance => FluentIcons.color,
    SettingsSection.practice => FluentIcons.video,
    SettingsSection.privacy => FluentIcons.shield,
    SettingsSection.teacherAccess => FluentIcons.people,
  };
}
