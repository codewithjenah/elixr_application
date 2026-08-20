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
  where,
  setDoc,
  updateDoc,
  writeBatch,
  serverTimestamp,
  Timestamp,
  deleteField,
} from 'firebase/firestore';

const PROJECT_ID = 'demo-elixr';
const GROUP_ID = 'group-1';
const ASG_A = 'asgA';
const ASG_B = 'asgB';
const RULES_SOURCE = readFileSync(
  new URL('../firestore.rules', import.meta.url),
  'utf8',
);

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: RULES_SOURCE,
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

function rubricFields({
  technique = 3,
  stability = 2,
  completion = 3,
  propPositioning = 2,
} = {}) {
  const total = technique + stability + completion + propPositioning;
  const performanceLevel =
    total <= 3
      ? 'beginning'
      : total <= 6
        ? 'developing'
        : total <= 9
          ? 'competent'
          : total <= 11
            ? 'proficient'
            : 'mastered';
  return {
    assessment_version: 2,
    rubric: {
      technique,
      stability,
      completion,
      prop_positioning: propPositioning,
    },
    rubric_total: total,
    performance_level: performanceLevel,
  };
}

function assignmentContext(assignmentId = ASG_A) {
  const official =
    assignmentId === ASG_B
      ? {
          movement_id: 'official_normal_grip',
          revision_id: 'official_normal_grip_v1',
        }
      : {
          movement_id: 'official_hand_stall',
          revision_id: 'official_hand_stall_v1',
        };
  return {
    assignment_id: assignmentId,
    group_id: GROUP_ID,
    teacher_id: 'teacher',
    ...official,
  };
}

function officialAssignmentDoc(assignmentId = ASG_A) {
  const ctx = assignmentContext(assignmentId);
  const name = assignmentId === ASG_B ? 'Normal Grip' : 'Hand Stall';
  return {
    teacher_id: 'teacher',
    group_id: GROUP_ID,
    movement_id: ctx.movement_id,
    revision_id: ctx.revision_id,
    origin: 'official_elixr',
    assessment_mode: 'official_guided',
    status: 'active',
    display_title: name,
    teacher_display_name: 'Grace Hopper',
    group_name: 'BSHM 4A',
    official_movement_name: name,
    created_at: Timestamp.now(),
    updated_at: Timestamp.now(),
  };
}

function v2Session({
  userId = 'trainee',
  movementName = 'Hand Stall',
  createdAt = serverTimestamp(),
  context = null,
} = {}) {
  return {
    user_id: userId,
    movement_name: movementName,
    difficulty: 'Medium',
    duration_seconds: 90,
    prop_type: 'bottle',
    ...rubricFields(),
    created_at: createdAt,
    ...(context ? { assignment_context: context } : {}),
  };
}

function officialPointer({
  sessionId,
  assignmentId = ASG_A,
  traineeId = 'trainee',
  awardsGlobalXp = false,
} = {}) {
  const ctx = assignmentContext(assignmentId);
  return {
    trainee_id: traineeId,
    teacher_id: ctx.teacher_id,
    group_id: ctx.group_id,
    assignment_id: ctx.assignment_id,
    movement_id: ctx.movement_id,
    revision_id: ctx.revision_id,
    origin: 'official_elixr',
    assessment_mode: 'official_guided',
    attempt_kind: 'practice_pointer',
    status: 'submitted',
    awards_global_xp: awardsGlobalXp,
    source_session_id: sessionId,
    ...rubricFields(),
    duration_seconds: 90,
    prop_type: 'bottle',
    created_at: serverTimestamp(),
    completed_at: serverTimestamp(),
  };
}

async function seedClassroom({ secondAssignment = true } = {}) {
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
      status: 'approved',
      invite_id: '7KPMXR4DQ2WT',
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    await setDoc(
      doc(admin, 'group_assignments', ASG_A),
      officialAssignmentDoc(ASG_A),
    );
    if (secondAssignment) {
      await setDoc(
        doc(admin, 'group_assignments', ASG_B),
        officialAssignmentDoc(ASG_B),
      );
    }
  });
}

