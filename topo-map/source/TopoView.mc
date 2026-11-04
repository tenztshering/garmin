import Toybox.Attention;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Position;
import Toybox.Timer;
import Toybox.WatchUi;

// Topographic map from resources/data/topo.json (built by tools/make_topo.py).
//
// Drawing the whole visible map in one go trips the watch's watchdog, so the map is
// rendered progressively into an off-screen bitmap (a few hundred points every 50 ms).
// onUpdate() only copies that bitmap and draws the overlays on top.
class TopoView extends WatchUi.View {

    // Garmin-topo style. Keep in sync with tools/preview.py.
    const PAPER      = 0xE9E8E3;
    const CONTOUR    = 0xB4885C;
    const INDEX      = 0x8A5A2E;
    const WATER      = 0x3F63D6;
    const TRACK      = 0x7E7D78;
    const ROAD       = 0xD2861A;
    const TREE       = 0x2F9E44;
    const TREE_EDGE  = 0x1E6B2E;
    const TRUNK      = 0x6B4A2B;
    const INK        = 0x151515;
    const NORTH      = 0xE0261B;

    // Screen width in metres for each zoom level
    const ZOOMS = [1000, 2000, 5000, 10000];

    // Render passes in draw order: [kind, colour, pen width].
    // Kinds 0-5 are lines (contour, index contour, water, main road, track, street);
    // the negative ones are symbols: trees, elevation labels, place names.
    const PASS_SHADE = -4;
    const PASS_TREES = -1;
    const PASS_LABELS = -2;
    const PASS_PLACES = -3;
    const PASSES = [[-4, 0, 0], [0, 0xB4885C, 1], [1, 0x8A5A2E, 1], [2, 0x3F63D6, 1], [4, 0x7E7D78, 1],
                    [5, 0x7E7D78, 1], [3, 0xD2861A, 2], [-1, 0, 0], [-2, 0, 0], [-3, 0, 0]];

    const BUDGET = 350;          // work units per render step (1 per point, 1 per 8 boxes checked)
    const STEP_MS = 50;

    // Map data (see make_topo.py): per kind, encoded polyline pieces and packed bounding boxes.
    private var _pieces as Array<Array<String>>;
    private var _boxes as Array<Array<Number>>;
    private var _trees as Array<Number> = [];         // one per tree: (x << 12 | y) in 12-bit units
    private var _labels as Array<Array<Number>>;      // [x, y, elevation, angle]
    private var _places as Array<Array>;              // [x, y, name]
    private var _labelFont as Graphics.VectorFont? = null;
    private var _placeFont as Graphics.VectorFont? = null;
    private var _half as Number;
    private var _unit as Float;          // metres per 12-bit map unit
    private var _lat0 as Float;
    private var _lon0 as Float;
    private var _kx as Float;

    // What the user is looking at
    private var _zoom as Number = 1;
    private var _fix as Boolean = false;
    private var _mx as Float = 0.0;      // position, map metres
    private var _my as Float = 0.0;

    // Off-screen render
    private var _buf as Graphics.BufferedBitmapReference? = null;
    private var _w as Number = 390;
    private var _bx as Float = 0.0;      // map metres at the bitmap centre
    private var _by as Float = 0.0;
    private var _bzoom as Number = -1;
    private var _pass as Number = 0;
    private var _piece as Number = 0;
    private var _rendering as Boolean = false;
    private var _steps as Number = 0;
    private var _timer as Timer.Timer = new Timer.Timer();
    private var _wake as Timer.Timer = new Timer.Timer();
    private var _awake as Boolean = true;

