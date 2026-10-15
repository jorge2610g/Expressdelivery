import 'package:expressdelivery/express_offline_banner.dart';
import 'package:expressdelivery/offline_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  final monitor = ExpressConnectivityMonitor.instance;

  setUp(() {
    monitor.probe = null;
    monitor.recordSuccess('test_reset');
  });

  testWidgets('online shows nothing and never claims a connection state', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Stack(children: [ExpressOfflineBanner()])),
    ));
    expect(find.textContaining('Sin conexión'), findsNothing);
    expect(find.textContaining('Reconectando'), findsNothing);
  });

  testWidgets('offline shows the offline label and the age of saved data', (tester) async {
    monitor.recordSuccess('passenger_home');
    monitor.recordFailure(http.ClientException('down'));
    monitor.recordFailure(http.ClientException('down'));
    monitor.recordFailure(http.ClientException('down'));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Stack(children: [ExpressOfflineBanner()])),
    ));
    expect(find.textContaining('Sin conexión'), findsOneWidget);
    expect(find.textContaining('datos hace un momento'), findsOneWidget);
    monitor.recordSuccess('test_reset');
  });

  testWidgets('reconnecting is labelled as reconnecting, not offline', (tester) async {
    monitor.recordFailure(http.ClientException('down'));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Stack(children: [ExpressOfflineBanner()])),
    ));
    expect(find.textContaining('Reconectando'), findsOneWidget);
    expect(find.textContaining('Sin conexión'), findsNothing);
    monitor.recordSuccess('test_reset');
  });

  testWidgets('the banner never absorbs taps on the map beneath it', (tester) async {
    monitor.recordFailure(http.ClientException('down'));
    var tapped = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => tapped++,
              child: const ColoredBox(color: Colors.white),
            ),
          ),
          const ExpressOfflineBanner(),
        ]),
      ),
    ));
    await tester.tapAt(const Offset(200, 400));
    expect(tapped, 1);
    monitor.recordSuccess('test_reset');
  });

  testWidgets('recovery removes the banner once a read succeeds', (tester) async {
    for (var i = 0; i < 3; i++) {
      monitor.recordFailure(http.ClientException('down'));
    }
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Stack(children: [ExpressOfflineBanner()])),
    ));
    expect(find.textContaining('Sin conexión'), findsOneWidget);
    monitor.recordSuccess('passenger_home');
    await tester.pump();
    expect(find.textContaining('Sin conexión'), findsNothing);
    expect(find.textContaining('Reconectando'), findsNothing);
  });
}
