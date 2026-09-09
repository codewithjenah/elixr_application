import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import assert from 'node:assert/strict';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  getDoc,
  serverTimestamp,
  writeBatch,
} from 'firebase/firestore';

const PROJECT_ID = 'demo-elixr';
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

function context(uid, {
  emailVerified = true,
  teacherClaim = uid === 'teacher' || uid === 'other-teacher',
  email = `${uid}@example.com`,
} = {}) {
  return testEnv.authenticatedContext(uid, {
    email,
    email_verified: emailVerified,
    ...(teacherClaim ? { role: 'Teacher' } : {}),
  });
}

// Exact default Teacher Review assessment produced by
// TeacherActivityAssessmentConfig.newActivityDefaults() /
// TeacherActivityRubric.builtIn(standardTechnique, 50).
function flutterDefaultActivityAssessment() {
  return {
    schema_version: 3,
    readiness: { hands: 'none', body: 'none' },
    rubric: {
      template_id: 'standard_technique',
      maximum_score: 50,
      criteria: [
        {
          id: 'setup',
          label: 'Setup',
          description: 'Uses the required setup and starting position.',
          maximum_points: 10,
          weight: 20,
        },
        {
          id: 'technique',
          label: 'Technique',
          description: 'Performs the demonstrated technique safely and accurately.',
          maximum_points: 20,
          weight: 40,
        },
        {
          id: 'control',
          label: 'Control',
          description: 'Maintains deliberate control of props and body position.',
          maximum_points: 13,
          weight: 25,
        },
        {
          id: 'finish',
          label: 'Finish',
          description: 'Completes the movement with a stable, intentional finish.',
          maximum_points: 7,
          weight: 15,
        },
      ],
    },
    recording_duration_seconds: 30,
  };
}

function flutterTeacherReviewRevision({
  movementId,
  teacherId = 'teacher',
} = {}) {
  return {
    movement_id: movementId,
    teacher_id: teacherId,
    schema_version: 2,
    assessment_mode: 'teacher_reviewed',
    spec: {
      instructions: 'Balance the tin upright.',
      required_prop: 'bottle',
      capability: 'teacher_review_only',
      activity_assessment: flutterDefaultActivityAssessment(),
    },
    created_at: serverTimestamp(),
  };
}

function flutterWristStallRevision({
  movementId,
  teacherId = 'teacher',
  laterality = 'left',
  extraAssessmentKeys = {},
} = {}) {
  return {
    movement_id: movementId,
    teacher_id: teacherId,
    schema_version: 1,
    assessment_mode: 'template_scored',
    spec: {
      instructions: `Balance the bottle on the ${laterality} wrist.`,
      required_prop: 'bottle',
      assessment: {
        schema_version: 1,
        template_id: 'balance_stall.wrist_v1',
        prop: 'bottle',
        target: 'wrist',
        laterality,
        ...extraAssessmentKeys,
      },
    },
    created_at: serverTimestamp(),
  };
}

function flutterMovementRoot({
  teacherId = 'teacher',
  title,
  currentRevisionId,
} = {}) {
  return {
    teacher_id: teacherId,
    title,
    status: 'active',
    current_revision_id: currentRevisionId,
    schema_version: 1,
    created_at: serverTimestamp(),
    updated_at: serverTimestamp(),
  };
}

function commitCreateBatch(db, {
  movementId,
  revisionId,
  revision,
  root,
}) {
  const batch = writeBatch(db);
  batch.set(
    doc(db, 'teacher_movements', movementId, 'revisions', revisionId),
    revision,
  );
  batch.set(doc(db, 'teacher_movements', movementId), root);
  return batch.commit();
}

