import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/teacher_theme.dart';
import '../../core/widgets/teacher_auth_widgets.dart';
import '../auth/teacher_auth_controller.dart';

class RosterScreen extends StatelessWidget {
  const RosterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<TeacherAuthController>();
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roster'),
        actions: [
          IconButton(
            tooltip: 'Logout',
            onPressed: auth.isBusy ? null : auth.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const TeacherBrandMark(),
              const SizedBox(height: 28),
              if (user != null) ...[
                Text(
                  user.fullName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TeacherColors.textSecondary,
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('roster_logout'),
                    onPressed: auth.isBusy ? null : auth.signOut,
                    child: const Text('Logout'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.groups_outlined,
                          size: 48,
                          color: TeacherColors.primarySoft.withValues(
                            alpha: 0.8,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No students linked yet',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Trainees can be linked to your roster in a later update. Nothing is listed here until then.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: TeacherColors.textSecondary,
                                height: 1.4,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
