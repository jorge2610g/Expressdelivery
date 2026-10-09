import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/supabase_client.dart';

/// Watches changes to the signed-in driver's registration without subscribing
/// to every driver's location and without repeatedly querying the database.
///
/// Production already publishes driver_profiles and notifications to Realtime.
/// Documents are not in the Realtime publication, so the registration detail
/// screen uses a slow foreground-only fallback and refreshes on app resume.
class DriverRegistrationStatusWatcher with WidgetsBindingObserver {
  DriverRegistrationStatusWatcher({
    required this.userId,
    required this.onChanged,
    this.fallbackEvery,
  });

  final String userId;
  final VoidCallback onChanged;
  final Duration? fallbackEvery;

  RealtimeChannel? _channel;
  Timer? _debounce;
  Timer? _fallback;
  String? _lastProfileSignature;
  bool _started = false;
  bool _disposed = false;
  bool _foreground = true;

  /// Ignore GPS/heading/time changes: otherwise driver tracking would cause
  /// a network reload of the registration screen on every location update.
  static String profileStatusSignature(Map<String, dynamic> profile) {
    const fields = <String>[
      'approval_status',
      'online_status',
      'zone_id',
      'country_code',
      'onboarding_completed_at',
      'profile_photo_path',
      'vehicle_summary',
      'license_number',
    ];
    return fields.map((key) => '$key=${profile[key] ?? ''}').join('|');
  }

  void start() {
    if (_started || _disposed) return;
    final currentUserId = supabase.auth.currentUser?.id;
    if (currentUserId == null || currentUserId != userId) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    _channel = supabase
        .channel('driver-registration-$userId-${identityHashCode(this)}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'driver_profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (event) {
            final row = event.newRecord;
            if (row.isEmpty) {
              _scheduleReload();
              return;
            }
            final signature = profileStatusSignature(row);
            if (signature == _lastProfileSignature) return;
            _lastProfileSignature = signature;
            _scheduleReload();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (event) {
            final type =
                event.newRecord['type']?.toString().toLowerCase() ?? '';
            if (type.contains('driver') ||
                type.contains('identity') ||
                type.contains('kyc') ||
                type.contains('document')) {
              _scheduleReload();
            }
          },
        )
        .subscribe((status, error) {
          // If Android loses its websocket while the app stays open,
          // reconcile the source of truth as soon as Realtime reconnects.
          // The debounce coalesces this with profile/notification events.
          if (status == RealtimeSubscribeStatus.subscribed) {
            _scheduleReload();
          }
        });

    if (fallbackEvery != null) {
      _fallback = Timer.periodic(fallbackEvery!, (_) => _scheduleReload());
    }
  }

  void _scheduleReload() {
    if (_disposed || !_foreground || supabase.auth.currentUser?.id != userId) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () {
      if (!_disposed &&
          _foreground &&
          supabase.auth.currentUser?.id == userId) {
        onChanged();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nowForeground = state == AppLifecycleState.resumed;
    if (nowForeground && !_foreground) {
      _foreground = true;
      _scheduleReload();
    } else if (!nowForeground) {
      _foreground = false;
      _debounce?.cancel();
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounce?.cancel();
    _fallback?.cancel();
    if (_started) WidgetsBinding.instance.removeObserver(this);
    final channel = _channel;
    if (channel != null) unawaited(supabase.removeChannel(channel));
    _channel = null;
  }
}
