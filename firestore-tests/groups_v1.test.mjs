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
  deleteDoc,
  doc,
  getDoc,
  getDocs,
  query,
  orderBy,
  serverTimestamp,
  setDoc,
  updateDoc,
  where,
  writeBatch,
} from 'firebase/firestore';

const PROJECT_ID = 'demo-elixr';
const CODE = '7KPMXR4DQ2WT';
const CODE2 = 'ABCD2345EFGH';
const GROUP_ID = 'group-1';
const MEMBERSHIP_ID = `${GROUP_ID}_trainee`;
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

async function seedUsers() {
  await testEnv.withSecurityRulesDisabled(async (admin) => {
    await setDoc(doc(admin.firestore(), 'users', 'teacher'), {
      full_name: 'Grace Hopper',
      role: 'Teacher',
    });
    await setDoc(doc(admin.firestore(), 'users', 'trainee'), {
      full_name: 'Ada Lovelace',
      role: 'Trainee',
    });
    await setDoc(doc(admin.firestore(), 'users', 'other'), {
      full_name: 'Other Teacher',
      role: 'Teacher',
    });
  });
}

function activeGroupPayload(name = 'BSHM 4A') {
  return {
    teacher_id: 'teacher',
    name,
    status: 'active',
    schema_version: 2,
    created_at: serverTimestamp(),
    updated_at: serverTimestamp(),
  };
}

async function createOwnedGroup(groupId = GROUP_ID) {
  const teacher = context('teacher').firestore();
  await assertSucceeds(
    setDoc(doc(teacher, 'groups', groupId), activeGroupPayload()),
  );
}

