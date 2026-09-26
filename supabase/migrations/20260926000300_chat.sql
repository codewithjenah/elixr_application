-- Direct messages. Reads are participant-scoped under RLS (and delivered by
-- Realtime); sends and state changes are transactional RPCs.

create table public.chat_conversations (
  id text primary key,
  participant_a text not null,
  participant_b text not null,
  participant_ids text[] not null,
  participant_snapshots jsonb not null,
  last_message_id text,
  last_message_body text,
  last_message_sender_id text,
  last_message_at timestamptz,
  unread_counts jsonb not null default '{}'::jsonb,
  read_at jsonb not null default '{}'::jsonb,
  cleared_at jsonb not null default '{}'::jsonb,
  status text not null default 'active' check (status in ('active', 'archived')),
  schema_version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz,
  check (participant_a < participant_b),
  check (participant_ids = array[participant_a, participant_b])
);
create index chat_conversations_a_idx on public.chat_conversations (participant_a, updated_at desc);
create index chat_conversations_b_idx on public.chat_conversations (participant_b, updated_at desc);

create table public.chat_messages (
  conversation_id text not null references public.chat_conversations (id) on delete cascade,
  id text not null,
  sender_id text not null,
  body text check (body is null or (char_length(body) between 1 and 2000 and body ~ '\S')),
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  deleted_at timestamptz,
  idempotency_key text check (idempotency_key is null or char_length(idempotency_key) between 1 and 256),
  legacy_coaching boolean,
  primary key (conversation_id, id),
  check ((deleted_at is null) = (body is not null))
);
create index chat_messages_recent_idx on public.chat_messages (conversation_id, created_at desc, id desc);

create table public.chat_blocks (
  blocker_id uuid not null references auth.users (id) on delete cascade,
  blocked_id uuid not null references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index chat_blocks_blocked_idx on public.chat_blocks (blocked_id);

create table public.chat_search_rate_limits (
  user_id uuid primary key references auth.users (id) on delete cascade,
  last_request_at timestamptz not null default now()
);

alter table public.chat_conversations enable row level security;
alter table public.chat_messages enable row level security;
alter table public.chat_blocks enable row level security;
alter table public.chat_search_rate_limits enable row level security;

create policy chat_conversations_select on public.chat_conversations
  for select to authenticated
  using (auth.uid()::text in (participant_a, participant_b));

create policy chat_messages_select on public.chat_messages
  for select to authenticated
  using (exists (
    select 1 from public.chat_conversations c
    where c.id = chat_messages.conversation_id
      and auth.uid()::text in (c.participant_a, c.participant_b)
  ));

create or replace function private.is_supported_chat_account(p_uid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.profiles p
    where p.id = p_uid and p.role in ('Teacher', 'Trainee') and p.lifecycle_state = 'active'
      and char_length(btrim(p.full_name)) > 0
  )
$$;

create policy chat_blocks_select on public.chat_blocks
  for select to authenticated using (blocker_id = auth.uid() or blocked_id = auth.uid());
create policy chat_blocks_insert on public.chat_blocks
  for insert to authenticated
  with check (blocker_id = auth.uid() and private.is_supported_chat_account(blocked_id));
create policy chat_blocks_delete on public.chat_blocks
  for delete to authenticated using (blocker_id = auth.uid());

create or replace function private.chat_snapshot(p_uid uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'id', p.id::text, 'display_name', p.full_name, 'role', p.role,
    'avatar_url', p.profile_picture_url
  ))
  from public.profiles p where p.id = p_uid
$$;

-- FNV-1a (32-bit) identical to the Dart client so idempotent result messages
-- keep their established deterministic IDs.
create or replace function private.chat_idempotent_message_id(p_key text) returns text
language plpgsql immutable as $$
declare
  v_hash bigint := 2166136261;
  v_bytes bytea := convert_to(p_key, 'UTF8');
