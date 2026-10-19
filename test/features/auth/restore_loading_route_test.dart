import 'package:badrgo_ops_console/app/router.dart';
import 'package:badrgo_ops_console/core/presentation/theme.dart';
import 'package:badrgo_ops_console/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuthBloc extends MockBloc<AuthEvent, AuthState> implements AuthBloc {}

void main() {
  setUpAll(() => registerFallbackValue(const AuthRestoreRetried()));

  Future<_MockAuthBloc> pumpRouter(WidgetTester tester, AuthState state) async {
    final auth = _MockAuthBloc();
    whenListen(auth, const Stream<AuthState>.empty(), initialState: state);
    final refresh = StreamListenable(auth.stream);
    final router = buildRouter(auth, refresh: refresh);
    addTearDown(() {
      router.dispose();
      refresh.dispose();
    });
    await tester.pumpWidget(MaterialApp.router(theme: AppTheme.light(), routerConfig: router));
    await tester.pump();
    return auth;
  }

  testWidgets('a failed restore with a notice offers Try again', (tester) async {
    final auth = await pumpRouter(tester, const AuthState.unknown(restorePending: true, notice: 'Server error'));

    expect(find.text('Server error'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    verify(() => auth.add(any(that: isA<AuthRestoreRetried>()))).called(1);
  });

  testWidgets('restoring without a notice shows the spinner', (tester) async {
    await pumpRouter(tester, const AuthState.unknown());

    expect(find.text('Restoring your session…'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });
}
