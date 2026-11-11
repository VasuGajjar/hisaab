import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Hisaab tokens that have no slot in [ColorScheme]: card surface, the amber
/// "needs details" and teal "money in" families, and the receipt paper.
class HisaabColors extends ThemeExtension<HisaabColors> {
  const HisaabColors({
    required this.card,
    required this.sheet,
    required this.muted,
    required this.amber,
    required this.onAmber,
    required this.amberC,
    required this.onAmberC,
    required this.teal,
    required this.tealC,
    required this.onTealC,
    required this.paper,
    required this.paperEdge,
    required this.onPaper,
    required this.paperMuted,
    required this.hl,
  });

  final Color card, sheet, muted;
  final Color amber, onAmber, amberC, onAmberC;
  final Color teal, tealC, onTealC;
  final Color paper, paperEdge, onPaper, paperMuted, hl;

  // v2 palette, "iris on cool glass": cool neutrals, iris ink, saffron and
  // teal accents; the receipt paper stays warm on purpose.
  static const light = HisaabColors(
    card: Color(0xFFFFFFFF),
    sheet: Color(0xFFFFFFFF),
    muted: Color(0xFF5A6075),
    amber: Color(0xFFA04800),
    onAmber: Color(0xFFFFFFFF),
    amberC: Color(0xFFFFE3C7),
    onAmberC: Color(0xFF4A2300),
    teal: Color(0xFF006B62),
    tealC: Color(0xFFCFF4EC),
    onTealC: Color(0xFF00382F),
    paper: Color(0xFFF4EEE2),
    paperEdge: Color(0xFFA69A84),
    onPaper: Color(0xFF352F25),
    paperMuted: Color(0xFF5E5646),
    hl: Color(0xFFFFE59A),
  );

  static const dark = HisaabColors(
    card: Color(0xFF151826),
    sheet: Color(0xFF1A1D2C),
    muted: Color(0xFFA2A7B8),
    amber: Color(0xFFFFB86B),
    onAmber: Color(0xFF4A2300),
    amberC: Color(0xFF6B3600),
    onAmberC: Color(0xFFFFDDBD),
    teal: Color(0xFF5FDCCB),
    tealC: Color(0xFF00524A),
    onTealC: Color(0xFFB8F3E8),
    paper: Color(0xFF26221B),
    paperEdge: Color(0xFF6F6655),
    onPaper: Color(0xFFE6DECF),
    paperMuted: Color(0xFFB8AE9C),
    hl: Color(0xFF5A4810),
  );

  // ponytail: nothing overrides or animates these tokens, so copyWith/lerp stay trivial.
  @override
  HisaabColors copyWith() => this;

  @override
  HisaabColors lerp(HisaabColors? other, double t) => t < .5 || other == null ? this : other;
}

/// Glass materials: translucent fills over one ambient field. [on] false is
/// Settings › Glass effects off: solid fills, no blur, same layout.
class HisaabGlass extends ThemeExtension<HisaabGlass> {
  const HisaabGlass({
    required this.on,
    required this.thin,
    required this.regular,
    required this.strong,
    required this.sheet,
    required this.edge,
    required this.line,
    required this.shadow,
    required this.base,
    required this.pools,
    this.rim,
    this.inner,
    this.sheen,
  });

  final bool on;

  /// The shiny edge: a 1 px stroke lit top-left, faint in the middle, with a
  /// glint bottom-right. Null (solid) = a flat [edge].
  final List<Color>? rim;

  /// A 1 px highlight just inside the top edge, following the corners.
  final Color? inner;

  /// A soft gloss over the top of the fill.
  final List<Color>? sheen;

  /// thin: tracks behind thumbs · regular: cards, rows, chips, fields ·
  /// strong: sheets, raised thumbs. Text only sits on regular or thicker.
  final Color thin, regular, strong, sheet, edge, line;
  final List<BoxShadow> shadow;

  /// The ambient field: [base] with iris, aqua and saffron [pools].
  final Color base;
  final List<Color> pools;

