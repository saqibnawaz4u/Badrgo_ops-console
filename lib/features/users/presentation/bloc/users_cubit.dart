import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/domain/shared_entities.dart';
import '../../../../core/error/api_exception.dart';
import '../../domain/users.dart';

enum UsersStatus { loading, ready, failure }

class UsersState extends Equatable {
  const UsersState({
    this.status = UsersStatus.loading,
    this.users = const [],
    this.page = 1,
    this.totalPages = 1,
    this.total = 0,
    this.search = '',
    this.cities = const [],
    this.busyIds = const {},
    this.error,
    this.message,
  });

  final UsersStatus status;
  final List<AppUser> users;
  final int page;
  final int totalPages;
  final int total;
  final String search;
  final List<City> cities;
  final Set<String> busyIds;
  final String? error;
  final String? message;

  String cityName(String? id) =>
      id == null ? 'All cities' : cities.where((c) => c.id == id).firstOrNull?.name ?? id;

  UsersState copyWith({
    UsersStatus? status,
    List<AppUser>? users,
    int? page,
    int? totalPages,
    int? total,
    String? search,
    List<City>? cities,
    Set<String>? busyIds,
    String? Function()? error,
    String? Function()? message,
  }) =>
      UsersState(
        status: status ?? this.status,
        users: users ?? this.users,
        page: page ?? this.page,
        totalPages: totalPages ?? this.totalPages,
        total: total ?? this.total,
        search: search ?? this.search,
        cities: cities ?? this.cities,
        busyIds: busyIds ?? this.busyIds,
        error: error != null ? error() : this.error,
        message: message != null ? message() : this.message,
      );

  @override
  List<Object?> get props =>
      [status, users, page, totalPages, total, search, cities, busyIds, error, message];
}

/// Result for the create form: field errors from a 422 stay in the form.
class FormOutcome {
  const FormOutcome.ok() : ok = true, message = null, fieldErrors = const {};
  const FormOutcome.failed(this.message, this.fieldErrors) : ok = false;

  final bool ok;
  final String? message;
  final Map<String, String> fieldErrors;
}

class UsersCubit extends Cubit<UsersState> {
  UsersCubit(this._repository) : super(const UsersState());

  final UsersRepository _repository;
  Timer? _searchTimer;
  int _loadGeneration = 0;

  Future<void> start() async {
    unawaited(_loadCities());
    await load();
  }

  Future<void> _loadCities() async {
    try {
      final cities = await _repository.fetchCities();
      if (!isClosed) emit(state.copyWith(cities: cities));
    } on ApiException {
      // City names fall back to ids.
    }
  }

  Future<void> load({int? page}) async {
    // Only the latest request may land: a slow older response (fast paging
    // or typing) must not overwrite a newer one.
    final generation = ++_loadGeneration;
    emit(state.copyWith(status: UsersStatus.loading, error: () => null));
    try {
      final result = await _repository.fetchUsers(page: page ?? state.page, search: state.search);
      if (isClosed || generation != _loadGeneration) return;
      emit(state.copyWith(
        status: UsersStatus.ready,
        users: result.users,
        page: result.page,
        totalPages: result.totalPages,
        total: result.total,
      ));
    } on ApiException catch (e) {
      if (isClosed || generation != _loadGeneration) return;
      emit(state.copyWith(status: UsersStatus.failure, error: () => e.message));
    }
  }

  void searchChanged(String query) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), () {
      if (isClosed) return;
      emit(state.copyWith(search: query));
      load(page: 1);
    });
  }

  String? requiredText(String? v, {int min = 1}) =>
      (v ?? '').trim().length < min ? 'At least $min characters.' : null;

  String? validateEmail(String? v) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email.';

  /// Every role except super_admin needs a city.
  bool roleNeedsCity(String role) => role != 'super_admin';

  Future<FormOutcome> create(NewUser user) async {
    try {
      final created = await _repository.create(user);
      if (isClosed) return const FormOutcome.ok();
      emit(state.copyWith(message: () => 'Created ${created.email}.'));
      await load(page: 1);
      return const FormOutcome.ok();
    } on ApiException catch (e) {
      return FormOutcome.failed(e.message, e.fieldErrors);
    }
  }

  Future<void> changeRole(AppUser user, String role, String? cityId) => _mutate(
        user,
        () => _repository.update(user.id, role: role, cityId: roleNeedsCity(role) ? cityId : null),
        'Updated ${user.email}: now $role.',
      );

  Future<void> ban(AppUser user, String reason) =>
      _mutate(user, () => _repository.ban(user.id, reason), 'Banned ${user.email}. Their sessions are revoked.');

  Future<void> unban(AppUser user) => _mutate(user, () => _repository.unban(user.id), 'Unbanned ${user.email}.');

  Future<void> _mutate(AppUser user, Future<AppUser> Function() action, String success) async {
    emit(state.copyWith(busyIds: {...state.busyIds, user.id}));
    try {
      final updated = await action();
      if (isClosed) return;
      emit(state.copyWith(
        users: [for (final u in state.users) u.id == updated.id ? updated : u],
        message: () => success,
      ));
    } on ApiException catch (e) {
      if (isClosed) return;
      emit(state.copyWith(message: () => e.message));
    } finally {
      if (!isClosed) emit(state.copyWith(busyIds: {...state.busyIds}..remove(user.id)));
    }
  }

  void clearMessage() => emit(state.copyWith(message: () => null));

  @override
  Future<void> close() {
    _searchTimer?.cancel();
    return super.close();
  }
}
