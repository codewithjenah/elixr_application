-- Assignment, attempt, Class Challenge and learning-material RPCs. These
-- replace the former Cloud Functions handlers and the client-side Firestore
-- transitions; each transition is a single database transaction.

create or replace function private.assignment_json(p_row public.group_assignments)
returns jsonb language sql stable as $$
  select jsonb_strip_nulls(to_jsonb(p_row))
$$;

create or replace function private.attempt_json(p_row public.assignment_attempts)
returns jsonb language sql stable as $$
  select jsonb_strip_nulls(to_jsonb(p_row))
$$;

create or replace function private.parse_timestamp(p_value text, p_error text)
returns timestamptz language plpgsql stable as $$
begin
  if p_value is null then
    return null;
  end if;
  return p_value::timestamptz;
exception when others then
  perform private.fail(p_error);
  return null;
end;
$$;

create or replace function private.effective_attempt_policy(p_row public.group_assignments)
returns jsonb language sql immutable as $$
  select case
    when private.valid_attempt_policy(p_row.attempt_policy) then p_row.attempt_policy
    when private.valid_attempt_policy(p_row.activity_assessment -> 'attempt_policy')
      then p_row.activity_assessment -> 'attempt_policy'
    else '{"type": "unlimited"}'::jsonb
  end
$$;

-- Validates that every recipient is an approved member of the classroom.
create or replace function private.require_recipients(
  p_group_id text, p_teacher_id uuid, p_audience text, p_recipient_ids text[]
) returns uuid[] language plpgsql stable security definer set search_path = '' as $$
declare
  v_ids uuid[] := '{}';
  v_raw text;
begin
  if p_audience not in ('entire_class', 'selected_students', 'individual_student')
     or (p_audience = 'entire_class' and cardinality(p_recipient_ids) <> 0)
     or (p_audience = 'selected_students' and cardinality(p_recipient_ids) < 1)
     or (p_audience = 'individual_student' and cardinality(p_recipient_ids) <> 1)
     or (select count(distinct r) from unnest(p_recipient_ids) r) <> cardinality(p_recipient_ids) then
    perform private.fail('invalid_audience');
  end if;
  foreach v_raw in array p_recipient_ids loop
    begin
      v_ids := v_ids || v_raw::uuid;
    exception when others then
      perform private.fail('invalid_recipient');
    end;
    if not private.is_approved_member(p_group_id, v_raw::uuid, p_teacher_id) then
      perform private.fail('invalid_recipient');
    end if;
  end loop;
  return v_ids;
end;
$$;

create or replace function private.replace_recipients(
  p_assignment public.group_assignments, p_ids uuid[]
) returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.assignment_recipients
  where assignment_id = p_assignment.id and not (trainee_id = any (p_ids));
  insert into public.assignment_recipients (
    assignment_id, trainee_id, group_id, teacher_id, audience_type
  )
  select p_assignment.id, r, p_assignment.group_id, p_assignment.teacher_id, p_assignment.audience_type
  from unnest(p_ids) r
  on conflict (assignment_id, trainee_id) do update set
    group_id = excluded.group_id, teacher_id = excluded.teacher_id,
    audience_type = excluded.audience_type, created_at = now();
end;
$$;

create or replace function private.recipient_ids(p_assignment_id text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(trainee_id::text order by trainee_id), '[]'::jsonb)
  from public.assignment_recipients where assignment_id = p_assignment_id
$$;

-- ---------------------------------------------------------------------------
-- Assignment creation (former createClassroomAssignment Function)
-- ---------------------------------------------------------------------------

