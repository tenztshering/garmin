import Toybox.Graphics;
import Toybox.Lang;

// AMOLED always-on rules (break either and the watch swaps in its plain default face):
// at most 10% of pixels lit, and no pixel lit for more than 3 minutes.
//
// aodShift(): where to nudge the content this minute; steps are 6-8 px, wider than the
// strokes, so the same stroke never covers the same pixel two minutes running.
function aodShift(minute as Number) as [Number, Number] {
    var shifts = [[0, 0], [8, 4], [-6, 8], [6, -8], [-8, -4]];
    return shifts[minute % 5] as [Number, Number];
}

// burnInMask(): draw last. Blanks every other pixel row, swapping rows each minute, so no
// pixel can be lit two minutes in a row whatever was drawn.
function burnInMask(dc as Graphics.Dc, minute as Number) as Void {
    if (dc has :setAntiAlias) { dc.setAntiAlias(false); }
    dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
    dc.setPenWidth(1);
    var w = dc.getWidth();
    for (var y = minute % 2; y < dc.getHeight(); y += 2) {
        dc.drawLine(0, y, w, y);
    }
}
