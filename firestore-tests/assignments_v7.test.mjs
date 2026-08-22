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
  writeBatch,
  serverTimestamp,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = 'demo-elixr';
const GROUP_ID = 'group-1';
const INACTIVE_GROUP = 'group-inactive';
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

function assessmentSpec({ laterality = 'either', extra } = {}) {
  return {
    schema_version: 1,
    template_id: 'balance_stall.wrist_v1',
    prop: 'bottle',
    target: 'wrist',
    laterality,
    ...extra,
  };
}

function templateSpec({
  instructions = 'Balance the bottle on the wrist.',
  requiredProp = 'bottle',
  safetyGuidance,
  assessment = assessmentSpec(),
  extra,
} = {}) {
  return {
    instructions,
    required_prop: requiredProp,
    assessment,
    ...(safetyGuidance == null ? {} : { safety_guidance: safetyGuidance }),
    ...extra,
  };
}

function teacherReviewedSpec() {
  return {
    instructions: 'Hold the tin upright.',
    required_prop: 'bottle',
    capability: 'teacher_review_only',
  };
}

function rubricFields({
  technique = 3,
  stability = 2,
  completion = 3,
  propPositioning = 2,
  performanceLevel,
} = {}) {
  const total = technique + stability + completion + propPositioning;
  const level =
    performanceLevel ??
    (total <= 3
      ? 'beginning'
      : total <= 6
        ? 'developing'
        : total <= 9
          ? 'competent'
          : total <= 11
            ? 'proficient'
            : 'mastered');
  return {
    assessment_version: 2,
    rubric: {
      technique,
      stability,
      completion,
      prop_positioning: propPositioning,
    },
    rubric_total: total,
    performance_level: level,
  };
}

function templateScore({
  traineeId = 'trainee',
  teacherId = 'teacher',
  groupId = GROUP_ID,
  assignmentId = 'asgTpl',
  movementId = 'tmTpl',
  revisionId = 'rev1',
  awardsGlobalXp = false,
  status = 'submitted',
  propType = 'bottle',
  extra,
} = {}) {
  return {
    trainee_id: traineeId,
    teacher_id: teacherId,
    group_id: groupId,
    assignment_id: assignmentId,
    movement_id: movementId,
    revision_id: revisionId,
    origin: 'teacher_created',
    assessment_mode: 'template_scored',
    attempt_kind: 'template_score',
    status,
    awards_global_xp: awardsGlobalXp,
    ...rubricFields(),
    duration_seconds: 11,
    prop_type: propType,
    created_at: serverTimestamp(),
    completed_at: serverTimestamp(),
    ...extra,
  };
}

