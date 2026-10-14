import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('review notifications open document corrections even before approval', () {
    final source = File('lib/connected_experience.dart').readAsStringSync();
    final handler = source.substring(
      source.indexOf('Future<void> _handlePushEvent('),
      source.indexOf('String? targetMode = event.mode;'),
    );
    expect(handler, contains("event.type == 'driver_document_review'"));
    expect(handler, contains("focusSection: 'documents'"));
    expect(handler, contains('editExisting: true'));
    expect(handler, contains("if (!mounted) return;"));
    expect(handler, contains('DriverSetupPage('));
  });
}
