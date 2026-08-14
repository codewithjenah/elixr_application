import 'package:elixr_core/elixr_core.dart';
import 'package:flutter/material.dart';
import 'coaching_notes_controller.dart';

class CoachingNotesSection extends StatelessWidget {
  const CoachingNotesSection({super.key, required this.controller});
  final TeacherCoachingNotesController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, child) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Coaching Notes',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Spacer(),
            if (controller.canAuthor)
              FilledButton.icon(
                onPressed: controller.saving ? null : () => _compose(context),
                icon: const Icon(Icons.add),
                label: const Text('Add note'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (controller.state == TeacherCoachingNotesState.loading)
          const Center(child: CircularProgressIndicator())
        else if (controller.state ==
            TeacherCoachingNotesState.relationshipRequired)
          const Text(
            'Coaching is unavailable because this relationship is no longer approved.',
          )
        else if (controller.state == TeacherCoachingNotesState.error)
          OutlinedButton(
            onPressed: controller.refresh,
            child: const Text('Retry'),
          )
        else if (controller.notes.isEmpty)
          const Text('No coaching notes yet.')
        else ...[
          for (final note in controller.notes)
            Card(
              child: ListTile(
                title: Text(note.movementName ?? 'General coaching'),
                subtitle: Text(note.body),
                trailing: controller.canAuthor
                    ? PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _compose(context, note);
                          } else {
                            _delete(context, note);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      )
                    : null,
              ),
            ),
          if (controller.paginationError != null)
            OutlinedButton(
              onPressed: controller.loadingMore ? null : controller.loadMore,
              child: const Text('Try loading again'),
            )
          else if (controller.hasMore)
            OutlinedButton(
              onPressed: controller.loadingMore ? null : controller.loadMore,
              child: Text(controller.loadingMore ? 'Loading…' : 'Load more'),
            ),
        ],
      ],
    ),
  );
  Future<void> _compose(BuildContext context, [CoachingNote? note]) async {
    final body = TextEditingController(text: note?.body);
    String? movement = note?.movementName;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.viewInsetsOf(sheet).bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String?>(
                initialValue: movement,
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('General / no movement'),
                  ),
                  ...coachingMovementNames.map(
                    (name) => DropdownMenuItem(value: name, child: Text(name)),
                  ),
                ],
                onChanged: (value) => setState(() => movement = value),
              ),
              TextField(
                controller: body,
                maxLength: CoachingNote.maximumBodyLength,
                minLines: 4,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Recommendation'),
              ),
              FilledButton(
                onPressed: controller.saving
                    ? null
                    : () async {
                        try {
                          if (note == null) {
                            await controller.create(body.text, movement);
                          } else {
                            await controller.update(note, body.text, movement);
                          }
                          if (sheet.mounted) Navigator.pop(sheet);
                        } on CoachingNoteException catch (error) {
                          if (sheet.mounted) {
                            ScaffoldMessenger.of(sheet).showSnackBar(
                              SnackBar(
                                content: Text(
                                  error.message ?? 'Could not save note.',
                                ),
                              ),
                            );
                          }
                        }
                      },
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    body.dispose();
  }

  Future<void> _delete(BuildContext context, CoachingNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete coaching note?'),
        content: Text(
          'This permanently removes this ${note.movementName ?? 'general'} note.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await controller.delete(note);
      } catch (_) {}
    }
  }
}