    function initialize() {
        View.initialize();
        var d = WatchUi.loadResource(Rez.JsonData.Topo) as Dictionary;
        _pieces = d["k"] as Array<Array<String>>;
        _boxes = d["b"] as Array<Array<Number>>;
        var tb = (d["tr"] as String).toUtf8Array();
        for (var i = 0; i + 3 < tb.size(); i += 4) {
            _trees.add((dec(tb[i], tb[i + 1]) << 12) | dec(tb[i + 2], tb[i + 3]));
        }
        _labels = d["t"] as Array<Array<Number>>;
        _places = d["pl"] as Array<Array>;
        _half = d["h"] as Number;
        _unit = (2.0 * _half / 4095.0).toFloat();
        _lat0 = d["lat"] as Float;
        _lon0 = d["lon"] as Float;
        _kx = (111320.0 * Math.cos(Math.toRadians(_lat0))).toFloat();
    }

    function onLayout(dc as Graphics.Dc) as Void {
        _w = dc.getWidth();
        if (Graphics has :getVectorFont) {
            var bold = ["RobotoCondensedBold", "RobotoBold", "RobotoRegular"];
            _labelFont = Graphics.getVectorFont({:face => bold, :size => (_w * 0.05).toNumber()});
            _placeFont = Graphics.getVectorFont({:face => bold, :size => (_w * 0.045).toNumber()});
        }
        // Native colour format (no palette, ~304 KB): scaled bitmap drawing, used for the
        // hill-shade, refuses palette targets.
        _buf = Graphics.createBufferedBitmap({:width => _w, :height => _w});
        startRender();
    }

    function onHide() as Void {
        _wake.stop();
        _timer.stop();
        _rendering = false;
        _bzoom = -1;      // re-render when shown again
    }

    function onShow() as Void {
        if (_awake) {
            keepAwake();
            _wake.start(method(:keepAwake), 5000, true);
        }
        if (_buf != null && _bzoom == -1) {
            startRender();
        }
    }

    // Off in battery saver mode. Takes effect immediately.
    function setKeepAwake(on as Boolean) as Void {
        _awake = on;
        _wake.stop();
        if (on) {
            keepAwake();
            _wake.start(method(:keepAwake), 5000, true);
        }
    }

    // Keep the screen lit while the map is open (stopped in onHide, i.e. when you press BACK).
    // On AMOLED the watch refuses after a while to prevent burn-in; then we just try again later.
    function keepAwake() as Void {
        if (Attention has :backlight) {
            try {
                Attention.backlight(true);
            } catch (e instanceof Attention.BacklightOnTooLongException) {
            }
        }
    }

    function setPosition(info as Position.Info) as Void {
        var p = info.position;
        if (p == null || info.accuracy < Position.QUALITY_POOR) {
            return;
        }
        var deg = p.toDegrees();
        var mx = ((deg[1] - _lon0) * _kx).toFloat();
        var my = ((deg[0] - _lat0) * 110540.0).toFloat();
        // standing still: skip the redraw unless we moved at least a pixel
        var px = _w.toFloat() / ZOOMS[_zoom];
        if (_fix && (mx - _mx).abs() * px < 1 && (my - _my).abs() * px < 1) {
            return;
        }
        _mx = mx;
        _my = my;
        _fix = true;
        // re-render once we have moved 15% of the screen away from the rendered centre
        var limit = ZOOMS[_zoom] * 0.15;
        var c = viewCentre();
        if ((c[0] - _bx).abs() > limit || (c[1] - _by).abs() > limit) {
            startRender();
        }
        WatchUi.requestUpdate();
    }

    function zoom(step as Number) as Void {
        var z = _zoom + step;
        if (z >= 0 && z < ZOOMS.size()) {
            _zoom = z;
            startRender();
            WatchUi.requestUpdate();
        }
    }

    // ------------------------------------------------------------------ progressive render

    private function inside() as Boolean {
        return _mx.abs() <= _half && _my.abs() <= _half;
    }

    // Centre of the view: your position, or the map centre when there is no usable fix.
    private function viewCentre() as Array<Float> {
        return (_fix && inside()) ? [_mx, _my] : [0.0, 0.0];
    }

