-- Personal Custom Movement practice: optional private completion evidence and
-- retry-safe persistence for one logical attempt.
--
-- The official evidence kind 'hold_confirmed' describes an official Guided
-- Practice hold. A custom movement may be dynamic, so its evidence is the
-- frame that confirmed completion: 'movement_completed', allowed only on a
-- custom-movement session. Path and size rules are unchanged.
alter table public.sessions drop constraint sessions_evidence_shape;
alter table public.sessions add constraint sessions_evidence_shape check (
  (evidence_storage_path is null and evidence_kind is null and evidence_size_bytes is null)
  or (evidence_storage_path = 'users/' || user_id || '/session_evidence/' || id || '.jpg'
    and evidence_size_bytes between 1024 and 262144
    and (
      (evidence_kind = 'hold_confirmed' and custom_movement_id is null)
      or (evidence_kind = 'movement_completed' and custom_movement_id is not null)
    ))
);

-- A distinct name (not an overload of save_custom_movement_result) keeps
-- PostgREST resolution deterministic. The earlier RPC remains for older
-- clients and still never writes evidence.
--
-- The evidence path is derived here from auth.uid() and the session id; the
-- client supplies only the uploaded object's size. Movement identity fields
-- are copied from the owned movement, never from the client.
create or replace function public.save_custom_movement_practice_result(
  p_session_id text, p_movement_id text, p_revision_id text,
  p_total_score double precision, p_component_scores jsonb, p_feedback jsonb,
  p_duration_seconds int, p_evidence_size_bytes int default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_existing public.sessions;
  v_movement public.custom_movements;
  v_revision public.custom_movement_revisions;
  v_evidence_path text;
  v_row public.sessions;
begin
  if not private.valid_doc_id(p_session_id)
     or p_total_score is null or p_total_score < 0 or p_total_score > 100
     or p_duration_seconds is null or p_duration_seconds not between 0 and 86400
     or jsonb_typeof(coalesce(p_component_scores, '{}'::jsonb)) <> 'object'
     or jsonb_typeof(coalesce(p_feedback, '[]'::jsonb)) <> 'array'
     or (p_evidence_size_bytes is not null
       and p_evidence_size_bytes not between 1024 and 262144) then
    perform private.fail('malformed');
  end if;

  select * into v_existing from public.sessions where id = p_session_id;
  if found then
    -- Retry of an already-committed save of the same logical attempt.
    if v_existing.user_id = v_uid
       and v_existing.custom_movement_id is not distinct from p_movement_id
       and exists (
         select 1 from public.custom_movement_results r
         where r.id = p_session_id and r.owner_uid = v_uid
           and r.movement_id = p_movement_id and r.revision_id = p_revision_id
       ) then
      return jsonb_build_object('reused', true);
    end if;
    perform private.fail('forbidden');
  end if;

  select * into v_movement from public.custom_movements where id = p_movement_id;
  select * into v_revision from public.custom_movement_revisions
  where id = p_revision_id and movement_id = p_movement_id;
  if v_movement.id is null or v_revision.id is null or v_movement.owner_uid <> v_uid
     or v_revision.owner_uid <> v_uid then
    perform private.fail('forbidden');
  end if;

  if p_evidence_size_bytes is not null then
    v_evidence_path := 'users/' || v_uid || '/session_evidence/' || p_session_id || '.jpg';
    -- Metadata may only reference an object that was actually uploaded.
    if not exists (
      select 1 from storage.objects o
      where o.bucket_id = 'session-evidence' and o.name = v_evidence_path
    ) then
      perform private.fail('evidence_missing');
    end if;
  end if;

  v_row := private.insert_session(v_uid, p_session_id, jsonb_build_object(
    'movement_name', v_movement.name,
    'difficulty', v_movement.difficulty,
    'duration_seconds', p_duration_seconds,
    'prop_type', v_movement.prop_type,
    -- The sessions partition stores a custom percentage in the 0..100 score
    -- column; clients identify it by custom_movement_id, never as legacy V1.
    'assessment_version', 1,
    'score', round(p_total_score)::int,
    'custom_movement_id', p_movement_id,
    'custom_movement_revision_id', p_revision_id,
    'reference_image_storage_path', v_movement.reference_image_storage_path,
    'evidence_storage_path', v_evidence_path,
    'evidence_kind', case when v_evidence_path is not null then 'movement_completed' end,
    'evidence_size_bytes', p_evidence_size_bytes
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
  return jsonb_build_object('reused', false, 'created_at', v_row.created_at);
end;
$$;

revoke execute on function public.save_custom_movement_practice_result(
  text, text, text, double precision, jsonb, jsonb, int, int
) from public, anon;
grant execute on function public.save_custom_movement_practice_result(
  text, text, text, double precision, jsonb, jsonb, int, int
) to authenticated;
