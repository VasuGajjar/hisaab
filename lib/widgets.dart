import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data.dart';
import 'format.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Painters

/// Dashed outline for any rounded rect or circle (Flutter has no dashed border).
class Dashed extends StatelessWidget {
  const Dashed({
    super.key,
    required this.child,
    required this.color,
    this.radius = 12,
    this.width = 1.5,
    this.circle = false,
  });

  final Widget child;
  final Color color;
  final double radius, width;
  final bool circle;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(foregroundPainter: _DashPainter(color, radius, width, circle), child: child);
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, this.radius, this.width, this.circle);

  final Color color;
  final double radius, width;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(width / 2);
    final path = circle
        ? (Path()..addOval(r))
        : (Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(radius, r.shortestSide / 2)))));
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final dash = width * 3, gap = width * 2;
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += dash + gap) {
        canvas.drawPath(m.extractPath(d, d + dash), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) =>
      o.color != color || o.radius != radius || o.width != width || o.circle != circle;
}

class _HDashPainter extends CustomPainter {
  _HDashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = size.height;
    final y = size.height / 2;
    for (double x = 0; x < size.width; x += 7.5) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4.5, size.width), y), p);
    }
  }

  @override
  bool shouldRepaint(_HDashPainter o) => o.color != color;
}

/// Diagonal amber stripes: spend still waiting for a category.
class Stripes extends StatelessWidget {
  const Stripes({super.key, this.radius = 0});
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: CustomPaint(painter: _StripePainter(context.hc.amber, context.hc.amberC), size: Size.infinite),
  );
}

class _StripePainter extends CustomPainter {
  _StripePainter(this.a, this.b);
  final Color a, b;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = b);
    final p = Paint()
      ..color = a
      ..strokeWidth = 3 / math.sqrt2 * 1.4;
    for (double x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(_StripePainter o) => o.a != a || o.b != b;
}

// ---------------------------------------------------------------------------
// Glass

/// The ambient field every screen sits on: iris, aqua and saffron pools.
/// Glass effects off: the flat background.
class Ambient extends StatelessWidget {
  const Ambient({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return CustomPaint(painter: _AmbientPainter(g.base, g.pools), child: child);
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.base, this.pools);
  final Color base;
  final List<Color> pools;

  // Each pool: centre (x, y) and radii (rx, ry), as fractions of the screen.
  static const _spots = [(.06, .02, .60, .42), (1.0, .24, .55, .38), (.28, 1.0, .70, .46)];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = base);
    for (final (i, c) in pools.indexed) {
      final (x, y, rx, ry) = _spots[i];
      final a = rx * size.width, b = ry * size.height;
      canvas
        ..save()
        ..translate(x * size.width, y * size.height)
        ..scale(1, b / a);
      canvas.drawCircle(
        Offset.zero,
        a,
        Paint()..shader = ui.Gradient.radial(Offset.zero, a, [c, c.withValues(alpha: 0)], [0, .7]),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AmbientPainter o) => o.base != base || o.pools != pools;
}

/// Soft shadows painted only outside [shape], so a translucent surface
/// doesn't show its own shadow through it.
class GlassShadow extends StatelessWidget {
  const GlassShadow({super.key, required this.shape, required this.shadows, required this.child});
  final ShapeBorder shape;
  final List<BoxShadow> shadows;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _ShadowPainter(shape, shadows), child: child);
}

class _ShadowPainter extends CustomPainter {
  _ShadowPainter(this.shape, this.shadows);
  final ShapeBorder shape;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size, outline = shape.getOuterPath(r);
    canvas
      ..save()
      ..clipPath(Path.combine(PathOperation.difference, Path()..addRect(r.inflate(80)), outline));
    for (final s in shadows) {
      canvas.drawPath(shape.getOuterPath(r.shift(s.offset).inflate(s.spreadRadius)), s.toPaint());
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShadowPainter o) => o.shape != shape || o.shadows != shadows;
}

enum Mat { thin, regular, strong }

/// [s]'s outline on [r], pulled in by [inset] (corner radii shrink with it).
Path _outline(ShapeBorder s, Rect r, double inset) => s is RoundedRectangleBorder
    ? (Path()..addRRect(s.borderRadius.resolve(TextDirection.ltr).toRRect(r).deflate(inset)))
    : s.getOuterPath(r.deflate(inset));

/// Fill, then a soft gloss over its top.
class _FillPainter extends CustomPainter {
  _FillPainter(this.shape, this.fill, this.sheen);
  final ShapeBorder shape;
  final Color fill;
  final List<Color>? sheen;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size, path = _outline(shape, r, 0);
    canvas.drawPath(path, Paint()..color = fill);
    if (sheen != null) {
      final reach = math.min(1.0, 28 / size.height); // gloss over the top 28 px, or half a short chip
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment(0, -1 + 2 * math.min(reach, .5)),
            colors: sheen!,
          ).createShader(r),
      );
    }
  }

  @override
  bool shouldRepaint(_FillPainter o) => o.shape != shape || o.fill != fill || o.sheen != sheen;
}

/// The edge: a lit gradient rim (or a flat [edge]), and a highlight just
/// inside the top that follows the corners.
class _RimPainter extends CustomPainter {
  _RimPainter(this.shape, {this.rim, this.edge, this.width = 1, this.inner});
  final ShapeBorder shape;
  final List<Color>? rim;
  final Color? edge, inner;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    if (edge != null) {
      canvas.drawPath(_outline(shape, r, width / 2), stroke..color = edge!);
    } else if (rim != null) {
      stroke.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: rim!,
        stops: const [0, .45, 1],
      ).createShader(r);
      canvas.drawPath(_outline(shape, r, width / 2), stroke);
    }
    if (inner != null) {
      final reach = math.min(1.0, 16 / size.height);
      canvas.drawPath(
        _outline(shape, r, width + .5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment(0, -1 + 2 * reach),
            colors: [inner!, inner!.withValues(alpha: 0)],
          ).createShader(r),
      );
    }
  }

  @override
  bool shouldRepaint(_RimPainter o) =>
      o.shape != shape || o.rim != rim || o.edge != edge || o.width != width || o.inner != inner;
}

