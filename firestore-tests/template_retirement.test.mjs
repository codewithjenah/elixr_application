import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  deleteDoc,
  doc,
  getDoc,
  serverTimestamp,
  setDoc,
  Timestamp,
  updateDoc,
  writeBatch,
} from 'firebase/firestore';

const PROJECT_ID = 'demo-elixr';
const GROUP_ID = 'group-history';
const MOVEMENT_ID = 'movement-history';
const REVISION_ID = 'revision-history';
const ASSIGNMENT_ID = 'assignment-history';
const ATTEMPT_ID = 'attempt-history';
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

function context(uid) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: true,
  });
}

async function seedBypassingRules(fn) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await fn(admin.firestore());
  });
}

function historicalRevision() {
  return {
    movement_id: MOVEMENT_ID,
    teacher_id: 'teacher',
    schema_version: 1,
    assessment_mode: 'template_scored',
    spec: {
      instructions: 'Balance the bottle on the wrist.',
      required_prop: 'bottle',
      assessment: {
        schema_version: 1,
        template_id: 'balance_stall.wrist_v1',
        prop: 'bottle',
        target: 'wrist',
        laterality: 'either',
      },
    },
    created_at: Timestamp.now(),
  };
}

function historicalAssignment() {
  return {
    teacher_id: 'teacher',
    group_id: GROUP_ID,
    movement_id: MOVEMENT_ID,
    revision_id: REVISION_ID,
    origin: 'teacher_created',
    assessment_mode: 'template_scored',
    status: 'active',
    display_title: 'Classroom Wrist Stall',
    teacher_display_name: 'Grace Hopper',
    group_name: 'History Class',
    display_instructions: 'Balance the bottle on the wrist.',
    allowed_prop: 'bottle',
    assessment_spec: {
      schema_version: 1,
      template_id: 'balance_stall.wrist_v1',
      prop: 'bottle',
      target: 'wrist',
      laterality: 'either',
    },
    created_at: Timestamp.now(),
    updated_at: Timestamp.now(),
  };
}

function historicalAttempt() {
  return {
    trainee_id: 'trainee',
    teacher_id: 'teacher',
    group_id: GROUP_ID,
    assignment_id: ASSIGNMENT_ID,
    movement_id: MOVEMENT_ID,
    revision_id: REVISION_ID,
    origin: 'teacher_created',
    assessment_mode: 'template_scored',
    attempt_kind: 'template_score',
    status: 'submitted',
    awards_global_xp: false,
    assessment_version: 2,
    rubric: {
      technique: 3,
      stability: 2,
      completion: 3,
      prop_positioning: 2,
    },
    rubric_total: 10,
    performance_level: 'proficient',
    duration_seconds: 11,
    prop_type: 'bottle',
    created_at: Timestamp.now(),
    completed_at: Timestamp.now(),
  };
}

