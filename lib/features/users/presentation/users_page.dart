import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/permissions/permissions.dart';
import '../../../core/presentation/theme.dart';
import '../../../core/presentation/widgets/page_header.dart';
import '../../../core/presentation/widgets/state_views.dart';
import '../../auth/presentation/bloc/auth_bloc.dart';
import '../domain/users.dart';
import 'bloc/users_cubit.dart';

class UsersPage extends StatelessWidget {
  const UsersPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => UsersCubit(context.read<UsersRepository>())..start(),
    child: BlocListener<UsersCubit, UsersState>(
      listenWhen: (a, b) => b.message != null && a.message != b.message,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message!)));
        context.read<UsersCubit>().clearMessage();
      },
      child: const _UsersView(),
    ),
  );
}

class _UsersView extends StatelessWidget {
  const _UsersView();

  @override
  Widget build(BuildContext context) {
    // Read from AuthBloc so a live role change updates the actions.
    final permissions = context.select((AuthBloc b) => b.state.user?.permissions ?? Permissions.none);
    return BlocBuilder<UsersCubit, UsersState>(
      builder: (context, state) {
        final cubit = context.read<UsersCubit>();
        Widget body;
        if (state.status == UsersStatus.loading && state.users.isEmpty) {
          body = const LoadingView();
        } else if (state.status == UsersStatus.failure) {
          body = ErrorView(message: state.error!, onRetry: cubit.load);
        } else if (state.users.isEmpty) {
          body = const MessageView(icon: Icons.people_outline, title: 'No users match');
        } else {
          body = Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                // Reloading (page change, search) keeps the list visible.
                if (state.status == UsersStatus.loading) const LinearProgressIndicator(minHeight: 2),
                Expanded(
                  child: ListView.separated(
                    itemCount: state.users.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, i) => _UserRow(user: state.users[i], state: state),
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: pagePadding(context, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(
                title: 'Users',
                badge: CountPill('${state.total} users'),
                actions: [
                  SizedBox(
                    width: 260,
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Search name or email',
                      ),
                      onChanged: cubit.searchChanged,
                    ),
                  ),
                  if (permissions.can(Permission.userCreate))
                    FilledButton.icon(
                      onPressed: () => _showCreateDialog(context, cubit),
                      icon: const Icon(Icons.person_add),
                      label: const Text('New user'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Shared sandbox: only change users you created. Demo accounts ask for confirmation.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Expanded(child: body),
              if (state.totalPages > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      onPressed: state.page > 1 ? () => cubit.load(page: state.page - 1) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text('Page ${state.page} of ${state.totalPages}'),
                    IconButton(
                      onPressed: state.page < state.totalPages ? () => cubit.load(page: state.page + 1) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user, required this.state});

  final AppUser user;
  final UsersState state;

  Future<bool> _confirmDemo(BuildContext context) async {
    if (!user.isDemoAccount) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This is a shared demo account'),
        content: Text('${user.email} is used by everyone testing this sandbox. Change it anyway?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, change it')),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UsersCubit>();
    final busy = state.busyIds.contains(user.id);
    final ops = OpsColors.of(context);
    final permissions = context.select((AuthBloc b) => b.state.user?.permissions ?? Permissions.none);
    final canSetRole = permissions.can(Permission.userSetRole);
    final canBan = permissions.can(Permission.userBan);
    Future<void> changeRole() async {
      if (await _confirmDemo(context) && context.mounted) {
        await _showRoleDialog(context, cubit, user, state);
      }
    }

    Future<void> ban() async {
      if (await _confirmDemo(context) && context.mounted) await _showBanDialog(context, cubit, user);
    }

    Future<void> unban() async {
      if (await _confirmDemo(context) && context.mounted) await cubit.unban(user);
    }

    final Widget? actions;
    if (!canSetRole && !canBan) {
      actions = null;
    } else if (isCompact(context)) {
      // Three text buttons do not fit next to the user on a phone.
      actions = PopupMenuButton<VoidCallback>(
        tooltip: 'Actions',
        onSelected: (action) => action(),
        itemBuilder: (context) => [
          if (canSetRole) PopupMenuItem(value: changeRole, child: const Text('Change role')),
          if (canBan && user.banned)
            PopupMenuItem(value: unban, child: const Text('Unban'))
          else if (canBan)
            PopupMenuItem(
              value: ban,
              child: Text('Ban', style: TextStyle(color: ops.danger)),
            ),
        ],
      );
    } else {
      actions = Wrap(
        spacing: 4,
        children: [
          if (canSetRole) TextButton(onPressed: changeRole, child: const Text('Change role')),
          if (canBan && user.banned)
            TextButton(onPressed: unban, child: const Text('Unban'))
          else if (canBan)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: ops.danger),
              onPressed: ban,
              child: const Text('Ban'),
            ),
        ],
      );
    }
    return ListTile(
      leading: CircleAvatar(child: Text(user.name.isEmpty ? '?' : user.name[0])),
      title: Row(
        children: [
          Flexible(child: Text(user.name, overflow: TextOverflow.ellipsis)),
          if (user.isDemoAccount) ...[const SizedBox(width: 8), const Chip(label: Text('demo'))],
          if (user.banned) ...[
            const SizedBox(width: 8),
            Chip(label: const Text('banned'), backgroundColor: ops.danger.withValues(alpha: 0.15)),
          ],
        ],
      ),
      subtitle: Text(
        '${user.email} · ${user.role} · ${state.cityName(user.cityId)}'
        '${user.banReason != null ? ' · ${user.banReason}' : ''}',
      ),
      trailing: busy
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
          : actions,
    );
  }
}

Future<void> _showRoleDialog(BuildContext context, UsersCubit cubit, AppUser user, UsersState state) {
  var role = user.role;
  var cityId = user.cityId ?? state.cities.firstOrNull?.id;
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('Change role for ${user.name}'),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [for (final r in assignableRoles) DropdownMenuItem(value: r, child: Text(r))],
                onChanged: (v) => setState(() => role = v!),
              ),
              if (cubit.roleNeedsCity(role)) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: cityId,
                  decoration: const InputDecoration(labelText: 'City'),
                  items: [for (final c in state.cities) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => cityId = v),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              cubit.changeRole(user, role, cityId);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showBanDialog(BuildContext context, UsersCubit cubit, AppUser user) =>
    showDialog<void>(context: context, builder: (_) => _BanDialog(cubit: cubit, user: user));

/// Owns its controller so it is disposed only after the dialog has left the
/// tree. Disposing it when `showDialog` completes is too early: the closing
/// animation still shows the text field.
class _BanDialog extends StatefulWidget {
  const _BanDialog({required this.cubit, required this.user});

  final UsersCubit cubit;
  final AppUser user;

  @override
  State<_BanDialog> createState() => _BanDialogState();
}

class _BanDialogState extends State<_BanDialog> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Ban ${widget.user.name}?'),
        content: Form(
          key: _form,
          child: TextFormField(
            controller: _reason,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Reason'),
            validator: (v) => widget.cubit.requiredText(v, min: 3),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              Navigator.pop(context);
              widget.cubit.ban(widget.user, _reason.text);
            },
            child: const Text('Ban and sign out'),
          ),
        ],
      );
}

Future<void> _showCreateDialog(BuildContext context, UsersCubit cubit) => showDialog<void>(
  context: context,
  builder: (_) => BlocProvider.value(value: cubit, child: const _CreateUserDialog()),
);

class _CreateUserDialog extends StatefulWidget {
  const _CreateUserDialog();

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _role = 'viewer';
  String? _cityId;
  bool _saving = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final cubit = context.read<UsersCubit>();
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    final outcome = await cubit.create(
      NewUser(
        name: _name.text,
        email: _email.text,
        password: _password.text,
        role: _role,
        cityId: cubit.roleNeedsCity(_role) ? (_cityId ?? cubit.state.cities.firstOrNull?.id) : null,
      ),
    );
    if (!mounted) return;
    if (outcome.ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = outcome.message;
        _fieldErrors = outcome.fieldErrors;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<UsersCubit>();
    final cities = context.watch<UsersCubit>().state.cities;
    return AlertDialog(
      title: const Text('New user'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: 'Name', errorText: _fieldErrors['name']),
                validator: (v) => cubit.requiredText(v, min: 2),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                decoration: InputDecoration(labelText: 'Email', errorText: _fieldErrors['email']),
                validator: cubit.validateEmail,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(labelText: 'Password', errorText: _fieldErrors['password']),
                validator: (v) => cubit.requiredText(v, min: 8),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: [for (final r in assignableRoles) DropdownMenuItem(value: r, child: Text(r))],
                onChanged: (v) => setState(() => _role = v!),
              ),
              if (cubit.roleNeedsCity(_role)) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _cityId ?? cities.firstOrNull?.id,
                  decoration: InputDecoration(labelText: 'City', errorText: _fieldErrors['cityId']),
                  items: [for (final c in cities) DropdownMenuItem(value: c.id, child: Text(c.name))],
                  onChanged: (v) => setState(() => _cityId = v),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _saving ? null : _submit, child: const Text('Create')),
      ],
    );
  }
}
