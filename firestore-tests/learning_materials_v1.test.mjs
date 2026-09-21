import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteField, doc, setDoc, Timestamp } from 'firebase/firestore';
import { getBytes, ref, updateMetadata, uploadBytes } from 'firebase/storage';

const PROJECT_ID = 'demo-elixr';
const ASSIGNMENT_ID = 'assignment-1';
const MATERIAL_ID = 'material-1';
const OTHER_MATERIAL_ID = 'material-2';
const UPLOAD_ID = 'upload-1';
const STAGING_PATH = `activity_material_staging/teacher/${ASSIGNMENT_ID}/${UPLOAD_ID}`;
const FINAL_PATH = `activity_learning_materials/${ASSIGNMENT_ID}/${MATERIAL_ID}`;
const OTHER_FINAL_PATH = `activity_learning_materials/${ASSIGNMENT_ID}/${OTHER_MATERIAL_ID}`;

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1', port: 8080,
    },
    storage: {
      rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1', port: 9199,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    const expires = Timestamp.fromMillis(Date.now() + 10 * 60 * 1000);
    await setDoc(doc(db, 'activity_material_uploads', UPLOAD_ID), {
      upload_id: UPLOAD_ID, material_id: MATERIAL_ID, assignment_id: ASSIGNMENT_ID,
      owner_teacher_id: 'teacher', type: 'pdf', display_name: 'Safety sheet',
      declared_content_type: 'application/pdf', declared_size_bytes: 3,
      staging_path: STAGING_PATH, state: 'staging', schema_version: 1,
      created_at: Timestamp.now(), expires_at: expires,
    });
    await setDoc(doc(db, 'activity_material_access_state', ASSIGNMENT_ID), {
      assignment_id: ASSIGNMENT_ID, generation: 1, state: 'ready',
      revoked_material_ids: [], schema_version: 1, updated_at: Timestamp.now(),
    });
    await setDoc(doc(db, 'group_assignments', ASSIGNMENT_ID,
      'learning_materials', MATERIAL_ID), {
      material_id: MATERIAL_ID, assignment_id: ASSIGNMENT_ID,
      owner_teacher_id: 'teacher', type: 'pdf', status: 'ready',
      storage_path: FINAL_PATH, schema_version: 1,
    });
    for (const userId of ['teacher', 'targeted']) {
      await setDoc(doc(db, 'activity_material_access',
        `${ASSIGNMENT_ID}__${MATERIAL_ID}__${userId}`), {
        assignment_id: ASSIGNMENT_ID, material_id: MATERIAL_ID, user_id: userId,
        owner_teacher_id: 'teacher', projection_generation: 1,
        schema_version: 1, created_at: Timestamp.now(),
      });
    }
    await uploadBytes(ref(admin.storage(), FINAL_PATH), new Uint8Array([1, 2, 3]), {
      contentType: 'application/pdf',
    });
  });
});

after(async () => testEnv.cleanup());

function storage(uid) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`, email_verified: true,
    ...(uid === 'teacher' || uid === 'otherTeacher' ? {role: 'Teacher'} : {}),
  }).storage();
}

function firestore(uid) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`, email_verified: true,
    ...(uid === 'teacher' || uid === 'otherTeacher' ? {role: 'Teacher'} : {}),
  }).firestore();
}

async function reserveStage({
  uploadId,
  type,
  contentType,
  sizeBytes,
  expiresAt = Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
}) {
  const stagingPath = `activity_material_staging/teacher/${ASSIGNMENT_ID}/${uploadId}`;
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'activity_material_uploads', uploadId), {
      upload_id: uploadId, material_id: `material-${uploadId}`,
      assignment_id: ASSIGNMENT_ID, owner_teacher_id: 'teacher', type,
      display_name: uploadId, declared_content_type: contentType,
      declared_size_bytes: sizeBytes, staging_path: stagingPath,
      state: 'staging', schema_version: 1,
      created_at: Timestamp.now(), expires_at: expiresAt,
    });
  });
  return stagingPath;
}