async function seedClassroom({
  includeInactiveGroup = false,
  membershipStatus = 'approved',
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
    if (includeInactiveGroup) {
      await setDoc(doc(admin, 'groups', INACTIVE_GROUP), {
        teacher_id: 'teacher',
        name: 'Archived class',
        status: 'archived',
        schema_version: 1,
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    }
    if (membershipStatus) {
      await setDoc(doc(admin, 'group_memberships', `${GROUP_ID}_trainee`), {
        group_id: GROUP_ID,
        teacher_id: 'teacher',
        trainee_id: 'trainee',
        teacher_display_name: 'Grace Hopper',
        trainee_display_name: 'Ada Lovelace',
        status: membershipStatus,
        invite_id: '7KPMXR4DQ2WT',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    }
  });
}

async function seedTemplateMovement({
  movementId = 'tmTpl',
  revisionId = 'rev1',
  spec = templateSpec(),
  title = 'Classroom Wrist Stall',
} = {}) {
  await seedBypassingRules(async (admin) => {
    await setDoc(doc(admin, 'teacher_movements', movementId, 'revisions', revisionId), {
      movement_id: movementId,
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'template_scored',
      spec,
      created_at: Timestamp.now(),
    });
    await setDoc(doc(admin, 'teacher_movements', movementId), {
      teacher_id: 'teacher',
      title,
      status: 'active',
      current_revision_id: revisionId,
      schema_version: 1,
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
  });
}

async function seedTeacherReviewedMovement() {
  await seedBypassingRules(async (admin) => {
    await setDoc(doc(admin, 'teacher_movements', 'tmRev', 'revisions', 'rev1'), {
      movement_id: 'tmRev',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'teacher_reviewed',
      spec: teacherReviewedSpec(),
      created_at: Timestamp.now(),
    });
    await setDoc(doc(admin, 'teacher_movements', 'tmRev'), {
      teacher_id: 'teacher',
      title: 'Tin Balance',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
  });
}

function templateAssignmentDoc({
  movementId = 'tmTpl',
  revisionId = 'rev1',
  assessment = assessmentSpec(),
  extra,
} = {}) {
  return {
    teacher_id: 'teacher',
    group_id: GROUP_ID,
    movement_id: movementId,
    revision_id: revisionId,
    origin: 'teacher_created',
    assessment_mode: 'template_scored',
    status: 'active',
    display_title: 'Classroom Wrist Stall',
    teacher_display_name: 'Grace Hopper',
    group_name: 'BSHM 4A',
    display_instructions: 'Balance the bottle on the wrist.',
    allowed_prop: 'bottle',
    assessment_spec: assessment,
    created_at: serverTimestamp(),
    updated_at: serverTimestamp(),
    ...extra,
  };
}

async function seedTemplateAssignment(overrides = {}) {
  await seedTemplateMovement();
  await seedBypassingRules(async (admin) => {
    await setDoc(doc(admin, 'group_assignments', 'asgTpl'), {
      ...templateAssignmentDoc(overrides),
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
  });
}

describe('Phase 7E template movement revisions', () => {
  test('1 assigning Teacher valid template revision create', async () => {
    await seedClassroom();
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tmNew', 'revisions', 'rev1'), {
      movement_id: 'tmNew',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'template_scored',
      spec: templateSpec(),
      created_at: serverTimestamp(),
    });
    batch.set(doc(db, 'teacher_movements', 'tmNew'), {
      teacher_id: 'teacher',
      title: 'Classroom Wrist Stall',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertSucceeds(batch.commit());
  });

  test('2 unrelated Teacher denied', async () => {
    await seedClassroom();
    const db = context('other').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tmNew', 'revisions', 'rev1'), {
      movement_id: 'tmNew',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'template_scored',
      spec: templateSpec(),
      created_at: serverTimestamp(),
    });
    batch.set(doc(db, 'teacher_movements', 'tmNew'), {
      teacher_id: 'teacher',
      title: 'Classroom Wrist Stall',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('3 Trainee denied', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tmNew', 'revisions', 'rev1'), {
      movement_id: 'tmNew',
      teacher_id: 'trainee',
      schema_version: 1,
      assessment_mode: 'template_scored',
      spec: templateSpec(),
      created_at: serverTimestamp(),
    });
    batch.set(doc(db, 'teacher_movements', 'tmNew'), {
      teacher_id: 'trainee',
      title: 'Classroom Wrist Stall',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('4 shaker denied', async () => {
    await seedClassroom();
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tmNew', 'revisions', 'rev1'), {
      movement_id: 'tmNew',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'template_scored',
      spec: templateSpec({
        requiredProp: 'shaker',
        assessment: { ...assessmentSpec(), prop: 'shaker' },
      }),
      created_at: serverTimestamp(),
    });
    batch.set(doc(db, 'teacher_movements', 'tmNew'), {
      teacher_id: 'teacher',
      title: 'Classroom Wrist Stall',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('5 unknown template denied', async () => {
    await seedClassroom();
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tmNew', 'revisions', 'rev1'), {
      movement_id: 'tmNew',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'template_scored',
      spec: templateSpec({
        assessment: { ...assessmentSpec(), template_id: 'balance_stall.grip_v1' },
      }),
      created_at: serverTimestamp(),
    });
    batch.set(doc(db, 'teacher_movements', 'tmNew'), {
      teacher_id: 'teacher',
      title: 'Classroom Wrist Stall',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('6 extra threshold denied', async () => {
    await seedClassroom();
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tmNew', 'revisions', 'rev1'), {
      movement_id: 'tmNew',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'template_scored',
      spec: templateSpec({
        assessment: assessmentSpec({ extra: { threshold: 0.42 } }),
      }),
      created_at: serverTimestamp(),
    });
    batch.set(doc(db, 'teacher_movements', 'tmNew'), {
      teacher_id: 'teacher',
      title: 'Classroom Wrist Stall',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('7 eval/code field denied', async () => {
    await seedClassroom();
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tmNew', 'revisions', 'rev1'), {
      movement_id: 'tmNew',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'template_scored',
      spec: templateSpec({
        assessment: assessmentSpec({ extra: { eval: '1+1', code: 'pass' } }),
      }),
      created_at: serverTimestamp(),
    });
    batch.set(doc(db, 'teacher_movements', 'tmNew'), {
      teacher_id: 'teacher',
      title: 'Classroom Wrist Stall',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('8 invalid laterality denied', async () => {
    await seedClassroom();
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tmNew', 'revisions', 'rev1'), {
      movement_id: 'tmNew',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'template_scored',
      spec: templateSpec({ assessment: assessmentSpec({ laterality: 'both' }) }),
      created_at: serverTimestamp(),
    });
    batch.set(doc(db, 'teacher_movements', 'tmNew'), {
      teacher_id: 'teacher',
      title: 'Classroom Wrist Stall',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('9 extra wrapper key denied', async () => {
    await seedClassroom();
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tmNew', 'revisions', 'rev1'), {
      movement_id: 'tmNew',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'template_scored',
      spec: templateSpec({ extra: { formula: 'x+1' } }),
      created_at: serverTimestamp(),
    });
    batch.set(doc(db, 'teacher_movements', 'tmNew'), {
      teacher_id: 'teacher',
      title: 'Classroom Wrist Stall',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('10 assessment_mode/spec mismatch denied', async () => {
    await seedClassroom();
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(doc(db, 'teacher_movements', 'tmNew', 'revisions', 'rev1'), {
      movement_id: 'tmNew',
      teacher_id: 'teacher',
      schema_version: 1,
      assessment_mode: 'template_scored',
      spec: teacherReviewedSpec(),
      created_at: serverTimestamp(),
    });
    batch.set(doc(db, 'teacher_movements', 'tmNew'), {
      teacher_id: 'teacher',
      title: 'Classroom Wrist Stall',
      status: 'active',
      current_revision_id: 'rev1',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });
});

describe('Phase 7E template assignments', () => {
  test('11 valid Teacher template assignment', async () => {
    await seedClassroom();
    await seedTemplateMovement();
    const db = context('teacher').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'group_assignments', 'asgTpl'), templateAssignmentDoc()),
    );
  });

  test('12 frozen assessment_spec exact', async () => {
    await seedClassroom();
    await seedTemplateMovement();
    const db = context('teacher').firestore();
    await assertSucceeds(
      setDoc(
        doc(db, 'group_assignments', 'asgTpl'),
        templateAssignmentDoc({ assessment: assessmentSpec({ laterality: 'either' }) }),
      ),
    );
    const snap = await getDoc(doc(db, 'group_assignments', 'asgTpl'));
    assert.deepEqual(snap.data().assessment_spec, assessmentSpec());
  });

  test('13 missing assessment_spec denied', async () => {
    await seedClassroom();
    await seedTemplateMovement();
    const db = context('teacher').firestore();
    const payload = templateAssignmentDoc();
    delete payload.assessment_spec;
    await assertFails(setDoc(doc(db, 'group_assignments', 'asgTpl'), payload));
  });

  test('14 forged assessment spec different from revision denied', async () => {
    await seedClassroom();
    await seedTemplateMovement();
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(
        doc(db, 'group_assignments', 'asgTpl'),
        templateAssignmentDoc({ assessment: assessmentSpec({ laterality: 'left' }) }),
      ),
    );
  });

  test('15 forged revision denied', async () => {
    await seedClassroom();
    await seedTemplateMovement();
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(
        doc(db, 'group_assignments', 'asgTpl'),
        templateAssignmentDoc({ revisionId: 'revForged' }),
      ),
    );
  });

  test('16 forged movement denied', async () => {
    await seedClassroom();
    await seedTemplateMovement();
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(
        doc(db, 'group_assignments', 'asgTpl'),
        templateAssignmentDoc({ movementId: 'tmForged' }),
      ),
    );
  });

  test('17 unrelated Teacher denied', async () => {
    await seedClassroom();
    await seedTemplateMovement();
    const db = context('other').firestore();
    await assertFails(
      setDoc(doc(db, 'group_assignments', 'asgTpl'), templateAssignmentDoc()),
    );
  });

  test('18 inactive group denied', async () => {
    await seedClassroom({ includeInactiveGroup: true });
    await seedTemplateMovement();
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(
        doc(db, 'group_assignments', 'asgTpl'),
        {
          ...templateAssignmentDoc(),
          group_id: INACTIVE_GROUP,
          group_name: 'Archived class',
        },
      ),
    );
  });

  test('19 teacher_reviewed assignment with template spec denied', async () => {
    await seedClassroom();
    await seedTeacherReviewedMovement();
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(doc(db, 'group_assignments', 'asgBad'), {
        teacher_id: 'teacher',
        group_id: GROUP_ID,
        movement_id: 'tmRev',
        revision_id: 'rev1',
        origin: 'teacher_created',
        assessment_mode: 'teacher_reviewed',
        status: 'active',
        display_title: 'Tin Balance',
        teacher_display_name: 'Grace Hopper',
        group_name: 'BSHM 4A',
        display_instructions: 'Hold the tin upright.',
        allowed_prop: 'bottle',
        assessment_spec: assessmentSpec(),
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('20 official assignment with template spec denied', async () => {
    await seedClassroom();
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(doc(db, 'group_assignments', 'asgOff'), {
        teacher_id: 'teacher',
        group_id: GROUP_ID,
        movement_id: 'official_hand_stall',
        revision_id: 'official_hand_stall_v1',
        origin: 'official_elixr',
        assessment_mode: 'official_guided',
        status: 'active',
        display_title: 'Hand Stall',
        teacher_display_name: 'Grace Hopper',
        group_name: 'BSHM 4A',
        official_movement_name: 'Hand Stall',
        assessment_spec: assessmentSpec(),
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      }),
    );
  });
});

describe('Phase 7E template_score attempts', () => {
  test('21 approved Trainee valid create', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'assignment_attempts', 'template_score_ok1'), templateScore()),
    );
  });

  test('22 unrelated Trainee denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('otherTrainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({ traineeId: 'otherTrainee' }),
      ),
    );
  });

  test('23 no/removed membership denied', async () => {
    await seedClassroom({ membershipStatus: null });
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(doc(db, 'assignment_attempts', 'template_score_ok1'), templateScore()),
    );
  });

  test('24 awards_global_xp=true denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({ awardsGlobalXp: true }),
      ),
    );
  });

  test('25 wrong Teacher denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({ teacherId: 'other' }),
      ),
    );
  });

  test('26 wrong group denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({ groupId: 'group-other' }),
      ),
    );
  });

  test('27 wrong assignment denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({ assignmentId: 'asgOther' }),
      ),
    );
  });

  test('28 wrong movement denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({ movementId: 'tmOther' }),
      ),
    );
  });

  test('29 wrong revision denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({ revisionId: 'revOther' }),
      ),
    );
  });

  test('30 teacher_reviewed assignment template_score denied', async () => {
    await seedClassroom();
    await seedTeacherReviewedMovement();
    await seedBypassingRules(async (admin) => {
      await setDoc(doc(admin, 'group_assignments', 'asgRev'), {
        teacher_id: 'teacher',
        group_id: GROUP_ID,
        movement_id: 'tmRev',
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
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({
          assignmentId: 'asgRev',
          movementId: 'tmRev',
        }),
      ),
    );
  });

  test('31 official assignment template_score denied', async () => {
    await seedClassroom();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({
          assignmentId: 'asgOfficial',
          movementId: 'official_hand_stall',
          revisionId: 'official_hand_stall_v1',
        }),
      ),
    );
  });

  test('32 status != submitted denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({ status: 'draft' }),
      ),
    );
  });

  test('33 missing rubric denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    const payload = templateScore();
    delete payload.rubric;
    delete payload.rubric_total;
    delete payload.performance_level;
    delete payload.assessment_version;
    await assertFails(
      setDoc(doc(db, 'assignment_attempts', 'template_score_ok1'), payload),
    );
  });

  test('34 rubric out of range denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({
          extra: rubricFields({ technique: 4, stability: 2, completion: 3, propPositioning: 2 }),
        }),
      ),
    );
  });

  test('35 forged performance level denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({
          extra: rubricFields({ performanceLevel: 'mastered' }),
        }),
      ),
    );
  });

  test('36 prop_type=shaker denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({ propType: 'shaker' }),
      ),
    );
  });

  test('37 video fields denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({
          extra: {
            video_storage_path: 'assignment_submissions/x.mp4',
            video_content_type: 'video/mp4',
          },
        }),
      ),
    );
  });

  test('38 review fields denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({
          extra: {
            review_verdict: 'approved',
            review_feedback: 'Nice work.',
          },
        }),
      ),
    );
  });

  test('39 source_session_id denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', 'template_score_ok1'),
        templateScore({ extra: { source_session_id: 'sess-1' } }),
      ),
    );
  });

  test('40 Teacher cannot create score for Trainee', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(doc(db, 'assignment_attempts', 'template_score_ok1'), templateScore()),
    );
  });

  test('41 unrelated Teacher cannot read', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    await seedBypassingRules(async (admin) => {
      await setDoc(
        doc(admin, 'assignment_attempts', 'template_score_ok1'),
        {
          ...templateScore(),
          created_at: Timestamp.now(),
          completed_at: Timestamp.now(),
        },
      );
    });
    await assertFails(
      getDoc(doc(context('other').firestore(), 'assignment_attempts', 'template_score_ok1')),
    );
  });

  test('42 assigning Teacher can read', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    await seedBypassingRules(async (admin) => {
      await setDoc(
        doc(admin, 'assignment_attempts', 'template_score_ok1'),
        {
          ...templateScore(),
          created_at: Timestamp.now(),
          completed_at: Timestamp.now(),
        },
      );
    });
    await assertSucceeds(
      getDoc(doc(context('teacher').firestore(), 'assignment_attempts', 'template_score_ok1')),
    );
  });

  test('43 owner Trainee can read', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    await seedBypassingRules(async (admin) => {
      await setDoc(
        doc(admin, 'assignment_attempts', 'template_score_ok1'),
        {
          ...templateScore(),
          created_at: Timestamp.now(),
          completed_at: Timestamp.now(),
        },
      );
    });
    await assertSucceeds(
      getDoc(doc(context('trainee').firestore(), 'assignment_attempts', 'template_score_ok1')),
    );
  });

  test('44 update score denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'assignment_attempts', 'template_score_ok1'), templateScore()),
    );
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', 'template_score_ok1'), {
        duration_seconds: 99,
      }),
    );
  });

  test('45 rewrite rubric denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'assignment_attempts', 'template_score_ok1'), templateScore()),
    );
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', 'template_score_ok1'), {
        rubric_total: 12,
        performance_level: 'mastered',
      }),
    );
  });

  test('46 change awards_global_xp denied', async () => {
    await seedClassroom();
    await seedTemplateAssignment();
    const db = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(db, 'assignment_attempts', 'template_score_ok1'), templateScore()),
    );
    await assertFails(
      updateDoc(doc(db, 'assignment_attempts', 'template_score_ok1'), {
        awards_global_xp: true,
      }),
    );
  });
});
