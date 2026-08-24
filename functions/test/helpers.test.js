const assert = require('node:assert/strict');
const test = require('node:test');

const {
  archivedConversationId,
  authenticatedUid,
  buildArchivedConversationData,
  buildSearchPrefixes,
  conversationIdFor,
  isActiveChatProfile,
  isSearchRateLimited,
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