describe('Teacher Activity create batch from FirebaseTeacherMovementRepository', () => {
  test('verified Teacher can create a Teacher Review movement', async () => {
    const db = context('teacher').firestore();
    const movementId = 'tmTeacherReview';
    const revisionId = 'revTeacherReview';
    await assertSucceeds(
      commitCreateBatch(db, {
        movementId,
        revisionId,
        revision: flutterTeacherReviewRevision({ movementId }),
        root: flutterMovementRoot({
          title: 'Tin Balance',
          currentRevisionId: revisionId,
        }),
      }),
    );

    const root = await getDoc(doc(db, 'teacher_movements', movementId));
    const revision = await getDoc(
      doc(db, 'teacher_movements', movementId, 'revisions', revisionId),
    );
    assert.equal(root.data().current_revision_id, revisionId);
    assert.equal(root.data().schema_version, 1);
    assert.equal(root.data().status, 'active');
    assert.equal(root.data().teacher_id, 'teacher');
    assert.equal(revision.data().schema_version, 2);
    assert.equal(revision.data().assessment_mode, 'teacher_reviewed');
    assert.equal(revision.data().spec.capability, 'teacher_review_only');
    assert.equal(revision.data().spec.activity_assessment.schema_version, 3);
    assert.equal(
      revision.data().spec.activity_assessment.rubric.template_id,
      'standard_technique',
    );
  });

  test('verified Teacher can create Automatic Wrist Stall Left', async () => {
    const db = context('teacher').firestore();
    const movementId = 'tmWristLeft';
    const revisionId = 'revWristLeft';
    await assertSucceeds(
      commitCreateBatch(db, {
        movementId,
        revisionId,
        revision: flutterWristStallRevision({
          movementId,
          laterality: 'left',
        }),
        root: flutterMovementRoot({
          title: 'Classroom Wrist Stall',
          currentRevisionId: revisionId,
        }),
      }),
    );

    const revision = await getDoc(
      doc(db, 'teacher_movements', movementId, 'revisions', revisionId),
    );
    assert.equal(revision.data().assessment_mode, 'template_scored');
    assert.equal(revision.data().spec.assessment.template_id, 'balance_stall.wrist_v1');
    assert.equal(revision.data().spec.assessment.prop, 'bottle');
    assert.equal(revision.data().spec.assessment.target, 'wrist');
    assert.equal(revision.data().spec.assessment.laterality, 'left');
  });

  test('verified Teacher can create Automatic Wrist Stall Right', async () => {
    const db = context('teacher').firestore();
    const movementId = 'tmWristRight';
    const revisionId = 'revWristRight';
    await assertSucceeds(
      commitCreateBatch(db, {
        movementId,
        revisionId,
        revision: flutterWristStallRevision({
          movementId,
          laterality: 'right',
        }),
        root: flutterMovementRoot({
          title: 'Classroom Wrist Stall Right',
          currentRevisionId: revisionId,
        }),
      }),
    );
    const revision = await getDoc(
      doc(db, 'teacher_movements', movementId, 'revisions', revisionId),
    );
    assert.equal(revision.data().spec.assessment.laterality, 'right');
  });

  test('template laterality either is rejected for new writes', async () => {
    const db = context('teacher').firestore();
    const movementId = 'tmWristEither';
    const revisionId = 'revWristEither';
    await assertFails(
      commitCreateBatch(db, {
        movementId,
        revisionId,
        revision: flutterWristStallRevision({
          movementId,
          laterality: 'either',
        }),
        root: flutterMovementRoot({
          title: 'Either Wrist Stall',
          currentRevisionId: revisionId,
        }),
      }),
    );
  });

  test('malformed assessment spec is rejected', async () => {
    const db = context('teacher').firestore();
    const movementId = 'tmWristMalformed';
    const revisionId = 'revWristMalformed';
    await assertFails(
      commitCreateBatch(db, {
        movementId,
        revisionId,
        revision: flutterWristStallRevision({
          movementId,
          laterality: 'left',
          extraAssessmentKeys: { threshold: 0.4 },
        }),
        root: flutterMovementRoot({
          title: 'Malformed Wrist Stall',
          currentRevisionId: revisionId,
        }),
      }),
    );
  });

  test('Trainee is rejected', async () => {
    const db = context('trainee', { teacherClaim: false }).firestore();
    const movementId = 'tmTrainee';
    const revisionId = 'revTrainee';
    await assertFails(
      commitCreateBatch(db, {
        movementId,
        revisionId,
        revision: flutterTeacherReviewRevision({ movementId }),
        root: flutterMovementRoot({
          title: 'Tin Balance',
          currentRevisionId: revisionId,
        }),
      }),
    );
  });

  test('unverified Teacher is rejected', async () => {
    const db = context('teacher', { emailVerified: false }).firestore();
    const movementId = 'tmUnverified';
    const revisionId = 'revUnverified';
    await assertFails(
      commitCreateBatch(db, {
        movementId,
        revisionId,
        revision: flutterTeacherReviewRevision({ movementId }),
        root: flutterMovementRoot({
          title: 'Tin Balance',
          currentRevisionId: revisionId,
        }),
      }),
    );
  });

  test('mismatched teacher_id is rejected', async () => {
    const db = context('teacher').firestore();
    const movementId = 'tmMismatch';
    const revisionId = 'revMismatch';
    await assertFails(
      commitCreateBatch(db, {
        movementId,
        revisionId,
        revision: flutterTeacherReviewRevision({
          movementId,
          teacherId: 'other-teacher',
        }),
        root: flutterMovementRoot({
          teacherId: 'other-teacher',
          title: 'Tin Balance',
          currentRevisionId: revisionId,
        }),
      }),
    );
  });

  test('root pointing to a different revision is rejected', async () => {
    const db = context('teacher').firestore();
    const movementId = 'tmWrongPointer';
    const revisionId = 'revActual';
    await assertFails(
      commitCreateBatch(db, {
        movementId,
        revisionId,
        revision: flutterTeacherReviewRevision({ movementId }),
        root: flutterMovementRoot({
          title: 'Tin Balance',
          currentRevisionId: 'revOther',
        }),
      }),
    );
  });

  test('revision not included atomically is rejected', async () => {
    const db = context('teacher').firestore();
    const movementId = 'tmRootOnly';
    const revisionId = 'revMissing';
    await assertFails(
      writeBatch(db)
        .set(
          doc(db, 'teacher_movements', movementId),
          flutterMovementRoot({
            title: 'Tin Balance',
            currentRevisionId: revisionId,
          }),
        )
        .commit(),
    );
  });

  test('revision without matching root pointer is rejected', async () => {
    const db = context('teacher').firestore();
    const movementId = 'tmRevisionOnly';
    const revisionId = 'revOrphan';
    await assertFails(
      writeBatch(db)
        .set(
          doc(db, 'teacher_movements', movementId, 'revisions', revisionId),
          flutterTeacherReviewRevision({ movementId }),
        )
        .commit(),
    );
  });
});
