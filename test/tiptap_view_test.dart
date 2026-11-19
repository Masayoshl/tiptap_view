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

  void ready({int protocol = TiptapProtocol.version, String? mode = 'view', List<String> extensions = const ['starterKit']}) =>
      event('ready', {
        'protocol': protocol,
        'bundle': 'test',
        'runtimeVersion': '0.1.0',
        'mode': mode,
        'modes': const ['view'],
        'extensions': extensions,
      });

  /// Answers to the runtime's requests, as `resolve` received them.
  final List<Map<String, Object?>> resolved = [];

  void request(String id, String name, [Map<String, Object?> payload = const {}]) =>
      post({'type': 'request', 'id': id, 'name': name, 'payload': payload});

  List<String> get methods => [for (final call in calls) call['method'] as String];

  @override
  Future<void> loadHtml(String html, {required Uri baseUrl}) async {
    this.html = html;
    this.baseUrl = baseUrl;
  }

  @override
  Future<void> runJavaScript(String source) async {
    final answer = RegExp(r'resolve\((.*)\);$').firstMatch(source);
    if (answer != null) {
      resolved.add(jsonDecode(answer.group(1)!) as Map<String, Object?>);
      return;
    }
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

    test('parses requests and builds answers to them', () {
      final request = TiptapProtocol.parse(
        '{"type":"request","id":"r1","name":"pick","payload":{"a":1},"token":"abc"}',
        token: 'abc',
      );
      expect(request, isA<TiptapRequestMessage>().having((m) => m.name, 'name', 'pick').having((m) => m.payload, 'payload', {'a': 1}));
      expect(TiptapProtocol.parse('{"type":"request","id":"r1","token":"abc"}', token: 'abc'), isNull);
      expect(TiptapProtocol.respond('r1', result: {'x': 1}), 'window.tiptapView && window.tiptapView.resolve({"id":"r1","result":{"x":1}});');
      expect(TiptapProtocol.respond('r1', error: 'no'), 'window.tiptapView && window.tiptapView.resolve({"id":"r1","error":"no"});');
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
    expect(page, contains('"mode":"view"'), reason: 'the view starts the runtime in its view mode');
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

    testWidgets('refuses a bundle that cannot start in the view mode', (tester) async {
      final errors = <TiptapError>[];
      final session = await pump(tester, () => TiptapView(adapter: adapter, bundle: bundle(), content: const TiptapContent.html(''), onError: errors.add));
      session.ready(mode: null);
      await tester.pump();
      expect(errors.single.context, 'mode');
      expect(session.calls, isEmpty);
    });

    testWidgets('answers extension requests, and rejects ones nobody handles', (tester) async {
      final session = await pump(tester, () => TiptapView(
            adapter: adapter,
            bundle: bundle(),
            content: const TiptapContent.html(''),
            extensions: [
              TiptapExtension('starterKit', requests: {
                'pick': (payload) async => {'picked': payload['from']},
                'fail': (_) => throw StateError('nope'),
              }),
            ],
          ));
      session.ready();
      session.request('r1', 'pick', {'from': 'a'});
      session.request('r2', 'fail');
      session.request('r3', 'unknown');
      await tester.pump();
      // Each request is answered when its handler is done, not in the order they came.
      expect(session.resolved, unorderedEquals([
        {'id': 'r1', 'result': {'picked': 'a'}},
        {'id': 'r2', 'error': 'Bad state: nope'},
        {'id': 'r3', 'error': 'No handler for request: unknown'},
      ]));
    });

    testWidgets('shows the loading builder until the content is in and measured', (tester) async {
      final session = await pump(tester, () => TiptapView(
            adapter: adapter,
            bundle: bundle(),
            content: const TiptapContent.html('<p>a</p>'),
            loadingBuilder: (_) => const SizedBox(key: Key('loading')),
          ));
      expect(find.byKey(const Key('loading')), findsOneWidget);
      session.ready();
      await tester.pump();
      await tester.pump();
      expect(session.methods, contains('setContent'));
      expect(find.byKey(const Key('loading')), findsOneWidget, reason: 'rendered, not measured yet');
      session.event('height', {'height': 300});
      await tester.pump();
      expect(find.byKey(const Key('loading')), findsNothing);
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

  group('TiptapEditor', () {
    late FakeAdapter adapter;

    Future<FakeSession> pump(WidgetTester tester, Widget Function() editor) async {
      await tester.pumpWidget(DefaultAssetBundle(
        bundle: FakeAssets(),
        child: MaterialApp(home: Scaffold(body: ListView(children: [editor()]))),
      ));
      await tester.pump();
      return adapter.session!;
    }

    setUp(() => adapter = FakeAdapter());

    TiptapBundle bundle() => TiptapBundle.asset('bundle');
    final document = {'type': 'doc', 'content': const []};

    testWidgets('starts the editor mode and opens the document once the runtime is ready', (tester) async {
      var opened = 0;
      final session = await pump(tester, () => TiptapEditor(
            adapter: adapter,
            bundle: bundle(),
            content: TiptapContent.json(document, schemaVersion: 1),
            onOpened: () => opened++,
          ));
      expect(session.html, contains('"mode":"editor"'));
      expect(session.calls, isEmpty, reason: 'nothing is sent before ready');
      session.respond = (method, _) => method == 'setContent' ? {'status': 'ok'} : null;
      session.ready(mode: 'editor');
      await tester.pump();
      final open = session.calls.firstWhere((call) => call['method'] == 'setContent');
      expect(open['params'], {'format': 'json', 'content': document, 'schemaVersion': 1, 'editable': true});
      expect(opened, 1);
    });

    testWidgets('refuses a bundle that cannot start the editor mode', (tester) async {
      final errors = <TiptapError>[];
      final session = await pump(tester, () => TiptapEditor(adapter: adapter, bundle: bundle(), content: const TiptapContent.html(''), onError: errors.add));
      session.ready(mode: null);
      await tester.pump();
      expect(errors.single.context, 'mode');
      expect(errors.single.message, contains('TiptapEditor needs a bundle with the "editor" runtime mode'));
      expect(session.calls, isEmpty);
    });

    testWidgets('reports a document the schema cannot hold, to its callback or else as an error', (tester) async {
      final refused = <TiptapIncompatibleContent>[];
      var session = await pump(tester, () => TiptapEditor(
            adapter: adapter,
            bundle: bundle(),
            content: TiptapContent.json(document, schemaVersion: 3),
            onIncompatibleContent: refused.add,
          ));
      session.respond = (method, _) => {
            'status': 'incompatible',
            'reason': 'newerSchema',
            'types': ['callout'],
            'attributes': ['image.caption'],
            'documentVersion': 3,
            'bundleVersion': 2,
          };
      session.ready(mode: 'editor');
      await tester.pump();
      final problem = refused.single;
      expect(problem.reason, TiptapIncompatibility.newerSchema);
      expect(problem.types, ['callout']);
      expect(problem.attributes, ['image.caption']);
      expect((problem.documentVersion, problem.bundleVersion), (3, 2));

      await tester.pumpWidget(const SizedBox());
      final errors = <TiptapError>[];
      session = await pump(tester, () => TiptapEditor(adapter: adapter, bundle: bundle(), content: TiptapContent.json(document), onError: errors.add));
      session.respond = (method, _) => {'status': 'incompatible', 'reason': 'unknownTypes', 'types': ['x']};
      session.ready(mode: 'editor');
      await tester.pump();
      expect(errors.single.context, 'content');
      expect(errors.single.message, contains('unknownTypes'));
    });

    testWidgets('runs commands by name and keeps the toolbar state', (tester) async {
      final controller = TiptapEditorController();
      addTearDown(controller.dispose);
      final states = <TiptapEditorState>[];
      final session = await pump(tester, () => TiptapEditor(
            adapter: adapter,
            bundle: bundle(),
            controller: controller,
            content: const TiptapContent.html('<p>a</p>'),
            onStateChange: states.add,
          ));
      session.respond = (method, params) => switch (method) {
            'setContent' => {'status': 'ok'},
            'command' => params['name'] != 'nothingToDo',
            'canRun' => params['name'] == 'undo',
            'commands' => ['toggleBold', 'undo'],
            _ => null,
          };
      session.ready(mode: 'editor');
      await tester.pump();

      expect(await controller.command('toggleHeading', {'level': 2}), isTrue);
      expect(session.calls.last['params'], {'name': 'toggleHeading', 'args': [{'level': 2}], 'focus': true});
      expect(await controller.command('nothingToDo'), isFalse);
      expect(session.calls.last['params'], {'name': 'nothingToDo', 'args': [], 'focus': true});
      await controller.commandWith('insertContentAt', [1, 'x'], focus: false);
      expect(session.calls.last['params'], {'name': 'insertContentAt', 'args': [1, 'x'], 'focus': false});
      expect(await controller.canRun('undo'), isTrue);
      expect(await controller.canRun('redo'), isFalse);
      expect(await controller.commands(), ['toggleBold', 'undo']);

      expect(controller.state.value, isNull, reason: 'no state before the first event');
      session.event('state', {
        'version': 3,
        'editable': true,
        'focused': true,
        'marks': {'bold': {}, 'link': {'href': '/x'}},
        'nodes': [
          {'type': 'bulletList', 'attrs': {}},
          {'type': 'heading', 'attrs': {'level': 2, 'textAlign': 'center'}},
        ],
        'canUndo': true,
        'canRedo': false,
        'selection': {'empty': false, 'from': 2, 'to': 4, 'node': null},
      });
      final state = controller.state.value!;
      expect(states.single, state);
      expect(state.block?.type, 'heading');
      expect(state.isActive('bold'), isTrue);
      expect(state.isActive('link', {'href': '/x'}), isTrue);
      expect(state.isActive('heading', {'level': 2}), isTrue);
      expect(state.isActive('heading', {'level': 3}), isFalse);
      expect(state.isActive('paragraph', {'textAlign': 'center'}), isFalse);
      expect(state.isActive('bulletList'), isTrue);
      expect((state.canUndo, state.canRedo, state.selectionEmpty, state.selectionFrom), (true, false, false, 2));

      await tester.pumpWidget(const SizedBox());
      expect(controller.state.value, isNull, reason: 'the state goes with the editor');
    });

    testWidgets('uploads an image through the app, with a placeholder, Retry and Remove', (tester) async {
      final controller = TiptapEditorController();
      addTearDown(controller.dispose);
      final session = await pump(tester, () => TiptapEditor(adapter: adapter, bundle: bundle(), controller: controller, content: const TiptapContent.html('')));
      session.respond = (method, params) => switch (method) {
            'setContent' => {'status': 'ok'},
            'finishUpload' => true,
            _ => null,
          };
      session.ready(mode: 'editor');
      await tester.pump();

      var attempts = 0;
      final failOnce = Completer<void>();
      Future<TiptapUploadedImage> upload() async {
        attempts++;
        if (attempts == 1) {
          failOnce.complete();
          throw StateError('offline');
        }
        return const TiptapUploadedImage('https://cdn.example/a.png', attributes: {'mediaId': 'm1'}, node: 'blockImage');
      }

      final done = controller.uploadImage(upload, preview: Uint8List.fromList([1, 2, 3]), previewType: 'image/png');
      await tester.pump();
      await failOnce.future;
      await tester.pump();
      final begin = session.calls.firstWhere((call) => call['method'] == 'beginUpload');
      final id = (begin['params'] as Map)['id'];
      expect((begin['params'] as Map)['preview'], 'data:image/png;base64,AQID');
      expect(session.calls.last['method'], 'failUpload');
      expect((session.calls.last['params'] as Map)['message'], contains('offline'));

      session.event('uploadRetry', {'id': id});
      await tester.pump();
      expect(await done, isTrue);
      expect(attempts, 2);
      expect(session.calls.last['params'], {
        'id': id,
        'src': 'https://cdn.example/a.png',
        'attributes': {'mediaId': 'm1'},
        'node': 'blockImage',
      });

      final removed = controller.uploadImage(() => Completer<TiptapUploadedImage>().future);
      await tester.pump();
      final second = (session.calls.lastWhere((call) => call['method'] == 'beginUpload')['params'] as Map)['id'];
      session.event('uploadCancel', {'id': second});
      expect(await removed, isFalse);

      final orphan = controller.uploadImage(() => Completer<TiptapUploadedImage>().future);
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      expect(await orphan, isFalse, reason: 'an upload ends with its page');
    });

    testWidgets('pasted images go to onImageUpload; links and embeds go through the controller', (tester) async {
      final controller = TiptapEditorController();
      addTearDown(controller.dispose);
      final files = <TiptapImageFile>[];
      final taps = <TiptapLinkTap>[];
      final session = await pump(tester, () => TiptapEditor(
            adapter: adapter,
            bundle: bundle(),
            controller: controller,
            content: const TiptapContent.html(''),
            onImageUpload: (file) async {
              files.add(file);
              return const TiptapUploadedImage('https://cdn.example/p.png');
            },
            onLinkTap: taps.add,
          ));
      session.respond = (method, params) => switch (method) {
            'setContent' => {'status': 'ok'},
            'getLink' => {'active': true, 'href': '/docs', 'attributes': {'title': 'Docs'}, 'text': 'the docs', 'empty': true},
            'setLink' || 'removeLink' => true,
            'insertEmbed' => params['url'] == 'https://youtu.be/x' ? {'inserted': true, 'type': 'youtube'} : {'inserted': false, 'type': null},
            _ => null,
          };
      session.ready(mode: 'editor');
      await tester.pump();
      expect(session.calls.firstWhere((call) => call['method'] == 'setImagePaste')['params'], {'enabled': true});

      session.request('r1', 'imageUpload', {'data': 'AQID', 'type': 'image/png', 'name': 'shot.png'});
      await tester.pump();
      expect(files.single.bytes, [1, 2, 3]);
      expect(files.single.mimeType, 'image/png');
      expect(session.resolved.single, {
        'id': 'r1',
        'result': {'src': 'https://cdn.example/p.png', 'attributes': {}, 'node': 'image'},
      });

      final link = await controller.getLink();
      expect((link.active, link.href, link.text, link.attributes['title']), (true, '/docs', 'the docs', 'Docs'));
      await controller.setLink('/manual', attributes: {'title': 'Manual'});
      expect(session.calls.last['params'], {'href': '/manual', 'attributes': {'title': 'Manual'}});
      await controller.setLink('/x', text: 'X');
      expect((session.calls.last['params'] as Map)['text'], 'X');
      expect(await controller.removeLink(), isTrue);
      expect(await controller.insertEmbed('https://youtu.be/x'), 'youtube');
      expect(await controller.insertEmbed('https://example.com'), isNull);

      session.event('linkTap', {'href': '/docs', 'text': 'the docs', 'attributes': {'href': '/docs'}});
      expect(taps.single.href, '/docs');
      expect(taps.single.uri, Uri.parse('https://tiptap-view.local/docs'));
    });

    testWidgets('scrolls the page around it to keep the caret in sight', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(DefaultAssetBundle(
        bundle: FakeAssets(),
        child: MaterialApp(
          home: Scaffold(
            body: ListView(controller: scroll, children: [
              const SizedBox(height: 200),
              TiptapEditor(adapter: adapter, bundle: bundle(), content: const TiptapContent.html('')),
            ]),
          ),
        ),
      ));
      await tester.pump();
      final session = adapter.session!;
      session.respond = (method, _) => method == 'setContent' ? {'status': 'ok'} : null;
      session.ready(mode: 'editor');
      session.event('height', {'height': 3000});
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);

      // The caret 2000px down the document: 2200px down the page, far below the 600px screen.
      session.event('caret', {'focused': true, 'top': 2000, 'left': 40, 'bottom': 2020});
      await tester.pumpAndSettle();
      final caretOnScreen = 200 + 2000 - scroll.offset;
      expect(caretOnScreen, inInclusiveRange(0, 600 - 20), reason: 'the caret is on screen');

      // Without focus nothing moves.
      final offset = scroll.offset;
      session.event('caret', {'focused': false});
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(scroll.offset, offset);
    });

    testWidgets('follows the keyboard coming up over the caret', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(DefaultAssetBundle(
        bundle: FakeAssets(),
        child: MaterialApp(
          home: Scaffold(
            body: ListView(controller: scroll, children: [
              TiptapEditor(adapter: adapter, bundle: bundle(), content: const TiptapContent.html('')),
            ]),
          ),
        ),
      ));
      await tester.pump();
      final session = adapter.session!;
      session.respond = (method, _) => method == 'setContent' ? {'status': 'ok'} : null;
      session.ready(mode: 'editor');
      session.event('height', {'height': 1000});
      // On screen before the keyboard: 500px down a 600px screen.
      session.event('caret', {'focused': true, 'top': 500, 'left': 40, 'bottom': 520});
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);

      // A 300px keyboard (insets are physical pixels; the test view's ratio is 3): the Scaffold's body
      // shrinks to 300px and the caret has to move up into it.
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      final caretOnScreen = 500 - scroll.offset;
      expect(caretOnScreen, inInclusiveRange(0, 300 - 20), reason: 'the caret is above the keyboard');
    });

    testWidgets('on Android, a scroll of the page drops the selection handles once, while focused', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await tester.pumpWidget(DefaultAssetBundle(
        bundle: FakeAssets(),
        child: MaterialApp(
          home: Scaffold(
            body: ListView(controller: scroll, children: [
              TiptapEditor(adapter: adapter, bundle: bundle(), content: const TiptapContent.html('')),
            ]),
          ),
        ),
      ));
      await tester.pump();
      final session = adapter.session!;
      session.respond = (method, _) => method == 'setContent' ? {'status': 'ok'} : true;
      session.ready(mode: 'editor');
      session.event('height', {'height': 3000});
      await tester.pumpAndSettle();
      int drops() => session.methods.where((method) => method == 'hideSelectionHandles').length;

      scroll.jumpTo(100);
      expect(drops(), 0, reason: 'nothing to drop without focus');

      session.event('caret', {'focused': true, 'top': 300, 'left': 10, 'bottom': 320});
      await tester.pumpAndSettle();
      scroll.jumpTo(150);
      scroll.jumpTo(200);
      scroll.jumpTo(250);
      expect(drops(), 1, reason: 'once for a run of scroll updates');
      await tester.pump(const Duration(milliseconds: 400));
      scroll.jumpTo(300);
      expect(drops(), 2, reason: 'again after a pause');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('reports changes, reads the document and follows editable', (tester) async {
      final changes = <int>[];
      final controller = TiptapEditorController();
      var editable = true;
      late StateSetter setOuter;
      final session = await pump(tester, () => StatefulBuilder(builder: (context, setState) {
            setOuter = setState;
            return TiptapEditor(
              adapter: adapter,
              bundle: bundle(),
              controller: controller,
              content: const TiptapContent.html('<p>a</p>'),
              editable: editable,
              onChange: (change) => changes.add(change.version),
            );
          }));
      session.respond = (method, _) => switch (method) {
            'setContent' => {'status': 'ok'},
            'getContent' => {
                'json': document,
                'html': '<p>a</p>',
                'version': 4,
                'errors': [{'code': 'uploading'}],
              },
            _ => null,
          };
      session.ready(mode: 'editor');
      await tester.pump();

      session.event('change', {'version': 4});
      expect(changes, [4]);

      final content = await controller.getContent();
      expect(content.html, '<p>a</p>');
      expect(content.version, 4);
      expect(content.canSave, isFalse);
      expect(content.errors.single, {'code': 'uploading'});

      setOuter(() => editable = false);
      await tester.pump();
      expect(session.calls.last, containsPair('method', 'setEditable'));
      expect(session.calls.last['params'], {'editable': false});
      expect(session.methods.where((method) => method == 'setContent').length, 1, reason: 'editable alone does not reopen');
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