/// One glass surface: a translucent fill with a gloss, a shiny rim and inner
/// highlight, a soft shadow outside; backdrop blur and saturation if [blur].
/// Glass effects off: solid fill, flat edge, no blur.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.mat = Mat.regular,
    this.radius = 20,
    this.shape,
    this.color,
    this.edge,
    this.edgeWidth = 1,
    this.padding,
    this.shadow = true,
    this.blur = false,
    this.strongBlur = false,
    this.rim = true,
    this.expand = true,
  });

  final Widget child;
  final Mat mat;
  final double radius;

  /// Defaults to a rounded rect of [radius].
  final ShapeBorder? shape;

  /// [edge]: a flat coloured border (a selected chip, a focused field) in place of the rim.
  final Color? color, edge;
  final double edgeWidth;
  final EdgeInsetsGeometry? padding;

  /// [blur]: backdrop blur, only for glass that floats over moving content
  /// (a sheet, the FAB, a menu, a snackbar). Glass in the flow sits on the
  /// still ambient field, where a blur shows almost nothing yet costs the GPU
  /// a backdrop pass every frame.
  final bool shadow, blur, strongBlur, rim, expand;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    final shape = this.shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));
    final fill =
        color ??
        switch (mat) {
          Mat.thin => g.thin,
          Mat.regular => g.regular,
          Mat.strong => g.strong,
        };
    Widget box = CustomPaint(
      painter: _FillPainter(shape, fill, g.sheen),
      foregroundPainter: _RimPainter(
        shape,
        rim: rim ? g.rim : null,
        edge: edge ?? (rim && g.rim == null ? g.edge : null),
        width: edgeWidth,
        inner: g.inner,
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
    if (expand) box = SizedBox(width: double.infinity, child: box);
    if (blur && g.on) {
      final f = g.blur(strong: strongBlur);
      box = ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: BackdropFilter(filter: f, child: box),
      );
    }
    return shadow ? GlassShadow(shape: shape, shadows: g.shadow, child: box) : box;
  }
}

/// A dropdown menu's panel on strong glass. Put the menu's items in it.
class GlassMenu extends StatelessWidget {
  const GlassMenu({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Glass(
    mat: Mat.strong,
    radius: 18,
    shadow: false,
    blur: true,
    strongBlur: true,
    expand: false,
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: children),
  );
}

/// A page whose list scrolls under a glass app bar; the bar frosts once
/// something is beneath it.
class GlassPage extends StatefulWidget {
  const GlassPage({super.key, required this.bar, this.barHeight = 64, required this.body, this.fab});

  final Widget bar;
  final double barHeight;

  /// The scrolling body; its first item must clear [top].
  final Widget Function(BuildContext context, double top) body;
  final Widget? fab;

  @override
  State<GlassPage> createState() => _GlassPageState();
}

class _GlassPageState extends State<GlassPage> {
  bool _under = false;

  @override
  Widget build(BuildContext context) => Scaffold(
    extendBodyBehindAppBar: true,
    appBar: _GlassBar(height: widget.barHeight, frosted: _under, child: widget.bar),
    body: Ambient(
      child: NotificationListener<ScrollUpdateNotification>(
        onNotification: (n) {
          final under = n.metrics.pixels > 0;
          if (n.depth == 0 && n.metrics.axis == Axis.vertical && under != _under) setState(() => _under = under);
          return false;
        },
        child: Builder(builder: (c) => widget.body(c, MediaQuery.paddingOf(c).top)),
      ),
    ),
    floatingActionButton: widget.fab,
  );
}

class _GlassBar extends StatelessWidget implements PreferredSizeWidget {
  const _GlassBar({required this.height, required this.frosted, required this.child});
  final double height;
  final bool frosted;
  final Widget child;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    return ClipRect(
      child: BackdropFilter(
        enabled: frosted && g.on,
        filter: g.blur(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(color: frosted ? g.regular : g.regular.withValues(alpha: 0)),
          // A foreground hairline takes no layout space.
          foregroundDecoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: frosted ? g.edge : g.edge.withValues(alpha: 0))),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(height: height, child: child),
          ),
        ),
      ),
    );
  }
}

/// 44 dp glass circle in a 48 dp touch target: app-bar and sheet actions.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.tooltip, this.onPressed});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Glass(
        shape: const CircleBorder(),
        expand: false,
        // No blur of its own: beneath it is the bar, frosted once the list scrolls under.
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            foregroundColor: context.cs.onSurface,
            fixedSize: const Size.square(44),
            minimumSize: const Size.square(44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}