async function setStageState(uploadId, state) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'activity_material_uploads', uploadId), {
      state,
    }, {merge: true});
  });
}

describe('Learning Material Storage quarantine and access projection', () => {
  test('only the server-authorized owning Teacher can create the exact staging object', async () => {
    // The Function has already authorized this UID as a Teacher and created
    // the exact short-lived stage. Storage may briefly see the pre-refresh
    // token on Windows, so the stage capability—not the cached role claim—is
    // the authoritative second hop.
    const staleTeacherStorage = testEnv.authenticatedContext('teacher', {
      email: 'teacher@example.com', email_verified: true,
    }).storage();
    await assertSucceeds(uploadBytes(ref(staleTeacherStorage, STAGING_PATH),
      new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));
    await assertFails(uploadBytes(ref(storage('otherTeacher'), STAGING_PATH),
      new Uint8Array([1]), {contentType: 'application/pdf'}));
    await assertFails(uploadBytes(ref(storage('teacher'),
      `activity_material_staging/teacher/${ASSIGNMENT_ID}/different-upload`),
    new Uint8Array([1]), {contentType: 'application/pdf'}));
    await assertFails(uploadBytes(ref(storage('trainee'), STAGING_PATH),
      new Uint8Array([1]), {contentType: 'application/pdf'}));
  });

  test('all supported file MIME types allow exact create and immutable Windows metadata bootstrap', async () => {
    const imagePath = await reserveStage({
      uploadId: 'image-upload', type: 'image', contentType: 'image/png', sizeBytes: 3,
    });
    const videoPath = await reserveStage({
      uploadId: 'video-upload', type: 'video', contentType: 'video/mp4', sizeBytes: 3,
    });

    const imageStage = ref(storage('teacher'), imagePath);
    const videoStage = ref(storage('teacher'), videoPath);
    await assertSucceeds(uploadBytes(imageStage,
      new Uint8Array([1, 2, 3]), {contentType: 'image/png'}));
    await assertSucceeds(uploadBytes(videoStage,
      new Uint8Array([1, 2, 3]), {contentType: 'video/mp4'}));
    await assertSucceeds(updateMetadata(imageStage, {contentType: 'image/png'}));
    await assertSucceeds(updateMetadata(videoStage, {contentType: 'video/mp4'}));
    await assertFails(updateMetadata(imageStage, {contentType: 'image/jpeg'}));
    await assertFails(updateMetadata(videoStage, {customMetadata: {owner: 'forged'}}));
  });

  test('wrong byte count, MIME type, and expired capabilities are denied', async () => {
    await assertFails(uploadBytes(ref(storage('teacher'), STAGING_PATH),
      new Uint8Array([1, 2]), {contentType: 'application/pdf'}));
    await assertFails(uploadBytes(ref(storage('teacher'), STAGING_PATH),
      new Uint8Array([1, 2, 3]), {contentType: 'image/png'}));
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'activity_material_uploads', UPLOAD_ID), {
        expires_at: Timestamp.fromMillis(Date.now() - 1000),
      }, {merge: true});
    });
    await assertFails(uploadBytes(ref(storage('teacher'), STAGING_PATH),
      new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));
  });

  test('assignment and upload path components must match the capability exactly', async () => {
    await assertFails(uploadBytes(ref(storage('teacher'),
      `activity_material_staging/teacher/other-assignment/${UPLOAD_ID}`),
    new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));
    await assertFails(uploadBytes(ref(storage('teacher'),
      `activity_material_staging/teacher/${ASSIGNMENT_ID}/other-upload`),
    new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));
  });

  test('staging is never client-readable and cannot be overwritten', async () => {
    await assertSucceeds(uploadBytes(ref(storage('teacher'), STAGING_PATH),
      new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));
    await assertFails(getBytes(ref(storage('teacher'), STAGING_PATH)));
    await assertFails(uploadBytes(ref(storage('teacher'), STAGING_PATH),
      new Uint8Array([4]), {contentType: 'application/pdf'}));
  });

  test('Windows metadata bootstrap preserves staged bytes and declared type', async () => {
    const staged = ref(storage('teacher'), STAGING_PATH);
    await assertSucceeds(uploadBytes(staged,
      new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));
    await assertSucceeds(updateMetadata(staged, {contentType: 'application/pdf'}));
    await assertFails(updateMetadata(staged, {contentType: 'image/png'}));
    await assertFails(updateMetadata(staged, {customMetadata: {capability: 'forged'}}));
  });

  test('Windows metadata bootstrap survives validating and ready finalizer races', async () => {
    const validatingPath = await reserveStage({
      uploadId: 'validating-race', type: 'pdf',
      contentType: 'application/pdf', sizeBytes: 3,
    });
    const readyPath = await reserveStage({
      uploadId: 'ready-race', type: 'pdf',
      contentType: 'application/pdf', sizeBytes: 3,
    });
    const rejectedPath = await reserveStage({
      uploadId: 'rejected-race', type: 'pdf',
      contentType: 'application/pdf', sizeBytes: 3,
    });
    const deletingPath = await reserveStage({
      uploadId: 'deleting-race', type: 'pdf',
      contentType: 'application/pdf', sizeBytes: 3,
    });
    const expiredPath = await reserveStage({
      uploadId: 'expired-race', type: 'pdf',
      contentType: 'application/pdf', sizeBytes: 3,
    });
    const validatingStage = ref(storage('teacher'), validatingPath);
    const readyStage = ref(storage('teacher'), readyPath);
    const rejectedStage = ref(storage('teacher'), rejectedPath);
    const deletingStage = ref(storage('teacher'), deletingPath);
    const expiredStage = ref(storage('teacher'), expiredPath);

    await assertSucceeds(uploadBytes(validatingStage,
      new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));
    await assertSucceeds(uploadBytes(readyStage,
      new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));
    await assertSucceeds(uploadBytes(rejectedStage,
      new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));
    await assertSucceeds(uploadBytes(deletingStage,
      new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));
    await assertSucceeds(uploadBytes(expiredStage,
      new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));

    await setStageState('validating-race', 'validating');
    await assertSucceeds(updateMetadata(validatingStage, {
      contentType: 'application/pdf',
    }));

    await setStageState('ready-race', 'validating');
    await setStageState('ready-race', 'ready');
    await assertSucceeds(updateMetadata(readyStage, {
      contentType: 'application/pdf',
    }));

    await assertFails(updateMetadata(readyStage, {contentType: 'image/png'}));
    await assertFails(updateMetadata(readyStage, {
      customMetadata: {capability: 'forged'},
    }));
    await assertFails(updateMetadata(ref(storage('otherTeacher'), readyPath), {
      contentType: 'application/pdf',
    }));
    await assertFails(uploadBytes(readyStage,
      new Uint8Array([3, 2, 1]), {contentType: 'application/pdf'}));

    await setStageState('rejected-race', 'rejected');
    await setStageState('deleting-race', 'deleting');
    await assertFails(updateMetadata(rejectedStage, {
      contentType: 'application/pdf',
    }));
    await assertFails(updateMetadata(deletingStage, {
      contentType: 'application/pdf',
    }));

    await setStageState('expired-race', 'ready');
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'activity_material_uploads', 'expired-race'), {
        expires_at: Timestamp.fromMillis(Date.now() - 1000),
      }, {merge: true});
    });
    await assertFails(updateMetadata(expiredStage, {
      contentType: 'application/pdf',
    }));
  });

  test('final material reads succeed within the two-document Storage rule lookup budget', async () => {
    // A successful Storage read proves the rule stays within Firebase Storage
    // Rules' two-Firestore-document access limit; a third unique get denies.
    await assertSucceeds(getBytes(ref(storage('teacher'), FINAL_PATH)));
    await assertSucceeds(getBytes(ref(storage('targeted'), FINAL_PATH)));
    await assertFails(getBytes(ref(storage('approvedButNotTargeted'), FINAL_PATH)));
    await assertFails(getBytes(ref(storage('unrelatedTrainee'), FINAL_PATH)));
    await assertFails(uploadBytes(ref(storage('teacher'), FINAL_PATH),
      new Uint8Array([9]), {contentType: 'application/pdf'}));
  });

  test('ready materials remain readable while legacy state documents are upgraded', async () => {
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'activity_material_access_state', ASSIGNMENT_ID), {
        revoked_material_ids: deleteField(),
      }, {merge: true});
    });
    await assertSucceeds(getBytes(ref(storage('teacher'), FINAL_PATH)));
    await assertSucceeds(getBytes(ref(storage('targeted'), FINAL_PATH)));
  });

  test('revoked material fails closed even if a stale access record exists', async () => {
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'activity_material_access_state', ASSIGNMENT_ID), {
        revoked_material_ids: [MATERIAL_ID],
      }, {merge: true});
    });
    await assertFails(getBytes(ref(storage('targeted'), FINAL_PATH)));
  });

  test('revoking one material does not interrupt another ready material', async () => {
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      const db = admin.firestore();
      await setDoc(doc(db, 'group_assignments', ASSIGNMENT_ID,
        'learning_materials', OTHER_MATERIAL_ID), {
        material_id: OTHER_MATERIAL_ID, assignment_id: ASSIGNMENT_ID,
        owner_teacher_id: 'teacher', type: 'pdf', status: 'ready',
        storage_path: OTHER_FINAL_PATH, schema_version: 1,
      });
      await setDoc(doc(db, 'activity_material_access',
        `${ASSIGNMENT_ID}__${OTHER_MATERIAL_ID}__${'targeted'}`), {
        assignment_id: ASSIGNMENT_ID, material_id: OTHER_MATERIAL_ID, user_id: 'targeted',
        owner_teacher_id: 'teacher', projection_generation: 1,
        schema_version: 1, created_at: Timestamp.now(),
      });
      await setDoc(doc(db, 'activity_material_access_state', ASSIGNMENT_ID), {
        revoked_material_ids: [MATERIAL_ID],
      }, {merge: true});
      await uploadBytes(ref(admin.storage(), OTHER_FINAL_PATH), new Uint8Array([4, 5, 6]), {
        contentType: 'application/pdf',
      });
    });
    await assertFails(getBytes(ref(storage('targeted'), FINAL_PATH)));
    await assertSucceeds(getBytes(ref(storage('targeted'), OTHER_FINAL_PATH)));
  });
});

describe('Learning Material server-owned Firestore records', () => {
  test('clients cannot forge metadata, upload authorization, or an access projection', async () => {
    await assertFails(setDoc(doc(firestore('teacher'), 'group_assignments', ASSIGNMENT_ID,
      'learning_materials', MATERIAL_ID), {
      material_id: MATERIAL_ID, assignment_id: ASSIGNMENT_ID, owner_teacher_id: 'teacher',
      type: 'pdf', status: 'ready', storage_path: FINAL_PATH,
    }));
    await assertFails(setDoc(doc(firestore('teacher'), 'activity_material_uploads', 'forged'), {
      upload_id: 'forged', state: 'staging', owner_teacher_id: 'teacher',
    }));
    await assertFails(setDoc(doc(firestore('approvedButNotTargeted'),
      'activity_material_access', `${ASSIGNMENT_ID}__${MATERIAL_ID}__approvedButNotTargeted`), {
      assignment_id: ASSIGNMENT_ID, material_id: MATERIAL_ID,
      user_id: 'approvedButNotTargeted', schema_version: 1,
    }));
  });
});
