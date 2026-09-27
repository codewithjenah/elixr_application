-- ELIXR database security and behavior tests.
--
-- Run against a disposable database after the migrations (and, on plain
-- PostgreSQL, supabase/tests/support/local_supabase_stub.sql):
--   psql -v ON_ERROR_STOP=1 -f supabase/tests/rls/elixr_security_test.sql
-- Every assertion raises on failure; the whole script runs in one
-- transaction and is rolled back.

begin;

create schema tests;
grant usage on schema tests to authenticated;

create function tests.check(p_condition boolean, p_message text) returns void
language plpgsql as $$
begin
  if p_condition is not true then
    raise exception 'ASSERTION FAILED: %', p_message;
  end if;
end;
$$;

-- Runs p_sql as the current role; asserts it fails with p_expected in the
-- error message (or any error when p_expected is null).
create function tests.expect_error(p_sql text, p_expected text, p_message text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if p_expected is not null and position(p_expected in sqlerrm) = 0 then
      raise exception 'ASSERTION FAILED: % (expected "%", got "%")', p_message, p_expected, sqlerrm;
    end if;
    return;
  end;
  raise exception 'ASSERTION FAILED: % (statement succeeded)', p_message;
end;
$$;

create function tests.login(p_uid uuid) returns void language sql as $$
  select set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
$$;

grant execute on all functions in schema tests to authenticated;

-- ---------------------------------------------------------------------------
-- Fixtures (as the migration owner)
-- ---------------------------------------------------------------------------

insert into public.teacher_access_codes (code) values ('ABCDEFGHJKLM'), ('BCDEFGHJKLMN');

-- Email/password registrations go through the sign-up trigger.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-4111-8111-111111111111', 'teacher@example.com', now(),
   '{"elixr_registration":"v1","role":"Teacher","first_name":"Tess","last_name":"Teacher","teacher_access_code":"ABCDEFGHJKLM","privacy_policy_version":"v6","terms_of_service_version":"v3"}'),
  ('22222222-2222-4222-8222-222222222222', 'ana@example.com', now(),
   '{"elixr_registration":"v1","role":"Trainee","first_name":"Ana","middle_name":"M","last_name":"Trainee","privacy_policy_version":"v6","terms_of_service_version":"v3"}'),
  ('33333333-3333-4333-8333-333333333333', 'ben@example.com', now(),
   '{"elixr_registration":"v1","role":"Trainee","first_name":"Ben","last_name":"Outsider","privacy_policy_version":"v6","terms_of_service_version":"v3"}'),
  ('44444444-4444-4444-8444-444444444444', 'cara@example.com', now(),
   '{"elixr_registration":"v1","role":"Trainee","first_name":"Cara","last_name":"Classmate","privacy_policy_version":"v6","terms_of_service_version":"v3"}');

do $$
begin
  perform tests.check((select role from public.profiles where id = '11111111-1111-4111-8111-111111111111') = 'Teacher',
    'teacher registration creates a Teacher profile');
  perform tests.check((select consumed_by from public.teacher_access_codes where code = 'ABCDEFGHJKLM')
    = '11111111-1111-4111-8111-111111111111', 'teacher registration consumes the access code');
  perform tests.check((select full_name from public.profiles where id = '22222222-2222-4222-8222-222222222222')
    = 'Ana M Trainee', 'full name composition');
  perform tests.check((select visibility from public.public_profiles where user_id = '22222222-2222-4222-8222-222222222222')
    = 'public', 'new accounts seed a public profile root');
end $$;

-- A consumed access code cannot create a second Teacher (sign-up aborts).
select tests.expect_error($$
  insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
    ('55555555-5555-4555-8555-555555555555', 'mallory@example.com', now(),
     '{"elixr_registration":"v1","role":"Teacher","first_name":"Mal","last_name":"Lory","teacher_access_code":"ABCDEFGHJKLM","privacy_policy_version":"v6","terms_of_service_version":"v3"}')
$$, 'access_code_consumed', 'reused Teacher access code');

select tests.expect_error($$
  insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
    ('55555555-5555-4555-8555-555555555555', 'mallory@example.com', now(),
     '{"elixr_registration":"v1","role":"Trainee","first_name":"Mal","last_name":"Lory","teacher_access_code":"BCDEFGHJKLMN","privacy_policy_version":"v6","terms_of_service_version":"v3"}')
$$, 'invalid_role', 'Trainee registration cannot carry an access code');

-- OAuth identity without a profile (onboarding completes explicitly).
insert into auth.users (id, email, email_confirmed_at) values
  ('66666666-6666-4666-8666-666666666666', 'gina@example.com', now());

-- Uploaded submission object stand-in used later (as the Storage service).
set local role authenticated;

-- ---------------------------------------------------------------------------
-- Profiles: ownership isolation, allow-listed updates
-- ---------------------------------------------------------------------------

select tests.login('22222222-2222-4222-8222-222222222222');
do $$
begin
  perform tests.check((select count(*) from public.profiles) = 1, 'a user reads only their own profile');
  perform tests.check((select id from public.profiles) = '22222222-2222-4222-8222-222222222222',
    'own profile is readable');
end $$;
select tests.expect_error($$ select public.update_own_profile('{"role":"Teacher"}') $$,
  'invalid_field', 'role is not client-writable');
select tests.expect_error($$ select public.update_own_profile('{"email":"x@example.com"}') $$,
  'forbidden', 'profile email must match the auth email');
select tests.expect_error($$ select public.update_own_profile('{"profile_border_id":"starter_glow"}') $$,
  'forbidden', 'Trainees cannot set a Teacher border');
