const assert = require('node:assert/strict');
const test = require('node:test');
const {Timestamp} = require('firebase-admin/firestore');

const {
  archivedConversationId,
  assignmentAudienceAllows,
  assignmentJsonValue,
  createClassroomAssignmentHandler,
  authenticatedUid,
  ensureTeacherRoleClaimHandler,
  buildArchivedConversationData,
  buildSearchPrefixes,
  conversationIdFor,
  isActiveChatProfile,
  isSearchRateLimited,
  listTraineeAssignmentsHandler,
  updateTeacherActivityAssignmentHandler,
  validActivityAssessment,
  ACTIVITY_MATERIAL_LIMITS,
  detectActivityMaterialContent,
  finalMaterialPathFor,
  materialAccessId,
  materialMaximumBytes,
  normalizeActivityMaterialLink,
  stagingPathFor,
  beginActivityMaterialUploadHandler,
  getActivityMaterialUploadStatusHandler,
  removeActivityLearningMaterialHandler,
  runActivityMaterialReconciliation,
  syncActivityMaterialAccess,
  permanentDeleteAssignmentHandler,
  permanentDeleteClassroomHandler,
  normalizeSearchText,
  sanitizeDirectoryDocuments,
  sanitizedResult,
  validateSearchQuery,
  runScheduledAnnouncementPublication,
} = require('../index')._test;

function scheduledAnnouncementDatabase(records, {failIds = []} = {}) {
  const calls = [];
  let limitValue = records.length;
  let startAfterId = null;
  let queryReads = 0;
  const docs = records.map((record) => ({
    ref: {
      id: record.id,
      path: `groups/${record.groupId || 'group-1'}/announcements/${record.id}`,
    },
    data: () => record.data,
  }));
  const matchesDueQuery = (record) => {
    if (queryReads > 0 && record.exists === false) return false;
    const data = queryReads === 0 ? (record.queryData || record.data) : record.data;
    const visible = data.trainee_visible === false;
    const publishAt = data.publish_at;
    return visible && publishAt instanceof Timestamp && publishAt.toMillis() <= 1000;
  };
  const query = {
    where(field, operator, value) {
      calls.push({method: 'where', field, operator, value});
      return this;
    },
    orderBy(field, direction) {
      calls.push({method: 'orderBy', field, direction});
      return this;
    },
    startAfter(document) {
      startAfterId = document.ref.id;
      calls.push({method: 'startAfter', id: startAfterId});
      return this;
    },
    limit(value) {
      limitValue = value;
      calls.push({method: 'limit', value});
      return this;
    },
    async get() {
      const candidates = docs
        .filter((document) => matchesDueQuery(records.find((item) => item.id === document.ref.id)))
        .filter((document) => startAfterId == null || document.ref.id > startAfterId)
        .slice(0, limitValue);
      queryReads += 1;
      return {docs: candidates, size: candidates.length};
    },
  };
  return {
    calls,
    collection() {
      throw new Error('scheduled publication must not scan top-level collections');
    },
    collectionGroup(name) {
      calls.push({method: 'collectionGroup', name});
      return query;
    },
    async runTransaction(callback) {
      const transaction = {
        get: async (ref) => {
          const record = records.find((item) => item.id === ref.id);
          return {exists: Boolean(record?.exists !== false), data: () => record?.data};
        },
        update: (ref, patch) => {
          if (failIds.includes(ref.id)) throw new Error('write failed');
          Object.assign(records.find((item) => item.id === ref.id).data, patch);
        },
      };
      return callback(transaction);
    },
  };
}

test('scheduled announcement publication queries only due unpublished candidates', async () => {
  const now = Timestamp.fromMillis(1000);
  const future = {id: 'future',
    data: {trainee_visible: false, publish_at: Timestamp.fromMillis(1001)}};
  const due = {id: 'due', data: {trainee_visible: false, publish_at: Timestamp.fromMillis(1000)}};
  const database = scheduledAnnouncementDatabase([future, due]);
  const result = await runScheduledAnnouncementPublication({firestore: database, now, batchSize: 2});

  assert.deepEqual(result, {candidates: 1, published: 1, skipped: 0, failed: 0});
  assert.equal(future.data.trainee_visible, false);
  assert.equal(due.data.trainee_visible, true);
  assert.deepEqual(database.calls.map((call) => call.method),
    ['collectionGroup', 'where', 'where', 'orderBy', 'limit']);
  assert.deepEqual(database.calls.slice(1, 3).map(({field, operator}) => ({field, operator})), [
    {field: 'trainee_visible', operator: '=='},
    {field: 'publish_at', operator: '<='},
  ]);
});

test('scheduled announcement publication handles stale, deleted, malformed, and repeated candidates safely', async () => {
  const now = Timestamp.fromMillis(1000);
  const records = [
    {id: 'past', data: {trainee_visible: false, publish_at: Timestamp.fromMillis(999)}},
    {id: 'future-after-reschedule', queryData: {trainee_visible: false, publish_at: Timestamp.fromMillis(999)},
      data: {trainee_visible: false, publish_at: Timestamp.fromMillis(1001)}},
    {id: 'deleted', exists: false, data: {trainee_visible: false, publish_at: Timestamp.fromMillis(999)}},
    {id: 'malformed', queryData: {trainee_visible: false, publish_at: Timestamp.fromMillis(999)},
      data: {trainee_visible: false, publish_at: 'not-a-timestamp'}},
    {id: 'visible', queryData: {trainee_visible: false, publish_at: Timestamp.fromMillis(999)},
      data: {trainee_visible: true, publish_at: Timestamp.fromMillis(999)}},
  ];
  const database = scheduledAnnouncementDatabase(records);
  const first = await runScheduledAnnouncementPublication({firestore: database, now, batchSize: 10});
  const second = await runScheduledAnnouncementPublication({firestore: database, now, batchSize: 10});

  assert.deepEqual(first, {candidates: 5, published: 1, skipped: 4, failed: 0});
  assert.equal(records[0].data.trainee_visible, true);
  assert.equal(records[1].data.trainee_visible, false);
  assert.deepEqual(second, {candidates: 0, published: 0, skipped: 0, failed: 0});
});

test('scheduled announcement publication isolates failures and processes bounded pages', async () => {
  const now = Timestamp.fromMillis(1000);
  const records = [
    {id: 'fails-a', data: {trainee_visible: false, publish_at: Timestamp.fromMillis(999)}},
    {id: 'fails-b', data: {trainee_visible: false, publish_at: Timestamp.fromMillis(999)}},
    {id: 'succeeds', data: {trainee_visible: false, publish_at: Timestamp.fromMillis(999)}},
  ];
  const database = scheduledAnnouncementDatabase(records, {failIds: ['fails-a', 'fails-b']});
  const result = await runScheduledAnnouncementPublication({firestore: database, now, batchSize: 2});

  assert.deepEqual(result, {candidates: 3, published: 1, skipped: 0, failed: 2});
  assert.equal(records[2].data.trainee_visible, true);
  assert.ok(database.calls.some((call) => call.method === 'startAfter'));
  const bounded = scheduledAnnouncementDatabase(records.map((record) => ({
    ...record, data: {trainee_visible: false, publish_at: Timestamp.fromMillis(999)},
  })));
  const boundedResult = await runScheduledAnnouncementPublication({
    firestore: bounded, now, batchSize: 1, maxPages: 1,
  });
  assert.equal(boundedResult.candidates, 1);
  assert.equal(bounded.calls.at(-1).value, 1);
});

test('Learning Material byte classification accepts only the narrow supported signatures', () => {
  assert.deepEqual(
    detectActivityMaterialContent(Buffer.from('%PDF-1.7\nminimal')),
    {type: 'pdf', contentType: 'application/pdf'},
  );
  assert.deepEqual(
    detectActivityMaterialContent(Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00,
    ])),
    {type: 'image', contentType: 'image/png'},
  );
  assert.deepEqual(
    detectActivityMaterialContent(Buffer.from([0xff, 0xd8, 0xff, 0xdb, 0x00])),
    {type: 'image', contentType: 'image/jpeg'},
  );
  assert.deepEqual(
    detectActivityMaterialContent(Buffer.from([
      0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70,
      0x69, 0x73, 0x6f, 0x6d, 0x00, 0x00, 0x00, 0x00,
    ])),
    {type: 'video', contentType: 'video/mp4'},
  );
  assert.equal(detectActivityMaterialContent(Buffer.alloc(0)), null);
  assert.equal(detectActivityMaterialContent(Buffer.from('not a PDF')), null);
  assert.equal(detectActivityMaterialContent(Buffer.from('%PDF')), null);
  assert.equal(detectActivityMaterialContent(Buffer.from([
    0x00, 0x00, 0x00, 0x18, 0x66, 0x74, 0x79, 0x70,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ])), null);
});

