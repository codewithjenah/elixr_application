import { readFileSync } from 'node:fs';
import { before, beforeEach, after, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  collection,
  deleteField,
  doc,
  getDoc,
  getDocs,
  query,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

const PROJECT_ID = 'demo-elixr';
const CODE = '7KPMXR4DQ2WT';
const LINK_ID = 'teacher_trainee';
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

async function seedUsers() {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'users', 'teacher'), {
      full_name: 'Grace Hopper',
      role: 'Teacher',
    });
    await setDoc(doc(admin.firestore(), 'users', 'trainee'), {
      full_name: 'Ada Lovelace',
      role: 'Trainee',
      session_evidence_enabled: true,
    });
    await setDoc(doc(admin.firestore(), 'users', 'other'), {
      full_name: 'Other Teacher',
      role: 'Teacher',
    });
  });
}

async function createInvite() {
  const teacher = context('teacher').firestore();
  const batch = writeBatch(teacher);
  batch.set(doc(teacher, 'teacher_invites', CODE), {
    teacher_id: 'teacher',
    teacher_display_name: 'Grace Hopper',
    created_at: serverTimestamp(),
  });
  batch.update(doc(teacher, 'users', 'teacher'), {
    teacher_roster_invite_code: CODE,
  });
  await assertSucceeds(batch.commit());
}

function v2Request() {
  return {
    teacher_id: 'teacher',
    trainee_id: 'trainee',
    teacher_display_name: 'Grace Hopper',
    trainee_display_name: 'Ada Lovelace',
    status: 'pending',
    invite_id: CODE,
    request_version: 2,
    created_at: serverTimestamp(),
    updated_at: serverTimestamp(),
    progress_access: 'none',
  };
}

async function createRequest() {
  const trainee = context('trainee').firestore();
  await assertSucceeds(
    setDoc(doc(trainee, 'teacher_student_links', LINK_ID), v2Request()),
  );
}

async function seedApproved({ progress = false, evidence = false } = {}) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'teacher_student_links', LINK_ID), {
      teacher_id: 'teacher',
      trainee_id: 'trainee',
      teacher_display_name: 'Grace Hopper',
      trainee_display_name: 'Ada Lovelace',
      status: 'approved',
      invite_id: CODE,
      request_version: 2,
      created_at: new Date(),
      updated_at: new Date(),
      progress_access: progress ? 'granted' : 'none',
      ...(progress ? {
        progress_access_version: 1,
        progress_access_granted_at: new Date(),
      } : {}),
      ...(evidence ? {
        evidence_access: 'granted',
        evidence_access_version: 1,
        evidence_access_granted_at: new Date(),
      } : {}),
    });
  });
}