    private function startRender() as Void {
        var buf = _buf;
        if (buf == null) { return; }
        var c = viewCentre();
        _bx = c[0];
        _by = c[1];
        _bzoom = _zoom;
        _pass = 0;
        _piece = 0;
        var bdc = (buf.get() as Graphics.BufferedBitmap).getDc();
        bdc.setColor(PAPER, PAPER);
        bdc.clear();
        if (!_rendering) {
            _rendering = true;
            _timer.start(method(:renderStep), STEP_MS, true);
        }
    }

    function renderStep() as Void {
        var buf = _buf;
        if (buf == null) { return; }
        var dc = (buf.get() as Graphics.BufferedBitmap).getDc();
        var budget = BUDGET;
        while (budget > 0 && _pass < PASSES.size()) {
            var p = PASSES[_pass];
            var kind = p[0];
            var used = (kind == PASS_SHADE) ? drawShade(dc)
                     : (kind == PASS_TREES) ? drawTrees(dc, budget)
                     : (kind == PASS_LABELS) ? drawLabels(dc, budget)
                     : (kind == PASS_PLACES) ? drawPlaces(dc)
                     : drawPieces(dc, kind, p[1], p[2], budget);
            if (used < 0) {        // pass finished; carry over what is left of the budget
                budget = -used - 1;
                _pass++;
                _piece = 0;
            } else {
                budget = 0;
            }
        }
        _steps++;
        if (_pass >= PASSES.size()) {
            _timer.stop();
            _rendering = false;
            WatchUi.requestUpdate();
        } else if (_steps % 4 == 0) {      // show progress 5x a second, not on every step
            WatchUi.requestUpdate();
        }
    }

    // Draws pieces of one kind starting at _piece until the budget runs out.
    // Returns 0 if it stopped on the budget, or -(1 + unused budget) when the pass is done.
    private function drawPieces(dc as Graphics.Dc, kind as Number, color as Number, pen as Number,
                                budget as Number) as Number {
        // level of detail: thin contours only when zoomed in, tracks hidden at the widest zoom
        if ((kind == 0 && _bzoom >= 2) || (kind == 4 && _bzoom >= 3)) {
            return -(1 + budget);
        }
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);

        // work in 12-bit map units: q = (metres + half) / unit
        var span = ZOOMS[_bzoom];
        var u = _unit;
        var qvx = (_bx + _half) / u;
        var qvy = (_by + _half) / u;
        var qr = span / 2.0 * 1.05 / u;
        var x0 = qvx - qr;
        var x1 = qvx + qr;
        var y0 = qvy - qr;
        var y1 = qvy + qr;
        var c = _w / 2.0;
        var kq = _w * u / span;                  // pixels per map unit
        var step = (_bzoom >= 3) ? 8 : 4;        // 4 bytes per point; widest zoom skips every other point

