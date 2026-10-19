import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/presentation/formatters.dart';
import '../../domain/entities/trip.dart';
import '../bloc/trip_detail_cubit.dart';

Future<void> showAssignDriverDialog(BuildContext context, TripDetailCubit cubit) {
  cubit.loadDriverOptions();
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider.value(value: cubit, child: const _AssignDriverDialog()),
  );
}

Future<void> showCancelTripDialog(BuildContext context, TripDetailCubit cubit) => showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(value: cubit, child: const _CancelTripDialog()),
    );

Future<void> showRefundDialog(BuildContext context, TripDetailCubit cubit) => showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(value: cubit, child: const _RefundDialog()),
    );

void _closeWith(BuildContext context, ActionOutcome outcome) {
  if (!context.mounted) return;
  Navigator.of(context).pop();
  // Conflicts are explained by the page banner; everything else gets a toast.
  if (!outcome.conflict) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(outcome.message)));
  }
}

class _AssignDriverDialog extends StatefulWidget {
  const _AssignDriverDialog();

  @override
  State<_AssignDriverDialog> createState() => _AssignDriverDialogState();
}

class _AssignDriverDialogState extends State<_AssignDriverDialog> {
  AssignableDriver? _selected;
  String? _error;

  Future<void> _submit() async {
    final driver = _selected;
    if (driver == null) return;
    final cubit = context.read<TripDetailCubit>();
    final outcome = await cubit.assign(driver);
    if (!mounted) return;
    if (outcome.ok || outcome.conflict) {
      _closeWith(context, outcome);
    } else {
      setState(() => _error = outcome.message);
      // The driver may have been taken meanwhile; show a fresh list.
      await cubit.loadDriverOptions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<TripDetailCubit>().state;
    final options = state.driverOptions;
    Widget body;
    if (options.loading) {
      body = const SizedBox(height: 200, child: Center(child: CircularProgressIndicator()));
    } else if (options.error != null) {
      body = Text(options.error!, style: TextStyle(color: Theme.of(context).colorScheme.error));
    } else if (options.drivers.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('No drivers are available in this city right now. Refresh in a moment.'),
      );
    } else {
      body = SizedBox(
        height: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            RadioGroup<String>(
              groupValue: _selected?.id,
              onChanged: (id) => setState(() {
                _selected = options.drivers.firstWhere((d) => d.id == id);
                _error = null;
              }),
              child: Column(children: [
                for (final d in options.drivers)
                  RadioListTile<String>(
                    value: d.id,
                    title: Text(d.name),
                    subtitle: Text([
                      if (d.distanceKm != null) '${d.distanceKm!.toStringAsFixed(1)} km from pickup',
                      if (d.rating != null) '★ ${d.rating!.toStringAsFixed(2)}',
                      if (d.vehicle != null) d.vehicle!.label,
                    ].join(' · ')),
                  ),
              ]),
            ),
          ],
        ),
      );
    }

    return AlertDialog(
      title: Row(children: [
        const Expanded(child: Text('Assign a driver')),
        IconButton(
          tooltip: 'Refresh available drivers',
          onPressed: options.loading ? null : context.read<TripDetailCubit>().loadDriverOptions,
          icon: const Icon(Icons.refresh),
        ),
      ]),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Available drivers in the trip\'s city, nearest to the pickup first.'),
            const SizedBox(height: 12),
            body,
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(
          onPressed: _selected == null || state.busy ? null : _submit,
          child: state.busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Assign'),
        ),
      ],
    );
  }
}

class _CancelTripDialog extends StatefulWidget {
  const _CancelTripDialog();

  @override
  State<_CancelTripDialog> createState() => _CancelTripDialogState();
}

class _CancelTripDialogState extends State<_CancelTripDialog> {
  final _form = GlobalKey<FormState>();
  final _reason = TextEditingController();
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _fieldErrors = const {});
    if (!_form.currentState!.validate()) return;
    final outcome = await context.read<TripDetailCubit>().cancel(_reason.text);
    if (!mounted) return;
    if (outcome.ok || outcome.conflict) {
      _closeWith(context, outcome);
    } else {
      setState(() {
        _error = outcome.message;
        _fieldErrors = outcome.fieldErrors;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<TripDetailCubit>();
    return AlertDialog(
      title: const Text('Cancel this trip?'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('The driver is freed and the rider is notified. This cannot be undone.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _reason,
                autofocus: true,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: 'Reason',
                  errorText: _fieldErrors['reason'],
                ),
                validator: cubit.validateReason,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Keep trip')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
          onPressed: cubit.state.busy ? null : _submit,
          child: const Text('Cancel trip'),
        ),
      ],
    );
  }
}

class _RefundDialog extends StatefulWidget {
  const _RefundDialog();

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  final _form = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String? _error;
  Map<String, String> _fieldErrors = const {};

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _fieldErrors = const {});
    if (!_form.currentState!.validate()) return;
    final outcome = await context.read<TripDetailCubit>().refund(_amount.text, _reason.text);
    if (!mounted) return;
    if (outcome.ok || outcome.conflict) {
      _closeWith(context, outcome);
    } else {
      setState(() {
        _error = outcome.fieldErrors.isEmpty ? outcome.message : null;
        _fieldErrors = outcome.fieldErrors;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<TripDetailCubit>();
    final trip = cubit.state.trip!;
    return AlertDialog(
      title: const Text('Refund trip'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Fare ${formatMoney(trip.fare)}, already refunded ${formatMoney(trip.refunded)}. '
                  'Up to ${formatMoney(trip.refundable)} can be refunded.'),
              const SizedBox(height: 16),
              TextFormField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Amount',
                  suffixText: trip.fare.currency,
                  errorText: _fieldErrors['amount'],
                  helperText: 'Max ${trip.refundable.amount.toStringAsFixed(2)}',
                ),
                validator: cubit.validateRefundAmount,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _reason,
                maxLength: 200,
                decoration: InputDecoration(labelText: 'Reason', errorText: _fieldErrors['reason']),
                validator: cubit.validateReason,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_error != null)
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(
          onPressed: cubit.state.busy ? null : _submit,
          child: const Text('Refund'),
        ),
      ],
    );
  }
}