describe('Phase 5 official assignment session+pointer contract', () => {
  test('ordinary official non-assignment session creation still succeeds', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'sessions', 'ordinary1'), v2Session()),
    );
  });

  test('valid atomic assigned official session + pointer succeeds', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    const sessionId = 'sessA';
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'sessions', sessionId),
      v2Session({ context: assignmentContext(ASG_A) }),
    );
    batch.set(
      doc(db, 'assignment_attempts', `official_ptr_${sessionId}`),
      officialPointer({ sessionId, assignmentId: ASG_A }),
    );
    await assertSucceeds(batch.commit());
    const pointer = await getDoc(
      doc(db, 'assignment_attempts', `official_ptr_${sessionId}`),
    );
    assert.equal(pointer.data().awards_global_xp, false);
    assert.equal(pointer.data().source_session_id, sessionId);
  });

  test('historical ordinary Hand Stall cannot create an official pointer', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'sessions', 'histHand'), v2Session()),
    );
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'official_ptr_histHand'),
        officialPointer({ sessionId: 'histHand' }),
      ),
    );
  });

  test('session created for Assignment A cannot satisfy Assignment B', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    const sessionId = 'sessAB';
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'sessions', sessionId),
      v2Session({ context: assignmentContext(ASG_A) }),
    );
    batch.set(
      doc(db, 'assignment_attempts', `official_ptr_${sessionId}`),
      officialPointer({ sessionId, assignmentId: ASG_B }),
    );
    await assertFails(batch.commit());
  });

  test('assignment_context without required pointer in the same atomic write is rejected', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'sessions', 'sessNoPtr'),
        v2Session({ context: assignmentContext(ASG_A) }),
      ),
    );
  });

  test('pointer without matching assigned session is rejected', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'official_ptr_missing'),
        officialPointer({ sessionId: 'missing' }),
      ),
    );
  });

  test('pointer/source movement mismatch is rejected', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    const sessionId = 'sessMove';
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'sessions', sessionId),
      v2Session({
        movementName: 'Normal Grip',
        context: assignmentContext(ASG_A),
      }),
    );
    batch.set(
      doc(db, 'assignment_attempts', `official_ptr_${sessionId}`),
      officialPointer({ sessionId }),
    );
    await assertFails(batch.commit());
  });

  test('pointer/source trainee mismatch is rejected', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    const sessionId = 'sessTrainee';
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'sessions', sessionId),
      v2Session({ context: assignmentContext(ASG_A) }),
    );
    batch.set(
      doc(db, 'assignment_attempts', `official_ptr_${sessionId}`),
      officialPointer({ sessionId, traineeId: 'otherTrainee' }),
    );
    await assertFails(batch.commit());
  });

  test('pointer/group/teacher/revision mismatch is rejected', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    const sessionId = 'sessRev';
    const pointer = officialPointer({ sessionId });
    pointer.revision_id = 'official_hand_stall_v9';
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'sessions', sessionId),
      v2Session({ context: assignmentContext(ASG_A) }),
    );
    batch.set(doc(db, 'assignment_attempts', `official_ptr_${sessionId}`), pointer);
    await assertFails(batch.commit());
  });

  test('awards_global_xp true is rejected', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    const sessionId = 'sessXp';
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'sessions', sessionId),
      v2Session({ context: assignmentContext(ASG_A) }),
    );
    batch.set(
      doc(db, 'assignment_attempts', `official_ptr_${sessionId}`),
      officialPointer({ sessionId, awardsGlobalXp: true }),
    );
    await assertFails(batch.commit());
  });

  test('assignment_context cannot be added to an old session later', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    await assertSucceeds(setDoc(doc(db, 'sessions', 'oldSess'), v2Session()));
    await assertFails(
      updateDoc(doc(db, 'sessions', 'oldSess'), {
        assignment_context: assignmentContext(ASG_A),
      }),
    );
  });

  test('assignment_context cannot be modified after creation', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    const sessionId = 'sessImm';
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'sessions', sessionId),
      v2Session({ context: assignmentContext(ASG_A) }),
    );
    batch.set(
      doc(db, 'assignment_attempts', `official_ptr_${sessionId}`),
      officialPointer({ sessionId }),
    );
    await assertSucceeds(batch.commit());
    await assertFails(
      updateDoc(doc(db, 'sessions', sessionId), {
        assignment_context: assignmentContext(ASG_B),
      }),
    );
  });

  test('legitimate Phase 4 evidence-removal update still succeeds', async () => {
    await seedClassroom();
    const createdAt = Timestamp.now();
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'sessions', 'evidence-remove'), {
        ...v2Session({ createdAt }),
        evidence_storage_path:
          'users/trainee/session_evidence/evidence-remove.jpg',
        evidence_kind: 'hold_confirmed',
        evidence_size_bytes: 2048,
      });
    });
    await assertSucceeds(
      updateDoc(doc(context('trainee').firestore(), 'sessions', 'evidence-remove'), {
        evidence_storage_path: deleteField(),
        evidence_kind: deleteField(),
        evidence_size_bytes: deleteField(),
      }),
    );
  });
});