create or replace function public.create_classroom_assignment(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_group public.groups;
  v_teacher_name text := private.caller_full_name();
  v_audience text := p ->> 'audience_type';
  v_recipient_text text[] := coalesce(
    array(select jsonb_array_elements_text(coalesce(p -> 'recipient_ids', '[]'::jsonb))), '{}');
  v_recipients uuid[];
  v_policy jsonb := coalesce(nullif(p -> 'attempt_policy', 'null'::jsonb), '{"type":"unlimited"}'::jsonb);
  v_due timestamptz := private.parse_timestamp(p ->> 'due_at', 'invalid_due_at');
  v_status text := coalesce(p ->> 'status', 'active');
  v_publish timestamptz := private.parse_timestamp(p ->> 'publish_at', 'invalid_publication');
  v_topic text;
  v_row public.group_assignments;
  v_movement public.teacher_movements;
  v_revision public.teacher_movement_revisions;
  v_spec jsonb;
  v_title text;
  v_instructions text;
  v_safety text;
  v_assessment jsonb;
  v_max int;
  v_official text := p ->> 'official_movement_name';
begin
  if not private.valid_attempt_policy(v_policy) then
    perform private.fail('invalid_audience');
  end if;
  if v_status not in ('draft', 'scheduled', 'active')
     or (v_status = 'scheduled' and (v_publish is null or v_publish <= now()))
     or (v_status <> 'scheduled' and v_publish is not null)
     or (v_due is not null and v_publish is not null and v_due <= v_publish) then
    perform private.fail('invalid_publication');
  end if;
  if p ? 'topic' and jsonb_typeof(p -> 'topic') <> 'null' then
    v_topic := nullif(btrim(p ->> 'topic'), '');
    if v_topic is null or char_length(v_topic) > 80 then
      perform private.fail('invalid_topic');
    end if;
  end if;
  select * into v_group from public.groups where id = p ->> 'group_id';
  if not found or v_group.teacher_id <> v_uid or v_group.status <> 'active' then
    perform private.fail('forbidden');
  end if;
  if not private.bounded_text(v_teacher_name, 80) or not private.bounded_text(v_group.name, 80) then
    perform private.fail('invalid_identity');
  end if;
  v_recipients := private.require_recipients(v_group.id, v_uid, v_audience, v_recipient_text);

  v_row.id := private.new_doc_id();
  v_row.teacher_id := v_uid;
  v_row.group_id := v_group.id;
  v_row.audience_type := v_audience;
  v_row.status := v_status;
  v_row.teacher_display_name := v_teacher_name;
  v_row.group_name := v_group.name;
  v_row.attempt_policy := v_policy;
  v_row.due_at := v_due;
  v_row.publish_at := v_publish;
  v_row.topic := v_topic;
  v_row.created_at := now();
  v_row.updated_at := now();

  if p ->> 'origin' = 'official_elixr' then
    if not private.is_official_movement(v_official) then
      perform private.fail('invalid_movement');
    end if;
    if not private.official_movement_supports_prop(v_official, p ->> 'allowed_prop') then
      perform private.fail('invalid_allowed_prop');
    end if;
    if p ? 'display_instructions' and jsonb_typeof(p -> 'display_instructions') <> 'null' then
      v_instructions := btrim(p ->> 'display_instructions');
      if v_instructions = '' then
        v_instructions := null;
      elsif char_length(v_instructions) > 2000 then
        perform private.fail('invalid_instructions');
      end if;
    end if;
    v_row.movement_id := private.official_movement_id(v_official);
    v_row.revision_id := private.official_movement_id(v_official) || '_v1';
    v_row.origin := 'official_elixr';
    v_row.assessment_mode := 'official_guided';
    v_row.official_movement_name := v_official;
    v_row.display_title := v_official;
    v_row.allowed_prop := p ->> 'allowed_prop';
    v_row.display_instructions := v_instructions;
  elsif p ->> 'origin' = 'teacher_created'
    and private.valid_doc_id(p ->> 'movement_id') and private.valid_doc_id(p ->> 'revision_id')
    and private.is_int_in(p -> 'max_score', 1, 100) then
    v_max := (p ->> 'max_score')::int;
    select * into v_movement from public.teacher_movements where id = p ->> 'movement_id';
    if not found then perform private.fail('movement_not_found'); end if;
    select * into v_revision from public.teacher_movement_revisions
      where id = p ->> 'revision_id' and movement_id = v_movement.id;
    if not found then perform private.fail('revision_not_found'); end if;
    if v_movement.teacher_id <> v_uid or v_revision.teacher_id <> v_uid then
      perform private.fail('invalid_movement_owner');
    end if;
    if v_movement.status <> 'active' then perform private.fail('movement_archived'); end if;
    if v_movement.current_revision_id <> v_revision.id then perform private.fail('stale_revision'); end if;
    if v_revision.assessment_mode <> 'teacher_reviewed' then perform private.fail('invalid_movement_spec'); end if;
    v_spec := v_revision.spec;
    v_title := btrim(coalesce(p ->> 'display_title', v_movement.title));
    v_instructions := btrim(coalesce(p ->> 'display_instructions', v_spec ->> 'instructions'));
    v_safety := case when p ? 'display_safety_guidance'
      then nullif(btrim(coalesce(p ->> 'display_safety_guidance', '')), '')
      else nullif(btrim(coalesce(v_spec ->> 'safety_guidance', '')), '') end;
    v_assessment := coalesce(nullif(p -> 'activity_assessment', 'null'::jsonb), v_spec -> 'activity_assessment');
    if v_spec ->> 'capability' is distinct from 'teacher_review_only'
       or not private.bounded_text(v_title, 80) or not private.bounded_text(v_instructions, 2000)
       or (v_safety is not null and char_length(v_safety) > 1000)
       or not (v_spec ->> 'required_prop' in ('bottle', 'shaker', 'bottle_and_shaker')) then
      perform private.fail('invalid_movement_spec');
    end if;
    if v_assessment is not null and not private.valid_activity_assessment(v_assessment, v_max) then
      perform private.fail('invalid_activity_assessment');
    end if;
    v_row.movement_id := v_movement.id;
    v_row.revision_id := v_revision.id;
    v_row.origin := 'teacher_created';
    v_row.assessment_mode := 'teacher_reviewed';
    v_row.display_title := v_title;
    v_row.display_instructions := v_instructions;
    v_row.display_safety_guidance := v_safety;
    v_row.allowed_prop := v_spec ->> 'required_prop';
    v_row.max_score := v_max;
    v_row.grading_locked := false;
    if v_assessment is not null then
      v_row.configuration_revision := 1;
      v_row.activity_assessment := v_assessment;
    end if;
  else
    perform private.fail('invalid_payload');
  end if;

  insert into public.group_assignments select v_row.*;
  perform private.replace_recipients(v_row, v_recipients);
  return jsonb_build_object(
    'assignment', private.assignment_json(v_row),
    'recipient_ids', private.recipient_ids(v_row.id)
  );
end;
$$;

create or replace function public.create_custom_movement_assignment(
  p_group_id text, p_movement_id text, p_revision_id text,
  p_attempt_policy jsonb, p_due_at timestamptz default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_group public.groups;
  v_movement public.custom_movements;
  v_revision public.custom_movement_revisions;
  v_row public.group_assignments;
begin
  select * into v_group from public.groups where id = p_group_id;
  if not found or v_group.teacher_id <> v_uid or v_group.status <> 'active' then
    perform private.fail('forbidden');
  end if;
  select * into v_movement from public.custom_movements where id = p_movement_id;
  select * into v_revision from public.custom_movement_revisions
    where id = p_revision_id and movement_id = p_movement_id;
  if v_movement.id is null or v_revision.id is null or v_movement.owner_uid <> v_uid
     or v_movement.owner_role <> 'teacher' or v_movement.status <> 'active'
     or v_movement.active_revision_id <> v_revision.id
     or not private.valid_attempt_policy(p_attempt_policy) then
    perform private.fail('identity_mismatch');
  end if;
  insert into public.group_assignments (
    id, teacher_id, group_id, movement_id, revision_id, origin, assessment_mode,
    status, display_title, teacher_display_name, group_name, display_instructions,
    allowed_prop, audience_type, attempt_policy, max_score, movement_template, due_at
  ) values (
    private.new_doc_id(), v_uid, v_group.id, v_movement.id, v_revision.id,
    'teacher_created', 'reference_matched', 'active', v_movement.name,
    private.caller_full_name(), v_group.name,
    nullif(btrim(v_movement.description), ''), v_movement.prop_type,
    'entire_class', p_attempt_policy, 12, v_revision.template, p_due_at
  ) returning * into v_row;
  return private.assignment_json(v_row);
end;
$$;

create or replace function private.require_owned_assignment(p_assignment_id text)
returns public.group_assignments language plpgsql security definer set search_path = '' as $$
declare
  v_row public.group_assignments;
begin
  perform private.require_verified_teacher();
  select * into v_row from public.group_assignments where id = p_assignment_id for update;
  if not found then
    perform private.fail('not_found');
  end if;
  if v_row.teacher_id <> auth.uid() then
    perform private.fail('forbidden');
  end if;
  return v_row;
end;
$$;

-- p_action: archive | restore | publish_now
create or replace function public.set_assignment_status(p_assignment_id text, p_action text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_row public.group_assignments := private.require_owned_assignment(p_assignment_id);
begin
  if v_row.assessment_mode = 'template_scored' then
    perform private.fail('identity_mismatch');
  end if;
  if p_action = 'archive' and v_row.status = 'active' then
    update public.group_assignments set status = 'archived', publish_at = null, updated_at = now()
    where id = v_row.id;
  elsif p_action = 'restore' and v_row.status = 'archived' then
    update public.group_assignments set status = 'active', publish_at = null, updated_at = now()
    where id = v_row.id;
  elsif p_action = 'publish_now' and v_row.status in ('draft', 'scheduled') then
    update public.group_assignments set status = 'active', publish_at = null, updated_at = now()
    where id = v_row.id;
  else
    perform private.fail('invalid_state');
  end if;
end;
$$;

create or replace function public.schedule_assignment_publication(
  p_assignment_id text, p_publish_at timestamptz
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_row public.group_assignments := private.require_owned_assignment(p_assignment_id);
begin
  if p_publish_at is null or p_publish_at <= now()
     or v_row.status not in ('draft', 'scheduled')
     or (v_row.due_at is not null and v_row.due_at <= p_publish_at) then
    perform private.fail('invalid_state');
  end if;
  update public.group_assignments set status = 'scheduled', publish_at = p_publish_at,
    updated_at = now() where id = v_row.id;
end;
$$;

create or replace function public.update_assignment_settings(
  p_assignment_id text, p_due_at timestamptz, p_max_score int, p_topic text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_row public.group_assignments := private.require_owned_assignment(p_assignment_id);
  v_topic text := nullif(btrim(coalesce(p_topic, '')), '');
begin
  if v_row.status not in ('active', 'draft', 'scheduled') or v_row.assessment_mode = 'template_scored' then
    perform private.fail('invalid_state');
  end if;
  if v_topic is not null and char_length(v_topic) > 80 then
    perform private.fail('invalid_topic');
  end if;
  if p_due_at is not null and v_row.publish_at is not null and p_due_at <= v_row.publish_at then
    perform private.fail('invalid_publication');
  end if;
  if p_max_score is not null then
    if p_max_score not between 1 and 100 or v_row.origin <> 'teacher_created'
       or coalesce(v_row.grading_locked, false) or v_row.activity_assessment is not null
       or v_row.assessment_mode = 'reference_matched'
       or exists (select 1 from public.assignment_attempts a
                  where a.assignment_id = v_row.id and a.status = 'checked') then
      perform private.fail('invalid_state');
    end if;
  end if;
  update public.group_assignments set
    due_at = p_due_at,
    topic = v_topic,
    max_score = coalesce(p_max_score, max_score),
    grading_locked = case when p_max_score is not null then false else grading_locked end,
    grading_locked_at = case when p_max_score is not null then null else grading_locked_at end,
    updated_at = now()
  where id = v_row.id returning * into v_row;
  return private.assignment_json(v_row);
end;
$$;

-- Former updateAssignmentConfiguration Function.
create or replace function public.update_assignment_configuration(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_row public.group_assignments;
  v_next public.group_assignments;
  v_group public.groups;
  v_audience text := p ->> 'audience_type';
  v_recipient_text text[] := coalesce(
    array(select jsonb_array_elements_text(coalesce(p -> 'recipient_ids', '[]'::jsonb))), '{}');
  v_recipients uuid[];
  v_official text := nullif(btrim(coalesce(p ->> 'official_movement_name', '')), '');
  v_policy jsonb := p -> 'attempt_policy';
  v_due timestamptz := private.parse_timestamp(p ->> 'due_at', 'invalid_due_at');
  v_topic text := nullif(btrim(coalesce(p ->> 'topic', '')), '');
  v_title text := nullif(btrim(coalesce(p ->> 'display_title', '')), '');
  v_instructions text := nullif(btrim(coalesce(p ->> 'display_instructions', '')), '');
  v_safety text := nullif(btrim(coalesce(p ->> 'display_safety_guidance', '')), '');
  v_assessment jsonb := nullif(p -> 'activity_assessment', 'null'::jsonb);
  v_movement public.teacher_movements;
  v_revision public.teacher_movement_revisions;
  v_has_work boolean;
  v_semantic_changed boolean;
  v_identity_changed boolean;
  v_old_recipients jsonb;
begin
  if not private.valid_doc_id(p ->> 'assignment_id') or not private.valid_doc_id(p ->> 'group_id')
     or not private.is_int_in(p -> 'expected_configuration_revision', 1, 2147483647)
     or not private.valid_attempt_policy(v_policy)
     or (v_topic is not null and char_length(v_topic) > 80)
     or (v_safety is not null and char_length(v_safety) > 1000) then
    perform private.fail('invalid_payload');
  end if;
  if v_official is not null then
    if not private.official_movement_supports_prop(v_official, p ->> 'allowed_prop') then
      perform private.fail('invalid_payload');
    end if;
  elsif not private.valid_doc_id(p ->> 'teacher_movement_id')
     or not private.valid_doc_id(p ->> 'teacher_revision_id')
     or not private.bounded_text(v_title, 80) or not private.bounded_text(v_instructions, 2000)
     or not private.valid_activity_assessment(v_assessment,
       (v_assessment #>> '{rubric,maximum_score}')::int) then
    perform private.fail('invalid_payload');
  end if;

  select * into v_row from public.group_assignments where id = p ->> 'assignment_id' for update;
  if not found then perform private.fail('not_found'); end if;
  select * into v_group from public.groups where id = p ->> 'group_id';
  if v_row.teacher_id <> v_uid or v_row.assessment_mode = 'template_scored'
     or v_row.status not in ('draft', 'scheduled', 'active')
     or v_row.deletion_state = 'deleting'
     or coalesce(v_row.configuration_revision, 1) <> (p ->> 'expected_configuration_revision')::int
     or v_group.id is null or v_group.teacher_id <> v_uid or v_group.status <> 'active' then
    perform private.fail('conflict');
  end if;

  v_next := v_row;
  v_next.group_id := v_group.id;
  v_next.group_name := v_group.name;
  v_next.audience_type := v_audience;
  v_next.attempt_policy := v_policy;
  v_next.topic := v_topic;
  v_next.due_at := v_due;
  if v_official is not null then
    v_next.movement_id := private.official_movement_id(v_official);
    v_next.revision_id := private.official_movement_id(v_official) || '_v1';
    v_next.origin := 'official_elixr';
    v_next.assessment_mode := 'official_guided';
    v_next.official_movement_name := v_official;
    v_next.display_title := v_official;
    v_next.allowed_prop := p ->> 'allowed_prop';
    v_next.display_instructions := null;
    v_next.display_safety_guidance := null;
    v_next.activity_assessment := null;
    v_next.max_score := null;
  else
    select * into v_movement from public.teacher_movements where id = p ->> 'teacher_movement_id';
    select * into v_revision from public.teacher_movement_revisions
      where id = p ->> 'teacher_revision_id' and movement_id = p ->> 'teacher_movement_id';
    -- A saved assignment may retain its own pinned revision; any other
    -- revision must be the movement's current active revision.
    if v_movement.id is null or v_revision.id is null or v_movement.teacher_id <> v_uid
       or v_revision.teacher_id <> v_uid or v_revision.assessment_mode <> 'teacher_reviewed'
       or v_revision.spec ->> 'capability' is distinct from 'teacher_review_only'
       or not (v_revision.spec ->> 'required_prop' in ('bottle', 'shaker', 'bottle_and_shaker'))
       or (not (v_row.origin = 'teacher_created' and v_row.movement_id = v_movement.id
                and v_row.revision_id = v_revision.id)
           and (v_movement.status <> 'active' or v_movement.current_revision_id <> v_revision.id)) then
      perform private.fail('invalid_movement');
    end if;
    v_next.movement_id := v_movement.id;
    v_next.revision_id := v_revision.id;
    v_next.origin := 'teacher_created';
    v_next.assessment_mode := 'teacher_reviewed';
    v_next.official_movement_name := null;
    v_next.display_title := v_title;
    v_next.display_instructions := v_instructions;
    v_next.display_safety_guidance := v_safety;
    v_next.allowed_prop := v_revision.spec ->> 'required_prop';
    v_next.activity_assessment := v_assessment;
    v_next.max_score := (v_assessment #>> '{rubric,maximum_score}')::int;
  end if;

  v_recipients := private.require_recipients(v_group.id, v_uid, v_audience, v_recipient_text);
  v_has_work := exists (select 1 from public.assignment_attempts a where a.assignment_id = v_row.id);
  v_old_recipients := private.recipient_ids(v_row.id);
  v_semantic_changed :=
    (v_row.group_id, v_row.movement_id, v_row.revision_id, v_row.origin, v_row.assessment_mode,
     v_row.official_movement_name, v_row.allowed_prop, v_row.audience_type, v_row.max_score)
      is distinct from
    (v_next.group_id, v_next.movement_id, v_next.revision_id, v_next.origin, v_next.assessment_mode,
     v_next.official_movement_name, v_next.allowed_prop, v_next.audience_type, v_next.max_score)
    or v_row.attempt_policy is distinct from v_next.attempt_policy
    or v_row.activity_assessment is distinct from v_next.activity_assessment
    or v_old_recipients is distinct from (
      select coalesce(jsonb_agg(r::text order by r), '[]'::jsonb) from unnest(v_recipients) r);
  if private.assignment_is_published(v_row.status, v_row.publish_at) and v_has_work and v_semantic_changed then
    perform private.fail('trainee_work_exists');
  end if;
  v_identity_changed :=
    (v_row.movement_id, v_row.revision_id, v_row.origin, v_row.assessment_mode,
     v_row.official_movement_name, v_row.allowed_prop, v_row.max_score)
      is distinct from
    (v_next.movement_id, v_next.revision_id, v_next.origin, v_next.assessment_mode,
     v_next.official_movement_name, v_next.allowed_prop, v_next.max_score)
    or v_row.activity_assessment is distinct from v_next.activity_assessment;
  if coalesce(v_row.grading_locked, false) and v_identity_changed then
    perform private.fail('trainee_work_exists');
  end if;
  if v_identity_changed and not v_has_work then
    v_next.grading_locked := case when v_official is not null then null else false end;
    v_next.grading_locked_at := null;
  end if;
  if v_due is not null and v_row.status = 'scheduled' and v_due <= v_row.publish_at then
    perform private.fail('invalid_publication');
  end if;
  if not v_semantic_changed
     and v_row.display_title is not distinct from v_next.display_title
     and v_row.display_instructions is not distinct from v_next.display_instructions
     and v_row.display_safety_guidance is not distinct from v_next.display_safety_guidance
     and v_row.topic is not distinct from v_next.topic
     and v_row.due_at is not distinct from v_next.due_at then
    return jsonb_build_object('assignment', private.assignment_json(v_row),
      'recipient_ids', v_old_recipients);
  end if;
  v_next.configuration_revision := (p ->> 'expected_configuration_revision')::int + 1;
  v_next.updated_at := now();
  update public.group_assignments set
    group_id = v_next.group_id, group_name = v_next.group_name,
    movement_id = v_next.movement_id, revision_id = v_next.revision_id,
    origin = v_next.origin, assessment_mode = v_next.assessment_mode,
    official_movement_name = v_next.official_movement_name,
    display_title = v_next.display_title,
    display_instructions = v_next.display_instructions,
    display_safety_guidance = v_next.display_safety_guidance,
    allowed_prop = v_next.allowed_prop, activity_assessment = v_next.activity_assessment,
    max_score = v_next.max_score, audience_type = v_next.audience_type,
    attempt_policy = v_next.attempt_policy, topic = v_next.topic, due_at = v_next.due_at,
    grading_locked = v_next.grading_locked, grading_locked_at = v_next.grading_locked_at,
    configuration_revision = v_next.configuration_revision, updated_at = now()
  where id = v_row.id returning * into v_next;
  perform private.replace_recipients(v_next, v_recipients);
  return jsonb_build_object('assignment', private.assignment_json(v_next),
    'recipient_ids', private.recipient_ids(v_next.id));
end;
$$;

-- Former updateTeacherActivityAssignment Function.
create or replace function public.update_teacher_activity_assignment(p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_row public.group_assignments;
  v_title text := nullif(btrim(coalesce(p ->> 'display_title', '')), '');
  v_instructions text := nullif(btrim(coalesce(p ->> 'display_instructions', '')), '');
  v_safety text := nullif(btrim(coalesce(p ->> 'display_safety_guidance', '')), '');
  v_topic text := nullif(btrim(coalesce(p ->> 'topic', '')), '');
  v_audience text := p ->> 'audience_type';
  v_recipient_text text[] := coalesce(
    array(select jsonb_array_elements_text(coalesce(p -> 'recipient_ids', '[]'::jsonb))), '{}');
  v_recipients uuid[];
  v_assessment jsonb := p -> 'activity_assessment';
  v_max int := (p #>> '{activity_assessment,rubric,maximum_score}')::int;
  v_prop text := p ->> 'allowed_prop';
  v_policy jsonb := p -> 'attempt_policy';
  v_due timestamptz := private.parse_timestamp(p ->> 'due_at', 'invalid_due_at');
  v_config_changed boolean;
  v_audience_changed boolean;
  v_policy_changed boolean;
  v_has_work boolean;
begin
  if not private.valid_doc_id(p ->> 'assignment_id')
     or not private.is_int_in(p -> 'expected_configuration_revision', 1, 2147483647)
     or not private.bounded_text(v_title, 80) or not private.bounded_text(v_instructions, 2000)
     or (v_safety is not null and char_length(v_safety) > 1000)
     or (v_topic is not null and char_length(v_topic) > 80)
     or not (v_prop in ('bottle', 'shaker', 'bottle_and_shaker'))
     or v_max is null or v_max not between 1 and 100
     or not private.valid_attempt_policy(v_policy)
     or not private.valid_activity_assessment(v_assessment, v_max) then
    perform private.fail('invalid_payload');
  end if;
  select * into v_row from public.group_assignments where id = p ->> 'assignment_id' for update;
  if not found then perform private.fail('not_found'); end if;
  if v_row.teacher_id <> v_uid or v_row.origin <> 'teacher_created'
     or v_row.assessment_mode <> 'teacher_reviewed'
     or v_row.status not in ('draft', 'scheduled', 'active')
     or v_row.deletion_state = 'deleting'
     or coalesce(v_row.configuration_revision, 1) <> (p ->> 'expected_configuration_revision')::int then
    perform private.fail('conflict');
  end if;
  if (v_policy ->> 'type') = 'finite' and exists (
    select 1 from public.assignment_attempt_states s
    where s.assignment_id = v_row.id and s.consumed_count > (v_policy ->> 'maximum_attempts')::int
  ) then
    perform private.fail('attempt_limit_conflict');
  end if;
  v_recipients := private.require_recipients(v_row.group_id, v_uid, v_audience, v_recipient_text);
  v_has_work := exists (select 1 from public.assignment_attempts a where a.assignment_id = v_row.id);
  v_config_changed := v_row.allowed_prop is distinct from v_prop
    or v_row.activity_assessment is distinct from v_assessment
    or v_row.max_score is distinct from v_max;
  v_audience_changed := v_row.audience_type is distinct from v_audience
    or private.recipient_ids(v_row.id) is distinct from (
      select coalesce(jsonb_agg(r::text order by r), '[]'::jsonb) from unnest(v_recipients) r);
  v_policy_changed := v_row.attempt_policy is distinct from v_policy;
  if private.assignment_is_published(v_row.status, v_row.publish_at) and v_has_work
     and (v_config_changed or v_audience_changed or v_policy_changed) then
    perform private.fail('trainee_work_exists');
  end if;
  if coalesce(v_row.grading_locked, false) and v_config_changed then
    perform private.fail('trainee_work_exists');
  end if;
  update public.group_assignments set
    display_title = v_title, display_instructions = v_instructions,
    display_safety_guidance = v_safety, topic = v_topic, due_at = v_due,
    audience_type = v_audience, activity_assessment = v_assessment,
    attempt_policy = v_policy, allowed_prop = v_prop, max_score = v_max,
    configuration_revision = (p ->> 'expected_configuration_revision')::int + 1,
    updated_at = now()
  where id = v_row.id returning * into v_row;
  perform private.replace_recipients(v_row, v_recipients);
  return jsonb_build_object('assignment', private.assignment_json(v_row),
    'recipient_ids', private.recipient_ids(v_row.id));
end;
$$;

create or replace function public.set_deadline_override(
  p_assignment_id text, p_trainee_id uuid, p_due_at timestamptz
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_row public.group_assignments := private.require_owned_assignment(p_assignment_id);
begin
  if v_row.due_at is null or p_due_at is null or p_due_at <= v_row.due_at
     or not private.is_approved_member(v_row.group_id, p_trainee_id, v_row.teacher_id)
     or not private.assignment_audience_allows(v_row.id, v_row.audience_type, p_trainee_id) then
    perform private.fail('forbidden');
  end if;
  insert into public.assignment_deadline_overrides (
    assignment_id, trainee_id, group_id, teacher_id, due_at
  ) values (v_row.id, p_trainee_id, v_row.group_id, v_row.teacher_id, p_due_at)
  on conflict (assignment_id, trainee_id) do update set
    due_at = excluded.due_at, group_id = excluded.group_id,
    teacher_id = excluded.teacher_id, updated_at = now();
end;
$$;

create or replace function public.clear_deadline_override(
  p_assignment_id text, p_trainee_id uuid
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_row public.group_assignments := private.require_owned_assignment(p_assignment_id);
begin
  delete from public.assignment_deadline_overrides
  where assignment_id = v_row.id and trainee_id = p_trainee_id;
end;
$$;

-- Trainee listing with the caller's effective (override-aware) deadline.
create or replace function public.list_trainee_assignments(p_group_id text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_trainee();
begin
  return coalesce((
    select jsonb_agg(
      private.assignment_json(a)
        || case when private.effective_due_at(a.id, v_uid) is not null
             then jsonb_build_object('due_at', private.effective_due_at(a.id, v_uid))
             else '{}'::jsonb end
      order by a.created_at desc)
    from public.group_assignments a
    where (p_group_id is null or a.group_id = p_group_id)
      and coalesce(a.deletion_state, '') <> 'deleting'
      and (a.status = 'archived' or private.assignment_is_published(a.status, a.publish_at))
      and private.is_approved_member(a.group_id, v_uid, a.teacher_id)
      and private.assignment_audience_allows(a.id, a.audience_type, v_uid)
  ), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- Trainee assignment attempts
-- ---------------------------------------------------------------------------

create or replace function private.require_trainee_assignment(
  p_assignment_id text, p_uid uuid
) returns public.group_assignments language plpgsql security definer set search_path = '' as $$
declare
  v_row public.group_assignments;
begin
  select * into v_row from public.group_assignments where id = p_assignment_id;
  if not found then
    perform private.fail('not_found');
  end if;
  if not private.is_trainee(p_uid)
     or not private.is_approved_member(v_row.group_id, p_uid, v_row.teacher_id)
     or not private.assignment_audience_allows(v_row.id, v_row.audience_type, p_uid)
     or not private.assignment_is_published(v_row.status, v_row.publish_at)
     or v_row.deletion_state = 'deleting' then
    perform private.fail('forbidden');
  end if;
  return v_row;
end;
$$;

create or replace function private.submission_open(
  p_assignment public.group_assignments, p_trainee uuid, p_recording_started timestamptz default null
) returns boolean language sql stable as $$
  select private.assignment_is_published(p_assignment.status, p_assignment.publish_at)
    and coalesce(p_assignment.deletion_state, '') <> 'deleting'
    and (
      private.effective_due_at(p_assignment.id, p_trainee) is null
      or now() <= private.effective_due_at(p_assignment.id, p_trainee)
      or (p_recording_started is not null
        and p_recording_started <= private.effective_due_at(p_assignment.id, p_trainee))
    )
$$;

-- Creates a Teacher-reviewed (non-Activity) attempt with server-derived
-- identity. A duplicate deterministic ID raises attempt_exists so callers
-- read and reconcile the existing attempt.
create or replace function public.create_assignment_attempt(
  p_attempt_id text, p_assignment_id text, p_attempt_kind text, p_status text,
  p_supersedes_attempt_id text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_assignment public.group_assignments := private.require_trainee_assignment(p_assignment_id, v_uid);
  v_previous public.assignment_attempts;
  v_row public.assignment_attempts;
begin
  if v_assignment.origin <> 'teacher_created' or v_assignment.assessment_mode <> 'teacher_reviewed'
     or not private.valid_doc_id(p_attempt_id) then
    perform private.fail('identity_mismatch');
  end if;
  if exists (select 1 from public.assignment_attempts where id = p_attempt_id) then
    perform private.fail('attempt_exists');
  end if;
  if p_attempt_kind = 'teacher_review_draft' then
    if p_attempt_id <> 'tc_draft_' || v_assignment.id || '_' || v_uid
       or p_status not in ('draft', 'in_progress') then
      perform private.fail('identity_mismatch');
    end if;
  elsif p_attempt_kind = 'teacher_review_submission' then
    if v_assignment.activity_assessment is not null
       or p_attempt_id !~ '^review_sub_[A-Za-z0-9_-]+$' then
      perform private.fail('identity_mismatch');
    end if;
    if p_attempt_id = 'review_sub_' || v_assignment.id || '_' || v_uid then
      if p_status <> 'in_progress' or p_supersedes_attempt_id is not null then
        perform private.fail('identity_mismatch');
      end if;
      if not private.submission_open(v_assignment, v_uid) then
        perform private.fail('deadline_passed');
      end if;
    elsif p_status <> 'draft' then
      perform private.fail('identity_mismatch');
    elsif p_supersedes_attempt_id is not null then
      select * into v_previous from public.assignment_attempts where id = p_supersedes_attempt_id;
      if not found or v_previous.attempt_kind <> 'teacher_review_submission'
         or v_previous.status <> 'needs_retry' or v_previous.review_verdict <> 'needs_retry'
         or v_previous.trainee_id <> v_uid or v_previous.assignment_id <> v_assignment.id
         or v_previous.movement_id <> v_assignment.movement_id
         or v_previous.revision_id <> v_assignment.revision_id then
        perform private.fail('invalid_state');
      end if;
    end if;
  else
    perform private.fail('identity_mismatch');
  end if;
  insert into public.assignment_attempts (
    id, trainee_id, teacher_id, group_id, assignment_id, movement_id, revision_id,
    origin, assessment_mode, attempt_kind, status, supersedes_attempt_id
  ) values (
    p_attempt_id, v_uid, v_assignment.teacher_id, v_assignment.group_id, v_assignment.id,
    v_assignment.movement_id, v_assignment.revision_id, 'teacher_created',
    'teacher_reviewed', p_attempt_kind, p_status, p_supersedes_attempt_id
  ) returning * into v_row;
  return private.attempt_json(v_row);
end;
$$;

-- Reference-matched (custom movement) assignment result. Finite policies
-- claim deterministic slots so the attempt limit cannot be exceeded.
create or replace function public.save_reference_match_attempt(
  p_assignment_id text, p_total int, p_performance_level text, p_component_scores jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_assignment public.group_assignments := private.require_trainee_assignment(p_assignment_id, v_uid);
  v_policy jsonb;
  v_sum int;
  v_row public.assignment_attempts;
  v_id text;
begin
  if v_assignment.assessment_mode <> 'reference_matched' then
    perform private.fail('identity_mismatch');
  end if;
  if not private.submission_open(v_assignment, v_uid) then
    perform private.fail('deadline_passed');
  end if;
  if jsonb_typeof(p_component_scores) <> 'object'
     or (select array_agg(k order by k) from jsonb_object_keys(p_component_scores) k)
       <> array['Body technique', 'Control/stability', 'Hand technique', 'Prop path', 'Timing']
     or exists (select 1 from jsonb_each(p_component_scores) e where not private.is_int_in(e.value, 0, 3)) then
    perform private.fail('malformed');
  end if;
  select sum((value #>> '{}')::int) into v_sum from jsonb_each(p_component_scores);
  if p_total <> (v_sum * 12 + 7) / 15 or p_performance_level <> private.performance_level(p_total) then
    perform private.fail('malformed');
  end if;
  v_policy := private.effective_attempt_policy(v_assignment);
  perform pg_advisory_xact_lock(hashtext('ref_attempt:' || v_assignment.id || ':' || v_uid));
  if v_policy ->> 'type' = 'finite' then
    select s into v_id from generate_series(1, (v_policy ->> 'maximum_attempts')::int) n,
      lateral (select 'custom_' || v_assignment.id || '_' || v_uid || '_' || n as s) ids
    where not exists (select 1 from public.assignment_attempts a where a.id = ids.s)
    order by n limit 1;
    if v_id is null then
      perform private.fail('attempts_exhausted');
    end if;
  else
    v_id := private.new_doc_id();
  end if;
  insert into public.assignment_attempts (
    id, trainee_id, teacher_id, group_id, assignment_id, movement_id, revision_id,
    origin, assessment_mode, attempt_kind, status, reference_total,
    reference_max_total, reference_component_scores, performance_level, prop_type,
    completed_at
  ) values (
    v_id, v_uid, v_assignment.teacher_id, v_assignment.group_id, v_assignment.id,
    v_assignment.movement_id, v_assignment.revision_id, 'teacher_created',
    'reference_matched', 'reference_match', 'submitted', p_total, 12,
    p_component_scores, p_performance_level, v_assignment.allowed_prop, now()
  ) returning * into v_row;
  return private.attempt_json(v_row);
end;
$$;

-- Trainee-owned transitions of Teacher-reviewed attempts (former Firestore
-- rule state machine). Actor identity and time come from the server.
create or replace function public.transition_trainee_attempt(
  p_attempt_id text, p_action text, p_payload jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_row public.assignment_attempts;
  v_assignment public.group_assignments;
  v_canonical boolean;
  v_path text;
  v_size int := (p_payload ->> 'video_size_bytes')::int;
  v_duration int := (p_payload ->> 'video_duration_ms')::int;
begin
  select * into v_row from public.assignment_attempts where id = p_attempt_id for update;
  if not found then
    perform private.fail('not_found');
  end if;
  if v_row.trainee_id <> v_uid
     or v_row.attempt_kind not in ('teacher_review_draft', 'teacher_review_submission') then
    perform private.fail('forbidden');
  end if;
  select * into v_assignment from public.group_assignments where id = v_row.assignment_id;
  v_canonical := v_row.id = 'review_sub_' || v_row.assignment_id || '_' || v_row.trainee_id;
  v_path := 'assignment_submissions/' || v_row.teacher_id || '/' || v_row.group_id || '/'
    || v_row.assignment_id || '/' || v_row.trainee_id || '/' || v_row.id || '.mp4';

  if p_action = 'promote' then
    if v_row.status <> 'draft' or v_row.abandoned_at is not null
       or v_row.video_storage_path is not null or v_row.submitted_at is not null
       or (v_row.attempt_kind = 'teacher_review_submission' and not v_canonical)
       or not private.submission_open(v_assignment, v_uid) then
      perform private.fail('invalid_state');
    end if;
    update public.assignment_attempts set status = 'in_progress',
      deletion_failed = null, deletion_failed_at = null
    where id = v_row.id returning * into v_row;
  elsif p_action in ('submit', 'attach_draft') then
    if v_row.attempt_kind <> 'teacher_review_submission'
       or v_row.activity_assessment_snapshot is not null
       or v_row.abandoned_at is not null
       or (p_payload ->> 'video_storage_path') is distinct from v_path
       or (p_payload ->> 'video_content_type') is distinct from 'video/mp4'
       or v_size is null or v_size not between 1 and 52428800
       or v_duration is null or v_duration not between 1 and 60000 then
      perform private.fail('invalid_state');
    end if;
    if not private.submission_open(v_assignment, v_uid) then
      perform private.fail('deadline_passed');
    end if;
    if p_action = 'attach_draft' then
      if not v_canonical or v_row.status <> 'in_progress' or v_row.video_storage_path is not null then
        perform private.fail('invalid_state');
      end if;
      update public.assignment_attempts set video_storage_path = v_path,
        video_content_type = 'video/mp4', video_size_bytes = v_size,
        video_duration_ms = v_duration, draft_saved_at = now(), deletion_failed = null
      where id = v_row.id returning * into v_row;
    else
      if v_row.status not in ('draft', 'in_progress')
         or (v_row.draft_saved_at is not null and (v_row.video_size_bytes <> v_size
           or v_row.video_duration_ms <> v_duration)) then
        perform private.fail('invalid_state');
      end if;
      update public.assignment_attempts set status = 'submitted',
        video_storage_path = v_path, video_content_type = 'video/mp4',
        video_size_bytes = v_size, video_duration_ms = v_duration,
        submitted_at = now(), video_expires_at = now() + interval '30 days'
      where id = v_row.id returning * into v_row;
    end if;
  elsif p_action = 'turn_in' then
    if not v_canonical or v_row.status <> 'in_progress' or v_row.draft_saved_at is null
       or v_row.video_storage_path is null or v_row.draft_cleanup_started_at is not null then
      perform private.fail('invalid_state');
    end if;
    if not private.submission_open(v_assignment, v_uid) then
      perform private.fail('deadline_passed');
    end if;
    update public.assignment_attempts set status = 'submitted', submitted_at = now(),
      video_expires_at = now() + interval '30 days', draft_saved_at = null
    where id = v_row.id returning * into v_row;
  elsif p_action = 'begin_draft_removal' then
    if not v_canonical or v_row.status <> 'in_progress' or v_row.draft_saved_at is null then
      perform private.fail('invalid_state');
    end if;
    update public.assignment_attempts set draft_cleanup_started_at = now()
    where id = v_row.id returning * into v_row;
  elsif p_action = 'complete_draft_removal' then
    if not v_canonical or v_row.status <> 'in_progress' or v_row.draft_cleanup_started_at is null then
      perform private.fail('invalid_state');
    end if;
    update public.assignment_attempts set video_storage_path = null, video_content_type = null,
      video_size_bytes = null, video_duration_ms = null, draft_saved_at = null,
      draft_cleanup_started_at = null
    where id = v_row.id returning * into v_row;
  elsif p_action = 'begin_unsubmit' then
    if not v_canonical then
      perform private.fail('invalid_state');
    end if;
    if v_row.status <> 'unsubmitting' then
      if not private.submission_open(v_assignment, v_uid) then
        perform private.fail('deadline_passed');
      end if;
      if v_row.status <> 'submitted' or v_row.video_storage_path is null then
        perform private.fail('invalid_state');
      end if;
      update public.assignment_attempts set status = 'unsubmitting', deletion_failed = false,
        deletion_failed_at = null
      where id = v_row.id returning * into v_row;
    end if;
  elsif p_action = 'complete_unsubmit' then
    if not v_canonical or v_row.status <> 'unsubmitting' then
      perform private.fail('invalid_state');
    end if;
    update public.assignment_attempts set status = 'in_progress', video_storage_path = null,
      video_content_type = null, video_size_bytes = null, video_duration_ms = null,
      submitted_at = null, video_expires_at = null, video_deleted_at = null,
      deletion_failed = false, deletion_failed_at = null
    where id = v_row.id returning * into v_row;
  elsif p_action = 'abandon' then
    if v_canonical or v_row.attempt_kind <> 'teacher_review_submission'
       or v_row.activity_assessment_snapshot is not null
       or v_row.status <> 'draft' or v_row.abandoned_at is not null
       or v_row.submitted_at is not null or v_row.reviewed_at is not null then
      perform private.fail('invalid_state');
    end if;
    update public.assignment_attempts set abandoned_at = now(),
      video_deleted_at = case when (p_payload ->> 'video_deleted')::boolean then now() end,
      deletion_failed = case
        when (p_payload ->> 'deletion_failed')::boolean then true
        when (p_payload ->> 'video_deleted')::boolean then false end,
      deletion_failed_at = case when (p_payload ->> 'deletion_failed')::boolean then now() end
    where id = v_row.id returning * into v_row;
  else
    perform private.fail('invalid_payload');
  end if;
  return private.attempt_json(v_row);
end;
$$;

-- Video lifecycle bookkeeping by either participant (retention cleanup,
-- unsubmit failures). The object itself is deleted through Storage.
create or replace function public.mark_attempt_video_state(
  p_attempt_id text, p_deleted boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_row public.assignment_attempts;
  v_canonical boolean;
  v_is_teacher boolean;
begin
  select * into v_row from public.assignment_attempts where id = p_attempt_id for update;
  if not found then
    perform private.fail('not_found');
  end if;
  v_is_teacher := v_row.teacher_id = v_uid and private.is_teacher();
  if not v_is_teacher and v_row.trainee_id <> v_uid then
    perform private.fail('forbidden');
  end if;
  v_canonical := v_row.id = 'review_sub_' || v_row.assignment_id || '_' || v_row.trainee_id;
  if p_deleted then
    if v_canonical and not v_is_teacher then
      perform private.fail('forbidden');
    end if;
    if not (v_row.status in ('submitted', 'approved', 'needs_retry', 'checked')
            or (v_row.status = 'draft' and v_row.abandoned_at is not null))
       or (v_row.status = 'checked' and not v_is_teacher) then
      perform private.fail('invalid_state');
    end if;
    update public.assignment_attempts set video_storage_path = null, video_deleted_at = now(),
      deletion_failed = false, deletion_failed_at = null
    where id = v_row.id returning * into v_row;
  else
    if v_canonical and (v_row.trainee_id <> v_uid or v_row.status <> 'unsubmitting') then
      perform private.fail('forbidden');
    end if;
    update public.assignment_attempts set deletion_failed = true, deletion_failed_at = now()
    where id = v_row.id returning * into v_row;
  end if;
  return private.attempt_json(v_row);
end;
$$;

-- ---------------------------------------------------------------------------
-- Teacher review of attempts
-- ---------------------------------------------------------------------------

create or replace function public.save_teacher_review(
  p_attempt_id text, p_grade_score int, p_feedback text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_row public.assignment_attempts;
  v_assignment public.group_assignments;
  v_max int;
  v_feedback text := nullif(btrim(coalesce(p_feedback, '')), '');
begin
  select * into v_row from public.assignment_attempts where id = p_attempt_id for update;
  if not found then perform private.fail('not_found'); end if;
  select * into v_assignment from public.group_assignments where id = v_row.assignment_id for update;
  if v_row.teacher_id <> v_uid or v_row.attempt_kind <> 'teacher_review_submission'
     or v_assignment.origin <> 'teacher_created' or v_assignment.assessment_mode <> 'teacher_reviewed'
     or v_row.group_id <> v_assignment.group_id or v_row.movement_id <> v_assignment.movement_id
     or v_row.revision_id <> v_assignment.revision_id then
    perform private.fail('forbidden');
  end if;
  if v_row.status not in ('submitted', 'checked', 'approved', 'needs_retry') then
    perform private.fail('invalid_state');
  end if;
  v_max := coalesce(v_row.grade_max_score, v_assignment.max_score, 100);
  if v_max not between 1 and 100 or p_grade_score not between 0 and v_max then
    perform private.fail('invalid_grade');
  end if;
  if v_feedback is not null and char_length(v_feedback) > 1000 then
    perform private.fail('invalid_grade');
  end if;
  update public.assignment_attempts set status = 'checked', grade_score = p_grade_score,
    grade_max_score = v_max, checked_at = coalesce(checked_at, now()),
    review_updated_at = now(), review_revision = coalesce(review_revision, 0) + 1,
    video_expires_at = now() + interval '14 days', review_verdict = null,
    reviewed_at = null, result_sent_revision = null, result_sent_at = null,
    result_message_id = null, review_feedback = v_feedback
  where id = v_row.id returning * into v_row;
  if not coalesce(v_assignment.grading_locked, false) then
    update public.group_assignments set max_score = v_max, grading_locked = true,
      grading_locked_at = now(), updated_at = now()
    where id = v_assignment.id;
  end if;
  return private.attempt_json(v_row);
end;
$$;

create or replace function public.mark_review_result_sent(
  p_attempt_id text, p_message_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_row public.assignment_attempts;
begin
  select * into v_row from public.assignment_attempts where id = p_attempt_id for update;
  if not found then perform private.fail('not_found'); end if;
  if v_row.teacher_id <> v_uid or v_row.status <> 'checked' or v_row.review_revision is null
     or not private.bounded_text(p_message_id, 256) then
    perform private.fail('invalid_state');
  end if;
  if v_row.result_sent_revision is distinct from v_row.review_revision then
    update public.assignment_attempts set result_sent_revision = review_revision,
      result_sent_at = now(), result_message_id = btrim(p_message_id)
    where id = v_row.id returning * into v_row;
  end if;
  return private.attempt_json(v_row);
end;
$$;

-- Legacy non-canonical approve / needs_retry review.
create or replace function public.review_teacher_submission(
  p_attempt_id text, p_verdict text, p_feedback text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_row public.assignment_attempts;
  v_feedback text := nullif(btrim(coalesce(p_feedback, '')), '');
begin
  select * into v_row from public.assignment_attempts where id = p_attempt_id for update;
  if not found then perform private.fail('not_found'); end if;
  if v_row.teacher_id <> v_uid then perform private.fail('forbidden'); end if;
  if v_row.attempt_kind <> 'teacher_review_submission' or v_row.status <> 'submitted'
     or v_row.id = 'review_sub_' || v_row.assignment_id || '_' || v_row.trainee_id
     or p_verdict not in ('approved', 'needs_retry')
     or (v_feedback is not null and char_length(v_feedback) > 1000) then
    perform private.fail('invalid_state');
  end if;
  update public.assignment_attempts set status = p_verdict, review_verdict = p_verdict,
    reviewed_at = now(), video_expires_at = now() + interval '14 days',
    review_feedback = coalesce(v_feedback, review_feedback)
  where id = v_row.id returning * into v_row;
  return private.attempt_json(v_row);
end;
$$;

-- ---------------------------------------------------------------------------
-- Teacher Activity attempts (reserve -> consume -> finalize -> turn in)
-- ---------------------------------------------------------------------------

create or replace function private.activity_state(p_assignment_id text, p_trainee uuid)
returns public.assignment_attempt_states language plpgsql security definer set search_path = '' as $$
declare
  v_state public.assignment_attempt_states;
begin
  select * into v_state from public.assignment_attempt_states
  where id = p_assignment_id || '__' || p_trainee for update;
  return v_state;
end;
$$;

create or replace function public.reserve_teacher_activity_attempt(
  p_assignment_id text, p_request_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_assignment public.group_assignments;
  v_state public.assignment_attempt_states;
  v_policy jsonb;
  v_ordinal int;
  v_attempt_id text;
  v_row public.assignment_attempts;
begin
  if not private.valid_doc_id(p_request_id) then
    perform private.fail('invalid_payload');
  end if;
  v_assignment := private.require_trainee_assignment(p_assignment_id, v_uid);
  if not private.valid_activity_assessment(v_assignment.activity_assessment, v_assignment.max_score) then
    perform private.fail('forbidden');
  end if;
  if private.effective_due_at(v_assignment.id, v_uid) is not null
     and now() > private.effective_due_at(v_assignment.id, v_uid) then
    perform private.fail('deadline_passed');
  end if;
  perform pg_advisory_xact_lock(hashtext('activity_state:' || v_assignment.id || ':' || v_uid));
  v_state := private.activity_state(v_assignment.id, v_uid);
  if v_state.id is not null and v_state.state_kind <> 'teacher_activity' then
    perform private.fail('forbidden');
  end if;
  if coalesce(v_state.graded, false) or coalesce(v_assignment.grading_locked, false) then
    perform private.fail('graded');
  end if;
  if v_state.active_attempt_id is not null then
    if v_state.active_request_id = p_request_id then
      select * into v_row from public.assignment_attempts where id = v_state.active_attempt_id;
      return jsonb_build_object('attempt', private.attempt_json(v_row), 'reused', true);
    end if;
    raise exception using message = 'attempt_in_progress', errcode = 'P0001',
      detail = v_state.active_attempt_id;
  end if;
  v_policy := private.effective_attempt_policy(v_assignment);
  if v_policy ->> 'type' = 'finite'
     and coalesce(v_state.consumed_count, 0) >= (v_policy ->> 'maximum_attempts')::int then
    perform private.fail('attempts_exhausted');
  end if;
  v_ordinal := greatest(coalesce(v_state.next_ordinal, 0), coalesce(v_state.consumed_count, 0)) + 1;
  v_attempt_id := 'activity_' || v_assignment.id || '_' || v_uid || '_' || v_ordinal;
  insert into public.assignment_attempts (
    id, trainee_id, teacher_id, group_id, assignment_id, movement_id, revision_id,
    origin, assessment_mode, attempt_kind, status, attempt_number,
    reservation_request_id, assignment_configuration_revision,
    activity_assessment_snapshot
  ) values (
    v_attempt_id, v_uid, v_assignment.teacher_id, v_assignment.group_id, v_assignment.id,
    v_assignment.movement_id, v_assignment.revision_id, 'teacher_created',
    'teacher_reviewed', 'teacher_review_submission', 'in_progress', v_ordinal,
    p_request_id, v_assignment.configuration_revision, v_assignment.activity_assessment
  ) returning * into v_row;
  insert into public.assignment_attempt_states (
    id, state_kind, assignment_id, trainee_id, teacher_id, group_id,
    consumed_count, next_ordinal, active_attempt_id, active_request_id,
    active_consumed, graded
  ) values (
    v_assignment.id || '__' || v_uid, 'teacher_activity', v_assignment.id, v_uid,
    v_assignment.teacher_id, v_assignment.group_id, coalesce(v_state.consumed_count, 0),
    v_ordinal, v_attempt_id, p_request_id, false, false
  ) on conflict (id) do update set
    next_ordinal = excluded.next_ordinal, active_attempt_id = excluded.active_attempt_id,
    active_request_id = excluded.active_request_id, active_consumed = false,
    updated_at = now();
  return jsonb_build_object('attempt', private.attempt_json(v_row), 'reused', false);
end;
$$;

create or replace function public.consume_teacher_activity_attempt(
  p_assignment_id text, p_attempt_id text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_assignment public.group_assignments;
  v_state public.assignment_attempt_states;
  v_row public.assignment_attempts;
begin
  perform pg_advisory_xact_lock(hashtext('activity_state:' || p_assignment_id || ':' || v_uid));
  v_state := private.activity_state(p_assignment_id, v_uid);
  select * into v_row from public.assignment_attempts where id = p_attempt_id for update;
  if v_state.id is null or v_row.id is null or v_state.state_kind <> 'teacher_activity'
     or v_state.active_attempt_id is distinct from p_attempt_id
     or v_row.trainee_id <> v_uid or v_row.assignment_id <> p_assignment_id then
    perform private.fail('forbidden');
  end if;
  if v_row.recording_started_at is not null then
    return;
  end if;
  v_assignment := private.require_trainee_assignment(p_assignment_id, v_uid);
  if coalesce(v_state.graded, false) or coalesce(v_assignment.grading_locked, false)
     or not private.valid_activity_assessment(v_assignment.activity_assessment, v_assignment.max_score)
     or (private.effective_due_at(v_assignment.id, v_uid) is not null
       and now() > private.effective_due_at(v_assignment.id, v_uid)) then
    perform private.fail('forbidden');
  end if;
  update public.assignment_attempts set recording_started_at = now() where id = v_row.id;
  update public.assignment_attempt_states set consumed_count = consumed_count + 1,
    active_consumed = true, updated_at = now()
  where id = v_state.id;
end;
$$;

-- Releases the active reservation; a consumed-but-unsubmitted recording is
-- refunded so finite assignments can be attempted again.
create or replace function public.abandon_teacher_activity_attempt(
  p_assignment_id text, p_attempt_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_state public.assignment_attempt_states;
  v_row public.assignment_attempts;
begin
  perform pg_advisory_xact_lock(hashtext('activity_state:' || p_assignment_id || ':' || v_uid));
  v_state := private.activity_state(p_assignment_id, v_uid);
  if v_state.id is null or v_state.active_attempt_id is distinct from p_attempt_id then
    return jsonb_build_object('released', true, 'already_released', true);
  end if;
  if v_state.state_kind <> 'teacher_activity' then
    perform private.fail('forbidden');
  end if;
  select * into v_row from public.assignment_attempts where id = p_attempt_id for update;
  if not found or v_row.trainee_id <> v_uid or v_row.assignment_id <> p_assignment_id
     or v_row.attempt_kind <> 'teacher_review_submission' or v_row.status <> 'in_progress'
     or v_row.activity_assessment_snapshot is null then
    perform private.fail('forbidden');
  end if;
  update public.assignment_attempts set status = 'draft', abandoned_at = now() where id = v_row.id;
  update public.assignment_attempt_states set
    consumed_count = case when active_consumed then greatest(consumed_count - 1, 0) else consumed_count end,
    active_attempt_id = null, active_request_id = null, active_consumed = null,
    updated_at = now()
  where id = v_state.id;
  return jsonb_build_object('released', true, 'already_released', false);
end;
$$;

-- Verifies the uploaded object (size/type recorded by Storage) and attaches
-- it to the reserved attempt.
create or replace function public.finalize_teacher_activity_attempt(
  p_assignment_id text, p_attempt_id text, p_video_storage_path text,
  p_video_content_type text, p_video_size_bytes int, p_video_duration_ms int
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_row public.assignment_attempts;
  v_state public.assignment_attempt_states;
  v_assignment public.group_assignments;
  v_path text;
  v_object_size bigint;
  v_object_type text;
begin
  if p_video_content_type <> 'video/mp4' or p_video_size_bytes not between 1 and 52428800
     or p_video_duration_ms not between 1 and 60000 then
    perform private.fail('invalid_payload');
  end if;
  select * into v_row from public.assignment_attempts where id = p_attempt_id for update;
  if not found or v_row.trainee_id <> v_uid or v_row.assignment_id <> p_assignment_id
     or v_row.attempt_kind <> 'teacher_review_submission'
     or v_row.activity_assessment_snapshot is null then
    perform private.fail('forbidden');
  end if;
  v_path := 'assignment_submissions/' || v_row.teacher_id || '/' || v_row.group_id || '/'
    || v_row.assignment_id || '/' || v_row.trainee_id || '/' || v_row.id || '.mp4';
  if p_video_storage_path <> v_path then
    perform private.fail('invalid_payload');
  end if;
  if v_row.status = 'in_progress' and v_row.video_storage_path is not null then
    if v_row.video_storage_path = v_path and v_row.video_size_bytes = p_video_size_bytes
       and v_row.video_duration_ms = p_video_duration_ms then
      return jsonb_build_object('attempt', private.attempt_json(v_row), 'reused', true);
    end if;
    perform private.fail('attempt_conflict');
  end if;
  select (o.metadata ->> 'size')::bigint, o.metadata ->> 'mimetype'
    into v_object_size, v_object_type
  from storage.objects o
  where o.bucket_id = 'assignment-submissions' and o.name = v_path;
  if not found then
    perform private.fail('upload_missing');
  end if;
  if v_object_type <> 'video/mp4' or v_object_size <> p_video_size_bytes then
    perform private.fail('upload_mismatch');
  end if;
  v_assignment := private.require_trainee_assignment(p_assignment_id, v_uid);
  if not private.valid_activity_assessment(v_assignment.activity_assessment, v_assignment.max_score) then
    perform private.fail('forbidden');
  end if;
  perform pg_advisory_xact_lock(hashtext('activity_state:' || p_assignment_id || ':' || v_uid));
  v_state := private.activity_state(p_assignment_id, v_uid);
  if v_row.status <> 'in_progress' or v_row.abandoned_at is not null
     or v_state.active_attempt_id is distinct from p_attempt_id
     or v_state.active_consumed is not true then
    perform private.fail('attempt_conflict');
  end if;
  if private.effective_due_at(v_assignment.id, v_uid) is not null
     and now() > private.effective_due_at(v_assignment.id, v_uid)
     and (v_row.recording_started_at is null
       or v_row.recording_started_at > private.effective_due_at(v_assignment.id, v_uid)) then
    perform private.fail('deadline_passed');
  end if;
  update public.assignment_attempts set video_storage_path = v_path,
    video_content_type = 'video/mp4', video_size_bytes = p_video_size_bytes,
    video_duration_ms = p_video_duration_ms, draft_saved_at = now()
  where id = v_row.id returning * into v_row;
  update public.assignment_attempt_states set active_attempt_id = null,
    active_request_id = null, active_consumed = null, updated_at = now()
  where id = v_state.id;
  return jsonb_build_object('attempt', private.attempt_json(v_row), 'reused', false);
end;
$$;

-- Selects exactly one completed attempt as the Teacher-facing submission.
-- For unlimited Activity policies the previously selected video is retired;
-- its storage path is returned so the client can remove the object.
create or replace function public.turn_in_assignment_attempt(
  p_assignment_id text, p_attempt_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_assignment public.group_assignments;
  v_row public.assignment_attempts;
  v_state public.assignment_attempt_states;
  v_is_official boolean;
  v_is_activity boolean;
  v_previous public.assignment_attempts;
  v_cleanup text;
begin
  select * into v_row from public.assignment_attempts where id = p_attempt_id for update;
  if not found then perform private.fail('not_found'); end if;
  v_assignment := private.require_trainee_assignment(p_assignment_id, v_uid);
  v_is_official := v_row.attempt_kind = 'practice_pointer' and v_row.origin = 'official_elixr'
    and v_row.rubric is not null;
  v_is_activity := v_row.attempt_kind = 'teacher_review_submission'
    and v_row.activity_assessment_snapshot is not null and v_row.video_storage_path is not null
    and v_row.draft_saved_at is not null;
  perform pg_advisory_xact_lock(hashtext('activity_state:' || p_assignment_id || ':' || v_uid));
  select * into v_state from public.assignment_attempt_states
    where id = p_assignment_id || '__' || v_uid for update;
  if v_row.trainee_id <> v_uid or v_row.assignment_id <> p_assignment_id
     or v_row.teacher_id <> v_assignment.teacher_id or v_row.group_id <> v_assignment.group_id
     or v_row.status <> 'in_progress' or not (v_is_official or v_is_activity)
     or coalesce(v_state.graded, false) or coalesce(v_assignment.grading_locked, false) then
    perform private.fail('forbidden');
  end if;
  if private.effective_due_at(v_assignment.id, v_uid) is not null
     and now() > private.effective_due_at(v_assignment.id, v_uid) then
    perform private.fail('deadline_passed');
  end if;
  update public.assignment_attempts set status = 'in_progress', submitted_at = null,
    video_expires_at = null
  where assignment_id = p_assignment_id and trainee_id = v_uid and id <> p_attempt_id
    and status = 'submitted' and attempt_kind in ('practice_pointer', 'teacher_review_submission');
  update public.assignment_attempts set status = 'submitted',
    submitted_at = case when v_is_activity then now() end,
    video_expires_at = case when v_is_activity then now() + interval '30 days' end
  where id = v_row.id returning * into v_row;
  if v_is_activity and v_state.id is not null
     and v_state.latest_submission_id is not null
     and v_state.latest_submission_id <> v_row.id
     and private.effective_attempt_policy(v_assignment) ->> 'type' = 'unlimited' then
    select * into v_previous from public.assignment_attempts
      where id = v_state.latest_submission_id for update;
    if v_previous.video_storage_path is not null then
      v_cleanup := v_previous.video_storage_path;
      update public.assignment_attempts set video_storage_path = null, video_deleted_at = now()
      where id = v_previous.id;
    end if;
  end if;
  if v_state.id is not null then
    update public.assignment_attempt_states set latest_submission_id = v_row.id,
      latest_submission_ordinal = coalesce(v_row.attempt_number, 0),
      active_attempt_id = case when active_attempt_id = v_row.id then null else active_attempt_id end,
      updated_at = now()
    where id = v_state.id;
  end if;
  return jsonb_build_object('attempt', private.attempt_json(v_row), 'cleanup_storage_path', v_cleanup);
end;
$$;

create or replace function public.grade_teacher_activity_attempt(
  p_attempt_id text, p_criterion_scores jsonb, p_feedback text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_row public.assignment_attempts;
  v_state public.assignment_attempt_states;
  v_criteria jsonb;
  v_criterion jsonb;
  v_total int := 0;
  v_feedback text := nullif(btrim(coalesce(p_feedback, '')), '');
begin
  if jsonb_typeof(p_criterion_scores) <> 'object'
     or (v_feedback is not null and char_length(v_feedback) > 1000) then
    perform private.fail('invalid_payload');
  end if;
  select * into v_row from public.assignment_attempts where id = p_attempt_id for update;
  if not found then perform private.fail('not_found'); end if;
  if v_row.teacher_id <> v_uid or v_row.status <> 'submitted'
     or v_row.activity_assessment_snapshot is null then
    perform private.fail('forbidden');
  end if;
  select * into v_state from public.assignment_attempt_states
    where id = v_row.assignment_id || '__' || v_row.trainee_id for update;
  if v_state.id is null or v_state.latest_submission_id is distinct from v_row.id
     or v_state.graded then
    perform private.fail('not_current');
  end if;
  v_criteria := v_row.activity_assessment_snapshot #> '{rubric,criteria}';
  if jsonb_typeof(v_criteria) <> 'array' then
    perform private.fail('invalid_snapshot');
  end if;
  if (select count(*) from jsonb_object_keys(p_criterion_scores)) <> jsonb_array_length(v_criteria) then
    perform private.fail('invalid_scores');
  end if;
  for v_criterion in select value from jsonb_array_elements(v_criteria) loop
    if not private.is_int_in(p_criterion_scores -> (v_criterion ->> 'id'), 0,
        (v_criterion ->> 'maximum_points')::int) then
      perform private.fail('invalid_scores');
    end if;
    v_total := v_total + (p_criterion_scores ->> (v_criterion ->> 'id'))::int;
  end loop;
  update public.assignment_attempts set status = 'checked', criterion_scores = p_criterion_scores,
    grade_score = v_total,
    grade_max_score = (v_row.activity_assessment_snapshot #>> '{rubric,maximum_score}')::int,
    checked_at = now(), review_updated_at = now(),
    review_revision = coalesce(review_revision, 0) + 1, review_feedback = v_feedback
  where id = v_row.id returning * into v_row;
  update public.assignment_attempt_states set graded = true, updated_at = now() where id = v_state.id;
  return jsonb_build_object('attempt', private.attempt_json(v_row));
end;
$$;

-- ---------------------------------------------------------------------------
-- Official ELIXR assignment session (former completeOfficialAssignmentSession)
-- ---------------------------------------------------------------------------

create or replace function public.complete_official_assignment_session(
  p_session_id text, p_session jsonb, p_feedbacks jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_ctx jsonb := p_session -> 'assignment_context';
  v_assignment public.group_assignments;
  v_state public.assignment_attempt_states;
  v_existing public.sessions;
  v_pointer public.assignment_attempts;
  v_consumed int;
  v_policy jsonb;
  v_session public.sessions;
  v_key text;
begin
  if not private.valid_doc_id(p_session_id) or v_ctx is null
     or (select array_agg(k order by k) from jsonb_object_keys(v_ctx) k)
       <> array['assignment_id', 'group_id', 'movement_id', 'revision_id', 'teacher_id']
     or jsonb_typeof(coalesce(p_feedbacks, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_feedbacks, '[]'::jsonb)) > 8 then
    perform private.fail('invalid_payload');
  end if;
  for v_key in select jsonb_object_keys(p_session) loop
    if v_key not in ('assessment_version', 'assignment_context', 'difficulty',
      'duration_seconds', 'evidence_kind', 'evidence_size_bytes',
      'evidence_storage_path', 'movement_name', 'performance_level', 'prop_type',
      'rubric', 'rubric_total') then
      perform private.fail('invalid_payload');
    end if;
  end loop;
  if coalesce((p_session ->> 'assessment_version')::int, 0) <> 2 then
    perform private.fail('invalid_payload');
  end if;
  v_assignment := private.require_trainee_assignment(v_ctx ->> 'assignment_id', v_uid);
  if v_assignment.origin <> 'official_elixr' or v_assignment.assessment_mode <> 'official_guided'
     or v_assignment.group_id <> v_ctx ->> 'group_id'
     or v_assignment.teacher_id::text <> v_ctx ->> 'teacher_id'
     or v_assignment.movement_id <> v_ctx ->> 'movement_id'
     or v_assignment.revision_id <> v_ctx ->> 'revision_id'
     or v_assignment.official_movement_name <> p_session ->> 'movement_name' then
    perform private.fail('forbidden');
  end if;
  select * into v_existing from public.sessions where id = p_session_id;
  select * into v_pointer from public.assignment_attempts where id = 'official_ptr_' || p_session_id;
  if v_existing.id is not null or v_pointer.id is not null then
    if v_existing.id is not null and v_pointer.id is not null and v_existing.user_id = v_uid
       and v_pointer.source_session_id = p_session_id and v_pointer.trainee_id = v_uid
       and v_pointer.assignment_id = v_assignment.id
       and v_existing.rubric = p_session -> 'rubric'
       and v_existing.assignment_context = v_ctx then
      return jsonb_build_object('reused', true);
    end if;
    perform private.fail('attempt_conflict');
  end if;
  if private.effective_due_at(v_assignment.id, v_uid) is not null
     and now() > private.effective_due_at(v_assignment.id, v_uid) then
    perform private.fail('deadline_passed');
  end if;
  perform pg_advisory_xact_lock(hashtext('activity_state:' || v_assignment.id || ':' || v_uid));
  select * into v_state from public.assignment_attempt_states
    where id = v_assignment.id || '__' || v_uid for update;
  if v_state.id is not null and v_state.state_kind <> 'official_assignment' then
    perform private.fail('attempt_conflict');
  end if;
  select greatest(coalesce(v_state.consumed_count, 0), count(*)) into v_consumed
  from public.assignment_attempts a
  where a.assignment_id = v_assignment.id and a.trainee_id = v_uid
    and a.attempt_kind = 'practice_pointer' and a.origin = 'official_elixr'
    and a.status in ('in_progress', 'submitted', 'checked');
  v_policy := private.effective_attempt_policy(v_assignment);
  if v_policy ->> 'type' = 'finite' and v_consumed >= (v_policy ->> 'maximum_attempts')::int then
    perform private.fail('attempts_exhausted');
  end if;
  v_session := private.insert_session(v_uid, p_session_id, p_session, p_feedbacks);
  insert into public.assignment_attempts (
    id, trainee_id, teacher_id, group_id, assignment_id, movement_id, revision_id,
    origin, assessment_mode, attempt_kind, status, source_session_id,
    assessment_version, rubric, rubric_total, performance_level,
    duration_seconds, prop_type, completed_at
  ) values (
    'official_ptr_' || p_session_id, v_uid, v_assignment.teacher_id, v_assignment.group_id,
    v_assignment.id, v_assignment.movement_id, v_assignment.revision_id,
    'official_elixr', 'official_guided', 'practice_pointer', 'in_progress', p_session_id,
    2, v_session.rubric, v_session.rubric_total, v_session.performance_level,
    v_session.duration_seconds, v_session.prop_type, now()
  );
  insert into public.assignment_attempt_states (
    id, state_kind, assignment_id, trainee_id, teacher_id, group_id, consumed_count
  ) values (
    v_assignment.id || '__' || v_uid, 'official_assignment', v_assignment.id, v_uid,
    v_assignment.teacher_id, v_assignment.group_id, v_consumed + 1
  ) on conflict (id) do update set consumed_count = excluded.consumed_count, updated_at = now();
  return jsonb_build_object('reused', false);
end;
$$;

-- ---------------------------------------------------------------------------
-- Class Challenges (former challenge Functions)
-- ---------------------------------------------------------------------------

create or replace function private.challenge_payload(p jsonb) returns jsonb
language plpgsql stable as $$
declare
  v_start timestamptz;
  v_deadline timestamptz;
begin
  begin
    v_start := (p ->> 'start_at')::timestamptz;
    v_deadline := (p ->> 'deadline')::timestamptz;
  exception when others then
    perform private.fail('invalid_payload');
  end;
  if not private.valid_doc_id(p ->> 'group_id') or not private.bounded_text(p ->> 'title', 80)
     or not private.bounded_text(p ->> 'description', 500)
     or not private.bounded_text(p ->> 'difficulty', 20)
     or not private.official_movement_supports_prop(p ->> 'movement_name', p ->> 'prop_type')
     or v_start is null or v_deadline is null or v_start >= v_deadline
     or (p ? 'attempt_limit' and jsonb_typeof(p -> 'attempt_limit') <> 'null'
       and not private.is_int_in(p -> 'attempt_limit', 1, 20))
     or (p ? 'target_score' and jsonb_typeof(p -> 'target_score') <> 'null'
       and not private.is_int_in(p -> 'target_score', 0, 12)) then
    perform private.fail('invalid_payload');
  end if;
  return jsonb_build_object(
    'group_id', p ->> 'group_id', 'title', btrim(p ->> 'title'),
    'description', btrim(p ->> 'description'), 'difficulty', btrim(p ->> 'difficulty'),
    'movement_name', p ->> 'movement_name', 'prop_type', p ->> 'prop_type',
    'start_at', v_start, 'deadline', v_deadline,
    'attempt_limit', nullif(p -> 'attempt_limit', 'null'::jsonb),
    'target_score', nullif(p -> 'target_score', 'null'::jsonb)
  );
end;
$$;

create or replace function public.create_class_challenge(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_payload jsonb := private.challenge_payload(p);
  v_group public.groups;
  v_row public.class_challenges;
begin
  select * into v_group from public.groups where id = v_payload ->> 'group_id';
  if not found or v_group.teacher_id <> v_uid or v_group.status <> 'active'
     or not private.bounded_text(private.caller_full_name(), 80) then
    perform private.fail('forbidden');
  end if;
  insert into public.class_challenges (
    id, group_id, teacher_id, teacher_display_name, title, description,
    movement_name, difficulty, prop_type, start_at, deadline, attempt_limit, target_score
  ) values (
    private.new_doc_id(), v_group.id, v_uid, private.caller_full_name(),
    v_payload ->> 'title', v_payload ->> 'description', v_payload ->> 'movement_name',
    v_payload ->> 'difficulty', v_payload ->> 'prop_type',
    (v_payload ->> 'start_at')::timestamptz, (v_payload ->> 'deadline')::timestamptz,
    (v_payload ->> 'attempt_limit')::int, (v_payload ->> 'target_score')::int
  ) returning * into v_row;
  return jsonb_build_object('challenge', jsonb_strip_nulls(to_jsonb(v_row)));
end;
$$;

create or replace function public.update_class_challenge(p_challenge_id text, p jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_payload jsonb := private.challenge_payload(p);
  v_row public.class_challenges;
begin
  select * into v_row from public.class_challenges where id = p_challenge_id for update;
  if not found then perform private.fail('not_found'); end if;
  if v_row.teacher_id <> v_uid or v_row.group_id <> v_payload ->> 'group_id'
     or v_row.archived_at is not null then
    perform private.fail('forbidden');
  end if;
  if exists (select 1 from public.class_challenge_participants where challenge_id = v_row.id)
     and (v_row.movement_name, v_row.difficulty, v_row.prop_type, v_row.start_at,
          v_row.deadline, v_row.attempt_limit)
       is distinct from (v_payload ->> 'movement_name', v_payload ->> 'difficulty',
          v_payload ->> 'prop_type', (v_payload ->> 'start_at')::timestamptz,
          (v_payload ->> 'deadline')::timestamptz, (v_payload ->> 'attempt_limit')::int) then
    perform private.fail('attempts_exist');
  end if;
  update public.class_challenges set title = v_payload ->> 'title',
    description = v_payload ->> 'description', movement_name = v_payload ->> 'movement_name',
    difficulty = v_payload ->> 'difficulty', prop_type = v_payload ->> 'prop_type',
    start_at = (v_payload ->> 'start_at')::timestamptz,
    deadline = (v_payload ->> 'deadline')::timestamptz,
    attempt_limit = (v_payload ->> 'attempt_limit')::int,
    target_score = (v_payload ->> 'target_score')::int, updated_at = now()
  where id = v_row.id returning * into v_row;
  return jsonb_build_object('challenge', jsonb_strip_nulls(to_jsonb(v_row)));
end;
$$;

create or replace function public.archive_class_challenge(p_challenge_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_row public.class_challenges;
begin
  select * into v_row from public.class_challenges where id = p_challenge_id for update;
  if not found then perform private.fail('not_found'); end if;
  if v_row.teacher_id <> v_uid then perform private.fail('forbidden'); end if;
  if v_row.archived_at is null then
    update public.class_challenges set archived_at = now(), updated_at = now() where id = v_row.id;
  end if;
end;
$$;

-- Deletes the challenge and its attempts/results; referenced sessions are
-- Trainee history and are retained.
create or replace function public.delete_class_challenge(p_challenge_id text, p_confirmation text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_row public.class_challenges;
begin
  if p_confirmation is distinct from 'DELETE CHALLENGE' then
    perform private.fail('invalid_confirmation');
  end if;
  select * into v_row from public.class_challenges where id = p_challenge_id for update;
  if not found then
    return jsonb_build_object('deleted', true, 'already_deleted', true);
  end if;
  if v_row.teacher_id <> v_uid then perform private.fail('forbidden'); end if;
  delete from public.class_challenges where id = v_row.id;
  return jsonb_build_object('deleted', true);
end;
$$;

create or replace function public.reserve_class_challenge_attempt(
  p_challenge_id text, p_request_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_trainee();
  v_challenge public.class_challenges;
  v_state public.class_challenge_participants;
  v_attempt public.class_challenge_attempts;
  v_ordinal int;
begin
  if not private.valid_doc_id(p_request_id) then perform private.fail('invalid_payload'); end if;
  select * into v_challenge from public.class_challenges where id = p_challenge_id;
  if not found or not private.is_approved_member(v_challenge.group_id, v_uid, v_challenge.teacher_id) then
    perform private.fail('forbidden');
  end if;
  if v_challenge.archived_at is not null or now() < v_challenge.start_at then
    perform private.fail('not_started');
  end if;
  if now() >= v_challenge.deadline then perform private.fail('deadline_passed'); end if;
  insert into public.class_challenge_participants (id, challenge_id, group_id, teacher_id, trainee_id)
  values (p_challenge_id || '__' || v_uid, p_challenge_id, v_challenge.group_id, v_challenge.teacher_id, v_uid)
  on conflict (id) do nothing;
  select * into v_state from public.class_challenge_participants
    where id = p_challenge_id || '__' || v_uid for update;
  if v_state.active_attempt_id is not null then
    if v_state.active_request_id = p_request_id then
      select * into v_attempt from public.class_challenge_attempts where id = v_state.active_attempt_id;
      return jsonb_build_object('attempt', jsonb_strip_nulls(to_jsonb(v_attempt)));
    end if;
    perform private.fail('attempt_in_progress');
  end if;
  if v_challenge.attempt_limit is not null and v_state.attempts_started >= v_challenge.attempt_limit then
    perform private.fail('attempts_exhausted');
  end if;
  v_ordinal := v_state.attempts_started + 1;
  insert into public.class_challenge_attempts (
    id, challenge_id, group_id, teacher_id, trainee_id, attempt_number, request_id,
    movement_name, prop_type, status
  ) values (
    'challenge_' || p_challenge_id || '_' || v_uid || '_' || v_ordinal, p_challenge_id,
    v_challenge.group_id, v_challenge.teacher_id, v_uid, v_ordinal, p_request_id,
    v_challenge.movement_name, v_challenge.prop_type, 'in_progress'
  ) returning * into v_attempt;
  update public.class_challenge_participants set attempts_started = v_ordinal,
    active_attempt_id = v_attempt.id, active_request_id = p_request_id, updated_at = now()
  where id = v_state.id;
  return jsonb_build_object('attempt', jsonb_strip_nulls(to_jsonb(v_attempt)));
end;
$$;

create or replace function public.abandon_class_challenge_attempt(
  p_challenge_id text, p_attempt_id text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_state public.class_challenge_participants;
  v_attempt public.class_challenge_attempts;
begin
  select * into v_state from public.class_challenge_participants
    where id = p_challenge_id || '__' || v_uid for update;
  if not found or v_state.active_attempt_id is distinct from p_attempt_id then
    return;
  end if;
  select * into v_attempt from public.class_challenge_attempts where id = p_attempt_id for update;
  if not found or v_attempt.trainee_id <> v_uid or v_attempt.challenge_id <> p_challenge_id
     or v_attempt.status <> 'in_progress' then
    perform private.fail('forbidden');
  end if;
  update public.class_challenge_attempts set status = 'abandoned', abandoned_at = now()
  where id = p_attempt_id;
  update public.class_challenge_participants set active_attempt_id = null,
    active_request_id = null, updated_at = now() where id = v_state.id;
end;
$$;

create or replace function public.complete_class_challenge_attempt(
  p_challenge_id text, p_attempt_id text, p_session_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_challenge public.class_challenges;
  v_state public.class_challenge_participants;
  v_attempt public.class_challenge_attempts;
  v_session public.sessions;
  v_best public.class_challenge_results;
  v_profile public.profiles;
begin
  select * into v_challenge from public.class_challenges where id = p_challenge_id for update;
  select * into v_state from public.class_challenge_participants
    where id = p_challenge_id || '__' || v_uid for update;
  select * into v_attempt from public.class_challenge_attempts where id = p_attempt_id for update;
  select * into v_session from public.sessions where id = p_session_id;
  select * into v_best from public.class_challenge_results where id = p_challenge_id || '__' || v_uid for update;
  if v_challenge.id is null or v_state.id is null or v_attempt.id is null or v_session.id is null then
    perform private.fail('forbidden');
  end if;
  -- Idempotent retry of an already-completed attempt.
  if v_best.id is not null and v_attempt.status = 'completed'
     and v_attempt.session_id = p_session_id and v_attempt.trainee_id = v_uid
     and v_session.user_id = v_uid then
    return jsonb_build_object('best_result', jsonb_strip_nulls(to_jsonb(v_best)));
  end if;
  if not private.is_approved_member(v_challenge.group_id, v_uid, v_challenge.teacher_id)
     or v_challenge.archived_at is not null or now() >= v_challenge.deadline
     or v_state.active_attempt_id is distinct from p_attempt_id
     or v_attempt.trainee_id <> v_uid or v_attempt.challenge_id <> p_challenge_id
     or v_attempt.status <> 'in_progress' or v_session.user_id <> v_uid
     or v_session.assessment_version <> 2 or v_session.rubric_total is null
     or v_session.movement_name <> v_challenge.movement_name
     or v_session.prop_type <> v_challenge.prop_type
     or v_session.challenge_context ->> 'challenge_id' is distinct from p_challenge_id
     or v_session.challenge_context ->> 'group_id' is distinct from v_challenge.group_id
     or v_session.challenge_context ->> 'teacher_id' is distinct from v_challenge.teacher_id::text
     or v_session.challenge_context ->> 'attempt_id' is distinct from p_attempt_id then
    perform private.fail('forbidden');
  end if;
  update public.class_challenge_attempts set status = 'completed', session_id = p_session_id,
    score = v_session.rubric_total, completed_at = now() where id = p_attempt_id;
  update public.class_challenge_participants set active_attempt_id = null,
    active_request_id = null, updated_at = now() where id = v_state.id;
  if v_best.id is null or v_session.rubric_total > v_best.score then
    select * into v_profile from public.profiles where id = v_uid;
    insert into public.class_challenge_results (
      id, challenge_id, group_id, teacher_id, trainee_id, display_name,
      profile_picture_url, score, best_attempt_number, best_achieved_at, session_id
    ) values (
      p_challenge_id || '__' || v_uid, p_challenge_id, v_challenge.group_id,
      v_challenge.teacher_id, v_uid, coalesce(left(v_profile.full_name, 80), 'Trainee'),
      v_profile.profile_picture_url, v_session.rubric_total, v_attempt.attempt_number,
      now(), p_session_id
    ) on conflict (id) do update set display_name = excluded.display_name,
      profile_picture_url = excluded.profile_picture_url, score = excluded.score,
      best_attempt_number = excluded.best_attempt_number,
      best_achieved_at = excluded.best_achieved_at, session_id = excluded.session_id,
      updated_at = now()
    returning * into v_best;
    update public.class_challenges set
      completed_count = completed_count + case when v_best.best_attempt_number = v_attempt.attempt_number
        and not exists (select 1 from public.class_challenge_attempts a
          where a.challenge_id = p_challenge_id and a.trainee_id = v_uid
            and a.status = 'completed' and a.id <> p_attempt_id) then 1 else 0 end,
      top_score = greatest(coalesce(top_score, 0), v_session.rubric_total), updated_at = now()
    where id = p_challenge_id;
  end if;
  return jsonb_build_object('best_result', jsonb_strip_nulls(to_jsonb(v_best)));
end;
$$;

-- ---------------------------------------------------------------------------
-- Activity learning materials
-- ---------------------------------------------------------------------------

create or replace function private.material_max_bytes(p_type text) returns bigint
language sql immutable as $$
  select case p_type
    when 'pdf' then 20 * 1024 * 1024
    when 'image' then 10 * 1024 * 1024
    when 'video' then 100 * 1024 * 1024
    else 0 end::bigint
$$;

create or replace function private.material_json(p_row public.learning_materials)
returns jsonb language sql stable as $$
  select jsonb_strip_nulls(jsonb_build_object(
    'material_id', p_row.id, 'assignment_id', p_row.assignment_id,
    'type', p_row.type, 'display_name', p_row.display_name,
    'detected_content_type', p_row.detected_content_type,
    'size_bytes', p_row.size_bytes, 'storage_path', p_row.storage_path,
    'external_url', p_row.external_url, 'published_at', p_row.published_at
  ))
$$;

create or replace function private.require_material_assignment(p_assignment_id text)
returns public.group_assignments language plpgsql security definer set search_path = '' as $$
declare
  v_row public.group_assignments;
begin
  perform private.require_verified_teacher();
  select * into v_row from public.group_assignments where id = p_assignment_id for update;
  if not found then perform private.fail('not_found'); end if;
  if v_row.teacher_id <> auth.uid() then perform private.fail('forbidden'); end if;
  if v_row.status not in ('draft', 'scheduled', 'active') or v_row.deletion_state = 'deleting' then
    perform private.fail('assignment_unavailable');
  end if;
  return v_row;
end;
$$;

create or replace function public.begin_activity_material_upload(
  p_assignment_id text, p_request_id text, p_type text, p_display_name text,
  p_declared_content_type text, p_size_bytes bigint
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_assignment public.group_assignments;
  v_type text := lower(btrim(coalesce(p_declared_content_type, '')));
  v_existing public.activity_material_uploads;
  v_material_id text := extensions.gen_random_uuid()::text;
  v_upload_id text := extensions.gen_random_uuid()::text;
  v_upload public.activity_material_uploads;
begin
  if not private.valid_doc_id(p_request_id) or p_type not in ('pdf', 'image', 'video')
     or not private.bounded_text(p_display_name, 120)
     or not ((p_type = 'pdf' and v_type = 'application/pdf')
       or (p_type = 'image' and v_type in ('image/jpeg', 'image/png'))
       or (p_type = 'video' and v_type = 'video/mp4'))
     or p_size_bytes is null or p_size_bytes < 1 or p_size_bytes > private.material_max_bytes(p_type) then
    perform private.fail('invalid_payload');
  end if;
  v_assignment := private.require_material_assignment(p_assignment_id);
  select * into v_existing from public.activity_material_uploads
    where assignment_id = v_assignment.id and request_id = p_request_id;
  if found then
    v_upload := v_existing;
  else
    if (select count(*) from public.learning_materials m
        where m.assignment_id = v_assignment.id and m.status not in ('rejected')) >= 10 then
      perform private.fail('material_limit');
    end if;
    insert into public.learning_materials (
      id, assignment_id, owner_teacher_id, type, display_name, status, request_id
    ) values (
      v_material_id, v_assignment.id, v_assignment.teacher_id, p_type, btrim(p_display_name),
      'staging', 'upload:' || p_request_id
    );
    insert into public.activity_material_uploads (
      upload_id, material_id, assignment_id, owner_teacher_id, type, display_name,
      declared_content_type, declared_size_bytes, staging_path, state, request_id, expires_at
    ) values (
      v_upload_id, v_material_id, v_assignment.id, v_assignment.teacher_id, p_type,
      btrim(p_display_name), v_type, p_size_bytes,
      'activity_material_staging/' || v_assignment.teacher_id || '/' || v_assignment.id || '/' || v_upload_id,
      'staging', p_request_id, now() + interval '15 minutes'
    ) returning * into v_upload;
  end if;
  return jsonb_build_object(
    'upload_id', v_upload.upload_id, 'material_id', v_upload.material_id,
    'staging_path', v_upload.staging_path,
    'declared_content_type', v_upload.declared_content_type,
    'expires_at', v_upload.expires_at
  );
end;
$$;

create or replace function public.get_activity_material_upload_status(p_upload_id text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_upload public.activity_material_uploads;
  v_material public.learning_materials;
  v_out jsonb;
begin
  select * into v_upload from public.activity_material_uploads where upload_id = p_upload_id;
  if not found then perform private.fail('not_found'); end if;
  if v_upload.owner_teacher_id <> v_uid then perform private.fail('forbidden'); end if;
  v_out := jsonb_build_object('upload_id', v_upload.upload_id,
    'material_id', v_upload.material_id, 'state', v_upload.state);
  if v_upload.state = 'rejected' then
    v_out := v_out || jsonb_build_object('rejection_reason',
      case when v_upload.rejection_reason in ('invalid_size', 'invalid_content', 'expired',
        'material_unavailable', 'upload_failed') then v_upload.rejection_reason
      else 'upload_failed' end);
  elsif v_upload.state = 'ready' then
    select * into v_material from public.learning_materials where id = v_upload.material_id;
    if not found or v_material.status <> 'ready' then
      v_out := v_out || jsonb_build_object('state', 'rejected', 'rejection_reason', 'material_unavailable');
    else
      v_out := v_out || jsonb_build_object('material', private.material_json(v_material));
    end if;
  elsif v_upload.state = 'staging' and v_upload.expires_at <= now() then
    v_out := v_out || jsonb_build_object('state', 'rejected', 'rejection_reason', 'expired');
  end if;
  return v_out;
end;
$$;

create or replace function public.add_activity_learning_material_link(
  p_assignment_id text, p_display_name text, p_url text, p_request_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_assignment public.group_assignments;
  v_url text := btrim(coalesce(p_url, ''));
  v_existing public.learning_materials;
  v_row public.learning_materials;
begin
  if not private.valid_doc_id(p_request_id) or not private.bounded_text(p_display_name, 120)
     or char_length(v_url) not between 1 and 2048
     or v_url !~* '^https?://[^/@:\s]+(:[0-9]+)?(/[^\s#]*)?(#.*)?$' then
    perform private.fail('invalid_payload');
  end if;
  v_url := split_part(v_url, '#', 1);
  v_assignment := private.require_material_assignment(p_assignment_id);
  select * into v_existing from public.learning_materials
    where assignment_id = v_assignment.id and request_id = 'link:' || p_request_id;
  if found then
    if v_existing.display_name <> btrim(p_display_name) or v_existing.external_url <> v_url then
      perform private.fail('invalid_payload');
    end if;
    return private.material_json(v_existing);
  end if;
  if (select count(*) from public.learning_materials m
      where m.assignment_id = v_assignment.id and m.status not in ('rejected')) >= 10 then
    perform private.fail('material_limit');
  end if;
  insert into public.learning_materials (
    id, assignment_id, owner_teacher_id, type, display_name, external_url, status,
    request_id, published_at
  ) values (
    extensions.gen_random_uuid()::text, v_assignment.id, v_assignment.teacher_id, 'link',
    btrim(p_display_name), v_url, 'ready', 'link:' || p_request_id, now()
  ) returning * into v_row;
  return private.material_json(v_row);
end;
$$;

create or replace function private.can_read_learning_material(
  p_assignment_id text, p_material_id text
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.learning_materials m
    join public.group_assignments a on a.id = m.assignment_id
    where m.id = p_material_id and m.assignment_id = p_assignment_id and m.status = 'ready'
      and coalesce(a.deletion_state, '') <> 'deleting'
      and (
        (a.teacher_id = auth.uid() and private.is_teacher())
        or (private.assignment_is_published(a.status, a.publish_at)
          and private.is_approved_member(a.group_id, auth.uid(), a.teacher_id)
          and private.assignment_audience_allows(a.id, a.audience_type, auth.uid()))
      )
  )
$$;

create or replace function public.list_activity_learning_materials(p_assignment_id text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.require_uid();
  if not exists (select 1 from public.group_assignments where id = p_assignment_id) then
    perform private.fail('not_found');
  end if;
  return jsonb_build_object('materials', coalesce((
    select jsonb_agg(private.material_json(m) order by m.created_at)
    from public.learning_materials m
    where m.assignment_id = p_assignment_id and m.status = 'ready'
      and private.can_read_learning_material(m.assignment_id, m.id)
  ), '[]'::jsonb));
end;
$$;

create or replace function public.list_trainee_activity_learning_materials()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_trainee();
begin
  return jsonb_build_object('materials', coalesce((
    select jsonb_agg(private.material_json(m) order by m.created_at)
    from public.learning_materials m
    join public.group_assignments a on a.id = m.assignment_id
    where m.status = 'ready'
      and private.assignment_is_published(a.status, a.publish_at)
      and coalesce(a.deletion_state, '') <> 'deleting'
      and private.is_approved_member(a.group_id, v_uid, a.teacher_id)
      and private.assignment_audience_allows(a.id, a.audience_type, v_uid)
  ), '[]'::jsonb));
end;
$$;

-- Marks a material as deleting (immediately revoking read access) and
-- returns the Storage objects the admin Edge Function must remove.
create or replace function public.request_activity_material_removal(
  p_assignment_id text, p_material_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_assignment public.group_assignments;
  v_material public.learning_materials;
begin
  select * into v_assignment from public.group_assignments where id = p_assignment_id;
  if not found or v_assignment.teacher_id <> v_uid then
    perform private.fail('forbidden');
  end if;
  select * into v_material from public.learning_materials
    where id = p_material_id and assignment_id = p_assignment_id for update;
  if not found then
    return jsonb_build_object('already_removed', true, 'paths', '[]'::jsonb);
  end if;
  update public.learning_materials set status = 'deleting', deletion_requested_at = now(),
    updated_at = now() where id = p_material_id;
  update public.activity_material_uploads set state = 'deleting', terminal_at = now()
    where material_id = p_material_id and state <> 'deleting';
  return jsonb_build_object('already_removed', false, 'paths', (
    select coalesce(jsonb_agg(p), '[]'::jsonb) from (
      select v_material.storage_path as p where v_material.storage_path is not null
      union select u.staging_path from public.activity_material_uploads u
        where u.material_id = p_material_id
    ) paths
  ));
end;
$$;

-- Service-role helpers used only by the admin Edge Function after it has
-- validated uploaded bytes / removed objects with Storage.
create or replace function public.admin_claim_material_upload(p_upload_id text, p_teacher_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_upload public.activity_material_uploads;
begin
  select * into v_upload from public.activity_material_uploads where upload_id = p_upload_id for update;
  if not found or v_upload.owner_teacher_id <> p_teacher_id then
    perform private.fail('forbidden');
  end if;
  if v_upload.state in ('ready', 'rejected', 'deleting') then
    return jsonb_build_object('state', v_upload.state);
  end if;
  if v_upload.expires_at <= now() then
    update public.activity_material_uploads set state = 'rejected', rejection_reason = 'expired',
      terminal_at = now() where upload_id = p_upload_id;
    update public.learning_materials set status = 'rejected', rejection_reason = 'expired',
      updated_at = now() where id = v_upload.material_id and status = 'staging';
    return jsonb_build_object('state', 'rejected', 'staging_path', v_upload.staging_path);
  end if;
  if v_upload.state = 'validating' and v_upload.validation_started_at > now() - interval '5 minutes' then
    return jsonb_build_object('state', 'validating');
  end if;
  update public.activity_material_uploads set state = 'validating', validation_started_at = now()
  where upload_id = p_upload_id;
  return jsonb_build_object('state', 'claimed', 'upload', to_jsonb(v_upload));
end;
$$;

create or replace function public.admin_complete_material_upload(
  p_upload_id text, p_accepted boolean, p_final_path text,
  p_detected_content_type text, p_size_bytes bigint, p_rejection_reason text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_upload public.activity_material_uploads;
begin
  select * into v_upload from public.activity_material_uploads where upload_id = p_upload_id for update;
  if not found or v_upload.state <> 'validating' then
    perform private.fail('conflict');
  end if;
  if p_accepted then
    update public.learning_materials set status = 'ready', storage_path = p_final_path,
      detected_content_type = p_detected_content_type, size_bytes = p_size_bytes,
      published_at = now(), updated_at = now()
    where id = v_upload.material_id and status = 'staging';
    if not found then
      perform private.fail('material_unavailable');
    end if;
    update public.activity_material_uploads set state = 'ready', terminal_at = now()
    where upload_id = p_upload_id;
  else
    update public.activity_material_uploads set state = 'rejected',
      rejection_reason = coalesce(p_rejection_reason, 'upload_failed'), terminal_at = now()
    where upload_id = p_upload_id;
    update public.learning_materials set status = 'rejected',
      rejection_reason = coalesce(p_rejection_reason, 'upload_failed'), updated_at = now()
    where id = v_upload.material_id and status = 'staging';
  end if;
end;
$$;

create or replace function public.admin_finish_material_removal(p_material_id text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.learning_materials where id = p_material_id and status = 'deleting';
end;
$$;

-- ---------------------------------------------------------------------------
-- Permanent deletion helpers for the admin Edge Function. They authorize the
-- supplied (JWT-verified) Teacher, delete rows, and return Storage prefixes.
-- ---------------------------------------------------------------------------

create or replace function private.assignment_storage_prefixes(p_row public.group_assignments)
returns text[] language sql immutable as $$
  select array[
    'assignment-submissions:assignment_submissions/' || p_row.teacher_id || '/' || p_row.group_id || '/' || p_row.id || '/',
    'teacher-activity-demos:teacher_activity_demos/' || p_row.teacher_id || '/assignments/' || p_row.id || '/',
    'activity-learning-materials:activity_material_staging/' || p_row.teacher_id || '/' || p_row.id || '/',
    'activity-learning-materials:activity_learning_materials/' || p_row.id || '/'
  ]
$$;

create or replace function public.admin_permanent_delete_assignment(
  p_teacher_id uuid, p_assignment_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_row public.group_assignments;
begin
  select * into v_row from public.group_assignments where id = p_assignment_id for update;
  if not found then
    return jsonb_build_object('deleted', true, 'already_deleted', true, 'prefixes', '[]'::jsonb);
  end if;
  if v_row.teacher_id <> p_teacher_id
     or private.profile_role(p_teacher_id) is distinct from 'Teacher' then
    perform private.fail('forbidden');
  end if;
  delete from public.group_assignments where id = p_assignment_id;
  return jsonb_build_object('deleted', true, 'prefixes', to_jsonb(private.assignment_storage_prefixes(v_row)));
end;
$$;

create or replace function public.admin_permanent_delete_classroom(
  p_teacher_id uuid, p_group_id text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_group public.groups;
  v_prefixes text[] := '{}';
  v_assignment public.group_assignments;
begin
  select * into v_group from public.groups where id = p_group_id for update;
  if not found then
    return jsonb_build_object('deleted', true, 'already_deleted', true, 'prefixes', '[]'::jsonb);
  end if;
  if v_group.teacher_id <> p_teacher_id
     or private.profile_role(p_teacher_id) is distinct from 'Teacher' then
    perform private.fail('forbidden');
  end if;
  for v_assignment in select * from public.group_assignments where group_id = p_group_id loop
    v_prefixes := v_prefixes || private.assignment_storage_prefixes(v_assignment);
  end loop;
  delete from public.groups where id = p_group_id;
  return jsonb_build_object('deleted', true, 'prefixes', to_jsonb(v_prefixes));
end;
$$;
