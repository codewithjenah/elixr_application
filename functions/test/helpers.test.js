const assert = require('node:assert/strict');
const test = require('node:test');

const {
  archivedConversationId,
  assignmentAudienceAllows,
  assignmentJsonValue,
  createClassroomAssignmentHandler,
  authenticatedUid,
  buildArchivedConversationData,
  buildSearchPrefixes,
  conversationIdFor,
  isActiveChatProfile,
  isSearchRateLimited,
  listTraineeAssignmentsHandler,
  updateTeacherActivityAssignmentHandler,
  validActivityAssessment,
  permanentDeleteAssignmentHandler,
  permanentDeleteClassroomHandler,
  normalizeSearchText,
  sanitizeDirectoryDocuments,
  sanitizedResult,
  validateSearchQuery,
} = require('../index')._test;

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
      verifyToken: async () => ({uid: 'teacher', email_verified: true}),
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
      verifyToken: async () => ({uid: 'teacher', email_verified: true}),
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
      verifyToken: async () => ({uid: 'teacher', email_verified: true}),
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
