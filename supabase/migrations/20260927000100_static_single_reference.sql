-- A static hold (schema v3, movement_behavior = 'static') is learned from one
-- held reference. Dynamic schema v1/v2 templates still require two. This is
-- the 20260926000510 validator with only the reference_count bound changed.
create or replace function private.valid_movement_template(p_value jsonb)
returns boolean language plpgsql immutable as $$
declare
  v_keys text[];
  v_version int;
  v_trace jsonb;
  v_caps jsonb;
  v_cap_keys text[];
  v_total double precision;
begin
  if p_value is null or jsonb_typeof(p_value) <> 'object' then
    return false;
  end if;
  select array_agg(k) into v_keys from jsonb_object_keys(p_value) k;
  if not (v_keys <@ array['schema_version', 'capture_version', 'duration_ms',
      'reference_count', 'required_modalities', 'normalization_metadata',
      'feature_capabilities', 'canonical_sequence', 'variability_metadata',
      'prop_events', 'rotation_trace', 'movement_behavior'])
     or not (v_keys @> array['schema_version', 'capture_version', 'duration_ms',
      'reference_count', 'required_modalities', 'normalization_metadata',
      'feature_capabilities', 'canonical_sequence', 'variability_metadata',
      'prop_events']) then
    return false;
  end if;
  if not private.is_int_in(p_value -> 'schema_version', 1, 3) then
    return false;
  end if;
  v_version := (p_value ->> 'schema_version')::int;
  -- Schema v3 is only ever static (enforced below), so v3 may carry one
  -- reference while v1/v2 dynamic templates keep the two-reference minimum.
  if not private.is_int_in(p_value -> 'reference_count',
         case when v_version = 3 then 1 else 2 end, 10)
     or jsonb_typeof(p_value -> 'feature_capabilities') <> 'object'
     or jsonb_typeof(p_value -> 'canonical_sequence') <> 'array' then
    return false;
  end if;
  if jsonb_array_length(p_value -> 'canonical_sequence') not between 2 and 600 then
    return false;
  end if;
  if v_version = 1 then
    return not (p_value ? 'rotation_trace')
      and not (p_value ? 'movement_behavior')
      and (p_value #> '{feature_capabilities,prop_rotation}') = 'false'::jsonb;
  end if;
  if v_version = 2 then
    if p_value ? 'movement_behavior' then
      return false;
    end if;
  else
    -- V3 is the current client envelope; validate its data shapes at the
    -- database boundary without changing the legacy v1/v2 acceptance rules.
    v_caps := p_value -> 'feature_capabilities';
    select array_agg(k) into v_cap_keys from jsonb_object_keys(v_caps) k;
    if not private.is_int_in(p_value -> 'duration_ms', 1, 120000)
       or jsonb_typeof(p_value -> 'required_modalities') <> 'array'
       or jsonb_typeof(p_value -> 'normalization_metadata') <> 'object'
       or jsonb_typeof(p_value -> 'variability_metadata') <> 'object'
       or jsonb_typeof(p_value -> 'prop_events') <> 'array'
       or (v_cap_keys <@ array['pose', 'hands', 'prop_translation',
         'release_catch', 'prop_rotation', 'left_hand', 'right_hand']) is not true
       or (v_cap_keys @> array['pose', 'hands', 'prop_translation',
         'release_catch', 'prop_rotation']) is not true then
      return false;
    end if;
    if jsonb_array_length(p_value -> 'required_modalities') not between 1 and 3
       or jsonb_array_length(p_value -> 'prop_events') > 64
       or exists (select 1 from jsonb_each(v_caps) as capability(key, value)
         where jsonb_typeof(value) <> 'boolean')
       or (v_caps ? 'left_hand') <> (v_caps ? 'right_hand')
       or (v_caps -> 'hands' = 'true'::jsonb
         and v_caps ? 'left_hand'
         and v_caps -> 'left_hand' = 'false'::jsonb
         and v_caps -> 'right_hand' = 'false'::jsonb)
       or (v_caps -> 'hands' = 'false'::jsonb
         and (v_caps -> 'left_hand' = 'true'::jsonb
           or v_caps -> 'right_hand' = 'true'::jsonb)) then
      return false;
    end if;
    if exists (select 1 from jsonb_array_elements(p_value -> 'required_modalities') as modality(value)
         where jsonb_typeof(value) <> 'string'
           or value #>> '{}' not in ('pose', 'hands', 'prop_translation'))
       or (select count(distinct value) from jsonb_array_elements(p_value -> 'required_modalities')
           as modality(value)) <> jsonb_array_length(p_value -> 'required_modalities')
       or exists (select 1 from jsonb_array_elements(p_value -> 'canonical_sequence') as sample(value)
           where jsonb_typeof(value) <> 'object')
       or exists (select 1 from jsonb_array_elements(p_value -> 'prop_events') as prop_event(value)
           where jsonb_typeof(value) <> 'object') then
      return false;
    end if;
    if not (p_value ? 'movement_behavior')
       or not (p_value ? 'rotation_trace')
       or (p_value -> 'movement_behavior') is distinct from '"static"'::jsonb
       or not private.is_int_in(p_value -> 'capture_version', 1, 1)
       or jsonb_array_length(p_value -> 'canonical_sequence') <> 32 then
      return false;
    end if;
    v_trace := p_value -> 'rotation_trace';
    if (p_value #> '{feature_capabilities,prop_rotation}') = 'false'::jsonb then
      -- A present JSON null is distinct from an absent key and SQL NULL.
      return v_trace = 'null'::jsonb;
    end if;
  end if;
  v_trace := p_value -> 'rotation_trace';
  if not (p_value ? 'rotation_trace')
     or (p_value #> '{feature_capabilities,prop_rotation}') is distinct from 'true'::jsonb
     or jsonb_array_length(p_value -> 'canonical_sequence') <> 32
     or jsonb_typeof(v_trace) <> 'object' then
    return false;
  end if;
  if (select array_agg(k order by k) from jsonb_object_keys(v_trace) k)
       is distinct from array['angles_rad', 'coverage', 'pair_coverage', 'total_signed_rad']
     or jsonb_typeof(v_trace -> 'angles_rad') <> 'array' then
    return false;
  end if;
  if jsonb_array_length(v_trace -> 'angles_rad') <> 32
     or jsonb_typeof(v_trace -> 'total_signed_rad') <> 'number'
     or jsonb_typeof(v_trace -> 'coverage') <> 'number'
     or jsonb_typeof(v_trace -> 'pair_coverage') <> 'number' then
    return false;
  end if;
  if v_version = 3 then
    if (select count(*) from jsonb_array_elements(v_trace -> 'angles_rad') as angle(value)
        where value <> 'null'::jsonb) < 16
       or exists (
         select 1 from jsonb_array_elements(v_trace -> 'angles_rad') as angle(value)
         where case jsonb_typeof(value)
           when 'number' then abs((value #>> '{}')::numeric) > 126
           when 'null' then false
           else true
         end
       )
       or abs((v_trace ->> 'total_signed_rad')::numeric) > 126
       or not (p_value -> 'required_modalities' ? 'prop_translation') then
      return false;
    end if;
  end if;
  v_total := (v_trace ->> 'total_signed_rad')::double precision;
  return (v_total >= 4.084 or v_total <= -4.084)
    and (v_trace ->> 'coverage')::double precision between 0.8 and 1
    and (v_trace ->> 'pair_coverage')::double precision between 0.7 and 1;
end;
$$;
