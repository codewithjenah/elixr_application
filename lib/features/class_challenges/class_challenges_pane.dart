import 'dart:async';
import 'dart:developer' as developer;

import 'package:firebase_core/firebase_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/movements.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_panel_card.dart';
import '../../core/widgets/elix_primary_button.dart';
import '../../core/widgets/elix_status_panel.dart';
import '../../core/widgets/movement_image.dart';
import '../../data/models/class_challenge.dart';
import '../../data/models/movement.dart';
import '../../data/models/training_prop.dart';
import '../../data/repositories/class_challenge_repository.dart';

bool canStartTeacherChallengeSubscription({
  required String currentUserId,
  required String teacherId,
}) {
  final current = currentUserId.trim();
  return current.isNotEmpty && current == teacherId.trim();
}

/// Wide desktop editor sizing that adapts to the available Windows window.
BoxConstraints classChallengeEditorConstraints(Size windowSize) {
  final paddedWidth = windowSize.width - AppSpacing.xl * 2;
  final paddedHeight = windowSize.height - AppSpacing.xl * 2;
  var width = paddedWidth.clamp(320.0, 760.0).toDouble();
  var height = paddedHeight.clamp(360.0, 780.0).toDouble();
  if (width > windowSize.width) width = windowSize.width;
  if (height > windowSize.height) height = windowSize.height;
  return BoxConstraints(minWidth: width, maxWidth: width, maxHeight: height);
}

int classChallengeDisplayHour(DateTime value) {
  final hour = value.hour % 12;
  return hour == 0 ? 12 : hour;
}

String classChallengeDisplayPeriod(DateTime value) =>
    value.hour < 12 ? 'AM' : 'PM';

DateTime classChallengeDateTimeFrom12Hour(
  DateTime value, {
  required int hour,
  required int minute,
  required String period,
}) {
  final hour24 = (hour % 12) + (period == 'PM' ? 12 : 0);
  return DateTime(value.year, value.month, value.day, hour24, minute);
}

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
    if (isTeacher &&
        !canStartTeacherChallengeSubscription(
          currentUserId: currentUserId,
          teacherId: teacherId,
        )) {
      return const SizedBox.shrink();
    }
    return StreamBuilder<List<ClassChallenge>>(
      stream: repository.watchChallengesForGroup(
        groupId: groupId,
        teacherId: teacherId,
      ),
      builder: (context, challengeSnapshot) {
        if (challengeSnapshot.hasError) {
          developer.log(
            'Class Challenge query failed for group $groupId.',
            name: 'ClassChallengesPane',
            error: challengeSnapshot.error,
            stackTrace: challengeSnapshot.stackTrace,
          );
          final accessDenied = _isPermissionDenied(challengeSnapshot.error);
          return ElixStatusPanel(
            key: Key('class_challenges_error'),
            title: 'Challenges unavailable',
            message: accessDenied
                ? 'You no longer have access to this classroom.'
                : 'Check your connection and try again.',
            isError: true,
          );
        }
        if (!challengeSnapshot.hasData) {
          return const Center(child: ProgressRing());
        }
        return StreamBuilder<List<ClassChallengeLeaderboardEntry>>(
          stream: repository.watchResultsForGroup(
            groupId: groupId,
            teacherId: teacherId,
          ),
          builder: (context, resultSnapshot) {
            if (resultSnapshot.hasError) {
              developer.log(
                'Class Challenge results query failed for group $groupId.',
                name: 'ClassChallengesPane',
                error: resultSnapshot.error,
                stackTrace: resultSnapshot.stackTrace,
              );
              final accessDenied = _isPermissionDenied(resultSnapshot.error);
              return ElixStatusPanel(
                key: const Key('class_challenge_results_error'),
                title: 'Challenge results unavailable',
                message: accessDenied
                    ? 'You no longer have access to this classroom.'
                    : 'Check your connection and try again.',
                isError: true,
              );
            }
            final challenges = challengeSnapshot.data!
                .where((challenge) => isTeacher || challenge.archivedAt == null)
                .toList(growable: false);
            final results = resultSnapshot.data ?? const [];
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Class Challenges',
                            style: AppTheme.headingMedium,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            isTeacher
                                ? 'Create competitive movement challenges for this class.'
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
                                  results.where(
                                    (entry) =>
                                        entry.challengeId == challenge.id,
                                  ),
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
                                        teacherDisplayName: teacherDisplayName,
                                        existing: challenge,
                                      ),
                                onArchive:
                                    !isTeacher || challenge.archivedAt != null
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
              ),
            );
          },
        );
      },
    );
  }
}

