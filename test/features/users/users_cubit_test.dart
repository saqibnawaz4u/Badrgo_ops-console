import 'dart:async';

import 'package:badrgo_ops_console/features/users/domain/users.dart';
import 'package:badrgo_ops_console/features/users/presentation/bloc/users_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockUsersRepository extends Mock implements UsersRepository {}

AppUser _user(String id) =>
    AppUser(id: id, name: 'User $id', email: '$id@example.com', role: 'viewer', cityId: null, banned: false);

void main() {
  test('a slower, older load result does not overwrite a newer one', () async {
    final repository = _MockUsersRepository();
    final slowPage1 = Completer<UsersResult>();
    final fastPage2 = Completer<UsersResult>();
    when(() => repository.fetchUsers(page: 1, search: any(named: 'search'))).thenAnswer((_) => slowPage1.future);
    when(() => repository.fetchUsers(page: 2, search: any(named: 'search'))).thenAnswer((_) => fastPage2.future);
    final cubit = UsersCubit(repository);
    addTearDown(cubit.close);

    final older = cubit.load(page: 1);
    final newer = cubit.load(page: 2);
    fastPage2.complete(UsersResult(users: [_user('b')], page: 2, totalPages: 2, total: 2));
    await newer;
    slowPage1.complete(UsersResult(users: [_user('a')], page: 1, totalPages: 2, total: 2));
    await older;

    expect(cubit.state.status, UsersStatus.ready);
    expect(cubit.state.page, 2);
    expect(cubit.state.users.single.id, 'b');
  });
}