/// Tinted glass pill: the one primary action floating over a list.
class GlassFab extends StatelessWidget {
  const GlassFab({super.key, required this.icon, required this.label, required this.onPressed});
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, g = context.glass;
    final fab = Glass(
      shape: const StadiumBorder(),
      color: g.on ? cs.primary.withValues(alpha: .88) : cs.primary,
      expand: false,
      shadow: false,
      blur: true, // it floats over the list
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                Icon(icon, color: cs.onPrimary),
                Text(
                  label,
                  style: T.l.copyWith(fontWeight: FontWeight.w600, color: cs.onPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return Semantics(
      button: true,
      child: GlassShadow(
        shape: const StadiumBorder(),
        shadows: [BoxShadow(color: cs.primary.withValues(alpha: .34), offset: const Offset(0, 10), blurRadius: 28)],
        child: fab,
      ),
    );
  }
}

/// Switch painted at 40 × 24; the whole 48 dp square toggles it.
class HSwitch extends StatelessWidget {
  const HSwitch({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    child: SizedBox.square(
      dimension: 48,
      child: Center(
        child: SizedBox(
          width: 40,
          height: 24,
          child: FittedBox(
            child: Switch(value: value, onChanged: onChanged, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
          ),
        ),
      ),
    ),
  );
}

/// How long a tab switch takes: Seg's thumb slide, and the content it swaps.
const tabSwitch = Duration(milliseconds: 280);

/// Segmented control: thin glass track, raised glass thumb that slides to
/// the picked option.
class Seg<V> extends StatelessWidget {
  const Seg({super.key, required this.value, required this.options, required this.onChanged, this.label});

  final V value;
  final List<(V, String, IconData?)> options;
  final ValueChanged<V> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    final n = options.length, i = options.indexWhere((o) => o.$1 == value);
    return Semantics(
      label: label,
      container: true,
      child: Glass(
        mat: Mat.thin,
        radius: 22,
        shadow: false,
        padding: const EdgeInsets.all(3),
        child: SizedBox(
          height: 36,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The raised thumb: strong glass, no blur of its own (the track's is beneath).
              // It fills the track's height, so its inset is the same 3 dp on every side.
              if (i >= 0)
                AnimatedAlign(
                  duration: tabSwitch,
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(n == 1 ? 0 : -1 + 2 * i / (n - 1), 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / n,
                    child: const GlassShadow(
                      shape: StadiumBorder(),
                      shadows: [BoxShadow(color: Color(0x29141C3C), offset: Offset(0, 1), blurRadius: 3)],
                      child: Glass(shape: StadiumBorder(), mat: Mat.strong, shadow: false, child: SizedBox.expand()),
                    ),
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (v, text, icon) in options)
                    Expanded(
                      child: Semantics(
                        selected: v == value,
                        button: true,
                        child: Material(
                          type: MaterialType.transparency,
                          shape: const StadiumBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => onChanged(v),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                spacing: 6,
                                children: [
                                  if (icon != null) Icon(icon, size: 18, color: cs.onSurface),
                                  Flexible(
                                    child: AnimatedDefaultTextStyle(
                                      duration: tabSwitch,
                                      // What Text(style:) merged onto inside the Material before.
                                      style: Theme.of(context).textTheme.bodyMedium!.merge(
                                        T.l.copyWith(
                                          color: cs.onSurface,
                                          fontWeight: v == value ? FontWeight.w600 : FontWeight.w500,
                                        ),
                                      ),
                                      child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Swaps [child] when [index] changes: the new one slides in from the side
/// of the tab picked (higher index: from the right) as the old one fades out
/// the other way, and the height follows.
class TabSwitch extends StatefulWidget {
  const TabSwitch({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<TabSwitch> createState() => _TabSwitchState();
}

class _TabSwitchState extends State<TabSwitch> {
  double _dir = 1;

  @override
  void didUpdateWidget(TabSwitch old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) _dir = widget.index > old.index ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: tabSwitch,
    curve: Curves.easeOutCubic,
    alignment: Alignment.topCenter,
    child: AnimatedSwitcher(
      duration: tabSwitch,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) =>
          Stack(alignment: Alignment.topCenter, children: [...previous, ?current]),
      // A new closure each build, so AnimatedSwitcher re-wraps every child on
      // a switch: the one leaving gets the new direction too, and exits away.
      transitionBuilder: (c, a) {
        final dx = c.key == ValueKey(widget.index) ? .08 * _dir : -.08 * _dir;
        return FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: Offset(dx, 0), end: Offset.zero).animate(a), child: c),
        );
      },
      child: KeyedSubtree(key: ValueKey(widget.index), child: widget.child),
    ),
  );
}

// ---------------------------------------------------------------------------
// Money

enum AmtSize { xl, lg, ml, md, sm }

/// ₹ / rupees / paise spans with tabular figures.
class AmountText extends StatelessWidget {
  const AmountText(
    this.paise, {
    super.key,
    this.size = AmtSize.md,
    this.color,
    this.prefix = '₹',
    this.struck = false,
    this.showDec = true,
  });

  final int paise;
  final AmtSize size;
  final Color? color;
  final String prefix;
  final bool struck, showDec;

  @override
  Widget build(BuildContext context) {
    final (i, d) = money(paise);
    final (fs, cur, dec, h, ls) = switch (size) {
      AmtSize.xl => (40.0, 28.0, 24.0, 48.0, -.6),
      AmtSize.lg => (28.0, 20.0, 18.0, 36.0, -.3),
      AmtSize.ml => (22.0, 16.0, 14.0, 28.0, -.2),
      AmtSize.md => (16.0, 16.0, 13.0, 24.0, 0.0),
      AmtSize.sm => (14.0, 14.0, 12.0, 20.0, 0.0),
    };
    return Text.rich(
      TextSpan(
        style: T.num.copyWith(
          fontSize: fs,
          height: h / fs,
          letterSpacing: ls,
          fontWeight: FontWeight.w600,
          color: color ?? context.cs.onSurface,
        ),
        children: [
          TextSpan(
            text: prefix,
            style: TextStyle(fontSize: cur, fontWeight: FontWeight.w500),
          ),
          TextSpan(
            text: i,
            style: struck ? const TextStyle(decoration: TextDecoration.lineThrough, decorationThickness: 1.5) : null,
          ),
          if (showDec)
            TextSpan(
              text: d,
              style: TextStyle(fontSize: dec, fontWeight: FontWeight.w500, color: color ?? context.hc.muted),
            ),
        ],
      ),
      softWrap: false,
    );
  }
}

/// Out / in arrow in a 20 dp circle.
class DirIcon extends StatelessWidget {
  const DirIcon({super.key, required this.inflow});
  final bool inflow;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, hc = context.hc;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(color: inflow ? hc.tealC : cs.surfaceContainerHigh, shape: BoxShape.circle),
      child: Icon(
        inflow ? Icons.south_west_rounded : Icons.north_east_rounded,
        size: 14,
        color: inflow ? hc.onTealC : cs.onSurfaceVariant,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Badges: icon + word, never colour alone

enum Tone { needs, done, ignored, credit, error, dup, sms, you }

class HBadge extends StatelessWidget {
  const HBadge(this.label, {super.key, this.icon, this.tone = Tone.done, this.height = 24});

  final String label;
  final IconData? icon;
  final Tone tone;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, hc = context.hc;
    final (Color? bg, Color fg) = switch (tone) {
      Tone.needs => (hc.amberC, hc.onAmberC),
      Tone.done => (cs.surfaceContainerHigh, cs.onSurfaceVariant),
      Tone.ignored => (null, hc.muted),
      Tone.credit => (hc.tealC, hc.onTealC),
      Tone.error => (cs.errorContainer, cs.onErrorContainer),
      Tone.dup => (null, cs.onSurfaceVariant),
      Tone.sms => (hc.paper, hc.onPaper),
      Tone.you => (cs.primaryContainer, cs.onPrimaryContainer),
    };
    final r = height / 2;
    final Widget pill = Container(
      height: height,
      padding: EdgeInsets.only(left: icon == null ? 8 : 6, right: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(r),
        border: tone == Tone.ignored ? Border.all(color: cs.outlineVariant) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          if (icon != null) Icon(icon, size: 14, color: fg),
          Text(
            label,
            style: tone == Tone.sms
                ? T.monoS.copyWith(fontWeight: FontWeight.w500, color: fg)
                : TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: fg),
          ),
        ],
      ),
    );
    return switch (tone) {
      Tone.dup => Dashed(color: cs.outline, radius: r, width: 1, child: pill),
      Tone.sms => Dashed(color: hc.paperEdge, radius: r, width: 1, child: pill),
      _ => pill,
    };
  }
}

// ---------------------------------------------------------------------------
// Transaction row

class TxnAvatar extends StatelessWidget {
  const TxnAvatar(this.t, {super.key, this.size = 36});
  final Txn t;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, hc = context.hc;
    Widget circle(Color? bg, Widget child, {Color? border}) => Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: border == null ? null : Border.all(color: border, width: 1.5),
      ),
      child: child,
    );
    return switch (t.status) {
      TxnStatus.needs => Dashed(
        color: hc.amber,
        circle: true,
        child: circle(null, Text(t.name.isEmpty ? '?' : t.name[0], style: T.t.copyWith(color: hc.amber))),
      ),
      TxnStatus.credit => circle(hc.tealC, Icon(Icons.south_west_rounded, color: hc.onTealC)),
      TxnStatus.dup => circle(null, Icon(Icons.content_copy_rounded, color: hc.muted), border: cs.outlineVariant),
      TxnStatus.ignored => circle(null, Icon(Icons.swap_horiz_rounded, color: hc.muted), border: cs.outlineVariant),
      TxnStatus.unread => circle(hc.paper, Icon(Icons.sms_outlined, color: hc.onPaper), border: hc.paperEdge),
      TxnStatus.filed => circle(t.cat!.of(context).cc, Icon(t.cat!.icon, color: t.cat!.of(context).con)),
    };
  }
}

/// One payment. [capsule]: a floating glass row in a list; false inside a card.
class TxnTile extends StatelessWidget {
  const TxnTile(this.t, {super.key, this.dated = false, this.capsule = true, this.onTap});

  final Txn t;

  /// [dated]: the meta line shows the day, not just the time.
  final bool dated, capsule;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, hc = context.hc;
    final ignored = t.status == TxnStatus.ignored;
    final trailing = switch (t.status) {
      TxnStatus.needs => const HBadge('Add details', icon: Icons.edit_outlined, tone: Tone.needs),
      TxnStatus.credit => const HBadge('Credit', icon: Icons.south_west_rounded, tone: Tone.credit),
      TxnStatus.dup => const HBadge('Duplicate?', icon: Icons.content_copy_rounded, tone: Tone.dup),
      TxnStatus.ignored => const HBadge('Not an expense', icon: Icons.do_not_disturb_on_outlined, tone: Tone.ignored),
      TxnStatus.unread => const HBadge("Couldn't read", icon: Icons.warning_amber_rounded, tone: Tone.error),
      TxnStatus.filed => Text(
        t.catLabel,
        style: TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w600, color: cs.primary),
      ),
    };
    final row = InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: capsule ? 12 : 16, vertical: 6),
          child: Row(
            spacing: 12,
            children: [
              TxnAvatar(t),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      t.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        height: 22 / 16,
                        fontWeight: FontWeight.w500,
                        color: ignored ? hc.muted : null,
                      ),
                    ),
                    Text(
                      t.metaLine(dated: dated),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.manual
                          ? TextStyle(fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, color: cs.primary)
                          : T.monoS.copyWith(color: hc.muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                spacing: 4,
                children: [
                  AmountText(
                    t.paise,
                    prefix: t.isCredit ? '+₹' : '₹',
                    color: ignored ? hc.muted : (t.isCredit ? hc.teal : null),
                    struck: ignored,
                  ),
                  trailing,
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (!capsule) return row;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Glass(radius: 18, shadow: false, child: row),
    );
  }
}

// ---------------------------------------------------------------------------
// Chips

enum ChipKind { plain, sugg, sel, add, tag, tagSel }

/// 36 dp glass pill: a category, a tag, or "+ add".
class HChip extends StatelessWidget {
  const HChip(this.label, {super.key, this.cat, this.icon, this.why, this.kind = ChipKind.plain, this.onTap});

  final String label;
  final Cat? cat;
  final IconData? icon;
  final String? why;
  final ChipKind kind;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, hc = context.hc, g = context.glass;
    final cc = cat?.of(context);
    final sel = kind == ChipKind.sel;
    final bg = switch (kind) {
      ChipKind.sel => cc!.cc,
      ChipKind.tagSel => cs.primaryContainer,
      ChipKind.sugg => g.strong,
      ChipKind.add => g.thin,
      _ => g.regular,
    };
    final fg = switch (kind) {
      ChipKind.sel => cc!.con,
      ChipKind.tagSel => cs.onPrimaryContainer,
      ChipKind.add => cs.primary,
      ChipKind.tag => cs.onSurfaceVariant,
      _ => cs.onSurface,
    };
    // A coloured border says "suggested" or "picked"; otherwise the glass rim.
    final edge = switch (kind) {
      ChipKind.sugg || ChipKind.tagSel => cs.primary,
      ChipKind.sel => cc!.con,
      _ => null,
    };
    final dot = cc != null && (kind == ChipKind.plain || kind == ChipKind.sugg || sel);
    Widget chip = Glass(
      shape: const StadiumBorder(),
      color: bg,
      edge: edge,
      edgeWidth: edge == null ? 1 : 1.5,
      rim: kind != ChipKind.add, // its edge is the dashes
      shadow: false,
      expand: false,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: EdgeInsets.only(left: dot ? 6 : (kind == ChipKind.add ? 8 : 12), right: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 6,
              children: [
                if (dot)
                  Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(color: sel ? cc.con : cc.cc, shape: BoxShape.circle),
                    child: Icon(sel ? Icons.check_rounded : (icon ?? cat!.icon), size: 14, color: sel ? cc.cc : cc.con),
                  ),
                if (kind == ChipKind.add && icon != null) Icon(icon, size: 18, color: fg),
                Text(
                  label,
                  style: TextStyle(fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w500, color: fg),
                ),
                if (why != null && why!.isNotEmpty)
                  Text(
                    why!,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: sel ? cc!.con : hc.muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    if (kind == ChipKind.add) chip = Dashed(color: cs.primary.withValues(alpha: .55), radius: 18, child: chip);
    return Semantics(selected: sel || kind == ChipKind.tagSel, button: true, child: chip);
  }
}

/// 32 dp glass filter pill with a trailing chevron (or ✕ to clear).
class FChip extends StatelessWidget {
  const FChip(
    this.label, {
    super.key,
    this.on = false,
    this.leading,
    this.trailing = Icons.expand_more_rounded,
    this.semanticLabel,
    this.onTap,
  });

  final String label;
  final bool on;
  final IconData? leading;
  final IconData trailing;
  final String? semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, g = context.glass;
    final fg = on ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: semanticLabel != null,
      button: true,
      child: Glass(
        shape: const StadiumBorder(),
        color: on ? cs.primaryContainer.withValues(alpha: g.on ? .84 : 1) : null,
        edge: on ? cs.primary.withValues(alpha: .3) : null,
        shadow: false,
        expand: false,
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Container(
            height: 32,
            padding: EdgeInsets.only(left: leading == null ? 12 : 10, right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                if (leading != null) Icon(leading, size: 16, color: fg),
                Text(
                  label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: fg),
                ),
                Icon(trailing, size: 16, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category grid: every category + New, 4 per row. Any number can be selected.

class CategoryGrid extends StatelessWidget {
  const CategoryGrid({super.key, this.selected = const {}, this.suggested, required this.onPick, this.onNew});

  final Set<Cat> selected;
  final Cat? suggested;
  final ValueChanged<Cat> onPick;
  final VoidCallback? onNew;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[for (final c in cats) _tile(context, c), _tile(context, null)];
    return Column(
      spacing: 4,
      children: [
        for (var i = 0; i < tiles.length; i += 4)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: [for (final t in tiles.sublist(i, math.min(i + 4, tiles.length))) Expanded(child: t)],
          ),
      ],
    );
  }

  Widget _tile(BuildContext context, Cat? c) {
    final cs = context.cs, hc = context.hc;
    final cc = c?.of(context);
    final sel = c != null && selected.contains(c);
    final ring = c == null
        ? Dashed(
            color: cs.outline,
            circle: true,
            child: SizedBox.square(dimension: 40, child: Icon(Icons.add_rounded, color: cs.primary)),
          )
        : Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: sel ? cc!.con : cc!.cc, shape: BoxShape.circle),
            child: Icon(c.icon, color: sel ? cc.cc : cc.con),
          );
    Widget corner(Color bg, Color fg, IconData icon) => Positioned(
      right: -2,
      top: -2,
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: bg,
          shape: BoxShape.circle,
          border: Border.all(color: hc.sheet, width: 2),
        ),
        child: Icon(icon, size: 12, color: fg),
      ),
    );
    return Semantics(
      button: true,
      selected: sel,
      label: c?.full ?? 'New category',
      excludeSemantics: true,
      child: Material(
        color: sel ? cc!.cc : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: c == null ? onNew : () => onPick(c),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
              child: Column(
                spacing: 6,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      ring,
                      if (sel) corner(cs.primary, cs.onPrimary, Icons.check_rounded),
                      if (!sel && selected.isEmpty && c != null && c == suggested)
                        corner(cs.primaryContainer, cs.onPrimaryContainer, Icons.auto_awesome_outlined),
                    ],
                  ),
                  Text(
                    c?.short ?? 'New',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 16 / 12,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? cc!.con : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Receipt = facts read from the SMS (mono on a frosted, dashed paper slip)

class Receipt extends StatelessWidget {
  const Receipt({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(12, 8, 12, 10)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc, g = context.glass;
    // A frosted paper slip: the dashes are its edge, so no rim.
    return Dashed(
      color: hc.paperEdge,
      radius: 18,
      child: Glass(
        radius: 18,
        color: g.on ? hc.paper.withValues(alpha: .78) : hc.paper,
        rim: false,
        shadow: false,
        padding: padding,
        child: DefaultTextStyle.merge(
          style: T.mono.copyWith(color: hc.onPaper),
          child: IconTheme.merge(
            data: IconThemeData(color: hc.paperMuted, size: 16),
            child: child,
          ),
        ),
      ),
    );
  }
}

class ReceiptHead extends StatelessWidget {
  const ReceiptHead(this.text, {super.key, this.icon = Icons.sms_outlined, this.trailing});

  final String text;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 24),
    child: Row(
      spacing: 6,
      children: [
        Icon(icon, size: 16),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: T.monoS.copyWith(color: context.hc.paperMuted),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Dashed tear line across the slip. (No perforation notches: they need a flat ground.)
class ReceiptCut extends StatelessWidget {
  const ReceiptCut({super.key, this.inset = 12});
  final double inset;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: SizedBox(
      height: 1.5,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -inset,
            right: -inset,
            top: 0,
            bottom: 0,
            child: CustomPaint(painter: _HDashPainter(context.hc.paperEdge)),
          ),
        ],
      ),
    ),
  );
}

class ReceiptRow extends StatelessWidget {
  const ReceiptRow(this.left, this.right, {super.key, this.leftMuted = false});

  final String left;
  final Widget right;
  final bool leftMuted;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    style: T.monoS.copyWith(height: 20 / 12),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      spacing: 12,
      children: [
        Text(left, style: leftMuted ? TextStyle(color: context.hc.paperMuted) : null),
        Flexible(child: right),
      ],
    ),
  );
}

/// Raw SMS text; [brackets] become highlighted facts.
class RawSms extends StatelessWidget {
  const RawSms(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    final spans = <TextSpan>[];
    text.splitMapJoin(
      RegExp(r'\[([^\]]*)\]'),
      onMatch: (m) {
        spans.add(
          TextSpan(
            text: m[1],
            style: TextStyle(backgroundColor: hc.hl),
          ),
        );
        return '';
      },
      onNonMatch: (s) {
        spans.add(TextSpan(text: s));
        return '';
      },
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: hc.paperEdge.withValues(alpha: .14), borderRadius: BorderRadius.circular(8)),
      child: Text.rich(
        TextSpan(children: spans),
        style: T.monoS.copyWith(height: 18 / 12, color: hc.onPaper),
      ),
    );
  }
}

String signedAmount(Txn t) => t.status == TxnStatus.unread
    ? rupees(t.paise)
    : t.inflow
    ? '+${rupees(t.paise)}'
    : '−${rupees(t.paise)}';

/// A small ink-coloured link on a receipt: "Raw ▾", "Edit".
Widget receiptLink(BuildContext context, String label, IconData icon, VoidCallback onTap, {bool iconFirst = false}) {
  final cs = context.cs;
  final style = TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w600, color: cs.primary);
  return InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          if (iconFirst) Icon(icon, size: 16, color: cs.primary),
          Text(label, style: style),
          if (!iconFirst) Icon(icon, size: 16, color: cs.primary),
        ],
      ),
    ),
  );
}

/// Full receipt for one captured payment. [onRename] adds Edit: the payee
/// becomes a field, and once it differs from the SMS it flips to ink.
class TxnReceipt extends StatefulWidget {
  const TxnReceipt(this.t, {super.key, this.name, this.onRename, this.rawOpen = false});

  final Txn t;

  /// The payee as edited so far; null = as the SMS said.
  final String? name;
  final ValueChanged<String>? onRename;
  final bool rawOpen;

  @override
  State<TxnReceipt> createState() => _TxnReceiptState();
}

class _TxnReceiptState extends State<TxnReceipt> {
  bool _editing = false;
  late bool _raw = widget.rawOpen;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final cs = context.cs, hc = context.hc;
    final unread = t.status == TxnStatus.unread;
    final name = widget.name ?? t.name, edited = name.trim() != t.name && name.trim().isNotEmpty;
    final payeeLine = edited
        ? 'SMS said ${t.vpa.isEmpty ? t.name : t.vpa}'
        : [if (t.vpa.isNotEmpty) t.isCredit ? 'from ${t.vpa}' : t.vpa, if (t.newPayee) 'new payee'].join(' · ');
    final inkStyle = TextStyle(
      fontFamily: 'Inter',
      fontSize: 15,
      height: 20 / 15,
      fontWeight: FontWeight.w600,
      color: cs.primary,
    );
    final Widget payee;
    if (_editing) {
      payee = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: TextFormField(
          initialValue: name,
          autofocus: true,
          style: inkStyle,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: context.glass.strong,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: cs.primary, width: 2),
            ),
          ),
          onChanged: widget.onRename,
          onFieldSubmitted: (_) => setState(() => _editing = false),
        ),
      );
    } else if (edited) {
      payee = Row(
        spacing: 4,
        children: [
          Icon(Icons.edit_outlined, size: 14, color: cs.primary),
          Flexible(child: Text(name.trim(), style: inkStyle)),
        ],
      );
    } else {
      payee = Text(
        t.name,
        style: TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600, color: hc.onPaper),
      );
    }

    return Receipt(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ReceiptHead(
            'SMS · ${t.sender}',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  expanded: _raw,
                  child: receiptLink(
                    context,
                    'Raw',
                    _raw ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    () => setState(() => _raw = !_raw),
                  ),
                ),
                if (widget.onRename != null && !unread)
                  receiptLink(
                    context,
                    _editing ? 'Done' : 'Edit',
                    _editing ? Icons.check_rounded : Icons.edit_outlined,
                    () => setState(() => _editing = !_editing),
                    iconFirst: true,
                  ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (t.isCredit) const Padding(padding: EdgeInsets.only(right: 8), child: DirIcon(inflow: true)),
              Text(
                signedAmount(t),
                style: T.mono.copyWith(
                  fontSize: 30,
                  height: 38 / 30,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -.6,
                  color: t.isCredit ? hc.teal : hc.onPaper,
                ),
              ),
              const Spacer(),
              Text(switch (t.status) {
                TxnStatus.credit => 'CREDIT',
                TxnStatus.unread => 'UNCLEAR',
                _ => 'DEBIT',
              }, style: T.monoS.copyWith(letterSpacing: .8, fontWeight: FontWeight.w500, color: hc.paperMuted)),
            ],
          ),
          if (!unread) payee,
          if (!unread && payeeLine.isNotEmpty) Text(payeeLine, style: T.monoS.copyWith(color: hc.paperMuted)),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            alignment: Alignment.topCenter,
            child: _raw
                ? Padding(padding: const EdgeInsets.only(top: 6), child: RawSms(t.raw))
                : const SizedBox(width: double.infinity),
          ),
          const ReceiptCut(),
          ReceiptRow(t.acct, Text('${dowDayMon(t.when)} · ${time12(t.when)}', overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ink = anything the user types (Inter, iris values in clear glass fields)

class InkHeading extends StatelessWidget {
  const InkHeading(this.text, {super.key, this.trailing});
  final String text;
  final String? trailing;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minHeight: 24),
    child: Row(
      children: [
        Icon(Icons.edit_outlined, size: 16, color: context.cs.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
              color: context.cs.primary,
            ),
          ),
        ),
        if (trailing != null) Text(trailing!, style: T.ls.copyWith(color: context.hc.muted)),
      ],
    ),
  );
}

