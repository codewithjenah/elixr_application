import 'package:fluent_ui/fluent_ui.dart';

import '../../core/constants/app_spacing.dart';

class GoogleAuthButton extends StatelessWidget {
  const GoogleAuthButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 42,
      child: Button(
        onPressed: isLoading ? null : onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              const Text(
                'G',
                style: TextStyle(
                  color: Color(0xFF4285F4),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: FittedBox(fit: BoxFit.scaleDown, child: Text(label)),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider()),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text('or'),
        ),
        Expanded(child: Divider()),
      ],
    );
  }
}