begin
  for i in 0..length(v_bytes) - 1 loop
    v_hash := ((v_hash # get_byte(v_bytes, i)) * 16777619) & 4294967295;
  end loop;
  return 'assignment_result_' || lpad(to_hex(v_hash), 8, '0');
end;
$$;

create or replace function public.send_chat_message(
  p_recipient_id uuid, p_body text, p_idempotency_key text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_body text := btrim(coalesce(p_body, ''));
  v_key text := nullif(btrim(coalesce(p_idempotency_key, '')), '');
  v_a text;
  v_b text;
  v_id text;
  v_conversation public.chat_conversations;
  v_message_id text;
  v_existing public.chat_messages;
  v_message public.chat_messages;
begin
  if p_recipient_id is null or p_recipient_id = v_uid
     or char_length(v_body) not between 1 and 2000
     or (p_idempotency_key is not null and (v_key is null or char_length(v_key) > 256)) then
    perform private.fail('invalid_payload');
  end if;
  if not private.is_supported_chat_account(v_uid) or not private.is_supported_chat_account(p_recipient_id) then
    perform private.fail('recipient_unavailable');
  end if;
  if exists (
    select 1 from public.chat_blocks b
    where (b.blocker_id = v_uid and b.blocked_id = p_recipient_id)
       or (b.blocker_id = p_recipient_id and b.blocked_id = v_uid)
  ) then
    perform private.fail('blocked');
  end if;
  v_a := least(v_uid::text, p_recipient_id::text);
  v_b := greatest(v_uid::text, p_recipient_id::text);
  v_id := v_a || '__' || v_b;
  insert into public.chat_conversations (
    id, participant_a, participant_b, participant_ids, participant_snapshots,
    unread_counts, read_at
  ) values (
    v_id, v_a, v_b, array[v_a, v_b],
    jsonb_build_object(v_uid::text, private.chat_snapshot(v_uid),
      p_recipient_id::text, private.chat_snapshot(p_recipient_id)),
    jsonb_build_object(v_uid::text, 0, p_recipient_id::text, 0),
    jsonb_build_object(v_uid::text, now(), p_recipient_id::text, null)
  ) on conflict (id) do nothing;
  select * into v_conversation from public.chat_conversations where id = v_id for update;
  if v_conversation.status <> 'active' then
    perform private.fail('conversation_unavailable');
  end if;
  v_message_id := case when v_key is null then private.new_doc_id()
    else private.chat_idempotent_message_id(v_key) end;
  select * into v_existing from public.chat_messages
    where conversation_id = v_id and id = v_message_id;
  if found then
    if v_key is null or v_existing.idempotency_key is distinct from v_key
       or v_existing.sender_id <> v_uid::text or v_existing.body is distinct from v_body then
      perform private.fail('idempotency_conflict');
    end if;
    return jsonb_build_object('conversation_id', v_id, 'message_id', v_message_id,
      'created_at', v_existing.created_at);
  end if;
  insert into public.chat_messages (conversation_id, id, sender_id, body, idempotency_key)
  values (v_id, v_message_id, v_uid::text, v_body, v_key)
  returning * into v_message;
  update public.chat_conversations set
    last_message_id = v_message_id, last_message_body = v_body,
    last_message_sender_id = v_uid::text, last_message_at = now(),
    unread_counts = unread_counts || jsonb_build_object(
      v_uid::text, 0,
      p_recipient_id::text, coalesce((unread_counts ->> p_recipient_id::text)::int, 0) + 1),
    read_at = case when read_at ? v_uid::text then read_at
      else read_at || jsonb_build_object(v_uid::text, now()) end,
    updated_at = now()
  where id = v_id;
  return jsonb_build_object('conversation_id', v_id, 'message_id', v_message_id,
    'created_at', v_message.created_at);
end;
$$;

create or replace function private.require_chat_participant(p_conversation_id text)
returns public.chat_conversations language plpgsql security definer set search_path = '' as $$
declare
  v_row public.chat_conversations;
begin
  select * into v_row from public.chat_conversations where id = p_conversation_id for update;
  if not found then
    perform private.fail('not_found');
  end if;
  if not (auth.uid()::text in (v_row.participant_a, v_row.participant_b)) then
    perform private.fail('forbidden');
  end if;
  return v_row;
end;
$$;

create or replace function public.edit_chat_message(
  p_conversation_id text, p_message_id text, p_body text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_conversation public.chat_conversations := private.require_chat_participant(p_conversation_id);
  v_body text := btrim(coalesce(p_body, ''));
  v_message public.chat_messages;
begin
  if char_length(v_body) not between 1 and 2000 then
    perform private.fail('invalid_message');
  end if;
  select * into v_message from public.chat_messages
    where conversation_id = p_conversation_id and id = p_message_id for update;
  if not found then perform private.fail('not_found'); end if;
  if v_message.sender_id <> v_uid::text or v_message.deleted_at is not null then
    perform private.fail('forbidden');
  end if;
  update public.chat_messages set body = v_body, edited_at = now()
  where conversation_id = p_conversation_id and id = p_message_id;
  if v_conversation.last_message_id = p_message_id then
    update public.chat_conversations set last_message_body = v_body where id = p_conversation_id;
  end if;
end;
$$;

create or replace function public.delete_chat_message(
  p_conversation_id text, p_message_id text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_conversation public.chat_conversations := private.require_chat_participant(p_conversation_id);
  v_message public.chat_messages;
begin
  select * into v_message from public.chat_messages
    where conversation_id = p_conversation_id and id = p_message_id for update;
  if not found then perform private.fail('not_found'); end if;
  if v_message.sender_id <> v_uid::text or v_message.deleted_at is not null then
    perform private.fail('forbidden');
  end if;
  update public.chat_messages set body = null, deleted_at = now(), edited_at = null
  where conversation_id = p_conversation_id and id = p_message_id;
  if v_conversation.last_message_id = p_message_id then
    update public.chat_conversations set last_message_body = 'Message deleted'
    where id = p_conversation_id;
  end if;
end;
$$;

-- p_action: read | unread | clear
create or replace function public.update_chat_read_state(
  p_conversation_id text, p_action text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid text := private.require_uid()::text;
begin
  perform private.require_chat_participant(p_conversation_id);
  if p_action = 'read' then
    update public.chat_conversations set
      unread_counts = unread_counts || jsonb_build_object(v_uid, 0),
      read_at = read_at || jsonb_build_object(v_uid, now())
    where id = p_conversation_id;
  elsif p_action = 'unread' then
    update public.chat_conversations set
      unread_counts = unread_counts || jsonb_build_object(v_uid, 1)
    where id = p_conversation_id;
  elsif p_action = 'clear' then
    update public.chat_conversations set
      unread_counts = unread_counts || jsonb_build_object(v_uid, 0),
      read_at = read_at || jsonb_build_object(v_uid, now()),
      cleared_at = cleared_at || jsonb_build_object(v_uid, now())
    where id = p_conversation_id;
  else
    perform private.fail('invalid_payload');
  end if;
end;
$$;

-- Directory search by name prefix or exact email (email never returned).
create or replace function public.search_chat_users(p_query text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_raw text := btrim(coalesce(p_query, ''));
  v_norm text := lower(regexp_replace(btrim(coalesce(p_query, '')), '\s+', ' ', 'g'));
  v_last timestamptz;
begin
  if char_length(v_raw) not between 2 and 80 or char_length(v_norm) < 2 then
    perform private.fail('invalid_query');
  end if;
  select last_request_at into v_last from public.chat_search_rate_limits
    where user_id = v_uid for update;
  if found and v_last > now() - interval '500 milliseconds' then
    perform private.fail('rate_limited');
  end if;
  insert into public.chat_search_rate_limits (user_id, last_request_at) values (v_uid, now())
  on conflict (user_id) do update set last_request_at = now();
  return jsonb_build_object('results', coalesce((
    select jsonb_agg(private.chat_snapshot(p.id))
    from (
      select p.id from public.profiles p
      where p.id <> v_uid and private.is_supported_chat_account(p.id)
        and (
          (v_raw ~ '^[^\s@]+@[^\s@]+\.[^\s@]+$' and lower(p.email) = v_norm)
          or (v_raw !~ '@' and (
            lower(p.full_name) like replace(replace(v_norm, '%', ''), '_', '\_') || '%'
            or exists (
              select 1 from unnest(string_to_array(lower(p.full_name), ' ')) w
              where w like replace(replace(v_norm, '%', ''), '_', '\_') || '%'
            )
          ))
        )
      order by p.full_name limit 20
    ) p
  ), '[]'::jsonb));
end;
$$;

create or replace function public.list_faculty_directory() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_verified_teacher() then
    perform private.fail('forbidden');
  end if;
  return coalesce((
    select jsonb_agg(private.chat_snapshot(p.id) order by p.full_name)
    from public.profiles p
    where p.role = 'Teacher' and p.lifecycle_state = 'active'
  ), '[]'::jsonb);
end;
$$;

-- Account erasure: conversations with other active users are retained
-- under an anonymized 'deleted_user' identity; others are deleted.
create or replace function private.archive_chat_for_account_erasure(p_uid uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_conversation public.chat_conversations;
  v_other text;
  v_archive_id text;
  v_ids text[];
begin
  for v_conversation in
    select * from public.chat_conversations
    where p_uid::text in (participant_a, participant_b) for update
  loop
    v_other := case when v_conversation.participant_a = p_uid::text
      then v_conversation.participant_b else v_conversation.participant_a end;
    if v_other = 'deleted_user' or not private.is_supported_chat_account(v_other::uuid) then
      delete from public.chat_conversations where id = v_conversation.id;
      continue;
    end if;
    v_ids := array[least(v_other, 'deleted_user'), greatest(v_other, 'deleted_user')];
    v_archive_id := 'archived_' || left(encode(extensions.digest(
      v_conversation.id || '|' || v_other, 'sha256'), 'hex'), 40);
    insert into public.chat_conversations (
      id, participant_a, participant_b, participant_ids, participant_snapshots,
      last_message_id, last_message_body, last_message_sender_id, last_message_at,
      unread_counts, read_at, cleared_at, status, schema_version, created_at,
      updated_at, archived_at
    ) values (
      v_archive_id, v_ids[1], v_ids[2], v_ids,
      jsonb_build_object(
        'deleted_user', jsonb_build_object('id', 'deleted_user', 'display_name', 'Deleted user',
          'role', coalesce(v_conversation.participant_snapshots #>> array[p_uid::text, 'role'], 'Trainee')),
        v_other, coalesce(v_conversation.participant_snapshots -> v_other, private.chat_snapshot(v_other::uuid))),
      v_conversation.last_message_id, v_conversation.last_message_body,
      case when v_conversation.last_message_sender_id = p_uid::text then 'deleted_user'
        else v_conversation.last_message_sender_id end,
      v_conversation.last_message_at,
      jsonb_build_object(v_other, coalesce((v_conversation.unread_counts ->> v_other)::int, 0)),
      jsonb_build_object(v_other, v_conversation.read_at -> v_other),
      '{}'::jsonb, 'archived', 1, v_conversation.created_at, now(), now()
    ) on conflict (id) do nothing;
    insert into public.chat_messages (
      conversation_id, id, sender_id, body, created_at, edited_at, deleted_at,
      idempotency_key, legacy_coaching
    )
    select v_archive_id, m.id,
      case when m.sender_id = p_uid::text then 'deleted_user' else m.sender_id end,
      m.body, m.created_at, m.edited_at, m.deleted_at, m.idempotency_key, m.legacy_coaching
    from public.chat_messages m where m.conversation_id = v_conversation.id
    on conflict do nothing;
    delete from public.chat_conversations where id = v_conversation.id;
  end loop;
end;
$$;
