import 'package:elixr_core/elixr_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChatUser teacher({
    required String id,
    required String name,
    String? avatarUrl,
  }) {
    return ChatUser(
      id: id,
      displayName: name,
      role: User.roleTeacher,
      avatarUrl: avatarUrl,
    );
  }

  group('InMemoryFacultyDirectoryRepository', () {
    late InMemoryFacultyDirectoryRepository repository;

    setUp(() {
      repository = InMemoryFacultyDirectoryRepository();
    });

    tearDown(() => repository.dispose());

    test(
      'watchTeachers maps seeded Teacher rows and skips invalid ones',
      () async {
        repository.seed(teacher(id: 'ada', name: 'Ada Teacher'));
        repository.seed(
          const ChatUser(
            id: 'sam',
            displayName: 'Sam Trainee',
            role: User.roleTrainee,
          ),
        );
        repository.seed(
          teacher(id: 'gone', name: 'Gone Teacher'),
          lifecycleState: 'deleting',
        );

        final first = await repository.watchTeachers().first;
        expect(first.map((user) => user.id), ['ada']);
        expect(first.single.displayName, 'Ada Teacher');
      },
    );

    test('watchTeachers emits updates after seed', () async {
      final events = <List<String>>[];
      final sub = repository.watchTeachers().listen(
        (users) => events.add(users.map((user) => user.id).toList()),
      );
      addTearDown(sub.cancel);

      await Future<void>.delayed(Duration.zero);
      repository.seed(teacher(id: 'ada', name: 'Ada Teacher'));
      await Future<void>.delayed(Duration.zero);

      expect(events, [
        <String>[],
        ['ada'],
      ]);
    });
  });
}
