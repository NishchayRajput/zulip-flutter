import 'package:checks/checks.dart';
import 'package:test/scaffolding.dart';
import 'package:zulip/api/notifications.dart';

import '../stdlib_checks.dart';

void main() {
  final baseBaseJson = {
    "server": "zulip.example.cloud",
    "realm_id": "4",
    "realm_uri": "https://zulip.example.com/",
    "user_id": "234",
  };

  void checkParseFails(Map<String, String> data) {
    check(() => FcmMessage.fromJson(data)).throws();
  }

  group('FcmMessage', () {
    test('parse fails on missing or bad event type', () {
      check(FcmMessage.fromJson({})).isA<UnexpectedFcmMessage>();
      check(FcmMessage.fromJson({'event': 'nonsense'})).isA<UnexpectedFcmMessage>();
    });
  });

  group('MessageFcmMessage', () {
    final baseJson = {
      ...baseBaseJson,
      "event": "message",

      "sender_id": "123",
      "sender_email": "sender@example.com",
      "sender_avatar_url": "https://zulip.example.com/avatar/123.jpeg",
      "sender_full_name": "A Sender",

      "time": "1546300800",
      "zulip_message_id": "12345",

      "content": "This is a message",
      "content_truncated": "This is a m…",
    };

    final streamJson = {
      ...baseJson,
      "recipient_type": "stream",
      "stream_id": "42",
      "stream": "denmark",
      "topic": "play",

      "alert": "New stream message from A Sender in denmark",
    };

    final groupDmJson = {
      ...baseJson,
      "recipient_type": "private",
      "pm_users": "123,234,345",

      "alert": "New private group message from A Sender",
    };

    final dmJson = {
      ...baseJson,
      "recipient_type": "private",

      "alert": "New private message from A Sender",
    };

    MessageFcmMessage parse(Map<String, dynamic> json) {
      return FcmMessage.fromJson(json) as MessageFcmMessage;
    }

    test("fields get parsed right in happy path", () {
      check(parse(streamJson))
        ..server.equals(baseJson['server']!)
        ..realmId.equals(4)
        ..realmUri.equals(Uri.parse(baseJson['realm_uri']!))
        ..userId.equals(234)
        ..senderId.equals(123)
        ..senderEmail.equals(streamJson['sender_email']!)
        ..senderAvatarUrl.equals(Uri.parse(streamJson['sender_avatar_url']!))
        ..senderFullName.equals(streamJson['sender_full_name']!)
        ..zulipMessageId.equals(12345)
        ..recipient.isA<FcmMessageStreamRecipient>().which(it()
          ..streamId.equals(42)
          ..streamName.equals(streamJson['stream']!)
          ..topic.equals(streamJson['topic']!))
        ..content.equals(streamJson['content']!)
        ..time.equals(1546300800);

      check(parse(groupDmJson))
        .recipient.isA<FcmMessageDmRecipient>()
        .allRecipientIds.deepEquals([123, 234, 345]);

      check(parse(dmJson))
        .recipient.isA<FcmMessageDmRecipient>()
        .allRecipientIds.deepEquals([123, 234]);
    });

    test('optional fields missing cause no error', () {
      check(parse({ ...streamJson }..remove('stream')))
        .recipient.isA<FcmMessageStreamRecipient>().which(it()
          ..streamId.equals(42)
          ..streamName.isNull());
    });

    test('toJson round-trips', () {
      void checkRoundTrip(Map<String, String> json) {
        check(parse(json).toJson())
          .deepEquals({ ...json }
            ..remove('recipient_type') // Redundant with stream_id.
            ..remove('content_truncated') // Redundant with content.
            ..remove('alert') // Redundant with the other data; we make our own UI.
          );
      }

      checkRoundTrip(streamJson);
      checkRoundTrip(groupDmJson);
      checkRoundTrip(dmJson);
      checkRoundTrip({ ...streamJson }..remove('stream'));
    });

    test('ignored fields missing have no effect', () {
      final baseline = parse(streamJson);
      check(parse({ ...streamJson }..remove('recipient_type'))).jsonEquals(baseline);
      check(parse({ ...streamJson }..remove('content_truncated'))).jsonEquals(baseline);
      check(parse({ ...streamJson }..remove('alert'))).jsonEquals(baseline);
    });

    test('obsolete or novel fields have no effect', () {
      final baseline = parse(dmJson);
      void checkInert(Map<String, String> extraJson) =>
        check(parse({ ...dmJson, ...extraJson })).jsonEquals(baseline);

      // Cut in 2017, in zulip/zulip@c007b9ea4.
      checkInert({ 'user': 'client@example.com' });

      // Hypothetical future field.
      checkInert({ 'awesome_feature': 'enabled' });
    });

    group("parse failures on malformed 'message'", () {
      int n = 1;
      test("${n++}", () => checkParseFails({ ...dmJson }..remove('server')));
      test("${n++}", () => checkParseFails({ ...dmJson }..remove('realm_id')));
      test("${n++}", () => checkParseFails({ ...dmJson, 'realm_id': '12,34' }));
      test("${n++}", () => checkParseFails({ ...dmJson, 'realm_id': 'abc' }));
      test("${n++}", () => checkParseFails({ ...dmJson }..remove('realm_uri')));
      test(skip: true, // Dart's Uri.parse is lax in what it accepts.
           "${n++}", () => checkParseFails({ ...dmJson, 'realm_uri': 'zulip.example.com' }));
      test(skip: true, // Dart's Uri.parse is lax in what it accepts.
           "${n++}", () => checkParseFails({ ...dmJson, 'realm_uri': '/examplecorp' }));

      test("${n++}", () => checkParseFails({ ...streamJson, 'stream_id': '12,34' }));
      test("${n++}", () => checkParseFails({ ...streamJson, 'stream_id': 'abc' }));
      test("${n++}", () => checkParseFails({ ...streamJson }..remove('topic')));
      test("${n++}", () => checkParseFails({ ...groupDmJson, 'pm_users': 'abc,34' }));
      test("${n++}", () => checkParseFails({ ...groupDmJson, 'pm_users': '12,abc' }));
      test("${n++}", () => checkParseFails({ ...groupDmJson, 'pm_users': '12,' }));

      test("${n++}", () => checkParseFails({ ...dmJson }..remove('sender_avatar_url')));
      test(skip: true, // Dart's Uri.parse is lax in what it accepts.
           "${n++}", () => checkParseFails({ ...dmJson, 'sender_avatar_url': '/avatar/123.jpeg' }));
      test(skip: true, // Dart's Uri.parse is lax in what it accepts.
           "${n++}", () => checkParseFails({ ...dmJson, 'sender_avatar_url': '' }));

      test("${n++}", () => checkParseFails({ ...dmJson }..remove('sender_id')));
      test("${n++}", () => checkParseFails({ ...dmJson }..remove('sender_email')));
      test("${n++}", () => checkParseFails({ ...dmJson }..remove('sender_full_name')));
      test("${n++}", () => checkParseFails({ ...dmJson }..remove('zulip_message_id')));
      test("${n++}", () => checkParseFails({ ...dmJson, 'zulip_message_id': '12,34' }));
      test("${n++}", () => checkParseFails({ ...dmJson, 'zulip_message_id': 'abc' }));
      test("${n++}", () => checkParseFails({ ...dmJson }..remove('content')));
      test("${n++}", () => checkParseFails({ ...dmJson }..remove('time')));
      test("${n++}", () => checkParseFails({ ...dmJson, 'time': '12:34' }));
    });
  });

  group('RemoveFcmMessage', () {
    final baseJson = {
      ...baseBaseJson,
      'event': 'remove',

      'zulip_message_ids': '123,234',
      'zulip_message_id': '123',
    };

    RemoveFcmMessage parse(Map<String, dynamic> json) {
      return FcmMessage.fromJson(json) as RemoveFcmMessage;
    }

    test('fields get parsed right in happy path', () {
      check(parse(baseJson))
        ..server.equals(baseJson['server']!)
        ..realmId.equals(4)
        ..realmUri.equals(Uri.parse(baseJson['realm_uri']!))
        ..userId.equals(234)
        ..zulipMessageIds.deepEquals([123, 234]);
    });

    test('toJson round-trips', () {
      check(parse(baseJson).toJson())
        .deepEquals({ ...baseJson }..remove('zulip_message_id'));
    });

    test('ignored fields missing have no effect', () {
      final baseline = parse(baseJson);
      check(parse({ ...baseJson }..remove('zulip_message_id'))).jsonEquals(baseline);
    });

    test('obsolete or novel fields have no effect', () {
      final baseline = parse(baseJson);
      check(parse({ ...baseJson, 'awesome_feature': 'enabled' })).jsonEquals(baseline);
    });

    group('parse failures on malformed data', () {
      int n = 1;

      test("${n++}", () => checkParseFails({ ...baseJson }..remove('server')));
      test("${n++}", () => checkParseFails({ ...baseJson }..remove('realm_id')));
      test("${n++}", () => checkParseFails({ ...baseJson, 'realm_id': 'abc' }));
      test("${n++}", () => checkParseFails({ ...baseJson, 'realm_id': '12,34' }));
      test("${n++}", () => checkParseFails({ ...baseJson }..remove('realm_uri')));
      test(skip: true, // Dart's Uri.parse is lax in what it accepts.
           "${n++}", () => checkParseFails({ ...baseJson, 'realm_uri': 'zulip.example.com' }));
      test(skip: true, // Dart's Uri.parse is lax in what it accepts.
           "${n++}", () => checkParseFails({ ...baseJson, 'realm_uri': '/examplecorp' }));

      for (final badIntList in ["abc,34", "12,abc", "12,", ""]) {
        test("${n++}", () => checkParseFails({ ...baseJson, 'zulip_message_ids': badIntList }));
      }
    });
  });
}

