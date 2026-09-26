-- Classroom domain: Teacher rosters, classrooms, announcements, Teacher and
-- custom movements, assignments, attempts, Class Challenges and learning
-- materials. Tables are read under RLS; mutations are RPCs (next migrations).

-- ---------------------------------------------------------------------------
-- Invite codes (roster + classroom) share one namespace.
-- ---------------------------------------------------------------------------

create table public.teacher_invites (
  code text primary key check (private.is_coach_code(code)),
  teacher_id uuid not null references auth.users (id) on delete cascade,
  teacher_display_name text not null check (char_length(teacher_display_name) between 1 and 80),
  created_at timestamptz not null default now()
);
create index teacher_invites_teacher_idx on public.teacher_invites (teacher_id);

create table public.teacher_student_links (
  id text primary key,
  teacher_id uuid not null references auth.users (id) on delete cascade,
  trainee_id uuid not null references auth.users (id) on delete cascade,
  teacher_display_name text not null,
  trainee_display_name text not null,
  status text not null check (status in ('pending', 'approved', 'rejected', 'cancelled', 'revoked')),
  invite_id text,
  request_version int,
  progress_access text not null default 'none' check (progress_access in ('none', 'granted')),
  progress_access_version int,
  progress_access_granted_at timestamptz,
  evidence_access text check (evidence_access is null or evidence_access = 'granted'),
  evidence_access_version int,
  evidence_access_granted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (id = teacher_id || '_' || trainee_id),
  check (teacher_id <> trainee_id),
  check (
    (progress_access = 'none' and progress_access_version is null and progress_access_granted_at is null)
    or (progress_access = 'granted' and progress_access_version = 1
      and progress_access_granted_at is not null and status = 'approved')
  ),
  check (
    (evidence_access is null and evidence_access_version is null and evidence_access_granted_at is null)
    or (evidence_access = 'granted' and evidence_access_version = 1
      and evidence_access_granted_at is not null and progress_access = 'granted')
  )
);
create index teacher_student_links_teacher_idx on public.teacher_student_links (teacher_id);
create index teacher_student_links_trainee_idx on public.teacher_student_links (trainee_id);

create table public.groups (
  id text primary key check (private.valid_doc_id(id)),
  teacher_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80 and name ~ '\S'),
  section text check (section is null or private.bounded_text(section, 80)),
  schedule text check (schedule is null or private.bounded_text(schedule, 120)),
  status text not null default 'active' check (status in ('active', 'archived')),
  schema_version int not null default 2,
  invite_code text,
  pinned_announcement_id text,
  pinned_announcement_at timestamptz,
  deletion_state text check (deletion_state is null or deletion_state = 'deleting'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((pinned_announcement_id is null) = (pinned_announcement_at is null))
);
create index groups_teacher_created_idx on public.groups (teacher_id, created_at desc);

create table public.group_invites (
  code text primary key check (private.is_coach_code(code)),
  group_id text not null references public.groups (id) on delete cascade,
  teacher_id uuid not null references auth.users (id) on delete cascade,
  teacher_display_name text not null check (char_length(teacher_display_name) between 1 and 80),
  created_at timestamptz not null default now()
);

-- Trainee-observable classroom lifecycle (no classroom metadata), so an
-- archived classroom can be signalled without exposing the archived row.
create table public.group_lifecycle (
  group_id text primary key references public.groups (id) on delete cascade,
  status text not null check (status in ('active', 'archived')),
  updated_at timestamptz not null default now()
);

create table public.group_memberships (
  id text primary key,
  group_id text not null references public.groups (id) on delete cascade,
  teacher_id uuid not null references auth.users (id) on delete cascade,
  trainee_id uuid not null references auth.users (id) on delete cascade,
  teacher_display_name text not null,
  trainee_display_name text not null,
  status text not null check (status in ('pending', 'approved', 'rejected', 'cancelled', 'removed')),
  invite_id text,
  request_version int,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (id = group_id || '_' || trainee_id),
  check (teacher_id <> trainee_id)
);
create index group_memberships_group_status_idx on public.group_memberships (group_id, status, created_at desc);
create index group_memberships_trainee_idx on public.group_memberships (trainee_id, created_at desc);
create index group_memberships_teacher_idx on public.group_memberships (teacher_id, group_id, created_at desc);

