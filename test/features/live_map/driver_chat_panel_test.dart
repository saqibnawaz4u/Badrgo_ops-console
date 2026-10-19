import 'package:badrgo_ops_console/core/presentation/theme.dart';
import 'package:badrgo_ops_console/features/live_map/domain/repositories/live_map_repository.dart';
import 'package:badrgo_ops_console/features/live_map/presentation/bloc/driver_chat_cubit.dart';
import 'package:badrgo_ops_console/features/live_map/presentation/widgets/driver_chat_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDriverChatRepository extends Mock implements DriverChatRepository {}

void main() {
  late _MockDriverChatRepository repository;

  setUp(() {
    repository = _MockDriverChatRepository();
    when(() => repository.watchMessages()).thenAnswer((_) => const Stream.empty());
    when(() => repository.fetchHistory(any())).thenAnswer((_) async => []);
  });

  Future<void> pump(WidgetTester tester, {required bool offline}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: BlocProvider(
            create: (_) => DriverChatCubit(repository, driverId: 'drv_1')..start(),
            child: DriverChatPanel(driverOffline: offline),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  IconButton sendButton(WidgetTester tester) =>
      tester.widget<IconButton>(find.ancestor(of: find.byIcon(Icons.send), matching: find.byType(IconButton)));

  testWidgets('offline driver: Send is disabled and the hint says why', (tester) async {
    await pump(tester, offline: true);
    expect(sendButton(tester).onPressed, isNull);
    expect(find.text('Driver is offline and cannot receive messages'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    verifyNever(() => repository.send(driverId: any(named: 'driverId'), body: any(named: 'body')));
  });

  testWidgets('online driver: Send is enabled', (tester) async {
    await pump(tester, offline: false);
    expect(sendButton(tester).onPressed, isNotNull);
    expect(find.text('Message the driver'), findsOneWidget);
  });
}
