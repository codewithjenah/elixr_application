import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, test } from 'node:test';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, Timestamp } from 'firebase/firestore';
import { getBytes, ref, uploadBytes } from 'firebase/storage';

const PROJECT_ID = 'demo-elixr';
const ASSIGNMENT_ID = 'assignment-1';
const MATERIAL_ID = 'material-1';
const UPLOAD_ID = 'upload-1';
const STAGING_PATH = `activity_material_staging/teacher/${ASSIGNMENT_ID}/${UPLOAD_ID}`;
const FINAL_PATH = `activity_learning_materials/${ASSIGNMENT_ID}/${MATERIAL_ID}`;

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
      declared_content_type: 'application/pdf', declared_size_bytes: 1024,
      staging_path: STAGING_PATH, state: 'staging', schema_version: 1,
      created_at: Timestamp.now(), expires_at: expires,
    });
    await setDoc(doc(db, 'activity_material_access_state', ASSIGNMENT_ID), {
      assignment_id: ASSIGNMENT_ID, generation: 1, state: 'ready',
      schema_version: 1, updated_at: Timestamp.now(),
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
  }).storage();
}

function firestore(uid) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`, email_verified: true,
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

  test('final material reads require the one-record server projection', async () => {
    await assertSucceeds(getBytes(ref(storage('teacher'), FINAL_PATH)));
    await assertSucceeds(getBytes(ref(storage('targeted'), FINAL_PATH)));
    await assertFails(getBytes(ref(storage('approvedButNotTargeted'), FINAL_PATH)));
    await assertFails(uploadBytes(ref(storage('teacher'), FINAL_PATH),
      new Uint8Array([9]), {contentType: 'application/pdf'}));
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
