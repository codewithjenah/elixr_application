-- ELIXR core schema: identity, practice sessions, gamification and public
-- profiles. Clients receive only row-level-secured reads; every mutation that
-- carries a security or integrity invariant is a SECURITY DEFINER RPC that
-- derives identity from auth.uid() and time from the database clock.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Error and identity helpers
-- ---------------------------------------------------------------------------

-- Raises a stable, presentation-safe error code. Clients map the message; the
-- SQLSTATE lets PostgREST choose a sensible HTTP status.
create or replace function private.fail(p_code text) returns void
language plpgsql as $$
begin
  raise exception using
    message = p_code,
    errcode = case p_code
      when 'unauthenticated' then '28000'
      when 'forbidden' then '42501'
      when 'not_found' then 'P0002'
      else 'P0001'
    end;
end;
$$;

create or replace function private.require_uid() returns uuid
language plpgsql stable as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    perform private.fail('unauthenticated');
  end if;
  return v_uid;
end;
$$;

create or replace function private.valid_doc_id(p_value text) returns boolean
language sql immutable as $$
  select p_value is not null and p_value ~ '^[A-Za-z0-9_-]{1,128}$'
$$;

create or replace function private.is_coach_code(p_value text) returns boolean
language sql immutable as $$
  select p_value is not null
    and p_value ~ '^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{12}$'
$$;

create or replace function private.bounded_text(p_value text, p_max int)
returns boolean language sql immutable as $$
  select p_value is not null
    and char_length(btrim(p_value)) between 1 and p_max
    and p_value ~ '\S'
$$;

-- Opaque 20-character identifier, the same shape as the former Firestore
-- document IDs so existing path/ID validators continue to apply.
create or replace function private.new_doc_id() returns text
language plpgsql volatile as $$
declare
  v_alphabet constant text :=
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  v_bytes bytea := extensions.gen_random_bytes(20);
  v_result text := '';
begin
  for i in 0..19 loop
    v_result := v_result || substr(v_alphabet, (get_byte(v_bytes, i) % 62) + 1, 1);
  end loop;
  return v_result;
end;
$$;

create or replace function private.generate_coach_code() returns text
language plpgsql volatile as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_bytes bytea := extensions.gen_random_bytes(12);
  v_result text := '';
begin
  for i in 0..11 loop
    v_result := v_result || substr(v_alphabet, (get_byte(v_bytes, i) % 32) + 1, 1);
  end loop;
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Manila calendar helpers. All "what day is it" decisions use the database
-- clock (now()), never a client-supplied day key.
-- ---------------------------------------------------------------------------

create or replace function private.manila_day_key(p_at timestamptz) returns text
language sql stable as $$
  select to_char(p_at at time zone 'Asia/Manila', 'YYYYMMDD')
$$;

create or replace function private.manila_month_key(p_at timestamptz) returns text
language sql stable as $$
  select to_char(p_at at time zone 'Asia/Manila', 'YYYYMM')
$$;

create or replace function private.manila_day_start(p_at timestamptz)
returns timestamptz language sql stable as $$
  select date_trunc('day', p_at at time zone 'Asia/Manila') at time zone 'Asia/Manila'
$$;

create or replace function private.is_day_key(p_value text) returns boolean
language sql immutable as $$
  select p_value is not null
    and p_value ~ '^[0-9]{4}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])$'
$$;

-- ---------------------------------------------------------------------------
-- Catalogs mirrored from the Dart/Python sources (contract-tested there).
-- ---------------------------------------------------------------------------

create or replace function private.official_movement_props(p_name text)
returns text[] language sql immutable as $$
  select case p_name
    when 'Normal Grip' then array['bottle']
    when 'Bartender''s Grip' then array['bottle']
    when 'Reverse Grip' then array['bottle']
    when 'Claw Grip' then array['bottle']
    when 'Body Grip' then array['bottle']
    when 'Hand Stall' then array['bottle', 'shaker']
    when 'One Finger Stall' then array['bottle', 'shaker']
    when 'Forearm Stall' then array['bottle', 'shaker']
    when 'Elbow Stall' then array['bottle', 'shaker']
    when 'Wrist Stall' then array['bottle', 'shaker']
    when 'Reverse Forearm Stall' then array['bottle']
    when 'Shoulder Stall' then array['bottle']
    when 'Double Hand Stall' then array['bottle']
    when 'Bottle in a tin' then array['bottle_and_shaker']
    when 'Double Forearm Stall' then array['bottle']
    else null
  end
$$;

create or replace function private.is_official_movement(p_name text)
returns boolean language sql immutable as $$
  select private.official_movement_props(p_name) is not null
$$;

create or replace function private.official_movement_supports_prop(
  p_name text, p_prop text
) returns boolean language sql immutable as $$
  select coalesce(p_prop = any (private.official_movement_props(p_name)), false)
$$;

create or replace function private.official_movement_id(p_name text)
returns text language sql immutable as $$
  select case p_name
    when 'Normal Grip' then 'official_normal_grip'
    when 'Bartender''s Grip' then 'official_bartenders_grip'
    when 'Reverse Grip' then 'official_reverse_grip'
    when 'Claw Grip' then 'official_claw_grip'
    when 'Body Grip' then 'official_body_grip'
    when 'Hand Stall' then 'official_hand_stall'
    when 'One Finger Stall' then 'official_one_finger_stall'
    when 'Forearm Stall' then 'official_forearm_stall'
    when 'Elbow Stall' then 'official_elbow_stall'
    when 'Wrist Stall' then 'official_wrist_stall'
    when 'Reverse Forearm Stall' then 'official_reverse_forearm_stall'
    when 'Shoulder Stall' then 'official_shoulder_stall'
    when 'Double Hand Stall' then 'official_double_hand_stall'
    when 'Bottle in a tin' then 'official_bottle_in_a_tin'
    when 'Double Forearm Stall' then 'official_double_forearm_stall'
    else null
  end
$$;

-- Authoritative rubric thresholds: 0-3 / 4-6 / 7-9 / 10-11 / 12.
create or replace function private.performance_level(p_total int)
returns text language sql immutable as $$
  select case
    when p_total <= 3 then 'beginning'
    when p_total <= 6 then 'developing'
    when p_total <= 9 then 'competent'
    when p_total <= 11 then 'proficient'
    else 'mastered'
  end
$$;

