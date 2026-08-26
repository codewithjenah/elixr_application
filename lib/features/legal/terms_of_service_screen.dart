import 'package:elixr_core/legal/legal_documents.dart';
import 'package:elixr_core/privacy/privacy_consent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'widgets/legal_document_page.dart';

class TermsOfServiceScreen extends StatelessWidget {
  const TermsOfServiceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalDocumentPage(
      title: ElixrLegalDocuments.termsOfServiceTitle,
      subtitle: ElixrLegalDocuments.termsOfServiceSubtitle,
      sections: ElixrLegalDocuments.termsOfServiceSectionsFor(
        ElixrLegalClient.traineeWindows,
      ),
      lastUpdated: ElixrLegalDocuments.termsOfServiceLastUpdated,
      version: RegistrationLegalConsent.currentTermsOfServiceVersion,
    );
  }
}
