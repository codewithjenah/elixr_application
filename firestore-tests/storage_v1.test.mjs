import { readFileSync } from 'node:fs';
import { before, beforeEach, after, describe, test } from 'node:test';

import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, Timestamp } from 'firebase/firestore';
import { deleteObject, getBytes, ref, updateMetadata, uploadBytes } from 'firebase/storage';

const PROJECT_ID = 'demo-elixr';
const GROUP_ID = 'group-1';
const ASG = 'asgCustom';
const ATTEMPT = 'review_sub_clip1';
const PATH =
  `assignment_submissions/teacher/${GROUP_ID}/${ASG}/trainee/${ATTEMPT}.mp4`;

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
});

after(async () => {
  await testEnv.cleanup();
});

function context(uid, { emailVerified = true } = {}) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: emailVerified,
  });
}

function metadata(overrides = {}) {
  return {
    contentType: 'video/mp4',
    customMetadata: {
      teacher_id: 'teacher',
      group_id: GROUP_ID,
      assignment_id: ASG,
      trainee_id: 'trainee',
      attempt_id: ATTEMPT,
      movement_id: 'tm1',
      revision_id: 'rev1',
      ...overrides,
    },
  };
}

async function seedClassroom({
  membership = 'approved',
  attemptStatus = 'draft',
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    await setDoc(doc(db, 'users', 'teacher'), {
      full_name: 'Grace Hopper',
      role: 'Teacher',
    });
    await setDoc(doc(db, 'users', 'trainee'), {
      full_name: 'Ada Lovelace',
      role: 'Trainee',
    });
    await setDoc(doc(db, 'users', 'other'), {
      full_name: 'Other Teacher',
      role: 'Teacher',
    });
    await setDoc(doc(db, 'users', 'otherTrainee'), {
      full_name: 'Other Trainee',
      role: 'Trainee',
    });
    await setDoc(doc(db, 'groups', GROUP_ID), {
      teacher_id: 'teacher',
      name: 'BSHM 4A',
      status: 'active',
      schema_version: 1,
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    await setDoc(doc(db, 'group_memberships', `${GROUP_ID}_trainee`), {
      group_id: GROUP_ID,
      teacher_id: 'teacher',
      trainee_id: 'trainee',
      teacher_display_name: 'Grace Hopper',
      trainee_display_name: 'Ada Lovelace',
      status: membership,
      invite_id: '7KPMXR4DQ2WT',
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    await setDoc(doc(db, 'group_assignments', ASG), {
      teacher_id: 'teacher',
      group_id: GROUP_ID,
      movement_id: 'tm1',
      revision_id: 'rev1',
      origin: 'teacher_created',
      assessment_mode: 'teacher_reviewed',
      status: 'active',
      display_title: 'Tin Balance',
      teacher_display_name: 'Grace Hopper',
      group_name: 'BSHM 4A',
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    await setDoc(doc(db, 'assignment_attempts', ATTEMPT), {
      trainee_id: 'trainee',
      teacher_id: 'teacher',
      group_id: GROUP_ID,
      assignment_id: ASG,
      movement_id: 'tm1',
      revision_id: 'rev1',
      origin: 'teacher_created',
      assessment_mode: 'teacher_reviewed',
      attempt_kind: 'teacher_review_submission',
      status: attemptStatus,
      awards_global_xp: false,
      created_at: Timestamp.now(),
    });
  });
}

describe('assignment_submissions Storage', () => {
  test('approved Trainee creates matching <=15MiB video/mp4', async () => {
    await seedClassroom();
    const storage = context('trainee').storage();
    await assertSucceeds(
      uploadBytes(ref(storage, PATH), new Uint8Array(64), metadata()),
    );
  });

  test('over 15MiB denied', async () => {
    await seedClassroom();
    const storage = context('trainee').storage();
    await assertFails(
      uploadBytes(
        ref(storage, PATH),
        new Uint8Array(15 * 1024 * 1024 + 1),
        metadata(),
      ),
    );
  });

  test('wrong MIME denied', async () => {
    await seedClassroom();
    const storage = context('trainee').storage();
    await assertFails(
      uploadBytes(ref(storage, PATH), new Uint8Array(64), {
        ...metadata(),
        contentType: 'image/jpeg',
      }),
    );
  });

  test('wrong path identity denied', async () => {
    await seedClassroom();
    const storage = context('trainee').storage();
    await assertFails(
      uploadBytes(
        ref(
          storage,
          `assignment_submissions/other/${GROUP_ID}/${ASG}/trainee/${ATTEMPT}.mp4`,
        ),
        new Uint8Array(64),
        metadata(),
      ),
    );
  });

  test('forged metadata denied', async () => {
    await seedClassroom();
    const storage = context('trainee').storage();
    await assertFails(
      uploadBytes(
        ref(storage, PATH),
        new Uint8Array(64),
        metadata({ teacher_id: 'other' }),
      ),
    );
  });

  test('no current approved membership denies NEW upload', async () => {
    await seedClassroom({ membership: 'removed' });
    const storage = context('trainee').storage();
    await assertFails(
      uploadBytes(ref(storage, PATH), new Uint8Array(64), metadata()),
    );
  });

  test('assigning Teacher reads submitted/historical object without membership', async () => {
    await seedClassroom();
    await assertSucceeds(
      uploadBytes(
        ref(context('trainee').storage(), PATH),
        new Uint8Array(64),
        metadata(),
      ),
    );
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'group_memberships', `${GROUP_ID}_trainee`), {
        group_id: GROUP_ID,
        teacher_id: 'teacher',
        trainee_id: 'trainee',
        teacher_display_name: 'Grace Hopper',
        trainee_display_name: 'Ada Lovelace',
        status: 'removed',
        invite_id: '7KPMXR4DQ2WT',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
      await setDoc(doc(admin.firestore(), 'public_profiles', 'trainee'), {
        visibility: 'private',
        updated_at: Timestamp.now(),
      });
    });
    await assertSucceeds(getBytes(ref(context('teacher').storage(), PATH)));
  });

  test('Teacher without General Evidence Access still reads assignment video', async () => {
    await seedClassroom();
    await assertSucceeds(
      uploadBytes(
        ref(context('trainee').storage(), PATH),
        new Uint8Array(64),
        metadata(),
      ),
    );
    await assertSucceeds(getBytes(ref(context('teacher').storage(), PATH)));
    await assertSucceeds(
      uploadBytes(
        ref(context('trainee').storage(), 'users/trainee/session_evidence/session-1.jpg'),
        new Uint8Array(1024),
        { contentType: 'image/jpeg' },
      ),
    );
    await assertFails(
      getBytes(
        ref(context('teacher').storage(), 'users/trainee/session_evidence/session-1.jpg'),
      ),
    );
  });

  test('unrelated Teacher and other Trainee denied', async () => {
    await seedClassroom();
    await assertSucceeds(
      uploadBytes(
        ref(context('trainee').storage(), PATH),
        new Uint8Array(64),
        metadata(),
      ),
    );
    await assertFails(getBytes(ref(context('other').storage(), PATH)));
    await assertFails(getBytes(ref(context('otherTrainee').storage(), PATH)));
  });

  test('General Evidence Access alone does not grant submission read', async () => {
    await seedClassroom();
    await assertSucceeds(
      uploadBytes(
        ref(context('trainee').storage(), PATH),
        new Uint8Array(64),
        metadata(),
      ),
    );
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'teacher_student_links', 'other_trainee'), {
        teacher_id: 'other',
        trainee_id: 'trainee',
        status: 'approved',
        progress_access: 'granted',
        progress_access_version: 1,
        progress_access_granted_at: Timestamp.now(),
        evidence_access: 'granted',
        evidence_access_version: 1,
        evidence_access_granted_at: Timestamp.now(),
        request_version: 2,
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });
    await assertFails(getBytes(ref(context('other').storage(), PATH)));
  });

  test('Trainee owner and assigning Teacher can delete; unrelated cannot', async () => {
    await seedClassroom();
    await assertSucceeds(
      uploadBytes(
        ref(context('trainee').storage(), PATH),
        new Uint8Array(64),
        metadata(),
      ),
    );
    await assertFails(deleteObject(ref(context('other').storage(), PATH)));
    await assertSucceeds(deleteObject(ref(context('trainee').storage(), PATH)));
    await assertSucceeds(
      uploadBytes(
        ref(context('trainee').storage(), PATH),
        new Uint8Array(64),
        metadata(),
      ),
    );
    await assertSucceeds(deleteObject(ref(context('teacher').storage(), PATH)));
  });

  test('object update is denied', async () => {
    await seedClassroom();
    const storage = context('trainee').storage();
    await assertSucceeds(
      uploadBytes(ref(storage, PATH), new Uint8Array(64), metadata()),
    );
    // Byte overwrite is treated as create by the Storage emulator. Metadata
    // update is the real `update` operation and must stay denied.
    await assertFails(
      updateMetadata(ref(storage, PATH), { contentType: 'video/mp4' }),
    );
  });
});