  // Painted outside the surface only (see GlassShadow), as CSS box-shadow is.
  static const _shadowLight = [
    BoxShadow(color: Color(0x0F1C2250), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x1A1C2250), offset: Offset(0, 10), blurRadius: 30),
  ];
  static const _shadowDark = [
    BoxShadow(color: Color(0x66000000), offset: Offset(0, 10), blurRadius: 30),
  ];

  static const light = HisaabGlass(
    on: true,
    // Fills are the design's values × .88 (12% more see-through).
    thin: Color(0x48FFFFFF), // 28%
    regular: Color(0x6BFFFFFF), // 42%
    strong: Color(0xA2FAFAFD), // 64%
    sheet: Color(0x8BFAFAFD), // 55%
    edge: Color(0xC7FFFFFF),
    line: Color(0x141C2250),
    shadow: _shadowLight,
    base: Color(0xFFEEF1F8),
    pools: [Color(0x666C70FF), Color(0x4D48C8E0), Color(0x42FFA868)],
    rim: [Color(0xF2FFFFFF), Color(0x59FFFFFF), Color(0xBFFFFFFF)],
    inner: Color(0xD9FFFFFF),
    sheen: [Color(0x38FFFFFF), Color(0x00FFFFFF)],
  );

  static const dark = HisaabGlass(
    on: true,
    thin: Color(0x4824283C), // 28%
    regular: Color(0x6B1E2234), // 42%
    strong: Color(0xAB161928), // 67%
    sheet: Color(0x98161928), // 60%
    edge: Color(0x21FFFFFF),
    line: Color(0x12FFFFFF),
    shadow: _shadowDark,
    base: Color(0xFF0A0C14),
    pools: [Color(0x734C50E6), Color(0x6110768C), Color(0x52964C14)],
    rim: [Color(0x4DFFFFFF), Color(0x0FFFFFFF), Color(0x29FFFFFF)],
    inner: Color(0x29FFFFFF),
    sheen: [Color(0x0FFFFFFF), Color(0x00FFFFFF)],
  );

  /// Glass effects off: every material becomes its solid token.
  static const solidLight = HisaabGlass(
    on: false,
    thin: Color(0xFFEDF0F6),
    regular: Color(0xFFFFFFFF),
    strong: Color(0xFFFFFFFF),
    sheet: Color(0xFFFFFFFF),
    edge: Color(0xFFD5DAE6),
    line: Color(0x141C2250),
    shadow: _shadowLight,
    base: Color(0xFFF3F5FA),
    pools: [],
  );

  static const solidDark = HisaabGlass(
    on: false,
    thin: Color(0xFF191C2A),
    regular: Color(0xFF151826),
    strong: Color(0xFF151826),
    sheet: Color(0xFF1A1D2C),
    edge: Color(0xFF343949),
    line: Color(0x12FFFFFF),
    shadow: _shadowDark,
    base: Color(0xFF0A0C14),
    pools: [],
  );

  /// Backdrop blur: the design's σ 11 / 18 (CSS blur(22px) / 36px) less 25%;
  /// [strong] for sheets and menus. The design's saturate(170%) is left out:
  /// on a phone it cost ~6 ms a frame under a sheet, and the fills over it
  /// are mostly opaque enough to hide it.
  ui.ImageFilter blur({bool strong = false}) =>
      ui.ImageFilter.blur(sigmaX: strong ? 13.5 : 8.25, sigmaY: strong ? 13.5 : 8.25);

  @override
  HisaabGlass copyWith() => this;

  @override
  HisaabGlass lerp(HisaabGlass? other, double t) => t < .5 || other == null ? this : other;
}

