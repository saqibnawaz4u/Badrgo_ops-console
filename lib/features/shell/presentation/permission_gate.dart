import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/permissions/permissions.dart';
import '../../../core/presentation/widgets/state_views.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';

/// Shows [child] only while the signed-in user holds [required]; otherwise
/// a "no access" page. Rebuilds when permissions change (e.g. an admin
/// switches the role), so an open page locks itself immediately.
class PermissionGate extends StatelessWidget {
  const PermissionGate({super.key, required this.required, required this.child});

  final Permission required;
  final Widget child;

  @override
  Widget build(BuildContext context) => BlocSelector<AuthBloc, AuthState, bool>(
        selector: (state) => state.user?.permissions.can(required) ?? false,
        builder: (context, allowed) => allowed
            ? child
            : NoAccessView(requirement: '$required', onGoHome: () => context.go('/')),
      );
}