/// Glass text field with the label inside, ink-coloured once filled.
class InkField extends StatefulWidget {
  const InkField({
    super.key,
    required this.icon,
    this.label,
    this.hint,
    this.initial,
    this.onChanged,
    this.autofocus = false,
  });

  final IconData icon;
  final String? label, hint, initial;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  State<InkField> createState() => _InkFieldState();
}

class _InkFieldState extends State<InkField> {
  late final _c = TextEditingController(text: widget.initial)..addListener(_redraw);
  final _f = FocusNode();

  void _redraw() => setState(() {});

  @override
  void initState() {
    super.initState();
    _f.addListener(_redraw);
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, hc = context.hc;
    final filled = _c.text.isNotEmpty, focused = _f.hasFocus;
    return GestureDetector(
      onTap: _f.requestFocus,
      child: Glass(
        radius: 18,
        shadow: false,
        edge: focused || filled ? cs.primary : null,
        edgeWidth: focused ? 2 : 1,
        padding: const EdgeInsets.fromLTRB(14, 6, 12, 6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            spacing: 12,
            children: [
              Icon(widget.icon, size: 20, color: filled ? cs.primary : hc.muted),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.label != null)
                      Text(
                        widget.label!,
                        style: TextStyle(fontSize: 12, height: 16 / 12, color: hc.muted),
                      ),
                    TextField(
                      controller: _c,
                      focusNode: _f,
                      autofocus: widget.autofocus,
                      onChanged: widget.onChanged,
                      decoration: InputDecoration.collapsed(
                        hintText: widget.hint,
                        hintStyle: TextStyle(color: hc.muted),
                      ),
                      style: TextStyle(
                        fontSize: 16,
                        height: 24 / 16,
                        color: filled ? cs.primary : cs.onSurface,
                        fontWeight: filled ? FontWeight.w500 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Containers & rows

enum BannerTone { warn, err, info, ok }

class HBanner extends StatelessWidget {
  const HBanner({
    super.key,
    required this.icon,
    required this.title,
    this.text,
    this.tone = BannerTone.info,
    this.actions = const [],
  });

  final IconData icon;
  final String title;
  final String? text;
  final BannerTone tone;
  final List<(String, VoidCallback)> actions;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs, hc = context.hc, g = context.glass;
    final (bg, fg, a) = switch (tone) {
      BannerTone.warn => (hc.amberC, hc.onAmberC, .82),
      BannerTone.err => (cs.errorContainer, cs.onErrorContainer, .84),
      BannerTone.info => (cs.primaryContainer, cs.onPrimaryContainer, .80),
      BannerTone.ok => (hc.tealC, hc.onTealC, .80),
    };
    return Glass(
      color: g.on ? bg.withValues(alpha: a) : bg,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Icon(icon, color: fg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 4,
              children: [
                Text(
                  title,
                  style: T.b.copyWith(fontWeight: FontWeight.w600, color: fg),
                ),
                if (text != null) Text(text!, style: T.b.copyWith(color: fg)),
                if (actions.isNotEmpty)
                  Transform.translate(
                    offset: const Offset(8, 2),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 4,
                        children: [
                          for (final (label, onTap) in actions)
                            TextButton(
                              onPressed: onTap,
                              style: TextButton.styleFrom(foregroundColor: fg, minimumSize: const Size(0, 40)),
                              child: Text(label),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Glass card.
class HCard extends StatelessWidget {
  const HCard({super.key, required this.child, this.padding = EdgeInsets.zero, this.borderColor});

  final Widget child;
  final EdgeInsets padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Glass(padding: padding, edge: borderColor, child: child);
}

/// Settings-style list row.
class Li extends StatelessWidget {
  const Li({
    super.key,
    required this.title,
    this.icon,
    this.leading,
    this.iconColor,
    this.sub,
    this.subMono = false,
    this.note,
    this.trailing,
    this.onTap,
    this.titleStyle,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  final String title;
  final IconData? icon;
  final Widget? leading;
  final Color? iconColor;
  final String? sub, note;
  final bool subMono;
  final Widget? trailing;
  final VoidCallback? onTap;
  final TextStyle? titleStyle;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final muted = context.hc.muted;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: padding,
          child: Row(
            spacing: 14,
            children: [
              if (icon != null) Icon(icon, color: iconColor ?? context.cs.onSurfaceVariant),
              ?leading,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 16, height: 24 / 16).merge(titleStyle)),
                    if (sub != null)
                      Text(
                        sub!,
                        style: subMono ? T.monoS.copyWith(height: 18 / 12, color: muted) : T.b.copyWith(color: muted),
                      ),
                    if (note != null) Text(note!, style: T.b.copyWith(color: muted)),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      ),
    );
  }
}

/// A divider inset past a row's leading icon.
class LiDivider extends StatelessWidget {
  const LiDivider({super.key});

  @override
  Widget build(BuildContext context) => const Divider(indent: 54);
}

class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.icon,
    required this.title,
    required this.sub,
    required this.value,
    required this.onChanged,
    this.iconColor,
  });

  final IconData icon;
  final String title, sub;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        spacing: 12,
        children: [
          Icon(icon, size: 20, color: iconColor ?? context.cs.primary),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: T.l),
                Text(sub, style: T.lsReg.copyWith(color: context.hc.muted)),
              ],
            ),
          ),
          HSwitch(value: value, onChanged: onChanged),
        ],
      ),
    ),
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(text.toUpperCase(), style: T.eyebrow.copyWith(color: context.hc.muted));
}

class SecLabel extends StatelessWidget {
  const SecLabel(this.text, {super.key, this.top = 16});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(16, top, 16, 4),
    child: Text(
      text,
      style: T.b.copyWith(fontWeight: FontWeight.w600, color: context.cs.primary),
    ),
  );
}

class DayHeader extends StatelessWidget {
  const DayHeader(this.left, this.right, {super.key});
  final String left, right;

  @override
  Widget build(BuildContext context) {
    final muted = context.hc.muted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 4),
      // Wrap: the day total drops under the date when both don't fit.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 2,
        children: [
          Text(
            left.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w600,
              letterSpacing: .4,
              color: muted,
            ),
          ),
          Text(
            right,
            style: T.monoS.copyWith(fontWeight: FontWeight.w500, color: muted),
          ),
        ],
      ),
    );
  }
}

