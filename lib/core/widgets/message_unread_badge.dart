import 'package:fluent_ui/fluent_ui.dart';

import '../constants/app_colors.dart';

class MessageUnreadBadge extends StatelessWidget {
  const MessageUnreadBadge({
    super.key,
    required this.count,
    this.compact = false,
  });

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final label = count > 99 ? '99+' : '$count';

    return Semantics(
      label: '$count unread ${count == 1 ? 'message' : 'messages'}',
      child: Container(
        constraints: BoxConstraints(minWidth: compact ? 16 : 20),
        height: compact ? 16 : 20,
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 9 : 10,
            height: 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
