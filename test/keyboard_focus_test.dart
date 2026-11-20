import 'package:flutter_test/flutter_test.dart';
import 'package:tiptap_view/src/keyboard_accessory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <bool>[];
  var canControl = true;

  setUp(() {
    calls.clear();
    canControl = true;
    TiptapKeyboardFocus.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      TiptapKeyboardAccessory.channel,
      (call) async {
        expect(call.method, 'setFocusShowsKeyboard');
        calls.add(call.arguments as bool);
        return canControl;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      TiptapKeyboardAccessory.channel,
      null,
    );
  });

  test('the first editor turns it on, the last one turns it off', () async {
    expect(await TiptapKeyboardFocus.hold(), isTrue);
    expect(await TiptapKeyboardFocus.hold(), isTrue);
    expect(calls, [true], reason: 'the second editor does not ask again');

    await TiptapKeyboardFocus.release();
    expect(calls, [true], reason: 'one editor still wants it');

    await TiptapKeyboardFocus.release();
    expect(calls, [true, false]);
  });

  test('releasing without holding asks for nothing', () async {
    await TiptapKeyboardFocus.release();
    expect(calls, isEmpty);
  });

  test('says so when the platform cannot do it', () async {
    canControl = false;
    expect(await TiptapKeyboardFocus.hold(), isFalse);
  });
}
