-- Classroom RPCs: roster links, classrooms, memberships, announcements and
-- movement authoring. Every function derives the actor from auth.uid().

create or replace function private.caller_full_name() returns text
language sql stable security definer set search_path = '' as $$
  select p.full_name from public.profiles p where p.id = auth.uid()
$$;

-- Allocates a code unused by both roster and classroom invites. The caller
-- holds a transaction-scoped advisory lock so concurrent allocations cannot
-- race between the two tables.
create or replace function private.allocate_invite_code() returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  v_code text;
begin
  perform pg_advisory_xact_lock(hashtext('elixr_invite_codes'));
  for i in 1..8 loop
    v_code := private.generate_coach_code();
    if not exists (select 1 from public.teacher_invites where code = v_code)
       and not exists (select 1 from public.group_invites where code = v_code) then
      return v_code;
    end if;
  end loop;
  perform private.fail('collision_exhausted');
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Legacy Teacher rosters (teacher_student_links)
-- ---------------------------------------------------------------------------

create or replace function public.rotate_roster_invite() returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_previous text;
  v_code text;
  v_invite public.teacher_invites;
begin
  select teacher_roster_invite_code into v_previous from public.profiles where id = v_uid for update;
  v_code := private.allocate_invite_code();
  if v_previous is not null then
    delete from public.teacher_invites where code = v_previous and teacher_id = v_uid;
  end if;
  insert into public.teacher_invites (code, teacher_id, teacher_display_name)
  values (v_code, v_uid, private.caller_full_name())
  returning * into v_invite;
  update public.profiles set teacher_roster_invite_code = v_code where id = v_uid;
  return to_jsonb(v_invite);
end;
$$;

create or replace function public.get_active_roster_invite() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_invite public.teacher_invites;
begin
  select i.* into v_invite from public.teacher_invites i
  join public.profiles p on p.teacher_roster_invite_code = i.code
  where p.id = v_uid and i.teacher_id = v_uid;
  if not found then
    return null;
  end if;
  return to_jsonb(v_invite);
end;
$$;

create or replace function public.revoke_roster_invite() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_code text;
begin
  select teacher_roster_invite_code into v_code from public.profiles where id = v_uid for update;
  if v_code is not null then
    delete from public.teacher_invites where code = v_code and teacher_id = v_uid;
  end if;
  update public.profiles set teacher_roster_invite_code = null where id = v_uid;
end;
$$;