create or replace function private.is_int_in(p_value jsonb, p_min int, p_max int)
returns boolean language sql immutable as $$
  select p_value is not null
    and jsonb_typeof(p_value) = 'number'
    and (p_value #>> '{}') ~ '^-?[0-9]+$'
    and (p_value #>> '{}')::int between p_min and p_max
$$;

create or replace function private.valid_rubric(p_rubric jsonb)
returns boolean language sql immutable as $$
  select p_rubric is not null
    and jsonb_typeof(p_rubric) = 'object'
    and (select array_agg(k order by k) from jsonb_object_keys(p_rubric) k)
      = array['completion', 'prop_positioning', 'stability', 'technique']
    and private.is_int_in(p_rubric -> 'technique', 0, 3)
    and private.is_int_in(p_rubric -> 'stability', 0, 3)
    and private.is_int_in(p_rubric -> 'completion', 0, 3)
    and private.is_int_in(p_rubric -> 'prop_positioning', 0, 3)
$$;

create or replace function private.rubric_sum(p_rubric jsonb)
returns int language sql immutable as $$
  select (p_rubric ->> 'technique')::int + (p_rubric ->> 'stability')::int
    + (p_rubric ->> 'completion')::int + (p_rubric ->> 'prop_positioning')::int
$$;

create or replace function private.achievement_reward_border(p_achievement text)
returns text language sql immutable as $$
  select case p_achievement
    when 'first_steps' then 'starter_glow'
    when 'getting_started' then 'bronze_ember'
    when 'flair_regular' then 'violet_flow'
    when 'century_club' then 'gold_mastery'
    when 'sharp_pour' then 'cyan_orbit'
    when 'perfect_serve' then 'perfect_serve'
    when 'movement_explorer' then 'prismatic_arc'
    when 'versatility_master' then 'triad_frame'
    when 'week_warrior' then 'week_warrior'
    when 'bottle_in_tin_specialist' then 'tin_specialist'
    else null
  end
$$;

create or replace function private.is_known_border(p_border text)
returns boolean language sql immutable as $$
  select p_border in (
    'starter_glow', 'bronze_ember', 'violet_flow', 'gold_mastery', 'cyan_orbit',
    'perfect_serve', 'prismatic_arc', 'triad_frame', 'week_warrior',
    'tin_specialist'
  )
$$;

-- Daily quest catalog: [xp, kind, target]. Mirrors lib/data/models/daily_quest.dart.
create or replace function private.quest_definition(p_quest text)
returns jsonb language sql immutable as $$
  select case p_quest
    when 'session_count_1' then '[10, "count", 1]'
    when 'duration_10min' then '[10, "duration", 600]'
    when 'score_70' then '[10, "best", 7]'
    when 'two_movements' then '[10, "movements", 2]'
    when 'practice_easy_movement' then '[10, "difficulty", "easy"]'
    when 'use_shaker' then '[10, "prop", "shaker"]'
    when 'session_count_3' then '[15, "count", 3]'
    when 'duration_20min' then '[15, "duration", 1200]'
    when 'score_85' then '[15, "best", 10]'
    when 'sessions_above_70_x2' then '[15, "above", 2]'
    when 'three_movements' then '[15, "movements", 3]'
    when 'practice_medium_movement' then '[15, "difficulty", "medium"]'
    when 'distinct_props_2' then '[15, "props", 2]'
    when 'session_count_5' then '[20, "count", 5]'
    when 'duration_30min' then '[20, "duration", 1800]'
    when 'score_95' then '[20, "best", 12]'
    when 'practice_hard_movement' then '[20, "difficulty", "hard"]'
    when 'use_bottle_and_shaker_combo' then '[20, "prop", "bottle_and_shaker"]'
    else null
  end::jsonb
$$;

-- ---------------------------------------------------------------------------
-- Profiles (former users/{uid}) and Teacher access codes
-- ---------------------------------------------------------------------------

create or replace function private.valid_profile_name(p_value text)
returns boolean language sql immutable as $$
  select p_value is not null
    and char_length(p_value) between 1 and 80
    and p_value ~ '^\S(.*\S)?$'
$$;

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  first_name text not null check (private.valid_profile_name(first_name)),
  middle_name text check (middle_name is null or private.valid_profile_name(middle_name)),
  last_name text not null check (private.valid_profile_name(last_name)),
  full_name text not null check (private.valid_profile_name(full_name)),
  email text not null,
  role text not null check (role in ('Trainee', 'Teacher')),
  teacher_access_code text,
  created_at timestamptz not null default now(),
  privacy_consent_at timestamptz,
  privacy_policy_version text,
  terms_consent_at timestamptz,
  terms_of_service_version text,
  profile_picture_url text check (
    profile_picture_url is null
    or (char_length(profile_picture_url) <= 2048 and profile_picture_url ~ '^https://')
  ),
  profile_picture_storage_path text,
  profile_picture_path text,
  profile_border_id text check (
    profile_border_id is null or private.is_known_border(profile_border_id)
  ),
  session_evidence_enabled boolean,
  session_evidence_policy_version text,
  session_evidence_decision_at timestamptz,
  teacher_roster_invite_code text,
  lifecycle_state text not null default 'active'
    check (lifecycle_state in ('active', 'deleting')),
  constraint profiles_full_name_composition check (
    full_name = first_name || ' '
      || coalesce(middle_name || ' ', '') || last_name
  ),
  constraint profiles_teacher_code check (
    (role = 'Teacher') = (teacher_access_code is not null)
  ),
  constraint profiles_border_teacher_only check (
    profile_border_id is null or role = 'Teacher'
  )
);

create table public.teacher_access_codes (
  code text primary key check (private.is_coach_code(code)),
  consumed boolean not null default false,
  consumed_by uuid references auth.users (id) on delete set null,
  consumed_at timestamptz,
  created_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  note text check (note is null or char_length(note) <= 200),
  constraint teacher_access_codes_consumption check (
    consumed = (consumed_at is not null)
  )
);
create index teacher_access_codes_created_by_idx on public.teacher_access_codes (created_by);
create index teacher_access_codes_consumed_by_idx on public.teacher_access_codes (consumed_by);

-- A consumed code is permanently bound to its Teacher profile.
alter table public.profiles
  add constraint profiles_teacher_access_code_fk
  foreign key (teacher_access_code) references public.teacher_access_codes (code);
create unique index profiles_teacher_access_code_key
  on public.profiles (teacher_access_code) where teacher_access_code is not null;

create or replace function private.email_verified(p_uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from auth.users u
    where u.id = p_uid and u.email_confirmed_at is not null
  )
$$;

create or replace function private.profile_role(p_uid uuid) returns text
language sql stable security definer set search_path = '' as $$
  select p.role from public.profiles p
  where p.id = p_uid and p.lifecycle_state = 'active'
$$;

-- Replaces the former Firebase custom claim: the role column is writable only
-- by the access-code consuming registration functions below.
create or replace function private.is_teacher() returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.profile_role(auth.uid()) = 'Teacher', false)
$$;

create or replace function private.is_verified_teacher() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_teacher() and private.email_verified(auth.uid())
$$;