/// 64 dp top app bar; actions float as glass circles.
class TopBar extends StatelessWidget {
  const TopBar(this.title, {super.key, this.leading, this.actions = const [], this.small = false});

  final String title;
  final Widget? leading;
  final List<Widget> actions;
  final bool small;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 64,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        spacing: 4,
        children: [
          ?leading,
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: leading == null ? 12 : 8),
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: small
                      ? const TextStyle(fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600)
                      : const TextStyle(fontSize: 24, height: 30 / 24, fontWeight: FontWeight.w700, letterSpacing: -.3),
                ),
              ),
            ),
          ),
          ...actions,
        ],
      ),
    ),
  );
}

/// Back arrow for a pushed page.
class BackBtn extends StatelessWidget {
  const BackBtn({super.key});

  @override
  Widget build(BuildContext context) =>
      GlassIconButton(icon: Icons.arrow_back_rounded, tooltip: 'Back', onPressed: () => Navigator.maybePop(context));
}

class CloseButtonX extends StatelessWidget {
  const CloseButtonX({super.key, this.tooltip = 'Close', this.onPressed});
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => GlassIconButton(
    icon: Icons.close_rounded,
    tooltip: tooltip,
    onPressed: onPressed ?? () => Navigator.maybePop(context),
  );
}

