-- Private Storage buckets. Object names keep the former Firebase Storage
-- paths so every persisted storage_path remains valid; one bucket per file
-- category lets Storage enforce size and MIME limits.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('profile-images', 'profile-images', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('session-evidence', 'session-evidence', false, 262144, array['image/jpeg']),
  ('custom-movement-references', 'custom-movement-references', false, 524288, array['image/jpeg']),
  ('assignment-submissions', 'assignment-submissions', false, 52428800, array['video/mp4']),
  ('teacher-activity-demos', 'teacher-activity-demos', false, 52428800, array['video/mp4']),
  ('activity-learning-materials', 'activity-learning-materials', false, 104857600,
    array['application/pdf', 'image/jpeg', 'image/png', 'video/mp4'])
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- Assignment submission objects:
-- assignment_submissions/{teacher}/{group}/{assignment}/{trainee}/{attempt}.mp4
-- The canonical path is the identity; the attempt row is the authority.
-- ---------------------------------------------------------------------------

create or replace function private.submission_attempt_for_object(p_name text)
returns public.assignment_attempts language plpgsql stable security definer set search_path = '' as $$
declare
  v_parts text[] := string_to_array(p_name, '/');
  v_file text;
  v_row public.assignment_attempts;
begin
  if array_length(v_parts, 1) <> 6 or v_parts[1] <> 'assignment_submissions' then
    return null;
  end if;
  v_file := v_parts[6];
  if v_file !~ '^(review_sub_|activity_)[A-Za-z0-9_-]+\.mp4$' then
    return null;
  end if;
  select * into v_row from public.assignment_attempts
  where id = left(v_file, char_length(v_file) - 4)
    and teacher_id::text = v_parts[2] and group_id = v_parts[3]
    and assignment_id = v_parts[4] and trainee_id::text = v_parts[5]
    and attempt_kind = 'teacher_review_submission'
    and origin = 'teacher_created' and assessment_mode = 'teacher_reviewed';
  return v_row;
end;
$$;

create or replace function private.can_write_submission_object(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_row public.assignment_attempts := private.submission_attempt_for_object(p_name);
begin
  return v_row.id is not null
    and v_row.trainee_id = auth.uid()
    and v_row.status in ('draft', 'in_progress')
    and v_row.abandoned_at is null
    and v_row.video_storage_path is null
    and (
      (v_row.activity_assessment_snapshot is not null and v_row.recording_started_at is not null)
      or private.is_approved_member(v_row.group_id, v_row.trainee_id, v_row.teacher_id)
    );
end;
$$;

create or replace function private.can_read_submission_object(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_row public.assignment_attempts := private.submission_attempt_for_object(p_name);
  v_canonical boolean;
begin
  if v_row.id is null then
    return false;
  end if;
  v_canonical := v_row.id = 'review_sub_' || v_row.assignment_id || '_' || v_row.trainee_id;
  return (v_row.trainee_id = auth.uid() and (not v_canonical or v_row.status <> 'unsubmitting'))
    or (v_row.teacher_id = auth.uid() and private.is_teacher()
      and v_row.status in ('submitted', 'approved', 'needs_retry', 'checked'));
end;
$$;

create or replace function private.can_delete_submission_object(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare
  v_row public.assignment_attempts := private.submission_attempt_for_object(p_name);
  v_canonical boolean;
begin
  if v_row.id is null then
    return false;
  end if;
  v_canonical := v_row.id = 'review_sub_' || v_row.assignment_id || '_' || v_row.trainee_id;
  if v_row.trainee_id = auth.uid() then
    if v_canonical then
      return v_row.status = 'unsubmitting'
        or (v_row.status = 'in_progress' and v_row.draft_cleanup_started_at is not null)
        or v_row.video_storage_path is null;
    end if;
    -- Non-canonical: the Trainee may remove an object no longer referenced
    -- as a live video (failed upload, abandoned or server-retired).
    return v_row.activity_assessment_snapshot is null
      or v_row.abandoned_at is not null
      or v_row.video_storage_path is null;
  end if;
  return v_row.teacher_id = auth.uid() and private.is_teacher()
    and (v_row.status in ('submitted', 'approved', 'needs_retry', 'checked')
      or v_row.abandoned_at is not null);
end;
$$;

-- Teacher demonstrations: the owning Teacher, or a Trainee currently
-- approved in one of that Teacher's classrooms.
create or replace function private.can_read_teacher_demo(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select (storage.foldername(p_name))[1] = 'teacher_activity_demos'
    and storage.filename(p_name) ~ '^[A-Za-z0-9_-]+\.mp4$'
    and (
      ((storage.foldername(p_name))[2] = auth.uid()::text and private.is_teacher())
      or exists (
        select 1 from public.group_memberships m
        join public.groups g on g.id = m.group_id
        where m.trainee_id = auth.uid() and m.status = 'approved'
          and m.teacher_id::text = (storage.foldername(p_name))[2]
          and g.teacher_id = m.teacher_id
      )
    )
$$;

create or replace function private.can_write_teacher_demo(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select (storage.foldername(p_name))[1] = 'teacher_activity_demos'
    and (storage.foldername(p_name))[2] = auth.uid()::text
    and private.is_verified_teacher()
    and storage.filename(p_name) ~ '^[A-Za-z0-9_-]+\.mp4$'
    and (
      array_length(storage.foldername(p_name), 1) = 2
      or (array_length(storage.foldername(p_name), 1) = 4
        and (storage.foldername(p_name))[3] = 'assignments'
        and private.valid_doc_id((storage.foldername(p_name))[4]))
    )
$$;

-- Learning-material staging: exactly the server-reserved, unexpired path.
create or replace function private.can_write_material_staging(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.activity_material_uploads u
    where u.staging_path = p_name and u.owner_teacher_id = auth.uid()
      and u.state = 'staging' and u.expires_at > now()
  )
$$;

create or replace function private.can_read_material_object(p_name text)
returns boolean language sql stable security definer set search_path = '' as $$
  select (storage.foldername(p_name))[1] = 'activity_learning_materials'
    and array_length(storage.foldername(p_name), 1) = 2
    and private.can_read_learning_material((storage.foldername(p_name))[2], storage.filename(p_name))
$$;

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------

-- Profile avatars: any signed-in user may view; only the owner writes under
-- users/{uid}/profile/.
create policy profile_images_select on storage.objects
  for select to authenticated using (bucket_id = 'profile-images');
create policy profile_images_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'profile-images'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'profile'
    and array_length(storage.foldername(name), 1) = 3
  );
create policy profile_images_update on storage.objects
  for update to authenticated
  using (bucket_id = 'profile-images' and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[1] = 'users' and (storage.foldername(name))[3] = 'profile')
  with check (bucket_id = 'profile-images' and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[1] = 'users' and (storage.foldername(name))[3] = 'profile');
create policy profile_images_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'profile-images' and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'profile');

-- Session evidence: owner, or a Teacher with a current evidence grant /
-- classroom authorization while the Trainee's evidence consent is on.
create policy session_evidence_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'session-evidence'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[3] = 'session_evidence'
    and storage.filename(name) ~ '^[^/]+\.jpg$'
    and (
      (storage.foldername(name))[2] = auth.uid()::text
      or private.teacher_has_evidence_access(((storage.foldername(name))[2])::uuid)
    )
  );
create policy session_evidence_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'session-evidence'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'session_evidence'
    and array_length(storage.foldername(name), 1) = 3
    and storage.filename(name) ~ '^[A-Za-z0-9_-]+\.jpg$'
  );
create policy session_evidence_update on storage.objects
  for update to authenticated
  using (bucket_id = 'session-evidence' and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'session_evidence')
  with check (bucket_id = 'session-evidence' and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'session_evidence'
    and storage.filename(name) ~ '^[A-Za-z0-9_-]+\.jpg$');
create policy session_evidence_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'session-evidence' and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'session_evidence');

-- Custom movement reference stills: owner only.
create policy custom_references_select on storage.objects
  for select to authenticated
  using (bucket_id = 'custom-movement-references' and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'custom_movement_references');
create policy custom_references_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'custom-movement-references'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'custom_movement_references'
    and array_length(storage.foldername(name), 1) = 3
    and storage.filename(name) ~ '^[A-Za-z0-9_-]+_[A-Za-z0-9_-]+\.jpg$'
  );
