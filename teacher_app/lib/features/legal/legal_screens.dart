import 'package:elixr_core/legal/legal_documents.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/teacher_routes.dart';
import '../../core/theme/teacher_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalDocumentScreen(
      title: ElixrLegalDocuments.privacyPolicyTitle,
      subtitle: ElixrLegalDocuments.privacyPolicySubtitle,
      paragraphs: ElixrLegalDocuments.privacyPolicyParagraphs,
    );
  }
}

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _LegalDocumentScreen(
      title: ElixrLegalDocuments.termsOfServiceTitle,
      subtitle: ElixrLegalDocuments.termsOfServiceSubtitle,
      paragraphs: ElixrLegalDocuments.termsOfServiceParagraphs,
    );
  }
}

class _LegalDocumentScreen extends StatelessWidget {
  const _LegalDocumentScreen({
    required this.title,
    required this.subtitle,
    required this.paragraphs,
  });

  final String title;
  final String subtitle;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(TeacherRoutes.register);
            }
          },
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Text(
              subtitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: TeacherColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < paragraphs.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              Text(
                paragraphs[i],
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TeacherColors.textSecondary,
                  height: 1.45,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