describe('Teacher-owned roster V2', () => {
  test('exact invite get works while listing and forged ownership fail', async () => {
    await seedUsers();
    await createInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(getDoc(doc(trainee, 'teacher_invites', CODE)));
    await assertFails(getDocs(collection(trainee, 'teacher_invites')));
    const other = context('other').firestore();
    await assertFails(setDoc(doc(other, 'teacher_invites', 'ABCD2345EFGH'), {
      teacher_id: 'teacher',
      teacher_display_name: 'Grace Hopper',
      created_at: serverTimestamp(),
    }));
    const traineeBatch = writeBatch(trainee);
    traineeBatch.set(doc(trainee, 'teacher_invites', 'ABCD2345EFGH'), {
      teacher_id: 'trainee',
      teacher_display_name: 'Ada Lovelace',
      created_at: serverTimestamp(),
    });
    traineeBatch.update(doc(trainee, 'users', 'trainee'), {
      teacher_roster_invite_code: 'ABCD2345EFGH',
    });
    await assertFails(traineeBatch.commit());
  });

  test('only Trainee creates a V2 request from the exact live Teacher code', async () => {
    await seedUsers();
    await createInvite();
    await createRequest();
    const trainee = context('trainee').firestore();
    const saved = await getDoc(doc(trainee, 'teacher_student_links', LINK_ID));
    assert.equal(saved.data().request_version, 2);
    await assertFails(setDoc(doc(context('teacher').firestore(), 'teacher_student_links', LINK_ID), v2Request()));
    await assertFails(setDoc(doc(trainee, 'teacher_student_links', 'other_trainee'), {
      ...v2Request(),
      teacher_id: 'other',
      teacher_display_name: 'Other Teacher',
      invite_id: 'ABCD2345EFGH',
    }));
    await assertFails(updateDoc(
      doc(trainee, 'teacher_student_links', LINK_ID),
      { updated_at: serverTimestamp() },
    ));
  });

  test('a stale invite document is not a live roster code', async () => {
    await seedUsers();
    await createInvite();
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'teacher_invites', 'ABCD2345EFGH'), {
        teacher_id: 'teacher',
        teacher_display_name: 'Grace Hopper',
        created_at: new Date(),
      });
    });
    await assertFails(setDoc(
      doc(context('trainee').firestore(), 'teacher_student_links', LINK_ID),
      { ...v2Request(), invite_id: 'ABCD2345EFGH' },
    ));
  });

  test('only a valid V2 request may supersede a deterministic legacy row', async () => {
    await seedUsers();
    await createInvite();
    const createdAt = new Date('2025-01-01T00:00:00Z');
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'teacher_student_links', LINK_ID), {
        teacher_id: 'teacher',
        trainee_id: 'trainee',
        teacher_display_name: 'Old Teacher',
        trainee_display_name: 'Old Trainee',
        status: 'pending',
        invite_id: CODE,
        created_at: createdAt,
        updated_at: createdAt,
      });
    });
    const traineeLink = doc(
      context('trainee').firestore(),
      'teacher_student_links',
      LINK_ID,
    );
    await assertFails(updateDoc(traineeLink, {
      ...v2Request(),
      trainee_id: 'other',
      created_at: createdAt,
    }));
    await assertSucceeds(updateDoc(traineeLink, {
      ...v2Request(),
      created_at: createdAt,
    }));
  });

  test('Teacher decides pending request and Trainee owns cancel/revoke', async () => {
    await seedUsers();
    await createInvite();
    await createRequest();
    const link = doc(context('teacher').firestore(), 'teacher_student_links', LINK_ID);
    await assertSucceeds(updateDoc(link, {
      status: 'approved',
      updated_at: serverTimestamp(),
    }));
    await assertFails(updateDoc(doc(context('other').firestore(), 'teacher_student_links', LINK_ID), {
      status: 'rejected',
      updated_at: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(doc(context('trainee').firestore(), 'teacher_student_links', LINK_ID), {
      status: 'revoked',
      updated_at: serverTimestamp(),
    }));
  });

  test('progress withdrawal clears evidence in the same update', async () => {
    await seedUsers();
    await seedApproved({ progress: true, evidence: true });
    const link = doc(context('trainee').firestore(), 'teacher_student_links', LINK_ID);
    await assertFails(updateDoc(link, {
      progress_access: 'none',
      progress_access_version: deleteField(),
      progress_access_granted_at: deleteField(),
      updated_at: serverTimestamp(),
    }));
    await assertSucceeds(updateDoc(link, {
      progress_access: 'none',
      progress_access_version: deleteField(),
      progress_access_granted_at: deleteField(),
      evidence_access: deleteField(),
      evidence_access_version: deleteField(),
      evidence_access_granted_at: deleteField(),
      updated_at: serverTimestamp(),
    }));
  });

  test('participant-scoped list queries work; broad and unrelated queries fail', async () => {
    await seedUsers();
    await seedApproved();
    const teacher = context('teacher').firestore();
    await assertSucceeds(getDocs(query(
      collection(teacher, 'teacher_student_links'),
      where('teacher_id', '==', 'teacher'),
    )));
    await assertFails(getDocs(collection(teacher, 'teacher_student_links')));
    await assertFails(getDoc(doc(context('other').firestore(), 'teacher_student_links', LINK_ID)));
  });
});

