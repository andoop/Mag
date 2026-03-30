import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_agent/core/models.dart';

void main() {
  test('newId generates stable prefix', () {
    final id = newId('session');
    expect(id.startsWith('session-'), isTrue);
  });
}