describe('Phase 5 teacher movements and attempts', () => {
  test('owner Teacher can create a movement root and first revision atomically', async () => {
    await seedClassroom();
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    const movementRef = doc(db, 'teacher_movements', 'tm1');
    const revisionRef = doc(movementRef, 'revisions', 'rev1');
    batch.set(revisionRef, {
      movement_id: 'tm1',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'teacher_reviewed',
      spec: {
        instructions: 'Hold the tin upright.',
        required_prop: 'bottle',
        capability: 'teacher_review_only',
      },
      created_at: serverTimestamp(),
    });
    batch.set(movementRef, {
      teacher_id: 'teacher',
      title: 'Tin Balance',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  test('unrelated Teacher cannot read private Teacher movements', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'teacher_movements', 'tm1'), {
        teacher_id: 'teacher',
        title: 'Tin Balance',
        status: 'active',
        current_revision_id: 'rev1',
        schema_version: 1,
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });
    await assertFails(getDoc(doc(context('other').firestore(), 'teacher_movements', 'tm1')));
    await assertFails(getDoc(doc(context('trainee').firestore(), 'teacher_movements', 'tm1')));
  });

  test('archived Teacher movement cannot be used for a new assignment', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'teacher_movements', 'tm1'), {
        teacher_id: 'teacher',
        title: 'Tin Balance',
        status: 'archived',
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
    });
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(doc(db, 'group_assignments', 'asgCustom'), {
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
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('Teacher-created draft attempt starts in_progress without session fields', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
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
      await setDoc(doc(admin, 'group_assignments', 'asgCustom'), {
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
    const db = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'assignment_attempts', 'tc_draft_asgCustom_trainee'), {
        trainee_id: 'trainee',
        teacher_id: 'teacher',
        group_id: GROUP_ID,
        assignment_id: 'asgCustom',
        movement_id: 'tm1',
        revision_id: 'rev1',
        origin: 'teacher_created',
        assessment_mode: 'teacher_reviewed',
        attempt_kind: 'teacher_review_draft',
        status: 'in_progress',
        awards_global_xp: false,
        created_at: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(db, 'assignment_attempts', 'tc_review_denied'), {
        trainee_id: 'trainee',
        teacher_id: 'teacher',
        group_id: GROUP_ID,
        assignment_id: 'asgCustom',
        movement_id: 'tm1',
        revision_id: 'rev1',
        origin: 'teacher_created',
        assessment_mode: 'teacher_reviewed',
        attempt_kind: 'teacher_review_draft',
        status: 'approved',
        awards_global_xp: false,
        review_verdict: 'approved',
        created_at: serverTimestamp(),
      }),
    );
  });

  test('assigning Teacher can read classroom attempt; unrelated Teacher cannot', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    const sessionId = 'sessRead';
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'sessions', sessionId),
      v2Session({ context: assignmentContext(ASG_A) }),
    );
    batch.set(
      doc(db, 'assignment_attempts', `official_ptr_${sessionId}`),
      officialPointer({ sessionId }),
    );
    await assertSucceeds(batch.commit());
    await assertSucceeds(
      getDoc(doc(context('teacher').firestore(), 'assignment_attempts', `official_ptr_${sessionId}`)),
    );
    await assertFails(
      getDoc(doc(context('other').firestore(), 'assignment_attempts', `official_ptr_${sessionId}`)),
    );
    await assertFails(
      getDoc(doc(context('otherTrainee').firestore(), 'assignment_attempts', `official_ptr_${sessionId}`)),
    );
  });

  test('official practice_pointer is immutable after create', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    const sessionId = 'sessPtrImm';
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'sessions', sessionId),
      v2Session({ context: assignmentContext(ASG_A) }),
    );
    batch.set(
      doc(db, 'assignment_attempts', `official_ptr_${sessionId}`),
      officialPointer({ sessionId }),
    );
    await assertSucceeds(batch.commit());
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', `official_ptr_${sessionId}`), {
        status: 'in_progress',
      }),
    );
  });

  test('Teacher cannot list another Teacher assignments by query', async () => {
    await seedClassroom();
    const other = context('other').firestore();
    await assertFails(
      getDocs(query(collection(other, 'group_assignments'), where('teacher_id', '==', 'teacher'))),
    );
  });
});