extension HisaabContext on BuildContext {
  ColorScheme get cs => Theme.of(this).colorScheme;
  HisaabColors get hc => Theme.of(this).extension<HisaabColors>()!;
  HisaabGlass get glass => Theme.of(this).extension<HisaabGlass>()!;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

const _tab = [FontFeature.tabularFigures()];

/// Type scale (Inter; IBM Plex Mono marks facts read from an SMS).
abstract final class T {
  static const display = TextStyle(fontSize: 40, height: 48 / 40, fontWeight: FontWeight.w600, letterSpacing: -.6);
  static const hl = TextStyle(fontSize: 24, height: 32 / 24, fontWeight: FontWeight.w600, letterSpacing: -.2);
  static const tl = TextStyle(fontSize: 20, height: 28 / 20, fontWeight: FontWeight.w600);
  static const t = TextStyle(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w600);
  static const bl = TextStyle(fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400);
  static const b = TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400);
  static const l = TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500);
  static const ls = TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, letterSpacing: .2);
  static const lsReg = TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400, letterSpacing: .2);
  static const eyebrow = TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, letterSpacing: .8);
  static const mono = TextStyle(fontFamily: 'IBMPlexMono', fontSize: 13, height: 20 / 13, fontFeatures: _tab);
  static const monoS = TextStyle(fontFamily: 'IBMPlexMono', fontSize: 12, height: 16 / 12, fontFeatures: _tab);
  static const num = TextStyle(fontFeatures: _tab);
}

// One instance per (brightness, glass): rebuilding the app with the same
// pair hands MaterialApp the identical theme, so nothing animates.
final _themes = <(Brightness, bool), ThemeData>{};

ThemeData hisaabTheme(Brightness b, {bool glass = true}) => _themes[(b, glass)] ??= _theme(b, glass);

