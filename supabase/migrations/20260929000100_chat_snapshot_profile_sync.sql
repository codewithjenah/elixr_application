-- Keep chat participant snapshots in sync with the authoritative profile.
--
-- send_chat_message stores participant_snapshots only when a conversation is
-- first created, so later name or profile-picture changes never reached
-- existing conversations. Only the participant's own snapshot entry is
-- replaced (with the existing private.chat_snapshot shape); ordering,
-- message, unread, read and cleared state are never touched.

create or replace function private.sync_chat_participant_snapshot() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_uid text := new.id::text;
begin
  update public.chat_conversations c
  set participant_snapshots = c.participant_snapshots
    || jsonb_build_object(v_uid, private.chat_snapshot(new.id))
  where (c.participant_a = v_uid or c.participant_b = v_uid)
    and c.participant_snapshots ? v_uid
    and c.participant_snapshots -> v_uid is distinct from private.chat_snapshot(new.id);
  return null;
end;
$$;

create trigger profiles_sync_chat_snapshot
  after update of full_name, role, profile_picture_url on public.profiles
  for each row
  when (old.full_name is distinct from new.full_name
     or old.role is distinct from new.role
     or old.profile_picture_url is distinct from new.profile_picture_url)
  execute function private.sync_chat_participant_snapshot();

-- Refreshes every snapshot entry that belongs to an existing profile. Keys are
-- matched as text so archived identities such as 'deleted_user' (which are
-- not UUIDs and have no profile) are never cast and are left untouched.
create or replace function private.refresh_all_chat_participant_snapshots()
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.chat_conversations c
  set participant_snapshots = c.participant_snapshots || fresh.snapshots
  from (
    select c2.id, jsonb_object_agg(k.key, private.chat_snapshot(p.id)) as snapshots
    from public.chat_conversations c2
    cross join lateral jsonb_object_keys(c2.participant_snapshots) as k(key)
    join public.profiles p on p.id::text = k.key
    where c2.participant_snapshots -> k.key is distinct from private.chat_snapshot(p.id)
    group by c2.id
  ) fresh
  where c.id = fresh.id;
end;
$$;

revoke all on function private.sync_chat_participant_snapshot() from public;
revoke all on function private.refresh_all_chat_participant_snapshots() from public;

select private.refresh_all_chat_participant_snapshots();
