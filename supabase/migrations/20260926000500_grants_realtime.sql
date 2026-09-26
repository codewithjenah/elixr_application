-- Least-privilege grants. Supabase grants broad table/function privileges to
-- anon and authenticated by default; RLS is authoritative, and these revokes
-- make the RPC-only write surface explicit as defense in depth.

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;

grant select on
  public.profiles,
  public.teacher_access_codes,
  public.sessions,
  public.feedbacks,
  public.leaderboard,
  public.leaderboard_processed_sessions,
  public.daily_quest_boards,
  public.daily_quest_claims,
  public.achievement_claims,
  public.user_cosmetics,
  public.public_profiles,
  public.public_profile_summaries,
  public.public_profile_sessions,
  public.public_profile_achievements,
  public.profile_visits,
  public.training_plans,
  public.teacher_student_links,
  public.groups,
  public.group_lifecycle,
  public.group_memberships,
  public.group_announcements,
  public.teacher_movements,
  public.teacher_movement_revisions,
  public.custom_movements,
  public.custom_movement_revisions,
  public.custom_movement_results,
  public.group_assignments,
  public.assignment_recipients,
  public.assignment_deadline_overrides,
  public.assignment_attempts,
  public.class_challenges,
  public.class_challenge_attempts,
  public.class_challenge_participants,
  public.class_challenge_results,
  public.chat_conversations,
  public.chat_messages,
  public.chat_blocks
to authenticated;

grant delete on public.teacher_access_codes to authenticated;
grant insert, delete on public.chat_blocks to authenticated;

-- Client RPCs.
grant execute on function
  public.create_own_profile(text, text, text, text, text, text, text),
  public.update_own_profile(jsonb),
  public.assert_teacher_authorized(),
  public.mint_teacher_access_code(text),
  public.save_session(text, jsonb, jsonb),
  public.clear_session_evidence_metadata(),
  public.award_session_xp(text, text, text),
  public.touch_leaderboard_presence(),
  public.sync_leaderboard_public_profile(text, text, boolean),
  public.leaderboard_rank(uuid, text),
  public.get_or_create_daily_quest_board(text[]),
  public.claim_daily_quest(text),
  public.claim_achievement(text),
  public.equip_border(text),
  public.ensure_public_profile_root(text, text, text),
  public.update_public_identity(text, text, boolean),
  public.set_public_profile_visibility(text),
  public.project_public_session(text),
  public.sync_public_profile_projections(),
  public.reconcile_public_evidence_availability(),
  public.record_profile_visit(uuid),
  public.upsert_training_plan(jsonb),
  public.delete_training_plan(text),
  public.rotate_roster_invite(),
  public.get_active_roster_invite(),
  public.revoke_roster_invite(),
  public.resolve_roster_code(text),
  public.request_teacher_join(text),
  public.transition_teacher_link(text, text),
  public.set_link_access(text, text, boolean),
  public.revoke_all_evidence_access(),
  public.create_group(text, text, text),
  public.update_group_details(text, text, text, text),
  public.set_group_status(text, text),
  public.rotate_group_invite(text),
  public.get_active_group_invite(text),
  public.resolve_group_invite(text),
  public.request_group_join(text),
  public.transition_group_membership(text, text),
  public.prepare_classroom_access_context(uuid, text),
  public.has_progress_access(uuid),
  public.create_announcement(text, text, text, timestamptz),
  public.update_announcement(text, text, text, timestamptz),
  public.delete_announcement(text),
  public.set_pinned_announcement(text, text),
  public.create_teacher_movement(text, jsonb, int),
  public.edit_teacher_movement(text, text, jsonb, int),
  public.archive_teacher_movement(text),
  public.delete_teacher_movement(text),
  public.create_custom_movement(text, text, text, text, text, text, text, jsonb, text),
  public.publish_custom_movement_revision(text, text, text, text, text, text, text, jsonb, text),
  public.archive_custom_movement(text),
  public.save_custom_movement_result(text, text, text, double precision, jsonb, jsonb, int),
  public.create_classroom_assignment(jsonb),
  public.create_custom_movement_assignment(text, text, text, jsonb, timestamptz),
  public.set_assignment_status(text, text),
  public.schedule_assignment_publication(text, timestamptz),
  public.update_assignment_settings(text, timestamptz, int, text),
  public.update_assignment_configuration(jsonb),
  public.update_teacher_activity_assignment(jsonb),
  public.set_deadline_override(text, uuid, timestamptz),
  public.clear_deadline_override(text, uuid),
  public.list_trainee_assignments(text),
  public.create_assignment_attempt(text, text, text, text, text),
  public.save_reference_match_attempt(text, int, text, jsonb),
  public.transition_trainee_attempt(text, text, jsonb),
  public.mark_attempt_video_state(text, boolean),
  public.save_teacher_review(text, int, text),
  public.mark_review_result_sent(text, text),
  public.review_teacher_submission(text, text, text),
  public.reserve_teacher_activity_attempt(text, text),
  public.consume_teacher_activity_attempt(text, text),
  public.abandon_teacher_activity_attempt(text, text),
  public.finalize_teacher_activity_attempt(text, text, text, text, int, int),
  public.turn_in_assignment_attempt(text, text),
  public.grade_teacher_activity_attempt(text, jsonb, text),
  public.complete_official_assignment_session(text, jsonb, jsonb),
  public.create_class_challenge(jsonb),
  public.update_class_challenge(text, jsonb),
  public.archive_class_challenge(text),
  public.delete_class_challenge(text, text),
  public.reserve_class_challenge_attempt(text, text),
  public.abandon_class_challenge_attempt(text, text),
  public.complete_class_challenge_attempt(text, text, text),
  public.begin_activity_material_upload(text, text, text, text, text, bigint),
  public.get_activity_material_upload_status(text),
  public.add_activity_learning_material_link(text, text, text, text),
  public.list_activity_learning_materials(text),
  public.list_trainee_activity_learning_materials(),
  public.request_activity_material_removal(text, text),
  public.send_chat_message(uuid, text, text),
  public.edit_chat_message(text, text, text),
  public.delete_chat_message(text, text),
  public.update_chat_read_state(text, text),
  public.search_chat_users(text),
  public.list_faculty_directory()
