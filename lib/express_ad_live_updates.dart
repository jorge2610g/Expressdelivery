import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/supabase_client.dart';

/// Changes carry only revision metadata. Creatives are re-read via scoped RPCs.
class ExpressAdLiveUpdates {
  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _recovery;
  bool _disposed = false;

  ExpressAdLiveUpdates(String zoneId, void Function() refresh) {
    void changed() {
      if (_disposed) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 150), () {
        if (!_disposed) refresh();
      });
    }

    _channel = supabase
        .channel('ads-$zoneId-${DateTime.now().microsecondsSinceEpoch}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'express_ad_revisions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'zone_id',
            value: zoneId,
          ),
          callback: (_) => changed(),
        )
        .subscribe((status, _) {
          if (status == RealtimeSubscribeStatus.subscribed) changed();
        });
    // Scheduled campaigns and reconnects still reconcile if a socket was lost.
    _recovery = Timer.periodic(const Duration(seconds: 30), (_) => changed());
  }

  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _recovery?.cancel();
    final channel = _channel;
    if (channel != null) unawaited(supabase.removeChannel(channel));
  }
}
