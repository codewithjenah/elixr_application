import { readFileSync } from 'node:fs';
import { before, beforeEach, after, describe, test } from 'node:test';

import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { deleteDoc, doc, getDoc, setDoc, Timestamp, updateDoc, serverTimestamp } from 'firebase/firestore';
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

async function seedTeacherActivityDemoAccess({membership = 'approved'} = {}) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    await setDoc(doc(db, 'classroom_teacher_access', 'teacher_trainee'), {
      teacher_id: 'teacher',
      trainee_id: 'trainee',
      group_id: GROUP_ID,
      schema_version: 1,
    });
    await setDoc(doc(db, 'group_memberships', `${GROUP_ID}_trainee`), {
      group_id: GROUP_ID,
      teacher_id: 'teacher',
      trainee_id: 'trainee',
      status: membership,
    });
  });
}

describe('Teacher Activity demonstration storage', () => {
  const demoPath = 'teacher_activity_demos/teacher/demo_1.mp4';
  const demoMetadata = {
    contentType: 'video/mp4',
    customMetadata: {owner_id: 'teacher'},
  };

  test('teacher owns writes and an approved current trainee may read', async () => {
    await seedTeacherActivityDemoAccess();
    const teacherStorage = context('teacher').storage();
    await assertSucceeds(
      uploadBytes(ref(teacherStorage, demoPath), new Uint8Array([1, 2, 3]), demoMetadata),
    );
    await assertSucceeds(getBytes(ref(context('trainee').storage(), demoPath)));
    await assertFails(getBytes(ref(context('otherTrainee').storage(), demoPath)));

    const assignmentDemoPath =
      `teacher_activity_demos/teacher/assignments/${ASG}/override_1.mp4`;
    await assertSucceeds(
      uploadBytes(
        ref(teacherStorage, assignmentDemoPath),
        new Uint8Array([1, 2, 3]),
        demoMetadata,
      ),
    );
    await assertSucceeds(
      getBytes(ref(context('trainee').storage(), assignmentDemoPath)),
    );
  });

  test('rejects foreign owners, non-MP4 content, and former trainees', async () => {
    await seedTeacherActivityDemoAccess({membership: 'removed'});
    const teacherStorage = context('teacher').storage();
    await assertFails(
      uploadBytes(ref(context('other').storage(), demoPath), new Uint8Array([1]), demoMetadata),
    );
    await assertFails(
      uploadBytes(ref(teacherStorage, demoPath), new Uint8Array([1]), {
        contentType: 'video/quicktime',
        customMetadata: {owner_id: 'teacher'},
      }),
    );
    await assertSucceeds(
      uploadBytes(ref(teacherStorage, demoPath), new Uint8Array([1]), demoMetadata),
    );
    await assertFails(getBytes(ref(context('trainee').storage(), demoPath)));
  });
});

async function seedClassroomEvidence({
  membership = 'approved',
  enabled = true,
  contextGroup = GROUP_ID,
} = {}) {
  await seedClassroom({ membership });
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    await setDoc(doc(db, 'users', 'trainee'), {
      session_evidence_enabled: enabled,
    }, { merge: true });
    await setDoc(doc(db, 'classroom_teacher_access', 'teacher_trainee'), {
      teacher_id: 'teacher',
      trainee_id: 'trainee',
      group_id: contextGroup,
      schema_version: 1,
      updated_at: Timestamp.now(),
    });
  });
}

async function uploadSavedImage() {
  await assertSucceeds(
    uploadBytes(
      ref(context('trainee').storage(), 'users/trainee/session_evidence/session-1.jpg'),
      new Uint8Array(1024),
      { contentType: 'image/jpeg' },
    ),
  );
}

