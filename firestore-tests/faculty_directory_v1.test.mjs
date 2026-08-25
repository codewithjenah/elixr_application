import {readFileSync} from 'node:fs';
import {after, before, beforeEach, describe, test} from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  setDoc,
  where,
} from 'firebase/firestore';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-elixr',
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const admin = context.firestore();
    await setDoc(doc(admin, 'users', 'teacher'), {
      full_name: 'Grace Hopper',
      email: 'teacher@example.test',
      role: 'Teacher',
    });
    await setDoc(doc(admin, 'users', 'other-teacher'), {
      full_name: 'Ada Teacher',
      email: 'other-teacher@example.test',
      role: 'Teacher',
    });
    await setDoc(doc(admin, 'users', 'trainee'), {
      full_name: 'Ada Lovelace',
      email: 'trainee@example.test',
      role: 'Trainee',
    });
    await setDoc(doc(admin, 'chat_user_directory', 'teacher'), directoryRow({
      display_name: 'Grace Hopper',
      role: 'Teacher',
    }));
    await setDoc(doc(admin, 'chat_user_directory', 'other-teacher'), directoryRow({
      display_name: 'Ada Teacher',
      role: 'Teacher',
    }));
    await setDoc(doc(admin, 'chat_user_directory', 'trainee'), directoryRow({
      display_name: 'Ada Lovelace',
      role: 'Trainee',
    }));
  });
});

after(async () => testEnv.cleanup());

function directoryRow({display_name, role}) {
  return {
    display_name,
    role,
    search_prefixes: [display_name.split(' ')[0].toLowerCase()],
    lifecycle_state: 'active',
    schema_version: 1,
  };
}

function db(uid, {emailVerified = true} = {}) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.test`,
    email_verified: emailVerified,
  }).firestore();
}

describe('chat_user_directory faculty list', () => {
  test('verified Teacher can query Teacher rows', async () => {
    const snapshot = await assertSucceeds(getDocs(query(
      collection(db('teacher'), 'chat_user_directory'),
      where('role', '==', 'Teacher'),
    )));
    const ids = snapshot.docs.map((row) => row.id).sort();
    if (ids.join(',') !== 'other-teacher,teacher') {
      throw new Error(`unexpected Teacher ids: ${ids.join(',')}`);
    }
  });

  test('verified Teacher can get another Teacher directory row', async () => {
    await assertSucceeds(
      getDoc(doc(db('teacher'), 'chat_user_directory', 'other-teacher')),
    );
  });

  test('unfiltered list fails when a Trainee row exists', async () => {
    await assertFails(getDocs(collection(db('teacher'), 'chat_user_directory')));
  });

  test('verified Teacher cannot get a Trainee directory row', async () => {
    await assertFails(
      getDoc(doc(db('teacher'), 'chat_user_directory', 'trainee')),
    );
  });

  test('Trainee cannot list Teacher directory rows', async () => {
    await assertFails(getDocs(query(
      collection(db('trainee'), 'chat_user_directory'),
      where('role', '==', 'Teacher'),
    )));
  });

  test('unverified Teacher cannot list Teacher directory rows', async () => {
    await assertFails(getDocs(query(
      collection(db('teacher', {emailVerified: false}), 'chat_user_directory'),
      where('role', '==', 'Teacher'),
    )));
  });

  test('client writes to the directory fail', async () => {
    const teacher = db('teacher');
    await assertFails(setDoc(doc(teacher, 'chat_user_directory', 'spoof'), directoryRow({
      display_name: 'Spoof Teacher',
      role: 'Teacher',
    })));
    await assertFails(
      deleteDoc(doc(teacher, 'chat_user_directory', 'other-teacher')),
    );
  });
});
