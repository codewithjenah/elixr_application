import 'package:elixr_application/services/join_link_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('accepts only one normalized elixr join code and retains it', () {
    final service = JoinLinkService();
    addTearDown(service.dispose);
    expect(
      service.acceptUri(Uri.parse('elixr://join?code=7kpm-xr4d-q2wt')),
      isTrue,
    );
    expect(service.pendingCode, '7KPMXR4DQ2WT');
  });

  test(
    'rejects malformed schemes, hosts, extra params, and duplicate codes',
    () {
      final service = JoinLinkService();
      addTearDown(service.dispose);
      expect(
        service.acceptUri(Uri.parse('https://join?code=7KPMXR4DQ2WT')),
        isFalse,
      );
      expect(
        service.acceptUri(Uri.parse('elixr://other?code=7KPMXR4DQ2WT')),
        isFalse,
      );
      expect(
        service.acceptUri(
          Uri.parse('elixr://join?code=7KPMXR4DQ2WT&other=value'),
        ),
        isFalse,
      );
      expect(
        service.acceptUri(
          Uri.parse('elixr://join?code=7KPMXR4DQ2WT&code=ABCD2345EFGH'),
        ),
        isFalse,
      );
      expect(
        service.acceptUri(Uri.parse('elixr://join?code=7KPMXR4DQ2WT#extra')),
        isFalse,
      );
      expect(
        service.acceptUri(Uri.parse('elixr://user@join?code=7KPMXR4DQ2WT')),
        isFalse,
      );
      expect(
        service.acceptUri(Uri.parse('elixr://join:99?code=7KPMXR4DQ2WT')),
        isFalse,
      );
      expect(service.acceptUri(Uri.parse('elixr://join?code=short')), isFalse);
    },
  );
}
