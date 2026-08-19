import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import 'teacher_student_detail_controller.dart';

class TeacherStudentCoachingSection extends StatefulWidget {
  const TeacherStudentCoachingSection({
    super.key,
    required this.controller,
    required this.teacherDisplayName,
  });

  final TeacherStudentDetailController controller;
  final String teacherDisplayName;

  @override
  State<TeacherStudentCoachingSection> createState() =>
      _TeacherStudentCoachingSectionState();
}

class _TeacherStudentCoachingSectionState
    extends State<TeacherStudentCoachingSection> {
  final List<CoachingNote> _notes = [];
  bool _loading = true;
  String? _error;
  bool _busy = false;
  CoachingNoteCursor? _cursor;
  bool _hasMore = false;
  String? _loadedGroupId;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _loadedGroupId = widget.controller.selectedGroupId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load(initial: true);
    });
  }

  @override
  void didUpdateWidget(TeacherStudentCoachingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _loadedGroupId = widget.controller.selectedGroupId;
      _cursor = null;
      _load(initial: true);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final nextGroupId = widget.controller.selectedGroupId;
    if (nextGroupId != _loadedGroupId) {
      _loadedGroupId = nextGroupId;
      _cursor = null;
      _load(initial: true);
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _load({bool initial = false, bool more = false}) async {
    if (more && _busy) return;
    final groupId = widget.controller.selectedGroupId;
    final generation = initial ? ++_loadGeneration : _loadGeneration;
    if (groupId == null) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _notes.clear();
        _cursor = null;
        _hasMore = false;
        _loading = false;
        _error = null;
        _busy = false;
      });
      return;
    }
    _busy = true;
    if (initial) {
      _loading = true;
      _error = null;
    }
    setState(() {});
    try {
      final repository = context.read<CoachingNoteRepository>();
      final page = await repository.fetchForTeacher(
        teacherId: widget.controller.teacherId,
        traineeId: widget.controller.traineeId,
        groupId: groupId,
        startAfter: more ? _cursor : null,
      );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        if (more) {
          _notes.addAll(page.notes);
        } else {
          _notes
            ..clear()
            ..addAll(page.notes);
        }
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = 'Could not load coaching notes.';
        _loading = false;
      });
    } finally {
      if (generation == _loadGeneration) {
        _busy = false;
      }
    }
  }

  Future<void> _showComposer({CoachingNote? existing}) async {
    final groupId = widget.controller.selectedGroupId;
    if (groupId == null) return;
    final bodyController = TextEditingController(text: existing?.body ?? '');
    String? movement = existing?.movementName;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: Text(existing == null ? 'New coaching note' : 'Edit note'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ComboBox<String?>(
              value: movement,
              placeholder: const Text('Movement (optional)'),
              items: [
                const ComboBoxItem(value: null, child: Text('No movement')),
                for (final name in coachingMovementNames)
                  ComboBoxItem(value: name, child: Text(name)),
              ],
              onChanged: (value) => movement = value,
            ),
            const SizedBox(height: AppSpacing.md),
            TextBox(
              controller: bodyController,
              placeholder: 'Recommendation',
              maxLines: 6,
            ),
          ],
        ),
        actions: [
          Button(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            child: const Text('Save'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    final repository = context.read<CoachingNoteRepository>();
    try {
      if (existing == null) {
        await repository.createNote(
          teacherId: widget.controller.teacherId,
          traineeId: widget.controller.traineeId,
          body: bodyController.text,
          movementName: movement,
          groupId: groupId,
        );
      } else {
        await repository.updateNote(
          noteId: existing.id,
          teacherId: widget.controller.teacherId,
          traineeId: widget.controller.traineeId,
          body: bodyController.text,
          movementName: movement,
        );
      }
      await _load(initial: true);
    } catch (_) {
      if (!mounted) return;
      await displayInfoBar(
        context,
        builder: (context, close) => InfoBar(
          title: const Text('Could not save note'),
          severity: InfoBarSeverity.error,
          onClose: close,
        ),
      );
    }
  }

  Future<void> _deleteNote(CoachingNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('Delete note?'),
        content: const Text('This cannot be undone.'),
        actions: [
          Button(
            child: const Text('Cancel'),
            onPressed: () => Navigator.pop(context, false),
          ),
          FilledButton(
            child: const Text('Delete'),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<CoachingNoteRepository>().deleteNote(
      noteId: note.id,
      teacherId: widget.controller.teacherId,
      traineeId: widget.controller.traineeId,
    );
    await _load(initial: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.hasClassroomAuthorization) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Coaching', style: AppTheme.headingMedium),
            const Spacer(),
            if (widget.controller.approvedMemberships.length > 1)
              ComboBox<String>(
                value: widget.controller.selectedGroupId,
                items: [
                  for (final membership
                      in widget.controller.approvedMemberships)
                    ComboBoxItem(
                      value: membership.groupId,
                      child: Text(
                        widget.controller.displayNameForGroupId(
                          membership.groupId,
                        ),
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    widget.controller.setSelectedGroupId(value);
                  }
                },
              ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: _busy ? null : () => _showComposer(),
              child: const Text('Add note'),
            ),
          ],
        ),
        if (widget.controller.classroomGroupCaption != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.controller.classroomGroupCaption!,
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (_loading)
          Text(
            'Loading coaching notes…',
            style: AppTheme.body.copyWith(color: context.elixTextSecondary),
          )
        else if (_error != null)
          Text(_error!, style: AppTheme.body)
        else if (_notes.isEmpty)
          Text(
            'No coaching notes yet.',
            style: AppTheme.body.copyWith(color: context.elixTextSecondary),
          )
        else
          ..._notes.map(
            (note) => _NoteCard(
              note: note,
              onEdit: () => _showComposer(existing: note),
              onDelete: () => _deleteNote(note),
            ),
          ),
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Button(
              onPressed: _busy ? null : () => _load(more: true),
              child: const Text('Load more'),
            ),
          ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.onEdit,
    required this.onDelete,
  });

  final CoachingNote note;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat.yMMMd().add_jm();
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: context.elixCardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.elixBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatter.format(note.createdAt.toLocal()),
                  style: AppTheme.caption.copyWith(
                    color: context.elixTextSecondary,
                  ),
                ),
              ),
              Button(onPressed: onEdit, child: const Text('Edit')),
              const SizedBox(width: AppSpacing.xs),
              Button(onPressed: onDelete, child: const Text('Delete')),
            ],
          ),
          if (note.movementName != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(note.movementName!, style: AppTheme.caption),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(note.body, style: AppTheme.body),
        ],
      ),
    );
  }
}
