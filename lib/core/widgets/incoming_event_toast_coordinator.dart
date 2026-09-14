import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

import '../../features/teacher/activity_center/teacher_activity_controller.dart';
import '../../features/trainee/activity_center/trainee_activity_controller.dart';
import '../../services/auth_service.dart';
import '../../services/message_unread_service.dart';
import 'elix_toast.dart';

/// Presents only events that appeared after each account's initial snapshots.
/// Stable activity/message IDs make rebuilds and profile updates harmless.
class IncomingEventToastCoordinator extends StatefulWidget {
  const IncomingEventToastCoordinator({super.key, required this.child});

  final Widget child;

  @override
  State<IncomingEventToastCoordinator> createState() =>
      _IncomingEventToastCoordinatorState();
}

class _IncomingEventToastCoordinatorState
    extends State<IncomingEventToastCoordinator> {
  String? _accountKey;
  MessageUnreadService? _messages;
  TeacherActivityController? _teacherActivities;
  TraineeActivityController? _traineeActivities;
  final Set<String> _seenMessageIds = <String>{};
  final Set<String> _seenTeacherActivityIds = <String>{};
  final Set<String> _seenTraineeActivityIds = <String>{};
  bool _teacherBaselineReady = false;
  bool _traineeBaselineReady = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthService>();
    final key = '${auth.currentUser?.id}:${auth.accountSessionGeneration}';
    if (_accountKey != key) {
      _accountKey = key;
      _seenMessageIds.clear();
      _seenTeacherActivityIds.clear();
      _seenTraineeActivityIds.clear();
      _teacherBaselineReady = false;
      _traineeBaselineReady = false;
    }
    final messages = context.read<MessageUnreadService>();
    _replaceListener(_messages, messages, _onMessages);
    _messages = messages;
    final teacherActivities = context.read<TeacherActivityController>();
    _replaceListener(
      _teacherActivities,
      teacherActivities,
      _onTeacherActivities,
    );
    _teacherActivities = teacherActivities;
    final traineeActivities = context.read<TraineeActivityController>();
    _replaceListener(
      _traineeActivities,
      traineeActivities,
      _onTraineeActivities,
    );
    _traineeActivities = traineeActivities;
    _establishActivityBaselines();
  }

  void _replaceListener(
    ChangeNotifier? oldNotifier,
    ChangeNotifier newNotifier,
    VoidCallback listener,
  ) {
    if (identical(oldNotifier, newNotifier)) return;
    oldNotifier?.removeListener(listener);
    newNotifier.addListener(listener);
  }

  void _establishActivityBaselines() {
    final teacher = _teacherActivities;
    if (teacher != null && !teacher.loading && !_teacherBaselineReady) {
      _seenTeacherActivityIds.addAll(
        teacher.activities.map((activity) => activity.id),
      );
      _teacherBaselineReady = true;
    }
    final trainee = _traineeActivities;
    if (trainee != null && !trainee.loading && !_traineeBaselineReady) {
      _seenTraineeActivityIds.addAll(
        trainee.activities.map((activity) => activity.id),
      );
      _traineeBaselineReady = true;
    }
  }

  void _onMessages() {
    final event = _messages?.latestIncomingMessage;
    if (!mounted || event == null || !_seenMessageIds.add(event.id)) return;
    ElixToast.showInfo(
      context,
      message: 'New message from ${event.senderName}.',
    );
  }

  void _onTeacherActivities() {
    final controller = _teacherActivities;
    if (!mounted || controller == null) return;
    if (!_teacherBaselineReady) {
      _establishActivityBaselines();
      return;
    }
    final newActivities = controller.activities
        .where((activity) => activity.type != TeacherActivityType.message)
        .where((activity) => _seenTeacherActivityIds.add(activity.id))
        .toList(growable: false);
    if (newActivities.isEmpty) return;
    final activity = newActivities.first;
    ElixToast.showInfo(
      context,
      message: _messageFor(activity.title, activity.description),
    );
  }

  void _onTraineeActivities() {
    final controller = _traineeActivities;
    if (!mounted || controller == null) return;
    if (!_traineeBaselineReady) {
      _establishActivityBaselines();
      return;
    }
    final newActivities = controller.activities
        .where((activity) => _seenTraineeActivityIds.add(activity.id))
        .toList(growable: false);
    if (newActivities.isEmpty) return;
    final activity = newActivities.first;
    ElixToast.showInfo(
      context,
      message: _messageFor(activity.title, activity.description),
    );
  }

  String _messageFor(String title, String description) =>
      description.isEmpty ? title : '$title — $description';

  @override
  void dispose() {
    _messages?.removeListener(_onMessages);
    _teacherActivities?.removeListener(_onTeacherActivities);
    _traineeActivities?.removeListener(_onTraineeActivities);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
