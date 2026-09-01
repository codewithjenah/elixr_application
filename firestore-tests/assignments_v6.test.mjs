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
  doc,
  getDoc,
  getDocs,
  query,
  runTransaction,
  where,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  Timestamp,
  deleteField,
} from 'firebase/firestore';

const PROJECT_ID = 'demo-elixr';
const GROUP_ID = 'group-1';
const ASG = 'asgCustom';
const ATTEMPT = 'review_sub_clip1';
const CANONICAL_ATTEMPT = `review_sub_${ASG}_trainee`;
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

function canonicalInProgressDoc(overrides = {}) {
  return {
    ...identity(),
    attempt_kind: 'teacher_review_submission',
    status: 'in_progress',
    created_at: serverTimestamp(),
    ...overrides,
  };
}

async function seedClassroom({
  membership = 'approved',
  audienceType,
  targetTraineeIds = [],
} = {}) {
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
      ...(audienceType == null
        ? {}
        : { audience_type: audienceType }),
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    if (audienceType && audienceType !== 'entire_class') {
      for (const traineeId of targetTraineeIds) {
        await setDoc(
          doc(admin, 'group_assignments', ASG, 'assignment_recipients', traineeId),
          {
            assignment_id: ASG,
            group_id: GROUP_ID,
            teacher_id: 'teacher',
            trainee_id: traineeId,
            audience_type: audienceType,
            schema_version: 1,
            created_at: Timestamp.now(),
          },
        );
      }
    }
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
  test('canonical first-time in_progress submission create succeeds', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'assignment_attempts', CANONICAL_ATTEMPT),
        canonicalInProgressDoc(),
      ),
    );
    const created = await assertSucceeds(
      getDoc(doc(db, 'assignment_attempts', CANONICAL_ATTEMPT)),
    );
    assert.equal(created.data().status, 'in_progress');
    assert.equal(created.data().attempt_kind, 'teacher_review_submission');
    assert.equal(created.data().awards_global_xp, false);
    assert.equal(created.data().source_session_id, undefined);
  });

  test('missing canonical read is denied even though direct canonical create succeeds', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    const ref = doc(db, 'assignment_attempts', CANONICAL_ATTEMPT);

    await assertFails(
      runTransaction(db, async (transaction) => {
        await transaction.get(ref);
        transaction.set(ref, canonicalInProgressDoc());
      }),
    );
    await assertSucceeds(setDoc(ref, canonicalInProgressDoc()));
  });

  test('canonical legacy draft promotes to in_progress', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'assignment_attempts', CANONICAL_ATTEMPT), {
        ...canonicalInProgressDoc({ status: 'draft' }),
        created_at: Timestamp.now(),
      });
    });
    await assertSucceeds(
      updateDoc(doc(context('trainee').firestore(), 'assignment_attempts', CANONICAL_ATTEMPT), {
        status: 'in_progress',
      }),
    );
  });

  test('canonical creation is denied without approved membership', async () => {
    await seedClassroom({ membership: 'removed' });
    await assertFails(
      setDoc(
        doc(context('trainee').firestore(), 'assignment_attempts', CANONICAL_ATTEMPT),
        canonicalInProgressDoc(),
      ),
    );
  });

  test('canonical creation is denied for an untargeted approved trainee', async () => {
    await seedClassroom({
      audienceType: 'individual_student',
      targetTraineeIds: ['otherTrainee'],
    });
    await assertFails(
      setDoc(
        doc(context('trainee').firestore(), 'assignment_attempts', CANONICAL_ATTEMPT),
        canonicalInProgressDoc(),
      ),
    );
  });

  test('targeted trainee can create and submit a teacher-reviewed assignment', async () => {
    await seedClassroom({
      audienceType: 'individual_student',
      targetTraineeIds: ['trainee'],
    });
    const db = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'assignment_attempts', ATTEMPT), draftDoc()),
    );
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

  test('submitted and checked canonical submissions cannot restart', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'assignment_attempts', CANONICAL_ATTEMPT), {
        ...canonicalInProgressDoc({ status: 'submitted' }),
        created_at: Timestamp.now(),
      });
    });
    const trainee = context('trainee').firestore();
    await assertFails(
      updateDoc(doc(trainee, 'assignment_attempts', CANONICAL_ATTEMPT), {
        status: 'in_progress',
      }),
    );
    await seedBypassingRules(async (admin) => {
      await updateDoc(doc(admin, 'assignment_attempts', CANONICAL_ATTEMPT), {
        status: 'checked',
      });
    });
    await assertFails(
      updateDoc(doc(trainee, 'assignment_attempts', CANONICAL_ATTEMPT), {
        status: 'in_progress',
      }),
    );
  });

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

  test('>60s metadata denied', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'submitted',
        video_storage_path: PATH,
        video_content_type: 'video/mp4',
        video_size_bytes: 2048,
        video_duration_ms: 60001,
        submitted_at: serverTimestamp(),
        video_expires_at: expiryUnreviewed(),
      }),
    );
  });

  test('>50MiB metadata denied', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'submitted',
        video_storage_path: PATH,
        video_content_type: 'video/mp4',
        video_size_bytes: 50 * 1024 * 1024 + 1,
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

  test('trainee cannot directly delete own teacher_review_submission draft', async () => {
    await seedClassroom();
    await seedDraft();
    await assertFails(
      deleteDoc(doc(context('trainee').firestore(), 'assignment_attempts', ATTEMPT)),
    );
  });

  test('trainee may mark own teacher_review_submission draft abandoned', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        abandoned_at: serverTimestamp(),
      }),
    );
    const snap = await getDoc(doc(db, 'assignment_attempts', ATTEMPT));
    assert.equal(snap.exists(), true);
    assert.equal(snap.data().status, 'draft');
    assert.ok(snap.data().abandoned_at);
    assert.equal(snap.data().awards_global_xp, false);
  });

  test('trainee may abandon a draft and mark leftover object gone', async () => {
    await seedClassroom();
    await seedDraft();
    await assertSucceeds(
      updateDoc(doc(context('trainee').firestore(), 'assignment_attempts', ATTEMPT), {
        abandoned_at: serverTimestamp(),
        video_deleted_at: serverTimestamp(),
        deletion_failed: false,
      }),
    );
  });

  test('trainee may abandon a draft as cleanup-pending', async () => {
    await seedClassroom();
    await seedDraft();
    await assertSucceeds(
      updateDoc(doc(context('trainee').firestore(), 'assignment_attempts', ATTEMPT), {
        abandoned_at: serverTimestamp(),
        deletion_failed: true,
        deletion_failed_at: serverTimestamp(),
      }),
    );
  });

  test('abandon cannot rewrite frozen identity', async () => {
    await seedClassroom();
    await seedDraft();
    await assertFails(
      updateDoc(doc(context('trainee').firestore(), 'assignment_attempts', ATTEMPT), {
        abandoned_at: serverTimestamp(),
        assignment_id: 'asgOther',
      }),
    );
  });

  test('assigning Teacher cannot mark a trainee draft abandoned', async () => {
    await seedClassroom();
    await seedDraft();
    await assertFails(
      updateDoc(doc(context('teacher').firestore(), 'assignment_attempts', ATTEMPT), {
        abandoned_at: serverTimestamp(),
      }),
    );
  });

  test('abandoned draft cannot transition to submitted', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        abandoned_at: serverTimestamp(),
      }),
    );
    await assertFails(
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

  test('abandoned draft cannot be rewritten into an active draft', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        abandoned_at: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        abandoned_at: deleteField(),
      }),
    );
  });

  test('abandoned draft cannot self-approve or gain XP', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        abandoned_at: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        status: 'approved',
        review_verdict: 'approved',
      }),
    );
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        awards_global_xp: true,
      }),
    );
  });

  test('trainee cannot delete submitted attempt', async () => {
    await submitAsTrainee();
    await assertFails(
      deleteDoc(doc(context('trainee').firestore(), 'assignment_attempts', ATTEMPT)),
    );
  });

  test('teacher cannot delete trainee draft', async () => {
    await seedClassroom();
    await seedDraft();
    await assertFails(
      deleteDoc(doc(context('teacher').firestore(), 'assignment_attempts', ATTEMPT)),
    );
  });

  test('abandon fails when video metadata is present', async () => {
    await seedClassroom();
    await seedDraft({
      video_storage_path: PATH,
      video_content_type: 'video/mp4',
    });
    await assertFails(
      updateDoc(doc(context('trainee').firestore(), 'assignment_attempts', ATTEMPT), {
        abandoned_at: serverTimestamp(),
      }),
    );
    await assertFails(
      deleteDoc(doc(context('trainee').firestore(), 'assignment_attempts', ATTEMPT)),
    );
  });

  test('unrelated trainee cannot delete another trainee draft', async () => {
    await seedClassroom();
    await seedDraft();
    await assertFails(
      deleteDoc(doc(context('otherTrainee').firestore(), 'assignment_attempts', ATTEMPT)),
    );
  });

  test('account erasure can still delete an abandoned teacher_review_submission', async () => {
    await seedClassroom();
    await seedDraft();
    await assertSucceeds(
      updateDoc(doc(context('trainee').firestore(), 'assignment_attempts', ATTEMPT), {
        abandoned_at: serverTimestamp(),
      }),
    );
    await seedBypassingRules(async (admin) => {
      await deleteDoc(doc(admin, 'users', 'trainee'));
    });
    await assertSucceeds(
      deleteDoc(doc(context('trainee').firestore(), 'assignment_attempts', ATTEMPT)),
    );
  });

  test('owner can mark an abandoned leftover object deleted', async () => {
    await seedClassroom();
    await seedDraft();
    const db = context('trainee').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        abandoned_at: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(db, 'assignment_attempts', ATTEMPT), {
        video_deleted_at: serverTimestamp(),
        deletion_failed: false,
      }),
    );
  });
});

describe('Phase 6 assignment_attempts list queries', () => {
  test('authenticated trainee can query own trainee_id', async () => {
    await seedClassroom();
    await seedDraft();
    const listed = await assertSucceeds(getDocs(query(
      collection(context('trainee').firestore(), 'assignment_attempts'),
      where('trainee_id', '==', 'trainee'),
    )));
    assert.equal(listed.docs.length, 1);
    assert.equal(listed.docs[0].id, ATTEMPT);
  });

  test('authenticated other trainee cannot query someone else trainee_id', async () => {
    await seedClassroom();
    await seedDraft();
    await assertFails(getDocs(query(
      collection(context('otherTrainee').firestore(), 'assignment_attempts'),
      where('trainee_id', '==', 'trainee'),
    )));
  });

  test('authenticated assigning Teacher can query own teacher_id', async () => {
    await seedClassroom();
    await seedDraft();
    const listed = await assertSucceeds(getDocs(query(
      collection(context('teacher').firestore(), 'assignment_attempts'),
      where('teacher_id', '==', 'teacher'),
    )));
    assert.equal(listed.docs.length, 1);
    assert.equal(listed.docs[0].id, ATTEMPT);
  });
});