// ---------------------------------------------------------------------------
// Empty state art: two receipts and a seal

class EmptyArt extends StatelessWidget {
  const EmptyArt({super.key, this.icon = Icons.check_rounded, this.done = true});
  final IconData icon;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final hc = context.hc;
    Widget paper({Widget? child}) => Dashed(
      color: hc.paperEdge,
      radius: 10,
      child: Container(
        width: 84,
        height: 92,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(color: hc.paper, borderRadius: BorderRadius.circular(10)),
        child: child,
      ),
    );
    Widget line(double w) => FractionallySizedBox(
      widthFactor: w,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 6,
        decoration: BoxDecoration(color: hc.paperEdge.withValues(alpha: .55), borderRadius: BorderRadius.circular(3)),
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: 132,
        height: 112,
        child: Stack(
          children: [
            Positioned(
              left: 18,
              top: 10,
              child: Transform.rotate(angle: -6 * math.pi / 180, child: paper()),
            ),
            Positioned(
              left: 34,
              top: 6,
              child: paper(child: Column(spacing: 7, children: [line(1), line(.7), line(1), line(.5)])),
            ),
            Positioned(
              right: 0,
              bottom: -4,
              child: Seal(icon: icon, done: done),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round mark ringed in the glass edge: done (iris) or waiting.
class Seal extends StatelessWidget {
  const Seal({super.key, this.icon = Icons.check_rounded, this.done = true, this.size = 44});
  final IconData icon;
  final bool done;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: context.glass.edge, shape: BoxShape.circle),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: done ? cs.primary : cs.surfaceContainerHighest, shape: BoxShape.circle),
        child: Icon(icon, color: done ? cs.onPrimary : cs.onSurfaceVariant),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.text, this.art = const EmptyArt(), this.action});
  final String title, text;
  final Widget art;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      spacing: 12,
      children: [
        art,
        Text(title, textAlign: TextAlign.center, style: T.tl),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: T.b.copyWith(color: context.hc.muted),
          ),
        ),
        ?action,
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Onboarding step dots, keypad

class Steps extends StatelessWidget {
  const Steps(this.at, {super.key, this.of = 5});
  final int at, of;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Step ${at + 1} of $of',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        for (var i = 0; i < of; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: i == at ? 28 : 16,
            height: 4,
            decoration: BoxDecoration(
              color: i == at ? context.cs.primary : context.cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    ),
  );
}