create or replace function private.is_trainee(p_uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(private.profile_role(p_uid) = 'Trainee', false)
$$;

create or replace function private.is_product_participant(p_uid uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(private.profile_role(p_uid) in ('Trainee', 'Teacher'), false)
$$;

create or replace function private.require_verified_teacher() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
begin
  if not private.is_verified_teacher() then
    perform private.fail('forbidden');
  end if;
  return v_uid;
end;
$$;

create or replace function private.require_trainee() returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
begin
  if not private.is_trainee(v_uid) then
    perform private.fail('forbidden');
  end if;
  return v_uid;
end;
$$;

-- Creates the caller's profile. Teacher creation atomically consumes a
-- single-use access code (row lock prevents double consumption).
create or replace function private.create_profile(
  p_uid uuid,
  p_email text,
  p_role text,
  p_first_name text,
  p_middle_name text,
  p_last_name text,
  p_teacher_access_code text,
  p_privacy_policy_version text,
  p_terms_of_service_version text
) returns public.profiles
language plpgsql security definer set search_path = '' as $$
declare
  v_first text := btrim(p_first_name);
  v_middle text := nullif(btrim(coalesce(p_middle_name, '')), '');
  v_last text := btrim(p_last_name);
  v_code public.teacher_access_codes;
  v_profile public.profiles;
begin
  if p_role not in ('Trainee', 'Teacher') then
    perform private.fail('invalid_role');
  end if;
  if p_privacy_policy_version is distinct from 'v6'
     or p_terms_of_service_version is distinct from 'v3' then
    perform private.fail('consent_required');
  end if;
  if exists (select 1 from public.profiles where id = p_uid) then
    perform private.fail('profile_exists');
  end if;
  if p_role = 'Teacher' then
    if not private.is_coach_code(p_teacher_access_code) then
      perform private.fail('malformed_code');
    end if;
    select * into v_code from public.teacher_access_codes
      where code = p_teacher_access_code for update;
    if not found then
      perform private.fail('access_code_not_found');
    end if;
    if v_code.consumed then
      perform private.fail('access_code_consumed');
    end if;
    update public.teacher_access_codes
      set consumed = true, consumed_by = p_uid, consumed_at = now()
      where code = p_teacher_access_code;
  elsif p_teacher_access_code is not null and btrim(p_teacher_access_code) <> '' then
    perform private.fail('invalid_role');
  end if;

  insert into public.profiles (
    id, first_name, middle_name, last_name, full_name, email, role,
    teacher_access_code, created_at, privacy_consent_at,
    privacy_policy_version, terms_consent_at, terms_of_service_version
  ) values (
    p_uid, v_first, v_middle, v_last,
    v_first || ' ' || coalesce(v_middle || ' ', '') || v_last,
    btrim(p_email), p_role,
    case when p_role = 'Teacher' then p_teacher_access_code end,
    now(), now(), p_privacy_policy_version, now(), p_terms_of_service_version
  ) returning * into v_profile;

  -- New accounts start with a public profile root (repair paths create
  -- private roots). This used to be a client seed after registration.
  insert into public.public_profiles (user_id, display_name, role, visibility)
  values (p_uid, v_profile.full_name, v_profile.role, 'public')
  on conflict (user_id) do nothing;
  return v_profile;
end;
$$;

-- ---------------------------------------------------------------------------
-- Practice sessions and feedback
-- ---------------------------------------------------------------------------

create table public.sessions (
  id text primary key check (private.valid_doc_id(id)),
  user_id uuid not null references auth.users (id) on delete cascade,
  movement_name text not null check (char_length(movement_name) between 1 and 80),
  difficulty text not null check (difficulty in ('Easy', 'Medium', 'Hard')),
  duration_seconds int not null check (duration_seconds between 0 and 86400),
  prop_type text not null check (prop_type in ('bottle', 'shaker', 'bottle_and_shaker')),
  created_at timestamptz not null default now(),
  assessment_version int not null check (assessment_version in (1, 2)),
  score int check (score between 0 and 100),
  rubric jsonb,
  rubric_total int check (rubric_total between 0 and 12),
  performance_level text,
  evidence_storage_path text,
  evidence_kind text,
  evidence_size_bytes int,
  assignment_context jsonb,
  challenge_context jsonb,
  custom_movement_id text,
  custom_movement_revision_id text,
  reference_image_storage_path text,
  constraint sessions_assessment_partition check (
    (assessment_version = 2 and score is null and private.valid_rubric(rubric)
      and rubric_total = private.rubric_sum(rubric)
      and performance_level = private.performance_level(rubric_total))
    or (assessment_version = 1 and score is not null and rubric is null
      and rubric_total is null and performance_level is null)
  ),
  constraint sessions_evidence_shape check (
    (evidence_storage_path is null and evidence_kind is null and evidence_size_bytes is null)
    or (evidence_storage_path = 'users/' || user_id || '/session_evidence/' || id || '.jpg'
      and evidence_kind = 'hold_confirmed'
      and evidence_size_bytes between 1024 and 262144)
  )
);
create index sessions_user_created_idx on public.sessions (user_id, created_at desc);

create table public.feedbacks (
  id text primary key check (char_length(id) between 1 and 200),
  session_id text not null references public.sessions (id) on delete cascade,
  message text not null check (char_length(message) between 1 and 1000),
  feedback_type text not null check (char_length(feedback_type) between 1 and 40),
  created_at timestamptz not null default now()
);
create index feedbacks_session_created_idx on public.feedbacks (session_id, created_at);

-- ---------------------------------------------------------------------------
-- Leaderboard, awards and gamification
-- ---------------------------------------------------------------------------

create table public.leaderboard (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  profile_picture_url text check (
    profile_picture_url is null
    or (char_length(profile_picture_url) <= 2048 and profile_picture_url ~ '^https://')
  ),
  total_xp int not null default 0 check (total_xp >= 0),
  quest_xp int not null default 0 check (quest_xp >= 0),
  sessions_completed int not null default 0 check (sessions_completed >= 0),
  score_sum double precision not null default 0 check (score_sum >= 0),
  average_score double precision not null default 0 check (average_score between 0 and 100),
  best_score int not null default 0 check (best_score between 0 and 100),
  last_session_at timestamptz,
  last_active_at timestamptz,
  updated_at timestamptz not null default now(),
  last_awarded_session_id text,
  last_claim_id text,
  equipped_border_id text not null default ''
    check (equipped_border_id = '' or private.is_known_border(equipped_border_id)),
  daily_key text,
  daily_xp int not null default 0 check (daily_xp >= 0),
  daily_sessions_completed int not null default 0 check (daily_sessions_completed >= 0),
  daily_score_sum double precision not null default 0,
  daily_average_score double precision not null default 0,
  daily_best_score int not null default 0,
  monthly_key text,
  monthly_xp int not null default 0 check (monthly_xp >= 0),
  monthly_sessions_completed int not null default 0 check (monthly_sessions_completed >= 0),
  monthly_score_sum double precision not null default 0,
  monthly_average_score double precision not null default 0,
  monthly_best_score int not null default 0,
  constraint leaderboard_xp_integrity check (total_xp = sessions_completed * 25 + quest_xp)
);
create index leaderboard_all_time_idx on public.leaderboard (total_xp desc, best_score desc, user_id);
create index leaderboard_daily_idx on public.leaderboard (daily_key, daily_xp desc, daily_best_score desc, user_id);
create index leaderboard_monthly_idx on public.leaderboard (monthly_key, monthly_xp desc, monthly_best_score desc, user_id);

-- Duplicate-award marker: one row per awarded session, never updated.
create table public.leaderboard_processed_sessions (
  session_id text primary key references public.sessions (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  score int check (score between 0 and 100),
  rubric_total int check (rubric_total between 0 and 12),
  xp_awarded int not null check (xp_awarded = 25),
  processed_at timestamptz not null default now(),
  check ((score is null) <> (rubric_total is null))
);
create index leaderboard_processed_sessions_user_idx
  on public.leaderboard_processed_sessions (user_id);

create table public.daily_quest_boards (
  id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  day_key text not null check (private.is_day_key(day_key)),
  day_start timestamptz not null,
  quest_ids text[] not null check (cardinality(quest_ids) = 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, day_key),
  check (id = user_id || '_' || day_key)
);

create table public.daily_quest_claims (
  id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  board_id text not null references public.daily_quest_boards (id) on delete cascade,
  day_key text not null,
  day_start timestamptz not null,
  quest_id text not null,
  xp_awarded int not null check (xp_awarded in (10, 15, 20)),
  claimed_at timestamptz not null default now(),
  unique (user_id, day_key, quest_id),
  check (id = user_id || '_' || day_key || '_' || quest_id)
);
create index daily_quest_claims_user_board_idx on public.daily_quest_claims (user_id, board_id);

create table public.achievement_claims (
  id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  achievement_id text not null
    check (private.achievement_reward_border(achievement_id) is not null),
  reward_border_id text not null,
  claimed_at timestamptz not null default now(),
  unique (user_id, achievement_id),
  check (id = user_id || '_' || achievement_id),
  check (reward_border_id = private.achievement_reward_border(achievement_id))
);

create table public.user_cosmetics (
  user_id uuid primary key references auth.users (id) on delete cascade,
  unlocked_border_ids text[] not null default '{}',
  last_achievement_claim_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Sanitized public profile projections and visitors
-- ---------------------------------------------------------------------------

create table public.public_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 80),
  profile_picture_url text check (
    profile_picture_url is null
    or (char_length(profile_picture_url) <= 2048 and profile_picture_url ~ '^https://')
  ),
  role text check (role is null or role in ('Trainee', 'Teacher')),
  visibility text not null default 'private' check (visibility in ('public', 'private')),
  schema_version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.public_profile_summaries (
  user_id uuid primary key references public.public_profiles (user_id) on delete cascade,
  total_duration_seconds int not null default 0 check (total_duration_seconds >= 0),
  completed_movement_names text[] not null default '{}',
  last_backfill_session_id text,
  updated_at timestamptz not null default now()
);

create table public.public_profile_sessions (
  session_id text primary key references public.sessions (id) on delete cascade,
  user_id uuid not null references public.public_profiles (user_id) on delete cascade,
  movement_name text not null,
  difficulty text not null,
  duration_seconds int not null check (duration_seconds >= 0),
  prop_type text not null,
  created_at timestamptz not null,
  assessment_version int,
  score int,
  rubric jsonb,
  rubric_total int,
  performance_level text,
  evidence_available boolean
);
create index public_profile_sessions_user_created_idx
  on public.public_profile_sessions (user_id, created_at desc, session_id desc);

create table public.public_profile_achievements (
  user_id uuid not null references public.public_profiles (user_id) on delete cascade,
  achievement_id text not null
    check (private.achievement_reward_border(achievement_id) is not null),
  claimed_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, achievement_id)
);

create table public.profile_visits (
  profile_owner_id uuid not null references auth.users (id) on delete cascade,
  viewer_id uuid not null references auth.users (id) on delete cascade,
  first_viewed_at timestamptz not null default now(),
  last_viewed_at timestamptz not null default now(),
  primary key (profile_owner_id, viewer_id),
  check (profile_owner_id <> viewer_id)
);
create index profile_visits_owner_recent_idx
  on public.profile_visits (profile_owner_id, last_viewed_at desc);
create index profile_visits_viewer_idx on public.profile_visits (viewer_id);

create table public.training_plans (
  id text primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  day_key text not null check (private.is_day_key(day_key)),
  plan_type text not null check (plan_type in ('rest', 'training')),
  movement_name text,
  difficulty text,
  prop_type text,
  target_duration_minutes int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, day_key),
  check (id = user_id || '_' || day_key),
  check (
    (plan_type = 'rest' and movement_name is null and difficulty is null
      and prop_type is null and target_duration_minutes is null)
    or (plan_type = 'training'
      and private.is_official_movement(movement_name)
      and difficulty in ('Easy', 'Medium', 'Hard')
      and prop_type in ('bottle', 'shaker', 'bottle_and_shaker')
      and target_duration_minutes in (5, 10, 15, 20, 30))
  )
);

-- ---------------------------------------------------------------------------
-- Read policies
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.teacher_access_codes enable row level security;
alter table public.sessions enable row level security;
alter table public.feedbacks enable row level security;
alter table public.leaderboard enable row level security;
alter table public.leaderboard_processed_sessions enable row level security;
alter table public.daily_quest_boards enable row level security;
alter table public.daily_quest_claims enable row level security;
alter table public.achievement_claims enable row level security;
alter table public.user_cosmetics enable row level security;
alter table public.public_profiles enable row level security;
alter table public.public_profile_summaries enable row level security;
alter table public.public_profile_sessions enable row level security;
alter table public.public_profile_achievements enable row level security;
alter table public.profile_visits enable row level security;
alter table public.training_plans enable row level security;

create policy profiles_select_own on public.profiles
  for select to authenticated using (id = auth.uid());

create policy teacher_access_codes_select_participant on public.teacher_access_codes
  for select to authenticated
  using (
    (created_by = auth.uid() and private.is_teacher())
    or consumed_by = auth.uid()
  );
create policy teacher_access_codes_delete_unused on public.teacher_access_codes
  for delete to authenticated
  using (created_by = auth.uid() and not consumed and private.is_teacher());

create policy sessions_select_own on public.sessions
  for select to authenticated using (user_id = auth.uid());

create policy feedbacks_select_own on public.feedbacks
  for select to authenticated
  using (exists (
    select 1 from public.sessions s
    where s.id = feedbacks.session_id and s.user_id = auth.uid()
  ));

create policy leaderboard_select_signed_in on public.leaderboard
  for select to authenticated using (true);

create policy leaderboard_markers_select_own on public.leaderboard_processed_sessions
  for select to authenticated using (user_id = auth.uid());

create policy daily_quest_boards_select_own on public.daily_quest_boards
  for select to authenticated using (user_id = auth.uid());
create policy daily_quest_claims_select_own on public.daily_quest_claims
  for select to authenticated using (user_id = auth.uid());
create policy achievement_claims_select_own on public.achievement_claims
  for select to authenticated using (user_id = auth.uid());
create policy user_cosmetics_select_own on public.user_cosmetics
  for select to authenticated using (user_id = auth.uid());

-- Public profile roots are readable by any signed-in user. Summary/session
-- detail policies depend on classroom authorization and are created in the
-- classroom migration.
create policy public_profiles_select_signed_in on public.public_profiles
  for select to authenticated using (true);

create policy public_profile_achievements_select on public.public_profile_achievements
  for select to authenticated
  using (
    user_id = auth.uid()
    or (
      private.is_product_participant(auth.uid())
      and exists (
        select 1 from public.public_profiles pp
        where pp.user_id = public_profile_achievements.user_id
          and pp.visibility = 'public'
      )
    )
  );

create policy profile_visits_select_participant on public.profile_visits
  for select to authenticated
  using (profile_owner_id = auth.uid() or viewer_id = auth.uid());

create policy training_plans_select_own on public.training_plans
  for select to authenticated using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Profile RPCs
-- ---------------------------------------------------------------------------

create or replace function public.check_teacher_access_code(p_code text)
returns void language plpgsql stable security definer set search_path = '' as $$
declare
  v_consumed boolean;
begin
  if not private.is_coach_code(p_code) then
    perform private.fail('malformed_code');
  end if;
  select consumed into v_consumed from public.teacher_access_codes where code = p_code;
  if not found then
    perform private.fail('access_code_not_found');
  end if;
  if v_consumed then
    perform private.fail('access_code_consumed');
  end if;
end;
$$;

create or replace function public.create_own_profile(
  p_role text,
  p_first_name text,
  p_middle_name text,
  p_last_name text,
  p_privacy_policy_version text,
  p_terms_of_service_version text,
  p_teacher_access_code text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_email text;
  v_profile public.profiles;
begin
  select email into v_email from auth.users where id = v_uid;
  if v_email is null or btrim(v_email) = '' then
    perform private.fail('email_required');
  end if;
  v_profile := private.create_profile(
    v_uid, v_email, p_role, p_first_name, p_middle_name, p_last_name,
    p_teacher_access_code, p_privacy_policy_version, p_terms_of_service_version
  );
  return jsonb_strip_nulls(to_jsonb(v_profile) - 'lifecycle_state');
end;
$$;

-- Email/password registration: the profile is created in the same
-- transaction as the auth user from sign-up metadata. Metadata is only the
-- requested input; the access code is validated and consumed here, so a
-- forged or reused code aborts the sign-up.
create or replace function private.handle_new_auth_user() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  if coalesce(v_meta ->> 'elixr_registration', '') <> 'v1' then
    return new; -- OAuth identities complete onboarding explicitly.
  end if;
  perform private.create_profile(
    new.id,
    new.email,
    v_meta ->> 'role',
    v_meta ->> 'first_name',
    v_meta ->> 'middle_name',
    v_meta ->> 'last_name',
    v_meta ->> 'teacher_access_code',
    v_meta ->> 'privacy_policy_version',
    v_meta ->> 'terms_of_service_version'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_auth_user();

-- Allow-listed owner profile edits. Null removes an optional field.
create or replace function public.update_own_profile(p_fields jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_profile public.profiles;
  v_key text;
  v_auth_email text;
  v_first text;
  v_middle text;
  v_last text;
begin
  select * into v_profile from public.profiles where id = v_uid for update;
  if not found then
    perform private.fail('not_found');
  end if;
  for v_key in select jsonb_object_keys(p_fields) loop
    if v_key not in (
      'first_name', 'middle_name', 'last_name', 'full_name', 'email',
      'profile_picture_url', 'profile_picture_storage_path',
      'profile_picture_path', 'session_evidence_enabled', 'profile_border_id'
    ) then
      perform private.fail('invalid_field');
    end if;
  end loop;

  if p_fields ? 'first_name' or p_fields ? 'middle_name' or p_fields ? 'last_name' then
    v_first := btrim(coalesce(p_fields ->> 'first_name', v_profile.first_name));
    v_last := btrim(coalesce(p_fields ->> 'last_name', v_profile.last_name));
    v_middle := case when p_fields ? 'middle_name'
      then nullif(btrim(coalesce(p_fields ->> 'middle_name', '')), '')
      else v_profile.middle_name end;
    v_profile.first_name := v_first;
    v_profile.middle_name := v_middle;
    v_profile.last_name := v_last;
    v_profile.full_name := v_first || ' ' || coalesce(v_middle || ' ', '') || v_last;
  end if;

  if p_fields ? 'email' then
    select email into v_auth_email from auth.users where id = v_uid;
    if lower(btrim(p_fields ->> 'email')) is distinct from lower(btrim(v_auth_email)) then
      perform private.fail('forbidden');
    end if;
    v_profile.email := btrim(v_auth_email);
  end if;

  if p_fields ? 'profile_picture_url' then
    v_profile.profile_picture_url := p_fields ->> 'profile_picture_url';
  end if;
  if p_fields ? 'profile_picture_storage_path' then
    v_profile.profile_picture_storage_path := p_fields ->> 'profile_picture_storage_path';
    if v_profile.profile_picture_storage_path is not null
       and v_profile.profile_picture_storage_path
         not like 'users/' || v_uid || '/profile/%' then
      perform private.fail('forbidden');
    end if;
  end if;
  if p_fields ? 'profile_picture_path' then
    v_profile.profile_picture_path := p_fields ->> 'profile_picture_path';
  end if;

  if p_fields ? 'session_evidence_enabled' then
    if jsonb_typeof(p_fields -> 'session_evidence_enabled') <> 'boolean' then
      perform private.fail('invalid_field');
    end if;
    v_profile.session_evidence_enabled := (p_fields ->> 'session_evidence_enabled')::boolean;
    v_profile.session_evidence_policy_version := 'v1';
    v_profile.session_evidence_decision_at := now();
  end if;

  if p_fields ? 'profile_border_id' then
    if v_profile.role <> 'Teacher' then
      perform private.fail('forbidden');
    end if;
    v_profile.profile_border_id := nullif(btrim(coalesce(p_fields ->> 'profile_border_id', '')), '');
  end if;

  update public.profiles set
    first_name = v_profile.first_name,
    middle_name = v_profile.middle_name,
    last_name = v_profile.last_name,
    full_name = v_profile.full_name,
    email = v_profile.email,
    profile_picture_url = v_profile.profile_picture_url,
    profile_picture_storage_path = v_profile.profile_picture_storage_path,
    profile_picture_path = v_profile.profile_picture_path,
    session_evidence_enabled = v_profile.session_evidence_enabled,
    session_evidence_policy_version = v_profile.session_evidence_policy_version,
    session_evidence_decision_at = v_profile.session_evidence_decision_at,
    profile_border_id = v_profile.profile_border_id
  where id = v_uid
  returning * into v_profile;
  return jsonb_strip_nulls(to_jsonb(v_profile) - 'lifecycle_state');
end;
$$;

-- Server-side replacement for the former Teacher custom-claim handshake.
create or replace function public.assert_teacher_authorized()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_profile public.profiles;
  v_code public.teacher_access_codes;
begin
  select * into v_profile from public.profiles where id = v_uid;
  if not found or v_profile.role <> 'Teacher' or v_profile.lifecycle_state <> 'active' then
    perform private.fail('teacher_evidence_invalid');
  end if;
  select * into v_code from public.teacher_access_codes where code = v_profile.teacher_access_code;
  if not found or not v_code.consumed or v_code.consumed_by is distinct from v_uid then
    perform private.fail('teacher_evidence_invalid');
  end if;
  return jsonb_build_object('teacher_role', true, 'email_verified', private.email_verified(v_uid));
end;
$$;

create or replace function public.mint_teacher_access_code(p_note text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_verified_teacher();
  v_note text := nullif(btrim(coalesce(p_note, '')), '');
  v_row public.teacher_access_codes;
begin
  if v_note is not null and char_length(v_note) > 200 then
    perform private.fail('invalid_note');
  end if;
  for i in 1..8 loop
    begin
      insert into public.teacher_access_codes (code, created_by, note)
      values (private.generate_coach_code(), v_uid, v_note)
      returning * into v_row;
      return jsonb_strip_nulls(to_jsonb(v_row));
    exception when unique_violation then
      continue;
    end;
  end loop;
  perform private.fail('collision_exhausted');
  return null;
end;
$$;

-- ---------------------------------------------------------------------------
-- Session persistence
-- ---------------------------------------------------------------------------

-- Validates and inserts a session row owned by p_uid. Shared by the plain
-- save, the official-assignment and custom-movement paths.
create or replace function private.insert_session(
  p_uid uuid, p_session_id text, p_session jsonb, p_feedbacks jsonb
) returns public.sessions
language plpgsql security definer set search_path = '' as $$
declare
  v_row public.sessions;
  v_feedback jsonb;
  v_index int := 0;
begin
  if not private.valid_doc_id(p_session_id) then
    perform private.fail('invalid_payload');
  end if;
  if jsonb_typeof(coalesce(p_feedbacks, '[]'::jsonb)) <> 'array'
     or jsonb_array_length(coalesce(p_feedbacks, '[]'::jsonb)) > 32 then
    perform private.fail('invalid_payload');
  end if;
  insert into public.sessions (
    id, user_id, movement_name, difficulty, duration_seconds, prop_type,
    created_at, assessment_version, score, rubric, rubric_total,
    performance_level, evidence_storage_path, evidence_kind,
    evidence_size_bytes, assignment_context, challenge_context,
    custom_movement_id, custom_movement_revision_id,
    reference_image_storage_path
  ) values (
    p_session_id, p_uid,
    p_session ->> 'movement_name',
    p_session ->> 'difficulty',
    (p_session ->> 'duration_seconds')::int,
    p_session ->> 'prop_type',
    now(),
    coalesce((p_session ->> 'assessment_version')::int, 1),
    (p_session ->> 'score')::int,
    p_session -> 'rubric',
    (p_session ->> 'rubric_total')::int,
    p_session ->> 'performance_level',
    p_session ->> 'evidence_storage_path',
    p_session ->> 'evidence_kind',
    (p_session ->> 'evidence_size_bytes')::int,
    p_session -> 'assignment_context',
    p_session -> 'challenge_context',
    p_session ->> 'custom_movement_id',
    p_session ->> 'custom_movement_revision_id',
    p_session ->> 'reference_image_storage_path'
  ) returning * into v_row;

  for v_feedback in select value from jsonb_array_elements(coalesce(p_feedbacks, '[]'::jsonb)) loop
    insert into public.feedbacks (id, session_id, message, feedback_type)
    values (
      coalesce(v_feedback ->> 'id', p_session_id || '_fb_' || v_index),
      p_session_id,
      v_feedback ->> 'message',
      v_feedback ->> 'feedback_type'
    );
    v_index := v_index + 1;
  end loop;
  return v_row;
end;
$$;

-- Plain official Guided Practice or Class Challenge session save. Assignment
-- sessions must use complete_official_assignment_session.
create or replace function public.save_session(
  p_session_id text, p_session jsonb, p_feedbacks jsonb default '[]'::jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_existing public.sessions;
  v_row public.sessions;
  v_ctx jsonb := p_session -> 'challenge_context';
  v_challenge record;
  v_attempt record;
begin
  select * into v_existing from public.sessions where id = p_session_id;
  if found then
    -- Retry of an already-committed save.
    if v_existing.user_id = v_uid then
      return jsonb_build_object('reused', true);
    end if;
    perform private.fail('forbidden');
  end if;
  if p_session ? 'assignment_context' then
    perform private.fail('assignment_requires_server_completion');
  end if;
  if p_session ? 'custom_movement_id' or p_session ? 'custom_movement_revision_id' then
    perform private.fail('invalid_payload');
  end if;
  if coalesce((p_session ->> 'assessment_version')::int, 1) <> 2
     or not private.is_official_movement(p_session ->> 'movement_name') then
    perform private.fail('invalid_payload');
  end if;
  if v_ctx is null then
    if not private.official_movement_supports_prop(
      p_session ->> 'movement_name', p_session ->> 'prop_type'
    ) then
      perform private.fail('invalid_payload');
    end if;
  else
    if (select array_agg(k order by k) from jsonb_object_keys(v_ctx) k)
       <> array['attempt_id', 'challenge_id', 'group_id', 'teacher_id'] then
      perform private.fail('invalid_payload');
    end if;
    select * into v_challenge from public.class_challenges c
      where c.id = v_ctx ->> 'challenge_id';
    select * into v_attempt from public.class_challenge_attempts a
      where a.id = v_ctx ->> 'attempt_id';
    if v_challenge.id is null or v_attempt.id is null
       or v_challenge.group_id <> v_ctx ->> 'group_id'
       or v_challenge.teacher_id::text <> v_ctx ->> 'teacher_id'
       or v_challenge.archived_at is not null
       or v_challenge.start_at > now() or v_challenge.deadline <= now()
       or v_challenge.movement_name <> p_session ->> 'movement_name'
       or v_challenge.prop_type <> p_session ->> 'prop_type'
       or v_attempt.challenge_id <> v_challenge.id
       or v_attempt.trainee_id <> v_uid
       or v_attempt.status <> 'in_progress'
       or not private.is_approved_member(v_challenge.group_id, v_uid, v_challenge.teacher_id) then
      perform private.fail('forbidden');
    end if;
  end if;
  v_row := private.insert_session(v_uid, p_session_id, p_session, p_feedbacks);
  return jsonb_build_object('reused', false, 'created_at', v_row.created_at);
end;
$$;

-- Privacy revocation may remove evidence metadata; it may never attach or
-- replace a reference.
create or replace function public.clear_session_evidence_metadata()
returns int language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_count int;
begin
  update public.sessions set
    evidence_storage_path = null, evidence_kind = null, evidence_size_bytes = null
  where user_id = v_uid and evidence_storage_path is not null;
  get diagnostics v_count = row_count;
  update public.public_profile_sessions set evidence_available = null
  where user_id = v_uid and evidence_available is not null;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- Leaderboard awards (idempotent) and presence
-- ---------------------------------------------------------------------------

create or replace function public.award_session_xp(
  p_session_id text, p_display_name text, p_profile_picture_url text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_session public.sessions;
  v_board public.leaderboard;
  v_score int;
  v_is_rubric boolean;
  v_name text := coalesce(nullif(btrim(coalesce(p_display_name, '')), ''), 'Trainee');
  v_picture text := nullif(btrim(coalesce(p_profile_picture_url, '')), '');
  v_day text;
  v_month text;
begin
  select * into v_session from public.sessions where id = p_session_id;
  if not found then
    perform private.fail('session_not_found');
  end if;
  if v_session.user_id <> v_uid then
    perform private.fail('forbidden');
  end if;
  if not private.is_official_movement(v_session.movement_name)
     or v_session.challenge_context is not null
     or v_session.custom_movement_id is not null then
    perform private.fail('not_awardable');
  end if;
  -- Lock ordering: marker insert decides idempotency atomically.
  v_is_rubric := v_session.assessment_version = 2;
  v_score := case when v_is_rubric then null else v_session.score end;
  begin
    insert into public.leaderboard_processed_sessions (
      session_id, user_id, score, rubric_total, xp_awarded
    ) values (
      p_session_id, v_uid, v_score,
      case when v_is_rubric then v_session.rubric_total end, 25
    );
  exception when unique_violation then
    return jsonb_build_object('status', 'already_processed');
  end;

  v_day := private.manila_day_key(v_session.created_at);
  v_month := private.manila_month_key(v_session.created_at);

  insert into public.leaderboard (user_id, display_name)
  values (v_uid, left(v_name, 80))
  on conflict (user_id) do nothing;
  select * into v_board from public.leaderboard where user_id = v_uid for update;

  v_board.sessions_completed := v_board.sessions_completed + 1;
  v_board.total_xp := v_board.total_xp + 25;
  if v_score is not null then
    v_board.score_sum := v_board.score_sum + v_score;
    v_board.average_score := v_board.score_sum / v_board.sessions_completed;
    v_board.best_score := greatest(v_board.best_score, v_score);
  end if;

  -- Daily aggregate: older events never roll a newer period back.
  if v_board.daily_key is null or v_day > v_board.daily_key then
    v_board.daily_key := v_day;
    v_board.daily_xp := 25;
    v_board.daily_sessions_completed := 1;
    v_board.daily_score_sum := coalesce(v_score, 0);
    v_board.daily_average_score := coalesce(v_score, 0);
    v_board.daily_best_score := coalesce(v_score, 0);
  elsif v_day = v_board.daily_key then
    v_board.daily_xp := v_board.daily_xp + 25;
    v_board.daily_sessions_completed := v_board.daily_sessions_completed + 1;
    if v_score is not null then
      v_board.daily_score_sum := v_board.daily_score_sum + v_score;
      v_board.daily_average_score := v_board.daily_score_sum / v_board.daily_sessions_completed;
      v_board.daily_best_score := greatest(v_board.daily_best_score, v_score);
    end if;
  end if;
  if v_board.monthly_key is null or v_month > v_board.monthly_key then
    v_board.monthly_key := v_month;
    v_board.monthly_xp := 25;
    v_board.monthly_sessions_completed := 1;
    v_board.monthly_score_sum := coalesce(v_score, 0);
    v_board.monthly_average_score := coalesce(v_score, 0);
    v_board.monthly_best_score := coalesce(v_score, 0);
  elsif v_month = v_board.monthly_key then
    v_board.monthly_xp := v_board.monthly_xp + 25;
    v_board.monthly_sessions_completed := v_board.monthly_sessions_completed + 1;
    if v_score is not null then
      v_board.monthly_score_sum := v_board.monthly_score_sum + v_score;
      v_board.monthly_average_score := v_board.monthly_score_sum / v_board.monthly_sessions_completed;
      v_board.monthly_best_score := greatest(v_board.monthly_best_score, v_score);
    end if;
  end if;

  update public.leaderboard set
    display_name = left(v_name, 80),
    profile_picture_url = coalesce(v_picture, profile_picture_url),
    total_xp = v_board.total_xp,
    sessions_completed = v_board.sessions_completed,
    score_sum = v_board.score_sum,
    average_score = v_board.average_score,
    best_score = v_board.best_score,
    last_session_at = v_session.created_at,
    last_awarded_session_id = p_session_id,
    updated_at = now(),
    daily_key = v_board.daily_key,
    daily_xp = v_board.daily_xp,
    daily_sessions_completed = v_board.daily_sessions_completed,
    daily_score_sum = v_board.daily_score_sum,
    daily_average_score = v_board.daily_average_score,
    daily_best_score = v_board.daily_best_score,
    monthly_key = v_board.monthly_key,
    monthly_xp = v_board.monthly_xp,
    monthly_sessions_completed = v_board.monthly_sessions_completed,
    monthly_score_sum = v_board.monthly_score_sum,
    monthly_average_score = v_board.monthly_average_score,
    monthly_best_score = v_board.monthly_best_score
  where user_id = v_uid;
  return jsonb_build_object('status', 'awarded', 'xp_awarded', 25);
end;
$$;

-- Presence only: at most one write per ten minutes, never creates a row.
create or replace function public.touch_leaderboard_presence()
returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_count int;
begin
  update public.leaderboard set last_active_at = now()
  where user_id = v_uid
    and (last_active_at is null or last_active_at <= now() - interval '10 minutes');
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

create or replace function public.sync_leaderboard_public_profile(
  p_display_name text, p_profile_picture_url text, p_clear_picture boolean
) returns boolean language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_name text := nullif(btrim(coalesce(p_display_name, '')), '');
  v_picture text := nullif(btrim(coalesce(p_profile_picture_url, '')), '');
  v_count int;
begin
  if v_name is null then
    return false;
  end if;
  update public.leaderboard set
    display_name = left(v_name, 80),
    profile_picture_url = case
      when p_clear_picture then null
      when v_picture is not null then v_picture
      else profile_picture_url end,
    updated_at = now()
  where user_id = v_uid
    and (
      display_name is distinct from left(v_name, 80)
      or (p_clear_picture and profile_picture_url is not null)
      or (not p_clear_picture and v_picture is not null
        and profile_picture_url is distinct from v_picture)
    );
  get diagnostics v_count = row_count;
  return v_count > 0;
end;
$$;

-- Deterministic rank with the shared ordering: period XP, best score, UID.
create or replace function public.leaderboard_rank(
  p_user_id uuid, p_period text default 'allTime'
) returns int language plpgsql stable security definer set search_path = '' as $$
declare
  v_row public.leaderboard;
  v_key text;
  v_xp int;
  v_best int;
  v_rank int;
begin
  perform private.require_uid();
  select * into v_row from public.leaderboard where user_id = p_user_id;
  if not found then
    return null;
  end if;
  if p_period = 'today' then
    v_key := private.manila_day_key(now());
    if v_row.daily_key is distinct from v_key then return null; end if;
    select 1 + count(*) into v_rank from public.leaderboard l
    where l.daily_key = v_key and (
      l.daily_xp > v_row.daily_xp
      or (l.daily_xp = v_row.daily_xp and l.daily_best_score > v_row.daily_best_score)
      or (l.daily_xp = v_row.daily_xp and l.daily_best_score = v_row.daily_best_score
        and l.user_id::text < p_user_id::text));
  elsif p_period = 'thisMonth' then
    v_key := private.manila_month_key(now());
    if v_row.monthly_key is distinct from v_key then return null; end if;
    select 1 + count(*) into v_rank from public.leaderboard l
    where l.monthly_key = v_key and (
      l.monthly_xp > v_row.monthly_xp
      or (l.monthly_xp = v_row.monthly_xp and l.monthly_best_score > v_row.monthly_best_score)
      or (l.monthly_xp = v_row.monthly_xp and l.monthly_best_score = v_row.monthly_best_score
        and l.user_id::text < p_user_id::text));
  else
    v_xp := v_row.total_xp;
    v_best := v_row.best_score;
    select 1 + count(*) into v_rank from public.leaderboard l
    where l.total_xp > v_xp
      or (l.total_xp = v_xp and l.best_score > v_best)
      or (l.total_xp = v_xp and l.best_score = v_best and l.user_id::text < p_user_id::text);
  end if;
  return v_rank;
end;
$$;

-- ---------------------------------------------------------------------------
-- Daily quests (Manila day from the server clock)
-- ---------------------------------------------------------------------------

create or replace function public.get_or_create_daily_quest_board(p_quest_ids text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_day text := private.manila_day_key(now());
  v_board public.daily_quest_boards;
  v_xp int[];
begin
  select * into v_board from public.daily_quest_boards
    where user_id = v_uid and day_key = v_day;
  if found then
    return to_jsonb(v_board);
  end if;
  if cardinality(p_quest_ids) <> 5
     or (select count(distinct q) from unnest(p_quest_ids) q) <> 5 then
    perform private.fail('invalid_board');
  end if;
  select array_agg((private.quest_definition(q) ->> 0)::int) into v_xp
    from unnest(p_quest_ids) q;
  if array_position(v_xp, null) is not null
     or (select count(*) from unnest(v_xp) x where x = 10) <> 2
     or (select count(*) from unnest(v_xp) x where x = 15) <> 2
     or (select count(*) from unnest(v_xp) x where x = 20) <> 1
     or (select count(*) from unnest(p_quest_ids) q
         where private.quest_definition(q) ->> 1 = 'count') > 1
     or (select count(*) from unnest(p_quest_ids) q
         where private.quest_definition(q) ->> 1 = 'duration') > 1
     or (select count(*) from unnest(p_quest_ids) q
         where q in ('score_70', 'score_85', 'score_95')) > 1 then
    perform private.fail('invalid_board');
  end if;
  insert into public.daily_quest_boards (id, user_id, day_key, day_start, quest_ids)
  values (v_uid || '_' || v_day, v_uid, v_day, private.manila_day_start(now()), p_quest_ids)
  on conflict (user_id, day_key) do nothing;
  select * into v_board from public.daily_quest_boards
    where user_id = v_uid and day_key = v_day;
  return to_jsonb(v_board);
end;
$$;

-- Trusted claim: evaluates today's persisted sessions server-side.
create or replace function public.claim_daily_quest(p_quest_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_def jsonb := private.quest_definition(p_quest_id);
  v_day text := private.manila_day_key(now());
  v_start timestamptz := private.manila_day_start(now());
  v_board public.daily_quest_boards;
  v_lb public.leaderboard;
  v_kind text;
  v_xp int;
  v_complete boolean;
  v_month text := private.manila_month_key(now());
  v_claim_id text;
begin
  if v_def is null then
    return jsonb_build_object('status', 'invalid_quest');
  end if;
  v_xp := (v_def ->> 0)::int;
  v_kind := v_def ->> 1;
  v_claim_id := v_uid || '_' || v_day || '_' || p_quest_id;
  if exists (select 1 from public.daily_quest_claims where id = v_claim_id) then
    return jsonb_build_object('status', 'already_claimed');
  end if;
  select * into v_board from public.daily_quest_boards
    where user_id = v_uid and day_key = v_day;
  if not found or not (p_quest_id = any (v_board.quest_ids)) then
    return jsonb_build_object('status', 'board_missing');
  end if;
  select * into v_lb from public.leaderboard where user_id = v_uid for update;
  if not found then
    return jsonb_build_object('status', 'leaderboard_missing');
  end if;

  with today as (
    select * from public.sessions s
    where s.user_id = v_uid and s.created_at >= v_start
      and s.created_at < v_start + interval '24 hours'
  )
  select case v_kind
    when 'count' then (select count(*) from today) >= (v_def ->> 2)::int
    when 'duration' then coalesce((select sum(duration_seconds) from today), 0) >= (v_def ->> 2)::int
    when 'best' then exists (select 1 from today where assessment_version = 2 and rubric_total >= (v_def ->> 2)::int)
    when 'above' then (select count(*) from today where assessment_version = 2 and rubric_total >= 7) >= (v_def ->> 2)::int
    when 'movements' then (select count(distinct lower(btrim(movement_name))) from today) >= (v_def ->> 2)::int
    when 'difficulty' then exists (select 1 from today where lower(btrim(difficulty)) = v_def ->> 2)
    when 'prop' then exists (select 1 from today where prop_type = v_def ->> 2)
    when 'props' then (select count(distinct prop_type) from today) >= (v_def ->> 2)::int
    else false
  end into v_complete;
  if not v_complete then
    return jsonb_build_object('status', 'quest_not_completed');
  end if;

  begin
    insert into public.daily_quest_claims (
      id, user_id, board_id, day_key, day_start, quest_id, xp_awarded
    ) values (v_claim_id, v_uid, v_board.id, v_day, v_start, p_quest_id, v_xp);
  exception when unique_violation then
    return jsonb_build_object('status', 'already_claimed');
  end;

  update public.leaderboard set
    quest_xp = quest_xp + v_xp,
    total_xp = total_xp + v_xp,
    last_claim_id = v_claim_id,
    daily_key = v_day,
    daily_xp = case when daily_key = v_day then daily_xp else 0 end + v_xp,
    daily_sessions_completed = case when daily_key = v_day then daily_sessions_completed else 0 end,
    daily_score_sum = case when daily_key = v_day then daily_score_sum else 0 end,
    daily_average_score = case when daily_key = v_day then daily_average_score else 0 end,
    daily_best_score = case when daily_key = v_day then daily_best_score else 0 end,
    monthly_key = v_month,
    monthly_xp = case when monthly_key = v_month then monthly_xp else 0 end + v_xp,
    monthly_sessions_completed = case when monthly_key = v_month then monthly_sessions_completed else 0 end,
    monthly_score_sum = case when monthly_key = v_month then monthly_score_sum else 0 end,
    monthly_average_score = case when monthly_key = v_month then monthly_average_score else 0 end,
    monthly_best_score = case when monthly_key = v_month then monthly_best_score else 0 end,
    updated_at = now()
  where user_id = v_uid;
  return jsonb_build_object('status', 'claimed', 'xp_awarded', v_xp);
end;
$$;

-- ---------------------------------------------------------------------------
-- Achievements and cosmetics. Completion is client-evaluated (cosmetic only,
-- no XP), exactly as documented for the capstone; reward mapping, ownership,
-- idempotency and equip-only-if-unlocked are enforced here.
-- ---------------------------------------------------------------------------

create or replace function public.claim_achievement(p_achievement_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_border text := private.achievement_reward_border(p_achievement_id);
  v_claim_id text;
begin
  if v_border is null then
    return jsonb_build_object('status', 'invalid_achievement');
  end if;
  v_claim_id := v_uid || '_' || p_achievement_id;
  begin
    insert into public.achievement_claims (id, user_id, achievement_id, reward_border_id)
    values (v_claim_id, v_uid, p_achievement_id, v_border);
  exception when unique_violation then
    return jsonb_build_object('status', 'already_claimed');
  end;
  insert into public.user_cosmetics (user_id, unlocked_border_ids, last_achievement_claim_id)
  values (v_uid, array[v_border], v_claim_id)
  on conflict (user_id) do update set
    unlocked_border_ids = case
      when v_border = any (public.user_cosmetics.unlocked_border_ids)
        then public.user_cosmetics.unlocked_border_ids
      else public.user_cosmetics.unlocked_border_ids || v_border end,
    last_achievement_claim_id = v_claim_id,
    updated_at = now();
  insert into public.public_profile_achievements (user_id, achievement_id)
  select v_uid, p_achievement_id
  where exists (select 1 from public.public_profiles where user_id = v_uid)
  on conflict do nothing;
  return jsonb_build_object('status', 'claimed', 'reward_border_id', v_border);
end;
$$;

create or replace function public.equip_border(p_border_id text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_next text := btrim(coalesce(p_border_id, ''));
  v_current text;
  v_unlocked text[];
begin
  if v_next <> '' and not private.is_known_border(v_next) then
    return jsonb_build_object('status', 'invalid_border');
  end if;
  select equipped_border_id into v_current from public.leaderboard
    where user_id = v_uid for update;
  if not found then
    return jsonb_build_object('status', 'leaderboard_missing');
  end if;
  if v_next <> '' then
    select unlocked_border_ids into v_unlocked from public.user_cosmetics where user_id = v_uid;
    if not found then
      return jsonb_build_object('status', 'cosmetics_missing');
    end if;
    if not (v_next = any (v_unlocked)) then
      return jsonb_build_object('status', 'border_locked');
    end if;
  end if;
  if v_current = v_next then
    return jsonb_build_object('status', 'already_equipped');
  end if;
  update public.leaderboard set equipped_border_id = v_next, updated_at = now()
  where user_id = v_uid;
  return jsonb_build_object('status', 'equipped');
end;
$$;

-- ---------------------------------------------------------------------------
-- Public profile projections (derived from authoritative rows server-side)
-- ---------------------------------------------------------------------------

create or replace function public.ensure_public_profile_root(
  p_display_name text, p_profile_picture_url text, p_initial_visibility text
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_name text := coalesce(nullif(btrim(coalesce(p_display_name, '')), ''), 'Trainee');
begin
  if p_initial_visibility not in ('public', 'private') then
    perform private.fail('invalid_payload');
  end if;
  insert into public.public_profiles (user_id, display_name, profile_picture_url, role, visibility)
  values (
    v_uid, left(v_name, 80),
    nullif(btrim(coalesce(p_profile_picture_url, '')), ''),
    private.profile_role(v_uid), p_initial_visibility
  ) on conflict (user_id) do nothing;
end;
$$;

create or replace function public.update_public_identity(
  p_display_name text, p_profile_picture_url text, p_clear_picture boolean
) returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_name text := nullif(btrim(coalesce(p_display_name, '')), '');
  v_picture text := nullif(btrim(coalesce(p_profile_picture_url, '')), '');
begin
  if v_name is null then
    return;
  end if;
  insert into public.public_profiles (user_id, display_name, profile_picture_url, role)
  values (v_uid, left(v_name, 80), v_picture, private.profile_role(v_uid))
  on conflict (user_id) do update set
    display_name = excluded.display_name,
    profile_picture_url = case
      when p_clear_picture then null
      when v_picture is not null then v_picture
      else public.public_profiles.profile_picture_url end,
    role = coalesce(private.profile_role(v_uid), public.public_profiles.role),
    updated_at = now();
end;
$$;

create or replace function public.set_public_profile_visibility(p_visibility text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
begin
  if p_visibility not in ('public', 'private') then
    perform private.fail('invalid_payload');
  end if;
  update public.public_profiles set visibility = p_visibility, updated_at = now()
  where user_id = v_uid;
  if not found then
    perform private.fail('not_found');
  end if;
end;
$$;

-- Projects sanitized fields of the caller's own session (no assignment,
-- challenge, custom-movement or storage-path data).
create or replace function public.project_public_session(p_session_id text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_session public.sessions;
begin
  select * into v_session from public.sessions where id = p_session_id and user_id = v_uid;
  if not found then
    perform private.fail('not_found');
  end if;
  if not exists (select 1 from public.public_profiles where user_id = v_uid) then
    perform private.fail('public_profile_missing');
  end if;
  insert into public.public_profile_sessions (
    session_id, user_id, movement_name, difficulty, duration_seconds, prop_type,
    created_at, assessment_version, score, rubric, rubric_total,
    performance_level, evidence_available
  ) values (
    v_session.id, v_uid, v_session.movement_name, v_session.difficulty,
    v_session.duration_seconds, v_session.prop_type, v_session.created_at,
    case when v_session.assessment_version = 2 then 2 end,
    v_session.score, v_session.rubric, v_session.rubric_total,
    v_session.performance_level,
    case when v_session.evidence_kind = 'hold_confirmed' then true end
  ) on conflict (session_id) do update set
    evidence_available = excluded.evidence_available;
  perform private.rebuild_public_summary(v_uid, p_session_id);
end;
$$;

create or replace function private.rebuild_public_summary(p_uid uuid, p_last_session text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into public.public_profile_summaries (
    user_id, total_duration_seconds, completed_movement_names,
    last_backfill_session_id, updated_at
  )
  select p_uid,
    coalesce(sum(s.duration_seconds), 0)::int,
    coalesce(array_agg(distinct btrim(s.movement_name) order by btrim(s.movement_name))
      filter (where private.is_official_movement(btrim(s.movement_name))), '{}'),
    p_last_session, now()
  from public.sessions s where s.user_id = p_uid
  on conflict (user_id) do update set
    total_duration_seconds = excluded.total_duration_seconds,
    completed_movement_names = excluded.completed_movement_names,
    last_backfill_session_id = coalesce(excluded.last_backfill_session_id,
      public.public_profile_summaries.last_backfill_session_id),
    updated_at = now();
end;
$$;

-- Backfills missing projections and the summary, and mirrors claimed
-- achievements. Never awards anything.
create or replace function public.sync_public_profile_projections()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_session record;
begin
  if not exists (select 1 from public.public_profiles where user_id = v_uid) then
    perform private.fail('public_profile_missing');
  end if;
  for v_session in
    select s.id from public.sessions s
    where s.user_id = v_uid
      and not exists (select 1 from public.public_profile_sessions p where p.session_id = s.id)
  loop
    perform public.project_public_session(v_session.id);
  end loop;
  perform private.rebuild_public_summary(v_uid, null);
  insert into public.public_profile_achievements (user_id, achievement_id, claimed_at)
  select v_uid, c.achievement_id, c.claimed_at
  from public.achievement_claims c where c.user_id = v_uid
  on conflict do nothing;
end;
$$;

create or replace function public.reconcile_public_evidence_availability()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
begin
  update public.public_profile_sessions p set evidence_available = true
  from public.sessions s
  where s.id = p.session_id and s.user_id = v_uid and p.user_id = v_uid
    and s.evidence_kind = 'hold_confirmed'
    and s.evidence_storage_path = 'users/' || v_uid || '/session_evidence/' || s.id || '.jpg'
    and p.evidence_available is distinct from true;
end;
$$;

create or replace function public.record_profile_visit(p_profile_owner_id uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
begin
  if p_profile_owner_id is null or p_profile_owner_id = v_uid then
    return;
  end if;
  if not exists (select 1 from auth.users where id = p_profile_owner_id) then
    return;
  end if;
  insert into public.profile_visits (profile_owner_id, viewer_id)
  values (p_profile_owner_id, v_uid)
  on conflict (profile_owner_id, viewer_id) do update set last_viewed_at = now();
end;
$$;

-- ---------------------------------------------------------------------------
-- Training plans: only today..today+366 (Manila) are actionable.
-- ---------------------------------------------------------------------------

create or replace function private.is_actionable_plan_day(p_day text)
returns boolean language sql stable as $$
  select private.is_day_key(p_day)
    and p_day >= private.manila_day_key(now())
    and p_day <= private.manila_day_key(now() + interval '366 days')
$$;

create or replace function public.upsert_training_plan(p_plan jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
  v_day text := p_plan ->> 'day_key';
  v_row public.training_plans;
begin
  if not private.is_actionable_plan_day(v_day) then
    perform private.fail('invalid_day');
  end if;
  insert into public.training_plans (
    id, user_id, day_key, plan_type, movement_name, difficulty, prop_type,
    target_duration_minutes
  ) values (
    v_uid || '_' || v_day, v_uid, v_day, p_plan ->> 'plan_type',
    p_plan ->> 'movement_name', p_plan ->> 'difficulty', p_plan ->> 'prop_type',
    (p_plan ->> 'target_duration_minutes')::int
  ) on conflict (id) do update set
    plan_type = excluded.plan_type,
    movement_name = excluded.movement_name,
    difficulty = excluded.difficulty,
    prop_type = excluded.prop_type,
    target_duration_minutes = excluded.target_duration_minutes,
    updated_at = now()
  returning * into v_row;
  return jsonb_strip_nulls(to_jsonb(v_row));
end;
$$;

create or replace function public.delete_training_plan(p_day_key text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := private.require_uid();
begin
  if not private.is_actionable_plan_day(p_day_key) then
    perform private.fail('invalid_day');
  end if;
  delete from public.training_plans where id = v_uid || '_' || p_day_key and user_id = v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- Optional explicit legacy identity map for a future Firestore data import.
-- Never exposed to clients.
-- ---------------------------------------------------------------------------

create table public.legacy_firebase_identities (
  firebase_uid text primary key check (char_length(firebase_uid) between 1 and 128),
  user_id uuid not null unique references auth.users (id) on delete cascade,
  mapped_at timestamptz not null default now()
);
alter table public.legacy_firebase_identities enable row level security;
