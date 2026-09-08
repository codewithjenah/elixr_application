import 'package:elixr_application/data/models/recognition_event.dart';
import 'package:elixr_application/data/models/ws_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('locked movement identity is never exposed from wire JSON', () {
    final event = RecognitionEvent.fromJson({
      'session_id': 's1',
      'event_id': 'e1',
      'kind': 'movement',
      'display_label': 'Elbow Stall',
      'identity_revealed': false,
      'quality': 'perfect',
      'movement': 'Elbow Stall',
      'prop_type': 'bottle',
      'supporting_message': 'Keep progressing to discover this movement.',
    });
    expect(event.kind, RecognitionKind.advancedTechnique);
    expect(event.movement, isNull);
    expect(event.identityRevealed, isFalse);
    expect(event.displayLabel, 'Advanced technique detected');
    expect(event.displayLabel, isNot(contains('Elbow')));
    expect(
      event.supportingMessage,
      'Keep progressing to discover this movement.',
    );
  });

  test('advanced_technique kind stays generic even if a name leaks', () {
    final event = RecognitionEvent.fromJson({
      'session_id': 's1',
      'event_id': 'e2',
      'kind': 'advanced_technique',
      'display_label': 'Forearm Stall',
      'identity_revealed': false,
      'movement': 'Forearm Stall',
    });
    expect(event.displayLabel, 'Advanced technique detected');
    expect(event.movement, isNull);
  });

  test('flip is a generic event without a catalog movement name', () {
    final event = RecognitionEvent.fromJson({
      'session_id': 's1',
      'event_id': 'e3',
      'kind': 'flip',
      'display_label': 'Flip',
      'identity_revealed': true,
      'quality': 'great',
      'movement': 'Bottle Flip',
      'prop_type': 'shaker',
    });
    expect(event.kind, RecognitionKind.flip);
    expect(event.displayLabel, 'Flip');
    expect(event.movement, isNull);
    expect(event.countsForCombo, isTrue);
  });

  test('decoder accepts recognition_event messages', () {
    const decoder = WsMessageDecoder();
    final decoded = decoder.decode(
      '{"message_type":"recognition_event","session_id":"s1","event_id":"e9",'
      '"kind":"movement","display_label":"Normal Grip","identity_revealed":true,'
      '"quality":"nice","movement":"Normal Grip","prop_type":"bottle"}',
    );
    expect(decoded, isA<WsRecognitionEventMessage>());
    final event = (decoded as WsRecognitionEventMessage).event;
    expect(event.displayLabel, 'Normal Grip');
    expect(event.movement, 'Normal Grip');
    expect(event.quality, RecognitionQuality.nice);
  });
}