/// 3×4 keypad of glass keys. Keys: '0'–'9', '.', '⌫'; long-press ⌫ sends 'C'.
class Keypad extends StatelessWidget {
  const Keypad({super.key, required this.onKey});
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    Widget key(String k) {
      final fn = k == '.' || k == '⌫';
      void send(String v) {
        HapticFeedback.selectionClick();
        onKey(v);
      }

      final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(20));
      Widget glass(Widget child) => fn
          ? Material(type: MaterialType.transparency, shape: shape, clipBehavior: Clip.antiAlias, child: child)
          : Glass(shape: shape, shadow: false, child: child);
      return Expanded(
        child: glass(
          InkWell(
            customBorder: shape,
            onTap: () => send(k),
            onLongPress: k == '⌫' ? () => send('C') : null,
            child: SizedBox(
              height: 52,
              child: Center(
                child: k == '⌫'
                    ? Icon(Icons.backspace_outlined, color: cs.onSurfaceVariant, semanticLabel: 'Delete')
                    : Text(
                        k,
                        style: T.num.copyWith(
                          fontSize: 24,
                          height: 32 / 24,
                          fontWeight: FontWeight.w500,
                          color: fn ? cs.onSurfaceVariant : cs.onSurface,
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      spacing: 8,
      children: [
        for (final row in const ['123', '456', '789', '.0⌫'])
          Row(spacing: 8, children: [for (final k in row.split('')) key(k)]),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sheets + snackbar

/// Thick glass behind a modal sheet: 32 radius, handle, strong blur.
class GlassSheet extends StatelessWidget {
  const GlassSheet({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = context.glass;
    const shape = RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32)));
    // ponytail: no full-screen softening blur behind the scrim any more; it
    // re-blurred the whole screen every frame of the slide and of any scroll
    // or keypad tap inside the sheet. The scrim alone separates the layers.
    return GlassShadow(
      shape: shape,
      shadows: const [BoxShadow(color: Color(0x2E14183C), offset: Offset(0, -12), blurRadius: 40)],
      child: Glass(
        shape: shape,
        color: g.sheet,
        blur: true,
        strongBlur: true,
        shadow: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 24,
              child: Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(color: context.cs.outline, borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

/// A modal sheet on thick glass.
Future<R?> showHSheet<R>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<R>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (c) => GlassSheet(child: builder(c)),
);

/// Bottom-sheet body: title row, scrolling content, pinned action bar.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    required this.title,
    required this.body,
    this.headerTrailing = const [],
    this.progress,
    this.footer,
    this.actions,
    this.heightFactor = .92,
    this.closeTooltip = 'Close',
    this.onClose,
  });

  final String title, closeTooltip;
  final Widget body;

  /// Beside the title, before Close: a queue's "2 of 5" and Skip.
  final List<Widget> headerTrailing;

  /// A progress line under the header.
  final double? progress;

  /// Between the scrolling body and the actions: a keypad, a snackbar.
  final Widget? footer;
  final List<Widget>? actions;
  final double heightFactor;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: SizedBox(
        height: math.max(240, MediaQuery.sizeOf(context).height * heightFactor - inset - 24),
        child: Column(
          children: [
            SizedBox(
              height: 52,
              child: Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Semantics(
                            header: true,
                            child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.tl),
                          ),
                        ),
                        ...headerTrailing,
                        CloseButtonX(tooltip: closeTooltip, onPressed: onClose),
                      ],
                    ),
                  ),
                  if (progress != null)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 0,
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(end: progress),
                        duration: const Duration(milliseconds: 250),
                        builder: (_, v, _) => LinearProgressIndicator(value: v, semanticsLabel: 'Review progress'),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12), child: body),
            ),
            ?footer,
            if (actions != null)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: context.glass.line)),
                ),
                child: SafeArea(top: false, child: Row(spacing: 12, children: actions!)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens a modal sheet; the sheet pops with a message, shown as a snackbar.
Future<void> openSheet(BuildContext context, Widget sheet) async {
  final msg = await showHSheet<String>(context, (_) => sheet);
  if (msg != null && context.mounted) toast(context, msg);
}

/// A dialog with one text field per (label, hint); null when cancelled.
Future<List<String>?> askText(
  BuildContext context,
  String title,
  List<(String label, String hint)> fields, {
  String action = 'Add',
  TextInputType? keyboard,
  List<String> initial = const [],
}) async {
  final cs = [for (final (i, _) in fields.indexed) TextEditingController(text: initial.elementAtOrNull(i))];
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          for (final (i, (label, hint)) in fields.indexed)
            TextField(
              controller: cs[i],
              autofocus: i == 0,
              keyboardType: i == fields.length - 1 ? keyboard : null,
              decoration: InputDecoration(labelText: label, hintText: hint),
              onSubmitted: i == fields.length - 1 ? (_) => Navigator.pop(d, true) : null,
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(d, true), child: Text(action)),
      ],
    ),
  );
  return ok == true ? [for (final c in cs) c.text.trim()] : null;
}