select tests.expect_error($$ update public.profiles set role = 'Teacher' $$,
  'permission denied', 'no direct profile writes');
do $$
declare
  v jsonb;
begin
  v := public.update_own_profile('{"session_evidence_enabled": true, "middle_name": null}');
  perform tests.check(v ->> 'full_name' = 'Ana Trainee', 'middle name removal recomposes full name');
  perform tests.check(v ->> 'session_evidence_policy_version' = 'v1', 'evidence decision is stamped');
end $$;

-- Trainees cannot perform Teacher operations.
select tests.expect_error($$ select public.create_group('Hack', null, null) $$,
  'forbidden', 'Trainee cannot create a classroom');
select tests.expect_error($$ select public.mint_teacher_access_code(null) $$,
  'forbidden', 'Trainee cannot mint access codes');

-- OAuth user completes a Trainee profile explicitly.
select tests.login('66666666-6666-4666-8666-666666666666');
select tests.expect_error($$ select public.create_own_profile('Teacher', 'Gina', null, 'G', 'v6', 'v3', 'ZZZZZZZZZZZZ') $$,
  'access_code_not_found', 'unknown Teacher access code');
select public.create_own_profile('Trainee', 'Gina', null, 'Google', 'v6', 'v3', null);
select tests.expect_error($$ select public.create_own_profile('Trainee', 'Gina', null, 'Google', 'v6', 'v3', null) $$,
  'profile_exists', 'profile creation is single-shot');

-- ---------------------------------------------------------------------------
-- Sessions and leaderboard replay protection
-- ---------------------------------------------------------------------------

select tests.login('22222222-2222-4222-8222-222222222222');
select public.save_session('sessAna0000000000001',
  '{"movement_name":"Hand Stall","difficulty":"Easy","duration_seconds":700,"prop_type":"shaker","assessment_version":2,"rubric":{"technique":3,"stability":2,"completion":3,"prop_positioning":2},"rubric_total":10,"performance_level":"proficient"}',
  '[{"message":"Nice","feedback_type":"positive"}]');
select tests.expect_error($$
  select public.save_session('sessAna0000000000002',
    '{"movement_name":"Hand Stall","difficulty":"Easy","duration_seconds":60,"prop_type":"bottle","assessment_version":2,"rubric":{"technique":3,"stability":3,"completion":3,"prop_positioning":3},"rubric_total":11,"performance_level":"proficient"}',
    '[]')
$$, 'sessions_assessment_partition', 'rubric total must equal the criterion sum');
select tests.expect_error($$
  select public.save_session('sessAna0000000000003',
    '{"movement_name":"Not Official","difficulty":"Easy","duration_seconds":60,"prop_type":"bottle","assessment_version":2,"rubric":{"technique":1,"stability":1,"completion":1,"prop_positioning":1},"rubric_total":4,"performance_level":"developing"}',
    '[]')
$$, 'invalid_payload', 'unofficial movement names cannot be saved as official sessions');
select tests.expect_error($$
  select public.save_session('sessAna0000000000004',
    '{"movement_name":"Hand Stall","difficulty":"Easy","duration_seconds":60,"prop_type":"shaker","assessment_version":2,"rubric":{"technique":1,"stability":1,"completion":1,"prop_positioning":1},"rubric_total":4,"performance_level":"developing","assignment_context":{"assignment_id":"x"}}',
    '[]')
$$, 'assignment_requires_server_completion', 'assignment sessions need the server completion path');
select tests.expect_error($$
  select public.save_session('sessAna0000000000005',
    '{"movement_name":"Hand Stall","difficulty":"Easy","duration_seconds":60,"prop_type":"shaker","assessment_version":2,"rubric":{"technique":1,"stability":1,"completion":1,"prop_positioning":1},"rubric_total":4,"performance_level":"developing","evidence_storage_path":"users/33333333-3333-4333-8333-333333333333/session_evidence/sessAna0000000000005.jpg","evidence_kind":"hold_confirmed","evidence_size_bytes":2048}',
    '[]')
$$, 'sessions_evidence_shape', 'evidence path must be the owner''s canonical path');

do $$
declare
  v jsonb;
begin
  v := public.award_session_xp('sessAna0000000000001', 'Ana Trainee', null);
  perform tests.check(v ->> 'status' = 'awarded', 'first award succeeds');
  v := public.award_session_xp('sessAna0000000000001', 'Ana Trainee', null);
  perform tests.check(v ->> 'status' = 'already_processed', 'award replay is idempotent');
  perform tests.check((select total_xp from public.leaderboard where user_id = auth.uid()) = 25,
    'exactly one session award');
  perform tests.check((select best_score from public.leaderboard where user_id = auth.uid()) = 0,
    'rubric sessions never enter percentage aggregates');
  perform tests.check((select daily_key from public.leaderboard where user_id = auth.uid())
    = to_char(now() at time zone 'Asia/Manila', 'YYYYMMDD'), 'daily key uses the Manila day');
  perform tests.check((select count(*) from public.feedbacks) = 1, 'feedback is stored with its session');
end $$;
select tests.expect_error($$ update public.leaderboard set total_xp = 9999 $$,
  'permission denied', 'no direct leaderboard writes');
select tests.expect_error($$ delete from public.leaderboard_processed_sessions $$,
  'permission denied', 'award markers cannot be deleted by clients');

