import 'package:elixr_core/legal/legal_documents.dart';
import 'package:elixr_core/privacy/privacy_consent.dart';
import 'package:fluent_ui/fluent_ui.dart';

import 'widgets/legal_document_page.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LegalDocumentPage(
      title: ElixrLegalDocuments.privacyPolicyTitle,
      subtitle: ElixrLegalDocuments.privacyPolicySubtitle,
      sections: ElixrLegalDocuments.privacyPolicySectionsFor(
        ElixrLegalClient.traineeWindows,
      ),
      lastUpdated: ElixrLegalDocuments.privacyPolicyLastUpdated,
      version: RegistrationLegalConsent.currentPrivacyPolicyVersion,
    );
  }
}