describe('unverified Trainee roster join (Windows auth parity)', () => {
  test('unverified Trainee submits valid pending teacher_student_link', async () => {
    await seedUsers();
    await createInvite();
    const trainee = context('trainee', { emailVerified: false }).firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'teacher_student_links', LINK_ID), v2Request()),
    );
  });

  test('unverified Teacher cannot create or rotate roster invite', async () => {
    await seedUsers();
    const unverifiedTeacher = context('teacher', { emailVerified: false }).firestore();
    const batch = writeBatch(unverifiedTeacher);
    batch.set(doc(unverifiedTeacher, 'teacher_invites', CODE), {
      teacher_id: 'teacher',
      teacher_display_name: 'Grace Hopper',
      created_at: serverTimestamp(),
    });
    batch.update(doc(unverifiedTeacher, 'users', 'teacher'), {
      teacher_roster_invite_code: CODE,
    });
    await assertFails(batch.commit());
    await createInvite();
    const rotateBatch = writeBatch(unverifiedTeacher);
    rotateBatch.set(doc(unverifiedTeacher, 'teacher_invites', 'ABCD2345EFGH'), {
      teacher_id: 'teacher',
      teacher_display_name: 'Grace Hopper',
      created_at: serverTimestamp(),
    });
    rotateBatch.update(doc(unverifiedTeacher, 'users', 'teacher'), {
      teacher_roster_invite_code: 'ABCD2345EFGH',
    });
    await assertFails(rotateBatch.commit());
  });
});

describe('unverified Teacher roster decisions (rules boundary)', () => {
  async function seedPendingLink({ traineeVerified = false } = {}) {
    await seedUsers();
    await createInvite();
    const trainee = context('trainee', { emailVerified: traineeVerified }).firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'teacher_student_links', LINK_ID), v2Request()),
    );
  }

  test('verified owning Teacher can approve unverified Trainee pending link', async () => {
    await seedPendingLink({ traineeVerified: false });
    await assertSucceeds(
      updateDoc(doc(context('teacher').firestore(), 'teacher_student_links', LINK_ID), {
        status: 'approved',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('verified owning Teacher can reject unverified Trainee pending link', async () => {
    await seedPendingLink({ traineeVerified: false });
    await assertSucceeds(
      updateDoc(doc(context('teacher').firestore(), 'teacher_student_links', LINK_ID), {
        status: 'rejected',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('unverified owning Teacher cannot approve pending link', async () => {
    await seedPendingLink();
    const unverifiedTeacher = context('teacher', { emailVerified: false }).firestore();
    await assertFails(
      updateDoc(doc(unverifiedTeacher, 'teacher_student_links', LINK_ID), {
        status: 'approved',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('unverified owning Teacher cannot reject pending link', async () => {
    await seedPendingLink();
    const unverifiedTeacher = context('teacher', { emailVerified: false }).firestore();
    await assertFails(
      updateDoc(doc(unverifiedTeacher, 'teacher_student_links', LINK_ID), {
        status: 'rejected',
        updated_at: serverTimestamp(),
      }),
    );
  });
});

describe('per-Teacher evidence Storage access', () => {
  test('only owner or fully authorized Teacher reads the bounded JPEG path', async () => {
    await seedUsers();
    const ownerStorage = context('trainee').storage();
    const imageRef = ref(
      ownerStorage,
      'users/trainee/session_evidence/session-1.jpg',
    );
    await assertSucceeds(uploadBytes(
      imageRef,
      new Uint8Array(1024),
      { contentType: 'image/jpeg' },
    ));
    await assertSucceeds(getBytes(imageRef));

    const teacherImage = ref(
      context('teacher').storage(),
      'users/trainee/session_evidence/session-1.jpg',
    );
    await assertFails(getBytes(teacherImage));
    await seedApproved({ progress: true, evidence: true });
    await assertSucceeds(getBytes(teacherImage));

    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await updateDoc(doc(admin.firestore(), 'teacher_student_links', LINK_ID), {
        progress_access: 'none',
        progress_access_version: deleteField(),
        progress_access_granted_at: deleteField(),
        evidence_access: deleteField(),
        evidence_access_version: deleteField(),
        evidence_access_granted_at: deleteField(),
      });
    });
    await assertFails(getBytes(teacherImage));
  });

  test('legacy Teacher evidence read is denied when image saving is disabled', async () => {
    await seedUsers();
    const ownerStorage = context('trainee').storage();
    const imageRef = ref(
      ownerStorage,
      'users/trainee/session_evidence/session-1.jpg',
    );
    await assertSucceeds(uploadBytes(
      imageRef,
      new Uint8Array(1024),
      { contentType: 'image/jpeg' },
    ));
    await seedApproved({ progress: true, evidence: true });
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await updateDoc(doc(admin.firestore(), 'users', 'trainee'), {
        session_evidence_enabled: false,
      });
    });
    await assertFails(getBytes(
      ref(context('teacher').storage(), 'users/trainee/session_evidence/session-1.jpg'),
    ));
  });
});