        var pieces = _pieces[kind];
        var boxes = _boxes[kind];
        var n = pieces.size();
        var checks = 0;
        while (_piece < n) {
            var i = _piece;
            _piece++;
            var lo = boxes[2 * i];
            var hi = boxes[2 * i + 1];
            checks++;
            if (checks == 8) { checks = 0; budget--; }
            if ((hi >> 12) < x0 || (lo >> 12) > x1 || (hi & 0xFFF) < y0 || (lo & 0xFFF) > y1) {
                if (budget <= 0) { return 0; }
                continue;
            }
            var b = pieces[i].toUtf8Array();
            var m = b.size();
            // decode inline: each value is two chars, 6 bits each, as 35+v ('c' stands for '\')
            var h = b[0];
            var l = b[1];
            if (h == 99) { h = 92; }
            if (l == 99) { l = 92; }
            var px = c + ((h - 35) * 64 + (l - 35) - qvx) * kq;
            h = b[2];
            l = b[3];
            if (h == 99) { h = 92; }
            if (l == 99) { l = 92; }
            var py = c - ((h - 35) * 64 + (l - 35) - qvy) * kq;
            var j = 0;
            while (j < m - 4) {
                j += step;
                if (j > m - 4) { j = m - 4; }    // always finish on the last point
                h = b[j];
                l = b[j + 1];
                if (h == 99) { h = 92; }
                if (l == 99) { l = 92; }
                var qx = c + ((h - 35) * 64 + (l - 35) - qvx) * kq;
                h = b[j + 2];
                l = b[j + 3];
                if (h == 99) { h = 92; }
                if (l == 99) { l = 92; }
                var qy = c - ((h - 35) * 64 + (l - 35) - qvy) * kq;
                dc.drawLine(px, py, qx, qy);
                px = qx;
                py = qy;
                budget--;
            }
            if (budget <= 0) { return 0; }
        }
        return -(1 + (budget > 0 ? budget : 0));
    }

    // ------------------------------------------------------------------ shaded relief

    // Draws hill-shade bitmaps under everything else, scaled up with smoothing.
    // 1-2 km zoom: the visible 128 px tiles, one per render step (loading is the slow part).
    // 5-10 km zoom: a single low-resolution overview. Same return convention as drawPieces.
    private function drawShade(dc as Graphics.Dc) as Number {
        if (!(dc has :drawBitmap2)) { return -1; }
        var k = _w.toFloat() / ZOOMS[_bzoom];       // screen px per metre
        var c = _w / 2.0;
        var left = c + (-_half - _bx) * k;          // screen position of the map's north-west corner
        var top = c - (_half - _by) * k;
        if (_bzoom >= 2) {
            if (_piece > 0) { return -1; }
            _piece = 1;
            var scale = 2.0 * _half / ShadeTiles.OVERVIEW * k;
            shadeBitmap(dc, Rez.Drawables.shade_overview, left, top, scale);
            return 0;
        }
        var n = ShadeTiles.PER_SIDE;
        var tileM = 2.0 * _half / n;                 // metres per tile
        var scale = tileM / ShadeTiles.TILE * k;
        var ids = ShadeTiles.tiles();
        while (_piece < n * n) {
            var i = _piece;
            _piece++;
            var x = left + (i % n) * tileM * k;
            var y = top + (i / n) * tileM * k;
            var size = tileM * k;
            if (x + size < 0 || y + size < 0 || x > _w || y > _w) { continue; }
            shadeBitmap(dc, ids[i], x, y, scale);
            return 0;
        }
        return -1;
    }

    private function shadeBitmap(dc as Graphics.Dc, id as ResourceId, x as Float, y as Float, scale as Float) as Void {
        var bmp = WatchUi.loadResource(id) as Graphics.BitmapReference or WatchUi.BitmapResource;
        var t = new Graphics.AffineTransform();
        t.scale(scale, scale);
        dc.drawBitmap2(x, y, bmp, {:transform => t, :filterMode => Graphics.FILTER_MODE_BILINEAR});
    }

    // ------------------------------------------------------------------ symbols

    // One 12-bit value from two encoded characters (see make_topo.py enc()).
    private function dec(h as Number, l as Number) as Number {
        if (h == 99) { h = 92; }
        if (l == 99) { l = 92; }
        return (h - 35) * 64 + (l - 35);
    }

    // Screen position of a map point given in 12-bit units, relative to the render centre.
    private function unitToScreen(qx as Number, qy as Number) as Array<Float> {
        var k = _w.toFloat() / ZOOMS[_bzoom];
        var c = _w / 2.0;
        return [c + (qx * _unit - _half - _bx) * k, c - (qy * _unit - _half - _by) * k];
    }

    private function onScreen(x as Float, y as Float, margin as Float) as Boolean {
        return x > -margin && y > -margin && x < _w + margin && y < _w + margin;
    }

    // Pine tree symbols in forest areas. Hidden at 10 km where they would be noise.
    private function drawTrees(dc as Graphics.Dc, budget as Number) as Number {
        if (_bzoom >= 3) { return -(1 + budget); }
        var n = _trees.size();
        var s = _w * 0.016;
        while (_piece < n) {
            var q = _trees[_piece];
            _piece++;
            budget--;
            var p = unitToScreen(q >> 12, q & 0xFFF);
            var x = p[0];
            var y = p[1];
            if (onScreen(x, y, s * 2)) {
                dc.setColor(TRUNK, Graphics.COLOR_TRANSPARENT);
                dc.fillRectangle(x - 1, y + s * 0.9, 2, s * 0.6);
                tier(dc, x, y + s, s, s * 1.2);
                tier(dc, x, y + s * 0.2, s * 0.75, s * 1.4);
                budget -= 6;
            }
            if (budget <= 0) { return 0; }
        }
        return -(1 + (budget > 0 ? budget : 0));
    }

    // One triangular tier of a pine: base centred at (x, y), half-width hw, height ht.
    private function tier(dc as Graphics.Dc, x as Float, y as Float, hw as Float, ht as Float) as Void {
        var pts = [[x - hw, y], [x + hw, y], [x, y - ht]];
        dc.setColor(TREE, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
        dc.setColor(TREE_EDGE, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(x - hw, y, x, y - ht);
        dc.drawLine(x, y - ht, x + hw, y);
        dc.drawLine(x - hw, y, x + hw, y);
    }

    // Bold black elevation numbers along index contours (1 and 2 km zoom only).
    private function drawLabels(dc as Graphics.Dc, budget as Number) as Number {
        if (_bzoom >= 2) { return -(1 + budget); }
        var k = _w.toFloat() / ZOOMS[_bzoom];
        var c = _w / 2.0;
        while (_piece < _labels.size()) {
            var t = _labels[_piece];
            _piece++;
            budget--;
            var x = c + (t[0] - _bx) * k;
            var y = c - (t[1] - _by) * k;
            if (onScreen(x, y, 0.0) && clearOfOverlays(x, y)) {
                haloText(dc, x, y, _labelFont, t[2].toString(), (t[3] + 360) % 360);
                budget -= 40;
            }
            if (budget <= 0) { return 0; }
        }
        return -(1 + (budget > 0 ? budget : 0));
    }

    // Place names, bold and upright.
    private function drawPlaces(dc as Graphics.Dc) as Number {
        if (_bzoom >= 3) { return -1; }
        var k = _w.toFloat() / ZOOMS[_bzoom];
        var c = _w / 2.0;
        for (var i = 0; i < _places.size(); i++) {
            var p = _places[i];
            var x = c + ((p[0] as Number) - _bx) * k;
            var y = c - ((p[1] as Number) - _by) * k;
            if (onScreen(x, y, 0.0) && clearOfOverlays(x, y)) {
                haloText(dc, x, y, _placeFont, p[2] as String, 0);
            }
        }
        return -1;
    }

    // Keep map text out from under the crosshair, the north arrow and the scale bar.
    // (Map pixels are relative to the render centre, which is the screen centre when drawn.)
    private function clearOfOverlays(x as Float, y as Float) as Boolean {
        var w = _w.toFloat();
        var c = w / 2;
        var dx = x - c;
        var dy = y - c;
        if (dx * dx + dy * dy < (w * 0.2) * (w * 0.2)) { return false; }          // crosshair
        if ((x - w * 0.16).abs() < w * 0.1 && (y - w * 0.27).abs() < w * 0.1) { return false; }   // north arrow
        if (y > w * 0.78 && (x - c).abs() < w * 0.25) { return false; }           // scale bar
        return true;
    }

    // Bold ink text on a paper halo: the halo knocks the map lines out behind the text.
    private function haloText(dc as Graphics.Dc, x as Float, y as Float, font as Graphics.VectorFont?,
                              s as String, angle as Number) as Void {
        var just = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var angled = font != null && (dc has :drawAngledText);
        var o = 2;
        var offs = [[-o, 0], [o, 0], [0, -o], [0, o], [-o, -o], [o, o], [-o, o], [o, -o], [0, 0]];
        for (var i = 0; i < offs.size(); i++) {
            var last = (i == offs.size() - 1);
            dc.setColor(last ? INK : PAPER, Graphics.COLOR_TRANSPARENT);
            var ox = x + offs[i][0];
            var oy = y + offs[i][1];
            if (angled) {
                dc.drawAngledText(ox, oy, font as Graphics.VectorFont, s, just, angle);
            } else {
                dc.drawText(ox, oy, Graphics.FONT_XTINY, s, just);
            }
        }
    }

    // ------------------------------------------------------------------ screen

    function onUpdate(dc as Graphics.Dc) as Void {
        var w = dc.getWidth();
        var c = w / 2.0;
        dc.setColor(PAPER, PAPER);
        dc.clear();

        // the rendered map, shifted by how far we have moved since it was rendered
        var buf = _buf;
        if (buf != null && _bzoom == _zoom) {
            var k = w.toFloat() / ZOOMS[_zoom];
            var vc = viewCentre();
            var dx = ((_bx - vc[0]) * k).toNumber();
            var dy = ((vc[1] - _by) * k).toNumber();
            dc.drawBitmap(dx, dy, buf);
        }

        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        drawNorth(dc, w);
        drawScale(dc, w, ZOOMS[_zoom]);
        drawCrosshair(dc, c);
    }

    // Your position: a crosshair on a paper halo so it always separates from the map.
    private function drawCrosshair(dc as Graphics.Dc, c as Float) as Void {
        crossLines(dc, c, PAPER, 7);
        crossLines(dc, c, INK, 3);
        dc.fillCircle(c, c, 2.5);

        var msg = !_fix ? "NO GPS" : (!inside() ? "OUTSIDE MAP" : null);
        if (msg != null) {
            var y = c * 0.36;
            var tw = dc.getTextWidthInPixels(msg, Graphics.FONT_XTINY) + c * 0.12;
            var th = c * 0.13;
            dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(c - tw / 2, y - th / 2, tw, th, th / 2);
            dc.setColor(PAPER, Graphics.COLOR_TRANSPARENT);
            dc.drawText(c, y, Graphics.FONT_XTINY, msg, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    private function crossLines(dc as Graphics.Dc, c as Float, color as Number, pen as Number) as Void {
        var r = c * 0.07;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(pen);
        dc.drawCircle(c, c, r);
        dc.drawLine(c - r * 2.1, c, c - r, c);
        dc.drawLine(c + r, c, c + r * 2.1, c);
        dc.drawLine(c, c - r * 2.1, c, c - r);
        dc.drawLine(c, c + r, c, c + r * 2.1);
    }

    // Red north arrow at the top left, on a paper disc.
    private function drawNorth(dc as Graphics.Dc, w as Number) as Void {
        var x = w * 0.16;
        var y = w * 0.27;
        var s = w * 0.032;
        dc.setColor(PAPER, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, s * 1.9);
        dc.setColor(NORTH, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x, y - s * 1.5], [x + s, y + s], [x, y + s * 0.35]]);
        dc.setColor(0x8E1710, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[x, y - s * 1.5], [x - s, y + s], [x, y + s * 0.35]]);
    }

    // Scale bar for about a fifth of the screen width.
    private function drawScale(dc as Graphics.Dc, w as Number, span as Number) as Void {
        var metres = span / 5;
        var nice = [100, 200, 250, 500, 1000, 2000];
        var m = nice[0];
        for (var i = 0; i < nice.size(); i++) {
            if (nice[i] <= metres) { m = nice[i]; }
        }
        var len = w.toFloat() * m / span;
        var x = w / 2.0 - len / 2;
        var y = w * 0.87;
        dc.setColor(PAPER, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x - 4, y - w * 0.067, len + 8, w * 0.08);
        dc.setColor(INK, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(x, y, x + len, y);
        dc.setPenWidth(2);
        dc.drawLine(x, y - 6, x, y + 1);
        dc.drawLine(x + len, y - 6, x + len, y + 1);
        var label = (m >= 1000) ? (m / 1000).toString() + " km" : m.toString() + " m";
        dc.drawText(w / 2.0, y - w * 0.045, Graphics.FONT_XTINY, label, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