test('Learning Material canonical paths and links cannot be client-shaped capabilities', () => {
  assert.equal(
    stagingPathFor('teacher', 'assignment', 'upload-id'),
    'activity_material_staging/teacher/assignment/upload-id',
  );
  assert.equal(
    finalMaterialPathFor('assignment', 'material-id'),
    'activity_learning_materials/assignment/material-id',
  );
  assert.equal(
    materialAccessId('assignment', 'material', 'trainee'),
    'assignment__material__trainee',
  );
  assert.equal(normalizeActivityMaterialLink(' HTTPS://example.com/path#fragment '),
    'https://example.com/path');
  assert.equal(normalizeActivityMaterialLink('javascript:alert(1)'), null);
  assert.equal(normalizeActivityMaterialLink('https://user:pass@example.com/a'), null);
  assert.equal(materialMaximumBytes('pdf'), ACTIVITY_MATERIAL_LIMITS.pdfBytes);
  assert.equal(materialMaximumBytes('image'), ACTIVITY_MATERIAL_LIMITS.imageBytes);
  assert.equal(materialMaximumBytes('video'), ACTIVITY_MATERIAL_LIMITS.videoBytes);
});

function activityAssessment({maximum = 50, attempts = 3, duration = 30} = {}) {
  return {
    schema_version: 2,
    readiness: {prop: 'two_bottles', hands: 'two_hands', body: 'upper_body'},
    rubric: {
      template_id: 'standard_technique',
      maximum_score: maximum,
      criteria: [
        {id: 'setup', label: 'Setup', description: 'Correct setup.', maximum_points: 10},
        {id: 'technique', label: 'Technique', description: 'Safe technique.', maximum_points: 20},
        {id: 'control', label: 'Control', description: 'Controlled finish.', maximum_points: maximum - 30},
      ],
    },
    attempt_policy: attempts == null
      ? {type: 'unlimited'}
      : {type: 'finite', maximum_attempts: attempts},
    recording_duration_seconds: duration,
  };
}

test('Teacher Activity assessment contract validates readiness, rubric and limits', () => {
  assert.equal(validActivityAssessment(activityAssessment(), 50), true);
  assert.equal(validActivityAssessment(activityAssessment({attempts: null}), 50), true);
  assert.equal(validActivityAssessment(activityAssessment({attempts: 4}), 50), false);
  assert.equal(validActivityAssessment(activityAssessment({duration: 20}), 50), false);
  const badReadiness = activityAssessment();
  badReadiness.readiness.prop = 'glass';
  assert.equal(validActivityAssessment(badReadiness, 50), false);
});

test('permanent deletion rejects wrong exact confirmation before database access', async () => {
  let databaseAccessed = false;
  const options = {
    authenticate: async () => 'teacher',
    databaseFactory: () => {
      databaseAccessed = true;
      throw new Error('must not access database');
    },
  };
  const assignmentResponse = fakeResponse();
  await permanentDeleteAssignmentHandler({
    method: 'POST', body: {assignment_id: 'assignment-1', confirmation: 'delete assignment'},
  }, assignmentResponse, options);
  assert.equal(assignmentResponse.statusCode, 400);

  const classroomResponse = fakeResponse();
  await permanentDeleteClassroomHandler({
    method: 'POST', body: {group_id: 'group-1', confirmation: 'DELETE CLASS'},
  }, classroomResponse, options);
  assert.equal(classroomResponse.statusCode, 400);
  assert.equal(databaseAccessed, false);
});
const {
  executeMigrationWrites,
  legacyMessageData,
  legacyMessageId,
  shouldReplaceConversationSummary,
} = require('../lib/migration_helpers');

function fakeResponse() {
  return {
    headers: {},
    statusCode: null,
    body: null,
    set(name, value) {
      this.headers[name] = value;
      return this;
    },
    status(value) {
      this.statusCode = value;
      return this;
    },
    json(value) {
      this.body = value;
      return this;
    },
    send(value) {
      this.body = value;
      return this;
    },
  };
}

function claimSnapshot(data) {
  return {
    exists: data != null,
    get: (field) => data?.[field],
    data: () => data,
  };
}

function fakeTeacherClaimServices({
  profile = {role: 'Teacher', teacher_access_code: 'ABCDEFGHJKM2'},
  code = {consumed: true, consumed_by: 'teacher'},
  customClaims = {billingPlan: 'faculty'},
} = {}) {
  const setCalls = [];
  const firestore = {
    collection(name) {
      return {
        doc(id) {
          return {
            get: async () => claimSnapshot(
              name === 'users' && id === 'teacher' ? profile :
                name === 'teacher_access_codes' && id === 'ABCDEFGHJKM2' ? code : null,
            ),
          };
        },
      };
    },
  };
  const auth = {
    getUser: async (uid) => ({uid, customClaims}),
    setCustomUserClaims: async (uid, claims) => setCalls.push({uid, claims}),
  };
  return {firestore, auth, setCalls};
}

async function callTeacherClaimHandler({
  token = {uid: 'teacher'},
  body = {},
  services = fakeTeacherClaimServices(),
  method = 'POST',
} = {}) {
  const response = fakeResponse();
  await ensureTeacherRoleClaimHandler(
    {method, body, get: () => ''},
    response,
    {
      verifyToken: async () => token,
      databaseFactory: () => services.firestore,
      authFactory: () => services.auth,
    },
  );
  return {response, services};
}

test('Teacher claim finalization requires authentication and an empty request body', async () => {
  const unauthenticated = await callTeacherClaimHandler({token: null});
  assert.equal(unauthenticated.response.statusCode, 401);

  for (const body of [{uid: 'victim'}, {role: 'Teacher'}, {role: 'Admin'}]) {
    const rejected = await callTeacherClaimHandler({body});
    assert.equal(rejected.response.statusCode, 400);
    assert.equal(rejected.services.setCalls.length, 0);
  }
});

test('Teacher claim finalization rejects incomplete or inconsistent evidence', async () => {
  const cases = [
    {profile: null},
    {profile: {role: 'Trainee', teacher_access_code: 'ABCDEFGHJKM2'}},
    {profile: {role: 'Teacher'}},
    {code: null},
    {code: {consumed: false, consumed_by: 'teacher'}},
    {code: {consumed: true, consumed_by: 'another-user'}},
  ];
  for (const values of cases) {
    const services = fakeTeacherClaimServices(values);
    const {response} = await callTeacherClaimHandler({services});
    assert.equal(response.statusCode, 403);
    assert.equal(services.setCalls.length, 0);
  }
});

test('Teacher claim finalization preserves unrelated claims and is idempotent', async () => {
  const services = fakeTeacherClaimServices();
  const granted = await callTeacherClaimHandler({services});
  assert.equal(granted.response.statusCode, 200);
  assert.deepEqual(services.setCalls, [{
    uid: 'teacher',
    claims: {billingPlan: 'faculty', role: 'Teacher'},
  }]);

  const alreadyCorrect = fakeTeacherClaimServices({
    customClaims: {billingPlan: 'faculty', role: 'Teacher'},
  });
  const repeated = await callTeacherClaimHandler({services: alreadyCorrect});
  assert.equal(repeated.response.statusCode, 200);
  assert.equal(alreadyCorrect.setCalls.length, 0);
});

