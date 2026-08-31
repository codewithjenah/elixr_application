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
  normalizeSearchText,
  sanitizeDirectoryDocuments,
  sanitizedResult,
  validateSearchQuery,
} = require('../index')._test;
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

function fakeAssignmentDatabase({memberships, assignments, recipients = []}) {
  const assignmentQueries = [];
  const docs = (values) => values.map((value) => ({
    id: value.id,
    data: () => value.data,
    ref: {
      collection(name) {
        assert.equal(name, 'assignment_recipients');
        return {
          doc(traineeId) {
            const recipient = recipients.find((item) =>
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

function fakeCreationDatabase({recipientIds}) {
  const writes = [];
  const values = new Map([
    ['users/teacher', {
      full_name: 'Grace Hopper', role: 'Teacher', lifecycle_state: 'active',
    }],
    ['groups/g1', {teacher_id: 'teacher', name: 'BSHM 4A', status: 'active'}],
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