async function provisionGroupInvite({
  groupId = GROUP_ID,
  code = CODE,
  deletePreviousCode = null,
} = {}) {
  const teacher = context('teacher').firestore();
  const batch = writeBatch(teacher);
  if (deletePreviousCode) {
    batch.delete(doc(teacher, 'group_invites', deletePreviousCode));
  }
  batch.set(doc(teacher, 'group_invites', code), {
    group_id: groupId,
    teacher_id: 'teacher',
    teacher_display_name: 'Grace Hopper',
    created_at: serverTimestamp(),
  });
  batch.update(doc(teacher, 'groups', groupId), {
    invite_code: code,
    updated_at: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
}

function pendingMembershipPayload(code = CODE) {
  return {
    group_id: GROUP_ID,
    teacher_id: 'teacher',
    trainee_id: 'trainee',
    teacher_display_name: 'Grace Hopper',
    trainee_display_name: 'Ada Lovelace',
    status: 'pending',
    invite_id: code,
    request_version: 1,
    created_at: serverTimestamp(),
    updated_at: serverTimestamp(),
  };
}

async function approveMembership(db = context('teacher').firestore()) {
  const batch = writeBatch(db);
  batch.update(doc(db, 'group_memberships', MEMBERSHIP_ID), {
    status: 'approved',
    updated_at: serverTimestamp(),
  });
  batch.set(doc(db, 'classroom_teacher_access', 'teacher_trainee'), {
    teacher_id: 'teacher',
    trainee_id: 'trainee',
    group_id: GROUP_ID,
    schema_version: 1,
    updated_at: serverTimestamp(),
  });
  await assertSucceeds(batch.commit());
}

describe('Phase 2 groups', () => {
  test('verified Teacher creates own group', async () => {
    await seedUsers();
    await createOwnedGroup();
    const saved = await getDoc(
      doc(context('teacher').firestore(), 'groups', GROUP_ID),
    );
    assert.equal(saved.data().teacher_id, 'teacher');
  });

  test('Teacher cannot create group for another Teacher', async () => {
    await seedUsers();
    const other = context('other').firestore();
    await assertFails(
      setDoc(doc(other, 'groups', GROUP_ID), {
        ...activeGroupPayload(),
        teacher_id: 'teacher',
      }),
    );
  });

  test('Trainee cannot create group', async () => {
    await seedUsers();
    const trainee = context('trainee').firestore();
    await assertFails(setDoc(doc(trainee, 'groups', GROUP_ID), activeGroupPayload()));
  });

  test('unrelated Teacher cannot update owned group', async () => {
    await seedUsers();
    await createOwnedGroup();
    const other = context('other').firestore();
    await assertFails(
      updateDoc(doc(other, 'groups', GROUP_ID), {
        name: 'Hijacked',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('invite pointer first-set requires matching atomic invite document', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const saved = await getDoc(
      doc(context('teacher').firestore(), 'groups', GROUP_ID),
    );
    assert.equal(saved.data().invite_code, CODE);
    await assertFails(
      updateDoc(doc(context('teacher').firestore(), 'groups', GROUP_ID), {
        invite_code: CODE2,
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('invite rotation works with matching atomic invite document', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite({ code: CODE });
    await provisionGroupInvite({ code: CODE2, deletePreviousCode: CODE });
    const saved = await getDoc(
      doc(context('teacher').firestore(), 'groups', GROUP_ID),
    );
    assert.equal(saved.data().invite_code, CODE2);
    const oldInvite = await getDoc(
      doc(context('trainee').firestore(), 'group_invites', CODE),
    );
    assert.equal(oldInvite.exists(), false);
    await assertSucceeds(
      getDoc(doc(context('trainee').firestore(), 'group_invites', CODE2)),
    );
  });

  test('forged invite pointer without matching invite document is denied', async () => {
    await seedUsers();
    await createOwnedGroup();
    await assertFails(
      updateDoc(doc(context('teacher').firestore(), 'groups', GROUP_ID), {
        invite_code: CODE,
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('unrelated Teacher cannot rotate invite pointer', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const other = context('other').firestore();
    const batch = writeBatch(other);
    batch.set(doc(other, 'group_invites', CODE2), {
      group_id: GROUP_ID,
      teacher_id: 'other',
      teacher_display_name: 'Other Teacher',
      created_at: serverTimestamp(),
    });
    batch.update(doc(other, 'groups', GROUP_ID), {
      invite_code: CODE2,
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('Trainee cannot modify invite pointer', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertFails(
      updateDoc(doc(trainee, 'groups', GROUP_ID), {
        invite_code: CODE2,
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('archive still works without changing invite pointer', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const teacher = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(teacher, 'groups', GROUP_ID), {
        status: 'archived',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('owning Teacher can unarchive a group without changing invite pointer', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const teacher = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(teacher, 'groups', GROUP_ID), {
        status: 'archived',
        updated_at: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(teacher, 'groups', GROUP_ID), {
        status: 'active',
        updated_at: serverTimestamp(),
      }),
    );
    const saved = await getDoc(doc(teacher, 'groups', GROUP_ID));
    assert.equal(saved.data().invite_code, CODE);
    assert.equal(saved.data().status, 'active');
  });

  test('unrelated Teacher cannot unarchive an owned group', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const teacher = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(teacher, 'groups', GROUP_ID), {
        status: 'archived',
        updated_at: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(context('other').firestore(), 'groups', GROUP_ID), {
        status: 'active',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('unarchive cannot change protected classroom fields', async () => {
    await seedUsers();
    await createOwnedGroup();
    const teacher = context('teacher').firestore();
    await assertSucceeds(
      updateDoc(doc(teacher, 'groups', GROUP_ID), {
        status: 'archived',
        updated_at: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(teacher, 'groups', GROUP_ID), {
        status: 'active',
        name: 'Hijacked classroom',
        updated_at: serverTimestamp(),
      }),
    );
  });
});

describe('invite code namespace', () => {
  test('group_invite exact get works and list is denied', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(getDoc(doc(trainee, 'group_invites', CODE)));
    await assertFails(getDocs(collection(trainee, 'group_invites')));
  });

  test('teacher_invite list remains denied', async () => {
    await seedUsers();
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'teacher_invites', CODE), {
        teacher_id: 'teacher',
        teacher_display_name: 'Grace Hopper',
        created_at: new Date(),
      });
    });
    const trainee = context('trainee').firestore();
    await assertSucceeds(getDoc(doc(trainee, 'teacher_invites', CODE)));
    await assertFails(getDocs(collection(trainee, 'teacher_invites')));
  });

  test('creating group_invite is denied when legacy teacher_invite exists', async () => {
    await seedUsers();
    await createOwnedGroup();
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'teacher_invites', CODE), {
        teacher_id: 'teacher',
        teacher_display_name: 'Grace Hopper',
        created_at: new Date(),
      });
    });
    const teacher = context('teacher').firestore();
    const batch = writeBatch(teacher);
    batch.set(doc(teacher, 'group_invites', CODE), {
      group_id: GROUP_ID,
      teacher_id: 'teacher',
      teacher_display_name: 'Grace Hopper',
      created_at: serverTimestamp(),
    });
    batch.update(doc(teacher, 'groups', GROUP_ID), {
      invite_code: CODE,
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
  });

  test('creating legacy teacher_invite is denied when group_invite exists', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const teacher = context('teacher').firestore();
    const batch = writeBatch(teacher);
    batch.set(doc(teacher, 'teacher_invites', CODE), {
      teacher_id: 'teacher',
      teacher_display_name: 'Grace Hopper',
      created_at: serverTimestamp(),
    });
    batch.update(doc(teacher, 'users', 'teacher'), {
      teacher_roster_invite_code: CODE,
    });
    await assertFails(batch.commit());
  });
});

describe('group memberships', () => {
  test('Trainee creates own pending membership', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
  });

  test('Trainee cannot approve self', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
    await assertFails(
      updateDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), {
        status: 'approved',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('owning Teacher approves pending membership', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
    await approveMembership();
  });

  test('membership approval and classroom context must be atomic', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );

    const teacher = context('teacher').firestore();
    await assertFails(
      updateDoc(doc(teacher, 'group_memberships', MEMBERSHIP_ID), {
        status: 'approved',
        updated_at: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(teacher, 'classroom_teacher_access', 'teacher_trainee'), {
        teacher_id: 'teacher',
        trainee_id: 'trainee',
        group_id: GROUP_ID,
        schema_version: 1,
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('approved Teacher can repair context but cannot retarget it', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
    await approveMembership();

    const teacher = context('teacher').firestore();
    await assertSucceeds(
      setDoc(doc(teacher, 'classroom_teacher_access', 'teacher_trainee'), {
        teacher_id: 'teacher',
        trainee_id: 'trainee',
        group_id: GROUP_ID,
        schema_version: 1,
        updated_at: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(teacher, 'classroom_teacher_access', 'teacher_trainee'), {
        teacher_id: 'teacher',
        trainee_id: 'trainee',
        group_id: 'other-group',
        schema_version: 1,
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('unrelated Teacher cannot approve membership', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
    await assertFails(
      updateDoc(doc(context('other').firestore(), 'group_memberships', MEMBERSHIP_ID), {
        status: 'approved',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('identity fields cannot change during Teacher decision', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
    await assertFails(
      updateDoc(doc(context('teacher').firestore(), 'group_memberships', MEMBERSHIP_ID), {
        status: 'approved',
        trainee_id: 'other',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('Teacher removal works for approved membership', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
    const teacherMembership = doc(
      context('teacher').firestore(),
      'group_memberships',
      MEMBERSHIP_ID,
    );
    await approveMembership();
    await assertSucceeds(
      updateDoc(teacherMembership, {
        status: 'removed',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('membership cannot carry progress or evidence consent fields', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertFails(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), {
        ...pendingMembershipPayload(),
        progress_access: 'granted',
      }),
    );
    await assertFails(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), {
        ...pendingMembershipPayload(),
        evidence_access: 'granted',
      }),
    );
  });
});

describe('Trainee-scoped membership lookup (repository preflight)', () => {
  // requestGroupJoin() must discover existing rows with this trainee_id query.
  // Exact GET of a missing deterministic ID is denied because
  // isMembershipParticipant() requires resource.data.
  function ownMembershipLookup(db, traineeId) {
    return getDocs(query(
      collection(db, 'group_memberships'),
      where('trainee_id', '==', traineeId),
    ));
  }

  async function seedSecondTrainee() {
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'users', 'trainee2'), {
        full_name: 'Second Trainee',
        role: 'Trainee',
      });
    });
  }

  test('Trainee own-membership query succeeds empty before any membership exists', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee', { emailVerified: false }).firestore();
    const missingRef = doc(trainee, 'group_memberships', MEMBERSHIP_ID);

    await assertFails(getDoc(missingRef));
    await assertFails(getDocs(collection(trainee, 'group_memberships')));

    const lookup = await assertSucceeds(ownMembershipLookup(trainee, 'trainee'));
    assert.equal(lookup.size, 0);
  });

  test('Trainee own-membership query returns the membership after it exists', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee', { emailVerified: false }).firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );

    const lookup = await assertSucceeds(ownMembershipLookup(trainee, 'trainee'));
    assert.equal(lookup.size, 1);
    assert.equal(lookup.docs[0].id, MEMBERSHIP_ID);
    assert.equal(lookup.docs[0].data().status, 'pending');
    await assertSucceeds(getDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID)));
  });

  test('Trainee cannot query another Trainee memberships', async () => {
    await seedUsers();
    await seedSecondTrainee();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
    const trainee2 = context('trainee2').firestore();
    await assertFails(ownMembershipLookup(trainee2, 'trainee'));
  });

  test('unfiltered group_memberships list remains denied', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
    await assertFails(getDocs(collection(trainee, 'group_memberships')));
    await assertFails(getDocs(collection(context('teacher').firestore(), 'group_memberships')));
    await assertFails(getDocs(collection(context('other').firestore(), 'group_memberships')));
  });

  test('exact GET of another Trainee existing membership remains denied', async () => {
    await seedUsers();
    await seedSecondTrainee();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
    const trainee2 = context('trainee2').firestore();
    await assertFails(getDoc(doc(trainee2, 'group_memberships', MEMBERSHIP_ID)));
  });

  test('exact GET of a missing membership remains denied', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertFails(getDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID)));
    await assertFails(
      getDoc(doc(trainee, 'group_memberships', `${GROUP_ID}_someoneelse`)),
    );
  });
});

describe('unverified Trainee group join (Windows auth parity)', () => {
  test('unverified Trainee creates own pending membership', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee', { emailVerified: false }).firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
  });

  test('unverified Trainee cannot approve self', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee', { emailVerified: false }).firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
    await assertFails(
      updateDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), {
        status: 'approved',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('unverified Trainee cannot create group', async () => {
    await seedUsers();
    const trainee = context('trainee', { emailVerified: false }).firestore();
    await assertFails(setDoc(doc(trainee, 'groups', GROUP_ID), activeGroupPayload()));
  });

  test('unverified Trainee cannot create group_invite', async () => {
    await seedUsers();
    await createOwnedGroup();
    const trainee = context('trainee', { emailVerified: false }).firestore();
    await assertFails(
      setDoc(doc(trainee, 'group_invites', CODE), {
        group_id: GROUP_ID,
        teacher_id: 'trainee',
        teacher_display_name: 'Ada Lovelace',
        created_at: serverTimestamp(),
      }),
    );
  });

  test('verified owning Teacher approves unverified Trainee request', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee', { emailVerified: false }).firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
    await approveMembership();
  });

  test('unverified Teacher cannot create group', async () => {
    await seedUsers();
    const teacher = context('teacher', { emailVerified: false }).firestore();
    await assertFails(setDoc(doc(teacher, 'groups', GROUP_ID), activeGroupPayload()));
  });

  test('unverified Teacher cannot create or rotate group invite', async () => {
    await seedUsers();
    await createOwnedGroup();
    const unverifiedTeacher = context('teacher', { emailVerified: false }).firestore();
    const batch = writeBatch(unverifiedTeacher);
    batch.set(doc(unverifiedTeacher, 'group_invites', CODE), {
      group_id: GROUP_ID,
      teacher_id: 'teacher',
      teacher_display_name: 'Grace Hopper',
      created_at: serverTimestamp(),
    });
    batch.update(doc(unverifiedTeacher, 'groups', GROUP_ID), {
      invite_code: CODE,
      updated_at: serverTimestamp(),
    });
    await assertFails(batch.commit());
    await provisionGroupInvite();
    const rotateBatch = writeBatch(unverifiedTeacher);
    rotateBatch.set(doc(unverifiedTeacher, 'group_invites', CODE2), {
      group_id: GROUP_ID,
      teacher_id: 'teacher',
      teacher_display_name: 'Grace Hopper',
      created_at: serverTimestamp(),
    });
    rotateBatch.update(doc(unverifiedTeacher, 'groups', GROUP_ID), {
      invite_code: CODE2,
      updated_at: serverTimestamp(),
    });
    await assertFails(rotateBatch.commit());
  });
});

describe('unverified Teacher membership decisions (rules boundary)', () => {
  async function seedPendingMembership({ traineeVerified = false } = {}) {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee', { emailVerified: traineeVerified }).firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );
  }

  test('unverified owning Teacher cannot approve pending membership', async () => {
    await seedPendingMembership();
    const unverifiedTeacher = context('teacher', { emailVerified: false }).firestore();
    await assertFails(
      updateDoc(doc(unverifiedTeacher, 'group_memberships', MEMBERSHIP_ID), {
        status: 'approved',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('unverified owning Teacher cannot reject pending membership', async () => {
    await seedPendingMembership();
    const unverifiedTeacher = context('teacher', { emailVerified: false }).firestore();
    await assertFails(
      updateDoc(doc(unverifiedTeacher, 'group_memberships', MEMBERSHIP_ID), {
        status: 'rejected',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('unverified owning Teacher cannot remove approved membership', async () => {
    await seedPendingMembership();
    const verifiedTeacher = context('teacher').firestore();
    const membershipRef = doc(verifiedTeacher, 'group_memberships', MEMBERSHIP_ID);
    await approveMembership();
    const unverifiedTeacher = context('teacher', { emailVerified: false }).firestore();
    await assertFails(
      updateDoc(doc(unverifiedTeacher, 'group_memberships', MEMBERSHIP_ID), {
        status: 'removed',
        updated_at: serverTimestamp(),
      }),
    );
  });

  test('unrelated verified Teacher still cannot decide another Teacher membership', async () => {
    await seedPendingMembership();
    await assertFails(
      updateDoc(doc(context('other').firestore(), 'group_memberships', MEMBERSHIP_ID), {
        status: 'approved',
        updated_at: serverTimestamp(),
      }),
    );
  });
});

describe('Teacher-scoped membership listener queries (Windows Groups screen)', () => {
  const GROUP_ID_2 = 'group-2';
  const MEMBERSHIP_ID_2 = `${GROUP_ID_2}_trainee`;

  function teacherMembershipQuery(db, {
    teacherId = 'teacher',
    groupId = GROUP_ID,
    status = null,
  } = {}) {
    const constraints = [
      where('teacher_id', '==', teacherId),
      where('group_id', '==', groupId),
    ];
    if (status != null) {
      constraints.push(where('status', '==', status));
    }
    constraints.push(orderBy('created_at', 'desc'));
    return getDocs(query(collection(db, 'group_memberships'), ...constraints));
  }

  function legacyGroupOnlyQuery(db, groupId = GROUP_ID, status = 'approved') {
    return getDocs(query(
      collection(db, 'group_memberships'),
      where('group_id', '==', groupId),
      where('status', '==', status),
      orderBy('created_at', 'desc'),
    ));
  }

  async function seedApprovedMembership({
    membershipId = MEMBERSHIP_ID,
    groupId = GROUP_ID,
    teacherId = 'teacher',
    traineeId = 'trainee',
  } = {}) {
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'group_memberships', membershipId), {
        group_id: groupId,
        teacher_id: teacherId,
        trainee_id: traineeId,
        teacher_display_name: 'Grace Hopper',
        trainee_display_name: 'Ada Lovelace',
        status: 'approved',
        invite_id: CODE,
        request_version: 1,
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      });
    });
  }

  async function seedSecondGroupForTeacher() {
    const teacher = context('teacher').firestore();
    await assertSucceeds(
      setDoc(doc(teacher, 'groups', GROUP_ID_2), activeGroupPayload('BSHM 4B')),
    );
    await provisionGroupInvite({ groupId: GROUP_ID_2, code: CODE2 });
  }

  test('owning Teacher can query pending memberships with teacher_id scope', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );

    const teacher = context('teacher').firestore();
    const snapshot = await assertSucceeds(
      teacherMembershipQuery(teacher, { status: 'pending' }),
    );
    assert.equal(snapshot.size, 1);
    assert.equal(snapshot.docs[0].id, MEMBERSHIP_ID);
    assert.equal(snapshot.docs[0].data().status, 'pending');
  });

  test('owning Teacher can query approved memberships with teacher_id scope', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    await seedApprovedMembership();

    const teacher = context('teacher').firestore();
    const snapshot = await assertSucceeds(
      teacherMembershipQuery(teacher, { status: 'approved' }),
    );
    assert.equal(snapshot.size, 1);
    assert.equal(snapshot.docs[0].id, MEMBERSHIP_ID);
    assert.equal(snapshot.docs[0].data().status, 'approved');
  });

  test('owning Teacher query returns only memberships for the selected group', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    await seedSecondGroupForTeacher();
    await seedApprovedMembership();
    await seedApprovedMembership({
      membershipId: MEMBERSHIP_ID_2,
      groupId: GROUP_ID_2,
    });

    const teacher = context('teacher').firestore();
    const groupOne = await assertSucceeds(
      teacherMembershipQuery(teacher, { groupId: GROUP_ID, status: 'approved' }),
    );
    assert.equal(groupOne.size, 1);
    assert.equal(groupOne.docs[0].id, MEMBERSHIP_ID);

    const groupTwo = await assertSucceeds(
      teacherMembershipQuery(teacher, { groupId: GROUP_ID_2, status: 'approved' }),
    );
    assert.equal(groupTwo.size, 1);
    assert.equal(groupTwo.docs[0].id, MEMBERSHIP_ID_2);
  });

  test('unrelated Teacher cannot query another Teacher memberships', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    await seedApprovedMembership();

    const other = context('other').firestore();
    await assertFails(
      teacherMembershipQuery(other, { status: 'approved' }),
    );
    await assertFails(
      teacherMembershipQuery(other, { status: 'pending' }),
    );
  });

  test('group_id + status query without teacher_id remains denied', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    await seedApprovedMembership();

    const teacher = context('teacher').firestore();
    await assertFails(legacyGroupOnlyQuery(teacher, GROUP_ID, 'approved'));
    await assertFails(legacyGroupOnlyQuery(teacher, GROUP_ID, 'pending'));
  });

  test('unfiltered group_memberships list remains denied for Teacher listener path', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    await seedApprovedMembership();

    await assertFails(getDocs(collection(context('teacher').firestore(), 'group_memberships')));
  });

  test('Trainee own-membership query by trainee_id remains allowed', async () => {
    await seedUsers();
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );

    const lookup = await assertSucceeds(getDocs(query(
      collection(trainee, 'group_memberships'),
      where('trainee_id', '==', 'trainee'),
      orderBy('created_at', 'desc'),
    )));
    assert.equal(lookup.size, 1);
    assert.equal(lookup.docs[0].id, MEMBERSHIP_ID);
  });

  test('exact GET privacy behavior remains unchanged', async () => {
    await seedUsers();
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'users', 'trainee2'), {
        full_name: 'Second Trainee',
        role: 'Trainee',
      });
    });
    await createOwnedGroup();
    await provisionGroupInvite();
    const trainee = context('trainee').firestore();
    await assertSucceeds(
      setDoc(doc(trainee, 'group_memberships', MEMBERSHIP_ID), pendingMembershipPayload()),
    );

    await assertSucceeds(getDoc(doc(context('teacher').firestore(), 'group_memberships', MEMBERSHIP_ID)));
    await assertFails(getDoc(doc(context('other').firestore(), 'group_memberships', MEMBERSHIP_ID)));
    await assertFails(getDoc(doc(context('trainee2').firestore(), 'group_memberships', MEMBERSHIP_ID)));
  });

  test('owning teacher can list memberships by teacher_id ordered newest first', async () => {
    await seedUsers();
    await createOwnedGroup();
    await testEnv.withSecurityRulesDisabled(async (admin) => {
      await setDoc(doc(admin.firestore(), 'group_memberships', MEMBERSHIP_ID), {
        group_id: GROUP_ID,
        teacher_id: 'teacher',
        trainee_id: 'trainee',
        teacher_display_name: 'Grace Hopper',
        trainee_display_name: 'Ada Lovelace',
        status: 'approved',
        request_version: 1,
        created_at: serverTimestamp(),
        updated_at: serverTimestamp(),
      });
    });
    const teacher = context('teacher').firestore();
    const owned = await assertSucceeds(getDocs(query(
      collection(teacher, 'group_memberships'),
      where('teacher_id', '==', 'teacher'),
      orderBy('created_at', 'desc'),
    )));
    assert.equal(owned.size, 1);
    await assertFails(getDocs(query(
      collection(context('other').firestore(), 'group_memberships'),
      where('teacher_id', '==', 'teacher'),
      orderBy('created_at', 'desc'),
    )));
    await assertFails(getDocs(collection(teacher, 'group_memberships')));
  });
});

describe('Classroom Authorization helper contract', () => {
  test('hasClassroomAuthorization binds request.auth.uid to group and membership teacher_id', () => {
    const start = RULES_SOURCE.indexOf('function hasClassroomAuthorization');
    assert.ok(start >= 0, 'hasClassroomAuthorization must exist in firestore.rules');
    const end = RULES_SOURCE.indexOf('function hasAssignmentSubmissionAuthorization', start);
    const body = RULES_SOURCE.slice(start, end);
    assert.match(body, /request\.auth\.uid == get\(groupPath\(groupId\)\)\.data\.teacher_id/);
    assert.match(
      body,
      /get\(groupMembershipPath\(groupId, traineeId\)\)\.data\.teacher_id\s*==\s*request\.auth\.uid/,
    );
    assert.doesNotMatch(body, /progress_access/);
    assert.doesNotMatch(body, /evidence_access/);
  });
});
