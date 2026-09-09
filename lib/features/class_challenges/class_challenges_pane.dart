import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../data/models/class_challenge.dart';
import '../../data/models/movement.dart';
import '../../data/models/training_prop.dart';
import '../../data/repositories/class_challenge_repository.dart';

class ClassChallengesPane extends StatelessWidget {
  const ClassChallengesPane({
    super.key,
    required this.repository,
    required this.groupId,
    required this.teacherId,
    required this.teacherDisplayName,
    required this.currentUserId,
    required this.isTeacher,
    required this.groupIsActive,
    required this.participantCount,
    required this.onOpenLeaderboard,
    this.onStart,
  });

  final ClassChallengeRepository repository;
  final String groupId;
  final String teacherId;
  final String teacherDisplayName;
  final String currentUserId;
  final bool isTeacher;
  final bool groupIsActive;
  final int participantCount;
  final ValueChanged<ClassChallenge> onOpenLeaderboard;
  final ValueChanged<ClassChallenge>? onStart;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ClassChallenge>>(
      stream: repository.watchChallengesForGroup(groupId: groupId),
      builder: (context, challengeSnapshot) {
        if (challengeSnapshot.hasError) {
          return const ElixStatusPanel(
            key: Key('class_challenges_error'),
            title: 'Challenges unavailable',
            message: 'Check your connection and try again.',
            isError: true,
          );
        }
        if (!challengeSnapshot.hasData) {
          return const Center(child: ProgressRing());
        }
        return StreamBuilder<List<ClassChallengeLeaderboardEntry>>(
          stream: repository.watchResultsForGroup(groupId: groupId),
          builder: (context, resultSnapshot) {
            final challenges = challengeSnapshot.data!
                .where((challenge) =>
                    isTeacher || challenge.archivedAt == null)
                .toList(growable: false);
            final results = resultSnapshot.data ?? const [];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Class Challenges', style: AppTheme.headingMedium),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            isTeacher
                                ? 'Create competitive runs scored by ELIXR\'s 0–12 movement rubric.'
                                : 'Compete with classmates. Only your best valid attempt ranks.',
                            style: AppTheme.bodySecondary,
                          ),
                        ],
                      ),
                    ),
                    if (isTeacher)
                      ElixPrimaryButton(
                        key: const Key('class_challenge_create'),
                        label: 'New challenge',
                        icon: FluentIcons.add,
                        expanded: false,
                        onPressed: groupIsActive
                            ? () => _showChallengeEditor(
                                context,
                                repository: repository,
                                groupId: groupId,
                                teacherId: teacherId,
                                teacherDisplayName: teacherDisplayName,
                              )
                            : null,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (challenges.isEmpty)
                  ElixStatusPanel(
                    key: const Key('class_challenges_empty'),
                    icon: FluentIcons.trophy,
                    title: 'No challenges yet',
                    message: isTeacher
                        ? 'Create the first timed movement challenge for this class.'
                        : 'Your teacher has not published a challenge yet.',
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 1100 ? 2 : 1;
                      final width = columns == 2
                          ? (constraints.maxWidth - AppSpacing.md) / 2
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: AppSpacing.md,
                        runSpacing: AppSpacing.md,
                        children: [
                          for (final challenge in challenges)
                            SizedBox(
                              width: width,
                              child: _ChallengeCard(
                                challenge: challenge,
                                entries: rankClassChallengeEntries(
                                  results.where((entry) =>
                                      entry.challengeId == challenge.id),
                                ),
                                currentUserId: currentUserId,
                                participantCount: participantCount,
                                isTeacher: isTeacher,
                                onOpenLeaderboard: () =>
                                    onOpenLeaderboard(challenge),
                                onStart: onStart == null
                                    ? null
                                    : () => onStart!(challenge),
                                onEdit: !isTeacher || !groupIsActive
                                    ? null
                                    : () => _showChallengeEditor(
                                          context,
                                          repository: repository,
                                          groupId: groupId,
                                          teacherId: teacherId,
                                          teacherDisplayName:
                                              teacherDisplayName,
                                          existing: challenge,
                                        ),
                                onArchive: !isTeacher || challenge.archivedAt != null
                                    ? null
                                    : () => _archiveChallenge(
                                          context,
                                          repository,
                                          challenge,
                                        ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ChallengeCard extends StatelessWidget {
  const _ChallengeCard({
    required this.challenge,
    required this.entries,
    required this.currentUserId,
    required this.participantCount,
    required this.isTeacher,
    required this.onOpenLeaderboard,
    this.onStart,
    this.onEdit,
    this.onArchive,
  });

  final ClassChallenge challenge;
  final List<ClassChallengeLeaderboardEntry> entries;
  final String currentUserId;
  final int participantCount;
  final bool isTeacher;
  final VoidCallback onOpenLeaderboard;
  final VoidCallback? onStart;
  final VoidCallback? onEdit;
  final VoidCallback? onArchive;

  @override
  Widget build(BuildContext context) {
    final status = challenge.statusAt();
    final personalIndex = entries.indexWhere(
      (entry) => entry.traineeId == currentUserId,
    );
    final personal = personalIndex < 0 ? null : entries[personalIndex];
    final canStart = !isTeacher && status == ClassChallengeStatus.active;
    return ElixPanelCard(
      key: Key('class_challenge_card_${challenge.id}'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0x33FF2FA8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(FluentIcons.trophy, color: Color(0xFFFF2FA8)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(challenge.title, style: AppTheme.headingMedium),
                    const SizedBox(height: 2),
                    Text(
                      '${challenge.movementName} · ${challenge.prop.displayLabel}',
                      style: AppTheme.bodySecondary,
                    ),
                  ],
                ),
              ),
              _StatusPill(status: status),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _deadlineLabel(challenge, status),
            style: AppTheme.body.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (isTeacher)
            Text(
              '$participantCount participants · ${challenge.completedCount} completed · '
              'Top score ${challenge.topScore == null ? '—' : '${challenge.topScore}/12'}',
              style: AppTheme.bodySecondary,
            )
          else
            Text(
              personal == null
                  ? 'Personal best — · Rank —'
                  : 'Personal best ${personal.score}/12 · Rank #${personalIndex + 1}',
              key: Key('class_challenge_personal_${challenge.id}'),
              style: AppTheme.bodySecondary,
            ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                onPressed: onOpenLeaderboard,
                child: const Text('View Leaderboard'),
              ),
              if (!isTeacher)
                Button(
                  key: Key('class_challenge_start_${challenge.id}'),
                  onPressed: canStart ? onStart : null,
                  child: Text(status == ClassChallengeStatus.upcoming
                      ? 'Not started'
                      : status == ClassChallengeStatus.ended
                          ? 'Challenge ended'
                          : 'Start Challenge'),
                ),
              if (onEdit != null)
                IconButton(
                  icon: const Icon(FluentIcons.edit),
                  onPressed: onEdit,
                ),
              if (onArchive != null)
                IconButton(
                  icon: const Icon(FluentIcons.archive),
                  onPressed: onArchive,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});
  final ClassChallengeStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      ClassChallengeStatus.upcoming => 'Upcoming',
      ClassChallengeStatus.active => 'Active',
      ClassChallengeStatus.ended => 'Ended',
      ClassChallengeStatus.archived => 'Archived',
    };
    final color = switch (status) {
      ClassChallengeStatus.active => const Color(0xFF4FE3AF),
      ClassChallengeStatus.upcoming => const Color(0xFFF4B84A),
      _ => const Color(0xFFAAA5B8),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}

String _deadlineLabel(
  ClassChallenge challenge,
  ClassChallengeStatus status,
) {
  final formatter = DateFormat('MMM d, y · h:mm a');
  if (status == ClassChallengeStatus.upcoming) {
    return 'Starts ${formatter.format(challenge.startAt.toLocal())}';
  }
  if (status == ClassChallengeStatus.active) {
    final remaining = challenge.deadline.difference(DateTime.now().toUtc());
    if (remaining.inDays > 0) return '${remaining.inDays}d remaining';
    if (remaining.inHours > 0) return '${remaining.inHours}h remaining';
    return '${remaining.inMinutes.clamp(0, 59)}m remaining';
  }
  return 'Ended ${formatter.format(challenge.deadline.toLocal())}';
}

Future<void> _archiveChallenge(
  BuildContext context,
  ClassChallengeRepository repository,
  ClassChallenge challenge,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => ContentDialog(
      title: const Text('Archive challenge?'),
      content: const Text(
        'Existing attempts and leaderboard results will be preserved.',
      ),
      actions: [
        Button(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Archive')),
      ],
    ),
  );
  if (confirmed == true) await repository.archiveChallenge(challengeId: challenge.id);
}

Future<void> _showChallengeEditor(
  BuildContext context, {
  required ClassChallengeRepository repository,
  required String groupId,
  required String teacherId,
  required String teacherDisplayName,
  ClassChallenge? existing,
}) async {
  final title = TextEditingController(text: existing?.title ?? '');
  final description = TextEditingController(text: existing?.description ?? '');
  final attempts = TextEditingController(text: existing?.attemptLimit?.toString() ?? '');
  final target = TextEditingController(text: existing?.targetScore?.toString() ?? '');
  Movement movement = movementCatalog.firstWhere(
    (item) => item.name == existing?.movementName,
    orElse: () => movementCatalog.first,
  );
  var prop = existing?.prop ?? movement.supportedProps.first;
  var start = existing?.startAt.toLocal() ?? DateTime.now().add(const Duration(hours: 1));
  var deadline = existing?.deadline.toLocal() ?? DateTime.now().add(const Duration(days: 7));
  String? error;
  var saving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) => ContentDialog(
        title: Text(existing == null ? 'Create Class Challenge' : 'Edit Class Challenge'),
        content: SizedBox(
          width: 560,
          height: 540,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InfoLabel(
                  label: 'Challenge title',
                  child: TextBox(controller: title, maxLength: ClassChallenge.maxTitleLength),
                ),
                const SizedBox(height: AppSpacing.sm),
                InfoLabel(
                  label: 'Instructions',
                  child: TextBox(
                    controller: description,
                    maxLength: ClassChallenge.maxDescriptionLength,
                    minLines: 2,
                    maxLines: 4,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                InfoLabel(
                  label: 'Official ELIXR movement',
                  child: ComboBox<Movement>(
                    value: movement,
                    isExpanded: true,
                    items: [
                      for (final item in movementCatalog.where((item) => item.enabled))
                        ComboBoxItem(value: item, child: Text(item.name)),
                    ],
                    onChanged: (value) => setDialogState(() {
                      if (value == null) return;
                      movement = value;
                      prop = movement.supportedProps.first;
                    }),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                InfoLabel(
                  label: 'Supported prop',
                  child: ComboBox<TrainingProp>(
                    value: prop,
                    isExpanded: true,
                    items: [
                      for (final item in movement.supportedProps)
                        ComboBoxItem(value: item, child: Text(item.displayLabel)),
                    ],
                    onChanged: (value) => setDialogState(() => prop = value ?? prop),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                _DateTimeField(
                  label: 'Start date and time',
                  value: start,
                  onChanged: (value) => setDialogState(() => start = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                _DateTimeField(
                  label: 'Deadline',
                  value: deadline,
                  onChanged: (value) => setDialogState(() => deadline = value),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: InfoLabel(
                        label: 'Attempt limit (optional, 1–20)',
                        child: TextBox(controller: attempts, keyboardType: TextInputType.number),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: InfoLabel(
                        label: 'Target score (optional, 0–12)',
                        child: TextBox(controller: target, keyboardType: TextInputType.number),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                const InfoBar(
                  title: Text('Scoring'),
                  content: Text('Best Assessment V2 rubric total wins (maximum 12).'),
                  severity: InfoBarSeverity.info,
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  InfoBar(title: const Text('Check the challenge'), content: Text(error!), severity: InfoBarSeverity.error),
                ],
              ],
            ),
          ),
        ),
        actions: [
          Button(onPressed: saving ? null : () => Navigator.pop(dialogContext), child: const Text('Cancel')),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    final limit = attempts.text.trim().isEmpty ? null : int.tryParse(attempts.text.trim());
                    final targetScore = target.text.trim().isEmpty ? null : int.tryParse(target.text.trim());
                    final titleValue = title.text.trim();
                    final descriptionValue = description.text.trim();
                    if (titleValue.isEmpty || titleValue.length > ClassChallenge.maxTitleLength) {
                      setDialogState(() => error = 'Enter a title of 80 characters or fewer.');
                      return;
                    }
                    if (descriptionValue.isEmpty || descriptionValue.length > ClassChallenge.maxDescriptionLength) {
                      setDialogState(() => error = 'Enter instructions of 500 characters or fewer.');
                      return;
                    }
                    if (!deadline.isAfter(start)) {
                      setDialogState(() => error = 'Deadline must be after the start time.');
                      return;
                    }
                    if (limit != null && (limit < 1 || limit > 20)) {
                      setDialogState(() => error = 'Attempt limit must be between 1 and 20.');
                      return;
                    }
                    if (targetScore != null && (targetScore < 0 || targetScore > 12)) {
                      setDialogState(() => error = 'Target score must be between 0 and 12.');
                      return;
                    }
                    setDialogState(() { saving = true; error = null; });
                    final value = ClassChallenge(
                      id: existing?.id ?? '',
                      groupId: groupId,
                      teacherId: teacherId,
                      teacherDisplayName: teacherDisplayName,
                      title: titleValue,
                      description: descriptionValue,
                      movementName: movement.name,
                      difficulty: movement.difficulty,
                      prop: prop,
                      startAt: start.toUtc(),
                      deadline: deadline.toUtc(),
                      attemptLimit: limit,
                      targetScore: targetScore,
                      archivedAt: existing?.archivedAt,
                      createdAt: existing?.createdAt,
                      updatedAt: existing?.updatedAt,
                    );
                    try {
                      if (existing == null) {
                        await repository.createChallenge(challenge: value);
                      } else {
                        await repository.updateChallenge(challenge: value);
                      }
                      if (dialogContext.mounted) Navigator.pop(dialogContext);
                    } on ClassChallengeException catch (failure) {
                      setDialogState(() {
                        saving = false;
                        error = failure.code == 'attempts_exist'
                            ? 'Movement, timing, prop, and attempt limit are locked after the first attempt.'
                            : 'Could not save the challenge. Check your connection and try again.';
                      });
                    }
                  },
            child: saving ? const ProgressRing(strokeWidth: 2) : const Text('Save'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  description.dispose();
  attempts.dispose();
  target.dispose();
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({required this.label, required this.value, required this.onChanged});
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InfoLabel(
      label: label,
      child: Row(
        children: [
          Expanded(
            child: DatePicker(
              selected: value,
              onChanged: (date) => onChanged(DateTime(date.year, date.month, date.day, value.hour, value.minute)),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 105,
            child: ComboBox<int>(
              value: value.hour,
              items: [for (var hour = 0; hour < 24; hour++) ComboBoxItem(value: hour, child: Text(hour.toString().padLeft(2, '0')))],
              onChanged: (hour) => onChanged(DateTime(value.year, value.month, value.day, hour ?? value.hour, value.minute)),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          SizedBox(
            width: 90,
            child: ComboBox<int>(
              value: value.minute,
              items: const [
                ComboBoxItem(value: 0, child: Text('00')),
                ComboBoxItem(value: 15, child: Text('15')),
                ComboBoxItem(value: 30, child: Text('30')),
                ComboBoxItem(value: 45, child: Text('45')),
              ],
              onChanged: (minute) => onChanged(DateTime(value.year, value.month, value.day, value.hour, minute ?? value.minute)),
            ),
          ),
        ],
      ),
    );
  }
}
