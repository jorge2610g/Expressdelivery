import 'package:flutter/widgets.dart';

import 'services/express_service.dart';

Future<void> initializeExpressAds() async {}

class ExpressPassengerAdBanner extends StatelessWidget {
  final ExpressService service;
  final String placement;

  const ExpressPassengerAdBanner({
    super.key,
    required this.service,
    required this.placement,
  });

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
