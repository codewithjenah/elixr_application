import { readFileSync } from 'node:fs';
import { before, beforeEach, after, describe, test } from 'node:test';

import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, Timestamp } from 'firebase/firestore';
import {
  deleteObject,
  getBytes,
  getMetadata,
  ref,
  updateMetadata,
  uploadBytes,
} from 'firebase/storage';

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

function phase6CustomMetadata(overrides = {}) {
  return {
    teacher_id: 'teacher',
    group_id: GROUP_ID,
    assignment_id: ASG,
    trainee_id: 'trainee',
    attempt_id: ATTEMPT,
    movement_id: 'tm1',
    revision_id: 'rev1',
    ...overrides,
  };
}

function atomicMetadata(overrides = {}) {
  return {
    contentType: 'video/mp4',
    customMetadata: phase6CustomMetadata(overrides),
  };
}

function bytesOnlyMetadata() {
  return { contentType: 'video/mp4' };
}

async function seedClassroom({
  membership = 'approved',
  attemptStatus = 'draft',
  includeAttempt = true,
  includeMembership = true,
  attemptOverrides = {},
  membershipOverrides = {},
  abandoned = false,
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
    if (includeMembership) {
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
        ...membershipOverrides,
      });
    }
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
    if (includeAttempt) {
      const attempt = {
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
        ...attemptOverrides,
      };
      if (abandoned) {
        attempt.abandoned_at = Timestamp.now();
      }
      await setDoc(doc(db, 'assignment_attempts', ATTEMPT), attempt);
    }
  });
}

async function setAttemptStatus(status, extra = {}) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'assignment_attempts', ATTEMPT), {
      status,
      ...extra,
    }, { merge: true });
  });
}

async function uploadWindowsCreate(uid = 'trainee', {
  path = PATH,
  body = new Uint8Array(64),
} = {}) {
  return uploadBytes(ref(context(uid).storage(), path), body, bytesOnlyMetadata());
}

async function bootstrapMetadata(uid = 'trainee', custom = phase6CustomMetadata()) {
  return updateMetadata(ref(context(uid).storage(), PATH), {
    customMetadata: custom,
  });
}

async function inspectMetadata(path = PATH) {
  let stored;
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    stored = await getMetadata(ref(admin.storage(), path));
  });
  return stored;
}

describe('Windows two-stage assignment_submissions upload', () => {
  test('STAGE 1 metadata-free CREATE is allowed', async () => {
    await seedClassroom();
    await assertSucceeds(uploadWindowsCreate());
    const stored = await inspectMetadata();
    if (!stored.md5Hash) {
      throw new Error(
        `STAGE 1 object missing md5Hash (crc32c from getMetadata=${stored.crc32c})`,
      );
    }
    const custom = stored.customMetadata || {};
    for (const key of [
      'teacher_id', 'group_id', 'assignment_id', 'trainee_id',
      'attempt_id', 'movement_id', 'revision_id',
    ]) {
      if (custom[key]) {
        throw new Error(`STAGE 1 stored unexpected metadata ${key}=${custom[key]}`);
      }
    }
  });

  test('STAGE 1 Teacher read and arbitrary metadata update are denied', async () => {
    await seedClassroom();
    await assertSucceeds(uploadWindowsCreate());
    await assertFails(getBytes(ref(context('teacher').storage(), PATH)));
    await assertFails(getBytes(ref(context('trainee').storage(), PATH)));
    await assertFails(
      updateMetadata(ref(context('trainee').storage(), PATH), {
        customMetadata: { teacher_id: 'other' },
      }),
    );
  });

  test('STAGE 2 exact seven-field bootstrap UPDATE is allowed once', async () => {
    await seedClassroom();
    await assertSucceeds(uploadWindowsCreate());
    await assertSucceeds(bootstrapMetadata());
    const stored = await inspectMetadata();
    const custom = stored.customMetadata || {};
    const expected = phase6CustomMetadata();
    for (const [key, value] of Object.entries(expected)) {
      if (custom[key] !== value) {
        throw new Error(`bootstrap stored ${key}=${custom[key]}, expected ${value}`);
      }
    }
    await assertSucceeds(getBytes(ref(context('trainee').storage(), PATH)));
    await assertFails(getBytes(ref(context('teacher').storage(), PATH)));
    await assertFails(bootstrapMetadata());
  });

  test('reviewable Teacher read works after bootstrap', async () => {
    await seedClassroom();
    await assertSucceeds(uploadWindowsCreate());
    await assertSucceeds(bootstrapMetadata());
    await setAttemptStatus('submitted');
    await assertSucceeds(getBytes(ref(context('teacher').storage(), PATH)));
    await assertFails(getBytes(ref(context('other').storage(), PATH)));
  });
});

