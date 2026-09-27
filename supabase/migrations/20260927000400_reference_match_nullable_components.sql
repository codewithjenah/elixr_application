-- Custom Movement scoring may leave a component "Not assessed" (JSON null) and
-- applies weighting/rotation that cannot be reconstructed from the five
-- component values. Accept null components and keep the backend-authoritative
-- total; only validate its range and performance-level consistency.
-- Authorization, deadline, attempt-slot locking, and insert are unchanged.
create or replace function public.save_reference_match_attempt(
  p_assignment_id text, p_total int, p_performance_level text, p_component_scores jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_assignment public.group_assignments := private.require_trainee_assignment(p_assignment_id, v_uid);
  v_policy jsonb;
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
     or exists (
       select 1 from jsonb_each(p_component_scores) e
       where jsonb_typeof(e.value) <> 'null' and not private.is_int_in(e.value, 0, 3)
     )
     or not exists (
       select 1 from jsonb_each(p_component_scores) e where jsonb_typeof(e.value) <> 'null'
     ) then
    perform private.fail('malformed');
  end if;
  if p_total is null or p_total < 0 or p_total > 12
     or p_performance_level is distinct from private.performance_level(p_total) then
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
