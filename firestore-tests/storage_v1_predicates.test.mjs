import { readFileSync } from 'node:fs';
import { before, beforeEach, after, describe, test } from 'node:test';

import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, Timestamp } from 'firebase/firestore';
import { ref, uploadBytes } from 'firebase/storage';

const PROJECT_ID = 'demo-elixr';
const TEACHER = 'WNFvwRJ4bzTFpVmsgv5x3qV2urt1';
const TRAINEE = 'OeflNaVfBkZ93BLOsGhRyOv6WAD3';
const GROUP = 'i0CaSM4nEA9sNuKSRagO';
const ASG = 'ENvAezoRemcyihux3wpP';
const MOVEMENT = 'CYdQM78YMPbLTCTblERB';
const REVISION = 'DNLnQUFnxmwUP0y5uIM9';
const ATTEMPT = 'review_sub_prodshaped1';

function objectPath({
  teacherId = TEACHER,
  groupId = GROUP,
  assignmentId = ASG,
  traineeId = TRAINEE,
  fileName = `${ATTEMPT}.mp4`,
} = {}) {
  return `assignment_submissions/${teacherId}/${groupId}/${assignmentId}/${traineeId}/${fileName}`;
}

const PATH = objectPath();

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
      teacher_id: TEACHER,
      group_id: GROUP,
      assignment_id: ASG,
      trainee_id: TRAINEE,
      attempt_id: ATTEMPT,
      movement_id: MOVEMENT,
      revision_id: REVISION,
      ...overrides,
    },
  };
}

async function seedClassroom({
  membership = 'approved',
  attemptStatus = 'draft',
  includeAttempt = true,
  attemptOverrides = {},
  abandoned = false,
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    await setDoc(doc(db, 'users', TEACHER), {
      full_name: 'Teacher One',
      role: 'Teacher',
    });
    await setDoc(doc(db, 'users', TRAINEE), {
      full_name: 'Trainee One',
      role: 'Trainee',
    });
    await setDoc(doc(db, 'group_memberships', `${GROUP}_${TRAINEE}`), {
      group_id: GROUP,
      teacher_id: TEACHER,
      trainee_id: TRAINEE,
      teacher_display_name: 'Teacher One',
      trainee_display_name: 'Trainee One',
      status: membership,
      invite_id: '7KPMXR4DQ2WT',
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    await setDoc(doc(db, 'group_assignments', ASG), {
      teacher_id: TEACHER,
      group_id: GROUP,
      movement_id: MOVEMENT,
      revision_id: REVISION,
      origin: 'teacher_created',
      assessment_mode: 'teacher_reviewed',
      status: 'active',
      display_title: 'Tin Balance',
      teacher_display_name: 'Teacher One',
      group_name: 'BSHM 4A',
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    if (includeAttempt) {
      const attempt = {
        trainee_id: TRAINEE,
        teacher_id: TEACHER,
        group_id: GROUP,
        assignment_id: ASG,
        movement_id: MOVEMENT,
        revision_id: REVISION,
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

function upload(uid, { path = PATH, body = new Uint8Array(64), meta = metadata() } = {}) {
  return uploadBytes(ref(context(uid).storage(), path), body, meta);
}

describe('production-shaped assignment_submissions create', () => {
  test('exact live Windows submit request is allowed', async () => {
    await seedClassroom();
    await assertSucceeds(upload(TRAINEE));
  });
});

describe('assignment_submissions create predicates', () => {
  test('1 request.auth missing is denied', async () => {
    await seedClassroom();
    await assertFails(
      uploadBytes(ref(testEnv.unauthenticatedContext().storage(), PATH), new Uint8Array(64), metadata()),
    );
  });

  test('2 wrong auth uid is denied', async () => {
    await seedClassroom();
    await assertFails(upload(TEACHER));
  });

  test('3 wrong teacher path is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        path: objectPath({ teacherId: 'otherTeacherUid0000000000001' }),
      }),
    );
  });

  test('4 wrong group path is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        path: objectPath({ groupId: 'otherGroup0000000001' }),
      }),
    );
  });

  test('5 wrong assignment path is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        path: objectPath({ assignmentId: 'otherAssignment0000001' }),
      }),
    );
  });

  test('6 wrong trainee path is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        path: objectPath({ traineeId: 'otherTraineeUid0000000000001' }),
      }),
    );
  });

  test('7 wrong attempt filename is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        path: objectPath({ fileName: 'review_sub_otherfile.mp4' }),
      }),
    );
  });

  test('8 wrong content type is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        meta: { ...metadata(), contentType: 'video/quicktime' },
      }),
    );
  });

  test('9 oversized object is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        body: new Uint8Array(15 * 1024 * 1024 + 1),
      }),
    );
  });

  test('10 missing attempt_id metadata is denied', async () => {
    await seedClassroom();
    const meta = metadata();
    delete meta.customMetadata.attempt_id;
    await assertFails(upload(TRAINEE, { meta }));
  });

  test('11 wrong custom teacher_id is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        meta: metadata({ teacher_id: 'otherTeacherUid0000000000001' }),
      }),
    );
  });

  test('12 wrong custom group_id is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        meta: metadata({ group_id: 'otherGroup0000000001' }),
      }),
    );
  });

  test('13 wrong custom assignment_id is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        meta: metadata({ assignment_id: 'otherAssignment0000001' }),
      }),
    );
  });

  test('14 wrong custom trainee_id is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        meta: metadata({ trainee_id: 'otherTraineeUid0000000000001' }),
      }),
    );
  });

  test('15 wrong movement_id metadata is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        meta: metadata({ movement_id: 'otherMovement0000000001' }),
      }),
    );
  });

  test('16 wrong revision_id metadata is denied', async () => {
    await seedClassroom();
    await assertFails(
      upload(TRAINEE, {
        meta: metadata({ revision_id: 'otherRevision0000000001' }),
      }),
    );
  });

  test('17 missing assignment attempt is denied', async () => {
    await seedClassroom({ includeAttempt: false });
    await assertFails(upload(TRAINEE));
  });

  test('18 abandoned draft is denied', async () => {
    await seedClassroom({ abandoned: true });
    await assertFails(upload(TRAINEE));
  });

  test('19 wrong attempt identity is denied', async () => {
    await seedClassroom({
      attemptOverrides: { assignment_id: 'otherAssignment0000001' },
    });
    await assertFails(upload(TRAINEE));
  });

  test('20 removed membership is denied', async () => {
    await seedClassroom({ membership: 'removed' });
    await assertFails(upload(TRAINEE));
  });

  test('21 exact fully valid request is allowed', async () => {
    await seedClassroom();
    await assertSucceeds(upload(TRAINEE));
  });
});
