import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../services/auth_service.dart';
import 'coaching_notes_controller.dart';

class CoachingNotesScreen extends StatefulWidget {
  const CoachingNotesScreen({super.key});
  @override
  State<CoachingNotesScreen> createState() => _CoachingNotesScreenState();
}

class _CoachingNotesScreenState extends State<CoachingNotesScreen> {
  CoachingNotesController? _controller;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= CoachingNotesController(
      repository: context.read<CoachingNoteRepository>(),
      traineeId: null,
    );
    _controller!.start(context.watch<AuthService>().currentUser?.id);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) => ElixScaffoldPage(
        content: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Coaching', style: AppTheme.headingLarge),
                        const Spacer(),
                        Button(
                          onPressed:
                              controller.state == CoachingNotesState.loading
                              ? null
                              : controller.refresh,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Instructional notes from approved Teachers.',
                      style: AppTheme.bodySecondary.copyWith(
                        color: context.elixTextSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(child: _content(controller)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(CoachingNotesController c) {
    if (c.state == CoachingNotesState.loading)
      return const Center(child: ProgressRing());
    if (c.state == CoachingNotesState.error)
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Could not load coaching notes.'),
            const SizedBox(height: 12),
            Button(onPressed: c.refresh, child: const Text('Retry')),
          ],
        ),
      );
    if (c.state == CoachingNotesState.empty)
      return const Center(child: Text('No coaching notes yet.'));
    return ListView(
      children: [
        for (final note in c.notes) _noteCard(note),
        if (c.paginationError != null)
          Button(
            onPressed: c.retryLoadMore,
            child: const Text('Try loading again'),
          )
        else if (c.hasMore)
          Button(
            onPressed: c.loadingMore ? null : c.loadMore,
            child: Text(c.loadingMore ? 'Loading…' : 'Load more'),
          ),
      ],
    );
  }

  Widget _noteCard(CoachingNote note) {
    final format = DateFormat.yMMMd().add_jm();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.teacherDisplayName,
                    style: AppTheme.headingMedium,
                  ),
                ),
                if (note.movementName != null)
                  InfoLabel(
                    label: note.movementName!,
                    child: const SizedBox.shrink(),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SelectableText(note.body, style: AppTheme.body),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Sent ${format.format(note.createdAt.toLocal())}${note.isEdited ? ' • Edited ${format.format(note.updatedAt.toLocal())}' : ''}',
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
