import 'package:badrgo_ops_console/core/permissions/permissions.dart';
import 'package:badrgo_ops_console/core/presentation/theme.dart';
import 'package:badrgo_ops_console/features/auth/domain/entities/current_user.dart';
import 'package:badrgo_ops_console/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:badrgo_ops_console/features/users/domain/users.dart';
import 'package:badrgo_ops_console/features/users/presentation/users_page.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../fixtures/roles.dart';

class _MockUsersRepository extends Mock implements UsersRepository {}

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

const _active = AppUser(id: 'u1', name: 'Active', email: 'active@example.com', role: 'viewer', cityId: null, banned: false);
const _banned = AppUser(id: 'u2', name: 'Banned', email: 'banned@example.com', role: 'viewer', cityId: null, banned: true);

/// A user who may list users and nothing else.
final _listOnly = CurrentUser(
  id: 'usr_list',
  name: 'List only',
  email: 'list@example.com',
  role: 'custom',
  roleDescription: 'custom',
  city: null,
  permissions: Permissions.fromJson(const {
    'user': ['list'],
  }),
);

void main() {
  late _MockUsersRepository users;

  setUp(() {
    users = _MockUsersRepository();
    when(() => users.fetchCities()).thenAnswer((_) async => const []);
    when(() => users.fetchUsers(page: any(named: 'page'), search: any(named: 'search'))).thenAnswer(
      (_) async => const UsersResult(users: [_active, _banned], page: 1, totalPages: 1, total: 2),
    );
  });

  Future<void> pumpUsers(WidgetTester tester, CurrentUser user) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final auth = _MockAuthBloc();
    when(() => auth.state).thenReturn(AuthState.authenticated(user, 'token'));
    await tester.pumpWidget(
      RepositoryProvider<UsersRepository>.value(
        value: users,
        child: BlocProvider<AuthBloc>.value(
          value: auth,
          child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: UsersPage())),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a user with only user:list sees the list but no actions', (tester) async {
    await pumpUsers(tester, _listOnly);

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('New user'), findsNothing);
    expect(find.text('Change role'), findsNothing);
    expect(find.text('Ban'), findsNothing);
    expect(find.text('Unban'), findsNothing);
  });

  testWidgets('super_admin sees New user, Change role, Ban and Unban', (tester) async {
    await pumpUsers(tester, userFor('super_admin'));

    expect(find.text('New user'), findsOneWidget);
    expect(find.text('Change role'), findsNWidgets(2));
    expect(find.text('Ban'), findsOneWidget);
    expect(find.text('Unban'), findsOneWidget);
  });

  testWidgets('banning a user closes the dialog cleanly and updates the row', (tester) async {
    when(() => users.ban('u1', 'Fraud check')).thenAnswer(
      (_) async => const AppUser(
        id: 'u1',
        name: 'Active',
        email: 'active@example.com',
        role: 'viewer',
        cityId: null,
        banned: true,
        banReason: 'Fraud check',
      ),
    );
    await pumpUsers(tester, userFor('super_admin'));

    await tester.tap(find.text('Ban'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Fraud check');
    await tester.tap(find.text('Ban and sign out'));
    // Runs the dialog's closing animation; a controller disposed too early
    // or a lost dependency throws here.
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ban and sign out'), findsNothing);
    verify(() => users.ban('u1', 'Fraud check')).called(1);
    expect(find.text('Unban'), findsNWidgets(2));
  });
}