bool _isPermissionDenied(Object? error) =>
    error is FirebaseException && error.code == 'permission-denied';

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
                  child: Text(
                    status == ClassChallengeStatus.upcoming
                        ? 'Not started'
                        : status == ClassChallengeStatus.ended
                        ? 'Challenge ended'
                        : 'Start Challenge',
                  ),
                ),
              if (onEdit != null)
                IconButton(
                  key: Key('class_challenge_edit_${challenge.id}'),
                  icon: const Icon(FluentIcons.edit),
                  onPressed: onEdit,
                ),
              if (onArchive != null)
                IconButton(
                  key: Key('class_challenge_archive_${challenge.id}'),
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

String _deadlineLabel(ClassChallenge challenge, ClassChallengeStatus status) {
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
    builder: (context) => ElixDialog(
      key: const Key('class_challenge_archive_confirmation'),
      title: 'Archive challenge?',
      subtitle: 'Keep the results while taking this challenge out of the class.',
      icon: FluentIcons.archive,
      iconColor: context.elixColors.error,
      headerAccentColor: context.elixColors.error,
      maxWidth: 480,
      content: Text(
        'The challenge will no longer be available for new attempts. '
        'Existing attempts and leaderboard results will be kept.',
        style: AppTheme.bodySecondary.copyWith(
          color: context.elixTextSecondary,
          height: 1.4,
        ),
      ),
      actions: [
        Button(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.pressed)) {
                return context.elixColors.error.withValues(alpha: 0.82);
              }
              if (states.contains(WidgetState.hovered)) {
                return context.elixColors.error.withValues(alpha: 0.92);
              }
              return context.elixColors.error;
            }),
            foregroundColor: WidgetStatePropertyAll(context.elixColors.onBrand),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Archive'),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await repository.archiveChallenge(challengeId: challenge.id);
  }
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
  final attempts = TextEditingController(
    text: existing?.attemptLimit?.toString() ?? '',
  );
  final target = TextEditingController(
    text: existing?.targetScore?.toString() ?? '',
  );
  Movement movement = movementCatalog.firstWhere(
    (item) => item.name == existing?.movementName,
    orElse: () => movementCatalog.first,
  );
  var prop = existing?.prop ?? movement.supportedProps.first;
  var start =
      existing?.startAt.toLocal() ??
      DateTime.now().add(const Duration(hours: 1));
  var deadline =
      existing?.deadline.toLocal() ??
      DateTime.now().add(const Duration(days: 7));
  String? error;
  String? titleError;
  String? descriptionError;
  String? attemptsError;
  String? targetError;
  var saving = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setDialogState) {
        final enabledMovements = movementCatalog
            .where((item) => item.enabled)
            .toList(growable: false);
        Future<void> saveChallenge() async {
          final limit = attempts.text.trim().isEmpty
              ? null
              : int.tryParse(attempts.text.trim());
          final targetScore = target.text.trim().isEmpty
              ? null
              : int.tryParse(target.text.trim());
          final titleValue = title.text.trim();
          final descriptionValue = description.text.trim();
          if (titleValue.isEmpty ||
              titleValue.length > ClassChallenge.maxTitleLength) {
            setDialogState(() {
              error = null;
              titleError = 'Enter a title of 80 characters or fewer.';
              descriptionError = null;
              attemptsError = null;
              targetError = null;
            });
            return;
          }
          if (descriptionValue.isEmpty ||
              descriptionValue.length > ClassChallenge.maxDescriptionLength) {
            setDialogState(() {
              error = null;
              titleError = null;
              descriptionError =
                  'Enter instructions of 500 characters or fewer.';
              attemptsError = null;
              targetError = null;
            });
            return;
          }
          if (!deadline.isAfter(start)) {
            setDialogState(() {
              error = 'Deadline must be after the start time.';
              titleError = null;
              descriptionError = null;
              attemptsError = null;
              targetError = null;
            });
            return;
          }
          if (attempts.text.trim().isNotEmpty &&
              (limit == null || limit < 1 || limit > 20)) {
            setDialogState(() {
              error = null;
              attemptsError = 'Attempt limit must be between 1 and 20.';
              targetError = null;
            });
            return;
          }
          if (target.text.trim().isNotEmpty &&
              (targetScore == null || targetScore < 0 || targetScore > 12)) {
            setDialogState(() {
              error = null;
              attemptsError = null;
              targetError = 'Target score must be between 0 and 12.';
            });
            return;
          }
          setDialogState(() {
            saving = true;
            error = null;
            titleError = null;
            descriptionError = null;
            attemptsError = null;
            targetError = null;
          });
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
        }

        final editorConstraints = classChallengeEditorConstraints(
          MediaQuery.sizeOf(dialogContext),
        );
        final availableWidth =
            MediaQuery.sizeOf(dialogContext).width - AppSpacing.lg * 2;
        final dialogWidth = editorConstraints.maxWidth > availableWidth
            ? availableWidth
            : editorConstraints.maxWidth;
        return FocusTraversalGroup(
          child: ElixDialog(
            key: const Key('class_challenge_editor'),
            title: existing == null
                ? 'Create Class Challenge'
                : 'Edit Class Challenge',
            subtitle: existing == null
                ? 'Set up a movement challenge for your class.'
                : 'Update the movement challenge for your class.',
            icon: FluentIcons.trophy,
            maxWidth: dialogWidth,
            maxHeight: editorConstraints.maxHeight,
            scrollableContent: true,
            content: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 620;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                      _EditorSection(
                        icon: FluentIcons.edit,
                        title: 'Challenge details',
                        description:
                            'Give the challenge a clear name and simple instructions.',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ChallengeField(
                              label: 'Challenge title',
                              helperText:
                                  'Choose a name your class will recognize.',
                              errorText: titleError,
                              child: TextBox(
                                key: const Key('class_challenge_title'),
                                controller: title,
                                autofocus: true,
                                placeholder: 'Example: Friday Bottle Flair',
                                maxLength: ClassChallenge.maxTitleLength,
                                onChanged: (_) {
                                  if (titleError != null) {
                                    setDialogState(() => titleError = null);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            _ChallengeField(
                              label: 'Instructions',
                              helperText:
                                  'Tell trainees what to practice and submit.',
                              errorText: descriptionError,
                              child: TextBox(
                                key: const Key('class_challenge_description'),
                                controller: description,
                                placeholder:
                                    'Add a short description of the challenge.',
                                maxLength: ClassChallenge.maxDescriptionLength,
                                minLines: 2,
                                maxLines: 4,
                                onChanged: (_) {
                                  if (descriptionError != null) {
                                    setDialogState(
                                      () => descriptionError = null,
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _EditorSection(
                        icon: FluentIcons.product_variant,
                        title: 'Movement',
                        description:
                            'Choose the movement and prop trainees will use.',
                        child: _MovementAndPropFields(
                          wide: wide,
                          movement: movement,
                          prop: prop,
                          enabledMovements: enabledMovements,
                          onMovementChanged: (value) => setDialogState(() {
                            if (value == null) return;
                            movement = value;
                            prop = movement.supportedProps.first;
                          }),
                          onPropChanged: (value) =>
                              setDialogState(() => prop = value ?? prop),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _EditorSection(
                        icon: FluentIcons.calendar,
                        title: 'Schedule',
                        description:
                            'Set when trainees can start and when the challenge closes.',
                        child: _ResponsivePair(
                          wide: wide,
                          left: _DateTimeField(
                            key: const Key('class_challenge_start'),
                            label: 'Start',
                            value: start,
                            onChanged: (value) =>
                                setDialogState(() => start = value),
                          ),
                          right: _DateTimeField(
                            key: const Key('class_challenge_deadline'),
                            label: 'Deadline',
                            value: deadline,
                            onChanged: (value) =>
                                setDialogState(() => deadline = value),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _EditorSection(
                        icon: FluentIcons.settings,
                        title: 'Challenge settings',
                        description:
                            'Make the challenge fit the way your class practices.',
                        child: _ResponsivePair(
                          wide: wide,
                          left: _ChallengeField(
                            label: 'Attempts per trainee',
                            helperText: 'Leave blank for unlimited attempts.',
                            errorText: attemptsError,
                            child: TextBox(
                              key: const Key('class_challenge_attempts'),
                              controller: attempts,
                              keyboardType: TextInputType.number,
                              placeholder: 'Unlimited',
                              onChanged: (_) => setDialogState(() {
                                attemptsError = null;
                                error = null;
                              }),
                            ),
                          ),
                          right: _ChallengeField(
                            label: 'Goal score',
                            helperText:
                                'Optional. Set a score trainees can aim for.',
                            errorText: targetError,
                            child: TextBox(
                              key: const Key('class_challenge_target'),
                              controller: target,
                              keyboardType: TextInputType.number,
                              placeholder: '0–12',
                              onChanged: (_) => setDialogState(() {
                                targetError = null;
                                error = null;
                              }),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const _ScoringInfo(),
                      if (error != null &&
                          attemptsError == null &&
                          targetError == null) ...[
                        const SizedBox(height: AppSpacing.md),
                        _EditorErrorNotice(message: error!),
                      ],
                  ],
                );
              },
            ),
            actions: [
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  SizedBox(
                    key: const Key('class_challenge_cancel_action'),
                    height: 56,
                    child: Button(
                      onPressed:
                          saving ? null : () => Navigator.pop(dialogContext),
                      child: const Text('Cancel'),
                    ),
                  ),
                  SizedBox(
                    key: const Key('class_challenge_primary_action'),
                    height: 56,
                    child: ElixPrimaryButton(
                      label: existing == null
                          ? 'Create Challenge'
                          : 'Save Changes',
                      expanded: false,
                      isLoading: saving,
                      onPressed: saving ? null : saveChallenge,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
  title.dispose();
  description.dispose();
  attempts.dispose();
  target.dispose();
}

class _EditorSection extends StatelessWidget {
  const _EditorSection({
    required this.icon,
    required this.title,
    required this.description,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tone = context.isHighContrast
        ? context.elixTextPrimary
        : context.elixColors.brandSecondary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: tone),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTheme.headingMedium.copyWith(
                      color: context.elixTextPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: AppTheme.caption.copyWith(
                      color: context.elixTextSecondary,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        child,
      ],
    );
  }
}

class _ChallengeField extends StatelessWidget {
  const _ChallengeField({
    required this.label,
    required this.helperText,
    required this.child,
    this.errorText,
  });

  final String label;
  final String helperText;
  final Widget child;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppTheme.label(color: context.elixTextPrimary)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          helperText,
          style: AppTheme.caption.copyWith(
            color: context.elixTextSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Semantics(label: label, hint: helperText, child: child),
        if (errorText != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                FluentIcons.error_badge,
                size: 13,
                color: context.elixColors.error,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  errorText!,
                  style: AppTheme.caption.copyWith(
                    color: context.elixColors.error,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _EditorErrorNotice extends StatelessWidget {
  const _EditorErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final tone = context.elixColors.error;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? context.elixCardSurface
            : tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: context.isHighContrast
              ? context.elixBorder
              : tone.withValues(alpha: 0.28),
          width: context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FluentIcons.error_badge,
            size: 16,
            color: context.isHighContrast ? context.elixTextPrimary : tone,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTheme.caption.copyWith(
                color: context.elixTextPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({
    required this.wide,
    required this.left,
    required this.right,
  });

  final bool wide;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          left,
          const SizedBox(height: AppSpacing.md),
          right,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: right),
      ],
    );
  }
}

class _MovementAndPropFields extends StatelessWidget {
  const _MovementAndPropFields({
    required this.wide,
    required this.movement,
    required this.prop,
    required this.enabledMovements,
    required this.onMovementChanged,
    required this.onPropChanged,
  });

  final bool wide;
  final Movement movement;
  final TrainingProp prop;
  final List<Movement> enabledMovements;
  final ValueChanged<Movement?> onMovementChanged;
  final ValueChanged<TrainingProp?> onPropChanged;

  @override
  Widget build(BuildContext context) {
    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ChallengeField(
          label: 'Movement',
          helperText: 'Choose the movement trainees will practice.',
          child: ComboBox<Movement>(
            key: const Key('class_challenge_movement'),
            value: movement,
            isExpanded: true,
            items: [
              for (final item in enabledMovements)
                ComboBoxItem(
                  value: item,
                  child: ClassChallengeMovementOption(
                    movement: item,
                    prop: prop,
                  ),
                ),
            ],
            selectedItemBuilder: (context) => [
              for (final item in enabledMovements)
                ClassChallengeMovementOption(movement: item, prop: prop),
            ],
            onChanged: onMovementChanged,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _ChallengeField(
          label: 'Prop',
          helperText: 'Choose the prop used for this challenge.',
          child: ComboBox<TrainingProp>(
            key: const Key('class_challenge_prop'),
            value: prop,
            isExpanded: true,
            items: [
              for (final item in movement.supportedProps)
                ComboBoxItem(value: item, child: Text(item.displayLabel)),
            ],
            onChanged: onPropChanged,
          ),
        ),
      ],
    );
    final preview = _SelectedMovementPreview(movement: movement, prop: prop);
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: preview),
          const SizedBox(height: AppSpacing.md),
          fields,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        preview,
        const SizedBox(width: AppSpacing.md),
        Expanded(child: fields),
      ],
    );
  }
}

class _SelectedMovementPreview extends StatelessWidget {
  const _SelectedMovementPreview({required this.movement, required this.prop});

  final Movement movement;
  final TrainingProp prop;

  @override
  Widget build(BuildContext context) {
    final accent = _difficultyAccent(context, movement.difficulty);
    return Container(
      width: 176,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? context.elixCardSurface
            : context.elixColors.surfaceTinted,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: context.isHighContrast
              ? context.elixBorder
              : context.elixColors.borderSubtle,
          width: context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 104,
            child: Center(
              child: MovementImage(
                key: const Key('class_challenge_movement_preview'),
                movementName: movement.name,
                size: 96,
                prop: prop,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            movement.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body.copyWith(
              fontWeight: FontWeight.w700,
              color: context.elixTextPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ElixPill(text: movement.difficulty, color: accent, compact: true),
        ],
      ),
    );
  }
}

/// ComboBox row used for both the closed selector and dropdown items.
class ClassChallengeMovementOption extends StatelessWidget {
  const ClassChallengeMovementOption({
    super.key,
    required this.movement,
    required this.prop,
  });

  final Movement movement;
  final TrainingProp prop;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MovementImage(
          movementName: movement.name,
          size: 22,
          paddingFactor: 0.02,
          prop: prop,
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            movement.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.body.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: context.elixTextPrimary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          movement.difficulty,
          style: AppTheme.caption.copyWith(
            color: _difficultyAccent(context, movement.difficulty),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ScoringInfo extends StatelessWidget {
  const _ScoringInfo();

  @override
  Widget build(BuildContext context) {
    final colors = context.elixColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? context.elixCardSurface
            : colors.brandSecondary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: context.isHighContrast
              ? context.elixBorder
              : colors.brandSecondary.withValues(alpha: 0.28),
          width: context.isHighContrast ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            FluentIcons.info,
            size: 14,
            color: context.isHighContrast
                ? context.elixTextPrimary
                : colors.brandSecondary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Highest score wins. Scores range from 0 to 12.',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _difficultyAccent(BuildContext context, String difficulty) {
  final colors = context.elixColors;
  return switch (difficulty) {
    'Easy' => colors.success,
    'Medium' => colors.warning,
    'Hard' => colors.error,
    _ => colors.textMuted,
  };
}

List<int> _visibleMinuteOptions(int minute) {
  final options = <int>{0, 15, 30, 45, minute}.toList()..sort();
  return options;
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final fieldKey = label == 'Start' ? 'start' : 'deadline';
    final displayHour = classChallengeDisplayHour(value);
    final displayPeriod = classChallengeDisplayPeriod(value);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              FluentIcons.calendar,
              size: 14,
              color: context.isHighContrast
                  ? context.elixTextPrimary
                  : context.elixColors.brandSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(label, style: AppTheme.label(color: context.elixTextPrimary)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        DatePicker(
          key: Key('class_challenge_${fieldKey}_date'),
          selected: value,
          onChanged: (date) => onChanged(
            DateTime(date.year, date.month, date.day, value.hour, value.minute),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Icon(
              FluentIcons.clock,
              size: 14,
              color: context.isHighContrast
                  ? context.elixTextPrimary
                  : context.elixColors.brandSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text('Time', style: AppTheme.label(color: context.elixTextPrimary)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(
              child: ComboBox<int>(
                key: Key('class_challenge_${fieldKey}_hour'),
                value: displayHour,
                isExpanded: true,
                placeholder: const Text('Hour'),
                items: [
                  for (var hour = 1; hour <= 12; hour++)
                    ComboBoxItem(value: hour, child: Text(hour.toString())),
                ],
                onChanged: (hour) => onChanged(
                  classChallengeDateTimeFrom12Hour(
                    value,
                    hour: hour ?? displayHour,
                    minute: value.minute,
                    period: displayPeriod,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text(
                ':',
                style: AppTheme.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.elixTextPrimary,
                ),
              ),
            ),
            Expanded(
              child: ComboBox<int>(
                key: Key('class_challenge_${fieldKey}_minute'),
                value: value.minute,
                isExpanded: true,
                placeholder: const Text('Minute'),
                items: [
                  for (final minute in _visibleMinuteOptions(value.minute))
                    ComboBoxItem(
                      value: minute,
                      child: Text(minute.toString().padLeft(2, '0')),
                    ),
                ],
                onChanged: (minute) => onChanged(
                  classChallengeDateTimeFrom12Hour(
                    value,
                    hour: displayHour,
                    minute: minute ?? value.minute,
                    period: displayPeriod,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ComboBox<String>(
                key: Key('class_challenge_${fieldKey}_period'),
                value: displayPeriod,
                isExpanded: true,
                items: const [
                  ComboBoxItem(value: 'AM', child: Text('AM')),
                  ComboBoxItem(value: 'PM', child: Text('PM')),
                ],
                onChanged: (period) => onChanged(
                  classChallengeDateTimeFrom12Hour(
                    value,
                    hour: displayHour,
                    minute: value.minute,
                    period: period ?? displayPeriod,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
