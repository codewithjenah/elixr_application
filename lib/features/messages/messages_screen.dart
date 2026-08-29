import 'package:elixr_core/elixr_core.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/router/app_route_paths.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/elix_card.dart';
import '../../core/widgets/elix_dialog.dart';
import '../../core/widgets/elix_editorial_header.dart';
import '../../core/widgets/elix_scaffold_page.dart';
import '../../services/auth_service.dart';
import '../profile/profile_route_args.dart';
import 'messages_controller.dart';

String _profilePathForChatUser(BuildContext context, ChatUser user) {
  final viewerIsTeacher =
      context.read<AuthService>().currentUser?.isTeacher ?? false;
  return viewerIsTeacher
      ? AppRoutePaths.teacherProfile(user.id)
      : '/profile/${Uri.encodeComponent(user.id)}';
}

void _openChatUserProfile(BuildContext context, ChatUser user) {
  context.push(
    _profilePathForChatUser(context, user),
    extra: ProfileRouteArgs(
      displayName: user.displayName,
      profilePictureUrl: user.avatarUrl,
      role: user.role,
    ),
  );
}

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({
    super.key,
    this.initialUserId,
    this.initialDisplayName,
    this.initialRole,
    this.initialAvatarUrl,
  });

  final String? initialUserId;
  final String? initialDisplayName;
  final String? initialRole;
  final String? initialAvatarUrl;

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _searchController = TextEditingController();
  final _composerController = TextEditingController();
  final _messageScrollController = ScrollController();
  MessagesController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final authUser = context.read<AuthService>().currentUser;
    final userId = authUser?.id;
    if (authUser == null || userId == null) return;
    final controller = MessagesController(
      repository: context.read<ChatRepository>(),
      currentUser: ChatUser(
        id: userId,
        displayName: authUser.fullName,
        role: authUser.role,
        avatarUrl: authUser.profilePictureUrl,
      ),
    );
    _controller = controller;
    final targetId = widget.initialUserId?.trim();
    final targetName = widget.initialDisplayName?.trim();
    final targetRole = widget.initialRole;
    controller.start(
      initialUser:
          targetId != null &&
              targetId.isNotEmpty &&
              targetName != null &&
              targetName.isNotEmpty &&
              (targetRole == 'Teacher' || targetRole == 'Trainee')
          ? ChatUser(
              id: targetId,
              displayName: targetName,
              role: targetRole!,
              avatarUrl: widget.initialAvatarUrl,
            )
          : null,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _searchController.dispose();
    _composerController.dispose();
    _messageScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return const ElixScaffoldPage(content: Center(child: ProgressRing()));
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => ElixScaffoldPage(
        padding: EdgeInsets.zero,
        content: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.pageTopInset,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Container(
            decoration: AppTheme.panelDecoration(context),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 840;
                if (narrow) {
                  return controller.selectedUser == null
                      ? _PeoplePane(
                          controller: controller,
                          searchController: _searchController,
                        )
                      : _ConversationPane(
                          controller: controller,
                          composerController: _composerController,
                          scrollController: _messageScrollController,
                          showBack: true,
                        );
                }
                return Row(
                  children: [
                    SizedBox(
                      width: 370,
                      child: _PeoplePane(
                        controller: controller,
                        searchController: _searchController,
                      ),
                    ),
                    Container(
                      width: 1,
                      color: context.elixBorder.withValues(alpha: 0.5),
                    ),
                    Expanded(
                      child: _ConversationPane(
                        controller: controller,
                        composerController: _composerController,
                        scrollController: _messageScrollController,
                        showBack: false,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PeoplePane extends StatelessWidget {
  const _PeoplePane({required this.controller, required this.searchController});

  final MessagesController controller;
  final TextEditingController searchController;

  @override
  Widget build(BuildContext context) {
    final searching = searchController.text.trim().isNotEmpty;
    final unreadCount = controller.inbox.fold<int>(
      0,
      (total, conversation) =>
          total + conversation.unreadFor(controller.currentUser.id),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ElixEditorialHeader(
                heading: 'Messages',
                eyebrow: 'INBOX',
                subtitle: 'Connect with your teachers and trainees.',
                variant: ElixEditorialHeaderVariant.compact,
                leading: Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: context.isHighContrast
                        ? context.elixCardSurface
                        : context.elixColors.brandPrimary.withValues(
                            alpha: 0.14,
                          ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: context.isHighContrast
                          ? context.elixBorder
                          : context.elixColors.brandPrimary.withValues(
                              alpha: 0.28,
                            ),
                    ),
                  ),
                  child: Icon(
                    key: const ValueKey('messages-header-icon'),
                    FluentIcons.chat,
                    size: 20,
                    color: context.elixColors.brandPrimary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextBox(
                controller: searchController,
                placeholder: 'Find a Teacher or Trainee',
                prefix: const Padding(
                  padding: EdgeInsets.only(left: AppSpacing.sm),
                  child: Icon(FluentIcons.search, size: 16),
                ),
                suffix: searching
                    ? IconButton(
                        icon: const Icon(FluentIcons.clear, size: 14),
                        onPressed: () {
                          searchController.clear();
                          controller.updateSearch('');
                        },
                      )
                    : null,
                onChanged: controller.updateSearch,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Enter at least 2 characters. Email search is exact and private.',
                style: AppTheme.caption.copyWith(
                  color: context.elixTextSecondary,
                ),
              ),
            ],
          ),
        ),
        if (controller.alertMessage != null)
          _InlineMessageAlert(
            key: const ValueKey('messages-alert'),
            message: controller.alertMessage!,
            onDismiss: controller.dismissAlert,
          ),
        Divider(
          style: DividerThemeData(
            decoration: BoxDecoration(color: context.elixBorder),
          ),
        ),
        _InboxSummary(
          searching: searching,
          conversationCount: controller.inbox.length,
          unreadCount: unreadCount,
        ),
        Expanded(
          child: searching
              ? _SearchResults(controller: controller)
              : _InboxList(controller: controller),
        ),
      ],
    );
  }
}

class _InlineMessageAlert extends StatelessWidget {
  const _InlineMessageAlert({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final accent = context.elixColors.brandPrimary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            color: highContrast
                ? context.elixCardSurface
                : Color.alphaBlend(
                    accent.withValues(alpha: 0.1),
                    context.elixCardSurface,
                  ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: highContrast
                  ? context.elixBorder
                  : accent.withValues(alpha: 0.34),
              width: highContrast ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: highContrast
                      ? context.elixCardSurface
                      : accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(FluentIcons.chat, size: 15, color: accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  message,
                  style: AppTheme.body.copyWith(
                    color: context.elixTextPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Tooltip(
                message: 'Dismiss notification',
                child: IconButton(
                  icon: const Icon(FluentIcons.clear, size: 12),
                  onPressed: onDismiss,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InboxSummary extends StatelessWidget {
  const _InboxSummary({
    required this.searching,
    required this.conversationCount,
    required this.unreadCount,
  });

  final bool searching;
  final int conversationCount;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              searching ? 'SEARCH RESULTS' : 'RECENT CONVERSATIONS',
              style: AppTheme.eyebrow(color: context.elixTextSecondary),
            ),
          ),
          if (!searching && conversationCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: unreadCount > 0
                    ? context.elixColors.brandPrimary.withValues(alpha: 0.14)
                    : context.elixPanelSurface,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                unreadCount > 0
                    ? '$unreadCount unread'
                    : '$conversationCount total',
                style: AppTheme.caption.copyWith(
                  color: unreadCount > 0
                      ? context.elixColors.brandPrimary
                      : context.elixTextSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.controller});
  final MessagesController controller;

  @override
  Widget build(BuildContext context) {
    return switch (controller.searchState) {
      MessageSearchState.idle => const SizedBox.shrink(),
      MessageSearchState.waiting => const _CenteredMessage(
        text: 'Type one more character to search.',
      ),
      MessageSearchState.loading => const Center(child: ProgressRing()),
      MessageSearchState.empty => const _CenteredMessage(
        icon: FluentIcons.search,
        title: 'No people found',
        text: 'No matching people found.',
      ),
      MessageSearchState.error => _CenteredMessage(
        icon: FluentIcons.warning,
        title: 'Search unavailable',
        text: controller.searchError is ChatException
            ? (controller.searchError! as ChatException).userMessage
            : 'Search is unavailable right now.',
      ),
      MessageSearchState.ready => ListView.builder(
        padding: const EdgeInsets.all(AppSpacing.sm),
        itemCount: controller.searchResults.length,
        itemBuilder: (context, index) {
          final user = controller.searchResults[index];
          return _PersonTile(
            user: user,
            subtitle: user.role,
            selected: controller.selectedUser?.id == user.id,
            onPressed: () => controller.openUser(user),
            onViewProfile: () => _openChatUserProfile(context, user),
          );
        },
      ),
    };
  }
}

class _InboxList extends StatelessWidget {
  const _InboxList({required this.controller});
  final MessagesController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.inboxError != null) {
      return const _CenteredMessage(
        icon: FluentIcons.warning,
        title: 'Inbox unavailable',
        text: 'Could not load conversations.',
      );
    }
    if (controller.inbox.isEmpty) {
      return const _CenteredMessage(
        icon: FluentIcons.chat,
        title: 'Start a conversation',
        text: 'Search for a teacher or trainee to send your first message.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      itemCount: controller.inbox.length,
      itemBuilder: (context, index) {
        final conversation = controller.inbox[index];
        final user = conversation.otherParticipant(controller.currentUser.id);
        if (user == null) return const SizedBox.shrink();
        final preview = conversation.lastMessageBody ?? 'Start a conversation';
        final timestamp = conversation.lastMessageAt;
        return _PersonTile(
          user: user,
          subtitle: preview,
          timestamp: timestamp,
          unread: conversation.unreadFor(controller.currentUser.id),
          selected: controller.selectedConversation?.id == conversation.id,
          onPressed: () => controller.openConversation(conversation),
          onMarkUnread: () => controller.markConversationUnread(conversation),
          onViewProfile: () => _openChatUserProfile(context, user),
          onDelete: () => _confirmDelete(context, conversation, user),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ChatConversation conversation,
    ChatUser user,
  ) async {
    final confirmed = await ElixDialog.show<bool>(
      context,
      title: 'Delete conversation?',
      icon: FluentIcons.delete,
      iconColor: context.elixColors.error,
      headerAccentColor: context.elixColors.error,
      content: Text(
        'This removes your conversation with ${user.displayName} from your '
        'inbox. It does not delete their copy, and this cannot be undone.',
        style: AppTheme.body.copyWith(
          color: context.elixTextSecondary,
          height: 1.45,
        ),
      ),
      actions: [
        Button(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
    if (confirmed == true) await controller.clearConversation(conversation);
  }
}

class _PersonTile extends StatefulWidget {
  const _PersonTile({
    required this.user,
    required this.subtitle,
    required this.selected,
    required this.onPressed,
    this.timestamp,
    this.unread = 0,
    this.onMarkUnread,
    this.onDelete,
    this.onViewProfile,
  });

  final ChatUser user;
  final String subtitle;
  final bool selected;
  final VoidCallback onPressed;
  final DateTime? timestamp;
  final int unread;
  final VoidCallback? onMarkUnread;
  final VoidCallback? onDelete;
  final VoidCallback? onViewProfile;

  @override
  State<_PersonTile> createState() => _PersonTileState();
}

class _PersonTileState extends State<_PersonTile> {
  static const _tileHeight = 88.0;

  final _menuController = FlyoutController();

  @override
  void dispose() {
    _menuController.dispose();
    super.dispose();
  }

  void _showMenu() {
    _menuController.showFlyout<void>(
      placementMode: FlyoutPlacementMode.bottomRight,
      builder: (context) => MenuFlyout(
        constraints: const BoxConstraints(minWidth: 190),
        items: [
          if (widget.onMarkUnread != null)
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.mail),
              text: const Text('Mark as unread'),
              onPressed: widget.unread > 0 ? null : widget.onMarkUnread,
            ),
          if (widget.onViewProfile != null)
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.contact_info),
              text: const Text('View profile'),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onViewProfile!();
              },
            ),
          if (widget.onDelete != null) ...[
            const MenuFlyoutSeparator(),
            MenuFlyoutItem(
              leading: const Icon(FluentIcons.delete),
              text: Text(
                'Delete conversation',
                style: TextStyle(color: context.elixColors.error),
              ),
              onPressed: widget.onDelete,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SizedBox(
        height: _tileHeight,
        child: ElixCard(
          onTap: widget.onPressed,
          selected: widget.selected,
          variant: ElixCardVariant.interactive,
          semanticLabel: '${widget.user.displayName}. ${widget.subtitle}',
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _ChatAvatar(user: widget.user, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (widget.unread > 0) ...[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: context.elixColors.brandPrimary,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            widget.user.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.body.copyWith(
                              color: context.elixTextPrimary,
                              fontWeight: widget.unread > 0
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                        ),
                        if (widget.timestamp != null)
                          Text(
                            _compactTime(widget.timestamp!),
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.caption.copyWith(
                              color: context.elixTextSecondary,
                              fontWeight: widget.unread > 0
                                  ? FontWeight.w600
                                  : null,
                            ),
                          ),
                        ),
                        if (widget.unread > 0) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: context.elixColors.brandPrimary,
                              borderRadius: const BorderRadius.all(
                                Radius.circular(10),
                              ),
                            ),
                            child: Text(
                              widget.unread > 99 ? '99+' : '${widget.unread}',
                              textAlign: TextAlign.center,
                              style: AppTheme.caption.copyWith(
                                color: context.elixColors.onBrand,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.onDelete != null || widget.onViewProfile != null) ...[
                const SizedBox(width: 2),
                Semantics(
                  button: true,
                  label: 'Conversation actions',
                  child: Tooltip(
                    message: 'Conversation actions',
                    child: FlyoutTarget(
                      controller: _menuController,
                      child: IconButton(
                        key: ValueKey('conversation-menu-${widget.user.id}'),
                        icon: Icon(
                          FluentIcons.more_vertical,
                          size: 16,
                          color: highContrast
                              ? context.elixTextPrimary
                              : context.elixTextSecondary,
                        ),
                        onPressed: _showMenu,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationPane extends StatelessWidget {
  const _ConversationPane({
    required this.controller,
    required this.composerController,
    required this.scrollController,
    required this.showBack,
  });

  final MessagesController controller;
  final TextEditingController composerController;
  final ScrollController scrollController;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final user = controller.selectedUser;
    if (user == null) {
      return const _CenteredMessage(
        icon: FluentIcons.chat,
        title: 'Your conversations, in one place',
        text: 'Select a conversation or search for someone to message.',
      );
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: context.isHighContrast
                ? context.elixCardSurface
                : Color.alphaBlend(
                    context.elixColors.brandSecondary.withValues(alpha: 0.05),
                    context.elixCardSurface,
                  ),
            border: Border(bottom: BorderSide(color: context.elixBorder)),
          ),
          child: Row(
            children: [
              if (showBack) ...[
                IconButton(
                  icon: const Icon(FluentIcons.back),
                  onPressed: controller.showInboxPane,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              _ChatAvatar(user: user, size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.headingMedium,
                    ),
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: context.elixColors.brandSecondary.withValues(
                            alpha: 0.12,
                          ),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          user.role.toUpperCase(),
                          style: AppTheme.caption.copyWith(
                            color: context.elixColors.brandSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.selectedConversation?.isArchived != true)
                Button(
                  onPressed: () => _confirmBlock(context),
                  child: Text(
                    controller.blockState.blockedByMe ? 'Unblock' : 'Block',
                  ),
                ),
            ],
          ),
        ),
        Expanded(child: _messageBody(context)),
        _Composer(controller: controller, textController: composerController),
      ],
    );
  }

  Widget _messageBody(BuildContext context) {
    if (controller.messageState == MessagePaneState.loading) {
      return const Center(child: ProgressRing());
    }
    if (controller.messageState == MessagePaneState.error &&
        controller.messages.isEmpty) {
      return const _CenteredMessage(
        icon: FluentIcons.warning,
        title: 'Messages unavailable',
        text: 'Could not load messages.',
      );
    }
    if (controller.messages.isEmpty) {
      return _CenteredMessage(
        icon: FluentIcons.chat,
        title: controller.selectedConversation?.isArchived == true
            ? 'Archived conversation'
            : 'Start the conversation',
        text: controller.selectedConversation?.isArchived == true
            ? 'This archived conversation is read-only.'
            : 'No messages yet. Say hello.',
      );
    }
    final ascending = controller.messages.reversed.toList(growable: false);
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        if (controller.hasOlder || controller.paginationError != null)
          Center(
            child: Button(
              onPressed: controller.loadingOlder ? null : controller.loadOlder,
              child: Text(
                controller.loadingOlder
                    ? 'Loading…'
                    : controller.paginationError != null
                    ? 'Try loading older messages again'
                    : 'Load older messages',
              ),
            ),
          ),
        for (var index = 0; index < ascending.length; index++) ...[
          if (index == 0 ||
              !_sameLocalDay(
                ascending[index - 1].createdAt,
                ascending[index].createdAt,
              ))
            _DateSeparator(date: ascending[index].createdAt),
          _MessageBubble(
            message: ascending[index],
            mine: ascending[index].senderId == controller.currentUser.id,
            sender: controller.selectedUser!,
            seen: controller.isLatestOutgoingSeen(ascending[index]),
            onRetry: () => controller.retryMessage(ascending[index]),
            onEdit: () => _editMessage(context, ascending[index]),
            onDelete: () => _deleteMessage(context, ascending[index]),
          ),
        ],
      ],
    );
  }

  Future<void> _confirmBlock(BuildContext context) async {
    final unblocking = controller.blockState.blockedByMe;
    final confirmed = await ElixDialog.show<bool>(
      context,
      title: unblocking ? 'Unblock this person?' : 'Block this person?',
      icon: unblocking ? FluentIcons.unlock : FluentIcons.blocked,
      iconColor: context.elixColors.warning,
      headerAccentColor: context.elixColors.warning,
      content: Text(
        unblocking
            ? 'You will both be able to send messages again unless they have blocked you.'
            : 'Neither person can send new messages while this block is active. Message history remains visible.',
        style: AppTheme.body.copyWith(
          color: context.elixTextSecondary,
          height: 1.45,
        ),
      ),
      actions: [
        Button(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
          child: Text(unblocking ? 'Unblock' : 'Block'),
        ),
      ],
    );
    if (confirmed == true) await controller.toggleBlock();
  }

  Future<void> _editMessage(BuildContext context, ChatMessage message) async {
    if (message.isDeleted || message.deliveryState != ChatDeliveryState.sent) {
      return;
    }
    final text = TextEditingController(text: message.body);
    final value = await ElixDialog.show<String>(
      context,
      title: 'Edit message',
      icon: FluentIcons.edit,
      content: TextBox(
        controller: text,
        minLines: 2,
        maxLines: 6,
        maxLength: ChatMessage.maximumBodyLength,
      ),
      actions: [
        Button(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(text.text),
          child: const Text('Save'),
        ),
      ],
    );
    text.dispose();
    if (value != null && value.trim() != message.body) {
      await controller.editMessage(message, value);
    }
  }

  Future<void> _deleteMessage(BuildContext context, ChatMessage message) async {
    if (message.isDeleted || message.deliveryState != ChatDeliveryState.sent) {
      return;
    }
    final confirmed = await ElixDialog.show<bool>(
      context,
      title: 'Delete message?',
      icon: FluentIcons.delete,
      iconColor: context.elixColors.error,
      headerAccentColor: context.elixColors.error,
      content: Text(
        'The message body will be removed and replaced by a tombstone.',
        style: AppTheme.body.copyWith(
          color: context.elixTextSecondary,
          height: 1.45,
        ),
      ),
      actions: [
        Button(
          onPressed: () =>
              Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
          child: const Text('Delete'),
        ),
      ],
    );
    if (confirmed == true) await controller.deleteMessage(message);
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.textController});
  final MessagesController controller;
  final TextEditingController textController;

  @override
  Widget build(BuildContext context) {
    final archived = controller.selectedConversation?.isArchived == true;
    final disabled = controller.blockState.cannotSend || archived;
    final message = archived
        ? 'This archived conversation is read-only.'
        : controller.blockState.blockedByMe
        ? 'Unblock this person to send a message.'
        : controller.blockState.blockedByOther
        ? 'Messages cannot be sent in this conversation.'
        : null;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: context.isHighContrast
            ? context.elixCardSurface
            : context.elixPanelSurface.withValues(alpha: 0.45),
        border: Border(top: BorderSide(color: context.elixBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (message != null) ...[
            Text(
              message,
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Focus(
                  onKeyEvent: (_, event) {
                    if (!disabled &&
                        event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed) {
                      _send();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextBox(
                    controller: textController,
                    enabled: !disabled,
                    minLines: 1,
                    maxLines: 5,
                    maxLength: ChatMessage.maximumBodyLength,
                    placeholder: 'Write a message...',
                    padding: const EdgeInsets.all(12),
                    suffix: Padding(
                      padding: const EdgeInsets.only(
                        right: 6,
                        bottom: 4,
                        top: 4,
                      ),
                      child: IconButton(
                        icon: const Icon(FluentIcons.send, size: 14),
                        style: ButtonStyle(
                          backgroundColor: disabled
                              ? null
                              : WidgetStatePropertyAll(
                                  context.elixColors.brandPrimary,
                                ),
                          foregroundColor: disabled
                              ? null
                              : WidgetStatePropertyAll(
                                  context.elixColors.onBrand,
                                ),
                          shape: const WidgetStatePropertyAll(CircleBorder()),
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.all(10),
                          ),
                        ),
                        onPressed: disabled ? null : _send,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Enter to send • Shift+Enter for a new line',
            style: AppTheme.caption.copyWith(color: context.elixTextSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final body = textController.text;
    if (body.trim().isEmpty) return;
    textController.clear();
    final sent = await controller.send(body);
    if (!sent) textController.text = body;
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.sender,
    required this.seen,
    required this.onRetry,
    required this.onEdit,
    required this.onDelete,
  });

  final ChatMessage message;
  final bool mine;
  final ChatUser sender;
  final bool seen;
  final VoidCallback onRetry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final highContrast = context.isHighContrast;
    final metadata = <String>[
      DateFormat.jm().format(message.createdAt.toLocal()),
      if (message.isEdited) 'Edited',
      if (message.deliveryState == ChatDeliveryState.sending) 'Sending',
      if (message.deliveryState == ChatDeliveryState.error) 'Error',
      if (seen) 'Seen',
    ].join(' • ');
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: highContrast
            ? context.elixCardSurface
            : mine
            ? context.elixColors.brandPrimary
            : context.elixCardSurface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 4),
          bottomRight: Radius.circular(mine ? 4 : 16),
        ),
        border: Border.all(
          color: message.deliveryState == ChatDeliveryState.error
              ? context.elixColors.error
              : Colors.transparent,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (message.isMigratedCoaching)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                message.legacyMovementName == null
                    ? 'Migrated coaching note'
                    : 'Migrated coaching • ${message.legacyMovementName}',
                style: AppTheme.caption.copyWith(
                  color: mine
                      ? context.elixColors.onBrand.withValues(alpha: 0.8)
                      : context.elixTextSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Text(
            message.isDeleted ? 'Message deleted' : message.body ?? '',
            style: AppTheme.body.copyWith(
              color: message.isDeleted
                  ? (mine
                        ? context.elixColors.onBrand.withValues(alpha: 0.6)
                        : context.elixTextSecondary)
                  : (mine
                        ? context.elixColors.onBrand
                        : context.elixTextPrimary),
              fontStyle: message.isDeleted ? FontStyle.italic : null,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                metadata,
                style: AppTheme.caption.copyWith(
                  color: mine
                      ? context.elixColors.onBrand.withValues(alpha: 0.7)
                      : context.elixTextSecondary,
                ),
              ),
              if (message.deliveryState == ChatDeliveryState.error) ...[
                const SizedBox(width: AppSpacing.xs),
                HyperlinkButton(
                  onPressed: onRetry,
                  style: ButtonStyle(
                    foregroundColor: WidgetStatePropertyAll(
                      context.elixColors.onBrand,
                    ),
                  ),
                  child: const Text('Retry'),
                ),
              ] else if (mine && !message.isDeleted) ...[
                const SizedBox(width: AppSpacing.xs),
                HyperlinkButton(
                  onPressed: onEdit,
                  style: ButtonStyle(
                    foregroundColor: WidgetStatePropertyAll(
                      context.elixColors.onBrand.withValues(alpha: 0.9),
                    ),
                  ),
                  child: const Text('Edit'),
                ),
                HyperlinkButton(
                  onPressed: onDelete,
                  style: ButtonStyle(
                    foregroundColor: WidgetStatePropertyAll(
                      context.elixColors.onBrand.withValues(alpha: 0.9),
                    ),
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: mine
            ? bubble
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _ChatAvatar(
                    key: ValueKey('message-sender-avatar-${message.id}'),
                    user: sender,
                    size: 30,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Flexible(child: bubble),
                ],
              ),
      ),
    );
  }
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              DateFormat.yMMMd().format(date.toLocal()),
              style: AppTheme.caption.copyWith(
                color: context.elixTextSecondary,
              ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}

class _ChatAvatar extends StatelessWidget {
  const _ChatAvatar({super.key, required this.user, required this.size});
  final ChatUser user;
  final double size;

  @override
  Widget build(BuildContext context) {
    final nameParts = user.displayName
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    final initials = nameParts
        .take(2)
        .map((part) => part[0])
        .join()
        .toUpperCase();
    final avatar = user.avatarUrl;
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        color: context.isHighContrast
            ? context.elixCardSurface
            : context.elixColors.brandSecondary.withValues(alpha: 0.18),
        child: avatar != null
            ? Image.network(
                avatar,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Text(initials),
              )
            : Text(
                initials,
                style: AppTheme.caption.copyWith(
                  color: context.elixTextPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.text, this.icon, this.title});
  final String text;
  final IconData? icon;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: context.isHighContrast
                      ? context.elixCardSurface
                      : context.elixColors.brandPrimary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: context.isHighContrast
                        ? context.elixBorder
                        : context.elixColors.brandPrimary.withValues(
                            alpha: 0.18,
                          ),
                  ),
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: context.elixColors.brandPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: AppTheme.cardTitle(color: context.elixTextPrimary),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTheme.body.copyWith(color: context.elixTextSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

bool _sameLocalDay(DateTime first, DateTime second) {
  final a = first.toLocal();
  final b = second.toLocal();
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

String _compactTime(DateTime value) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return DateFormat.jm().format(local);
  }
  return DateFormat.MMMd().format(local);
}
