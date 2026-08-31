/// Canonical Cloud Firestore collection ids used by ELIXR clients.
abstract final class FirestoreCollections {
  static const users = 'users';
  static const sessions = 'sessions';
  static const feedbacks = 'feedbacks';
  static const leaderboard = 'leaderboard';
  static const leaderboardProcessedSessions = 'leaderboard_processed_sessions';
  static const dailyQuestBoards = 'daily_quest_boards';
  static const dailyQuestClaims = 'daily_quest_claims';
  static const achievementClaims = 'achievement_claims';
  static const userCosmetics = 'user_cosmetics';
  static const publicProfiles = 'public_profiles';
  static const profileVisits = 'profile_visits';
  static const teacherInvites = 'teacher_invites';
  static const teacherAccessCodes = 'teacher_access_codes';
  static const teacherStudentLinks = 'teacher_student_links';
  static const teacherCoachingNotes = 'teacher_coaching_notes';
  static const chatUserDirectory = 'chat_user_directory';
  static const chatConversations = 'chat_conversations';
  static const chatMessages = 'messages';
  static const chatBlocks = 'chat_blocks';
  static const chatBlockedUsers = 'blocked_users';
  static const groups = 'groups';
  static const groupInvites = 'group_invites';
  static const groupMemberships = 'group_memberships';
  static const classroomTeacherAccess = 'classroom_teacher_access';
  static const trainingPlans = 'training_plans';
  static const teacherMovements = 'teacher_movements';
  static const groupAssignments = 'group_assignments';

  /// Private subcollection under each group assignment, keyed by trainee UID.
  static const assignmentRecipients = 'assignment_recipients';
  static const assignmentAttempts = 'assignment_attempts';

  /// Subcollection under [teacherMovements] for immutable published revisions.
  static const teacherMovementRevisions = 'revisions';
}