create policy custom_references_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'custom-movement-references' and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
    and (storage.foldername(name))[3] = 'custom_movement_references');

-- Assignment submissions.
create policy assignment_submissions_select on storage.objects
  for select to authenticated
  using (bucket_id = 'assignment-submissions' and private.can_read_submission_object(name));
create policy assignment_submissions_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'assignment-submissions' and private.can_write_submission_object(name));
create policy assignment_submissions_update on storage.objects
  for update to authenticated
  using (bucket_id = 'assignment-submissions' and private.can_write_submission_object(name))
  with check (bucket_id = 'assignment-submissions' and private.can_write_submission_object(name));
create policy assignment_submissions_delete on storage.objects
  for delete to authenticated
  using (bucket_id = 'assignment-submissions' and private.can_delete_submission_object(name));

-- Teacher Activity demonstrations (immutable; cleanup is server-side).
create policy teacher_demos_select on storage.objects
  for select to authenticated
  using (bucket_id = 'teacher-activity-demos' and private.can_read_teacher_demo(name));
create policy teacher_demos_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'teacher-activity-demos' and private.can_write_teacher_demo(name));

-- Learning materials: write-only reserved staging; published objects are
-- written by the admin Edge Function and read per assignment audience.
create policy material_staging_insert on storage.objects
  for insert to authenticated
  with check (bucket_id = 'activity-learning-materials' and private.can_write_material_staging(name));
