import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Cache only authorized object paths and only for the current Supabase viewer.
// Different upload paths never reuse the previous driver's portrait.
final Map<String, Uint8List> _sessionPortraitBytes = <String, Uint8List>{};
const int _maxSessionPortraits = 16;
String? _currentPortraitCacheKey(String? path) {
  final viewer = Supabase.instance.client.auth.currentUser?.id;
  final actualPath = path?.trim() ?? '';
  if (viewer == null || actualPath.isEmpty) return null;
  return '$viewer:$actualPath';
}

/// Never show an old public avatar while a newer private photo is loading.
String? driverPortraitFallback(
  String? authorizedPath,
  String? fallbackUrl, {
  String? driverId,
}) {
  // A driver identity with no private photo path must not briefly display
  // the legacy public users.avatar_url while the authorized path is fetched.
  if (driverId?.trim().isNotEmpty == true ||
      authorizedPath?.trim().isNotEmpty == true) return null;
  final fallback = fallbackUrl?.trim() ?? '';
  return fallback.isNotEmpty ? fallback : null;
}

/// Merge a live passenger offer update without discarding previously
/// enriched driver data when a bare Realtime row arrives later.
/// If the server explicitly supplies a null authorized path, respect it.
Map<String, dynamic> refreshedPassengerOffer(
  Map<String, dynamic> previous,
  Map<String, dynamic> incoming,
) {
  final merged = <String, dynamic>{...previous, ...incoming};
  for (final key in ['driver_profiles', 'driver_user']) {
    if (!incoming.containsKey(key) && previous.containsKey(key)) {
      merged[key] = previous[key];
    }
  }
  return merged;
}

/// Read an already authorized path delivered with a driver's live offer.
/// Never trust a user-facing avatar URL as proof of private portrait access.
String? authorizedOfferPortraitPath(Map<String, dynamic> offer) {
  final id = offer['driver_id']?.toString() ?? '';
  final nested = offer['driver_profiles'];
  if (id.isEmpty || nested is! Map) return null;
  final path = nested['profile_photo_path']?.toString().trim() ?? '';
  return path.startsWith('$id/') && path.length > id.length + 1
      ? path
      : null;
}

/// Keeps one authorized, private driver portrait in memory for the lifetime
/// of the active view. No short-lived signed image URL or public bucket.
class ExpressDriverPortrait extends StatefulWidget {
  final String? driverId;
  final String? approvedPath;
  final String? fallbackUrl;
  final double radius;

  const ExpressDriverPortrait({
    super.key,
    this.driverId,
    this.approvedPath,
    this.fallbackUrl,
    this.radius = 25,
  });

  @override
  State<ExpressDriverPortrait> createState() => _ExpressDriverPortraitState();
}

class _ExpressDriverPortraitState extends State<ExpressDriverPortrait>
    with WidgetsBindingObserver {
  Uint8List? _imageBytes;
  Timer? _retry;
  int _generation = 0;
  bool _loading = false;
  bool _exhausted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _begin();
  }

  @override
  void didUpdateWidget(ExpressDriverPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    final freshPath = widget.approvedPath?.trim() ?? '';
    final previousPath = oldWidget.approvedPath?.trim() ?? '';
    if (oldWidget.driverId != widget.driverId ||
        (freshPath.isNotEmpty && freshPath != previousPath)) {
      _begin();
    }
    // Temporary null profile data during GPS/state refresh must not erase
    // the photograph already fetched for this same driver.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _imageBytes == null && !_loading) {
      _begin();
    }
  }

  void _begin() {
    _retry?.cancel();
    final generation = ++_generation;
    final cacheKey = _currentPortraitCacheKey(widget.approvedPath);
    _imageBytes = cacheKey == null ? null : _sessionPortraitBytes[cacheKey];
    _exhausted = false;
    // A cached photo stays visible without an intermediate white/old-avatar frame.
    _loading = _imageBytes == null;
    if (mounted) setState(() {});
    if (_imageBytes == null) unawaited(_fetch(generation, 0));
  }

  Future<void> _fetch(int generation, int attempt) async {
    if (!mounted || generation != _generation) return;
    try {
      var path = widget.approvedPath?.trim() ?? '';
      final id = widget.driverId?.trim() ?? '';
      if (path.isEmpty && id.isNotEmpty) {
        // Server checks current passenger/offer/driver permission.
        final raw = await Supabase.instance.client.rpc(
          'driver_profile_for_viewer',
          params: {'p_driver_id': id},
        );
        if (raw is Map) {
          path = raw['profile_photo_path']?.toString().trim() ?? '';
        }
      }
      if (!mounted || generation != _generation) return;
      if (path.isEmpty) {
        setState(() {
          _loading = false;
          _exhausted = true;
        });
        return;
      }
      // Private object download with the current user's storage RLS.
      final bytes = await Supabase.instance.client.storage
          .from('driver-onboarding').download(path);
      if (!mounted || generation != _generation) return;
      if (bytes.isEmpty) throw StateError('Empty private portrait');
      final cacheKey = _currentPortraitCacheKey(path);
      if (cacheKey != null) {
        if (_sessionPortraitBytes.length >= _maxSessionPortraits &&
            !_sessionPortraitBytes.containsKey(cacheKey)) {
          _sessionPortraitBytes.remove(_sessionPortraitBytes.keys.first);
        }
        _sessionPortraitBytes[cacheKey] = bytes;
      }
      setState(() {
        _imageBytes = bytes;
        _loading = false;
        _exhausted = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() => _loading = false);
      if (attempt < 4) {
        _retry = Timer(Duration(seconds: 2 * (attempt + 1)), () {
          if (!mounted || generation != _generation) return;
          setState(() => _loading = true);
          unawaited(_fetch(generation, attempt + 1));
        });
      } else {
        setState(() => _exhausted = true);
      }
    }
  }

  @override
  void dispose() {
    ++_generation;
    _retry?.cancel();
    _imageBytes = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _imageBytes;
    // An outdated users.avatar_url must not flash before the private image.
    final fallback = driverPortraitFallback(
          widget.approvedPath,
          widget.fallbackUrl,
          driverId: widget.driverId,
        ) ?? '';
    final diameter = widget.radius * 2;
    final defaultIcon = Icon(Icons.person_rounded,
      color: Theme.of(context).colorScheme.primary, size: diameter * .52);
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: ClipOval(
        child: SizedBox(
          width: diameter,
          height: diameter,
          child: bytes != null
              ? Image.memory(bytes, fit: BoxFit.cover,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) =>
                      Center(child: defaultIcon))
              : fallback.isNotEmpty
                  ? Image.network(fallback, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          _manualRetry(defaultIcon))
                  : _manualRetry(defaultIcon),
        ),
      ),
    );
  }

  Widget _manualRetry(Widget fallback) {
    if (widget.driverId?.trim().isNotEmpty != true &&
        widget.approvedPath?.trim().isNotEmpty != true) {
      return Center(child: fallback);
    }
    return InkWell(
      onTap: _begin,
      child: Center(child: _exhausted
          ? const Icon(Icons.refresh_rounded, size: 22)
          : fallback),
    );
  }
}
