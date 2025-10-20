import 'dart:isolate';

import 'package:datum/source/core/engine/isolate_helper.dart';
import 'package:test/test.dart';

// This must be a top-level function to be used as an isolate entry point.
void _isolateEntryPoint(List<dynamic> message) {
  final sendPort = message[0] as SendPort;
  final data = message[1] as String;
  sendPort.send('Isolate received: $data');
}

void main() {
  group('IsolateHelper', () {
    late IsolateHelper isolateHelper;

    setUp(() {
      isolateHelper = const IsolateHelper();
    });

    test('spawn creates and runs an isolate', () async {
      // Arrange
      final receivePort = ReceivePort();
      final message = [receivePort.sendPort, 'hello'];

      // Act
      final isolate = await isolateHelper.spawn(_isolateEntryPoint, message);

      // Assert
      // Wait for the isolate to send a message back to confirm it's running.
      final response = await receivePort.first;
      expect(response, 'Isolate received: hello');

      // Clean up
      receivePort.close();
      isolate.kill();
    });

    test('computeJsonEncode correctly encodes an object', () async {
      // Arrange
      final objectToEncode = {'key': 'value', 'number': 123};
      const expectedJson = '{"key":"value","number":123}';

      // Act
      final jsonString = await isolateHelper.computeJsonEncode(objectToEncode);

      // Assert
      expect(jsonString, expectedJson);
    });
  });
}
