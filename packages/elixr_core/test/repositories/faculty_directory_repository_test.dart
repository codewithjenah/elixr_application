import 'package:elixr_core/elixr_core.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
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

  Map<String, dynamic> directoryMap({
    required String displayName,
    required String role,
    String? avatarUrl,
    String? lifecycleState = 'active',
  }) {
    return {
      'display_name': displayName,
      'role': role,
      'avatar_url': ?avatarUrl,
      'lifecycle_state': ?lifecycleState,
      'search_prefixes': [displayName.split(' ').first.toLowerCase()],
      'schema_version': 1,
    };
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

  group('FirebaseFacultyDirectoryRepository', () {
    late FakeFirebaseFirestore firestore;
    late FirebaseFacultyDirectoryRepository repository;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = FirebaseFacultyDirectoryRepository(firestore: firestore);
    });

    Future<void> seedDoc(String id, Map<String, dynamic> data) {
      return firestore
          .collection(FirestoreCollections.chatUserDirectory)
          .doc(id)
          .set(data);
    }

    test(
      'maps Teacher docs and skips malformed, Trainee, and inactive rows',
      () async {
        await seedDoc(
          'ada',
          directoryMap(displayName: 'Ada Teacher', role: User.roleTeacher),
        );
        await seedDoc(
          'sam',
          directoryMap(displayName: 'Sam Trainee', role: User.roleTrainee),
        );
        await seedDoc('bad', {'role': User.roleTeacher});
        await seedDoc(
          'gone',
          directoryMap(
            displayName: 'Gone Teacher',
            role: User.roleTeacher,
            lifecycleState: 'deleting',
          ),
        );
        await seedDoc(
          'no-lifecycle',
          directoryMap(
            displayName: 'Pat Teacher',
            role: User.roleTeacher,
            lifecycleState: null,
          ),
        );

        final users = await repository.watchTeachers().first;
        expect(users.map((user) => user.id).toSet(), {'ada', 'no-lifecycle'});
        expect(
          users.firstWhere((user) => user.id == 'ada').displayName,
          'Ada Teacher',
        );
      },
    );
  });
}
