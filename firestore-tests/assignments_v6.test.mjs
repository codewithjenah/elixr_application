import { readFileSync } from 'node:fs';
import { before, beforeEach, after, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  serverTimestamp,
  Timestamp,
  deleteField,
} from 'firebase/firestore';

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
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
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

async function seedBypassingRules(fn) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await fn(admin.firestore());
  });
}

function expiryUnreviewed() {
  return Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000);
}

function expiryReviewed() {
  return Timestamp.fromMillis(Date.now() + 14 * 24 * 60 * 60 * 1000);
}

function identity(overrides = {}) {
  return {
    trainee_id: 'trainee',
    teacher_id: 'teacher',
    group_id: GROUP_ID,
    assignment_id: ASG,
    movement_id: 'tm1',
    revision_id: 'rev1',
    origin: 'teacher_created',
    assessment_mode: 'teacher_reviewed',
    awards_global_xp: false,
    ...overrides,
  };
}

function draftDoc(overrides = {}) {
  return {
    ...identity(),
    attempt_kind: 'teacher_review_submission',
    status: 'draft',
    created_at: serverTimestamp(),
    ...overrides,
  };
}

async function seedClassroom({ membership = 'approved' } = {}) {
  await seedBypassingRules(async (admin) => {
    await setDoc(doc(admin, 'users', 'teacher'), {
      full_name: 'Grace Hopper',
      role: 'Teacher',
    });
    await setDoc(doc(admin, 'users', 'trainee'), {
      full_name: 'Ada Lovelace',
      role: 'Trainee',
    });
    await setDoc(doc(admin, 'users', 'other'), {
      full_name: 'Other Teacher',
      role: 'Teacher',
    });
    await setDoc(doc(admin, 'users', 'otherTrainee'), {
      full_name: 'Other Trainee',
      role: 'Trainee',
    });
    await setDoc(doc(admin, 'groups', GROUP_ID), {
      teacher_id: 'teacher',
      name: 'BSHM 4A',
      status: 'active',
      schema_version: 1,
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    await setDoc(doc(admin, 'group_memberships', `${GROUP_ID}_trainee`), {
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
    await setDoc(doc(admin, 'teacher_movements', 'tm1'), {
      teacher_id: 'teacher',
      title: 'Tin Balance',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    await setDoc(doc(admin, 'teacher_movements', 'tm1', 'revisions', 'rev1'), {
      movement_id: 'tm1',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'teacher_reviewed',
      spec: {
        instructions: 'Hold the tin upright.',
        required_prop: 'bottle',
        capability: 'teacher_review_only',
      },
      created_at: Timestamp.now(),
    });
    await setDoc(doc(admin, 'group_assignments', ASG), {
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
      display_instructions: 'Hold the tin upright.',
      allowed_prop: 'bottle',
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
  });
}

async function seedDraft(overrides = {}) {
  await seedBypassingRules(async (admin) => {
    await setDoc(doc(admin, 'assignment_attempts', ATTEMPT), {
      ...identity(),
      attempt_kind: 'teacher_review_submission',
      status: 'draft',
      created_at: Timestamp.now(),
      ...overrides,
    });
  });
}

describe('Phase 6 teacher_review_submission', () => {
  test('valid submission draft create', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    await assertSucceeds(setDoc(doc(db, 'assignment_attempts', ATTEMPT), draftDoc()));
  });

  test('unrelated trainee create denied', async () => {
    await seedClassroom();
    const db = context('otherTrainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'review_sub_other'),
        draftDoc({ trainee_id: 'otherTrainee' }),
      ),
    );
  });

  test('no membership create denied', async () => {
    await seedClassroom({ membership: 'removed' });
    const db = context('trainee').firestore();
    await assertFails(setDoc(doc(db, 'assignment_attempts', ATTEMPT), draftDoc()));
  });

  test('awards_global_xp true denied', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(doc(db, 'assignment_attempts', ATTEMPT), draftDoc({ awards_global_xp: true })),
    );
  });

  test('source_session_id on review submission denied', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', ATTEMPT),
        draftDoc({ source_session_id: 'sess1' }),
      ),
    );
  });

  test('trainee submitted transition valid', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'submitted',
        video_storage_path: PATH,
        video_content_type: 'video/mp4',
        video_size_bytes: 2048,
        video_duration_ms: 4000,
        submitted_at: serverTimestamp(),
        video_expires_at: expiryUnreviewed(),
      }),
    );
  });

  test('>20s metadata denied', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'submitted',
        video_storage_path: PATH,
        video_content_type: 'video/mp4',
        video_size_bytes: 2048,
        video_duration_ms: 20001,
        submitted_at: serverTimestamp(),
        video_expires_at: expiryUnreviewed(),
      }),
    );
  });

  test('>15MiB metadata denied', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'submitted',
        video_storage_path: PATH,
        video_content_type: 'video/mp4',
        video_size_bytes: 15 * 1024 * 1024 + 1,
        video_duration_ms: 4000,
        submitted_at: serverTimestamp(),
        video_expires_at: expiryUnreviewed(),
      }),
    );
  });

  test('forged video path denied', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'submitted',
        video_storage_path: 'assignment_submissions/other/group-1/asgCustom/trainee/review_sub_clip1.mp4',
        video_content_type: 'video/mp4',
        video_size_bytes: 2048,
        video_duration_ms: 4000,
        submitted_at: serverTimestamp(),
        video_expires_at: expiryUnreviewed(),
      }),
    );
  });

  test('trainee self-approved denied', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), { status: 'approved' }),
    );
  });

  test('trainee needs_retry denied', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), { status: 'needs_retry' }),
    );
  });

  test('trainee review_feedback denied', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        review_feedback: 'I passed',
      }),
    );
  });

  test('trainee reviewed_at denied', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        reviewed_at: serverTimestamp(),
      }),
    );
  });

  async function submitAsTrainee() {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'submitted',
        video_storage_path: PATH,
        video_content_type: 'video/mp4',
        video_size_bytes: 2048,
        video_duration_ms: 4000,
        submitted_at: serverTimestamp(),
        video_expires_at: expiryUnreviewed(),
      }),
    );
  }

  test('assigning Teacher approved valid', async () => {
    await submitAsTrainee();
    const db = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'approved',
        review_verdict: 'approved',
        reviewed_at: serverTimestamp(),
        video_expires_at: expiryReviewed(),
      }),
    );
  });

  test('assigning Teacher needs_retry valid', async () => {
    await submitAsTrainee();
    const db = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'needs_retry',
        review_verdict: 'needs_retry',
        review_feedback: 'Keep the tin upright.',
        reviewed_at: serverTimestamp(),
        video_expires_at: expiryReviewed(),
      }),
    );
  });

  test('verdict/status mismatch denied', async () => {
    await submitAsTrainee();
    const db = context('teacher').firestore();
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'approved',
        review_verdict: 'needs_retry',
        reviewed_at: serverTimestamp(),
        video_expires_at: expiryReviewed(),
      }),
    );
  });

  test('unrelated Teacher review denied', async () => {
    await submitAsTrainee();
    const db = context('other').firestore();
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'approved',
        review_verdict: 'approved',
        reviewed_at: serverTimestamp(),
        video_expires_at: expiryReviewed(),
      }),
    );
  });

  test('Teacher cannot rewrite trainee_id', async () => {
    await submitAsTrainee();
    const db = context('teacher').firestore();
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'approved',
        review_verdict: 'approved',
        reviewed_at: serverTimestamp(),
        video_expires_at: expiryReviewed(),
        trainee_id: 'otherTrainee',
      }),
    );
  });

  test('approved historical review immutable', async () => {
    await submitAsTrainee();
    const teacher = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(teacher, 'assignment_attempts', ATTEMPT), {
        status: 'approved',
        review_verdict: 'approved',
        reviewed_at: serverTimestamp(),
        video_expires_at: expiryReviewed(),
      }),
    );
    await assertFails(
      updateDoc(doc(teacher, 'assignment_attempts', ATTEMPT), {
        review_feedback: 'changed',
      }),
    );
  });

  test('needs_retry historical review immutable', async () => {
    await submitAsTrainee();
    const teacher = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(teacher, 'assignment_attempts', ATTEMPT), {
        status: 'needs_retry',
        review_verdict: 'needs_retry',
        review_feedback: 'Retry',
        reviewed_at: serverTimestamp(),
        video_expires_at: expiryReviewed(),
      }),
    );
    await assertFails(
      updateDoc(doc(teacher, 'assignment_attempts', ATTEMPT), {
        status: 'approved',
        review_verdict: 'approved',
        reviewed_at: serverTimestamp(),
        video_expires_at: expiryReviewed(),
      }),
    );
  });

  test('valid replacement references only matching needs_retry attempt', async () => {
    await submitAsTrainee();
    const teacher = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(teacher, 'assignment_attempts', ATTEMPT), {
        status: 'needs_retry',
        review_verdict: 'needs_retry',
        reviewed_at: serverTimestamp(),
        video_expires_at: expiryReviewed(),
      }),
    );
    const db = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'assignment_attempts', 'review_sub_clip2'), draftDoc({
        supersedes_attempt_id: ATTEMPT,
      })),
    );
  });

  test('cannot supersede approved attempt', async () => {
    await submitAsTrainee();
    const teacher = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(teacher, 'assignment_attempts', ATTEMPT), {
        status: 'approved',
        review_verdict: 'approved',
        reviewed_at: serverTimestamp(),
        video_expires_at: expiryReviewed(),
      }),
    );
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(doc(db, 'assignment_attempts', 'review_sub_clip2'), draftDoc({
        supersedes_attempt_id: ATTEMPT,
      })),
    );
  });

  test('cleanup transition valid for owner and assigning Teacher', async () => {
    await submitAsTrainee();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      updateDoc(doc(trainee, 'assignment_attempts', ATTEMPT), {
        video_storage_path: deleteField(),
        video_deleted_at: serverTimestamp(),
        deletion_failed: false,
      }),
    );
    await seedBypassingRules(async (admin) => {
      await updateDoc(doc(admin, 'assignment_attempts', ATTEMPT), {
        video_storage_path: PATH,
        video_deleted_at: deleteField(),
        deletion_failed: false,
      });
    });
    const teacher = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(teacher, 'assignment_attempts', ATTEMPT), {
        video_storage_path: deleteField(),
        video_deleted_at: serverTimestamp(),
        deletion_failed: false,
      }),
    );
  });

  test('cleanup cannot rewrite review/status', async () => {
    await submitAsTrainee();
    const teacher = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(teacher, 'assignment_attempts', ATTEMPT), {
        status: 'approved',
        review_verdict: 'approved',
        reviewed_at: serverTimestamp(),
        video_expires_at: expiryReviewed(),
      }),
    );
    const trainee = context('trainee').firestore();
    await assertFails(
      updateDoc(doc(trainee, 'assignment_attempts', ATTEMPT), {
        video_storage_path: deleteField(),
        video_deleted_at: serverTimestamp(),
        deletion_failed: false,
        status: 'needs_retry',
      }),
    );
  });

  test('created attempt remains readable by frozen Teacher', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    await assertSucceeds(setDoc(doc(db, 'assignment_attempts', ATTEMPT), draftDoc()));
    await assertSucceeds(getDoc(doc(context('teacher').firestore(), 'assignment_attempts', ATTEMPT)));
    await assertFails(getDoc(doc(context('other').firestore(), 'assignment_attempts', ATTEMPT)));
  });
});
