import Toybox.Lang;
import Toybox.Math;
import Toybox.Test;

// Counts circumambulations.
//
// Round 1: start circle. The first fix locks the start point. The round counts when you
// have been more than 2 x radius away and come back within radius. Meanwhile the walk's
// outer bounds give the chorten's centre, and the signed area gives the walking direction.
//
// Round 2 on: start line. The line runs from the centre out through the start point.
// Progress round the centre is summed fix by fix; a full turn in the walking direction
// counts a round, however far in or out you pass the start. Walking back over the line
// subtracts, so turning back and crossing again doesn't count twice.
class RoundCounter {

    var count as Number = 0;
    var dist as Float = 0.0;            // metres from the start point, last fix
    private var _lat as Float?;          // start point, radians
    private var _lon as Float = 0.0;
    private var _away as Boolean = false;
    private var _radius as Float;
    private var _x as Float = 0.0;       // last fix, metres east / north of the start point
    private var _y as Float = 0.0;
    private var _minX as Float = 0.0;    // round-1 bounds and signed area
    private var _maxX as Float = 0.0;
    private var _minY as Float = 0.0;
    private var _maxY as Float = 0.0;
    private var _n as Number = 0;
    private var _area as Float = 0.0;
    private var _cx as Float?;           // learned centre
    private var _cy as Float = 0.0;
    private var _cw as Boolean = true;   // clockwise seen from above (the usual kora)
    private var _turn as Float = 0.0;    // turns since the last round, in the walking direction
    private var _prev as Float = 0.0;    // last position()

    function initialize(radius as Float) {
        _radius = radius;
    }

    function hasAnchor() as Boolean {
        return _lat != null;
    }

    // Feed one GPS fix (radians). Returns true when it completes a round.
    function update(lat as Float, lon as Float) as Boolean {
        if (_lat == null) {
            _lat = lat;
            _lon = lon;
            return false;
        }
        // equirectangular: exact enough over a few hundred metres
        var x = ((lon - _lon) * Math.cos(lat) * 6371000.0).toFloat();
        var y = ((lat - (_lat as Float)) * 6371000.0).toFloat();
        dist = Math.sqrt(x * x + y * y).toFloat();
        if (count == 0) {
            if (x < _minX) { _minX = x; }
            if (x > _maxX) { _maxX = x; }
            if (y < _minY) { _minY = y; }
            if (y > _maxY) { _maxY = y; }
            _n++;
            _area += _x * y - x * _y;
        }
        _x = x;
        _y = y;

        if (_cx != null) {                       // start line
            var f = position();
            if (f == null) { return false; }
            var d = (f as Float) - _prev;
            if (d > 0.5) { d -= 1.0; } else if (d < -0.5) { d += 1.0; }
            _prev = f as Float;
            _turn += d;
            if (_turn >= 1.0) {
                _turn -= 1.0;
                count++;
                return true;
            }
            return false;
        }
        if (!_away && dist > 2 * _radius) {      // start circle
            _away = true;
        } else if (_away && dist < _radius) {
            add();
            return true;
        }
        return false;
    }

    // Round 1 by the start circle, and the lap button when GPS is blocked
    // (roofed prayer-wheel corridors): counts a round and treats you as on the start line.
    function add() as Void {
        count++;
        _away = false;
        if (count == 1 && _n >= 8 && _maxX - _minX > 4 && _maxY - _minY > 4) {
            _cx = (_minX + _maxX) / 2;
            _cy = (_minY + _maxY) / 2;
            _cw = _area < 0;
        }
        var f = position();
        if (f != null) {
            _prev = f as Float;
            _turn = _prev > 0.5 ? _prev - 1.0 : _prev;
        }
    }

    // 0..1 round the circuit from the start line, or null until round 1 has taught the
    // centre (and while you're within 3 m of it, where the angle means nothing).
    function position() as Float? {
        if (_cx == null) { return null; }
        var cx = _cx as Float;
        var ex = _x - cx;
        var ey = _y - _cy;
        if (ex * ex + ey * ey < 9) { return null; }
        var a0 = Math.atan2(-_cy, -cx);              // the start point, seen from the centre
        var a = Math.atan2(ey, ex);
        var d = _cw ? a0 - a : a - a0;
        var f = d / (2 * Math.PI);
        f -= Math.floor(f);
        return f.toFloat();
    }
}

// Feeds one fix dx/dy metres from the Thimphu Memorial Chorten test start point.
function feed(c as RoundCounter, dx as Float, dy as Float) as Boolean {
    var lat0 = Math.toRadians(27.4728);
    var m = 1.0 / 6371000.0;
    return c.update((lat0 + dy * m).toFloat(), (Math.toRadians(89.6411) + dx * m / Math.cos(lat0)).toFloat());
}

// Walks clockwise on a circle of radius r round a centre 25 m south of the start point,
// from angle a0 to a1 degrees (0 = due north of the centre), with +-3 m noise.
function walk(c as RoundCounter, r as Float, a0 as Number, a1 as Number) as Void {
    var step = a1 > a0 ? 5 : -5;
    for (var i = a0; i != a1 + step; i += step) {
        var a = Math.toRadians(i);
        var n = ((i / 5) % 4 - 1.5) * 2.0;
        feed(c, (r * Math.sin(a) + n).toFloat(), (r * Math.cos(a) - 25 + n).toFloat());
    }
}

// Standing at the start counts nothing; round 1 counts by the start circle; rounds 2-3 count
// by the start line even passing 12 m outside the start point, where the circle would miss.
(:test)
function roundCounterStartLine(logger as Test.Logger) as Boolean {
    var c = new RoundCounter(8.0);
    for (var i = 0; i < 30; i++) {
        feed(c, 0.0, ((i % 3 - 1) * 3).toFloat());       // jitter while standing at the start
    }
    Test.assertEqual(0, c.count);
    walk(c, 25.0, 0, 360);
    Test.assertEqual(1, c.count);
    walk(c, 37.0, 0, 720);                                // two wider rounds
    Test.assertEqual(3, c.count);
    // a quarter of the way round (due east of the centre) reads ~0.25
    walk(c, 37.0, 90, 90);
    var p = c.position() as Float;
    Test.assertMessage(p > 0.2 && p < 0.3, "position " + p.toString());
    return true;
}

// Turning back over the start line and crossing it again must not count twice.
(:test)
function roundCounterNoDoubleCount(logger as Test.Logger) as Boolean {
    var c = new RoundCounter(8.0);
    walk(c, 25.0, 0, 360);
    walk(c, 25.0, 0, 340);
    walk(c, 25.0, 340, 380);           // cross the line: round 2
    Test.assertEqual(2, c.count);
    walk(c, 25.0, 380, 330);           // back over it
    walk(c, 25.0, 330, 390);           // and forward again
    Test.assertEqual(2, c.count);
    walk(c, 25.0, 390, 720);           // round 3 completes at the line
    Test.assertEqual(3, c.count);
    return true;
}