create policy material_objects_select on storage.objects
  for select to authenticated
  using (bucket_id = 'activity-learning-materials' and private.can_read_material_object(name));

-- ---------------------------------------------------------------------------
-- Account erasure (service role only, called by the admin Edge Function
-- before deleting the auth user; row data then cascades from auth.users).
-- ---------------------------------------------------------------------------

create or replace function public.admin_prepare_account_erasure(p_uid uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_objects jsonb := '[]'::jsonb;
begin
  update public.profiles set lifecycle_state = 'deleting' where id = p_uid;
  perform private.archive_chat_for_account_erasure(p_uid);
  delete from public.chat_blocks where blocker_id = p_uid or blocked_id = p_uid;
  -- Consumed codes keep their audit facts; creator-linked personal data goes.
  delete from public.teacher_access_codes where created_by = p_uid and not consumed;
  update public.teacher_access_codes set note = null where created_by = p_uid;

  v_objects := jsonb_build_array(
    jsonb_build_object('bucket', 'profile-images', 'prefix', 'users/' || p_uid || '/profile/'),
    jsonb_build_object('bucket', 'session-evidence', 'prefix', 'users/' || p_uid || '/session_evidence/'),
    jsonb_build_object('bucket', 'custom-movement-references',
      'prefix', 'users/' || p_uid || '/custom_movement_references/'),
    jsonb_build_object('bucket', 'assignment-submissions', 'prefix', 'assignment_submissions/' || p_uid || '/'),
    jsonb_build_object('bucket', 'teacher-activity-demos', 'prefix', 'teacher_activity_demos/' || p_uid || '/'),
    jsonb_build_object('bucket', 'activity-learning-materials',
      'prefix', 'activity_material_staging/' || p_uid || '/')
  );
  v_objects := v_objects || coalesce((
    select jsonb_agg(jsonb_build_object('bucket', 'assignment-submissions', 'path',
      'assignment_submissions/' || a.teacher_id || '/' || a.group_id || '/' || a.assignment_id
        || '/' || a.trainee_id || '/' || a.id || '.mp4'))
    from public.assignment_attempts a
    where a.trainee_id = p_uid and a.attempt_kind = 'teacher_review_submission'
  ), '[]'::jsonb);
  v_objects := v_objects || coalesce((
    select jsonb_agg(jsonb_build_object('bucket', 'activity-learning-materials',
      'prefix', 'activity_learning_materials/' || a.id || '/'))
    from public.group_assignments a where a.teacher_id = p_uid
  ), '[]'::jsonb);
  return jsonb_build_object('objects', v_objects);
end;
$$;
