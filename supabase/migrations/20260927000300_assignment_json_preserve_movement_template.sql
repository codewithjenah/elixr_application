-- Assignment RPC responses compact null columns with jsonb_strip_nulls, which
-- is recursive: it also removed the JSON null `rotation_trace` required by a
-- stored schema-v3 `movement_template`. Clients then rejected the template, so
-- create_custom_movement_assignment reported failure after a committed insert
-- and list_trainee_assignments dropped reference-matched assignments.
--
-- Top-level null columns are still compacted; only the stored template is
-- restored verbatim.
create or replace function private.assignment_json(p_row public.group_assignments)
returns jsonb language sql stable as $$
  select jsonb_strip_nulls(to_jsonb(p_row))
    || case when p_row.movement_template is null then '{}'::jsonb
            else jsonb_build_object('movement_template', p_row.movement_template) end
$$;