to authenticated;

-- Pre-registration access-code validation (the sign-up trigger remains the
-- authoritative, atomic consumption point).
grant execute on function public.check_teacher_access_code(text) to anon, authenticated;

-- Admin RPCs are callable only by the service role inside Edge Functions.
grant execute on function
  public.admin_claim_material_upload(text, uuid),
  public.admin_complete_material_upload(text, boolean, text, text, bigint, text),
  public.admin_finish_material_removal(text),
  public.admin_permanent_delete_assignment(uuid, text),
  public.admin_permanent_delete_classroom(uuid, text),
  public.admin_prepare_account_erasure(uuid)
to service_role;

-- Read-only authorization predicates evaluated inside RLS and Storage
-- policies as the `authenticated` role. Privileged private helpers (profile
-- creation, session insertion, chat archival, invite allocation) stay
-- executable only by the definer-owned RPCs above.
grant execute on function
  private.valid_doc_id(text),
  private.is_teacher(),
  private.is_verified_teacher(),
  private.is_trainee(uuid),
  private.is_product_participant(uuid),
  private.profile_role(uuid),
  private.email_verified(uuid),
  private.is_approved_member(text, uuid, uuid),
  private.caller_is_group_teacher(text),
  private.caller_is_approved_member(text),
  private.teacher_has_classroom_access(uuid),
  private.teacher_has_progress_access(uuid),
  private.teacher_has_evidence_access(uuid),
  private.can_read_public_profile_details(uuid),
  private.assignment_is_published(text, timestamptz),
  private.assignment_audience_allows(text, text, uuid),
  private.trainee_can_see_assignment(text),
  private.challenge_viewer(text, uuid),
  private.is_supported_chat_account(uuid),
  private.submission_attempt_for_object(text),
  private.can_write_submission_object(text),
  private.can_read_submission_object(text),
  private.can_delete_submission_object(text),
  private.can_read_teacher_demo(text),
  private.can_write_teacher_demo(text),
  private.can_write_material_staging(text),
  private.can_read_material_object(text),
  private.can_read_learning_material(text, text)
to authenticated;

-- ---------------------------------------------------------------------------
-- Realtime: tables with live UX (former Firestore snapshot listeners).
-- Postgres Changes are filtered by each subscriber's RLS policies.
-- ---------------------------------------------------------------------------

alter publication supabase_realtime add table
  public.leaderboard,
  public.daily_quest_claims,
  public.achievement_claims,
  public.user_cosmetics,
  public.public_profiles,
  public.public_profile_summaries,
  public.teacher_access_codes,
  public.teacher_student_links,
  public.groups,
  public.group_lifecycle,
  public.group_memberships,
  public.group_announcements,
  public.teacher_movements,
  public.custom_movements,
  public.custom_movement_results,
  public.group_assignments,
  public.assignment_attempts,
  public.class_challenges,
  public.class_challenge_participants,
  public.class_challenge_results,
  public.chat_conversations,
  public.chat_messages,
  public.chat_blocks;

-- ---------------------------------------------------------------------------
-- Scheduled maintenance (pg_cron is available on Supabase projects).
-- ---------------------------------------------------------------------------

create or replace function private.expire_material_uploads() returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_count int;
begin
  update public.learning_materials m set status = 'rejected', rejection_reason = 'expired',
    updated_at = now()
  from public.activity_material_uploads u
  where u.material_id = m.id and m.status = 'staging' and u.state = 'staging'
    and u.expires_at <= now();
  update public.activity_material_uploads set state = 'rejected', rejection_reason = 'expired',
    terminal_at = now()
  where state = 'staging' and expires_at <= now();
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

do $$
declare
  v_cron_available boolean;
begin
  begin
    select exists (select 1 from pg_available_extensions where name = 'pg_cron')
      into v_cron_available;
  exception when others then
    v_cron_available := false;
  end;
  if v_cron_available then
    create extension if not exists pg_cron;
    perform cron.schedule(
      'elixr-publish-scheduled-announcements', '* * * * *',
      'select private.publish_due_announcements()'
    );
    perform cron.schedule(
      'elixr-expire-material-uploads', '*/10 * * * *',
      'select private.expire_material_uploads()'
    );
  else
    raise notice 'pg_cron unavailable: scheduled announcements rely on read-time publish_at checks only';
  end if;
end;
$$;
