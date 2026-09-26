import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  doc,
  deleteDoc,
  getDoc,
  serverTimestamp,
  setDoc,
  updateDoc,
  writeBatch,
  Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = 'demo-elixr';
const GROUP_ID = 'custom-group';
const TEACHER_MOVEMENT_ID = 'custom-teacher-move';
const TEACHER_REVISION_ID = 'custom-teacher-rev-1';
const TRAINEE_MOVEMENT_ID = 'custom-trainee-move';
const TRAINEE_REVISION_ID = 'custom-trainee-rev-1';
const ASSIGNMENT_ID = 'custom-assignment';

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
    await setDoc(doc(db, 'users', 'other-trainee'), {
      full_name: 'Other Trainee',
      role: 'Trainee',
    });
    await setDoc(doc(db, 'groups', GROUP_ID), {
      teacher_id: 'teacher',
      name: 'Reference Lab',
      status: 'active',
      schema_version: 2,
      created_at: Timestamp.now(),
      updated_at: Timestamp.now(),
    });
    await setDoc(doc(db, 'group_memberships', `${GROUP_ID}_trainee`), {
      group_id: GROUP_ID,
      teacher_id: 'teacher',
      trainee_id: 'trainee',
      status: 'approved',
    });
  });
});

after(async () => {
  await testEnv.cleanup();
});

function context(uid, teacherClaim = uid === 'teacher') {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: true,
    ...(teacherClaim ? { role: 'Teacher' } : {}),
  });
}

function template(overrides = {}) {
  return {
    schema_version: 1,
    capture_version: 1,
    duration_ms: 6000,
    reference_count: 3,
    required_modalities: ['pose', 'hands', 'prop_translation'],
    normalization_metadata: {
      anchor: 'shoulder_midpoint',
      scale: 'shoulder_width',
      mirrored: false,
    },
    feature_capabilities: {
      pose: true,
      hands: true,
      prop_translation: true,
      release_catch: true,
      prop_rotation: false,
    },
    canonical_sequence: [
      { timestamp_ms: 0, pose: {} },
      { timestamp_ms: 6000, pose: {} },
    ],
    variability_metadata: { duration_std_ms: 80 },
    prop_events: [],
    ...overrides,
  };
}

function rotationTemplate() {
  return template({
    schema_version: 2,
    canonical_sequence: Array.from({ length: 32 }, (_, index) => ({
      timestamp_ms: index * 200, pose: {}, hands: {},
      prop: { x: 0.5, y: 0.5, confidence: 0.9 },
      prop_metadata: {},
    })),
    feature_capabilities: {
      pose: true, hands: true, prop_translation: true,
      release_catch: true, prop_rotation: true,
    },
    rotation_trace: {
      angles_rad: Array.from({ length: 32 }, (_, index) => index * 0.2),
      total_signed_rad: 6.2,
      coverage: 0.95,
      pair_coverage: 0.9,
    },
  });
}

async function createMovement({
  uid,
  ownerRole,
  movementId,
  revisionId,
  name,
  propType = 'bottle',
  movementTemplate = template(),
  referenceImageStoragePath,
}) {
  const db = context(uid).firestore();
  const batch = writeBatch(db);
  batch.set(doc(db, 'custom_movements', movementId, 'revisions', revisionId), {
    movement_id: movementId,
    owner_uid: uid,
    owner_role: ownerRole,
    schema_version: 1,
    template: movementTemplate,
    created_at: serverTimestamp(),
  });
  batch.set(doc(db, 'custom_movements', movementId), {
    owner_uid: uid,
    owner_role: ownerRole,
    name,
    description: 'Three-reference automatic movement',
    difficulty: 'Hard',
    prop_type: propType,
    status: 'active',
    active_revision_id: revisionId,
    schema_version: 1,
    ...(referenceImageStoragePath
      ? { reference_image_storage_path: referenceImageStoragePath }
      : {}),
    created_at: serverTimestamp(),
    updated_at: serverTimestamp(),
  });
  await batch.commit();
}

async function createTeacherAssignment(movementTemplate = template()) {
  const db = context('teacher').firestore();
  await setDoc(doc(db, 'group_assignments', ASSIGNMENT_ID), {
    teacher_id: 'teacher',
    group_id: GROUP_ID,
    movement_id: TEACHER_MOVEMENT_ID,
    revision_id: TEACHER_REVISION_ID,
    origin: 'teacher_created',
    assessment_mode: 'reference_matched',
    status: 'active',
    display_title: 'Teacher Cascade',
    display_instructions: 'Three-reference automatic movement',
    allowed_prop: 'bottle',
    teacher_display_name: 'Grace Hopper',
    group_name: 'Reference Lab',
    audience_type: 'entire_class',
    attempt_policy: { type: 'finite', maximum_attempts: 3 },
    max_score: 12,
    movement_template: movementTemplate,
    created_at: serverTimestamp(),
    updated_at: serverTimestamp(),
  });
}

