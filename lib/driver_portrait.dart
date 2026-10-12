import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    _imageBytes = null;
    _exhausted = false;
    _loading = true;
    if (mounted) setState(() {});
    unawaited(_fetch(generation, 0));
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
    final hasSource = widget.approvedPath?.trim().isNotEmpty == true ||
        widget.driverId?.trim().isNotEmpty == true;
    final fallback = widget.fallbackUrl?.trim() ?? '';
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
              : (_loading || (hasSource && !_exhausted))
                  ? const Center(child: SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2)))
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