ThemeData _theme(Brightness b, bool glassOn) {
  final dark = b == Brightness.dark;
  final h = dark ? HisaabColors.dark : HisaabColors.light;
  final g = switch ((dark, glassOn)) {
    (false, true) => HisaabGlass.light,
    (true, true) => HisaabGlass.dark,
    (false, false) => HisaabGlass.solidLight,
    (true, false) => HisaabGlass.solidDark,
  };
  final c = dark
      ? const _Base(
          bg: Color(0xFF0A0C14), scLow: Color(0xFF10131E), sc: Color(0xFF191C2A), scHigh: Color(0xFF222636),
          scHighest: Color(0xFF2C3042), on: Color(0xFFE8EAF2), onVar: Color(0xFFC4C8D6), outline: Color(0xFF8A90A3),
          outlineVar: Color(0xFF343949), primary: Color(0xFFB9BBFF), onPrimary: Color(0xFF1C1C7A),
          primaryC: Color(0xFF3236A8), onPrimaryC: Color(0xFFE3E3FF), error: Color(0xFFFFB3AE),
          onError: Color(0xFF680008), errorC: Color(0xFF8F1B21), onErrorC: Color(0xFFFFDAD7),
          snack: Color(0xDBF2F2F8), onSnack: Color(0xFF1B1C1F), snackAction: Color(0xFF4447D6),
          scrim: Color(0x61000000))
      : const _Base(
          bg: Color(0xFFF3F5FA), scLow: Color(0xFFF7F8FC), sc: Color(0xFFEDF0F6), scHigh: Color(0xFFE5E9F1),
          scHighest: Color(0xFFDCE1EB), on: Color(0xFF121522), onVar: Color(0xFF3E4356), outline: Color(0xFF747A8C),
          outlineVar: Color(0xFFD5DAE6), primary: Color(0xFF4447D6), onPrimary: Color(0xFFFFFFFF),
          primaryC: Color(0xFFE3E3FF), onPrimaryC: Color(0xFF1A1A73), error: Color(0xFFC0262D),
          onError: Color(0xFFFFFFFF), errorC: Color(0xFFFFDEDC), onErrorC: Color(0xFF410006),
          snack: Color(0xCC1C1E2A), onSnack: Color(0xFFF2F0EB), snackAction: Color(0xFFB9BBFF),
          scrim: Color(0x38141628));

  final scheme = ColorScheme(
    brightness: b,
    primary: c.primary,
    onPrimary: c.onPrimary,
    primaryContainer: c.primaryC,
    onPrimaryContainer: c.onPrimaryC,
    // M3 tonal button, nav indicator, segmented and filter chips read the
    // secondary container; the design paints them all primary-container.
    secondary: c.primary,
    onSecondary: c.onPrimary,
    secondaryContainer: c.primaryC,
    onSecondaryContainer: c.onPrimaryC,
    tertiary: h.amber,
    onTertiary: h.onAmber,
    tertiaryContainer: h.amberC,
    onTertiaryContainer: h.onAmberC,
    error: c.error,
    onError: c.onError,
    errorContainer: c.errorC,
    onErrorContainer: c.onErrorC,
    surface: c.bg,
    onSurface: c.on,
    onSurfaceVariant: c.onVar,
    surfaceContainerLowest: h.card,
    surfaceContainerLow: c.scLow,
    surfaceContainer: c.sc,
    surfaceContainerHigh: c.scHigh,
    surfaceContainerHighest: c.scHighest,
    outline: c.outline,
    outlineVariant: c.outlineVar,
    inverseSurface: c.snack,
    onInverseSurface: c.onSnack,
    inversePrimary: c.snackAction,
    scrim: c.scrim,
    surfaceTint: Colors.transparent,
  );

  const pill = StadiumBorder();
  // Button/nav styles replace the ambient text style, so they must name the family.
  const btnText =
      TextStyle(fontFamily: 'Inter', fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w600, letterSpacing: .1);
  const btnSize = Size(48, 48);

  return ThemeData(
    useMaterial3: true,
    brightness: b,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: g.base,
    canvasColor: c.bg,
    extensions: [h, g],
    // Android's default (predictive back → fade-forwards) runs 450 ms and
    // repaints both glass pages under a full-screen fade every frame. Zoom is
    // 300 ms and animates a one-off snapshot of each page instead.
    // ponytail: costs the back-gesture peek; the gesture itself still pops.
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {TargetPlatform.android: ZoomPageTransitionsBuilder()},
    ),
    iconTheme: IconThemeData(color: c.onVar, size: 24),
    dividerTheme: DividerThemeData(color: g.line, thickness: 1, space: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: btnSize,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: pill,
        textStyle: btnText,
        iconSize: 18,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: btnSize,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: pill,
        textStyle: btnText,
        foregroundColor: c.primary,
        backgroundColor: g.thin,
        side: BorderSide(color: glassOn ? g.edge : c.outline),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: btnSize,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: pill,
        textStyle: btnText,
        foregroundColor: c.primary,
        iconSize: 18,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.primary,
      foregroundColor: c.onPrimary,
      shape: pill,
      extendedTextStyle: btnText,
      extendedIconLabelSpacing: 10,
      extendedPadding: const EdgeInsets.only(left: 16, right: 20),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.snack,
      contentTextStyle: TextStyle(fontFamily: 'Inter', fontSize: 14, height: 20 / 14, color: c.onSnack),
      actionTextColor: c.snackAction,
      elevation: 0,
      shape: const StadiumBorder(side: BorderSide(color: Color(0x1FFFFFFF))),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Colors.transparent,
      modalBackgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      modalBarrierColor: c.scrim,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.primary,
      linearTrackColor: g.regular,
      linearMinHeight: 3,
      borderRadius: BorderRadius.circular(2),
    ),
    // Drawn at 40 × 24 by HSwitch: off = outlined glass track, small thumb.
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : g.regular),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.primary : c.outline),
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.onPrimary : c.outline),
    ),
    timePickerTheme: TimePickerThemeData(backgroundColor: h.sheet),
    dialogTheme: DialogThemeData(backgroundColor: h.sheet),
    // The panel is see-through; GlassMenu paints the glass inside it.
    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        shadowColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(18)))),
      ),
    ),
  );
}

/// App-wide scrolling: the iOS elastic bounce on every platform, and content
/// that fades out at an edge while more of it lies beyond that edge.
class HisaabScroll extends MaterialScrollBehavior {
  const HisaabScroll();

  // ponytail: not AlwaysScrollable, so content that fits doesn't bounce; it
  // would also steal the drag from a sheet's swipe-to-dismiss.
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());

  // Replaces Android's stretch. Text fields opt out of this hook themselves.
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) =>
      EdgeFade(direction: details.direction, child: child);
}

