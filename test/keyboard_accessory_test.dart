import 'package:flutter_test/flutter_test.dart';
import 'package:tiptap_view/src/keyboard_accessory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <bool>[];
  var canControl = true;

  setUp(() {
    calls.clear();
    canControl = true;
    TiptapKeyboardAccessory.reset();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TiptapKeyboardAccessory.channel, (
          call,
        ) async {
          expect(call.method, 'setAccessoryHidden');
          calls.add(call.arguments as bool);
          return canControl;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TiptapKeyboardAccessory.channel, null);
  });

  test('the first editor hides the bar, the last one brings it back', () async {
    expect(await TiptapKeyboardAccessory.hide(), isTrue);
    expect(await TiptapKeyboardAccessory.hide(), isTrue);
    expect(calls, [true], reason: 'the second editor does not ask again');

    await TiptapKeyboardAccessory.release();
    expect(calls, [true], reason: 'one editor still wants it hidden');

    await TiptapKeyboardAccessory.release();
    expect(calls, [true, false]);
  });

  test('releasing without hiding asks for nothing', () async {
    await TiptapKeyboardAccessory.release();
    expect(calls, isEmpty);
  });

  test('says so when the platform cannot control the bar', () async {
    canControl = false;
    expect(await TiptapKeyboardAccessory.hide(), isFalse);
  });

  test('a platform without the plugin is not an error', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(TiptapKeyboardAccessory.channel, null);
    expect(await TiptapKeyboardAccessory.hide(), isFalse);
    await TiptapKeyboardAccessory.release();
  });
}
