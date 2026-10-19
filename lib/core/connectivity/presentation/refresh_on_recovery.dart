import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'connectivity_cubit.dart';

/// Calls [onRecovered] when the API comes back after maintenance or an
/// outage, so a page can refresh data that went stale meanwhile.
class RefreshOnRecovery extends StatelessWidget {
  const RefreshOnRecovery({super.key, required this.onRecovered, required this.child});

  final VoidCallback onRecovered;
  final Widget child;

  @override
  Widget build(BuildContext context) => BlocListener<ConnectivityCubit, ConnectivityState>(
        listenWhen: (previous, current) => current.recoveries != previous.recoveries,
        listener: (_, _) => onRecovered(),
        child: child,
      );
}
