import 'package:flutter/foundation.dart';

@immutable
class ExpressPassengerUiSnapshot {
  final String? openRideId;
  final int uiOfferCount;
  final bool searchPanelMounted;
  final bool offersCardMounted;
  final int loadRevision;
  final int panelRevision;
  final String lastEvent;
  final DateTime updatedAt;

  const ExpressPassengerUiSnapshot({
    this.openRideId,
    this.uiOfferCount = 0,
    this.searchPanelMounted = false,
    this.offersCardMounted = false,
    this.loadRevision = 0,
    this.panelRevision = 0,
    this.lastEvent = 'INIT',
    required this.updatedAt,
  });

  ExpressPassengerUiSnapshot copyWith({
    String? openRideId,
    bool clearOpenRideId = false,
    int? uiOfferCount,
    bool? searchPanelMounted,
    bool? offersCardMounted,
    int? loadRevision,
    int? panelRevision,
    String? lastEvent,
  }) {
    return ExpressPassengerUiSnapshot(
      openRideId: clearOpenRideId ? null : (openRideId ?? this.openRideId),
      uiOfferCount: uiOfferCount ?? this.uiOfferCount,
      searchPanelMounted: searchPanelMounted ?? this.searchPanelMounted,
      offersCardMounted: offersCardMounted ?? this.offersCardMounted,
      loadRevision: loadRevision ?? this.loadRevision,
      panelRevision: panelRevision ?? this.panelRevision,
      lastEvent: lastEvent ?? this.lastEvent,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}

class ExpressDiagnosticsHub {
  ExpressDiagnosticsHub._();

  static final ValueNotifier<ExpressPassengerUiSnapshot> passengerUi =
      ValueNotifier<ExpressPassengerUiSnapshot>(
    ExpressPassengerUiSnapshot(updatedAt: DateTime.now().toUtc()),
  );

  static void updatePassengerUi({
    required String? openRideId,
    required int uiOfferCount,
    required bool searchPanelMounted,
    required bool offersCardMounted,
    required int loadRevision,
    required int panelRevision,
  }) {
    final current = passengerUi.value;
    if (current.openRideId == openRideId &&
        current.uiOfferCount == uiOfferCount &&
        current.searchPanelMounted == searchPanelMounted &&
        current.offersCardMounted == offersCardMounted &&
        current.loadRevision == loadRevision &&
        current.panelRevision == panelRevision) {
      return;
    }

    passengerUi.value = ExpressPassengerUiSnapshot(
      openRideId: openRideId,
      uiOfferCount: uiOfferCount,
      searchPanelMounted: searchPanelMounted,
      offersCardMounted: offersCardMounted,
      loadRevision: loadRevision,
      panelRevision: panelRevision,
      lastEvent: current.lastEvent,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  static void note(String event) {
    final trimmed = event.trim();
    if (trimmed.isEmpty) return;
    passengerUi.value = passengerUi.value.copyWith(lastEvent: trimmed);
  }
}