describe('assignment_submissions CREATE negatives', () => {
  test('bad filename is denied', async () => {
    await seedClassroom();
    await assertFails(
      uploadWindowsCreate('trainee', {
        path: `assignment_submissions/teacher/${GROUP_ID}/${ASG}/trainee/clip.mp4`,
      }),
    );
    await assertFails(
      uploadWindowsCreate('trainee', {
        path: `assignment_submissions/teacher/${GROUP_ID}/${ASG}/trainee/review_sub_clip1.MP4`,
      }),
    );
  });

  test('wrong trainee path is denied', async () => {
    await seedClassroom();
    await assertFails(
      uploadWindowsCreate('trainee', {
        path: `assignment_submissions/teacher/${GROUP_ID}/${ASG}/otherTrainee/${ATTEMPT}.mp4`,
      }),
    );
  });

  test('missing attempt is denied', async () => {
    await seedClassroom({ includeAttempt: false });
    await assertFails(uploadWindowsCreate());
  });

  test('mismatched attempt identity is denied', async () => {
    await seedClassroom({
      attemptOverrides: { assignment_id: 'otherAssignment0000001' },
    });
    await assertFails(uploadWindowsCreate());
  });

  test('abandoned attempt CREATE is denied', async () => {
    await seedClassroom({ abandoned: true });
    await assertFails(uploadWindowsCreate());
  });

  test('removed membership CREATE is denied', async () => {
    await seedClassroom({ membership: 'removed' });
    await assertFails(uploadWindowsCreate());
  });

  test('oversized CREATE is denied', async () => {
    await seedClassroom();
    await assertFails(
      uploadWindowsCreate('trainee', {
        body: new Uint8Array(50 * 1024 * 1024 + 1),
      }),
    );
  });

  test('wrong contentType CREATE is denied', async () => {
    await seedClassroom();
    await assertFails(
      uploadBytes(
        ref(context('trainee').storage(), PATH),
        new Uint8Array(64),
        { contentType: 'video/quicktime' },
      ),
    );
  });
});

describe('assignment_submissions metadata bootstrap negatives', () => {
  async function stage1() {
    await seedClassroom();
    await assertSucceeds(uploadWindowsCreate());
  }

  test('wrong teacher_id is denied', async () => {
    await stage1();
    await assertFails(bootstrapMetadata('trainee', phase6CustomMetadata({ teacher_id: 'other' })));
  });

  test('wrong group_id is denied', async () => {
    await stage1();
    await assertFails(bootstrapMetadata('trainee', phase6CustomMetadata({ group_id: 'otherGroup' })));
  });

  test('wrong assignment_id is denied', async () => {
    await stage1();
    await assertFails(
      bootstrapMetadata('trainee', phase6CustomMetadata({ assignment_id: 'otherAsg' })),
    );
  });

  test('wrong trainee_id is denied', async () => {
    await stage1();
    await assertFails(
      bootstrapMetadata('trainee', phase6CustomMetadata({ trainee_id: 'otherTrainee' })),
    );
  });

  test('wrong attempt_id is denied', async () => {
    await stage1();
    await assertFails(
      bootstrapMetadata('trainee', phase6CustomMetadata({ attempt_id: 'review_sub_other' })),
    );
  });

  test('wrong movement_id is denied', async () => {
    await stage1();
    await assertFails(
      bootstrapMetadata('trainee', phase6CustomMetadata({ movement_id: 'otherMovement' })),
    );
  });

  test('wrong revision_id is denied', async () => {
    await stage1();
    await assertFails(
      bootstrapMetadata('trainee', phase6CustomMetadata({ revision_id: 'otherRevision' })),
    );
  });

  test('extra custom assignment metadata is denied', async () => {
    await stage1();
    await assertFails(
      bootstrapMetadata('trainee', {
        ...phase6CustomMetadata(),
        extra_field: 'nope',
      }),
    );
  });

  test('missing required metadata is denied', async () => {
    await stage1();
    const custom = phase6CustomMetadata();
    delete custom.revision_id;
    await assertFails(bootstrapMetadata('trainee', custom));
  });

  test('contentType change is denied', async () => {
    await stage1();
    await assertFails(
      updateMetadata(ref(context('trainee').storage(), PATH), {
        contentType: 'image/jpeg',
        customMetadata: phase6CustomMetadata(),
      }),
    );
  });

  test('second metadata update is denied', async () => {
    await stage1();
    await assertSucceeds(bootstrapMetadata());
    await assertFails(bootstrapMetadata());
  });

  test('metadata mutation after bootstrap is denied', async () => {
    await stage1();
    await assertSucceeds(bootstrapMetadata());
    await assertFails(
      updateMetadata(ref(context('trainee').storage(), PATH), {
        customMetadata: { movement_id: 'otherMovement' },
      }),
    );
  });

  test('content size and hash overwrite after bootstrap is denied', async () => {
    await stage1();
    await assertSucceeds(bootstrapMetadata());
    await assertFails(
      updateMetadata(ref(context('trainee').storage(), PATH), {
        contentType: 'video/mp4',
        customMetadata: phase6CustomMetadata(),
      }),
    );
    // Production overwrite is Storage UPDATE and is denied by md5Hash/crc32c
    // plus the one-time bootstrap. After submit, even the emulator's
    // uploadBytes-as-CREATE mismatch is denied because the attempt is no
    // longer an active upload anchor.
    await setAttemptStatus('submitted');
    await assertFails(
      uploadBytes(
        ref(context('trainee').storage(), PATH),
        new Uint8Array(128),
        bytesOnlyMetadata(),
      ),
    );
    await assertFails(
      uploadBytes(
        ref(context('trainee').storage(), PATH),
        new Uint8Array(64),
        atomicMetadata(),
      ),
    );
  });
});