extension UnexpectedFcmMessageChecks on Subject<UnexpectedFcmMessage> {
  Subject<Map<String, dynamic>> get json => has((x) => x.json, 'json');
}

extension FcmMessageWithIdentityChecks on Subject<FcmMessageWithIdentity> {
  Subject<String> get server => has((x) => x.server, 'server');
  Subject<int> get realmId => has((x) => x.realmId, 'realmId');
  Subject<Uri> get realmUri => has((x) => x.realmUri, 'realmUri');
  Subject<int> get userId => has((x) => x.userId, 'userId');
}

extension MessageFcmMessageChecks on Subject<MessageFcmMessage> {
  Subject<int> get senderId => has((x) => x.senderId, 'senderId');
  Subject<String> get senderEmail => has((x) => x.senderEmail, 'senderEmail');
  Subject<Uri> get senderAvatarUrl => has((x) => x.senderAvatarUrl, 'senderAvatarUrl');
  Subject<String> get senderFullName => has((x) => x.senderFullName, 'senderFullName');
  Subject<FcmMessageRecipient> get recipient => has((x) => x.recipient, 'recipient');
  Subject<int> get zulipMessageId => has((x) => x.zulipMessageId, 'zulipMessageId');
  Subject<int> get time => has((x) => x.time, 'time');
  Subject<String> get content => has((x) => x.content, 'content');
}

extension FcmMessageStreamRecipientChecks on Subject<FcmMessageStreamRecipient> {
  Subject<int> get streamId => has((x) => x.streamId, 'streamId');
  Subject<String?> get streamName => has((x) => x.streamName, 'streamName');
  Subject<String> get topic => has((x) => x.topic, 'topic');
}

extension FcmMessageDmRecipientChecks on Subject<FcmMessageDmRecipient> {
  Subject<List<int>> get allRecipientIds => has((x) => x.allRecipientIds, 'allRecipientIds');
}

extension RemoveFcmMessageChecks on Subject<RemoveFcmMessage> {
  Subject<List<int>> get zulipMessageIds => has((x) => x.zulipMessageIds, 'zulipMessageIds');
}
