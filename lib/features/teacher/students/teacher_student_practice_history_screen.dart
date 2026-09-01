import 'dart:typed_data';

import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/router/app_route_paths.dart';
import '../../../core/shell/teacher_shell.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/elix_back_button.dart';
import '../../../core/widgets/elix_editorial_header.dart';
import '../../../core/widgets/elix_status_panel.dart';
import '../../../core/widgets/movement_image.dart';
import '../../../data/models/assessment_score_display.dart';
import '../../../data/repositories/public_profile_repository.dart';
import '../../../services/auth_service.dart';
import '../../history/history_format.dart';
import 'teacher_student_detail_controller.dart';

class TeacherStudentPracticeHistoryScreen extends StatefulWidget {
  const TeacherStudentPracticeHistoryScreen({
    super.key,
    required this.traineeId,
    this.groupId,
    this.evidenceRepository,
  });
  final String traineeId;
  final String? groupId;
  final TeacherEvidenceRepository? evidenceRepository;
  @override
  State<TeacherStudentPracticeHistoryScreen> createState() =>
      _TeacherStudentPracticeHistoryScreenState();
}

class _TeacherStudentPracticeHistoryScreenState
    extends State<TeacherStudentPracticeHistoryScreen> {
  TeacherStudentDetailController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final teacherId = context.read<AuthService>().currentUser?.id;
    if (teacherId == null) return;
    _controller = TeacherStudentDetailController(
      groupRepository: context.read(),
      progressRepository: context.read(),
      publicProfileRepository: context.read<PublicProfileRepository>(),
      teacherId: teacherId,
      traineeId: widget.traineeId,
      preferredGroupId: widget.groupId,
      initialPracticePageSize: TeacherProgressRepository.defaultPageSize,
      evidenceRepository: widget.evidenceRepository ?? _maybeEvidence(context),
    )..start();
  }

  TeacherEvidenceRepository? _maybeEvidence(BuildContext context) {
    try {
      return context.read<TeacherEvidenceRepository>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const Center(child: ProgressRing());
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => TeacherScaffoldPage(
        scrollable: false,
        header: const ElixEditorialPageHeader(
          heading: 'History',
          eyebrow: 'TEACHER WORKSPACE',
          variant: ElixEditorialHeaderVariant.compact,
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ElixBackButton(
              label: 'Student details',
              tooltip: 'Back to student details',
              semanticLabel: 'Back to student details',
              onPressed: () => context.go(
                AppRoutePaths.teacherStudentDetail(
                  widget.traineeId,
                  groupId: widget.groupId,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(child: _HistoryBody(controller: controller)),
          ],
        ),
      ),
    );
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({required this.controller});
  final TeacherStudentDetailController controller;
  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    if (state == TeacherStudentDetailState.loadingClassroom ||
        state == TeacherStudentDetailState.loadingProgress)
      return const Center(child: ProgressRing());
    if (state == TeacherStudentDetailState.unauthorized ||
        state == TeacherStudentDetailState.pending ||
        state == TeacherStudentDetailState.relationshipRemoved)
      return const ElixStatusPanel(
        isError: true,
        message: 'Classroom authorization is required to view History.',
      );
    if (state == TeacherStudentDetailState.error ||
        state == TeacherStudentDetailState.connectionRequired)
      return ElixStatusPanel(
        isError: true,
        message: 'History could not be loaded.',
        actionLabel: 'Retry',
        onAction: controller.refresh,
      );
    if (controller.sessions.isEmpty)
      return const ElixStatusPanel(message: 'No History yet.');
    return ListView(
      children: [
        for (final session in controller.sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _TeacherHistorySessionRow(
              controller: controller,
              session: session,
            ),
          ),
        if (controller.paginationError != null)
          Center(
            child: Button(
              onPressed: controller.retryLoadMore,
              child: const Text('Retry load more'),
            ),
          )
        else if (controller.hasMore)
          Center(
            child: Button(
              onPressed: controller.loadingMore ? null : controller.loadMore,
              child: controller.loadingMore
                  ? const ProgressRing()
                  : const Text('Load more'),
            ),
          ),
      ],
    );
  }
}

class _TeacherHistorySessionRow extends StatefulWidget {
  const _TeacherHistorySessionRow({
    required this.controller,
    required this.session,
  });
  final TeacherStudentDetailController controller;
  final PublicProfileSession session;
  @override
  State<_TeacherHistorySessionRow> createState() =>
      _TeacherHistorySessionRowState();
}

class _TeacherHistorySessionRowState extends State<_TeacherHistorySessionRow> {
  bool _expanded = false, _hovered = false, _focused = false;
  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && widget.session.evidenceAvailable == true)
      widget.controller.loadEvidence(widget.session);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final rubric = s.rubric;
    final isRubric = s.isRubricAssessed && rubric != null;
    final result = isRubric
        ? '${AssessmentScoreDisplay.official(rubric.total)} · ${rubric.performanceLevel.label}'
        : s.legacyScore == null
        ? 'Not scored'
        : '${s.legacyScore}%';
    final active = _expanded || _hovered || _focused;
    return Semantics(
      button: true,
      expanded: _expanded,
      label: '${_expanded ? 'Collapse' : 'Expand'} ${s.movementName} session',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: AnimatedContainer(
            key: Key('teacher_history_row_${s.sessionId}'),
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: active
                  ? context.elixCardSurface
                  : context.elixPanelSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _focused
                    ? context.elixColors.focusRing
                    : _expanded || _hovered
                    ? AppColors.accent.withValues(alpha: .45)
                    : context.elixColors.borderSubtle,
                width: _focused ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LayoutBuilder(
                  builder: (context, c) => c.maxWidth >= 700
                      ? _WideSummary(
                          session: s,
                          result: result,
                          expanded: _expanded,
                        )
                      : _NarrowSummary(
                          session: s,
                          result: result,
                          expanded: _expanded,
                        ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.topCenter,
                  child: _expanded
                      ? _TeacherHistoryDetails(
                          controller: widget.controller,
                          session: s,
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WideSummary extends StatelessWidget {
  const _WideSummary({
    required this.session,
    required this.result,
    required this.expanded,
  });
  final PublicProfileSession session;
  final String result;
  final bool expanded;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      MovementImage(movementName: session.movementName, size: 48),
      const SizedBox(width: AppSpacing.md),
      Expanded(
        child: Text(
          session.movementName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      _SummaryText(session.difficulty),
      const SizedBox(width: AppSpacing.md),
      _SummaryText(_historyDate(session.createdAt)),
      const SizedBox(width: AppSpacing.md),
      _SummaryText(formatTrainingDuration(session.durationSeconds)),
      const SizedBox(width: AppSpacing.md),
      SizedBox(
        width: 150,
        child: Text(
          result,
          textAlign: TextAlign.right,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.caption.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(width: AppSpacing.sm),
      _Disclosure(expanded: expanded),
    ],
  );
}

class _NarrowSummary extends StatelessWidget {
  const _NarrowSummary({
    required this.session,
    required this.result,
    required this.expanded,
  });
  final PublicProfileSession session;
  final String result;
  final bool expanded;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MovementImage(movementName: session.movementName, size: 42),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              session.movementName,
              style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 3),
            Text(
              '${session.difficulty} · ${_historyDate(session.createdAt)} · ${formatTrainingDuration(session.durationSeconds)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              result,
              style: AppTheme.caption.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
      _Disclosure(expanded: expanded),
    ],
  );
}

class _SummaryText extends StatelessWidget {
  const _SummaryText(this.value);
  final String value;
  @override
  Widget build(BuildContext context) => Text(
    value,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
  );
}

class _Disclosure extends StatelessWidget {
  const _Disclosure({required this.expanded});
  final bool expanded;
  @override
  Widget build(BuildContext context) => AnimatedRotation(
    turns: expanded ? .5 : 0,
    duration: const Duration(milliseconds: 200),
    child: Icon(
      FluentIcons.chevron_down,
      size: 12,
      color: context.elixTextSecondary,
    ),
  );
}

class _TeacherHistoryDetails extends StatelessWidget {
  const _TeacherHistoryDetails({
    required this.controller,
    required this.session,
  });
  final TeacherStudentDetailController controller;
  final PublicProfileSession session;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Session details',
          style: AppTheme.caption.copyWith(
            fontWeight: FontWeight.w700,
            color: context.elixTextSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Training prop: ${session.propType.displayLabel}',
          style: AppTheme.bodySecondary,
        ),
        const SizedBox(height: AppSpacing.sm),
        _AssessmentDetails(session: session),
        const SizedBox(height: AppSpacing.md),
        if (session.evidenceAvailable == true)
          _HistoryEvidence(controller: controller, session: session)
        else
          Text(
            'No confirmed movement image',
            style: AppTheme.bodySecondary.copyWith(
              color: context.elixTextSecondary,
            ),
          ),
      ],
    ),
  );
}

class _AssessmentDetails extends StatelessWidget {
  const _AssessmentDetails({required this.session});
  final PublicProfileSession session;
  @override
  Widget build(BuildContext context) {
    final rubric = session.rubric;
    if (!session.isRubricAssessed || rubric == null)
      return Text(
        session.legacyScore == null
            ? 'No score recorded'
            : 'Score: ${session.legacyScore}%',
        style: AppTheme.body.copyWith(fontWeight: FontWeight.w600),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Overall performance',
          style: AppTheme.caption.copyWith(
            color: context.elixTextSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          rubric.performanceLevel.label,
          style: AppTheme.body.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text('Score: ${rubric.total} out of 12', style: AppTheme.bodySecondary),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Skill breakdown',
          style: AppTheme.caption.copyWith(
            color: context.elixTextSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        for (final criterion in RubricCriterion.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${_teacherCriterionLabel(criterion)}: ${rubric.scoreFor(criterion)}/3',
              style: AppTheme.bodySecondary,
            ),
          ),
      ],
    );
  }
}

String _teacherCriterionLabel(RubricCriterion criterion) => switch (criterion) {
  RubricCriterion.technique => 'Technique',
  RubricCriterion.stability => 'Stability & control',
  RubricCriterion.completion => 'Completion',
  RubricCriterion.propPositioning => 'Prop positioning',
};

class _HistoryEvidence extends StatelessWidget {
  const _HistoryEvidence({required this.controller, required this.session});
  final TeacherStudentDetailController controller;
  final PublicProfileSession session;
  @override
  Widget build(BuildContext context) {
    final state = controller.evidenceStateFor(session.sessionId);
    final bytes = controller.evidenceFor(session.sessionId);
    if (state == TeacherEvidenceState.loading ||
        state == TeacherEvidenceState.idle)
      return const SizedBox(height: 80, child: Center(child: ProgressRing()));
    if (state == TeacherEvidenceState.loaded && bytes != null)
      return _EvidencePreview(session: session, bytes: bytes);
    return Row(
      children: [
        Expanded(
          child: Text(
            state == TeacherEvidenceState.unavailable
                ? 'Saved image is unavailable.'
                : 'Saved image could not be loaded.',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ),
        Button(
          onPressed: () => controller.retryEvidence(session),
          child: const Text('Retry'),
        ),
      ],
    );
  }
}

class _EvidencePreview extends StatelessWidget {
  const _EvidencePreview({required this.session, required this.bytes});
  final PublicProfileSession session;
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Confirmed movement image',
        style: AppTheme.caption.copyWith(
          fontWeight: FontWeight.w700,
          color: context.elixTextSecondary,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      LayoutBuilder(
        builder: (context, constraints) => SizedBox(
          width: constraints.maxWidth < 280 ? constraints.maxWidth : 280,
          height: 190,
          child: Button(
            key: Key('teacher_history_evidence_preview_${session.sessionId}'),
            onPressed: () => _showEvidence(context, session, bytes),
            style: ButtonStyle(
              padding: WidgetStateProperty.all(EdgeInsets.zero),
            ),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.diagonal3Values(-1, 1, 1),
                    child: Image.memory(bytes, fit: BoxFit.contain),
                  ),
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: Color(0x8C000000),
                      child: Padding(
                        padding: EdgeInsets.all(4),
                        child: Text(
                          'Click to enlarge',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 11),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

void _showEvidence(
  BuildContext context,
  PublicProfileSession session,
  Uint8List bytes,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => ContentDialog(
    title: Text('${session.movementName} · Saved image'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 520),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.diagonal3Values(-1, 1, 1),
        child: Image.memory(bytes, fit: BoxFit.contain),
      ),
    ),
    actions: [
      Button(
        onPressed: () => Navigator.of(dialogContext).pop(),
        child: const Text('Close'),
      ),
    ],
  ),
);
String _historyDate(String? value) {
  final parsed = value == null ? null : DateTime.tryParse(value);
  return parsed == null
      ? 'Date unavailable'
      : DateFormat('MMM d, y · h:mm a').format(parsed.toLocal());
}