/// A snackbar on dark glass (light glass in dark mode).
void toast(BuildContext context, String msg, {VoidCallback? onUndo}) {
  final m = ScaffoldMessenger.of(context);
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        content: SnackPill(
          msg,
          onUndo: onUndo == null
              ? null
              : () {
                  m.hideCurrentSnackBar();
                  onUndo();
                },
        ),
        duration: const Duration(seconds: 6),
        persist: false,
      ),
    );
}

/// The snackbar's glass pill; also the queue's "Filed · Undo" inside a sheet.
class SnackPill extends StatelessWidget {
  const SnackPill(this.msg, {super.key, this.onUndo});
  final String msg;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final cs = context.cs;
    return Glass(
      shape: const StadiumBorder(),
      color: cs.inverseSurface,
      blur: true,
      padding: EdgeInsets.fromLTRB(20, 4, onUndo == null ? 20 : 4, 4),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          children: [
            Expanded(
              child: Text(
                msg,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: T.b.copyWith(color: cs.onInverseSurface),
              ),
            ),
            if (onUndo != null)
              TextButton(
                onPressed: onUndo,
                style: TextButton.styleFrom(foregroundColor: cs.inversePrimary, minimumSize: const Size(0, 40)),
                child: const Text('Undo'),
              ),
          ],
        ),
      ),
    );
  }
}