function teacherReviewedSpec({
  instructions = 'Hold the tin upright.',
  requiredProp = 'bottle',
  safetyGuidance,
} = {}) {
  return {
    instructions,
    required_prop: requiredProp,
    capability: 'teacher_review_only',
    ...(safetyGuidance == null ? {} : { safety_guidance: safetyGuidance }),
  };
}

function teacherMovementRoot({
  title = 'Tin Balance',
  status = 'active',
  currentRevisionId = 'rev1',
} = {}) {
  return {
    teacher_id: 'teacher',
    title,
    status,
    current_revision_id: currentRevisionId,
    schema_version: 1,
    created_at: Timestamp.now(),
    updated_at: Timestamp.now(),
  };
}

function teacherMovementRevision({
  movementId = 'tm1',
  revisionId = 'rev1',
  assessmentMode = 'teacher_reviewed',
  spec = teacherReviewedSpec(),
} = {}) {
  return {
    movement_id: movementId,
    teacher_id: 'teacher',
    schema_version: 1,
    assessment_mode: assessmentMode,
    spec,
    created_at: Timestamp.now(),
  };
}

function teacherCreatedAssignmentDoc({
  assignmentId = 'asgCustom',
  movementId = 'tm1',
  revisionId = 'rev1',
  assessmentMode = 'teacher_reviewed',
  displayTitle = 'Tin Balance',
  displayInstructions = 'Hold the tin upright.',
  displaySafetyGuidance,
  allowedProp = 'bottle',
} = {}) {
  return {
    teacher_id: 'teacher',
    group_id: GROUP_ID,
    movement_id: movementId,
    revision_id: revisionId,
    origin: 'teacher_created',
    assessment_mode: assessmentMode,
    status: 'active',
    display_title: displayTitle,
    teacher_display_name: 'Grace Hopper',
    group_name: 'BSHM 4A',
    display_instructions: displayInstructions,
    ...(displaySafetyGuidance == null
      ? {}
      : { display_safety_guidance: displaySafetyGuidance }),
    allowed_prop: allowedProp,
    created_at: Timestamp.now(),
    updated_at: Timestamp.now(),
  };
}

function teacherDraftAttempt({
  assignmentId = 'asgCustom',
  traineeId = 'trainee',
  assessmentMode = 'teacher_reviewed',
  status = 'in_progress',
} = {}) {
  return {
    trainee_id: traineeId,
    teacher_id: 'teacher',
    group_id: GROUP_ID,
    assignment_id: assignmentId,
    movement_id: 'tm1',
    revision_id: 'rev1',
    origin: 'teacher_created',
    assessment_mode: assessmentMode,
    attempt_kind: 'teacher_review_draft',
    status,
    awards_global_xp: false,
    created_at: serverTimestamp(),
  };
}

async function seedTeacherMovement({
  status = 'active',
  currentRevisionId = 'rev1',
  extraRevisions = [],
  spec = teacherReviewedSpec(),
  assessmentMode = 'teacher_reviewed',
} = {}) {
  await seedBypassingRules(async (admin) => {
    await setDoc(
      doc(admin, 'teacher_movements', 'tm1'),
      teacherMovementRoot({ status, currentRevisionId }),
    );
    await setDoc(
      doc(admin, 'teacher_movements', 'tm1', 'revisions', 'rev1'),
      teacherMovementRevision({ spec, assessmentMode }),
    );
    for (const revision of extraRevisions) {
      await setDoc(
        doc(admin, 'teacher_movements', 'tm1', 'revisions', revision.id),
        teacherMovementRevision({
          revisionId: revision.id,
          spec: revision.spec ?? spec,
          assessmentMode: revision.assessmentMode ?? assessmentMode,
        }),
      );
    }
  });
}

