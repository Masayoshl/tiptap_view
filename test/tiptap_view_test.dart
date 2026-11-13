import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tiptap_view/src/host_page.dart';
import 'package:tiptap_view/tiptap_view.dart';

/// Stands in for the WebView: records what the view sends and lets a test post messages as the runtime.
class FakeAdapter implements TiptapWebViewAdapter {
  FakeSession? session;

  @override
  TiptapWebViewSession createSession({required String channelName, required TiptapSessionCallbacks callbacks}) =>
      session = FakeSession(callbacks);
}

class FakeSession implements TiptapWebViewSession {
  FakeSession(this.callbacks);

  final TiptapSessionCallbacks callbacks;
  String? html;
  Uri? baseUrl;
  final List<Map<String, Object?>> calls = [];
  Object? Function(String method, Map<String, Object?> params)? respond;

  String get token => RegExp(r'"token":"([0-9a-f]+)"').firstMatch(html!)!.group(1)!;

  void post(Map<String, Object?> message, {String? token}) =>
      callbacks.onMessage(jsonEncode({...message, 'token': token ?? this.token}));

  void event(String name, [Map<String, Object?> payload = const {}]) =>
      post({'type': 'event', 'event': name, 'payload': payload});

  void ready({int protocol = TiptapProtocol.version, List<String> extensions = const ['starterKit']}) =>
      event('ready', {'protocol': protocol, 'bundle': 'test', 'runtimeVersion': '0.1.0', 'extensions': extensions});

  List<String> get methods => [for (final call in calls) call['method'] as String];

  @override
  Future<void> loadHtml(String html, {required Uri baseUrl}) async {
    this.html = html;
    this.baseUrl = baseUrl;
  }

  @override
  Future<void> runJavaScript(String source) async {
    final match = RegExp(r'receive\((.*)\);$').firstMatch(source)!;
    final call = jsonDecode(match.group(1)!) as Map<String, Object?>;
    calls.add(call);
    final params = Map<String, Object?>.from(call['params'] as Map);
    // Answer on a later microtask, as the page does.
    scheduleMicrotask(() {
      try {
        post({'type': 'response', 'id': call['id'], 'result': respond?.call(call['method'] as String, params)});
      } catch (error) {
        post({'type': 'response', 'id': call['id'], 'error': '$error'});
      }
    });
  }

  @override
  Widget build(BuildContext context, {required Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers}) =>
      const SizedBox.expand(key: Key('webview'));

  @override
  void dispose() {}
}

/// Serves the bundle's assets without the real 450 KB script.
class FakeAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(utf8.encode(switch (key) {
        'bundle/runtime.js' => 'console.log("</script>")',
        'bundle/runtime.css' => 'p{}',
        _ => throw FlutterError('No asset $key'),
      }));
}

