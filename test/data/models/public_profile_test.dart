import 'package:elixr_application/data/models/public_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PublicProfile', () {
    test('defaults missing visibility to private', () {
      final profile = PublicProfile.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Alice',
      });
      expect(profile, isNotNull);
      expect(profile!.visibility, ProfileVisibility.private);
    });

    test('parses public visibility', () {
      final profile = PublicProfile.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Alice',
        'visibility': 'public',
      });
      expect(profile!.visibility, ProfileVisibility.public);
    });

    test('unknown visibility fails closed to private', () {
      final profile = PublicProfile.tryFromMap({
        'user_id': 'u1',
        'display_name': 'Alice',
        'visibility': 'hidden',
      });
      expect(profile!.visibility, ProfileVisibility.private);
    });
  });
}