function fakeMaterialBeginDatabase({
  assignment = {teacher_id: 'teacher', status: 'draft'},
  user = {role: 'Teacher'},
  materialStatuses = [],
} = {}) {
  const writes = [];
  const document = (kind, id, data) => ({
    kind, id,
    snapshot: {
      exists: data != null,
      data: () => data,
      get: (field) => data?.[field],
      docs: Array.isArray(data)
        ? data.map((value, index) => ({id: `material-${index}`, get: (field) => value[field]}))
        : undefined,
    },
    collection(name) {
      assert.equal(kind, 'assignment');
      assert.equal(name, 'learning_materials');
      const materials = document(
        'materials', id, materialStatuses.map((status) => ({status})),
      );
      materials.doc = (materialId) => document('material', materialId, null);
      return materials;
    },
  });
  const database = {
    writes,
    collection(name) {
      return {
        doc(id) {
          if (name === 'group_assignments') return document('assignment', id, assignment);
          if (name === 'users') return document('user', id, user);
          if (name === 'activity_material_uploads') return document('stage', id, null);
          throw new Error(`unexpected collection ${name}`);
        },
      };
    },
    async runTransaction(callback) {
      return callback({
        get: async (ref) => ref.snapshot,
        create: (ref, data) => writes.push({kind: ref.kind, id: ref.id, data}),
      });
    },
  };
  return database;
}

test('Learning Material upload initialization rejects unauthenticated and non-owner callers', async () => {
  const unauthenticated = fakeResponse();
  await beginActivityMaterialUploadHandler(
    {method: 'POST', body: {}}, unauthenticated,
    {authenticate: async () => null, databaseFactory: () => { throw new Error('unused'); }},
  );
  assert.equal(unauthenticated.statusCode, 401);

  const forbidden = fakeResponse();
  await beginActivityMaterialUploadHandler(
    {method: 'POST', body: {
      assignment_id: 'assignment', type: 'pdf', display_name: 'Sheet',
      declared_content_type: 'application/pdf', size_bytes: 8,
    }}, forbidden,
    {authenticate: async () => 'other', databaseFactory: () => fakeMaterialBeginDatabase()},
  );
  assert.equal(forbidden.statusCode, 403);
});

test('Learning Material upload initialization reserves opaque server IDs and exact staging path', async () => {
  const response = fakeResponse();
  const database = fakeMaterialBeginDatabase();
  await beginActivityMaterialUploadHandler(
    {method: 'POST', body: {
      assignment_id: 'assignment', type: 'image', display_name: '  Setup photo ',
      declared_content_type: 'image/png', size_bytes: 8,
    }}, response,
    {authenticate: async () => 'teacher', databaseFactory: () => database},
  );
  assert.equal(response.statusCode, 200);
  assert.match(response.body.upload_id, /^[0-9a-f-]{36}$/);
  assert.match(response.body.material_id, /^[0-9a-f-]{36}$/);
  assert.equal(response.body.staging_path,
    `activity_material_staging/teacher/assignment/${response.body.upload_id}`);
  assert.equal(database.writes.length, 2);
  assert.equal(database.writes.find((write) => write.kind === 'material').data.status, 'staging');
  assert.equal(database.writes.find((write) => write.kind === 'stage').data.state, 'staging');
});

function fakeUploadStatusDatabase({
  stage = null,
  user = {role: 'Teacher'},
  material = null,
} = {}) {
  const snapshot = (data, id = 'upload') => ({
    exists: data != null,
    id,
    data: () => data,
    get: (field) => data?.[field],
  });
  return {
    collection(name) {
      return {
        doc(id) {
          if (name === 'activity_material_uploads') return {get: async () => snapshot(stage, id)};
          if (name === 'users') return {get: async () => snapshot(user, id)};
          if (name === 'group_assignments') {
            return {collection: (child) => {
              assert.equal(child, 'learning_materials');
              return {doc: (materialId) => ({get: async () => snapshot(material, materialId)})};
            }};
          }
          throw new Error(`unexpected collection ${name}`);
        },
      };
    },
  };
}

test('Learning Material upload status is owner-only and exposes only safe state', async () => {
  const stage = {
    owner_teacher_id: 'teacher', assignment_id: 'assignment', material_id: 'material',
    state: 'rejected', rejection_reason: 'storage failed at internal/path',
  };
  const unauthenticated = fakeResponse();
  await getActivityMaterialUploadStatusHandler({method: 'POST', body: {upload_id: 'upload'}},
    unauthenticated, {authenticate: async () => null});
  assert.equal(unauthenticated.statusCode, 401);

  const trainee = fakeResponse();
  await getActivityMaterialUploadStatusHandler({method: 'POST', body: {upload_id: 'upload'}},
    trainee, {authenticate: async () => 'trainee', databaseFactory: () => fakeUploadStatusDatabase({
      stage, user: {role: 'Trainee'},
    })});
  assert.equal(trainee.statusCode, 403);

  const otherTeacher = fakeResponse();
  await getActivityMaterialUploadStatusHandler({method: 'POST', body: {upload_id: 'upload'}},
    otherTeacher, {authenticate: async () => 'other', databaseFactory: () => fakeUploadStatusDatabase({stage})});
  assert.equal(otherTeacher.statusCode, 403);

  const owner = fakeResponse();
  await getActivityMaterialUploadStatusHandler({method: 'POST', body: {upload_id: 'upload'}},
    owner, {authenticate: async () => 'teacher', databaseFactory: () => fakeUploadStatusDatabase({stage})});
  assert.equal(owner.statusCode, 200);
  assert.deepEqual(owner.body, {
    upload_id: 'upload', material_id: 'material', state: 'rejected', rejection_reason: 'upload_failed',
  });
});

test('Learning Material upload status returns each owner lifecycle and requires ready metadata', async () => {
  for (const state of ['staging', 'validating', 'deleting']) {
    const response = fakeResponse();
    await getActivityMaterialUploadStatusHandler({method: 'POST', body: {upload_id: 'upload'}}, response,
      {authenticate: async () => 'teacher', databaseFactory: () => fakeUploadStatusDatabase({stage: {
        owner_teacher_id: 'teacher', assignment_id: 'assignment', material_id: 'material', state,
      }})});
    assert.equal(response.statusCode, 200);
    assert.equal(response.body.state, state);
  }
  const ready = fakeResponse();
  await getActivityMaterialUploadStatusHandler({method: 'POST', body: {upload_id: 'upload'}}, ready,
    {authenticate: async () => 'teacher', databaseFactory: () => fakeUploadStatusDatabase({
      stage: {owner_teacher_id: 'teacher', assignment_id: 'assignment', material_id: 'material', state: 'ready'},
      material: {
        owner_teacher_id: 'teacher', material_id: 'material', assignment_id: 'assignment',
        type: 'pdf', display_name: 'Sheet', status: 'ready', projection_sync_state: 'ready',
        storage_path: 'activity_learning_materials/assignment/material',
      },
    })});
  assert.equal(ready.statusCode, 200);
  assert.equal(ready.body.material.material_id, 'material');

  const pendingProjection = fakeResponse();
  await getActivityMaterialUploadStatusHandler({method: 'POST', body: {upload_id: 'upload'}}, pendingProjection,
    {authenticate: async () => 'teacher', databaseFactory: () => fakeUploadStatusDatabase({
      stage: {owner_teacher_id: 'teacher', assignment_id: 'assignment', material_id: 'material', state: 'ready'},
      material: {
        owner_teacher_id: 'teacher', material_id: 'material', assignment_id: 'assignment',
        type: 'pdf', display_name: 'Sheet', status: 'ready', projection_sync_state: 'pending',
        storage_path: 'activity_learning_materials/assignment/material',
      },
    })});
  assert.equal(pendingProjection.statusCode, 200);
  assert.equal(pendingProjection.body.state, 'validating');

  const missing = fakeResponse();
  await getActivityMaterialUploadStatusHandler({method: 'POST', body: {upload_id: 'missing'}}, missing,
    {authenticate: async () => 'teacher', databaseFactory: () => fakeUploadStatusDatabase()});
  assert.equal(missing.statusCode, 404);
});