select tests.login('33333333-3333-4333-8333-333333333333');
do $$
begin
  perform tests.check((select count(*) from public.sessions) = 0, 'unrelated user cannot read sessions');
  perform tests.check((select count(*) from public.feedbacks) = 0, 'unrelated user cannot read feedback');
  perform tests.check((select count(*) from public.leaderboard) = 1, 'leaderboard is readable when signed in');
end $$;
select tests.expect_error($$ select public.award_session_xp('sessAna0000000000001', 'Ben', null) $$,
  'forbidden', 'a user cannot award another user''s session');

-- ---------------------------------------------------------------------------
-- Daily quests (server-evaluated, replay-safe)
-- ---------------------------------------------------------------------------

select tests.login('22222222-2222-4222-8222-222222222222');
select tests.expect_error($$ select public.get_or_create_daily_quest_board(array['session_count_1','session_count_3','session_count_5','score_70','score_85']) $$,
  'invalid_board', 'board composition is validated');
select public.get_or_create_daily_quest_board(
  array['session_count_1', 'use_shaker', 'duration_20min', 'three_movements', 'score_95']);
do $$
declare
  v jsonb;
begin
  v := public.claim_daily_quest('three_movements');
  perform tests.check(v ->> 'status' = 'quest_not_completed', 'incomplete quest cannot be claimed');
  v := public.claim_daily_quest('score_70');
  perform tests.check(v ->> 'status' = 'board_missing', 'quest must be on today''s board');
  v := public.claim_daily_quest('use_shaker');
  perform tests.check(v ->> 'status' = 'claimed' and (v ->> 'xp_awarded')::int = 10, 'completed quest is claimed');
  v := public.claim_daily_quest('use_shaker');
  perform tests.check(v ->> 'status' = 'already_claimed', 'quest claims are replay-safe');
  perform tests.check((select total_xp from public.leaderboard where user_id = auth.uid()) = 35,
    'quest XP is added exactly once');
end $$;

-- ---------------------------------------------------------------------------
-- Classrooms and membership isolation
-- ---------------------------------------------------------------------------

select tests.login('11111111-1111-4111-8111-111111111111');
select public.create_group('Flair 101', 'A', null);
do $$
begin
  perform tests.check((select count(*) from public.groups) = 1, 'teacher sees own classroom');
  perform tests.check((select invite_code from public.groups) is not null, 'classroom gets an invite code');
end $$;
select set_config('tests.group_id', (select id from public.groups), true);
select set_config('tests.invite', (select invite_code from public.groups), true);

select tests.login('22222222-2222-4222-8222-222222222222');
do $$
begin
  perform tests.check((select count(*) from public.groups) = 0, 'pending trainee cannot read classroom');
  perform public.request_group_join(current_setting('tests.invite'));
end $$;
select tests.login('44444444-4444-4444-8444-444444444444');
select public.request_group_join(current_setting('tests.invite'));
select tests.expect_error($$ select public.request_group_join(current_setting('tests.invite')) $$,
  'already_pending', 'duplicate join request');

select tests.login('11111111-1111-4111-8111-111111111111');
select public.transition_group_membership(current_setting('tests.group_id') || '_22222222-2222-4222-8222-222222222222', 'approve');
select public.transition_group_membership(current_setting('tests.group_id') || '_44444444-4444-4444-8444-444444444444', 'approve');

select tests.login('22222222-2222-4222-8222-222222222222');
do $$
begin
  perform tests.check((select count(*) from public.groups) = 1, 'approved member reads active classroom');
  perform tests.check((select count(*) from public.group_memberships) = 2, 'approved members see approved classmates');
end $$;

select tests.login('33333333-3333-4333-8333-333333333333');
do $$
begin
  perform tests.check((select count(*) from public.groups) = 0, 'outsider cannot read classroom');
  perform tests.check((select count(*) from public.group_memberships) = 0, 'outsider cannot read memberships');
end $$;
select tests.expect_error($$
  select public.transition_group_membership(current_setting('tests.group_id') || '_22222222-2222-4222-8222-222222222222', 'remove')
$$, 'not_found', 'outsider cannot remove members');

-- ---------------------------------------------------------------------------
-- Official assignment with a finite attempt policy
-- ---------------------------------------------------------------------------

select tests.login('11111111-1111-4111-8111-111111111111');
do $$
declare
  v jsonb;