/// Fades [child] (a viewport) over [EdgeFade.extent] at each edge with
/// content past it, deepening over the first [EdgeFade.extent] of scroll.
class EdgeFade extends StatefulWidget {
  const EdgeFade({super.key, required this.direction, required this.child});
  final AxisDirection direction;
  final Widget child;

  static const extent = 32.0;

  @override
  State<EdgeFade> createState() => _EdgeFadeState();
}

class _EdgeFadeState extends State<EdgeFade> {
  double _before = 0, _after = 0;

  // Only this scrollable's own notifications (depth 0), not nested ones.
  bool _on(ViewportNotificationMixin n, ScrollMetrics m) {
    if (n.depth != 0) return false;
    final b = (m.extentBefore / EdgeFade.extent).clamp(0.0, 1.0);
    final a = (m.extentAfter / EdgeFade.extent).clamp(0.0, 1.0);
    if (b != _before || a != _after) {
      setState(() {
        _before = b;
        _after = a;
      });
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollMetricsNotification>(
    // Sent after the first layout and whenever the content resizes.
    onNotification: (n) => _on(n, n.metrics),
    child: NotificationListener<ScrollUpdateNotification>(
      onNotification: (n) => _on(n, n.metrics),
      child: _Fade(widget.direction, _before, _after, child: widget.child),
    ),
  );
}

class _Fade extends SingleChildRenderObjectWidget {
  const _Fade(this.direction, this.before, this.after, {super.child});
  final AxisDirection direction;
  final double before, after;

  @override
  _RenderFade createRenderObject(BuildContext context) => _RenderFade(direction, before, after);

  @override
  void updateRenderObject(BuildContext context, _RenderFade r) => r
    ..direction = direction
    ..before = before
    ..after = after
    ..markNeedsPaint();
}

/// A shader mask that skips its offscreen layer when nothing fades, so
/// content that fits costs nothing.
class _RenderFade extends RenderProxyBox {
  _RenderFade(this.direction, this.before, this.after);
  AxisDirection direction;
  double before, after;

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    if (before == 0 && after == 0) {
      layer = null;
      context.paintChild(child!, offset);
      return;
    }
    final (begin, end) = switch (direction) {
      AxisDirection.down => (Alignment.topCenter, Alignment.bottomCenter),
      AxisDirection.up => (Alignment.bottomCenter, Alignment.topCenter),
      AxisDirection.right => (Alignment.centerLeft, Alignment.centerRight),
      AxisDirection.left => (Alignment.centerRight, Alignment.centerLeft),
    };
    final len = axisDirectionToAxis(direction) == Axis.vertical ? size.height : size.width;
    final s = len <= 0 ? .5 : math.min(EdgeFade.extent / len, .5);
    const ink = Color(0xFF000000);
    final shader = LinearGradient(
      begin: begin,
      end: end,
      colors: [ink.withValues(alpha: 1 - before), ink, ink, ink.withValues(alpha: 1 - after)],
      stops: [0, s, 1 - s, 1],
    ).createShader(Offset.zero & size);
    layer = (layer as ShaderMaskLayer? ?? ShaderMaskLayer())
      ..shader = shader
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    context.pushLayer(layer!, super.paint, offset);
  }
}

class _Base {
  const _Base({
    required this.bg,
    required this.scLow,
    required this.sc,
    required this.scHigh,
    required this.scHighest,
    required this.on,
    required this.onVar,
    required this.outline,
    required this.outlineVar,
    required this.primary,
    required this.onPrimary,
    required this.primaryC,
    required this.onPrimaryC,
    required this.error,
    required this.onError,
    required this.errorC,
    required this.onErrorC,
    required this.snack,
    required this.onSnack,
    required this.snackAction,
    required this.scrim,
  });

  final Color bg, scLow, sc, scHigh, scHighest, on, onVar, outline, outlineVar;
  final Color primary, onPrimary, primaryC, onPrimaryC, error, onError, errorC, onErrorC;
  final Color snack, onSnack, snackAction, scrim;
}