function fakeAssignmentDatabase({memberships, assignments, recipients = [], overrides = []}) {
  const assignmentQueries = [];
  const docs = (values) => values.map((value) => ({
    id: value.id,
    data: () => value.data,
    ref: {
      collection(name) {
        assert.ok(['assignment_recipients', 'assignment_deadline_overrides'].includes(name));
        return {
          doc(traineeId) {
            const recipient = (name === 'assignment_recipients' ? recipients : overrides).find((item) =>
              item.assignmentId === value.id && item.traineeId === traineeId,
            );
            return {
              get: async () => ({
                exists: Boolean(recipient),
                data: () => recipient?.data,
              }),
            };
          },
        };
      },
    },
  }));
  return {
    assignmentQueries,
    collection(name) {
      return {
        doc(id) {
          const item = assignments.find((assignment) => assignment.id === id);
          return {
            get: async () => ({
              exists: Boolean(item),
              id,
              data: () => item?.data,
            }),
          };
        },
        where(field, operator, value) {
          assert.equal(field, name === 'group_memberships'
            ? 'trainee_id'
            : 'group_id');
          if (name === 'group_memberships') {
            assert.equal(operator, '==');
            return {
              get: async () => ({
                docs: docs(memberships.filter(
                  (item) => item.data.trainee_id === value,
                )),
              }),
            };
          }
          assert.equal(name, 'group_assignments');
          assignmentQueries.push({operator, value});
          const groupIds = operator === 'in' ? value : [value];
          return {
            get: async () => ({
              docs: docs(assignments.filter(
                (item) => groupIds.includes(item.data.group_id),
              )),
            }),
          };
        },
      };
    },
  };
}

function fakeCreationDatabase({recipientIds, documents = []}) {
  const writes = [];
  const values = new Map([
    ['users/teacher', {
      full_name: 'Grace Hopper', role: 'Teacher', lifecycle_state: 'active',
    }],
    ['groups/g1', {teacher_id: 'teacher', name: 'BSHM 4A', status: 'active'}],
    ...documents,
    ...recipientIds.map((id) => [
      `group_memberships/g1_${id}`,
      {
        group_id: 'g1', teacher_id: 'teacher', trainee_id: id,
        status: 'approved',
      },
    ]),
  ]);
  const makeRef = (path, id) => ({
    path,
    id,
    parent: {id: path.split('/').at(-2)},
    collection(name) {
      return {
        doc(childId) {
          return makeRef(`${path}/${name}/${childId}`, childId);
        },
      };
    },
  });
  const database = {
    collection(name) {
      return {
        doc(id) {
          const resolved = id || 'assignment-created';
          return makeRef(`${name}/${resolved}`, resolved);
        },
      };
    },
    async runTransaction(callback) {
      const transaction = {
        async get(ref) {
          const data = values.get(ref.path);
          return {
            exists: Boolean(data),
            get: (field) => data?.[field],
            data: () => data,
          };
        },
        create(ref, data) {
          writes.push({path: ref.path, data});
        },
      };
      return callback(transaction);
    },
    writes,
  };
  return database;
}

function updateAssessment({maximum = 50} = {}) {
  const value = activityAssessment({maximum});
  value.schema_version = 3;
  value.readiness = {hands: value.readiness.hands, body: value.readiness.body};
  delete value.attempt_policy;
  return value;
}

function fakeActivityUpdateDatabase({consumedCounts = []} = {}) {
  const writes = [];
  let assignment = {
    teacher_id: 'teacher',
    group_id: 'g1',
    movement_id: 'movement-fixed',
    revision_id: 'revision-fixed',
    origin: 'teacher_created',
    assessment_mode: 'teacher_reviewed',
    status: 'active',
    display_title: 'Original Activity',
    display_instructions: 'Original instructions.',
    teacher_display_name: 'Grace Hopper',
    group_name: 'BSHM 4A',
    audience_type: 'entire_class',
    allowed_prop: 'bottle',
    max_score: 50,
    attempt_policy: {type: 'finite', maximum_attempts: 3},
    activity_assessment: updateAssessment(),
    configuration_revision: 1,
  };
  const assignmentRef = {
    id: 'assignment-1',
    path: 'group_assignments/assignment-1',
    collection(name) {
      assert.equal(name, 'assignment_recipients');
      return {
        async get() { return {docs: []}; },
        doc(id) { return {id, path: `${assignmentRef.path}/${name}/${id}`}; },
      };
    },
  };
  const database = {
    collection(name) {
      if (name === 'group_assignments') {
        return {doc(id) { assert.equal(id, assignmentRef.id); return assignmentRef; }};
      }
      if (name === 'assignment_attempt_states') {
        return {
          where(field, operator, value) {
            assert.deepEqual([field, operator, value], ['assignment_id', '==', assignmentRef.id]);
            return {kind: 'attempt_states'};
          },
        };
      }
      if (name === 'group_memberships') {
        return {doc(id) { return {id, kind: 'membership'}; }};
      }
      throw new Error(`Unexpected collection ${name}`);
    },
    async runTransaction(callback) {
      return callback({
        async get(target) {
          if (target === assignmentRef) {
            return {exists: true, data: () => assignment};
          }
          if (target.kind === 'attempt_states') {
            return {docs: consumedCounts.map((count) => ({get: () => count}))};
          }
          if (target.kind === 'membership') return {exists: false};
          throw new Error('Unexpected transaction read');
        },
        update(ref, data) {
          assert.equal(ref, assignmentRef);
          assignment = {...assignment, ...data};
          writes.push({type: 'update', data});
        },
        set(ref, data) { writes.push({type: 'set', ref, data}); },
        delete(ref) { writes.push({type: 'delete', ref}); },
      });
    },
    get assignment() { return assignment; },
    writes,
  };
  return database;
}

function activityUpdateBody(overrides = {}) {
  return {
    assignment_id: 'assignment-1',
    expected_configuration_revision: 1,
    display_title: 'Edited Activity',
    display_instructions: 'Record the complete movement.',
    display_safety_guidance: 'Keep the floor dry.',
    topic: 'Bottle control',
    due_at: '2026-09-15T00:00:00.000Z',
    audience_type: 'entire_class',
    recipient_ids: [],
    activity_assessment: updateAssessment(),
    attempt_policy: {type: 'finite', maximum_attempts: 2},
    allowed_prop: 'bottle_and_shaker',
    ...overrides,
  };
}

test('Teacher Activity assignment updates round-trip twice and reject stale edits', async () => {
  const database = fakeActivityUpdateDatabase();
  const options = {
    authenticate: async () => 'teacher',
    databaseFactory: () => database,
  };
  const firstResponse = fakeResponse();
  await updateTeacherActivityAssignmentHandler(
    {method: 'POST', body: activityUpdateBody()},
    firstResponse,
    options,
  );
  assert.equal(firstResponse.statusCode, 200);
  assert.equal(firstResponse.body.assignment.configuration_revision, 2);
  assert.equal(firstResponse.body.assignment.display_title, 'Edited Activity');
  assert.equal(firstResponse.body.assignment.display_safety_guidance, 'Keep the floor dry.');
  assert.equal(firstResponse.body.assignment.topic, 'Bottle control');
  assert.equal(firstResponse.body.assignment.allowed_prop, 'bottle_and_shaker');
  assert.equal(firstResponse.body.assignment.movement_id, 'movement-fixed');
  assert.equal(firstResponse.body.assignment.revision_id, 'revision-fixed');

  const secondResponse = fakeResponse();
  await updateTeacherActivityAssignmentHandler(
    {method: 'POST', body: activityUpdateBody({
      expected_configuration_revision: 2,
      display_title: 'Edited Again',
      activity_assessment: updateAssessment({maximum: 100}),
    })},
    secondResponse,
    options,
  );
  assert.equal(secondResponse.statusCode, 200);
  assert.equal(secondResponse.body.assignment.configuration_revision, 3);
  assert.equal(secondResponse.body.assignment.display_title, 'Edited Again');
  assert.equal(secondResponse.body.assignment.max_score, 100);

  const staleResponse = fakeResponse();
  await updateTeacherActivityAssignmentHandler(
    {method: 'POST', body: activityUpdateBody()},
    staleResponse,
    options,
  );
  assert.equal(staleResponse.statusCode, 409);
  assert.deepEqual(staleResponse.body, {error: 'conflict'});
  assert.equal(database.assignment.display_title, 'Edited Again');
});

