import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Listens to Supabase Realtime changes on one or more tables and calls
/// [onChange] (debounced, so a burst of changes triggers one refresh).
/// Always call [dispose] when the screen/provider goes away.
///
/// Requires the tables to be in the `supabase_flutter` realtime
/// publication — see supabase/017_realtime.sql.
class TableWatcher {
  final void Function() onChange;
  final Duration debounce;
  final List<RealtimeChannel> _channels = [];
  Timer? _timer;
  bool _disposed = false;

  TableWatcher(this.onChange, {this.debounce = const Duration(milliseconds: 600)});

  /// Watches [table]. [event] defaults to every change; pass
  /// [filterColumn]/[filterValue] to only hear about matching rows.
  void watch(
    String table, {
    PostgresChangeEvent event = PostgresChangeEvent.all,
    String? filterColumn,
    String? filterValue,
  }) {
    if (_disposed) return;
    final client = Supabase.instance.client;
    final name = 'watch_${table}_${identityHashCode(this)}_${_channels.length}';
    final channel = client.channel(name).onPostgresChanges(
          event: event,
          schema: 'public',
          table: table,
          filter: filterColumn == null || filterValue == null
              ? null
              : PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: filterColumn, value: filterValue),
          callback: (_) => _schedule(),
        );
    channel.subscribe();
    _channels.add(channel);
  }

  void _schedule() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, () {
      if (!_disposed) onChange();
    });
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    final client = Supabase.instance.client;
    for (final c in _channels) {
      client.removeChannel(c);
    }
    _channels.clear();
  }
}
