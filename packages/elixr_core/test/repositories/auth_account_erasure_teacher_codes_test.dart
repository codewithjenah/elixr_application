import 'package:elixr_core/database/firestore_collections.dart';
import 'package:elixr_core/repositories/auth_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  Future<void> seed(String id, Map<String, dynamic> data) => firestore
      .collection(FirestoreCollections.teacherAccessCodes)
      .doc(id)
      .set(data);

  test('deletes only unused codes created by the erased Teacher', () async {
    await seed('OWN_UNUSED', {
      'consumed': false,
      'created_by': 'u1',
      'note': 'private note',
    });
    await seed('OTHER_UNUSED', {'consumed': false, 'created_by': 'u2'});

    await purgeTeacherAccessCodesForAccountErasure(
      firestore: firestore,
      uid: 'u1',
    );

    expect(
      (await firestore
              .collection(FirestoreCollections.teacherAccessCodes)
              .doc('OWN_UNUSED')
              .get())
          .exists,
      isFalse,
    );
    expect(
      (await firestore
              .collection(FirestoreCollections.teacherAccessCodes)
              .doc('OTHER_UNUSED')
              .get())
          .exists,
      isTrue,
    );
  });

  test('anonymizes consumed codes and is idempotent', () async {
    await seed('BOTH', {
      'consumed': true,
      'created_by': 'u1',
      'consumed_by': 'u1',
      'consumed_at': 'kept',
      'note': 'remove me',
    });
    await seed('CONSUMER', {
      'consumed': true,
      'created_by': 'u2',
      'consumed_by': 'u1',
      'consumed_at': 'kept',
      'note': 'creator note',
    });

    await purgeTeacherAccessCodesForAccountErasure(
      firestore: firestore,
      uid: 'u1',
    );
    await purgeTeacherAccessCodesForAccountErasure(
      firestore: firestore,
      uid: 'u1',
    );

    final both =
        (await firestore
                .collection(FirestoreCollections.teacherAccessCodes)
                .doc('BOTH')
                .get())
            .data()!;
    expect(both['consumed'], isTrue);
    expect(both['consumed_at'], 'kept');
    expect(both.containsKey('created_by'), isFalse);
    expect(both.containsKey('consumed_by'), isFalse);
    expect(both.containsKey('note'), isFalse);

    final consumer =
        (await firestore
                .collection(FirestoreCollections.teacherAccessCodes)
                .doc('CONSUMER')
                .get())
            .data()!;
    expect(consumer['created_by'], 'u2');
    expect(consumer['note'], 'creator note');
    expect(consumer.containsKey('consumed_by'), isFalse);
  });
}
