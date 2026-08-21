import { readFileSync } from 'node:fs';
import { before, beforeEach, after, describe, test } from 'node:test';

import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import { doc, setDoc, Timestamp } from 'firebase/firestore';
import { deleteObject, getBytes, ref, updateMetadata, uploadBytes } from 'firebase/storage';

const PROJECT_ID = 'demo-elixr';
const TEACHER = 'WNFvwRJ4bzTFpVmsgv5x3qV2urt1';
const TRAINEE = 'OeflNaVfBkZ93BLOsGhRyOv6WAD3';
const OTHER = 'otherUid000000000000000000001';
const GROUP = 'i0CaSM4nEA9sNuKSRagO';
const ASG = 'ENvAezoRemcyihux3wpP';
const MOVEMENT = 'CYdQM78YMPbLTCTblERB';
const REVISION = 'DNLnQUFnxmwUP0y5uIM9';

const CASES = [
  'request_local',
  'membership_one_get',
  'assignment_one_get',
  'two_gets',
];

function diagnosticPath(probeName, traineeId = TRAINEE) {
  return `__elixr_diagnostics__/phase6_cross_service/${traineeId}/${probeName}.bin`;
}

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: readFileSync(new URL('../storage.rules', import.meta.url), 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
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

function meta(contentType = 'application/octet-stream') {
  return { contentType };
}

async function seedDocs({
  includeMembership = true,
  membershipStatus = 'approved',
  includeAssignment = true,
  assignmentStatus = 'active',
} = {}) {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    const db = admin.firestore();
    if (includeMembership) {
      await setDoc(doc(db, 'group_memberships', `${GROUP}_${TRAINEE}`), {
        group_id: GROUP,
        teacher_id: TEACHER,
        trainee_id: TRAINEE,
        teacher_display_name: 'Teacher One',
        trainee_display_name: 'Trainee One',
        status: membershipStatus,
        invite_id: '7KPMXR4DQ2WT',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    }
    if (includeAssignment) {
      await setDoc(doc(db, 'group_assignments', ASG), {
        teacher_id: TEACHER,
        group_id: GROUP,
        movement_id: MOVEMENT,
        revision_id: REVISION,
        origin: 'teacher_created',
        assessment_mode: 'teacher_reviewed',
        status: assignmentStatus,
        display_title: 'Tin Balance',
        teacher_display_name: 'Teacher One',
        group_name: 'BSHM 4A',
        created_at: Timestamp.now(),
        updated_at: Timestamp.now(),
      });
    }
  });
}

function upload(uid, probeName, { body = new Uint8Array(128), contentType = 'application/octet-stream', traineeId = TRAINEE } = {}) {
  return uploadBytes(
    ref(context(uid).storage(), diagnosticPath(probeName, traineeId)),
    body,
    meta(contentType),
  );
}

describe('phase6 isolated Storage cross-service diagnostic', () => {
  test('request_local ALLOW', async () => {
    await assertSucceeds(upload(TRAINEE, 'request_local'));
  });

  test('membership_one_get ALLOW with valid membership', async () => {
    await seedDocs({ includeAssignment: false });
    await assertSucceeds(upload(TRAINEE, 'membership_one_get'));
  });

  test('membership_one_get DENY with missing membership', async () => {
    await seedDocs({ includeMembership: false, includeAssignment: false });
    await assertFails(upload(TRAINEE, 'membership_one_get'));
  });

  test('membership_one_get DENY with removed membership', async () => {
    await seedDocs({
      includeAssignment: false,
      membershipStatus: 'removed',
    });
    await assertFails(upload(TRAINEE, 'membership_one_get'));
  });

  test('assignment_one_get ALLOW with valid assignment', async () => {
    await seedDocs({ includeMembership: false });
    await assertSucceeds(upload(TRAINEE, 'assignment_one_get'));
  });

  test('assignment_one_get DENY with missing assignment', async () => {
    await seedDocs({ includeMembership: false, includeAssignment: false });
    await assertFails(upload(TRAINEE, 'assignment_one_get'));
  });

  test('assignment_one_get DENY with inactive assignment', async () => {
    await seedDocs({
      includeMembership: false,
      assignmentStatus: 'inactive',
    });
    await assertFails(upload(TRAINEE, 'assignment_one_get'));
  });

  test('two_gets ALLOW when both valid', async () => {
    await seedDocs();
    await assertSucceeds(upload(TRAINEE, 'two_gets'));
  });

  test('two_gets DENY when assignment invalid', async () => {
    await seedDocs({ assignmentStatus: 'inactive' });
    await assertFails(upload(TRAINEE, 'two_gets'));
  });

  test('two_gets DENY when membership invalid', async () => {
    await seedDocs({ membershipStatus: 'removed' });
    await assertFails(upload(TRAINEE, 'two_gets'));
  });

  for (const probeName of CASES) {
    describe(`negative controls for ${probeName}`, () => {
      test('unauthenticated DENY', async () => {
        await seedDocs();
        const storage = testEnv.unauthenticatedContext().storage();
        await assertFails(
          uploadBytes(
            ref(storage, diagnosticPath(probeName)),
            new Uint8Array(128),
            meta(),
          ),
        );
      });

      test('wrong UID DENY', async () => {
        await seedDocs();
        await assertFails(upload(OTHER, probeName));
        await assertFails(upload(OTHER, probeName, { traineeId: OTHER }));
      });

      test('oversized DENY', async () => {
        await seedDocs();
        await assertFails(
          upload(TRAINEE, probeName, { body: new Uint8Array(257) }),
        );
      });

      test('wrong contentType DENY', async () => {
        await seedDocs();
        await assertFails(
          upload(TRAINEE, probeName, { contentType: 'text/plain' }),
        );
      });

      test('read DENY', async () => {
        await seedDocs();
        await testEnv.withSecurityRulesDisabled(async (admin) => {
          await uploadBytes(
            ref(admin.storage(), diagnosticPath(probeName)),
            new Uint8Array(128),
            meta(),
          );
        });
        await assertFails(
          getBytes(ref(context(TRAINEE).storage(), diagnosticPath(probeName))),
        );
      });

      test('update DENY', async () => {
        await seedDocs();
        await testEnv.withSecurityRulesDisabled(async (admin) => {
          await uploadBytes(
            ref(admin.storage(), diagnosticPath(probeName)),
            new Uint8Array(128),
            meta(),
          );
        });
        await assertFails(
          updateMetadata(
            ref(context(TRAINEE).storage(), diagnosticPath(probeName)),
            { contentType: 'application/octet-stream' },
          ),
        );
      });
    });
  }

  test('unknown probeName DENY', async () => {
    await seedDocs();
    await assertFails(
      uploadBytes(
        ref(
          context(TRAINEE).storage(),
          `__elixr_diagnostics__/phase6_cross_service/${TRAINEE}/unknown.bin`,
        ),
        new Uint8Array(128),
        meta(),
      ),
    );
  });

  test('known Trainee can delete own diagnostic object', async () => {
    await assertSucceeds(upload(TRAINEE, 'request_local'));
    await assertSucceeds(
      deleteObject(
        ref(context(TRAINEE).storage(), diagnosticPath('request_local')),
      ),
    );
  });
});