void main() {
  group('TiptapProtocol', () {
    test('accepts messages with the session token only', () {
      const message = '{"type":"event","event":"height","payload":{"height":10},"token":"abc"}';
      expect(TiptapProtocol.parse(message, token: 'abc'), isA<TiptapEventMessage>());
      expect(TiptapProtocol.parse(message, token: 'other'), isNull);
      expect(TiptapProtocol.parse('not json', token: 'abc'), isNull);
      expect(TiptapProtocol.parse('{"type":"event","token":"abc"}', token: 'abc'), isNull);
    });

    test('builds a call the runtime can evaluate', () {
      expect(
        TiptapProtocol.call('1', 'setContent', {'content': "it's </script>"}),
        'window.tiptapView && window.tiptapView.receive({"id":"1","method":"setContent","params":{"content":"it\'s </script>"}});',
      );
    });
  });

  test('the host page cannot be closed early by the bundle', () {
    final page = TiptapHostPage.build(js: 'a="</script><b>"', css: 'x{} </style>', token: 'abc');
    expect('</script>'.allMatches(page).length, 2, reason: 'only the config and bundle scripts close');
    expect(page, contains(r'a="<\/script><b>"'));
    expect(page, contains(r'<\/style>'));
  });

  test('theme becomes --tv-* variables', () {
    final css = const TiptapTheme(textColor: Color(0x80FF0000), fontSize: 17.5, brightness: Brightness.dark).toCssVariables();
    expect(css['--tv-color-text'], 'rgba(255, 0, 0, 0.502)');
    expect(css['--tv-font-size'], '17.500px');
    expect(css['brightness'], 'dark');
  });

  test('a font face becomes an embedded @font-face rule', () {
    final bytes = ByteData.sublistView(Uint8List.fromList([1, 2, 3]));
    final css = const TiptapFontFace(family: 'General "Sans"', asset: 'assets/fonts/G.otf', weight: 600, italic: true).toCss(bytes);
    expect(css, '@font-face{font-family:"General \\"Sans\\"";src:url(data:font/otf;base64,AQID) format("opentype");'
        'font-weight:600;font-style:italic;font-display:swap}');
  });

  test('JSON content is equal by value', () {
    expect(TiptapContent.json({'type': 'doc', 'content': []}), TiptapContent.json({'type': 'doc', 'content': []}));
    expect(const TiptapContent.html('<p>a</p>'), isNot(const TiptapContent.html('<p>a</p>', sanitize: false)));
  });

  group('TiptapView', () {
    late FakeAdapter adapter;

    Future<FakeSession> pump(WidgetTester tester, Widget Function() view) async {
      await tester.pumpWidget(DefaultAssetBundle(
        bundle: FakeAssets(),
        child: MaterialApp(home: Scaffold(body: ListView(children: [view()]))),
      ));
      await tester.pump();
      return adapter.session!;
    }

    setUp(() => adapter = FakeAdapter());

    TiptapBundle bundle() => TiptapBundle.asset('bundle');

    testWidgets('loads the host page and sends theme and content once ready', (tester) async {
      final session = await pump(tester, () => TiptapView(adapter: adapter, bundle: bundle(), content: const TiptapContent.html('<p>Hi</p>')));
      expect(session.html, contains('<style>p{}</style>'));
      expect(session.baseUrl, TiptapView.defaultBaseUrl);
      expect(session.calls, isEmpty, reason: 'nothing is sent before the runtime is ready');

      session.ready();
      await tester.pump();
      expect(session.methods, ['setTheme', 'setContent']);
      expect(session.calls.last['params'], {'format': 'html', 'content': '<p>Hi</p>', 'sanitize': true});
    });

    testWidgets('grows to the reported height', (tester) async {
      final session = await pump(tester, () => TiptapView(adapter: adapter, bundle: bundle(), content: const TiptapContent.html('')));
      session.ready();
      session.event('height', {'height': 640});
      await tester.pump();
      expect(tester.getSize(find.byType(TiptapView)).height, 640);
    });

    testWidgets('ignores messages without the token', (tester) async {
      final session = await pump(tester, () => TiptapView(adapter: adapter, bundle: bundle(), content: const TiptapContent.html('')));
      session.ready();
      session.post({'type': 'event', 'event': 'height', 'payload': {'height': 900}}, token: 'forged');
      await tester.pump();
      expect(tester.getSize(find.byType(TiptapView)).height, 1);
    });

    testWidgets('reports link and image taps and blocks navigation away', (tester) async {
      final links = <TiptapLinkTap>[];
      final images = <TiptapImageTap>[];
      final session = await pump(tester, () => TiptapView(
            adapter: adapter,
            bundle: bundle(),
            baseUrl: Uri.parse('https://docs.example.com/space/'),
            content: const TiptapContent.html(''),
            onLinkTap: links.add,
            onImageTap: images.add,
          ));
      session.ready();
      session.event('linkTap', {'href': 'page', 'text': 'Page', 'attributes': {'data-page-id': 12}});
      session.event('imageTap', {
        'src': 'https://img/x.png',
        'alt': '',
        'attributes': {},
        'index': 2,
        'rect': {'left': 10, 'top': 20, 'width': 100, 'height': 50},
      });

      expect(links.single.uri, Uri.parse('https://docs.example.com/space/page'));
      expect(links.single.attributes['data-page-id'], '12');
      expect(links.single.isInternal(Uri.parse('https://docs.example.com/')), isTrue);
      expect(images.single.src, 'https://img/x.png');
      expect(images.single.index, 2);
      expect(images.single.rect, const Rect.fromLTWH(10, 20, 100, 50));
      final origin = tester.getTopLeft(find.byType(TiptapView));
      expect(images.single.globalRect, const Rect.fromLTWH(10, 20, 100, 50).shift(origin));

      final allowed = await session.callbacks.onNavigation(TiptapNavigation(url: Uri.parse('https://evil.example/'), isMainFrame: true));
      expect(allowed, isFalse);
      expect(links.last.href, 'https://evil.example/');
      expect(await session.callbacks.onNavigation(TiptapNavigation(url: Uri.parse('https://www.youtube.com/embed/x'), isMainFrame: false)), isTrue);
    });

    testWidgets('re-sends content only when it changes', (tester) async {
      var content = const TiptapContent.html('<p>a</p>');
      late StateSetter setOuter;
      final session = await pump(tester, () => StatefulBuilder(builder: (context, setState) {
            setOuter = setState;
            return TiptapView(adapter: adapter, bundle: bundle(), content: content);
          }));
      session.ready();
      await tester.pump();
      setOuter(() => content = const TiptapContent.html('<p>a</p>'));
      await tester.pump();
      expect(session.methods.where((m) => m == 'setContent').length, 1);
      setOuter(() => content = TiptapContent.json({'type': 'doc'}));
      await tester.pump();
      expect(session.methods.where((m) => m == 'setContent').length, 2);
    });

    testWidgets('says which extensions the bundle lacks, and refuses another protocol', (tester) async {
      final errors = <TiptapError>[];
      var session = await pump(tester, () => TiptapView(
            adapter: adapter,
            bundle: bundle(),
            content: const TiptapContent.html(''),
            extensions: const [TiptapExtension('starterKit'), TiptapExtension('collapsible')],
            onError: errors.add,
          ));
      session.ready();
      expect(errors.single.context, 'extensions');
      expect(errors.single.message, contains('collapsible'));

      await tester.pumpWidget(const SizedBox());
      errors.clear();
      session = await pump(tester, () => TiptapView(adapter: adapter, bundle: bundle(), content: const TiptapContent.html(''), onError: errors.add));
      session.ready(protocol: 99);
      await tester.pump();
      expect(errors.single.context, 'protocol');
      expect(session.calls, isEmpty);
    });

    testWidgets('routes extension events to their handlers', (tester) async {
      final received = <Map<String, Object?>>[];
      final session = await pump(tester, () => TiptapView(
            adapter: adapter,
            bundle: bundle(),
            content: const TiptapContent.html(''),
            extensions: [TiptapExtension('starterKit', events: {'mention': received.add})],
          ));
      session.ready();
      session.event('mention', {'id': 7});
      expect(received.single, {'id': 7});
    });

    testWidgets('controller calls wait for the runtime and return its answer', (tester) async {
      final controller = TiptapViewController();
      final session = await pump(tester, () => TiptapView(adapter: adapter, bundle: bundle(), controller: controller, content: const TiptapContent.html('')));
      session.respond = (method, params) => switch (method) {
            'htmlToJson' => {'type': 'doc', 'html': params['html']},
            'setImageHidden' => params['index'] == 0,
            'nope' => throw 'Unknown method: nope',
            _ => null,
          };

      final json = controller.htmlToJson('<p>x</p>');
      await tester.pump();
      expect(controller.isReady, isFalse);
      session.ready();
      await tester.pump();
      expect(await json, {'type': 'doc', 'html': '<p>x</p>'});
      expect(await controller.setImageHidden(0, hidden: true), isTrue);
      expect(session.calls.last['params'], {'index': 0, 'hidden': true});
      expect(await controller.setImageHidden(5, hidden: true), isFalse);
      await expectLater(controller.call('nope'), throwsA(isA<TiptapCallException>().having((e) => e.method, 'method', 'nope')));
    });

    testWidgets('survives being scrolled out of a lazy list', (tester) async {
      var sessions = 0;
      final counting = _CountingAdapter(adapter, () => sessions++);
      await tester.pumpWidget(DefaultAssetBundle(
        bundle: FakeAssets(),
        child: MaterialApp(
          home: Scaffold(
            body: ListView(children: [
              TiptapView(adapter: counting, bundle: bundle(), content: const TiptapContent.html('')),
              for (var i = 0; i < 40; i++) SizedBox(height: 200, child: Text('row $i')),
            ]),
          ),
        ),
      ));
      await tester.pump();
      await tester.drag(find.byType(ListView), const Offset(0, -6000));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, 6000));
      await tester.pumpAndSettle();
      expect(sessions, 1, reason: 'the page is not loaded again');
    });

    testWidgets('a failing setContent becomes an error, not an exception', (tester) async {
      final errors = <TiptapError>[];
      final session = await pump(tester, () => TiptapView(adapter: adapter, bundle: bundle(), content: TiptapContent.json({'type': 'doc'}), onError: errors.add));
      session.respond = (method, _) => method == 'setContent' ? throw 'Unknown node type: callout' : null;
      session.ready();
      await tester.pump();
      expect(errors.single.context, 'setContent');
      expect(errors.single.message, contains('callout'));
    });
  });
}

class _CountingAdapter implements TiptapWebViewAdapter {
  _CountingAdapter(this.inner, this.onCreate);

  final TiptapWebViewAdapter inner;
  final VoidCallback onCreate;

  @override
  TiptapWebViewSession createSession({required String channelName, required TiptapSessionCallbacks callbacks}) {
    onCreate();
    return inner.createSession(channelName: channelName, callbacks: callbacks);
  }
}
