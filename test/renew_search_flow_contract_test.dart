import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contratos del flujo «Seguir buscando 3 min» / «Subir mi oferta».
/// La prueba real se hace en los emuladores; aquí se fija la lógica crítica.
void main() {
  late String home;
  late String proposal;

  setUpAll(() {
    home = File('lib/video_style_home.dart').readAsStringSync();
    proposal = File(
      'docs/pending_migrations/20261018_renew_search_visibility_PROPOSAL.sql',
    ).readAsStringSync();
  });

  String decisionBody() {
    final start = home.indexOf('Future<void> _showSearchRenewalDecision(');
    final end = home.indexOf('Future<num?> _askSearchFare(');
    expect(start, isNonNegative, reason: 'missing _showSearchRenewalDecision');
    expect(end, greaterThan(start));
    return home.substring(start, end);
  }

  test('raise branch never cancels the search when the fare prompt is dismissed or fails', () {
    final body = decisionBody();
    final raise = body.indexOf("if (result == 'raise') {");
    final finalCancel = body.lastIndexOf('await _cancelExpiredRideSilently(id);');
    expect(raise, isNonNegative);
    expect(finalCancel, greaterThan(raise));

    final raiseBlock = body.substring(raise, finalCancel);
    expect(raiseBlock, isNot(contains('_cancelExpiredRideSilently')));
    expect(
      'return _reopenSearchRenewalDecision(ride);'.allMatches(raiseBlock).length,
      2,
      reason: 'Volver and a failed renewal both return to the decision',
    );
  });

  test('reopening the decision keeps the prompt guard in place', () {
    final start = home.indexOf('Future<void> _reopenSearchRenewalDecision(');
    expect(start, isNonNegative);
    final helper = home.substring(start, start + 400);
    expect(helper, contains('renewalDecisionOpen = true;'));
    expect(helper, contains('renewalDecisionRideId = id;'));
    expect(helper, contains('return _showSearchRenewalDecision(ride);'));
  });

  test('continue and raise publish a new taxi request; renewal is kept only for parcels', () {
    final body = decisionBody().split('Future<void> _searchAgainFor(').first;
    expect(
      'await _searchAgainFor('.allMatches(body).length,
      2,
      reason: 'Seguir and Subir both publish again',
    );
    expect(body, isNot(contains('renewRideRequest(')));

    final start = home.indexOf('Future<void> _searchAgainFor(');
    final end = home.indexOf('Future<void> _reopenSearchRenewalDecision(');
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final helper = home.substring(start, end);
    expect(helper, contains('createRideRequest('));
    expect(helper, contains("if (ride['service_mode'] == 'parcel')"));
    expect(helper, contains('renewRideRequest('));
  });

  test('Subir is a direct adjust panel with the confirmed fare as floor and the request currency', () {
    final start = home.indexOf('class _SearchFareDialogState');
    final end = home.indexOf('class _SearchRoundDecisionDialog');
    expect(start, isNonNegative);
    expect(end, greaterThan(start));
    final panel = home.substring(start, end);
    expect(panel, contains('late final num step = widget.step;'));
    expect(panel, contains('No puedes bajar de la oferta confirmada.'));
    expect(panel, contains('bool get _canDecrease => offer - step >= widget.initialFare;'));
    expect(panel, contains('offer > widget.initialFare'));
    expect(panel, contains('Navigator.pop(context, offer)'));
    expect(panel, contains('Buscar 3 min más'));
    expect(panel, isNot(contains('TextField(')));

    final raise = home.substring(
      home.indexOf("if (result == 'raise') {"),
      home.indexOf('Future<num?> _askSearchFare('),
    );
    expect(raise, contains("ride['currency']?.toString()"));
  });

  test('decision copy names the request type and never says repartidor', () {
    expect(home, contains("'Seguimos buscando un conductor para tu '"));
    expect(home, contains("'\${widget.isParcel ? 'envío' : 'viaje'}. '"));
    expect(home, isNot(contains('Seguimos buscando un repartidor')));
  });

  test('a successful renewal keeps its prompt key so stale data cannot re-prompt and cancel', () {
    expect(home, isNot(contains('renewalPromptedRideIds.remove(')));
    expect(home, contains(r"final promptKey = '$id|${expiresAt.toIso8601String()}';"));
    expect(home, contains('renewalPromptedRideIds.contains(promptKey)'));
  });

  test('pending SQL proposal stamps a fresh search start and filters drivers on it', () {
    expect(proposal, contains('add column if not exists search_started_at timestamptz'));
    expect(proposal, contains('search_started_at = now(),'));
    expect(
      proposal,
      contains('coalesce(r.search_started_at, r.created_at) >'),
    );
    expect(proposal, isNot(contains('or r.created_at >')));
  });
}