describe('assignment_submissions Storage', () => {
  test('approved classroom Teacher can read saved image while enabled', async () => {
    await seedClassroomEvidence();
    await uploadSavedImage();
    await assertSucceeds(
      getBytes(
        ref(context('teacher').storage(), 'users/trainee/session_evidence/session-1.jpg'),
      ),
    );
  });

  test('classroom saved-image read is denied when the Trainee disables it', async () => {
    await seedClassroomEvidence();
    await uploadSavedImage();
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'users', 'trainee'), {
        session_evidence_enabled: false,
      }, { merge: true });
    });
    await assertFails(
      getBytes(
        ref(context('teacher').storage(), 'users/trainee/session_evidence/session-1.jpg'),
      ),
    );
  });

  test('removed classroom membership invalidates a saved-image read', async () => {
    await seedClassroomEvidence();
    await uploadSavedImage();
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'group_memberships', `${GROUP_ID}_trainee`), {
        status: 'removed',
      }, { merge: true });
    });
    await assertFails(
      getBytes(
        ref(context('teacher').storage(), 'users/trainee/session_evidence/session-1.jpg'),
      ),
    );
  });

  test('unrelated Teacher cannot use a classroom context for another owner', async () => {
    await seedClassroomEvidence();
    await uploadSavedImage();
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'classroom_teacher_access', 'other_trainee'), {
        teacher_id: 'other',
        trainee_id: 'trainee',
        group_id: GROUP_ID,
        schema_version: 1,
        updated_at: Timestamp.now(),
      });
    });
    await assertFails(
      getBytes(
        ref(context('other').storage(), 'users/trainee/session_evidence/session-1.jpg'),
      ),
    );
  });

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
      await setDoc(doc(admin.firestore(), 'assignment_attempts', ATTEMPT), {
        trainee_id: 'trainee',
        teacher_id: 'teacher',
        group_id: GROUP_ID,
        assignment_id: ASG,
        movement_id: 'tm1',
        revision_id: 'rev1',
        origin: 'teacher_created',
        assessment_mode: 'teacher_reviewed',
        attempt_kind: 'teacher_review_submission',
        status: 'submitted',
        awards_global_xp: false,
        created_at: Timestamp.now(),
      }, { merge: true });
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
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'assignment_attempts', ATTEMPT), {
        status: 'submitted',
      }, { merge: true });
    });
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
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'assignment_attempts', ATTEMPT), {
        status: 'submitted',
      }, { merge: true });
    });
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
      await setDoc(doc(admin.firestore(), 'assignment_attempts', ATTEMPT), {
        status: 'submitted',
      }, { merge: true });
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
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'assignment_attempts', ATTEMPT), {
        status: 'submitted',
      }, { merge: true });
    });
    await assertSucceeds(deleteObject(ref(context('teacher').storage(), PATH)));
  });

  test('object update is denied after metadata is present', async () => {
    await seedClassroom();
    const storage = context('trainee').storage();
    await assertSucceeds(
      uploadBytes(ref(storage, PATH), new Uint8Array(64), metadata()),
    );
    // Atomic CREATE already bootstraps custom metadata. A later metadata
    // PATCH is not the one-time Windows bootstrap and must stay denied.
    await assertFails(
      updateMetadata(ref(storage, PATH), { contentType: 'video/mp4' }),
    );
  });

  async function uploadDraftObject() {
    await seedClassroom();
    await assertSucceeds(
      uploadBytes(
        ref(context('trainee').storage(), PATH),
        new Uint8Array(64),
        metadata(),
      ),
    );
  }

  async function setAttemptStatus(status) {
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'assignment_attempts', ATTEMPT), {
        status,
      }, { merge: true });
    });
  }

  test('Teacher reading draft object is denied; Trainee cleanup still works', async () => {
    await uploadDraftObject();
    await assertFails(getBytes(ref(context('teacher').storage(), PATH)));
    await assertSucceeds(getBytes(ref(context('trainee').storage(), PATH)));
    await assertSucceeds(deleteObject(ref(context('trainee').storage(), PATH)));
  });

  test('Teacher reading submitted object is allowed', async () => {
    await uploadDraftObject();
    await setAttemptStatus('submitted');
    await assertSucceeds(getBytes(ref(context('teacher').storage(), PATH)));
  });

  test('Teacher reading approved object is allowed', async () => {
    await uploadDraftObject();
    await setAttemptStatus('approved');
    await assertSucceeds(getBytes(ref(context('teacher').storage(), PATH)));
  });

  test('Teacher reading needs_retry object is allowed', async () => {
    await uploadDraftObject();
    await setAttemptStatus('needs_retry');
    await assertSucceeds(getBytes(ref(context('teacher').storage(), PATH)));
  });

  test('assigning Teacher cannot delete an active draft object', async () => {
    await uploadDraftObject();
    await assertFails(deleteObject(ref(context('teacher').storage(), PATH)));
  });

  test('abandoned draft keeps the Firestore authorization anchor across Storage cleanup', async () => {
    await uploadDraftObject();
    const traineeDb = context('trainee').firestore();
    await assertFails(
      deleteDoc(doc(traineeDb, 'assignment_attempts', ATTEMPT)),
    );
    await assertSucceeds(
      updateDoc(doc(traineeDb, 'assignment_attempts', ATTEMPT), {
        abandoned_at: serverTimestamp(),
      }),
    );
    await assertFails(
      uploadBytes(
        ref(context('trainee').storage(), PATH),
        new Uint8Array(32),
        metadata(),
      ),
    );
    await assertFails(getBytes(ref(context('teacher').storage(), PATH)));
    await assertFails(getBytes(ref(context('other').storage(), PATH)));
    await assertFails(deleteObject(ref(context('other').storage(), PATH)));
    await assertSucceeds(deleteObject(ref(context('trainee').storage(), PATH)));

    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await uploadBytes(ref(admin.storage(), PATH), new Uint8Array(64), metadata());
    });
    await assertFails(getBytes(ref(context('teacher').storage(), PATH)));
    await assertSucceeds(deleteObject(ref(context('teacher').storage(), PATH)));

    const remaining = await getDoc(doc(traineeDb, 'assignment_attempts', ATTEMPT));
    if (!remaining.exists()) {
      throw new Error('authorization anchor was deleted after Storage cleanup');
    }
  });
});