test('Teacher Activity assignment update returns actionable validation conflicts', async () => {
  const attemptDatabase = fakeActivityUpdateDatabase({consumedCounts: [3]});
  const attemptResponse = fakeResponse();
  await updateTeacherActivityAssignmentHandler(
    {method: 'POST', body: activityUpdateBody()},
    attemptResponse,
    {
      authenticate: async () => 'teacher',
      databaseFactory: () => attemptDatabase,
    },
  );
  assert.equal(attemptResponse.statusCode, 409);
  assert.deepEqual(attemptResponse.body, {error: 'attempt_limit_conflict'});

  const recipientDatabase = fakeActivityUpdateDatabase();
  const recipientResponse = fakeResponse();
  await updateTeacherActivityAssignmentHandler(
    {method: 'POST', body: activityUpdateBody({
      audience_type: 'individual_student',
      recipient_ids: ['trainee-missing'],
    })},
    recipientResponse,
    {
      authenticate: async () => 'teacher',
      databaseFactory: () => recipientDatabase,
    },
  );
  assert.equal(recipientResponse.statusCode, 409);
  assert.deepEqual(recipientResponse.body, {error: 'invalid_recipient'});
});

test('normalizes diacritics and whitespace for private directory search', () => {
  assert.equal(normalizeSearchText('  José   DELA Cruz '), 'jose dela cruz');
  assert.ok(buildSearchPrefixes('José Dela Cruz').includes('cru'));
  assert.ok(buildSearchPrefixes('José Dela Cruz').includes('jose d'));
});

test('conversation id is deterministic for either participant order', () => {
  assert.equal(conversationIdFor('uid-b', 'uid-a'), 'uid-a__uid-b');
  assert.equal(conversationIdFor('uid-a', 'uid-b'), 'uid-a__uid-b');
});

test('search result never exposes email or search prefixes', () => {
  const result = sanitizedResult('uid-1', {
    display_name: 'Sample User',
    role: 'Teacher',
    avatar_url: 'https://example.test/avatar.png',
    email: 'private@example.test',
    search_prefixes: ['sa'],
  });
  assert.deepEqual(Object.keys(result).sort(), [
    'avatar_url',
    'display_name',
    'id',
    'role',
  ]);
});

test('search query bounds distinguish exact email from name prefix', () => {
  assert.equal(validateSearchQuery('a').valid, false);
  assert.equal(validateSearchQuery('a'.repeat(81)).valid, false);
  assert.deepEqual(
    validateSearchQuery(' PERSON@EXAMPLE.TEST '),
    {
      valid: true,
      raw: 'PERSON@EXAMPLE.TEST',
      normalized: 'person@example.test',
      emailShaped: true,
    },
  );
  assert.equal(validateSearchQuery('Dela').emailShaped, false);
});

test('directory filtering excludes caller, deleting rows, bad roles, and caps results', () => {
  const documents = [
    {id: 'caller', data: () => ({display_name: 'Caller', role: 'Trainee', lifecycle_state: 'active'})},
    {id: 'deleting', data: () => ({display_name: 'Deleting', role: 'Teacher', lifecycle_state: 'deleting'})},
    {id: 'admin', data: () => ({display_name: 'Admin', role: 'Admin', lifecycle_state: 'active'})},
    ...Array.from({length: 25}, (_, index) => ({
      id: `user-${index}`,
      data: () => ({display_name: `User ${index}`, role: 'Teacher', lifecycle_state: 'active'}),
    })),
  ];
  const results = sanitizeDirectoryDocuments('caller', documents);
  assert.equal(results.length, 20);
  assert.ok(results.every((result) => !('email' in result)));
  assert.ok(results.every((result) => result.id !== 'caller'));
});

test('rate limit boundary is deterministic', () => {
  assert.equal(isSearchRateLimited(1000, 1499), true);
  assert.equal(isSearchRateLimited(1000, 1500), false);
});

test('missing bearer authentication is rejected before token verification', async () => {
  assert.equal(await authenticatedUid({get: () => ''}), null);
});

test('assignment audience filtering preserves legacy and recipient privacy', () => {
  assert.equal(assignmentAudienceAllows({}, 'trainee-a'), true);
  assert.equal(assignmentAudienceAllows({
    audience_type: 'entire_class',
  }, 'trainee-a'), true);
  assert.equal(assignmentAudienceAllows({
    audience_type: 'selected_students', group_id: 'g1', teacher_id: 'teacher-a',
  }, 'trainee-a', {
    assignment_id: 'assignment-1', group_id: 'g1', teacher_id: 'teacher-a',
    trainee_id: 'trainee-a', audience_type: 'selected_students', schema_version: 1,
    created_at: {toDate: () => new Date('2026-08-31T00:00:00.000Z')},
  }, 'assignment-1'), true);
  assert.equal(assignmentAudienceAllows({
    audience_type: 'selected_students', group_id: 'g1', teacher_id: 'teacher-a',
  }, 'trainee-a'), false);
  assert.equal(assignmentAudienceAllows({
    audience_type: 'selected_students', target_trainee_ids: ['trainee-a'],
  }, 'trainee-a'), false);
});

test('assignment creation accepts an uncapped targeted subset atomically', async () => {
  const recipientIds = Array.from({length: 12}, (_, index) => `trainee-${index}`);
  const database = fakeCreationDatabase({recipientIds});
  const response = fakeResponse();
  await createClassroomAssignmentHandler(
    {
      method: 'POST',
      body: {
        group_id: 'g1',
        audience_type: 'selected_students',
        recipient_ids: recipientIds,
        origin: 'official_elixr',
        official_movement_name: 'Hand Stall',
        topic: '  Bottle control  ',
      },
      get: () => '',
    },
    response,
    {
      verifyToken: async () => ({uid: 'teacher', email_verified: true, role: 'Teacher'}),
      databaseFactory: () => database,
    },
  );

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.body.recipient_ids, recipientIds);
  assert.equal(database.writes.length, recipientIds.length + 1);
  const assignmentWrite = database.writes.find((write) =>
    write.path === 'group_assignments/assignment-created');
  assert.ok(assignmentWrite);
  assert.equal('target_trainee_ids' in assignmentWrite.data, false);
  assert.equal(assignmentWrite.data.audience_type, 'selected_students');
  assert.equal(assignmentWrite.data.topic, 'Bottle control');
  assert.equal(
    database.writes.filter((write) =>
      write.path.includes('/assignment_recipients/')).length,
    recipientIds.length,
  );
});

test('assignment creation accepts a current Teacher Activity revision for the entire class', async () => {
  const database = fakeCreationDatabase({
    recipientIds: [],
    documents: [
      ['teacher_movements/movement-1', {
        teacher_id: 'teacher', status: 'active', current_revision_id: 'revision-1',
        title: 'Tin Balance',
      }],
      ['teacher_movements/movement-1/revisions/revision-1', {
        teacher_id: 'teacher', movement_id: 'movement-1',
        assessment_mode: 'teacher_reviewed',
        spec: {
          capability: 'teacher_review_only',
          instructions: 'Balance the bottle upright.', required_prop: 'bottle',
        },
      }],
    ],
  });
  const response = fakeResponse();
  await createClassroomAssignmentHandler(
    {
      method: 'POST',
      body: {
        group_id: 'g1', audience_type: 'entire_class', recipient_ids: [],
        origin: 'teacher_created', movement_id: 'movement-1', revision_id: 'revision-1',
        max_score: 50, attempt_policy: {type: 'unlimited'},
      },
      get: () => '',
    },
    response,
    {
      verifyToken: async () => ({uid: 'teacher', email_verified: true, role: 'Teacher'}),
      databaseFactory: () => database,
    },
  );

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.body.recipient_ids, []);
  const assignmentWrite = database.writes.find((write) =>
    write.path === 'group_assignments/assignment-created');
  assert.equal(assignmentWrite.data.origin, 'teacher_created');
  assert.equal(assignmentWrite.data.revision_id, 'revision-1');
  assert.equal(assignmentWrite.data.display_instructions, 'Balance the bottle upright.');
});

function teacherActivityDocuments({root = {}, revision = {}} = {}) {
  return [
    ['teacher_movements/movement-1', {
      teacher_id: 'teacher', status: 'active', current_revision_id: 'revision-1',
      title: 'Tin Balance', ...root,
    }],
    ['teacher_movements/movement-1/revisions/revision-1', {
      teacher_id: 'teacher', movement_id: 'movement-1',
      assessment_mode: 'teacher_reviewed',
      spec: {
        capability: 'teacher_review_only',
        instructions: 'Balance the bottle upright.',
        required_prop: 'bottle',
      },
      ...revision,
    }],
  ];
}

