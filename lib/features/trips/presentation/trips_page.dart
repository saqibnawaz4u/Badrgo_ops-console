import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/connectivity/presentation/refresh_on_recovery.dart';
import '../../../core/presentation/formatters.dart';
import '../../../core/presentation/widgets/page_header.dart';
import '../../../core/presentation/widgets/state_views.dart';
import '../domain/repositories/trips_repository.dart';
import 'bloc/trips_list_bloc.dart';
import 'widgets/trip_filters_bar.dart';
import 'widgets/trip_row.dart';

class TripsPage extends StatelessWidget {
  const TripsPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (context) => TripsListBloc(context.read<TripsRepository>())..add(const TripsStarted()),
    child: Builder(
      builder: (context) => RefreshOnRecovery(
        onRecovered: () => context.read<TripsListBloc>().add(const TripsRefreshRequested()),
        child: const _TripsView(),
      ),
    ),
  );
}

class _TripsView extends StatelessWidget {
  const _TripsView();

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TripsListBloc>();
    return Padding(
      padding: pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            title: 'Trips',
            badge: BlocBuilder<TripsListBloc, TripsListState>(
              buildWhen: (a, b) => a.totalCount != b.totalCount || a.status != b.status,
              builder: (context, state) => state.status == ListStatus.ready
                  ? CountPill('${formatCount(state.totalCount)} trips')
                  : const SizedBox.shrink(),
            ),
            actions: [
              if (!isCompact(context)) const _LiveLegend(),
              IconButton(
                tooltip: 'Reload',
                onPressed: () => bloc.add(const TripsRefreshRequested()),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 12),
          BlocBuilder<TripsListBloc, TripsListState>(
            buildWhen: (a, b) => a.filter != b.filter,
            builder: (context, state) => TripFiltersBar(
              filter: state.filter,
              onFilterChanged: (f) => bloc.add(TripsFilterChanged(f)),
              onSearchChanged: (q) => bloc.add(TripsSearchChanged(q)),
            ),
          ),
          const SizedBox(height: 12),
          const Expanded(child: _TripsList()),
        ],
      ),
    );
  }
}

class _TripsList extends StatelessWidget {
  const _TripsList();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TripsListBloc, TripsListState>(
      builder: (context, state) {
        final bloc = context.read<TripsListBloc>();
        switch (state.status) {
          case ListStatus.initial || ListStatus.loading:
            return const LoadingView(label: 'Loading trips…');
          case ListStatus.failure:
            return ErrorView(
              message: state.error ?? 'Unknown error',
              onRetry: () => bloc.add(const TripsRefreshRequested()),
            );
          case ListStatus.ready when state.items.isEmpty:
            return const MessageView(
              icon: Icons.inbox_outlined,
              title: 'No trips match',
              message: 'Try a different status, date range or search. New trips appear here live.',
            );
          case ListStatus.ready:
            break;
        }
        return Card(
          clipBehavior: Clip.antiAlias,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 300) bloc.add(const TripsLoadMoreRequested());
              return false;
            },
            child: ListView.separated(
              itemCount: state.items.length + 1,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                if (index == state.items.length) return _ListFooter(state: state);
                final trip = state.items[index];
                return TripRow(
                  key: ValueKey(trip.id),
                  trip: trip,
                  mark: state.marks[trip.id]?.kind,
                  onTap: () => context.go('/trips/${trip.id}'),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _ListFooter extends StatelessWidget {
  const _ListFooter({required this.state});

  final TripsListState state;

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<TripsListBloc>();
    Widget child;
    if (state.loadingMore) {
      child = const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2));
    } else if (state.loadMoreError != null) {
      child = TextButton.icon(
        onPressed: () => bloc.add(const TripsLoadMoreRequested()),
        icon: const Icon(Icons.refresh),
        label: Text('Could not load more: ${state.loadMoreError}. Retry'),
      );
    } else if (state.hasNextPage) {
      child = TextButton(onPressed: () => bloc.add(const TripsLoadMoreRequested()), child: const Text('Load more'));
    } else {
      child = Text('All ${state.items.length} trips loaded', style: Theme.of(context).textTheme.bodySmall);
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(child: child),
    );
  }
}

class _LiveLegend extends StatelessWidget {
  const _LiveLegend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const RowMarkBadge.created(),
        const SizedBox(width: 4),
        Text('arrived live', style: style),
        const SizedBox(width: 12),
        const RowMarkBadge.updated(),
        const SizedBox(width: 4),
        Text('changed live', style: style),
      ],
    );
  }
}
