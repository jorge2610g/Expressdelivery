import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Este contrato prueba el diseño del canario Preview, NO el despliegue
/// de Edge Functions ni la entrega de mensajes FCM en un dispositivo real.
void main() {
  late String dispatch;
  late String proposal;

  setUpAll(() {
    dispatch = File('supabase/functions/express-push-dispatch/index.ts')
        .readAsStringSync();
    proposal = File(
      'docs/pending_migrations/20261018_offer_invalidation_preview_PROPOSAL.sql',
    ).readAsStringSync();
  });

  test('preview data-only requires an enabled single-token canary', () {
    expect(dispatch, contains('EXPRESS_OVERLAY_DATA_PUSH'));
    expect(dispatch, contains('EXPRESS_OVERLAY_ALLOWLIST'));
    expect(dispatch, contains('overlayAllowlist.size === 1'));
    expect(dispatch, contains('device.floating_offer_enabled === true'));
    expect(dispatch, contains('permission_checked_at'));
    expect(dispatch, contains('String(device.channel ?? "").toLowerCase() === "preview"'));
  });

  test('invalidations are silent and do not turn trip cancellation silent', () {
    expect(dispatch, contains('"ride_request_invalidated"'));
    expect(dispatch, contains('overlayInvalidationTypes.has(type) && !dataOnly'));
    expect(dispatch, contains('const dataOnly = overlayEligible(device)'));
    expect(dispatch, contains('dataOnly && type === "ride_request"'));
    expect(dispatch, contains('ttl: type === "ride_request"'));
  });

  test('server validates that a request is still live before FCM dispatch', () {
    expect(dispatch, contains('ride_request_no_longer_active'));
    expect(dispatch, contains('.select("status,expires_at,channel")'));
    expect(dispatch, contains('row.status === "searching"'));
    expect(dispatch, contains('row.status === "offers_received"'));
    expect(dispatch, contains('expires > Date.now()'));
  });

  test('invalidation SQL is a proposal scoped to Preview', () {
    expect(proposal, contains('NO EJECUTADA'));
    expect(proposal, contains("NEW.channel <> 'preview'"));
    expect(proposal, contains("n.channel = 'preview'"));
    expect(proposal, contains("t.channel = 'preview'"));
    expect(proposal, contains("'ride_request_invalidated'"));
    expect(proposal, contains("'ride_request_id', NEW.id"));
  });
}