function teacherActivityCreationBody(overrides = {}) {
  return {
    group_id: 'g1', audience_type: 'entire_class', recipient_ids: [],
    origin: 'teacher_created', movement_id: 'movement-1', revision_id: 'revision-1',
    max_score: 50, attempt_policy: {type: 'unlimited'},
    ...overrides,
  };
}

async function createTeacherActivityAssignment({documents, body} = {}) {
  const response = fakeResponse();
  await createClassroomAssignmentHandler(
    {method: 'POST', body: body || teacherActivityCreationBody(), get: () => ''},
    response,
    {
      verifyToken: async () => ({uid: 'teacher', email_verified: true, role: 'Teacher'}),
      databaseFactory: () => fakeCreationDatabase({
        recipientIds: [], documents: documents || teacherActivityDocuments(),
      }),
    },
  );
  return response;
}

test('assignment creation accepts the current persisted Teacher Activity v3 shape', async () => {
  const assessment = updateAssessment();
  const response = await createTeacherActivityAssignment({
    documents: teacherActivityDocuments({
      revision: {schema_version: 2, spec: {
        capability: 'teacher_review_only', instructions: 'Balance the bottle upright.',
        required_prop: 'bottle', activity_assessment: assessment,
      }},
    }),
    body: teacherActivityCreationBody({activity_assessment: assessment}),
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.assignment.activity_assessment.schema_version, 3);
});

test('assignment creation accepts a supported legacy Teacher Activity assessment', async () => {
  const legacyAssessment = activityAssessment();
  const response = await createTeacherActivityAssignment({
    documents: teacherActivityDocuments({revision: {spec: {
      capability: 'teacher_review_only', instructions: 'Balance the bottle upright.',
      required_prop: 'bottle', activity_assessment: legacyAssessment,
    }}}),
  });
  assert.equal(response.statusCode, 200);
  assert.equal(response.body.assignment.activity_assessment.schema_version, 2);
});

test('Teacher Activity creation returns distinct invariant errors', async () => {
  const cases = [
    [{root: {current_revision_id: 'revision-2'}}, 'stale_revision'],
    [{root: {status: 'archived'}}, 'movement_archived'],
    [{root: {teacher_id: 'another-teacher'}}, 'invalid_movement_owner'],
    [{revision: {spec: {capability: 'teacher_review_only', instructions: 'Balance.', required_prop: 'glass'}}}, 'invalid_movement_spec'],
    [{}, 'invalid_activity_assessment', teacherActivityCreationBody({
      activity_assessment: {...updateAssessment(), recording_duration_seconds: 20},
    })],
  ];
  for (const [overrides, expected, body] of cases) {
    const response = await createTeacherActivityAssignment({
      documents: teacherActivityDocuments(overrides), body,
    });
    assert.equal(response.statusCode, 400);
    assert.deepEqual(response.body, {error: expected});
  }
});

test('assignment JSON timestamps are converted recursively', () => {
  const timestamp = {toDate: () => new Date('2026-08-31T00:00:00.000Z')};
  assert.deepEqual(assignmentJsonValue({created_at: timestamp}), {
    created_at: '2026-08-31T00:00:00.000Z',
  });
});

test('trainee assignment handler authenticates, scopes, and filters', async () => {
  const timestamp = {toDate: () => new Date('2026-08-31T00:00:00.000Z')};
  const database = fakeAssignmentDatabase({
    memberships: [
      {
        id: 'g1_trainee-a',
        data: {
          trainee_id: 'trainee-a',
          teacher_id: 'teacher-a',
          group_id: 'g1',
          status: 'approved',
        },
      },
      {
        id: 'g2_trainee-a',
        data: {
          trainee_id: 'trainee-a',
          teacher_id: 'teacher-a',
          group_id: 'g2',
          status: 'removed',
        },
      },
    ],
    assignments: [
      {
        id: 'legacy',
        data: {
          group_id: 'g1',
          teacher_id: 'teacher-a',
          created_at: timestamp,
        },
      },
      {
        id: 'selected',
        data: {
          group_id: 'g1',
          teacher_id: 'teacher-a',
          audience_type: 'selected_students',
        },
      },
      {
        id: 'not-targeted',
        data: {
          group_id: 'g1',
          teacher_id: 'teacher-a',
          audience_type: 'individual_student',
        },
      },
      {
        id: 'archived',
        data: {
          group_id: 'g1',
          teacher_id: 'teacher-a',
          audience_type: 'entire_class',
          status: 'archived',
        },
      },
      {
        id: 'wrong-owner',
        data: {group_id: 'g1', teacher_id: 'teacher-b'},
      },
      {
        id: 'malformed',
        data: {
          group_id: 'g1',
          teacher_id: 'teacher-a',
          audience_type: 'selected_students',
        },
      },
    ],
    recipients: [
      {assignmentId: 'selected', traineeId: 'trainee-a', data: {
        assignment_id: 'selected', group_id: 'g1', teacher_id: 'teacher-a',
        trainee_id: 'trainee-a', audience_type: 'selected_students', schema_version: 1,
        created_at: timestamp,
      }},
    ],
  });
  const response = fakeResponse();

  await listTraineeAssignmentsHandler(
    {method: 'GET', query: {group_id: 'g1'}},
    response,
    {
      authenticate: async () => 'trainee-a',
      databaseFactory: () => database,
    },
  );

  assert.equal(response.statusCode, 200);
  assert.deepEqual(response.body.assignments.map((item) => item.id), [
    'legacy',
    'selected',
    'archived',
  ]);
  assert.equal(
    response.body.assignments[0].created_at,
    '2026-08-31T00:00:00.000Z',
  );
  assert.deepEqual(database.assignmentQueries, [{operator: '==', value: 'g1'}]);
});

test('trainee assignment handler rejects missing auth before database access', async () => {
  const response = fakeResponse();
  let databaseAccessed = false;

  await listTraineeAssignmentsHandler(
    {method: 'GET', query: {}},
    response,
    {
      authenticate: async () => null,
      databaseFactory: () => {
        databaseAccessed = true;
        throw new Error('should not be called');
      },
    },
  );

  assert.equal(response.statusCode, 401);
  assert.deepEqual(response.body, {error: 'unauthenticated'});
  assert.equal(databaseAccessed, false);
});

test('trainee assignment handler chunks classroom queries at thirty', async () => {
  const memberships = Array.from({length: 31}, (_, index) => ({
    id: `g${index}_trainee-a`,
    data: {
      trainee_id: 'trainee-a',
      teacher_id: 'teacher-a',
      group_id: `g${index}`,
      status: 'approved',
    },
  }));
  const assignments = memberships.map((membership, index) => ({
    id: `assignment-${index}`,
    data: {
      group_id: membership.data.group_id,
      teacher_id: 'teacher-a',
      audience_type: 'entire_class',
    },
  }));
  const database = fakeAssignmentDatabase({memberships, assignments});
  const response = fakeResponse();

  await listTraineeAssignmentsHandler(
    {method: 'GET', query: {}},
    response,
    {
      authenticate: async () => 'trainee-a',
      databaseFactory: () => database,
    },
  );

  assert.equal(response.statusCode, 200);
  assert.equal(response.body.assignments.length, 31);
  assert.equal(database.assignmentQueries.length, 2);
  assert.equal(database.assignmentQueries[0].value.length, 30);
  assert.equal(database.assignmentQueries[1].operator, '==');
});

test('account erasure excludes deleting profiles and builds idempotent archives', () => {
  assert.equal(isActiveChatProfile({role: 'Teacher'}), true);
  assert.equal(
    isActiveChatProfile({role: 'Trainee', lifecycle_state: 'deleting'}),
    false,
  );
  assert.equal(
    archivedConversationId('alice__bob', ['bob']),
    archivedConversationId('alice__bob', ['bob']),
  );

  const archivedAt = Symbol('server timestamp');
  const archived = buildArchivedConversationData({
    data: {
      participant_ids: ['alice', 'bob'],
      participant_snapshots: {
        alice: {id: 'alice', display_name: 'Alice', role: 'Trainee'},
        bob: {id: 'bob', display_name: 'Bob', role: 'Teacher'},
      },
      last_message_sender_id: 'alice',
      unread_counts: {alice: 0, bob: 2},
      read_at: {alice: 1, bob: null},
      status: 'active',
      deleted_user_id: 'alice',
    },
    deletedUid: 'alice',
    activeProfiles: new Map([
      ['bob', {full_name: 'Bob', role: 'Teacher'}],
    ]),
    archivedAt,
  });
  assert.deepEqual(archived.participant_ids, ['bob', 'deleted_user']);
  assert.equal(archived.participant_a, 'bob');
  assert.equal(archived.participant_b, 'deleted_user');
  assert.equal(archived.participant_snapshots.deleted_user.display_name, 'Deleted user');
  assert.equal(archived.last_message_sender_id, 'deleted_user');
  assert.deepEqual(archived.unread_counts, {bob: 2});
  assert.deepEqual(archived.read_at, {bob: null});
  assert.equal(archived.status, 'archived');
  assert.equal(archived.archived_at, archivedAt);
  assert.equal('deleted_user_id' in archived, false);
});

test('migration message ids are deterministic and summary never regresses', () => {
  assert.equal(legacyMessageId('note-1'), legacyMessageId('note-1'));
  assert.notEqual(legacyMessageId('note-1'), legacyMessageId('note-2'));
  assert.equal(
    shouldReplaceConversationSummary(
      {exists: true, lastMessageAt: new Date('2026-08-24T02:00:00Z')},
      new Date('2026-08-24T01:00:00Z'),
    ),
    false,
  );
  const createdAt = new Date('2026-08-24T01:00:00Z');
  const updatedAt = new Date('2026-08-24T01:05:00Z');
  const migratedAt = Symbol('migration timestamp');
  assert.deepEqual(
    legacyMessageData({
      id: 'note-1',
      teacher_id: 'teacher',
      body: 'Keep your wrist level.',
      movement_name: 'Hand Stall',
      created_at: createdAt,
      updated_at: updatedAt,
    }, migratedAt),
    {
      sender_id: 'teacher',
      body: 'Keep your wrist level.',
      created_at: createdAt,
      edited_at: updatedAt,
      deleted_at: null,
      legacy_coaching: {
        source_note_id: 'note-1',
        movement_name: 'Hand Stall',
        migrated_at: migratedAt,
      },
    },
  );
});

test('dry-run migration write gate executes no actions', async () => {
  let writes = 0;
  const actions = [async () => { writes += 1; }];
  assert.equal(await executeMigrationWrites({write: false, actions}), 0);
  assert.equal(writes, 0);
  assert.equal(await executeMigrationWrites({write: true, actions}), 1);
  assert.equal(writes, 1);
});

function reconciliationSnapshot(data) {
  return {
    get exists() { return data.value != null; },
    data: () => data.value,
    get: (field) => data.value?.[field],
  };
}

function fakeReconciliationFirestore({deleting = [], pending = [], failDeleting = new Set()} = {}) {
  const state = {value: {cursors: {}}};
  const access = new Map();
  const assignment = {id: 'assignment', data: {teacher_id: 'teacher', status: 'draft'}};
  const records = [...deleting, ...pending].map((record) => ({...record}));
  const attempts = [];

  function merge(target, patch) {
    for (const [key, value] of Object.entries(patch)) {
      if (key === 'cursors' && value && typeof value === 'object') {
        target.cursors ||= {};
        for (const [cursorKey, cursor] of Object.entries(value)) {
          // FieldValue.delete() has no cursor shape. This is sufficient for
          // the state written by the reconciliation code under test.
          if (!cursor?.document_id) delete target.cursors[cursorKey];
          else target.cursors[cursorKey] = cursor;
        }
      } else {
        target[key] = value;
      }
    }
  }

  const stateRef = {
    id: 'v1',
    get: async () => reconciliationSnapshot(state),
    set: async (patch) => merge(state.value, patch),
  };
  const assignmentRef = {
    id: assignment.id,
    get: async () => ({exists: true, data: () => assignment.data, get: (field) => assignment.data[field]}),
    collection(name) {
      assert.equal(name, 'learning_materials');
      return query('assignment_materials');
    },
  };

  function document(record) {
    const ref = {
      id: record.id,
      parent: {parent: assignmentRef},
      get: async () => ({
        exists: !record.deleted, data: () => record, get: (field) => record[field],
      }),
      async delete() {
        if (record.status === 'deleting' && failDeleting.has(record.id)) {
          throw new Error(`delete failed for ${record.id}`);
        }
        record.deleted = true;
      },
      async set(patch) { merge(record, patch); },
    };
    return {
      id: record.id,
      ref,
      data: () => record,
      get: (field) => record[field],
    };
  }

  function query(kind, options = {}) {
    const filters = [...(options.filters || [])];
    let cursor = options.cursor;
    let limit = options.limit;
    return {
      where(field, operator, value) {
        return query(kind, {filters: [...filters, {field, operator, value}], cursor, limit});
      },
      orderBy() { return query(kind, {filters, cursor, limit}); },
      startAfter(_value, documentId) {
        return query(kind, {filters, cursor: documentId, limit});
      },
      limit(value) { return query(kind, {filters, cursor, limit: value}); },
      async get() {
        let values = kind === 'material_group' || kind === 'assignment_materials'
          ? records.filter((record) => !record.deleted) : [];
        for (const filter of filters) {
          if (filter.operator === '==') values = values.filter((record) => record[filter.field] === filter.value);
        }
        values.sort((left, right) => left.id.localeCompare(right.id));
        if (cursor) values = values.filter((record) => record.id > cursor);
        if (limit != null) values = values.slice(0, limit);
        const docs = values.map(document);
        return {docs, size: docs.length, empty: docs.length === 0};
      },
    };
  }

  const firestore = {
    attempts,
    state,
    collection(name) {
      if (name === 'activity_material_reconciliation_state') return {doc: () => stateRef};
      if (name === 'activity_material_access_state') {
        return {doc: () => ({
          get: async () => reconciliationSnapshot(state),
          set: async (patch) => merge(state.value, patch),
        })};
      }
      if (name === 'activity_material_access') {
        return {
          where: () => query('access'),
          doc: (id) => ({set: async (value) => access.set(id, value)}),
        };
      }
      if (name === 'activity_material_uploads') return {where: () => query('uploads')};
      if (name === 'group_memberships') return {where: () => query('memberships'), doc: () => ({get: async () => ({exists: false})})};
      throw new Error(`unexpected collection ${name}`);
    },
    collectionGroup(name) {
      assert.equal(name, 'learning_materials');
      return query('material_group');
    },
    batch() { return {delete: () => undefined, commit: async () => undefined}; },
    async runTransaction(callback) {
      return callback({
        get: async (ref) => ref.get(),
        set: (ref, patch) => ref.set(patch),
        update: (ref, patch) => ref.set(patch),
      });
    },
  };
  const storage = {
    bucket: () => ({file: (path) => ({delete: async () => attempts.push(path)})}),
  };
  return {firestore, storage, records, attempts, failDeleting};
}

test('Learning Material reconciliation advances past 100 records, retries failures, and resets cursors', async () => {
  const deleting = Array.from({length: 101}, (_, index) => ({
    id: `delete-${String(index).padStart(3, '0')}`,
    status: 'deleting', deletion_requested_at: index,
    storage_path: `activity_learning_materials/assignment/delete-${index}`,
  }));
  const pending = Array.from({length: 101}, (_, index) => ({
    id: `pending-${String(index).padStart(3, '0')}`,
    material_id: `pending-${String(index).padStart(3, '0')}`,
    assignment_id: 'assignment', status: 'ready', projection_sync_state: 'pending', created_at: index,
  }));
  const fake = fakeReconciliationFirestore({
    deleting, pending, failDeleting: new Set(['delete-000']),
  });
  const now = {toMillis: () => Date.now()};

  const originalConsoleError = console.error;
  console.error = () => undefined;
  try {
    await runActivityMaterialReconciliation({firestore: fake.firestore, storage: fake.storage, now});
  } finally {
    console.error = originalConsoleError;
  }
  assert.equal(fake.records.find((record) => record.id === 'delete-100').deleted, undefined);
  assert.equal(fake.records.find((record) => record.id === 'pending-100').projection_sync_state, 'pending');
  assert.equal(fake.firestore.state.value.cursors.deleting_material.document_id, 'delete-099');
  assert.equal(fake.firestore.state.value.cursors.pending_projection.document_id, 'pending-099');

  await runActivityMaterialReconciliation({firestore: fake.firestore, storage: fake.storage, now});
  assert.equal(fake.records.find((record) => record.id === 'delete-100').deleted, true);
  assert.equal(fake.records.find((record) => record.id === 'pending-100').projection_sync_state, 'ready');
  assert.equal(fake.firestore.state.value.cursors.deleting_material, undefined);
  assert.equal(fake.firestore.state.value.cursors.pending_projection, undefined);

  fake.failDeleting.clear();
  await runActivityMaterialReconciliation({firestore: fake.firestore, storage: fake.storage, now});
  assert.equal(fake.records.find((record) => record.id === 'delete-000').deleted, true);
  assert.ok(fake.attempts.includes('activity_learning_materials/assignment/delete-100'));
});

function fakeMaterialRemovalDatabase() {
  const material = {
    material_id: 'material-a', assignment_id: 'assignment', owner_teacher_id: 'teacher',
    status: 'ready', storage_path: 'activity_learning_materials/assignment/material-a',
  };
  const otherMaterial = {material_id: 'material-b', status: 'ready'};
  const state = {
    assignment_id: 'assignment', generation: 1, state: 'ready', schema_version: 1,
    revoked_material_ids: [],
  };
  const access = [
    {assignment_id: 'assignment', material_id: 'material-a', user_id: 'targeted'},
    {assignment_id: 'assignment', material_id: 'material-b', user_id: 'targeted'},
  ];
  const snapshot = (data) => ({
    get exists() { return data.value != null; },
    data: () => data.value,
    get: (field) => data.value?.[field],
  });
  const update = (data, patch) => Object.assign(data.value, patch);
  const stateValue = {value: state};
  const materialValue = {value: material};
  const assignmentValue = {value: {teacher_id: 'teacher'}};
  const userValue = {value: {role: 'Teacher'}};
  const stateRef = {get: async () => snapshot(stateValue), set: async (patch) => update(stateValue, patch)};
  const materialRef = {
    get: async () => snapshot(materialValue),
    set: async (patch) => update(materialValue, patch),
    delete: async () => { materialValue.value = null; },
  };
  const assignmentRef = {
    id: 'assignment',
    get: async () => snapshot(assignmentValue),
    collection(name) {
      assert.equal(name, 'learning_materials');
      return {
        doc: () => materialRef,
        where: () => ({get: async () => ({
          docs: materialValue.value ? [] : [{get: (field) => otherMaterial[field], ref: {delete: async () => undefined}}],
        })}),
      };
    },
  };
  const query = (filters = []) => ({
    where: (field, operator, value) => query([...filters, {field, operator, value}]),
    limit: () => query(filters),
    get: async () => {
      const docs = access.filter((entry) => !entry.deleted && filters.every((filter) =>
        filter.operator === '==' && entry[filter.field] === filter.value,
      )).map((entry) => ({
        get: (field) => entry[field],
        ref: {delete: async () => { entry.deleted = true; }},
      }));
      return {docs, size: docs.length, empty: docs.length === 0};
    },
  });
  return {
    state,
    material,
    materialExists: () => materialValue.value != null,
    access,
    collection(name) {
      if (name === 'group_assignments') return {doc: () => assignmentRef};
      if (name === 'users') return {doc: () => ({get: async () => snapshot(userValue)})};
      if (name === 'activity_material_access_state') return {doc: () => stateRef};
      if (name === 'activity_material_access') return {where: () => query()};
      if (name === 'activity_material_uploads') return {where: () => ({get: async () => ({docs: []})})};
      throw new Error(`unexpected collection ${name}`);
    },
    batch() {
      const deletes = [];
      return {delete: (ref) => deletes.push(ref), commit: async () => Promise.all(deletes.map((ref) => ref.delete()))};
    },
    async runTransaction(callback) {
      return callback({
        get: async (ref) => ref.get(),
        set: (ref, patch) => ref.set(patch),
      });
    },
  };
}

test('Learning Material removal revokes before Storage deletion and retains revocation on failure', async () => {
  const database = fakeMaterialRemovalDatabase();
  const objectDeletes = [];
  let failDelete = true;
  const storageFactory = () => ({bucket: () => ({file: (path) => ({delete: async () => {
    objectDeletes.push({path, revoked: [...database.state.revoked_material_ids]});
    if (failDelete) throw new Error('storage unavailable');
  }})})});
  const request = {method: 'POST', body: {assignment_id: 'assignment', material_id: 'material-a'}};

  const failed = fakeResponse();
  const originalConsoleError = console.error;
  console.error = () => undefined;
  try {
    await removeActivityLearningMaterialHandler(request, failed, {
      authenticate: async () => 'teacher', databaseFactory: () => database, storageFactory,
    });
  } finally {
    console.error = originalConsoleError;
  }
  assert.equal(failed.statusCode, 503);
  assert.equal(database.material.status, 'deleting');
  assert.deepEqual(database.state.revoked_material_ids, ['material-a']);
  assert.deepEqual(objectDeletes[0].revoked, ['material-a']);
  assert.equal(database.access.find((entry) => entry.material_id === 'material-b').deleted, undefined);

  failDelete = false;
  // Model an old synchronizer that wrote after the first revocation. The
  // idempotent cleanup path must remove it before clearing the marker.
  database.access.find((entry) => entry.material_id === 'material-a').deleted = false;
  const retried = fakeResponse();
  await removeActivityLearningMaterialHandler(request, retried, {
    authenticate: async () => 'teacher', databaseFactory: () => database, storageFactory,
  });
  assert.equal(retried.statusCode, 200);
  assert.equal(database.materialExists(), false);
  assert.deepEqual(database.state.revoked_material_ids, []);
  assert.equal(database.access.find((entry) => entry.material_id === 'material-a').deleted, true);

  // If a prior process failed only after metadata deletion, its idempotent
  // retry removes a stale projection before releasing the retained marker.
  database.state.revoked_material_ids = ['material-a'];
  database.access.find((entry) => entry.material_id === 'material-a').deleted = false;
  const cleanup = fakeResponse();
  await removeActivityLearningMaterialHandler(request, cleanup, {
    authenticate: async () => 'teacher', databaseFactory: () => database, storageFactory,
  });
  assert.equal(cleanup.statusCode, 200);
  assert.equal(database.access.find((entry) => entry.material_id === 'material-a').deleted, true);
  assert.deepEqual(database.state.revoked_material_ids, []);
});

test('Learning Material projection sync does not publish a stale deleting material snapshot', async () => {
  const state = {
    assignment_id: 'assignment', generation: 1, state: 'ready', schema_version: 1,
    revoked_material_ids: [],
  };
  const writes = [];
  const materialDocs = ['material-a', 'material-b'].map((id) => {
    const data = {
      material_id: id, assignment_id: 'assignment',
      status: id === 'material-a' ? 'deleting' : 'ready',
    };
    return {
      id,
      get: (field) => data[field],
      ref: {
        id,
        get: async () => ({exists: true, data: () => data, get: (field) => data[field]}),
        set: async () => undefined,
      },
    };
  });
  const stateRef = {get: async () => ({exists: true, data: () => state, get: (field) => state[field]}),
    set: async (patch) => Object.assign(state, patch)};
  const assignmentRef = {
    id: 'assignment',
    get: async () => ({exists: true, data: () => ({teacher_id: 'teacher', status: 'draft'})}),
    collection: () => ({where: () => ({get: async () => ({docs: materialDocs, empty: false})})}),
  };
  const emptyQuery = () => ({where: () => emptyQuery(), limit: () => emptyQuery(), get: async () => ({docs: [], empty: true})});
  const firestore = {
    collection(name) {
      if (name === 'activity_material_access_state') return {doc: () => stateRef};
      if (name === 'activity_material_access') return {where: () => emptyQuery(), doc: (id) => ({set: async () => writes.push(id)})};
      throw new Error(`unexpected collection ${name}`);
    },
    batch: () => ({delete: () => undefined, commit: async () => undefined}),
    runTransaction: async (callback) => callback({get: async (ref) => ref.get(), set: (ref, patch) => ref.set(patch)}),
  };
  await syncActivityMaterialAccess({firestore, assignmentRef});
  assert.equal(writes.some((id) => id.includes('material-a')), false);
  assert.equal(writes.some((id) => id.includes('material-b')), true);
  assert.deepEqual(state.revoked_material_ids, []);
});