create table public.group_announcements (
  id text primary key check (private.valid_doc_id(id)),
  group_id text not null references public.groups (id) on delete cascade,
  teacher_id uuid not null references auth.users (id) on delete cascade,
  title text not null check (private.bounded_text(title, 120)),
  body text not null check (private.bounded_text(body, 2000)),
  created_at timestamptz not null default now(),
  edited_at timestamptz,
  publish_at timestamptz,
  trainee_visible boolean not null default true,
  schema_version int not null default 1
);
create index group_announcements_group_created_idx
  on public.group_announcements (group_id, created_at desc, id desc);
create index group_announcements_due_idx
  on public.group_announcements (publish_at) where trainee_visible = false;

-- ---------------------------------------------------------------------------
-- Movements
-- ---------------------------------------------------------------------------

create table public.teacher_movements (
  id text primary key check (private.valid_doc_id(id)),
  teacher_id uuid not null references auth.users (id) on delete cascade,
  title text not null check (private.bounded_text(title, 80)),
  status text not null default 'active' check (status in ('active', 'archived')),
  current_revision_id text not null,
  schema_version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index teacher_movements_teacher_idx on public.teacher_movements (teacher_id);

create table public.teacher_movement_revisions (
  id text primary key check (private.valid_doc_id(id)),
  movement_id text not null references public.teacher_movements (id) on delete cascade,
  teacher_id uuid not null references auth.users (id) on delete cascade,
  schema_version int not null,
  assessment_mode text not null,
  spec jsonb not null,
  created_at timestamptz not null default now()
);
create index teacher_movement_revisions_movement_idx on public.teacher_movement_revisions (movement_id);

create table public.custom_movements (
  id text primary key check (private.valid_doc_id(id)),
  owner_uid uuid not null references auth.users (id) on delete cascade,
  owner_role text not null check (owner_role in ('teacher', 'trainee')),
  name text not null check (private.bounded_text(name, 80)),
  description text not null default '' check (char_length(description) <= 500),
  difficulty text not null check (difficulty in ('Easy', 'Medium', 'Hard')),
  prop_type text not null check (prop_type in ('bottle', 'shaker')),
  status text not null default 'active' check (status in ('active', 'archived')),
  active_revision_id text not null,
  schema_version int not null default 1,
  reference_image_storage_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index custom_movements_owner_idx on public.custom_movements (owner_uid);

create table public.custom_movement_revisions (
  id text primary key check (private.valid_doc_id(id)),
  movement_id text not null references public.custom_movements (id) on delete cascade,
  owner_uid uuid not null references auth.users (id) on delete cascade,
  owner_role text not null,
  schema_version int not null default 1,
  template jsonb not null,
  created_at timestamptz not null default now()
);
create index custom_movement_revisions_movement_idx on public.custom_movement_revisions (movement_id);

create table public.custom_movement_results (
  id text primary key references public.sessions (id) on delete cascade,
  owner_uid uuid not null references auth.users (id) on delete cascade,
  movement_id text not null references public.custom_movements (id) on delete cascade,
  revision_id text not null references public.custom_movement_revisions (id) on delete cascade,
  result_type text not null check (result_type = 'personal_practice'),
  total_score double precision not null check (total_score between 0 and 100),
  component_scores jsonb not null default '{}'::jsonb,
  feedback jsonb not null default '[]'::jsonb,
  awards_global_xp boolean not null default false check (awards_global_xp = false),
  created_at timestamptz not null default now()
);
create index custom_movement_results_owner_idx on public.custom_movement_results (owner_uid);

-- ---------------------------------------------------------------------------
-- Assignments and attempts
-- ---------------------------------------------------------------------------

create table public.group_assignments (
  id text primary key check (private.valid_doc_id(id)),
  teacher_id uuid not null references auth.users (id) on delete cascade,
  group_id text not null references public.groups (id) on delete cascade,
  movement_id text not null,
  revision_id text not null,
  origin text not null check (origin in ('official_elixr', 'teacher_created')),
  assessment_mode text not null
    check (assessment_mode in ('official_guided', 'teacher_reviewed', 'reference_matched', 'template_scored')),
  status text not null check (status in ('draft', 'scheduled', 'active', 'archived')),
  display_title text not null check (private.bounded_text(display_title, 80)),
  teacher_display_name text not null,
  group_name text not null,
  display_instructions text check (display_instructions is null or private.bounded_text(display_instructions, 2000)),
  display_safety_guidance text check (display_safety_guidance is null or private.bounded_text(display_safety_guidance, 1000)),
  allowed_prop text check (allowed_prop is null or allowed_prop in ('bottle', 'shaker', 'bottle_and_shaker')),
  official_movement_name text,
  due_at timestamptz,
  publish_at timestamptz,
  topic text check (topic is null or private.bounded_text(topic, 80)),
  max_score int check (max_score is null or max_score between 1 and 100),
  grading_locked boolean,
  grading_locked_at timestamptz,
  audience_type text check (audience_type is null or audience_type in ('entire_class', 'selected_students', 'individual_student')),
  configuration_revision int,
  activity_assessment jsonb,
  attempt_policy jsonb,
  movement_template jsonb,
  assessment_spec jsonb,
  deletion_state text check (deletion_state is null or deletion_state = 'deleting'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'scheduled') = (publish_at is not null)),
  check (due_at is null or publish_at is null or due_at > publish_at),
  check ((coalesce(grading_locked, false)) = (grading_locked_at is not null))
);
create index group_assignments_group_idx on public.group_assignments (group_id, teacher_id);
create index group_assignments_teacher_movement_idx on public.group_assignments (teacher_id, movement_id);

create table public.assignment_recipients (
  assignment_id text not null references public.group_assignments (id) on delete cascade,
  trainee_id uuid not null references auth.users (id) on delete cascade,
  group_id text not null,
  teacher_id uuid not null,
  audience_type text not null check (audience_type in ('selected_students', 'individual_student')),
  schema_version int not null default 1,
  created_at timestamptz not null default now(),
  primary key (assignment_id, trainee_id)
);
create index assignment_recipients_trainee_idx on public.assignment_recipients (trainee_id);

create table public.assignment_deadline_overrides (
  assignment_id text not null references public.group_assignments (id) on delete cascade,
  trainee_id uuid not null references auth.users (id) on delete cascade,
  group_id text not null,
  teacher_id uuid not null,
  due_at timestamptz not null,
  schema_version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (assignment_id, trainee_id)
);

create table public.assignment_attempts (
  id text primary key check (private.valid_doc_id(id)),
  trainee_id uuid not null references auth.users (id) on delete cascade,
  teacher_id uuid not null references auth.users (id) on delete cascade,
  group_id text not null,
  assignment_id text not null references public.group_assignments (id) on delete cascade,
  movement_id text not null,
  revision_id text not null,
  origin text not null,
  assessment_mode text not null,
  attempt_kind text not null check (attempt_kind in (
    'practice_pointer', 'teacher_review_draft', 'teacher_review_submission', 'reference_match'
  )),
  status text not null check (status in (
    'draft', 'in_progress', 'submitted', 'unsubmitting', 'approved', 'needs_retry', 'checked'
  )),
  awards_global_xp boolean not null default false check (awards_global_xp = false),
  created_at timestamptz not null default now(),
  source_session_id text,
  assessment_version int,
  rubric jsonb,
  rubric_total int,
  performance_level text,
  duration_seconds int,
  prop_type text,
  completed_at timestamptz,
  supersedes_attempt_id text,
  attempt_number int,
  reservation_request_id text,
  assignment_configuration_revision int,
  activity_assessment_snapshot jsonb,
  recording_started_at timestamptz,
  video_storage_path text,
  video_content_type text,
  video_size_bytes int,
  video_duration_ms int,
  draft_saved_at timestamptz,
  draft_cleanup_started_at timestamptz,
  submitted_at timestamptz,
  video_expires_at timestamptz,
  video_deleted_at timestamptz,
  abandoned_at timestamptz,
  deletion_failed boolean,
  deletion_failed_at timestamptz,
  review_verdict text,
  review_feedback text check (review_feedback is null or char_length(review_feedback) <= 1000),
  reviewed_at timestamptz,
  grade_score int,
  grade_max_score int,
  checked_at timestamptz,
  criterion_scores jsonb,
  review_updated_at timestamptz,
  review_revision int,
  result_sent_revision int,
  result_sent_at timestamptz,
  result_message_id text,
  reference_total int check (reference_total is null or reference_total between 0 and 12),
  reference_max_total int,
  reference_component_scores jsonb,
  check (video_storage_path is null
    or video_storage_path = 'assignment_submissions/' || teacher_id || '/' || group_id || '/'
      || assignment_id || '/' || trainee_id || '/' || id || '.mp4'),
  check (video_size_bytes is null or video_size_bytes between 1 and 52428800),
  check (video_duration_ms is null or video_duration_ms between 1 and 60000),
  check (grade_score is null or (grade_max_score between 1 and 100 and grade_score between 0 and grade_max_score))
);
create index assignment_attempts_assignment_trainee_idx on public.assignment_attempts (assignment_id, trainee_id);
create index assignment_attempts_teacher_idx on public.assignment_attempts (teacher_id, assignment_id);
create index assignment_attempts_trainee_idx on public.assignment_attempts (trainee_id);

-- Server-owned limit ledger. Never exposed to clients.
create table public.assignment_attempt_states (
  id text primary key,
  state_kind text not null check (state_kind in ('teacher_activity', 'official_assignment')),
  assignment_id text not null references public.group_assignments (id) on delete cascade,
  trainee_id uuid not null references auth.users (id) on delete cascade,
  teacher_id uuid not null,
  group_id text not null,
  consumed_count int not null default 0 check (consumed_count >= 0),
  next_ordinal int not null default 0,
  active_attempt_id text,
  active_request_id text,
  active_consumed boolean,
  graded boolean not null default false,
  latest_submission_id text,
  latest_submission_ordinal int,
  updated_at timestamptz not null default now(),
  check (id = assignment_id || '__' || trainee_id)
);

-- ---------------------------------------------------------------------------
-- Class Challenges (server-owned writes)
-- ---------------------------------------------------------------------------

create table public.class_challenges (
  id text primary key check (private.valid_doc_id(id)),
  group_id text not null references public.groups (id) on delete cascade,
  teacher_id uuid not null references auth.users (id) on delete cascade,
  teacher_display_name text not null,
  title text not null check (private.bounded_text(title, 80)),
  description text not null check (private.bounded_text(description, 500)),
  movement_name text not null check (private.is_official_movement(movement_name)),
  difficulty text not null check (private.bounded_text(difficulty, 20)),
  prop_type text not null,
  start_at timestamptz not null,
  deadline timestamptz not null,
  attempt_limit int check (attempt_limit is null or attempt_limit between 1 and 20),
  target_score int check (target_score is null or target_score between 0 and 12),
  scoring_mode text not null default 'rubric_total_v2' check (scoring_mode = 'rubric_total_v2'),
  max_score int not null default 12 check (max_score = 12),
  completed_count int not null default 0,
  top_score int,
  archived_at timestamptz,
  schema_version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (start_at < deadline),
  check (private.official_movement_supports_prop(movement_name, prop_type))
);
create index class_challenges_group_idx on public.class_challenges (group_id, teacher_id);

create table public.class_challenge_attempts (
  id text primary key,
  challenge_id text not null references public.class_challenges (id) on delete cascade,
  group_id text not null,
  teacher_id uuid not null,
  trainee_id uuid not null references auth.users (id) on delete cascade,
  attempt_number int not null,
  request_id text not null,
  movement_name text not null,
  prop_type text not null,
  status text not null check (status in ('in_progress', 'completed', 'abandoned')),
  started_at timestamptz not null default now(),
  session_id text,
  score int,
  completed_at timestamptz,
  abandoned_at timestamptz
);
create index class_challenge_attempts_challenge_idx on public.class_challenge_attempts (challenge_id, trainee_id);

create table public.class_challenge_participants (
  id text primary key,
  challenge_id text not null references public.class_challenges (id) on delete cascade,
  group_id text not null,
  teacher_id uuid not null,
  trainee_id uuid not null references auth.users (id) on delete cascade,
  attempts_started int not null default 0,
  active_attempt_id text,
  active_request_id text,
  updated_at timestamptz not null default now(),
  check (id = challenge_id || '__' || trainee_id)
);

create table public.class_challenge_results (
  id text primary key,
  challenge_id text not null references public.class_challenges (id) on delete cascade,
  group_id text not null,
  teacher_id uuid not null,
  trainee_id uuid not null references auth.users (id) on delete cascade,
  display_name text not null,
  profile_picture_url text,
  score int not null check (score between 0 and 12),
  best_attempt_number int not null,
  best_achieved_at timestamptz not null,
  session_id text not null,
  updated_at timestamptz not null default now(),
  check (id = challenge_id || '__' || trainee_id)
);
create index class_challenge_results_group_idx on public.class_challenge_results (group_id, teacher_id);

-- ---------------------------------------------------------------------------
-- Activity learning materials (server-owned; metadata served via RPCs)
-- ---------------------------------------------------------------------------

create table public.learning_materials (
  id text primary key,
  assignment_id text not null references public.group_assignments (id) on delete cascade,
  owner_teacher_id uuid not null references auth.users (id) on delete cascade,
  type text not null check (type in ('pdf', 'image', 'video', 'link')),
  display_name text not null check (private.bounded_text(display_name, 120)),
  external_url text check (external_url is null or char_length(external_url) <= 2048),
  storage_path text,
  detected_content_type text,
  size_bytes bigint,
  status text not null check (status in ('staging', 'ready', 'rejected', 'deleting')),
  rejection_reason text,
  request_id text,
  published_at timestamptz,
  deletion_requested_at timestamptz,
  schema_version int not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (assignment_id, request_id),
  check ((type = 'link') = (external_url is not null))
);

create table public.activity_material_uploads (
  upload_id text primary key,
  material_id text not null references public.learning_materials (id) on delete cascade,
  assignment_id text not null references public.group_assignments (id) on delete cascade,
  owner_teacher_id uuid not null references auth.users (id) on delete cascade,
  type text not null check (type in ('pdf', 'image', 'video')),
  display_name text not null,
  declared_content_type text not null,
  declared_size_bytes bigint not null check (declared_size_bytes > 0),
  staging_path text not null,
  state text not null check (state in ('staging', 'validating', 'ready', 'rejected', 'deleting')),
  rejection_reason text,
  request_id text not null,
  validation_started_at timestamptz,
  expires_at timestamptz not null,
  terminal_at timestamptz,
  created_at timestamptz not null default now(),
  unique (assignment_id, request_id),
  check (staging_path = 'activity_material_staging/' || owner_teacher_id || '/' || assignment_id || '/' || upload_id)
);

-- ---------------------------------------------------------------------------
-- Authorization helpers (SECURITY DEFINER so policies can consult rows the
-- caller may not read directly; each takes only the caller's own identity).
-- ---------------------------------------------------------------------------

create or replace function private.is_approved_member(
  p_group_id text, p_trainee_id uuid, p_teacher_id uuid
) returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.group_memberships m
    join public.groups g on g.id = m.group_id
    where m.group_id = p_group_id and m.trainee_id = p_trainee_id
      and m.teacher_id = p_teacher_id and m.status = 'approved'
      and g.teacher_id = p_teacher_id
  )
$$;

create or replace function private.caller_is_group_teacher(p_group_id text)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_teacher() and exists (
    select 1 from public.groups g where g.id = p_group_id and g.teacher_id = auth.uid()
  )
$$;

create or replace function private.caller_is_approved_member(p_group_id text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.group_memberships m
    join public.groups g on g.id = m.group_id
    where m.group_id = p_group_id and m.trainee_id = auth.uid()
      and m.status = 'approved' and g.teacher_id = m.teacher_id
  )
$$;

-- Classroom authorization: the calling Teacher currently owns a classroom in
-- which the Trainee holds an approved membership.
create or replace function private.teacher_has_classroom_access(p_trainee_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_teacher() and exists (
    select 1 from public.group_memberships m
    join public.groups g on g.id = m.group_id
    where m.trainee_id = p_trainee_id and m.teacher_id = auth.uid()
      and g.teacher_id = auth.uid() and m.status = 'approved'
  )
$$;

create or replace function private.teacher_has_progress_access(p_trainee_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_teacher() and (
    exists (
      select 1 from public.teacher_student_links l
      where l.teacher_id = auth.uid() and l.trainee_id = p_trainee_id
        and l.status = 'approved' and l.progress_access = 'granted'
    )
    or private.teacher_has_classroom_access(p_trainee_id)
  )
$$;

-- Evidence also requires the Trainee's live privacy consent.
create or replace function private.teacher_has_evidence_access(p_trainee_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.is_teacher()
    and exists (
      select 1 from public.profiles p
      where p.id = p_trainee_id and p.session_evidence_enabled is true
    )
    and (
      exists (
        select 1 from public.teacher_student_links l
        where l.teacher_id = auth.uid() and l.trainee_id = p_trainee_id
          and l.status = 'approved' and l.progress_access = 'granted'
          and l.evidence_access = 'granted'
      )
      or private.teacher_has_classroom_access(p_trainee_id)
    )
$$;

create or replace function private.can_read_public_profile_details(p_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select p_user_id = auth.uid()
    or (
      private.is_product_participant(auth.uid())
      and exists (
        select 1 from public.public_profiles pp
        where pp.user_id = p_user_id and pp.visibility = 'public'
      )
    )
    or private.teacher_has_progress_access(p_user_id)
$$;

create policy public_profile_summaries_select on public.public_profile_summaries
  for select to authenticated using (private.can_read_public_profile_details(user_id));
create policy public_profile_sessions_select on public.public_profile_sessions
  for select to authenticated using (private.can_read_public_profile_details(user_id));

create or replace function private.assignment_is_published(
  p_status text, p_publish_at timestamptz
) returns boolean language sql stable as $$
  select p_status = 'active' or (p_status = 'scheduled' and p_publish_at <= now())
$$;

create or replace function private.assignment_audience_allows(
  p_assignment_id text, p_audience_type text, p_trainee_id uuid
) returns boolean language sql stable security definer set search_path = '' as $$
  select p_audience_type is null or p_audience_type = 'entire_class'
    or exists (
      select 1 from public.assignment_recipients r
      join public.group_assignments a on a.id = r.assignment_id
      where r.assignment_id = p_assignment_id and r.trainee_id = p_trainee_id
        and r.audience_type = a.audience_type and r.group_id = a.group_id
        and r.teacher_id = a.teacher_id
    )
$$;

-- Trainee visibility of an assignment. Archived assignments stay visible as
-- history (matching the former listTraineeAssignments Function).
create or replace function private.trainee_can_see_assignment(p_assignment_id text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.group_assignments a
    where a.id = p_assignment_id
      and coalesce(a.deletion_state, '') <> 'deleting'
      and (a.status = 'archived' or private.assignment_is_published(a.status, a.publish_at))
      and private.is_approved_member(a.group_id, auth.uid(), a.teacher_id)
      and private.assignment_audience_allows(a.id, a.audience_type, auth.uid())
  )
$$;

create or replace function private.effective_due_at(p_assignment_id text, p_trainee_id uuid)
returns timestamptz language sql stable security definer set search_path = '' as $$
  select case
    when o.due_at is not null and (a.due_at is null or o.due_at > a.due_at) then o.due_at
    else a.due_at
  end
  from public.group_assignments a
  left join public.assignment_deadline_overrides o
    on o.assignment_id = a.id and o.trainee_id = p_trainee_id
    and o.group_id = a.group_id and o.teacher_id = a.teacher_id
  where a.id = p_assignment_id
$$;

create or replace function private.challenge_viewer(p_group_id text, p_teacher_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select (private.is_teacher() and p_teacher_id = auth.uid())
    or private.is_approved_member(p_group_id, auth.uid(), p_teacher_id)
$$;

-- ---------------------------------------------------------------------------
-- Lifecycle projection trigger
-- ---------------------------------------------------------------------------

create or replace function private.sync_group_lifecycle() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.group_lifecycle (group_id, status, updated_at)
  values (new.id, new.status, now())
  on conflict (group_id) do update set status = excluded.status, updated_at = now()
  where public.group_lifecycle.status is distinct from excluded.status;
  return new;
end;
$$;

create trigger groups_sync_lifecycle
  after insert or update of status on public.groups
  for each row execute function private.sync_group_lifecycle();

-- ---------------------------------------------------------------------------
-- Read policies
-- ---------------------------------------------------------------------------

alter table public.teacher_invites enable row level security;
alter table public.teacher_student_links enable row level security;
alter table public.groups enable row level security;
alter table public.group_invites enable row level security;
alter table public.group_lifecycle enable row level security;
alter table public.group_memberships enable row level security;
alter table public.group_announcements enable row level security;
alter table public.teacher_movements enable row level security;
alter table public.teacher_movement_revisions enable row level security;
alter table public.custom_movements enable row level security;
alter table public.custom_movement_revisions enable row level security;
alter table public.custom_movement_results enable row level security;
alter table public.group_assignments enable row level security;
alter table public.assignment_recipients enable row level security;
alter table public.assignment_deadline_overrides enable row level security;
alter table public.assignment_attempts enable row level security;
alter table public.assignment_attempt_states enable row level security;
alter table public.class_challenges enable row level security;
alter table public.class_challenge_attempts enable row level security;
alter table public.class_challenge_participants enable row level security;
alter table public.class_challenge_results enable row level security;
alter table public.learning_materials enable row level security;
alter table public.activity_material_uploads enable row level security;

-- Invite codes are bearer tokens: resolved only through RPCs, never listed.

create policy teacher_student_links_select on public.teacher_student_links
  for select to authenticated
  using ((teacher_id = auth.uid() and private.is_teacher()) or trainee_id = auth.uid());

create policy groups_select on public.groups
  for select to authenticated
  using (
    (teacher_id = auth.uid() and private.is_teacher())
    or (status = 'active' and private.is_approved_member(id, auth.uid(), teacher_id))
  );

create policy group_lifecycle_select on public.group_lifecycle
  for select to authenticated
  using (private.caller_is_group_teacher(group_id) or private.caller_is_approved_member(group_id));

create policy group_memberships_select on public.group_memberships
  for select to authenticated
  using (
    (teacher_id = auth.uid() and private.is_teacher())
    or trainee_id = auth.uid()
    or (status = 'approved' and private.is_approved_member(group_id, auth.uid(), teacher_id))
  );

create policy group_announcements_select on public.group_announcements
  for select to authenticated
  using (
    private.caller_is_group_teacher(group_id)
    or (
      trainee_visible
      and (publish_at is null or publish_at <= now())
      and exists (
        select 1 from public.groups g
        where g.id = group_announcements.group_id and g.status = 'active'
          and private.is_approved_member(g.id, auth.uid(), g.teacher_id)
      )
    )
  );

create policy teacher_movements_select on public.teacher_movements
  for select to authenticated using (teacher_id = auth.uid() and private.is_teacher());
create policy teacher_movement_revisions_select on public.teacher_movement_revisions
  for select to authenticated using (teacher_id = auth.uid() and private.is_teacher());

create policy custom_movements_select on public.custom_movements
  for select to authenticated using (owner_uid = auth.uid());
create policy custom_movement_revisions_select on public.custom_movement_revisions
  for select to authenticated using (owner_uid = auth.uid());
create policy custom_movement_results_select on public.custom_movement_results
  for select to authenticated using (owner_uid = auth.uid());

create policy group_assignments_select on public.group_assignments
  for select to authenticated
  using (
    (teacher_id = auth.uid() and private.is_teacher())
    or private.trainee_can_see_assignment(id)
  );

create policy assignment_recipients_select on public.assignment_recipients
  for select to authenticated
  using ((teacher_id = auth.uid() and private.is_teacher()) or trainee_id = auth.uid());

create policy assignment_deadline_overrides_select on public.assignment_deadline_overrides
  for select to authenticated
  using ((teacher_id = auth.uid() and private.is_teacher()) or trainee_id = auth.uid());

create policy assignment_attempts_select on public.assignment_attempts
  for select to authenticated
  using (trainee_id = auth.uid() or (teacher_id = auth.uid() and private.is_teacher()));

create policy class_challenges_select on public.class_challenges
  for select to authenticated using (private.challenge_viewer(group_id, teacher_id));
create policy class_challenge_attempts_select on public.class_challenge_attempts
  for select to authenticated
  using (
    private.challenge_viewer(group_id, teacher_id)
    and (teacher_id = auth.uid() or trainee_id = auth.uid())
  );
create policy class_challenge_participants_select on public.class_challenge_participants
  for select to authenticated
  using (
    private.challenge_viewer(group_id, teacher_id)
    and (teacher_id = auth.uid() or trainee_id = auth.uid())
  );
create policy class_challenge_results_select on public.class_challenge_results
  for select to authenticated using (private.challenge_viewer(group_id, teacher_id));