begin
  v := public.create_classroom_assignment(jsonb_build_object(
    'group_id', current_setting('tests.group_id'), 'audience_type', 'individual_student',
    'recipient_ids', jsonb_build_array('22222222-2222-4222-8222-222222222222'),
    'attempt_policy', jsonb_build_object('type', 'finite', 'maximum_attempts', 1),
    'origin', 'official_elixr', 'official_movement_name', 'Hand Stall', 'allowed_prop', 'shaker'));
  perform set_config('tests.assignment_id', v #>> '{assignment,id}', true);
  perform tests.check(jsonb_array_length(v -> 'recipient_ids') = 1, 'recipients are returned');
end $$;
select tests.expect_error($$
  select public.create_classroom_assignment(jsonb_build_object(
    'group_id', current_setting('tests.group_id'), 'audience_type', 'individual_student',
    'recipient_ids', jsonb_build_array('33333333-3333-4333-8333-333333333333'),
    'origin', 'official_elixr', 'official_movement_name', 'Hand Stall', 'allowed_prop', 'shaker'))
$$, 'invalid_recipient', 'recipients must be approved members');

select tests.login('44444444-4444-4444-8444-444444444444');
do $$
begin
  perform tests.check((select count(*) from public.group_assignments) = 0,
    'non-recipient classmate cannot see a targeted assignment');
end $$;

select tests.login('22222222-2222-4222-8222-222222222222');
do $$
declare
  v_session jsonb;
begin
  perform tests.check((select count(*) from public.group_assignments) = 1, 'recipient sees the assignment');
  v_session := jsonb_build_object('movement_name', 'Hand Stall', 'difficulty', 'Easy',
    'duration_seconds', 30, 'prop_type', 'shaker', 'assessment_version', 2,
    'rubric', '{"technique":2,"stability":2,"completion":2,"prop_positioning":2}'::jsonb,
    'rubric_total', 8, 'performance_level', 'competent',
    'assignment_context', jsonb_build_object('assignment_id', current_setting('tests.assignment_id'),
      'group_id', current_setting('tests.group_id'),
      'teacher_id', '11111111-1111-4111-8111-111111111111',
      'movement_id', 'official_hand_stall', 'revision_id', 'official_hand_stall_v1'));
  perform public.complete_official_assignment_session('sessAnaAssign0000001', v_session, '[]');
  perform tests.check((select count(*) from public.assignment_attempts
    where id = 'official_ptr_sessAnaAssign0000001') = 1, 'official pointer is written atomically');
  perform tests.check(
    (public.complete_official_assignment_session('sessAnaAssign0000001', v_session, '[]')) ->> 'reused' = 'true',
    'completion retry is idempotent');
  perform tests.expect_error(format(
    'select public.complete_official_assignment_session(%L, %L::jsonb, %L::jsonb)',
    'sessAnaAssign0000002', v_session, '[]'), 'attempts_exhausted', 'finite attempt limit is enforced');
  perform tests.check(
    (public.award_session_xp('sessAnaAssign0000001', 'Ana', null)) ->> 'status' = 'awarded',
    'assignment sessions still award practice XP once');
end $$;

-- ---------------------------------------------------------------------------
-- Teacher Activity: reserve -> consume -> finalize -> turn in -> grade
-- ---------------------------------------------------------------------------

select tests.login('11111111-1111-4111-8111-111111111111');
do $$
declare
  v_spec jsonb := '{"instructions":"Hold the bottle","required_prop":"bottle","capability":"teacher_review_only","activity_assessment":{"schema_version":3,"readiness":{"hands":"one_hand","body":"none"},"rubric":{"template_id":"custom","maximum_score":10,"criteria":[{"id":"a","label":"A","description":"A","maximum_points":4},{"id":"b","label":"B","description":"B","maximum_points":3},{"id":"c","label":"C","description":"C","maximum_points":3}]},"recording_duration_seconds":30}}';
  v jsonb;
begin
  v := public.create_teacher_movement('Bottle hold', v_spec, 2);
  v := public.create_classroom_assignment(jsonb_build_object(
    'group_id', current_setting('tests.group_id'), 'audience_type', 'entire_class',
    'recipient_ids', '[]'::jsonb, 'origin', 'teacher_created',
    'movement_id', v ->> 'id', 'revision_id', v ->> 'current_revision_id', 'max_score', 10,
    'attempt_policy', jsonb_build_object('type', 'finite', 'maximum_attempts', 2)));
  perform set_config('tests.activity_id', v #>> '{assignment,id}', true);
end $$;

select tests.login('22222222-2222-4222-8222-222222222222');
do $$
declare
  v jsonb;
begin
  v := public.reserve_teacher_activity_attempt(current_setting('tests.activity_id'), 'req1');
  perform set_config('tests.attempt_id', v #>> '{attempt,id}', true);
  perform set_config('tests.attempt_path', 'assignment_submissions/11111111-1111-4111-8111-111111111111/'
    || current_setting('tests.group_id') || '/' || current_setting('tests.activity_id')
    || '/22222222-2222-4222-8222-222222222222/' || (v #>> '{attempt,id}') || '.mp4', true);
  perform tests.check(
    (public.reserve_teacher_activity_attempt(current_setting('tests.activity_id'), 'req1')) ->> 'reused' = 'true',
    'reservation retry with the same request id is reused');
  perform tests.expect_error(format('select public.reserve_teacher_activity_attempt(%L, %L)',
    current_setting('tests.activity_id'), 'req2'), 'attempt_in_progress', 'one active reservation');
  perform public.consume_teacher_activity_attempt(current_setting('tests.activity_id'), current_setting('tests.attempt_id'));
  perform tests.expect_error(format('select public.finalize_teacher_activity_attempt(%L, %L, %L, %L, %s, %s)',
    current_setting('tests.activity_id'), current_setting('tests.attempt_id'),
    current_setting('tests.attempt_path'), 'video/mp4', 4096, 10000), 'upload_missing',
    'finalize requires the uploaded object');
end $$;

-- Storage RLS: the trainee may upload only to their reserved attempt path.
insert into storage.objects (bucket_id, name, owner, metadata)
values ('assignment-submissions', current_setting('tests.attempt_path'),
  '22222222-2222-4222-8222-222222222222', '{"size":4096,"mimetype":"video/mp4"}');
select tests.expect_error($$
  insert into storage.objects (bucket_id, name, metadata)
  values ('assignment-submissions', 'assignment_submissions/11111111-1111-4111-8111-111111111111/'
    || current_setting('tests.group_id') || '/' || current_setting('tests.activity_id')
    || '/22222222-2222-4222-8222-222222222222/activity_forged.mp4', '{}')
$$, 'row-level security', 'unreserved submission path is rejected');

do $$
declare
  v jsonb;
begin
  v := public.finalize_teacher_activity_attempt(current_setting('tests.activity_id'),
    current_setting('tests.attempt_id'), current_setting('tests.attempt_path'), 'video/mp4', 4096, 10000);
  perform tests.check(v #>> '{attempt,video_storage_path}' = current_setting('tests.attempt_path'),
    'finalize attaches the verified object');
  v := public.turn_in_assignment_attempt(current_setting('tests.activity_id'), current_setting('tests.attempt_id'));
  perform tests.check(v #>> '{attempt,status}' = 'submitted', 'attempt is turned in');
end $$;
select tests.expect_error($$
  insert into storage.objects (bucket_id, name, metadata)
  values ('assignment-submissions', current_setting('tests.attempt_path') || 'x', '{}')
$$, 'row-level security', 'submitted attempts cannot receive new objects');

select tests.login('33333333-3333-4333-8333-333333333333');
do $$
begin
  perform tests.check((select count(*) from storage.objects where bucket_id = 'assignment-submissions') = 0,
    'outsider cannot read submission objects');
  perform tests.check((select count(*) from public.assignment_attempts) = 0, 'outsider cannot read attempts');
end $$;

select tests.login('11111111-1111-4111-8111-111111111111');
do $$
declare
  v jsonb;
begin
  perform tests.check((select count(*) from storage.objects where bucket_id = 'assignment-submissions') = 1,
    'teacher reads submitted objects');
  perform tests.expect_error(format('select public.grade_teacher_activity_attempt(%L, %L::jsonb, null)',
    current_setting('tests.attempt_id'), '{"a":5,"b":1,"c":1}'), 'invalid_scores', 'criterion bounds');
  v := public.grade_teacher_activity_attempt(current_setting('tests.attempt_id'), '{"a":4,"b":2,"c":1}', 'Good');
  perform tests.check((v #>> '{attempt,grade_score}')::int = 7, 'grade total is server-computed');
end $$;

-- ---------------------------------------------------------------------------
-- Evidence privacy
-- ---------------------------------------------------------------------------

reset role;
insert into storage.objects (bucket_id, name, owner, metadata) values
  ('session-evidence', 'users/22222222-2222-4222-8222-222222222222/session_evidence/sessAna0000000000001.jpg',
   '22222222-2222-4222-8222-222222222222', '{"size":2048,"mimetype":"image/jpeg"}'),
  ('session-evidence', 'users/33333333-3333-4333-8333-333333333333/session_evidence/sessBen0000000000001.jpg',
   '33333333-3333-4333-8333-333333333333', '{"size":2048,"mimetype":"image/jpeg"}');
set local role authenticated;

select tests.login('11111111-1111-4111-8111-111111111111');
do $$
begin
  perform tests.check((select count(*) from storage.objects where bucket_id = 'session-evidence') = 1,
    'teacher reads classroom trainee evidence only while consent is on');
end $$;
select tests.login('22222222-2222-4222-8222-222222222222');
select public.update_own_profile('{"session_evidence_enabled": false}');
select tests.login('11111111-1111-4111-8111-111111111111');
do $$
begin
  perform tests.check((select count(*) from storage.objects where bucket_id = 'session-evidence') = 0,
    'revoked consent removes Teacher evidence access immediately');
end $$;
select tests.login('33333333-3333-4333-8333-333333333333');
select tests.expect_error($$
  insert into storage.objects (bucket_id, name, metadata)
  values ('session-evidence', 'users/22222222-2222-4222-8222-222222222222/session_evidence/x.jpg', '{}')
$$, 'row-level security', 'users cannot write another user''s evidence path');

-- ---------------------------------------------------------------------------
-- Membership removal revokes access
-- ---------------------------------------------------------------------------

select tests.login('22222222-2222-4222-8222-222222222222');
select public.transition_group_membership(current_setting('tests.group_id') || '_22222222-2222-4222-8222-222222222222', 'leave');
do $$
begin
  perform tests.check((select count(*) from public.groups) = 0, 'leaving removes classroom access');
  perform tests.check((select count(*) from public.group_assignments) = 0, 'leaving removes assignment access');
end $$;

-- ---------------------------------------------------------------------------
-- Custom movements: ownership and no global XP
-- ---------------------------------------------------------------------------

select tests.login('44444444-4444-4444-8444-444444444444');
do $$
declare
  v_template jsonb := '{"schema_version":1,"capture_version":1,"duration_ms":2000,"reference_count":2,"required_modalities":["hands"],"normalization_metadata":{},"feature_capabilities":{"prop_rotation":false},"canonical_sequence":[[0],[1]],"variability_metadata":{},"prop_events":[]}';
begin
  perform tests.expect_error(format('select public.create_custom_movement(%L,%L,%L,%L,%L,%L,%L,%L::jsonb,null)',
    'cmov1', 'crev1', 'teacher', 'Spin', '', 'Easy', 'bottle', v_template), 'forbidden',
    'Trainees cannot create Teacher-owned custom movements');
  perform public.create_custom_movement('cmov1', 'crev1', 'trainee', 'Spin', '', 'Easy', 'bottle', v_template, null);
  perform public.save_custom_movement_result('sessCara000000000001', 'cmov1', 'crev1', 81.4, '{}', '["ok"]', 30);
  perform tests.check((select score from public.sessions where id = 'sessCara000000000001') = 81,
    'custom result mirrors a rounded legacy score');
  perform tests.expect_error($q$ select public.award_session_xp('sessCara000000000001', 'Cara', null) $q$,
    'not_awardable', 'custom movement sessions never award global XP');
end $$;

-- Custom practice completion evidence and retry-safe persistence.
do $$
declare
  v jsonb;
begin
  v := public.save_custom_movement_practice_result('sessCara000000000002', 'cmov1', 'crev1',
    66.7, '{"Timing":2}', '["ok"]', 12, null);
  perform tests.check(v ->> 'reused' = 'false', 'first custom practice save commits');
  v := public.save_custom_movement_practice_result('sessCara000000000002', 'cmov1', 'crev1',
    66.7, '{"Timing":2}', '["ok"]', 12, null);
  perform tests.check(v ->> 'reused' = 'true', 'retry of the same attempt is idempotent');
  perform tests.check((select count(*) from public.custom_movement_results
    where id = 'sessCara000000000002') = 1, 'retry never duplicates the custom result');
  perform tests.check((select evidence_kind from public.sessions
    where id = 'sessCara000000000002') is null, 'no evidence is attached without an upload');
  perform tests.expect_error($q$ select public.save_custom_movement_practice_result(
    'sessCara000000000003', 'cmov1', 'crev1', 50, '{}', '[]', 10, 4096) $q$,
    'evidence_missing', 'evidence metadata requires the uploaded private object');
  perform tests.expect_error($q$ select public.save_custom_movement_practice_result(
    'sessCara000000000003', 'cmov1', 'crev1', 50, '{}', '[]', 10, 100) $q$,
    'malformed', 'evidence size stays within the Storage contract');
  perform tests.expect_error($q$ select public.save_custom_movement_practice_result(
    'sessCara000000000003', 'cmov1', 'crev1', 101, '{}', '[]', 10, null) $q$,
    'malformed', 'custom percentage is bounded 0..100');
end $$;
reset role;
insert into storage.objects (bucket_id, name, owner, metadata) values
  ('session-evidence', 'users/44444444-4444-4444-8444-444444444444/session_evidence/sessCara000000000004.jpg',
   '44444444-4444-4444-8444-444444444444', '{"size":4096,"mimetype":"image/jpeg"}');
set local role authenticated;
select tests.login('44444444-4444-4444-8444-444444444444');
do $$
begin
  perform public.save_custom_movement_practice_result('sessCara000000000004', 'cmov1', 'crev1',
    91.7, '{"Timing":3}', '[]', 9, 4096);
  perform tests.check((select evidence_kind from public.sessions where id = 'sessCara000000000004')
    = 'movement_completed', 'custom evidence uses the completed-movement kind');
  perform tests.check((select evidence_storage_path from public.sessions where id = 'sessCara000000000004')
    = 'users/44444444-4444-4444-8444-444444444444/session_evidence/sessCara000000000004.jpg',
    'custom evidence path is derived server-side');
  perform tests.check((select evidence_available from public.public_profile_sessions
    where session_id = 'sessCara000000000004') is null, 'custom evidence is never projected publicly');
end $$;
select tests.login('33333333-3333-4333-8333-333333333333');
select tests.expect_error($$
  select public.save_custom_movement_practice_result('sessBen0000000000009', 'cmov1', 'crev1', 50, '{}', '[]', 10, null)
$$, 'forbidden', 'only the movement owner can save a custom practice result');
select tests.expect_error($$
  select public.save_custom_movement_practice_result('sessCara000000000002', 'cmov1', 'crev1', 50, '{}', '[]', 10, null)
$$, 'forbidden', 'another user cannot replay someone else''s session id');
select tests.login('22222222-2222-4222-8222-222222222222');
select tests.expect_error($$
  select public.save_session('sessAna0000000000006',
    '{"movement_name":"Hand Stall","difficulty":"Easy","duration_seconds":60,"prop_type":"shaker","assessment_version":2,"rubric":{"technique":1,"stability":1,"completion":1,"prop_positioning":1},"rubric_total":4,"performance_level":"developing","evidence_storage_path":"users/22222222-2222-4222-8222-222222222222/session_evidence/sessAna0000000000006.jpg","evidence_kind":"movement_completed","evidence_size_bytes":2048}',
    '[]')
$$, 'sessions_evidence_shape', 'official sessions cannot claim custom completion evidence');
select tests.login('44444444-4444-4444-8444-444444444444');
do $$
declare
  v_v1 jsonb := '{"schema_version":1,"capture_version":1,"duration_ms":2000,"reference_count":2,"required_modalities":["hands","prop_translation"],"normalization_metadata":{},"feature_capabilities":{"pose":false,"hands":true,"prop_translation":true,"release_catch":false,"prop_rotation":false},"canonical_sequence":[[0],[1]],"variability_metadata":{},"prop_events":[]}';
  v_v2 jsonb;
  v_v3 jsonb;
  v_sequence jsonb;
  v_trace jsonb;
begin
  select jsonb_agg(jsonb_build_object('timestamp_ms', i * 25, 'pose', '{}'::jsonb))
    into v_sequence from generate_series(0, 31) i;
  select jsonb_build_object(
    'angles_rad', jsonb_agg(i * 0.2),
    'total_signed_rad', 6.2,
    'coverage', 0.95,
    'pair_coverage', 0.9
  ) into v_trace from generate_series(0, 31) i;
  v_v2 := jsonb_set(jsonb_set(jsonb_set(v_v1,
    '{schema_version}', '2'::jsonb),
    '{canonical_sequence}', v_sequence),
    '{feature_capabilities,prop_rotation}', 'true'::jsonb)
    || jsonb_build_object('rotation_trace', v_trace);
  v_v3 := jsonb_set(jsonb_set(v_v1,
    '{schema_version}', '3'::jsonb),
    '{canonical_sequence}', v_sequence)
    || jsonb_build_object('movement_behavior', 'static', 'rotation_trace', null);

  perform tests.check(private.valid_movement_template(v_v1), 'valid schema-v1 template remains accepted');
  perform tests.check(private.valid_movement_template(v_v2), 'valid schema-v2 rotation remains accepted');
  perform tests.check(private.valid_movement_template(v_v3), 'static schema-v3 JSON null trace is accepted');
  perform tests.check(jsonb_typeof(v_v3 -> 'rotation_trace') = 'null',
    'static fixture contains a present JSON null rotation trace');
  perform tests.check(not private.valid_movement_template(v_v3 - 'movement_behavior'),
    'schema-v3 movement behavior is required');
  perform tests.check(not private.valid_movement_template(v_v3 || jsonb_build_object('movement_behavior', 'dynamic')),
    'schema-v3 dynamic behavior is rejected');
  perform tests.check(not private.valid_movement_template(v_v3 || jsonb_build_object('movement_behavior', 'other')),
    'unknown schema-v3 behavior is rejected');
  perform tests.check(not private.valid_movement_template(v_v3 - 'rotation_trace'),
    'schema-v3 rotation trace key is required');
  perform tests.check(not private.valid_movement_template(v_v3 || jsonb_build_object('rotation_trace', v_trace)),
    'schema-v3 trace cannot contradict false rotation capability');
  perform tests.check(not private.valid_movement_template(jsonb_set(v_v3,
    '{feature_capabilities,prop_rotation}', 'true'::jsonb)),
    'schema-v3 learned rotation requires a trace');
  perform tests.check(not private.valid_movement_template(jsonb_set(jsonb_set(v_v3,
    '{feature_capabilities,prop_rotation}', 'true'::jsonb),
    '{rotation_trace}', '{"angles_rad":[]}'::jsonb)),
    'schema-v3 learned rotation rejects an invalid trace');
  perform tests.check(not private.valid_movement_template(jsonb_set(jsonb_set(v_v2,
    '{schema_version}', '3'::jsonb) || jsonb_build_object('movement_behavior', 'static'),
    '{rotation_trace,angles_rad,0}', '"invalid"'::jsonb)),
    'schema-v3 learned rotation rejects invalid angle values');
  perform tests.check(private.valid_movement_template(jsonb_set(v_v2,
    '{schema_version}', '3'::jsonb) || jsonb_build_object('movement_behavior', 'static')),
    'schema-v3 static movement can contain a valid learned rotation');
  perform tests.check(not private.valid_movement_template(v_v3 || '{"unexpected":true}'::jsonb),
    'schema-v3 unknown keys are rejected');
  perform tests.check(not private.valid_movement_template(jsonb_set(v_v3,
    '{capture_version}', '2'::jsonb)),
    'schema-v3 unsupported capture version is rejected');
  perform tests.check(not private.valid_movement_template(jsonb_set(v_v3,
    '{duration_ms}', '"bad"'::jsonb)),
    'schema-v3 malformed duration is rejected');
  perform tests.check(not private.valid_movement_template(jsonb_set(v_v3,
    '{required_modalities}', '["hands","hands"]'::jsonb)),
    'schema-v3 duplicate modalities are rejected');
  perform tests.check(not private.valid_movement_template(jsonb_set(v_v3,
    '{normalization_metadata}', '[]'::jsonb)),
    'schema-v3 malformed normalization metadata is rejected');
  perform tests.check(not private.valid_movement_template(jsonb_set(v_v3,
    '{prop_events}', '{}'::jsonb)),
    'schema-v3 malformed prop events are rejected');
  perform tests.check(not private.valid_movement_template(jsonb_set(v_v3,
    '{feature_capabilities,prop_rotation}', '"false"'::jsonb)),
    'schema-v3 rotation capability must be boolean');
  perform tests.check(not private.valid_movement_template(jsonb_set(v_v3,
    '{canonical_sequence}', '[]'::jsonb)),
    'schema-v3 canonical sequence must contain 32 samples');
  perform tests.check(not private.valid_movement_template(v_v1 || jsonb_build_object('movement_behavior', 'static')),
    'schema-v1 does not gain schema-v3 fields');
  perform tests.check(not private.valid_movement_template(v_v2 || jsonb_build_object('movement_behavior', 'static')),
    'schema-v2 does not gain schema-v3 fields');
  perform tests.check(private.valid_movement_template(jsonb_set(v_v3, '{reference_count}', '1'::jsonb)),
    'static schema-v3 is accepted with one reference');
  perform tests.check(not private.valid_movement_template(jsonb_set(v_v3, '{reference_count}', '0'::jsonb)),
    'static schema-v3 still needs a reference');
  perform tests.check(not private.valid_movement_template(jsonb_set(v_v1, '{reference_count}', '1'::jsonb)),
    'dynamic schema-v1 still needs two references');
  perform tests.check(not private.valid_movement_template(jsonb_set(v_v2, '{reference_count}', '1'::jsonb)),
    'dynamic schema-v2 still needs two references');
  perform tests.check(not private.valid_movement_template(jsonb_set(v_v3, '{reference_count}', '11'::jsonb)),
    'static schema-v3 keeps the ten-reference maximum');

  perform tests.expect_error(format(
    'select public.create_custom_movement(%L,%L,%L,%L,%L,%L,%L,%L::jsonb,null)',
    'cmovInvalid3', 'crevInvalid3', 'trainee', 'Static hold', '', 'Easy', 'bottle',
    v_v3 - 'movement_behavior'), 'malformed', 'create RPC rejects malformed schema-v3 template');
  perform public.create_custom_movement('cmovStatic3', 'crevStatic3', 'trainee',
    'Static hold', '', 'Easy', 'bottle', v_v3, null);
  perform tests.check((select count(*) from public.custom_movements where id = 'cmovStatic3') = 1,
    'create RPC inserts schema-v3 static movement');
  perform tests.check((select template from public.custom_movement_revisions
    where id = 'crevStatic3') = v_v3,
    'create RPC inserts the unmodified schema-v3 static revision');
end $$;
select tests.login('22222222-2222-4222-8222-222222222222');
do $$
begin
  perform tests.check((select count(*) from public.custom_movements) = 0, 'custom movements are owner-private');
end $$;

-- A static schema-v3 template stores `rotation_trace: null`; assignment JSON
-- must keep that nested key so clients can parse the committed assignment.
select tests.login('11111111-1111-4111-8111-111111111111');
do $$
declare
  v_sequence jsonb;
  v_template jsonb;
  v jsonb;
begin
  select jsonb_agg(jsonb_build_object('timestamp_ms', i * 25, 'pose', '{}'::jsonb))
    into v_sequence from generate_series(0, 31) i;
  v_template := '{"schema_version":3,"capture_version":1,"duration_ms":2000,"reference_count":1,"required_modalities":["hands","prop_translation"],"normalization_metadata":{},"feature_capabilities":{"pose":false,"hands":true,"prop_translation":true,"release_catch":false,"prop_rotation":false},"variability_metadata":{},"prop_events":[],"movement_behavior":"static","rotation_trace":null}'::jsonb
    || jsonb_build_object('canonical_sequence', v_sequence);
  perform public.create_custom_movement('cmovTeach3', 'crevTeach3', 'teacher',
    'Teacher hold', '', 'Easy', 'bottle', v_template, null);
  v := public.create_custom_movement_assignment(current_setting('tests.group_id'),
    'cmovTeach3', 'crevTeach3', '{"type":"unlimited"}'::jsonb, null);
  perform tests.check(v -> 'movement_template' = v_template,
    'custom assignment response returns the stored schema-v3 template verbatim');
  perform tests.check(jsonb_typeof(v -> 'movement_template' -> 'rotation_trace') = 'null',
    'custom assignment response keeps the JSON null rotation trace');
  perform tests.check((v ->> 'max_score')::int = 12 and v ->> 'assessment_mode' = 'reference_matched',
    'custom assignment keeps reference-matched 12-point scoring');
  perform tests.check(not (v ? 'topic') and not (v ? 'publish_at'),
    'top-level null assignment columns are still compacted');
end $$;
select tests.login('22222222-2222-4222-8222-222222222222');
do $$
declare
  v jsonb;
begin
  select a into v from jsonb_array_elements(public.list_trainee_assignments(null)) a
    where a ->> 'movement_id' = 'cmovTeach3';
  perform tests.check(jsonb_typeof(v -> 'movement_template' -> 'rotation_trace') = 'null',
    'trainee assignment listing keeps the schema-v3 JSON null rotation trace');
end $$;

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------

select tests.login('22222222-2222-4222-8222-222222222222');
select public.send_chat_message('11111111-1111-4111-8111-111111111111', 'Hello', null);
select tests.login('33333333-3333-4333-8333-333333333333');
do $$
begin
  perform tests.check((select count(*) from public.chat_conversations) = 0, 'non-participants cannot read conversations');
  perform tests.check((select count(*) from public.chat_messages) = 0, 'non-participants cannot read messages');
end $$;
select tests.login('11111111-1111-4111-8111-111111111111');
do $$
begin
  perform tests.check((select (unread_counts ->> auth.uid()::text)::int from public.chat_conversations) = 1,
    'recipient unread count increments');
end $$;
insert into public.chat_blocks (blocker_id, blocked_id)
values ('11111111-1111-4111-8111-111111111111', '22222222-2222-4222-8222-222222222222');
select tests.login('22222222-2222-4222-8222-222222222222');
select tests.expect_error($$ select public.send_chat_message('11111111-1111-4111-8111-111111111111', 'Hi again', null) $$,
  'blocked', 'blocked users cannot send');
select tests.expect_error($$
  insert into public.chat_blocks (blocker_id, blocked_id)
  values ('11111111-1111-4111-8111-111111111111', '33333333-3333-4333-8333-333333333333')
$$, 'row-level security', 'users cannot create blocks for others');

-- ---------------------------------------------------------------------------
-- Account erasure preparation (service role)
-- ---------------------------------------------------------------------------

reset role;
do $$
declare
  v jsonb;
begin
  v := public.admin_prepare_account_erasure('22222222-2222-4222-8222-222222222222');
  perform tests.check(jsonb_array_length(v -> 'objects') >= 6, 'erasure lists owned storage prefixes');
  perform tests.check((select count(*) from public.chat_conversations
    where participant_a = 'deleted_user' or participant_b = 'deleted_user') = 1,
    'chat with an active user is archived anonymously');
  delete from auth.users where id = '22222222-2222-4222-8222-222222222222';
  perform tests.check((select count(*) from public.sessions
    where user_id = '22222222-2222-4222-8222-222222222222') = 0, 'user data cascades on deletion');
  perform tests.check((select count(*) from public.leaderboard
    where user_id = '22222222-2222-4222-8222-222222222222') = 0, 'leaderboard row cascades');
end $$;

rollback;