describe('assignment_submissions read security', () => {
  test('unbootstrapped object Teacher read is denied', async () => {
    await seedClassroom();
    await assertSucceeds(uploadWindowsCreate());
    await setAttemptStatus('submitted');
    await assertFails(getBytes(ref(context('teacher').storage(), PATH)));
  });

  test('unrelated Teacher read is denied', async () => {
    await seedClassroom();
    await assertSucceeds(uploadWindowsCreate());
    await assertSucceeds(bootstrapMetadata());
    await setAttemptStatus('submitted');
    await assertFails(getBytes(ref(context('other').storage(), PATH)));
  });

  test('assigning Teacher only gets reviewable submission', async () => {
    await seedClassroom();
    await assertSucceeds(uploadWindowsCreate());
    await assertSucceeds(bootstrapMetadata());
    await assertFails(getBytes(ref(context('teacher').storage(), PATH)));
    await setAttemptStatus('submitted');
    await assertSucceeds(getBytes(ref(context('teacher').storage(), PATH)));
    await setAttemptStatus('approved');
    await assertSucceeds(getBytes(ref(context('teacher').storage(), PATH)));
    await setAttemptStatus('needs_retry');
    await assertSucceeds(getBytes(ref(context('teacher').storage(), PATH)));
  });
});

describe('assignment_submissions partial-object delete', () => {
  test('owner can clean unbootstrapped partial object', async () => {
    await seedClassroom();
    await assertSucceeds(uploadWindowsCreate());
    await assertFails(deleteObject(ref(context('other').storage(), PATH)));
    await assertFails(deleteObject(ref(context('otherTrainee').storage(), PATH)));
    await assertSucceeds(deleteObject(ref(context('trainee').storage(), PATH)));
  });

  test('owner can clean abandoned partial object', async () => {
    await seedClassroom();
    await assertSucceeds(uploadWindowsCreate());
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'assignment_attempts', ATTEMPT), {
        abandoned_at: Timestamp.now(),
      }, { merge: true });
    });
    await assertFails(deleteObject(ref(context('other').storage(), PATH)));
    await assertSucceeds(deleteObject(ref(context('trainee').storage(), PATH)));
  });

  test('unrelated Teacher cannot delete unbootstrapped or abandoned partial object', async () => {
    await seedClassroom();
    await assertSucceeds(uploadWindowsCreate());
    await assertFails(deleteObject(ref(context('other').storage(), PATH)));
    await assertFails(deleteObject(ref(context('teacher').storage(), PATH)));
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'assignment_attempts', ATTEMPT), {
        abandoned_at: Timestamp.now(),
      }, { merge: true });
    });
    await assertFails(deleteObject(ref(context('other').storage(), PATH)));
    await assertSucceeds(deleteObject(ref(context('teacher').storage(), PATH)));
  });
});