describe('custom movement v1 ownership and revisions', () => {
  test('validated version-two rotation trace is allowed without weakening ownership', async () => {
    const rotating = rotationTemplate();
    await assertSucceeds(createMovement({
      uid: 'trainee', ownerRole: 'trainee', movementId: 'rotation-move',
      revisionId: 'rotation-rev', name: 'Projected turn',
      movementTemplate: rotating,
    }));
    await assertFails(getDoc(doc(
      context('other-trainee', false).firestore(),
      'custom_movements', 'rotation-move',
    )));
    await assertFails(createMovement({
      uid: 'trainee', ownerRole: 'trainee', movementId: 'missing-trace',
      revisionId: 'missing-rev', name: 'Invalid turn',
      movementTemplate: template({
        schema_version: 2,
        feature_capabilities: rotating.feature_capabilities,
      }),
    }));
  });
  test('trainee creates an atomic private movement and cannot mutate revision', async () => {
    await assertSucceeds(
      createMovement({
        uid: 'trainee',
        ownerRole: 'trainee',
        movementId: TRAINEE_MOVEMENT_ID,
        revisionId: TRAINEE_REVISION_ID,
        name: 'My Cascade',
      }),
    );
    await assertFails(
      getDoc(
        doc(
          context('other-trainee', false).firestore(),
          'custom_movements',
          TRAINEE_MOVEMENT_ID,
        ),
      ),
    );
    await assertFails(
      updateDoc(
        doc(
          context('trainee', false).firestore(),
          'custom_movements',
          TRAINEE_MOVEMENT_ID,
          'revisions',
          TRAINEE_REVISION_ID,
        ),
        { template: template({ duration_ms: 7000 }) },
      ),
    );
  });

  test('revision scope preserves private reads and atomic root linkage', async () => {
    await assertSucceeds(createMovement({
      uid: 'trainee', ownerRole: 'trainee', movementId: TRAINEE_MOVEMENT_ID,
      revisionId: TRAINEE_REVISION_ID, name: 'My Cascade',
    }));
    const owner = context('trainee', false).firestore();
    const revision = (db, movementId = TRAINEE_MOVEMENT_ID,
      revisionId = TRAINEE_REVISION_ID) => doc(
      db, 'custom_movements', movementId, 'revisions', revisionId,
    );
    const snapshot = await assertSucceeds(getDoc(revision(owner)));
    for (const uid of ['other-trainee', 'teacher']) {
      await assertFails(getDoc(revision(context(uid).firestore())));
    }
    await assertFails(deleteDoc(revision(owner)));
    // A new revision must be selected by the root in the same atomic write.
    await assertFails(setDoc(revision(owner, TRAINEE_MOVEMENT_ID, 'unlinked'), {
      ...snapshot.data(), created_at: serverTimestamp(),
    }));
    await assertFails(setDoc(revision(owner, 'wrong-parent'), {
      ...snapshot.data(), created_at: serverTimestamp(),
    }));
    await assertFails(setDoc(doc(owner, 'custom_movements', TRAINEE_MOVEMENT_ID,
      'revisions', TRAINEE_REVISION_ID, 'extra', 'nested'), {owner_uid: 'trainee'}));
  });

  test('reference image path must match its owner and root revision', async () => {
    await assertSucceeds(createMovement({
      uid: 'trainee',
      ownerRole: 'trainee',
      movementId: 'image-path-move',
      revisionId: 'image-path-rev',
      name: 'Reference image move',
      referenceImageStoragePath:
        'users/trainee/custom_movement_references/image-path-move_image-path-rev.jpg',
    }));

    await assertFails(createMovement({
      uid: 'trainee',
      ownerRole: 'trainee',
      movementId: 'wrong-image-owner-move',
      revisionId: 'wrong-image-owner-rev',
      name: 'Wrong image owner',
      referenceImageStoragePath:
        'users/other-trainee/custom_movement_references/wrong-image-owner-move_wrong-image-owner-rev.jpg',
    }));
    await assertFails(createMovement({
      uid: 'trainee',
      ownerRole: 'trainee',
      movementId: 'wrong-image-revision-move',
      revisionId: 'right-image-rev',
      name: 'Wrong image revision',
      referenceImageStoragePath:
        'users/trainee/custom_movement_references/wrong-image-revision-move_wrong-image-rev.jpg',
    }));

    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const db = admin.firestore();
      for (const [movementId, revisionId] of [
        ['wrong-image-owner-move', 'wrong-image-owner-rev'],
        ['wrong-image-revision-move', 'right-image-rev'],
      ]) {
        const root = await getDoc(doc(db, 'custom_movements', movementId));
        const revision = await getDoc(doc(
          db, 'custom_movements', movementId, 'revisions', revisionId,
        ));
        if (root.exists() || revision.exists()) {
          throw new Error('A denied custom movement batch left partial data.');
        }
      }
    });
  });

  test('owner archives without deleting immutable history', async () => {
    await createMovement({
      uid: 'trainee',
      ownerRole: 'trainee',
      movementId: 'archive-move',
      revisionId: 'archive-rev',
      name: 'Archive this movement',
    });

    const ownerDb = context('trainee', false).firestore();
    const otherDb = context('other-trainee', false).firestore();
    const root = doc(ownerDb, 'custom_movements', 'archive-move');
    const revision = doc(
      ownerDb,
      'custom_movements',
      'archive-move',
      'revisions',
      'archive-rev',
    );
    await assertFails(updateDoc(
      doc(otherDb, 'custom_movements', 'archive-move'),
      { status: 'archived', updated_at: serverTimestamp() },
    ));
    await assertSucceeds(updateDoc(root, {
      status: 'archived',
      updated_at: serverTimestamp(),
    }));

    const archived = await assertSucceeds(getDoc(root));
    if (archived.data()?.status !== 'archived') {
      throw new Error('Owner archive did not persist the archived state.');
    }
    const historicalRevision = await assertSucceeds(getDoc(revision));
    if (!historicalRevision.exists()) {
      throw new Error('Archiving removed the immutable movement revision.');
    }
    await assertFails(updateDoc(revision, {
      template: template({ duration_ms: 7000 }),
    }));
    await assertFails(deleteDoc(root));
  });

  test('unsupported prop rotation and role spoofing are denied', async () => {
    const db = context('trainee', false).firestore();
    const batch = writeBatch(db);
    batch.set(
      doc(db, 'custom_movements', 'bad-move', 'revisions', 'bad-rev'),
      {
        movement_id: 'bad-move',
        owner_uid: 'trainee',
        owner_role: 'teacher',
        schema_version: 1,
        template: template({
          feature_capabilities: {
            pose: true,
            hands: true,
            prop_translation: true,
            release_catch: true,
            prop_rotation: true,
          },
        }),
        created_at: serverTimestamp(),
      },
    );
    batch.set(doc(db, 'custom_movements', 'bad-move'), {
      owner_uid: 'trainee',
      owner_role: 'teacher',
      name: 'Spoofed',
      description: '',
      difficulty: 'Easy',
      prop_type: 'bottle',
      status: 'active',
      active_revision_id: 'bad-rev',
      schema_version: 1,
      created_at: serverTimestamp(),
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('dual-prop custom movement is denied until two tracks are supported', async () => {
    await assertFails(
      createMovement({
        uid: 'trainee',
        ownerRole: 'trainee',
        movementId: 'dual-prop-move',
        revisionId: 'dual-prop-rev',
        name: 'Dual cascade',
        propType: 'bottle_and_shaker',
      }),
    );
  });
});

describe('teacher reference assignments', () => {
  beforeEach(async () => {
    await createMovement({
      uid: 'teacher',
      ownerRole: 'teacher',
      movementId: TEACHER_MOVEMENT_ID,
      revisionId: TEACHER_REVISION_ID,
      name: 'Teacher Cascade',
    });
  });

  test('teacher assigns the exact active immutable revision', async () => {
    await assertSucceeds(createTeacherAssignment());
    const saved = await assertSucceeds(
      getDoc(
        doc(context('trainee', false).firestore(), 'group_assignments', ASSIGNMENT_ID),
      ),
    );
    if (saved.data().assessment_mode !== 'reference_matched') {
      throw new Error('reference assignment was not saved');
    }
  });

  test('authorized trainee result is private and never awards global XP', async () => {
    await createTeacherAssignment();
    const db = context('trainee', false).firestore();
    const payload = {
      trainee_id: 'trainee',
      teacher_id: 'teacher',
      group_id: GROUP_ID,
      assignment_id: ASSIGNMENT_ID,
      movement_id: TEACHER_MOVEMENT_ID,
      revision_id: TEACHER_REVISION_ID,
      origin: 'teacher_created',
      assessment_mode: 'reference_matched',
      attempt_kind: 'reference_match',
      status: 'submitted',
      awards_global_xp: false,
      reference_total: 10,
      reference_max_total: 12,
      reference_component_scores: {
        'Body technique': 3,
        'Hand technique': 2,
        'Prop path': 3,
        Timing: 2,
        'Control/stability': 2,
      },
      performance_level: 'proficient',
      prop_type: 'bottle',
      created_at: serverTimestamp(),
      completed_at: serverTimestamp(),
    };
    await assertSucceeds(
      setDoc(
        doc(db, 'assignment_attempts', `custom_${ASSIGNMENT_ID}_trainee_1`),
        payload,
      ),
    );
    await assertFails(
      setDoc(
        doc(db, 'assignment_attempts', `custom_${ASSIGNMENT_ID}_trainee_2`),
        {
          ...payload,
          reference_total: 12,
          performance_level: 'mastered',
        },
      ),
    );
    await assertFails(
      setDoc(doc(db, 'assignment_attempts', 'forged-xp-attempt'), {
        ...payload,
        awards_global_xp: true,
      }),
    );
  });
});
