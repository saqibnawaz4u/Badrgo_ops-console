import 'package:flutter/material.dart';

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (label != null) ...[
              const SizedBox(height: 12),
              Text(label!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      );
}

/// Centered icon + title + message + optional action. Base for the
/// empty, error, not-found and no-access states.
class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: color ?? theme.colorScheme.outline),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              if (message != null) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => MessageView(
        icon: Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
        title: 'Could not load this',
        message: message,
        action: onRetry == null
            ? null
            : FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
      );
}

class NoAccessView extends StatelessWidget {
  const NoAccessView({super.key, required this.requirement, this.onGoHome});

  /// e.g. `driver:track`.
  final String requirement;
  final VoidCallback? onGoHome;

  @override
  Widget build(BuildContext context) => MessageView(
        icon: Icons.lock_outline,
        title: 'No access',
        message: 'Your role does not include $requirement, so this page is not available to you. '
            'If you think it should be, ask an administrator.',
        action: onGoHome == null
            ? null
            : FilledButton.tonal(onPressed: onGoHome, child: const Text('Go to my start page')),
      );
}

class NotFoundView extends StatelessWidget {
  const NotFoundView({super.key, required this.title, required this.message, this.action});

  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) =>
      MessageView(icon: Icons.search_off, title: title, message: message, action: action);
}
