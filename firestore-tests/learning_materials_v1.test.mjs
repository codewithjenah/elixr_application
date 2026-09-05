import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { deleteField, doc, setDoc, Timestamp } from 'firebase/firestore';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

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

describe('Learning Material Storage quarantine and access projection', () => {
  test('only the server-authorized owning Teacher can create the exact staging object', async () => {
    await assertSucceeds(uploadBytes(ref(storage('teacher'), STAGING_PATH),
      new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));
    await assertFails(uploadBytes(ref(storage('otherTeacher'), STAGING_PATH),
      new Uint8Array([1]), {contentType: 'application/pdf'}));
    await assertFails(uploadBytes(ref(storage('teacher'),
      `activity_material_staging/teacher/${ASSIGNMENT_ID}/different-upload`),
    new Uint8Array([1]), {contentType: 'application/pdf'}));
    await assertFails(uploadBytes(ref(storage('trainee'), STAGING_PATH),
      new Uint8Array([1]), {contentType: 'application/pdf'}));
  });

  test('staging is never client-readable and cannot be overwritten', async () => {
    await assertSucceeds(uploadBytes(ref(storage('teacher'), STAGING_PATH),
      new Uint8Array([1, 2, 3]), {contentType: 'application/pdf'}));
    await assertFails(getBytes(ref(storage('teacher'), STAGING_PATH)));
    await assertFails(uploadBytes(ref(storage('teacher'), STAGING_PATH),
      new Uint8Array([4]), {contentType: 'application/pdf'}));
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
