import 'package:flutter/widgets.dart';

import 'passenger_ads_policy.dart';

class ExpressPassengerAds {
  const ExpressPassengerAds._();

  static Future<void> initialize() async {}
}

class PassengerAdSlot extends StatelessWidget {
  final Map<String, dynamic> settings;
  final PassengerAdPlacement placement;

  const PassengerAdSlot({
    super.key,
    required this.settings,
    required this.placement,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