describe('Phase 5 integrity: Teacher movement edits require new revisions', () => {
  test('title change with same current_revision_id is denied', async () => {
    await seedClassroom();
    await seedTeacherMovement();
    const db = context('teacher').firestore();
    await assertFails(
      updateDoc(doc(db, 'teacher_movements', 'tm1'), {
        title: 'Renamed Without Revision',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('valid new revision plus root title/current_revision change is allowed', async () => {
    await seedClassroom();
    await seedTeacherMovement();
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tm1', 'revisions', 'rev2'), {
      movement_id: 'tm1',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'teacher_reviewed',
      spec: teacherReviewedSpec({ instructions: 'Keep the tin still.' }),
      created_at: serverTimestamp(),
    });
    batch.update(doc(db, 'teacher_movements', 'tm1'), {
      title: 'Still Tin Balance',
      current_revision_id: 'rev2',
      updated_at: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  test('repointing current_revision_id to a historical revision is denied', async () => {
    await seedClassroom();
    await seedTeacherMovement({
      currentRevisionId: 'rev2',
      extraRevisions: [
        { id: 'rev2', spec: teacherReviewedSpec({ instructions: 'Current spec.' }) },
      ],
    });
    const db = context('teacher').firestore();
    await assertFails(
      updateDoc(doc(db, 'teacher_movements', 'tm1'), {
        current_revision_id: 'rev1',
        updated_at: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(db, 'teacher_movements', 'tm1'), {
        title: 'Rolled Back Title',
        current_revision_id: 'rev1',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('repointing current_revision_id to another pre-existing non-current revision is denied', async () => {
    await seedClassroom();
    await seedTeacherMovement({
      currentRevisionId: 'rev3',
      extraRevisions: [
        { id: 'rev2', spec: teacherReviewedSpec({ instructions: 'Middle spec.' }) },
        { id: 'rev3', spec: teacherReviewedSpec({ instructions: 'Latest spec.' }) },
      ],
    });
    const db = context('teacher').firestore();
    await assertFails(
      updateDoc(doc(db, 'teacher_movements', 'tm1'), {
        current_revision_id: 'rev2',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('publishing a fresh revision from current rev2 to rev3 is allowed', async () => {
    await seedClassroom();
    await seedTeacherMovement({
      currentRevisionId: 'rev2',
      extraRevisions: [
        { id: 'rev2', spec: teacherReviewedSpec({ instructions: 'Current spec.' }) },
      ],
    });
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tm1', 'revisions', 'rev3'), {
      movement_id: 'tm1',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'teacher_reviewed',
      spec: teacherReviewedSpec({ instructions: 'Keep the tin still.' }),
      created_at: serverTimestamp(),
    });
    batch.update(doc(db, 'teacher_movements', 'tm1'), {
      title: 'Still Tin Balance',
      current_revision_id: 'rev3',
      updated_at: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  test('archived movement cannot silently reactivate by changing revision', async () => {
    await seedClassroom();
    await seedTeacherMovement({ status: 'archived' });
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tm1', 'revisions', 'rev2'), {
      movement_id: 'tm1',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'teacher_reviewed',
      spec: teacherReviewedSpec(),
      created_at: serverTimestamp(),
    });
    batch.update(doc(db, 'teacher_movements', 'tm1'), {
      status: 'active',
      current_revision_id: 'rev2',
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('normal archive of an active Teacher movement is allowed', async () => {
    await seedClassroom();
    await seedTeacherMovement();
    const db = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'teacher_movements', 'tm1'), {
        status: 'archived',
        updated_at: serverTimestamp(),
      }),
    );
  });
});

describe('Phase 5 integrity: assignment snapshots pin the current revision', () => {
  test('new assignment referencing an old non-current revision is denied', async () => {
    await seedClassroom();
    await seedTeacherMovement({
      currentRevisionId: 'rev2',
      extraRevisions: [
        { id: 'rev2', spec: teacherReviewedSpec({ instructions: 'Current spec.' }) },
      ],
    });
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(
        doc(db, 'group_assignments', 'asgOldRev'),
        {
          ...teacherCreatedAssignmentDoc({
            assignmentId: 'asgOldRev',
            revisionId: 'rev1',
          }),
          created_at: serverTimestamp(),
          updated_at: serverTimestamp(),
        },
      ),
    );
  });

  test('assignment with forged display_instructions is denied', async () => {
    await seedClassroom();
    await seedTeacherMovement();
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(
        doc(db, 'group_assignments', 'asgForgedInstr'),
        {
          ...teacherCreatedAssignmentDoc({
            displayInstructions: 'Classroom-only rewrite.',
          }),
          created_at: serverTimestamp(),
          updated_at: serverTimestamp(),
        },
      ),
    );
  });

  test('assignment with forged display_safety_guidance is denied', async () => {
    await seedClassroom();
    await seedTeacherMovement({
      spec: teacherReviewedSpec({ safetyGuidance: 'Keep a clear floor.' }),
    });
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(
        doc(db, 'group_assignments', 'asgForgedSafety'),
        {
          ...teacherCreatedAssignmentDoc({
            displaySafetyGuidance: 'Ignore the published safety note.',
          }),
          created_at: serverTimestamp(),
          updated_at: serverTimestamp(),
        },
      ),
    );
  });

  test('assignment omitting safety when revision has safety is denied', async () => {
    await seedClassroom();
    await seedTeacherMovement({
      spec: teacherReviewedSpec({ safetyGuidance: 'Keep a clear floor.' }),
    });
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(
        doc(db, 'group_assignments', 'asgMissingSafety'),
        {
          ...teacherCreatedAssignmentDoc(),
          created_at: serverTimestamp(),
          updated_at: serverTimestamp(),
        },
      ),
    );
  });

  test('assignment adding safety when revision has none is denied', async () => {
    await seedClassroom();
    await seedTeacherMovement();
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(
        doc(db, 'group_assignments', 'asgExtraSafety'),
        {
          ...teacherCreatedAssignmentDoc({
            displaySafetyGuidance: 'Invented safety note.',
          }),
          created_at: serverTimestamp(),
          updated_at: serverTimestamp(),
        },
      ),
    );
  });

  test('correctly snapshotted current revision assignment is allowed', async () => {
    await seedClassroom();
    await seedTeacherMovement({
      spec: teacherReviewedSpec({ safetyGuidance: 'Keep a clear floor.' }),
    });
    const db = context('teacher').firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'group_assignments', 'asgCurrent'),
        {
          ...teacherCreatedAssignmentDoc({
            displaySafetyGuidance: 'Keep a clear floor.',
          }),
          created_at: serverTimestamp(),
          updated_at: serverTimestamp(),
        },
      ),
    );
  });
});

describe('Phase 5 integrity: assignment snapshots are immutable after create', () => {
  test('changing display_instructions after create is denied', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(
        doc(admin, 'group_assignments', 'asgSnap'),
        teacherCreatedAssignmentDoc(),
      );
    });
    const db = context('teacher').firestore();
    await assertFails(
      updateDoc(doc(db, 'group_assignments', 'asgSnap'), {
        display_instructions: 'Rewritten after assign.',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('changing display_safety_guidance after create is denied', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(
        doc(admin, 'group_assignments', 'asgSnap'),
        teacherCreatedAssignmentDoc({
          displaySafetyGuidance: 'Keep a clear floor.',
        }),
      );
    });
    const db = context('teacher').firestore();
    await assertFails(
      updateDoc(doc(db, 'group_assignments', 'asgSnap'), {
        display_safety_guidance: 'Changed after assign.',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('changing movement or revision identity after create is denied', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(
        doc(admin, 'group_assignments', 'asgSnap'),
        teacherCreatedAssignmentDoc(),
      );
    });
    const db = context('teacher').firestore();
    await assertFails(
      updateDoc(doc(db, 'group_assignments', 'asgSnap'), {
        revision_id: 'rev2',
        movement_id: 'tm2',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('archive/status update only is allowed', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(
        doc(admin, 'group_assignments', 'asgSnap'),
        teacherCreatedAssignmentDoc(),
      );
    });
    const db = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'group_assignments', 'asgSnap'), {
        status: 'archived',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('due_at lifecycle update is allowed', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(
        doc(admin, 'group_assignments', 'asgSnap'),
        teacherCreatedAssignmentDoc(),
      );
    });
    const db = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(db, 'group_assignments', 'asgSnap'), {
        due_at: Timestamp.fromMillis(Date.now() + 86400000),
        updated_at: serverTimestamp(),
      }),
    );
  });
});

describe('Phase 5 integrity: template_scored writes remain closed', () => {
  test('template_scored Teacher movement revision create is denied', async () => {
    await seedClassroom();
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tmTpl', 'revisions', 'rev1'), {
      movement_id: 'tmTpl',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'template_scored',
      spec: teacherReviewedSpec(),
      created_at: serverTimestamp(),
    });
    batch.set(doc(db, 'teacher_movements', 'tmTpl'), {
      ...teacherMovementRoot(),
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('template_scored Teacher-created assignment is denied', async () => {
    await seedClassroom();
    await seedTeacherMovement();
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(
        doc(db, 'group_assignments', 'asgTpl'),
        {
          ...teacherCreatedAssignmentDoc({ assessmentMode: 'template_scored' }),
          created_at: serverTimestamp(),
          updated_at: serverTimestamp(),
        },
      ),
    );
  });

  test('template_scored Phase 5 draft attempt is denied', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(
        doc(admin, 'group_assignments', 'asgCustom'),
        teacherCreatedAssignmentDoc(),
      );
    });
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'tc_draft_asgCustom_trainee'),
        teacherDraftAttempt({ assessmentMode: 'template_scored' }),
      ),
    );
  });

  test('teacher_reviewed movement, assignment, and draft remain allowed', async () => {
    await seedClassroom();
    const teacherDb = context('teacher').firestore();
    const createBatch = writeBatch(teacherDb);
    createBatch.set(doc(teacherDb, 'teacher_movements', 'tmOk', 'revisions', 'rev1'), {
      movement_id: 'tmOk',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'teacher_reviewed',
      spec: teacherReviewedSpec(),
      created_at: serverTimestamp(),
    });
    createBatch.set(doc(teacherDb, 'teacher_movements', 'tmOk'), {
      teacher_id: 'teacher',
      title: 'Tin Balance',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertSucceeds(createBatch.commit());
    await assertSucceeds(
      setDoc(doc(teacherDb, 'group_assignments', 'asgOk'), {
        teacher_id: 'teacher',
        group_id: GROUP_ID,
        movement_id: 'tmOk',
        revision_id: 'rev1',
        origin: 'teacher_created',
        assessment_mode: 'teacher_reviewed',
        status: 'active',
        display_title: 'Tin Balance',
        teacher_display_name: 'Grace Hopper',
        group_name: 'BSHM 4A',
        display_instructions: 'Hold the tin upright.',
        allowed_prop: 'bottle',
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      setDoc(
        doc(context('trainee').firestore(), 'assignment_attempts', 'tc_draft_asgOk_trainee'),
        {
          ...teacherDraftAttempt({ assignmentId: 'asgOk' }),
          movement_id: 'tmOk',
        },
      ),
    );
  });
});

describe('Phase 5 integrity: canonical teacher-created draft attempt IDs', () => {
  test('canonical teacher-created draft ID is allowed', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(
        doc(admin, 'group_assignments', 'asgCustom'),
        teacherCreatedAssignmentDoc(),
      );
    });
    const db = context('trainee').firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'assignment_attempts', 'tc_draft_asgCustom_trainee'),
        teacherDraftAttempt(),
      ),
    );
  });

  test('arbitrary draft ID for the same assignment is denied', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(
        doc(admin, 'group_assignments', 'asgCustom'),
        teacherCreatedAssignmentDoc(),
      );
    });
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'spam_asgCustom_trainee'),
        teacherDraftAttempt(),
      ),
    );
  });

  test('another trainee cannot use the current trainee canonical draft ID', async () => {
    await seedClassroom();
    await seedBypassingRules(async (admin) => {
      await setDoc(
        doc(admin, 'group_assignments', 'asgCustom'),
        teacherCreatedAssignmentDoc(),
      );
      await setDoc(doc(admin, 'group_memberships', `${GROUP_ID}_otherTrainee`), {
        group_id: GROUP_ID,
        teacher_id: 'teacher',
        trainee_id: 'otherTrainee',
        teacher_display_name: 'Grace Hopper',
        trainee_display_name: 'Other Trainee',
        status: 'approved',
        invite_id: '7KPMXR4DQ2WT',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    });
    const db = context('otherTrainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'tc_draft_asgCustom_trainee'),
        teacherDraftAttempt({ traineeId: 'trainee' }),
      ),
    );
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'tc_draft_asgCustom_trainee'),
        teacherDraftAttempt({ traineeId: 'otherTrainee' }),
      ),
    );
  });
});
