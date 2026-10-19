import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/api_exception.dart';
import '../../domain/entities/driver.dart';
import '../../domain/repositories/live_map_repository.dart';

class DriverChatState extends Equatable {
  const DriverChatState({
    this.loading = true,
    this.messages = const [],
    this.sending = false,
    this.error,
  });

  final bool loading;

  /// Oldest first.
  final List<ChatMessage> messages;
  final bool sending;
  final String? error;

  DriverChatState copyWith({
    bool? loading,
    List<ChatMessage>? messages,
    bool? sending,
    String? Function()? error,
  }) =>
      DriverChatState(
        loading: loading ?? this.loading,
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        error: error != null ? error() : this.error,
      );

  @override
  List<Object?> get props => [loading, messages, sending, error];
}

/// Chat with one driver: REST history, live frames over the WebSocket,
/// sends as WebSocket commands with ack/error matching.
class DriverChatCubit extends Cubit<DriverChatState> {
  DriverChatCubit(this._repository, {required this.driverId}) : super(const DriverChatState());

  static const maxLength = 500;

  final DriverChatRepository _repository;
  final String driverId;
  StreamSubscription<ChatMessage>? _live;

  Future<void> start() async {
    _live ??= _repository.watchMessages().where((m) => m.driverId == driverId).listen(_add);
    try {
      final history = await _repository.fetchHistory(driverId);
      if (isClosed) return;
      // Live frames may have arrived while history loaded: merge by id.
      emit(state.copyWith(loading: false, messages: _merge(history, state.messages)));
    } on ApiException catch (e) {
      if (isClosed) return;
      emit(state.copyWith(loading: false, error: () => e.message));
    }
  }

  String? validate(String body) {
    final text = body.trim();
    if (text.isEmpty) return 'Type a message.';
    if (text.length > maxLength) return 'Keep it under $maxLength characters.';
    return null;
  }

  /// Returns true when sent, so the view can clear the input.
  Future<bool> send(String body) async {
    final invalid = validate(body);
    if (invalid != null) {
      emit(state.copyWith(error: () => invalid));
      return false;
    }
    emit(state.copyWith(sending: true, error: () => null));
    try {
      final message = await _repository.send(driverId: driverId, body: body);
      if (isClosed) return true;
      _add(message);
      emit(state.copyWith(sending: false));
      return true;
    } on ApiException catch (e) {
      if (isClosed) return false;
      final text = e.code == ApiErrorCode.invalidState
          ? 'This driver is offline and cannot receive messages.'
          : e.message;
      emit(state.copyWith(sending: false, error: () => text));
      return false;
    }
  }

  void _add(ChatMessage message) =>
      emit(state.copyWith(messages: _merge(state.messages, [message])));

  static List<ChatMessage> _merge(List<ChatMessage> a, List<ChatMessage> b) {
    final byId = {for (final m in a) m.id: m, for (final m in b) m.id: m};
    return byId.values.toList()..sort((x, y) => x.createdAt.compareTo(y.createdAt));
  }

  @override
  Future<void> close() async {
    await _live?.cancel();
    return super.close();
  }
}
