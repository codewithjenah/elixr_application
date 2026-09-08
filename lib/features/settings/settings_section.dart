import 'package:fluent_ui/fluent_ui.dart';

/// Top-level Settings navigation sections.
enum SettingsSection {
  accountProfile,
  security,
  appearance,
  practice,
  privacy,
  about,
  contactFeedback,
}

/// Which role the Settings surface is being shown for.
enum SettingsAudience { trainee, teacher }

/// Visible Settings panes for [audience]. IndexedStack children must follow
/// this list, not [SettingsSection.values], or teacher Privacy would land on
/// Practice.
List<SettingsSection> settingsSectionsFor(SettingsAudience audience) {
  return switch (audience) {
    SettingsAudience.trainee => List<SettingsSection>.unmodifiable(
      SettingsSection.values,
    ),
    SettingsAudience.teacher => const [
      SettingsSection.accountProfile,
      SettingsSection.security,
      SettingsSection.appearance,
      SettingsSection.privacy,
      SettingsSection.about,
      SettingsSection.contactFeedback,
    ],
  };
}

/// Parses a `?section=` query value (`accountProfile`, `privacy`, ...).
SettingsSection? tryParseSettingsSection(String? raw) {
  final name = raw?.trim();
  if (name == null || name.isEmpty) return null;
  for (final section in SettingsSection.values) {
    if (section.name == name) return section;
  }
  return null;
}

/// Clamps [requested] to a section that [audience] is allowed to see.
SettingsSection resolveSettingsSection({
  required SettingsAudience audience,
  required SettingsSection requested,
}) {
  final allowed = settingsSectionsFor(audience);
  return allowed.contains(requested) ? requested : allowed.first;
}

extension SettingsSectionX on SettingsSection {
  String get title => switch (this) {
    SettingsSection.accountProfile => 'Account & Profile',
    SettingsSection.security => 'Security',
    SettingsSection.appearance => 'Appearance',
    SettingsSection.practice => 'Practice',
    SettingsSection.privacy => 'Privacy',
    SettingsSection.about => 'About',
    SettingsSection.contactFeedback => 'Contact & Feedback',
  };

  String get description => switch (this) {
    SettingsSection.accountProfile =>
      'Update your photo, name, and sign-in email.',
    SettingsSection.security =>
      'Update your password and protect access to your Elixr account.',
    SettingsSection.appearance => 'Customize how Elixr looks on this device.',
    SettingsSection.practice => 'Camera, mirroring, and Playground music.',
    SettingsSection.privacy =>
      'Control who can see your detailed player profile activity.',
    SettingsSection.about => 'Learn about ELIXR and the team behind it.',
    SettingsSection.contactFeedback =>
      'Report issues, share feedback, or contact the ELIXR team.',
  };

  IconData get icon => switch (this) {
    SettingsSection.accountProfile => FluentIcons.contact,
    SettingsSection.security => FluentIcons.lock,
    SettingsSection.appearance => FluentIcons.color,
    SettingsSection.practice => FluentIcons.video,
    SettingsSection.privacy => FluentIcons.shield,
    SettingsSection.about => FluentIcons.info,
    SettingsSection.contactFeedback => FluentIcons.mail,
  };
}