create or replace function public.resolve_roster_code(p_code text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_invite public.teacher_invites;
begin
  perform private.require_uid();
  if not private.is_coach_code(p_code) then
    perform private.fail('malformed_code');
  end if;
  select * into v_invite from public.teacher_invites where code = p_code;
  if not found then
    perform private.fail('invite_not_found');
  end if;
  return to_jsonb(v_invite);
end;
$$;

create or replace function public.request_teacher_join(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_trainee();
  v_invite public.teacher_invites;
  v_existing public.teacher_student_links;
  v_link public.teacher_student_links;
  v_id text;
begin
  if not private.is_coach_code(p_code) then
    perform private.fail('malformed_code');
  end if;
  select * into v_invite from public.teacher_invites where code = p_code;
  if not found or not exists (
    select 1 from public.profiles p
    where p.id = v_invite.teacher_id and p.teacher_roster_invite_code = p_code
  ) then
    perform private.fail('invite_not_found');
  end if;
  if v_invite.teacher_id = v_uid then
    perform private.fail('invalid_participant');
  end if;
  v_id := v_invite.teacher_id || '_' || v_uid;
  select * into v_existing from public.teacher_student_links where id = v_id for update;
  if found then
    if v_existing.status = 'approved' then
      perform private.fail('already_linked');
    end if;
    if v_existing.status = 'pending' and v_existing.request_version = 2 then
      perform private.fail('already_pending');
    end if;
    update public.teacher_student_links set
      teacher_display_name = v_invite.teacher_display_name,
      trainee_display_name = private.caller_full_name(),
      status = 'pending', invite_id = p_code, request_version = 2,
      progress_access = 'none', progress_access_version = null,
      progress_access_granted_at = null, evidence_access = null,
      evidence_access_version = null, evidence_access_granted_at = null,
      updated_at = now()
    where id = v_id returning * into v_link;
  else
    insert into public.teacher_student_links (
      id, teacher_id, trainee_id, teacher_display_name, trainee_display_name,
      status, invite_id, request_version
    ) values (
      v_id, v_invite.teacher_id, v_uid, v_invite.teacher_display_name,
      private.caller_full_name(), 'pending', p_code, 2
    ) returning * into v_link;
  end if;
  return jsonb_strip_nulls(to_jsonb(v_link));
end;
$$;

-- p_action: approve | reject (Teacher), cancel | revoke (Trainee).
create or replace function public.transition_teacher_link(p_link_id text, p_action text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_link public.teacher_student_links;
  v_next text;
begin
  select * into v_link from public.teacher_student_links where id = p_link_id for update;
  if not found then
    perform private.fail('not_found');
  end if;
  if p_action in ('approve', 'reject') then
    if v_link.teacher_id <> v_uid or not private.is_verified_teacher()
       or v_link.status <> 'pending' or v_link.request_version is distinct from 2 then
      perform private.fail('not_found');
    end if;
    v_next := case p_action when 'approve' then 'approved' else 'rejected' end;
  elsif p_action = 'cancel' then
    if v_link.trainee_id <> v_uid or v_link.status <> 'pending'
       or v_link.request_version is distinct from 2 then
      perform private.fail('not_found');
    end if;
    v_next := 'cancelled';
  elsif p_action = 'revoke' then
    if v_link.trainee_id <> v_uid or v_link.status <> 'approved' then
      perform private.fail('not_found');
    end if;
    v_next := 'revoked';
  else
    perform private.fail('invalid_payload');
  end if;
  update public.teacher_student_links set
    status = v_next, updated_at = now(),
    progress_access = 'none', progress_access_version = null,
    progress_access_granted_at = null, evidence_access = null,
    evidence_access_version = null, evidence_access_granted_at = null
  where id = p_link_id;
end;
$$;

create or replace function public.set_link_access(
  p_link_id text, p_kind text, p_granted boolean
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_link public.teacher_student_links;
begin
  select * into v_link from public.teacher_student_links where id = p_link_id for update;
  if not found or v_link.trainee_id <> v_uid or v_link.status <> 'approved' then
    perform private.fail('not_found');
  end if;
  if p_kind = 'progress' then
    update public.teacher_student_links set
      progress_access = case when p_granted then 'granted' else 'none' end,
      progress_access_version = case when p_granted then 1 end,
      progress_access_granted_at = case when p_granted then now() end,
      evidence_access = case when p_granted then evidence_access end,
      evidence_access_version = case when p_granted then evidence_access_version end,
      evidence_access_granted_at = case when p_granted then evidence_access_granted_at end,
      updated_at = now()
    where id = p_link_id;
  elsif p_kind = 'evidence' then
    if v_link.progress_access <> 'granted' then
      perform private.fail('not_found');
    end if;
    update public.teacher_student_links set
      evidence_access = case when p_granted then 'granted' end,
      evidence_access_version = case when p_granted then 1 end,
      evidence_access_granted_at = case when p_granted then now() end,
      updated_at = now()
    where id = p_link_id;
  else
    perform private.fail('invalid_payload');
  end if;
end;
$$;

create or replace function public.revoke_all_evidence_access() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
begin
  update public.teacher_student_links set
    evidence_access = null, evidence_access_version = null,
    evidence_access_granted_at = null, updated_at = now()
  where trainee_id = v_uid and evidence_access is not null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Classrooms
-- ---------------------------------------------------------------------------

create or replace function private.normalize_optional(p_value text, p_max int)
returns text language plpgsql immutable as $$
declare
  v text := nullif(btrim(coalesce(p_value, '')), '');
begin
  if v is not null and char_length(v) > p_max then
    perform private.fail('detail_too_long');
  end if;
  return v;
end;
$$;

create or replace function private.rotate_group_invite_for(p_group public.groups)
returns public.group_invites language plpgsql security definer set search_path = '' as $$
declare
  v_code text := private.allocate_invite_code();
  v_invite public.group_invites;
begin
  if p_group.invite_code is not null then
    delete from public.group_invites where code = p_group.invite_code and group_id = p_group.id;
  end if;
  insert into public.group_invites (code, group_id, teacher_id, teacher_display_name)
  values (v_code, p_group.id, p_group.teacher_id, private.caller_full_name())
  returning * into v_invite;
  update public.groups set invite_code = v_code, updated_at = now() where id = p_group.id;
  return v_invite;
end;
$$;

create or replace function public.create_group(
  p_name text, p_section text default null, p_schedule text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_name text := btrim(coalesce(p_name, ''));
  v_group public.groups;
begin
  if v_name = '' or char_length(v_name) > 80 then
    perform private.fail('invalid_name');
  end if;
  insert into public.groups (id, teacher_id, name, section, schedule, status, schema_version)
  values (
    private.new_doc_id(), v_uid, v_name,
    private.normalize_optional(p_section, 80),
    private.normalize_optional(p_schedule, 120), 'active', 2
  ) returning * into v_group;
  perform private.rotate_group_invite_for(v_group);
  select * into v_group from public.groups where id = v_group.id;
  return jsonb_strip_nulls(to_jsonb(v_group));
end;
$$;

create or replace function private.require_owned_group(p_group_id text)
returns public.groups language plpgsql security definer set search_path = '' as $$
declare
  v_group public.groups;
begin
  perform private.require_verified_teacher();
  select * into v_group from public.groups where id = p_group_id for update;
  if not found or v_group.teacher_id <> auth.uid() then
    perform private.fail('not_found');
  end if;
  return v_group;
end;
$$;

create or replace function public.update_group_details(
  p_group_id text, p_name text, p_section text, p_schedule text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_group public.groups := private.require_owned_group(p_group_id);
  v_name text := btrim(coalesce(p_name, ''));
begin
  if v_name = '' or char_length(v_name) > 80 then
    perform private.fail('invalid_name');
  end if;
  update public.groups set
    name = v_name,
    section = private.normalize_optional(p_section, 80),
    schedule = private.normalize_optional(p_schedule, 120),
    schema_version = 2,
    updated_at = now()
  where id = v_group.id;
end;
$$;

create or replace function public.set_group_status(p_group_id text, p_status text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_group public.groups := private.require_owned_group(p_group_id);
begin
  if p_status not in ('active', 'archived') then
    perform private.fail('invalid_payload');
  end if;
  update public.groups set status = p_status, updated_at = now() where id = v_group.id;
end;
$$;

create or replace function public.rotate_group_invite(p_group_id text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_group public.groups := private.require_owned_group(p_group_id);
begin
  if v_group.status <> 'active' then
    perform private.fail('group_inactive');
  end if;
  return to_jsonb(private.rotate_group_invite_for(v_group));
end;
$$;

create or replace function public.get_active_group_invite(p_group_id text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_invite public.group_invites;
begin
  perform private.require_uid();
  select i.* into v_invite from public.group_invites i
  join public.groups g on g.invite_code = i.code and g.id = i.group_id
  where g.id = p_group_id and g.teacher_id = auth.uid();
  if not found then
    return null;
  end if;
  return to_jsonb(v_invite);
end;
$$;

create or replace function public.resolve_group_invite(p_code text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_invite public.group_invites;
begin
  perform private.require_uid();
  if not private.is_coach_code(p_code) then
    perform private.fail('malformed_code');
  end if;
  select * into v_invite from public.group_invites where code = p_code;
  if not found then
    perform private.fail('invite_not_found');
  end if;
  return to_jsonb(v_invite);
end;
$$;

create or replace function public.request_group_join(p_code text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_trainee();
  v_invite public.group_invites;
  v_group public.groups;
  v_existing public.group_memberships;
  v_row public.group_memberships;
  v_id text;
begin
  if not private.is_coach_code(p_code) then
    perform private.fail('malformed_code');
  end if;
  select * into v_invite from public.group_invites where code = p_code;
  if not found then
    perform private.fail('invite_not_found');
  end if;
  select * into v_group from public.groups where id = v_invite.group_id;
  if not found then
    perform private.fail('group_not_found');
  end if;
  if v_group.status <> 'active' or v_group.invite_code is distinct from p_code
     or v_group.teacher_id <> v_invite.teacher_id then
    perform private.fail('group_inactive');
  end if;
  if v_invite.teacher_id = v_uid then
    perform private.fail('invalid_participant');
  end if;
  v_id := v_group.id || '_' || v_uid;
  select * into v_existing from public.group_memberships where id = v_id for update;
  if found then
    if v_existing.status = 'approved' then
      perform private.fail('already_member');
    end if;
    if v_existing.status = 'pending' then
      perform private.fail('already_pending');
    end if;
    update public.group_memberships set
      teacher_display_name = v_invite.teacher_display_name,
      trainee_display_name = private.caller_full_name(),
      status = 'pending', invite_id = p_code, request_version = 1, updated_at = now()
    where id = v_id returning * into v_row;
  else
    insert into public.group_memberships (
      id, group_id, teacher_id, trainee_id, teacher_display_name,
      trainee_display_name, status, invite_id, request_version
    ) values (
      v_id, v_group.id, v_group.teacher_id, v_uid, v_invite.teacher_display_name,
      private.caller_full_name(), 'pending', p_code, 1
    ) returning * into v_row;
  end if;
  return jsonb_strip_nulls(to_jsonb(v_row));
end;
$$;

-- p_action: approve | reject | remove (Teacher), cancel | leave (Trainee).
create or replace function public.transition_group_membership(
  p_membership_id text, p_action text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_row public.group_memberships;
  v_next text;
begin
  select * into v_row from public.group_memberships where id = p_membership_id for update;
  if not found then
    perform private.fail('not_found');
  end if;
  if p_action in ('approve', 'reject', 'remove') then
    if v_row.teacher_id <> v_uid or not private.is_verified_teacher()
       or not exists (select 1 from public.groups g where g.id = v_row.group_id and g.teacher_id = v_uid) then
      perform private.fail('not_found');
    end if;
    if p_action = 'remove' then
      if v_row.status <> 'approved' then perform private.fail('not_found'); end if;
      v_next := 'removed';
    else
      if v_row.status <> 'pending' then perform private.fail('not_found'); end if;
      v_next := case p_action when 'approve' then 'approved' else 'rejected' end;
    end if;
  elsif p_action = 'cancel' then
    if v_row.trainee_id <> v_uid or v_row.status <> 'pending' then
      perform private.fail('not_found');
    end if;
    v_next := 'cancelled';
  elsif p_action = 'leave' then
    if v_row.trainee_id <> v_uid or v_row.status <> 'approved' then
      perform private.fail('not_found');
    end if;
    v_next := 'removed';
  else
    perform private.fail('invalid_payload');
  end if;
  update public.group_memberships set status = v_next, updated_at = now()
  where id = p_membership_id;
end;
$$;

-- RLS turns a withdrawn grant into empty results; progress screens need to
-- distinguish "no sessions" from "access withdrawn".
create or replace function public.has_progress_access(p_trainee_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() = p_trainee_id or private.teacher_has_progress_access(p_trainee_id)
$$;

-- Classroom authorization is derived from live memberships; this only
-- validates the relationship the caller is about to rely on.
create or replace function public.prepare_classroom_access_context(
  p_trainee_id uuid, p_group_id text
) returns void language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
begin
  if not private.is_approved_member(p_group_id, p_trainee_id, v_uid) then
    perform private.fail('not_found');
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Announcements
-- ---------------------------------------------------------------------------

create or replace function public.create_announcement(
  p_group_id text, p_title text, p_body text, p_publish_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_group public.groups := private.require_owned_group(p_group_id);
  v_row public.group_announcements;
begin
  if v_group.status <> 'active' then
    perform private.fail('group_inactive');
  end if;
  if p_publish_at is not null and p_publish_at <= now() then
    perform private.fail('invalid_publication');
  end if;
  insert into public.group_announcements (
    id, group_id, teacher_id, title, body, publish_at, trainee_visible
  ) values (
    private.new_doc_id(), v_group.id, v_group.teacher_id, btrim(p_title),
    btrim(p_body), p_publish_at, p_publish_at is null
  ) returning * into v_row;
  return jsonb_strip_nulls(to_jsonb(v_row));
end;
$$;

create or replace function public.update_announcement(
  p_announcement_id text, p_title text, p_body text, p_publish_at timestamptz default null
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_row public.group_announcements;
  v_group public.groups;
begin
  select * into v_row from public.group_announcements where id = p_announcement_id for update;
  if not found then
    perform private.fail('not_found');
  end if;
  v_group := private.require_owned_group(v_row.group_id);
  if v_group.status <> 'active' then
    perform private.fail('group_inactive');
  end if;
  if p_publish_at is not null and p_publish_at is distinct from v_row.publish_at
     and p_publish_at <= now() then
    perform private.fail('invalid_publication');
  end if;
  update public.group_announcements set
    title = btrim(p_title), body = btrim(p_body), edited_at = now(),
    publish_at = p_publish_at,
    trainee_visible = p_publish_at is null or p_publish_at <= now()
  where id = p_announcement_id;
end;
$$;

create or replace function public.delete_announcement(p_announcement_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_row public.group_announcements;
begin
  select * into v_row from public.group_announcements where id = p_announcement_id for update;
  if not found then
    return;
  end if;
  perform private.require_owned_group(v_row.group_id);
  delete from public.group_announcements where id = p_announcement_id;
  update public.groups set pinned_announcement_id = null, pinned_announcement_at = null, updated_at = now()
  where id = v_row.group_id and pinned_announcement_id = p_announcement_id;
end;
$$;

create or replace function public.set_pinned_announcement(
  p_group_id text, p_announcement_id text default null
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_group public.groups := private.require_owned_group(p_group_id);
  v_target public.group_announcements;
begin
  if nullif(btrim(coalesce(p_announcement_id, '')), '') is null then
    update public.groups set pinned_announcement_id = null, pinned_announcement_at = null,
      updated_at = now() where id = v_group.id;
    return;
  end if;
  if v_group.status <> 'active' then
    perform private.fail('group_inactive');
  end if;
  select * into v_target from public.group_announcements
  where id = p_announcement_id and group_id = v_group.id;
  if not found then
    perform private.fail('not_found');
  end if;
  if v_target.publish_at is not null and v_target.publish_at > now() then
    perform private.fail('scheduled_announcement');
  end if;
  update public.groups set pinned_announcement_id = p_announcement_id,
    pinned_announcement_at = now(), updated_at = now() where id = v_group.id;
end;
$$;

-- Flips due scheduled announcements so trainee realtime subscribers receive
-- an update. Authorization never depends on this marker (the read policy
-- also checks publish_at <= now()).
create or replace function private.publish_due_announcements() returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_count int;
begin
  update public.group_announcements set trainee_visible = true
  where trainee_visible = false and publish_at <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Teacher movements (teacher-reviewed specs with immutable revisions)
-- ---------------------------------------------------------------------------

create or replace function private.valid_attempt_policy(p_policy jsonb)
returns boolean language sql immutable as $$
  select p_policy is not null and jsonb_typeof(p_policy) = 'object' and (
    (p_policy ->> 'type' = 'unlimited'
      and (select count(*) from jsonb_object_keys(p_policy)) = 1)
    or (p_policy ->> 'type' = 'finite'
      and (select array_agg(k order by k) from jsonb_object_keys(p_policy) k)
        = array['maximum_attempts', 'type']
      and private.is_int_in(p_policy -> 'maximum_attempts', 1, 3))
  )
$$;

create or replace function private.valid_activity_assessment(p_value jsonb, p_max int)
returns boolean language plpgsql immutable as $$
declare
  v_version int;
  v_keys text[];
  v_readiness jsonb;
  v_rubric jsonb;
  v_criteria jsonb;
  v_criterion jsonb;
  v_total int := 0;
  v_ids text[] := '{}';
  v_demo jsonb;
begin
  if p_value is null or jsonb_typeof(p_value) <> 'object' or p_max is null then
    return false;
  end if;
  if not private.is_int_in(p_value -> 'schema_version', 2, 3) then
    return false;
  end if;
  v_version := (p_value ->> 'schema_version')::int;
  select array_agg(k) into v_keys from jsonb_object_keys(p_value) k;
  if v_version = 3 and not (v_keys <@ array['schema_version', 'readiness', 'rubric',
       'recording_duration_seconds', 'demonstration_video']) then
    return false;
  end if;
  if v_version = 2 and not (v_keys <@ array['schema_version', 'readiness', 'rubric',
       'attempt_policy', 'recording_duration_seconds', 'demonstration_video']) then
    return false;
  end if;
  if not ((p_value ->> 'recording_duration_seconds') in ('15', '30', '45', '60')) then
    return false;
  end if;
  v_readiness := p_value -> 'readiness';
  if jsonb_typeof(v_readiness) <> 'object'
     or not (v_readiness ->> 'hands' in ('none', 'one_hand', 'two_hands'))
     or not (v_readiness ->> 'body' in ('none', 'upper_body')) then
    return false;
  end if;
  if v_version = 3 and (select count(*) from jsonb_object_keys(v_readiness)) <> 2 then
    return false;
  end if;
  if v_version = 2 and (
    (select count(*) from jsonb_object_keys(v_readiness)) <> 3
    or not (v_readiness ->> 'prop' in ('none', 'one_bottle', 'one_shaker', 'bottle_and_shaker', 'two_bottles'))
    or not private.valid_attempt_policy(p_value -> 'attempt_policy')
  ) then
    return false;
  end if;
  v_rubric := p_value -> 'rubric';
  if jsonb_typeof(v_rubric) <> 'object'
     or not (v_rubric ->> 'template_id' in ('standard_technique', 'beginner_fundamentals',
       'control_consistency', 'performance_flow', 'custom'))
     or not private.is_int_in(v_rubric -> 'maximum_score', p_max, p_max) then
    return false;
  end if;
  v_criteria := v_rubric -> 'criteria';
  if jsonb_typeof(v_criteria) <> 'array'
     or jsonb_array_length(v_criteria) not between 3 and 5 then
    return false;
  end if;
  for v_criterion in select value from jsonb_array_elements(v_criteria) loop
    if jsonb_typeof(v_criterion) <> 'object'
       or not private.valid_doc_id(v_criterion ->> 'id')
       or (v_criterion ->> 'id') = any (v_ids)
       or not private.bounded_text(v_criterion ->> 'label', 80)
       or not private.bounded_text(v_criterion ->> 'description', 500)
       or not private.is_int_in(v_criterion -> 'maximum_points', 1, p_max)
       or (v_criterion ? 'weight' and not private.is_int_in(v_criterion -> 'weight', 1, 100)) then
      return false;
    end if;
    v_ids := v_ids || (v_criterion ->> 'id');
    v_total := v_total + (v_criterion ->> 'maximum_points')::int;
  end loop;
  if v_total <> p_max then
    return false;
  end if;
  v_demo := p_value -> 'demonstration_video';
  if v_demo is not null and jsonb_typeof(v_demo) <> 'null' and (
    not private.bounded_text(v_demo ->> 'storage_path', 1024)
    or (v_demo ->> 'content_type') is distinct from 'video/mp4'
    or not private.is_int_in(v_demo -> 'size_bytes', 1, 52428800)
    or not private.is_int_in(v_demo -> 'duration_ms', 1, 60000)
    or not (v_demo ->> 'source' in ('uploaded', 'recorded'))
  ) then
    return false;
  end if;
  return true;
end;
$$;

create or replace function private.valid_teacher_reviewed_spec(p_spec jsonb)
returns boolean language plpgsql immutable as $$
declare
  v_keys text[];
begin
  if p_spec is null or jsonb_typeof(p_spec) <> 'object' then
    return false;
  end if;
  select array_agg(k) into v_keys from jsonb_object_keys(p_spec) k;
  return v_keys <@ array['instructions', 'required_prop', 'capability',
      'safety_guidance', 'activity_assessment']
    and private.bounded_text(p_spec ->> 'instructions', 2000)
    and p_spec ->> 'required_prop' in ('bottle', 'shaker', 'bottle_and_shaker')
    and p_spec ->> 'capability' = 'teacher_review_only'
    and (not p_spec ? 'safety_guidance' or private.bounded_text(p_spec ->> 'safety_guidance', 1000))
    and (not p_spec ? 'activity_assessment' or private.valid_activity_assessment(
      p_spec -> 'activity_assessment',
      (p_spec #>> '{activity_assessment,rubric,maximum_score}')::int
    ));
end;
$$;

create or replace function public.create_teacher_movement(
  p_title text, p_spec jsonb, p_schema_version int default 2
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_movement_id text := private.new_doc_id();
  v_revision_id text := private.new_doc_id();
  v_row public.teacher_movements;
begin
  if not private.bounded_text(p_title, 80) or not private.valid_teacher_reviewed_spec(p_spec)
     or p_schema_version not in (1, 2) then
    perform private.fail('malformed');
  end if;
  insert into public.teacher_movements (id, teacher_id, title, status, current_revision_id)
  values (v_movement_id, v_uid, btrim(p_title), 'active', v_revision_id)
  returning * into v_row;
  insert into public.teacher_movement_revisions (
    id, movement_id, teacher_id, schema_version, assessment_mode, spec
  ) values (v_revision_id, v_movement_id, v_uid, p_schema_version, 'teacher_reviewed', p_spec);
  return to_jsonb(v_row);
end;
$$;

create or replace function private.require_owned_teacher_movement(p_movement_id text)
returns public.teacher_movements language plpgsql security definer set search_path = '' as $$
declare
  v_row public.teacher_movements;
  v_mode text;
begin
  perform private.require_verified_teacher();
  select * into v_row from public.teacher_movements where id = p_movement_id for update;
  if not found then
    perform private.fail('not_found');
  end if;
  if v_row.teacher_id <> auth.uid() then
    perform private.fail('forbidden');
  end if;
  select assessment_mode into v_mode from public.teacher_movement_revisions
  where id = v_row.current_revision_id and movement_id = v_row.id;
  if v_mode is distinct from 'teacher_reviewed' then
    perform private.fail('identity_mismatch');
  end if;
  return v_row;
end;
$$;

create or replace function public.edit_teacher_movement(
  p_movement_id text, p_title text, p_spec jsonb, p_schema_version int default 2
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_row public.teacher_movements := private.require_owned_teacher_movement(p_movement_id);
  v_revision_id text := private.new_doc_id();
begin
  if v_row.status <> 'active' then
    perform private.fail('archived');
  end if;
  if not private.bounded_text(p_title, 80) or not private.valid_teacher_reviewed_spec(p_spec)
     or p_schema_version not in (1, 2) then
    perform private.fail('malformed');
  end if;
  insert into public.teacher_movement_revisions (
    id, movement_id, teacher_id, schema_version, assessment_mode, spec
  ) values (v_revision_id, v_row.id, v_row.teacher_id, p_schema_version, 'teacher_reviewed', p_spec);
  update public.teacher_movements set title = btrim(p_title), current_revision_id = v_revision_id,
    updated_at = now() where id = v_row.id returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.archive_teacher_movement(p_movement_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_row public.teacher_movements := private.require_owned_teacher_movement(p_movement_id);
begin
  if v_row.status = 'active' then
    update public.teacher_movements set status = 'archived', updated_at = now() where id = v_row.id;
  end if;
end;
$$;

create or replace function public.delete_teacher_movement(p_movement_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_row public.teacher_movements := private.require_owned_teacher_movement(p_movement_id);
begin
  if exists (
    select 1 from public.group_assignments a
    where a.teacher_id = v_row.teacher_id and a.movement_id = v_row.id
  ) then
    perform private.fail('movement_in_use');
  end if;
  delete from public.teacher_movements where id = v_row.id;
end;
$$;

-- ---------------------------------------------------------------------------
-- Custom (reference-matched) movements
-- ---------------------------------------------------------------------------

create or replace function private.valid_movement_template(p_value jsonb)
returns boolean language plpgsql immutable as $$
declare
  v_keys text[];
  v_version int;
  v_trace jsonb;
  v_total double precision;
begin
  if p_value is null or jsonb_typeof(p_value) <> 'object' then
    return false;
  end if;
  select array_agg(k) into v_keys from jsonb_object_keys(p_value) k;
  if not (v_keys <@ array['schema_version', 'capture_version', 'duration_ms',
      'reference_count', 'required_modalities', 'normalization_metadata',
      'feature_capabilities', 'canonical_sequence', 'variability_metadata',
      'prop_events', 'rotation_trace'])
     or not (v_keys @> array['schema_version', 'capture_version', 'duration_ms',
      'reference_count', 'required_modalities', 'normalization_metadata',
      'feature_capabilities', 'canonical_sequence', 'variability_metadata',
      'prop_events']) then
    return false;
  end if;
  if not private.is_int_in(p_value -> 'schema_version', 1, 2)
     or not private.is_int_in(p_value -> 'reference_count', 2, 10)
     or jsonb_typeof(p_value -> 'feature_capabilities') <> 'object'
     or jsonb_typeof(p_value -> 'canonical_sequence') <> 'array'
     or jsonb_array_length(p_value -> 'canonical_sequence') not between 2 and 600 then
    return false;
  end if;
  v_version := (p_value ->> 'schema_version')::int;
  if v_version = 1 then
    return not (p_value ? 'rotation_trace')
      and (p_value #> '{feature_capabilities,prop_rotation}') = 'false'::jsonb;
  end if;
  v_trace := p_value -> 'rotation_trace';
  if not (p_value ? 'rotation_trace')
     or (p_value #> '{feature_capabilities,prop_rotation}') <> 'true'::jsonb
     or jsonb_array_length(p_value -> 'canonical_sequence') <> 32
     or jsonb_typeof(v_trace) <> 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(v_trace) k)
       <> array['angles_rad', 'coverage', 'pair_coverage', 'total_signed_rad']
     or jsonb_typeof(v_trace -> 'angles_rad') <> 'array'
     or jsonb_array_length(v_trace -> 'angles_rad') <> 32
     or jsonb_typeof(v_trace -> 'total_signed_rad') <> 'number'
     or jsonb_typeof(v_trace -> 'coverage') <> 'number'
     or jsonb_typeof(v_trace -> 'pair_coverage') <> 'number' then
    return false;
  end if;
  v_total := (v_trace ->> 'total_signed_rad')::double precision;
  return (v_total >= 4.084 or v_total <= -4.084)
    and (v_trace ->> 'coverage')::double precision between 0.8 and 1
    and (v_trace ->> 'pair_coverage')::double precision between 0.7 and 1;
end;
$$;

create or replace function private.custom_reference_path(
  p_owner uuid, p_movement_id text, p_revision_id text
) returns text language sql immutable as $$
  select 'users/' || p_owner || '/custom_movement_references/'
    || p_movement_id || '_' || p_revision_id || '.jpg'
$$;

create or replace function private.require_custom_owner_role(p_role text) returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
begin
  if not ((p_role = 'teacher' and private.is_verified_teacher())
      or (p_role = 'trainee' and private.is_trainee(v_uid))) then
    perform private.fail('forbidden');
  end if;
  return v_uid;
end;
$$;

-- IDs are allocated by the client first so the optional reference JPEG can be
-- uploaded to its deterministic owner-private path before this commit.
create or replace function public.create_custom_movement(
  p_movement_id text, p_revision_id text, p_owner_role text, p_name text,
  p_description text, p_difficulty text, p_prop_type text, p_template jsonb,
  p_reference_image_storage_path text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_custom_owner_role(p_owner_role);
  v_row public.custom_movements;
begin
  if not private.valid_doc_id(p_movement_id) or not private.valid_doc_id(p_revision_id)
     or not private.valid_movement_template(p_template) then
    perform private.fail('malformed');
  end if;
  if p_reference_image_storage_path is not null
     and p_reference_image_storage_path
       <> private.custom_reference_path(v_uid, p_movement_id, p_revision_id) then
    perform private.fail('malformed');
  end if;
  insert into public.custom_movements (
    id, owner_uid, owner_role, name, description, difficulty, prop_type,
    status, active_revision_id, reference_image_storage_path
  ) values (
    p_movement_id, v_uid, p_owner_role, btrim(p_name), btrim(coalesce(p_description, '')),
    p_difficulty, p_prop_type, 'active', p_revision_id, p_reference_image_storage_path
  ) returning * into v_row;
  insert into public.custom_movement_revisions (id, movement_id, owner_uid, owner_role, template)
  values (p_revision_id, p_movement_id, v_uid, p_owner_role, p_template);
  return jsonb_strip_nulls(to_jsonb(v_row));
end;
$$;

create or replace function public.publish_custom_movement_revision(
  p_movement_id text, p_expected_active_revision_id text, p_revision_id text,
  p_name text, p_description text, p_difficulty text, p_prop_type text,
  p_template jsonb, p_reference_image_storage_path text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_row public.custom_movements;
begin
  select * into v_row from public.custom_movements where id = p_movement_id for update;
  if not found or v_row.owner_uid <> v_uid
     or v_row.active_revision_id <> p_expected_active_revision_id
     or v_row.status <> 'active' then
    perform private.fail('conflict');
  end if;
  perform private.require_custom_owner_role(v_row.owner_role);
  if not private.valid_doc_id(p_revision_id) or not private.valid_movement_template(p_template)
     or p_revision_id = v_row.active_revision_id then
    perform private.fail('malformed');
  end if;
  if p_reference_image_storage_path is not null
     and p_reference_image_storage_path
       <> private.custom_reference_path(v_uid, p_movement_id, p_revision_id) then
    perform private.fail('malformed');
  end if;
  insert into public.custom_movement_revisions (id, movement_id, owner_uid, owner_role, template)
  values (p_revision_id, p_movement_id, v_uid, v_row.owner_role, p_template);
  update public.custom_movements set
    name = btrim(p_name), description = btrim(coalesce(p_description, '')),
    difficulty = p_difficulty, prop_type = p_prop_type,
    active_revision_id = p_revision_id,
    reference_image_storage_path = coalesce(p_reference_image_storage_path, reference_image_storage_path),
    updated_at = now()
  where id = p_movement_id returning * into v_row;
  return jsonb_strip_nulls(to_jsonb(v_row));
end;
$$;

-- Revisions and results are immutable history; archiving is the only
-- deletion-like transition available to clients.
create or replace function public.archive_custom_movement(p_movement_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_row public.custom_movements;
begin
  select * into v_row from public.custom_movements where id = p_movement_id for update;
  if not found then
    return;
  end if;
  if v_row.owner_uid <> v_uid then
    perform private.fail('forbidden');
  end if;
  if v_row.status = 'active' then
    update public.custom_movements set status = 'archived', updated_at = now() where id = p_movement_id;
  end if;
end;
$$;

-- Personal custom-movement practice: the result and its session-history
-- mirror are written together. Never awards global XP.
create or replace function public.save_custom_movement_result(
  p_session_id text, p_movement_id text, p_revision_id text,
  p_total_score double precision, p_component_scores jsonb, p_feedback jsonb,
  p_duration_seconds int
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_movement public.custom_movements;
  v_revision public.custom_movement_revisions;
begin
  if p_total_score is null or p_total_score < 0 or p_total_score > 100
     or p_duration_seconds not between 0 and 86400 then
    perform private.fail('malformed');
  end if;
  select * into v_movement from public.custom_movements where id = p_movement_id;
  select * into v_revision from public.custom_movement_revisions
  where id = p_revision_id and movement_id = p_movement_id;
  if v_movement.id is null or v_revision.id is null or v_movement.owner_uid <> v_uid
     or v_revision.owner_uid <> v_uid then
    perform private.fail('forbidden');
  end if;
  perform private.insert_session(v_uid, p_session_id, jsonb_build_object(
    'movement_name', v_movement.name,
    'difficulty', v_movement.difficulty,
    'duration_seconds', p_duration_seconds,
    'prop_type', v_movement.prop_type,
    'assessment_version', 1,
    'score', round(p_total_score)::int,
    'custom_movement_id', p_movement_id,
    'custom_movement_revision_id', p_revision_id,
    'reference_image_storage_path', v_movement.reference_image_storage_path
  ), '[]'::jsonb);
  insert into public.custom_movement_results (
    id, owner_uid, movement_id, revision_id, result_type, total_score,
    component_scores, feedback
  ) values (
    p_session_id, v_uid, p_movement_id, p_revision_id, 'personal_practice',
    p_total_score, coalesce(p_component_scores, '{}'::jsonb),
    coalesce((select jsonb_agg(value) from (
      select value from jsonb_array_elements(coalesce(p_feedback, '[]'::jsonb)) limit 8
    ) f), '[]'::jsonb)
  );
end;
$$;