async function seedHistoricalRecords() {
  await seedBypassingRules(async (db) => {
    await setDoc(doc(db, 'users', 'teacher'), {
      full_name: 'Grace Hopper',
      role: 'Teacher',
    });
    await setDoc(doc(db, 'users', 'trainee'), {
      full_name: 'Ada Lovelace',
      role: 'Trainee',
    });
    await setDoc(doc(db, 'users', 'other-teacher'), {
      full_name: 'Other Teacher',
      role: 'Teacher',
    });
    await setDoc(doc(db, 'groups', GROUP_ID), {
      teacher_id: 'teacher',
      name: 'History Class',
      status: 'active',
      schema_version: 1,
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    await setDoc(doc(db, 'group_memberships', `${GROUP_ID}_trainee`), {
      group_id: GROUP_ID,
      teacher_id: 'teacher',
      trainee_id: 'trainee',
      status: 'approved',
    });
    await setDoc(
      doc(db, 'teacher_movements', MOVEMENT_ID, 'revisions', REVISION_ID),
      historicalRevision(),
    );
    await setDoc(doc(db, 'teacher_movements', MOVEMENT_ID), {
      teacher_id: 'teacher',
      title: 'Classroom Wrist Stall',
      status: 'active',
      current_revision_id: REVISION_ID,
      schema_version: 1,
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    await setDoc(
      doc(db, 'group_assignments', ASSIGNMENT_ID),
      historicalAssignment(),
    );
    await setDoc(
      doc(db, 'assignment_attempts', ATTEMPT_ID),
      historicalAttempt(),
    );
  });
}

describe('retired template records', () => {
  test('authorized users can still read historical movement, assignment, and score', async () => {
    await seedHistoricalRecords();
    const teacherDb = context('teacher').firestore();
    const traineeDb = context('trainee').firestore();

    const revision = await assertSucceeds(
      getDoc(
        doc(
          teacherDb,
          'teacher_movements',
          MOVEMENT_ID,
          'revisions',
          REVISION_ID,
        ),
      ),
    );
    assert.equal(revision.data().assessment_mode, 'template_scored');

    const assignment = await assertSucceeds(
      getDoc(doc(traineeDb, 'group_assignments', ASSIGNMENT_ID)),
    );
    assert.equal(assignment.data().assessment_spec.template_id, 'balance_stall.wrist_v1');

    const attempt = await assertSucceeds(
      getDoc(doc(traineeDb, 'assignment_attempts', ATTEMPT_ID)),
    );
    assert.equal(attempt.data().attempt_kind, 'template_score');
    assert.equal(attempt.data().rubric_total, 10);

    await assertFails(
      getDoc(
        doc(
          context('other-teacher').firestore(),
          'teacher_movements',
          MOVEMENT_ID,
        ),
      ),
    );
  });

  test('historical template movement, assignment, and score are read-only', async () => {
    await seedHistoricalRecords();
    const teacherDb = context('teacher').firestore();
    const traineeDb = context('trainee').firestore();

    await assertFails(
      updateDoc(doc(teacherDb, 'teacher_movements', MOVEMENT_ID), {
        status: 'archived',
        updated_at: serverTimestamp(),
      }),
    );
    await assertFails(
      deleteDoc(
        doc(
          teacherDb,
          'teacher_movements',
          MOVEMENT_ID,
          'revisions',
          REVISION_ID,
        ),
      ),
    );
    await assertFails(
      deleteDoc(doc(teacherDb, 'teacher_movements', MOVEMENT_ID)),
    );

    await assertFails(
      updateDoc(doc(teacherDb, 'group_assignments', ASSIGNMENT_ID), {
        status: 'archived',
        updated_at: serverTimestamp(),
      }),
    );
    await assertFails(
      deleteDoc(doc(teacherDb, 'group_assignments', ASSIGNMENT_ID)),
    );

    await assertFails(
      updateDoc(doc(traineeDb, 'assignment_attempts', ATTEMPT_ID), {
        rubric_total: 12,
      }),
    );
    await assertFails(
      deleteDoc(doc(traineeDb, 'assignment_attempts', ATTEMPT_ID)),
    );
  });
});

describe('retired template writes', () => {
  test('new template revisions are denied', async () => {
    await seedHistoricalRecords();
    const db = context('teacher').firestore();
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'teacher_movements', 'movement-new', 'revisions', 'revision-new'),
      {
        ...historicalRevision(),
        movement_id: 'movement-new',
        created_at: serverTimestamp(),
      },
    );
    batch.set(doc(db, 'teacher_movements', 'movement-new'), {
      teacher_id: 'teacher',
      title: 'New Wrist Stall',
      status: 'active',
      current_revision_id: 'revision-new',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('new template assignments are denied', async () => {
    await seedHistoricalRecords();
    const db = context('teacher').firestore();
    await assertFails(
      setDoc(doc(db, 'group_assignments', 'assignment-new'), {
        ...historicalAssignment(),
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('new template score attempts are denied', async () => {
    await seedHistoricalRecords();
    const db = context('trainee').firestore();
    await assertFails(
      setDoc(doc(db, 'assignment_attempts', 'attempt-new'), {
        ...historicalAttempt(),
        created_at: serverTimestamp(),
        completed_at: serverTimestamp(),
      }),
    );
  });
});
