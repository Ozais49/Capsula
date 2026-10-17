import 'package:capsula_web/main.dart' as web;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the web entry point is the app', () {
    expect(web.main, isA<Future<void> Function()>());
  });
}
