const {createHash} = require('node:crypto');

function legacyMessageId(noteId) {
  return `legacy_${createHash('sha256').update(noteId).digest('hex').slice(0, 32)}`;
}

function timestampMillis(value) {
  if (value && typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return 0;
}

function shouldReplaceConversationSummary(existing, latestCreatedAt) {
  if (!existing || !existing.exists) return true;
  return timestampMillis(existing.lastMessageAt) <= timestampMillis(latestCreatedAt);
}

function legacyMessageData(note, migratedAt) {
  return {
    sender_id: note.teacher_id,
    body: note.body,
    created_at: note.created_at,
    edited_at: timestampMillis(note.updated_at) > timestampMillis(note.created_at)
      ? note.updated_at
      : null,
    deleted_at: null,
    legacy_coaching: {
      source_note_id: note.id,
      ...(note.movement_name ? {movement_name: note.movement_name} : {}),
      migrated_at: migratedAt,
    },
  };
}

async function executeMigrationWrites({write, actions}) {
  if (!write) return 0;
  for (const action of actions) await action();
  return actions.length;
}

module.exports = {
  executeMigrationWrites,
  legacyMessageData,
  legacyMessageId,
  shouldReplaceConversationSummary,
  timestampMillis,
};
