import 'package:elixr_application/data/models/session.dart';
import 'package:elixr_application/data/repositories/session_repository.dart';
import 'package:elixr_application/features/movements/movements_screen.dart';
import 'package:elixr_application/features/movements/widgets/movement_difficulty_section.dart';
import 'package:elixr_application/services/session_service.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _OfflineSessionRepository extends SessionRepository {
  @override
  Future<List<Session>> getSessionsForUser(String userId) =>
      Future<List<Session>>.error(StateError('offline'));
}

void main() {
  testWidgets(
    'remote session-stat failure does not block the movement catalog',
    (tester) async {
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SessionService>(
              create: (_) => SessionService(),
            ),
          ],
          child: FluentApp(
            home: MovementsScreen(
              sessionRepository: _OfflineSessionRepository(),
              userId: 'trainee-a',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MovementDifficultySection), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    },
  );
}
