import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/presentation/formatters.dart';
import '../bloc/driver_chat_cubit.dart';

class DriverChatPanel extends StatefulWidget {
  const DriverChatPanel({super.key, required this.driverOffline});

  final bool driverOffline;

  @override
  State<DriverChatPanel> createState() => _DriverChatPanelState();
}

class _DriverChatPanelState extends State<DriverChatPanel> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final sent = await context.read<DriverChatCubit>().send(_input.text);
    if (sent && mounted) _input.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Sends to an offline driver fail with INVALID_STATE; block them up front
    // (the cubit still maps that error in case the status is stale).
    final offline = widget.driverOffline;
    return BlocBuilder<DriverChatCubit, DriverChatState>(
      builder: (context, state) {
        return Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Text('Chat with driver', style: theme.textTheme.titleSmall),
              const Spacer(),
              if (widget.driverOffline) Text('offline', style: theme.textTheme.bodySmall),
            ]),
          ),
          Expanded(
            child: state.loading
                ? const Center(child: CircularProgressIndicator())
                : state.messages.isEmpty
                    ? Center(child: Text('No messages yet.', style: theme.textTheme.bodySmall))
                    : ListView.builder(
                        reverse: true,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: state.messages.length,
                        itemBuilder: (context, i) {
                          final m = state.messages[state.messages.length - 1 - i];
                          return Align(
                            alignment: m.fromDriver ? Alignment.centerLeft : Alignment.centerRight,
                            child: Container(
                              constraints: const BoxConstraints(maxWidth: 260),
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: m.fromDriver
                                    ? theme.colorScheme.surfaceContainerHighest
                                    : theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(m.body),
                                  Text(
                                    '${m.fromDriver ? 'Driver' : (m.sentBy ?? 'Ops')} · ${formatTime(m.createdAt)}',
                                    style: theme.textTheme.labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(state.error!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  maxLength: DriverChatCubit.maxLength,
                  decoration: InputDecoration(
                    hintText: offline ? 'Driver is offline and cannot receive messages' : 'Message the driver',
                    counterText: '',
                  ),
                  onSubmitted: offline ? null : (_) => _send(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: offline ? 'Driver is offline' : 'Send',
                onPressed: state.sending || offline ? null : _send,
                icon: state.sending
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}
