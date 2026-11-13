import 'package:flutter/material.dart';

/// How a document looks. Each value becomes a `--tv-*` CSS variable in the view; a bundle's own CSS can
/// use them too. Fonts are CSS font-family lists: app fonts bundled in Flutter are not visible to the
/// WebView, so the defaults are the system fonts.
@immutable
class TiptapTheme {
  const TiptapTheme({
    this.brightness = Brightness.light,
    this.textColor = const Color(0xFF1F2328),
    this.mutedColor = const Color(0xFF6B7280),
    this.linkColor = const Color(0xFF2563EB),
    this.borderColor = const Color(0xFFE5E7EB),
    this.codeBackgroundColor = const Color(0xFFF3F4F6),
    this.quoteColor = const Color(0xFFD1D5DB),
    this.fontSize = 16,
    this.lineHeight = 1.6,
    this.fontFamily,
    this.padding = 0,
    this.radius = 8,
  });

  /// A theme that follows the app's Material theme.
  factory TiptapTheme.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyLarge;
    return TiptapTheme(
      brightness: theme.brightness,
      textColor: body?.color ?? scheme.onSurface,
      mutedColor: scheme.onSurfaceVariant,
      linkColor: scheme.primary,
      borderColor: scheme.outlineVariant,
      codeBackgroundColor: scheme.surfaceContainerHighest,
      quoteColor: scheme.outline,
      fontSize: body?.fontSize ?? 16,
      lineHeight: body?.height ?? 1.6,
    );
  }

  final Brightness brightness;
  final Color textColor;
  final Color mutedColor;
  final Color linkColor;
  final Color borderColor;
  final Color codeBackgroundColor;
  final Color quoteColor;

  /// Logical pixels; a CSS pixel in the view is one logical pixel.
  final double fontSize;
  final double lineHeight;

  /// A CSS font-family list, such as `'"Inter", sans-serif'`. Null keeps the system font.
  final String? fontFamily;

  /// Space around the document inside the view, in logical pixels.
  final double padding;
  final double radius;

  TiptapTheme copyWith({
    Brightness? brightness,
    Color? textColor,
    Color? mutedColor,
    Color? linkColor,
    Color? borderColor,
    Color? codeBackgroundColor,
    Color? quoteColor,
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    double? padding,
    double? radius,
  }) {
    return TiptapTheme(
      brightness: brightness ?? this.brightness,
      textColor: textColor ?? this.textColor,
      mutedColor: mutedColor ?? this.mutedColor,
      linkColor: linkColor ?? this.linkColor,
      borderColor: borderColor ?? this.borderColor,
      codeBackgroundColor: codeBackgroundColor ?? this.codeBackgroundColor,
      quoteColor: quoteColor ?? this.quoteColor,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      padding: padding ?? this.padding,
      radius: radius ?? this.radius,
    );
  }

  /// The variables the runtime's `setTheme` method takes. Null values reset a variable to the CSS default.
  Map<String, Object?> toCssVariables() => {
        'brightness': brightness == Brightness.dark ? 'dark' : 'light',
        '--tv-color-text': _css(textColor),
        '--tv-color-muted': _css(mutedColor),
        '--tv-color-link': _css(linkColor),
        '--tv-color-border': _css(borderColor),
        '--tv-color-code-background': _css(codeBackgroundColor),
        '--tv-color-quote': _css(quoteColor),
        '--tv-font-size': '${_number(fontSize)}px',
        '--tv-line-height': _number(lineHeight),
        '--tv-font-family': fontFamily,
        '--tv-padding': '${_number(padding)}px',
        '--tv-radius': '${_number(radius)}px',
      };

  static String _css(Color color) {
    int channel(double value) => (value * 255).round().clamp(0, 255);
    return 'rgba(${channel(color.r)}, ${channel(color.g)}, ${channel(color.b)}, ${_number(color.a)})';
  }

  static String _number(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : value.toStringAsFixed(3);

  @override
  bool operator ==(Object other) =>
      other is TiptapTheme &&
      other.brightness == brightness &&
      other.textColor == textColor &&
      other.mutedColor == mutedColor &&
      other.linkColor == linkColor &&
      other.borderColor == borderColor &&
      other.codeBackgroundColor == codeBackgroundColor &&
      other.quoteColor == quoteColor &&
      other.fontSize == fontSize &&
      other.lineHeight == lineHeight &&
      other.fontFamily == fontFamily &&
      other.padding == padding &&
      other.radius == radius;

  @override
  int get hashCode => Object.hash(brightness, textColor, mutedColor, linkColor, borderColor,
      codeBackgroundColor, quoteColor, fontSize, lineHeight, fontFamily, padding, radius);
}
