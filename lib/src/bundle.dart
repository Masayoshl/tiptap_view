import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A built runtime: `runtime.js` (the runtime, TipTap and the bundle's extensions) and `runtime.css`.
///
/// The package ships [TiptapBundle.defaults], which knows the standard TipTap nodes. An app with its own
/// extensions builds its own bundle with the package's `js/build.mjs` and points to it with
/// [TiptapBundle.asset]. Extra stylesheets in [extraCss] are added after the bundle's CSS.
@immutable
class TiptapBundle {
  const TiptapBundle({required this.jsAsset, this.cssAsset, this.extraCss = const [], this.fonts = const []});

  /// A bundle built into the app's assets, as `<directory>/runtime.js` and `<directory>/runtime.css`.
  factory TiptapBundle.asset(String directory, {List<String> extraCss = const [], List<TiptapFontFace> fonts = const []}) {
    final base = directory.endsWith('/') ? directory : '$directory/';
    return TiptapBundle(jsAsset: '${base}runtime.js', cssAsset: '${base}runtime.css', extraCss: extraCss, fonts: fonts);
  }

  /// The package's own bundle: StarterKit, images, tables, YouTube, text styles, alignment, task lists.
  static const TiptapBundle defaults = TiptapBundle(
    jsAsset: 'packages/tiptap_view/assets/default/runtime.js',
    cssAsset: 'packages/tiptap_view/assets/default/runtime.css',
  );

  /// Returns a copy that adds the CSS assets in [assets] after this bundle's own CSS.
  TiptapBundle withCss(List<String> assets) =>
      TiptapBundle(jsAsset: jsAsset, cssAsset: cssAsset, extraCss: [...extraCss, ...assets], fonts: fonts);

  /// Returns a copy that also embeds [faces].
  TiptapBundle withFonts(List<TiptapFontFace> faces) =>
      TiptapBundle(jsAsset: jsAsset, cssAsset: cssAsset, extraCss: extraCss, fonts: [...fonts, ...faces]);

  final String jsAsset;
  final String? cssAsset;

  /// Asset paths of stylesheets added after [cssAsset], in order.
  final List<String> extraCss;

  /// Fonts from the app's assets, embedded into the page so the document can use the app's typeface.
  final List<TiptapFontFace> fonts;

  static final Expando<Map<String, Future<String>>> _cache = Expando();

  /// Loads the bundle's script and styles. Each asset is read once per asset bundle.
  Future<({String js, String css})> load([AssetBundle? bundle]) async {
    final assets = bundle ?? rootBundle;
    final cache = _cache[assets] ??= {};
    Future<String> read(String key) => cache.putIfAbsent(key, () => assets.loadString(key, cache: false));
    Future<String> font(TiptapFontFace face) =>
        cache.putIfAbsent('font:${face.asset}', () async => face.toCss(await assets.load(face.asset)));
    final js = await read(jsAsset);
    final styles = await Future.wait([
      ...fonts.map(font),
      if (cssAsset != null) read(cssAsset!),
      ...extraCss.map(read),
    ]);
    return (js: js, css: styles.join('\n'));
  }

  @override
  bool operator ==(Object other) =>
      other is TiptapBundle &&
      other.jsAsset == jsAsset &&
      other.cssAsset == cssAsset &&
      listEquals(other.extraCss, extraCss) &&
      listEquals(other.fonts, fonts);

  @override
  int get hashCode => Object.hash(jsAsset, cssAsset, Object.hashAll(extraCss), Object.hashAll(fonts));
}

/// A font file from the app's assets, embedded into the view's page as an `@font-face` rule.
///
/// The WebView cannot see fonts bundled in Flutter, so the page carries its own copy. Embed only the
/// weights the documents use: each one adds its file size, a third larger, to every page load.
@immutable
class TiptapFontFace {
  const TiptapFontFace({required this.family, required this.asset, this.weight = 400, this.italic = false});

  final String family;

  /// The font file's asset path, as in pubspec.yaml: `assets/fonts/Inter-Regular.ttf`.
  final String asset;
  final int weight;
  final bool italic;

  String toCss(ByteData bytes) {
    final data = base64Encode(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
    final extension = asset.split('.').last.toLowerCase();
    final (mime, format) = switch (extension) {
      'otf' => ('font/otf', 'opentype'),
      'woff' => ('font/woff', 'woff'),
      'woff2' => ('font/woff2', 'woff2'),
      _ => ('font/ttf', 'truetype'),
    };
    final name = family.replaceAll('"', r'\"');
    return '@font-face{font-family:"$name";src:url(data:$mime;base64,$data) format("$format");'
        'font-weight:$weight;font-style:${italic ? 'italic' : 'normal'};font-display:swap}';
  }

  @override
  bool operator ==(Object other) =>
      other is TiptapFontFace &&
      other.family == family &&
      other.asset == asset &&
      other.weight == weight &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(family, asset, weight, italic);
}
