import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Digit entry on the system WatchUi.Picker: a single 0-9 column, Start
// appends the chosen digit, Back removes the last digit or cancels when
// nothing has been entered yet. Every edit starts from an empty number; it
// is handed to the callback only once all digits are in. The firmware
// drives the picker, so buttons and touch work the same as in the watch's
// own settings.
//
// The native Picker paints the whole screen itself and gives each of its
// drawables (title, column entries, arrows, confirm item) a small drawing
// area of its own: on vivoactive 4 the title gets 182x23 px, the selected
// entry 175x35 px, each arrow 30x30 px; on fr955 202x31, 184x103 and
// 16x8 px. So the label lives in the title and the whole number lives in
// the entry: each item of the column draws the digits entered so far, then
// its own digit inverted as the candidate, then underscores for the rest
// ("09[8] ___"). Where the entry is too narrow for the whole number (65 to
// 120 px on 47 watches, 30 px on Venu Sq 2, 40 to 46 px on the
// semi-octagon Instinct family and Descent G1) it shows only the candidate,
// and the title shows the whole number instead of the label. The + and -
// that mark the tap zones go into the arrow
// areas: on both vivoactive 4 and fr955 the firmware takes the taps
// there and nowhere else. They are drawn only while the touch screen is
// enabled and the watch has no Up and Down buttons (vivoactive 4 yes,
// fr955 no: its 8x8 px signs were unreadable).
//
// Colours: the Picker's own background is not exposed by the API and
// differs between the simulator (white on vivoactive 4) and the watch
// (black, like the firmware's own pickers), and a drawable cannot read
// the pixels under it. So nothing here relies on that background: every
// drawable that draws something first fills its own area with PICKER_BG
// and then draws in PICKER_FG. White on black matches the watch; in the
// simulator the areas show as black patches on the white Picker, which is
// fine for development. Hidden items draw nothing at all.
//
// Memory: Monkey C frees objects by reference counting, so nothing here
// may point back at its owner. The shared state (DigitEntry) is
// referenced by the delegate, the title, the factory and the rows; none of
// them knows the picker. The factory makes a DigitRow (a few words and the
// reference to the entry) each time the Picker asks for one, so only the row
// on show exists; the digits live in a fixed array of numbers and draw()
// builds no strings.

const PICKER_FG = Graphics.COLOR_WHITE;
const PICKER_BG = Graphics.COLOR_BLACK;
const PICKER_MUTED = Graphics.COLOR_LT_GRAY;

// Fills the drawable's whole area with the background, so what it draws
// reads the same whatever the Picker painted there first.
function fillBackground(dc as Dc) as Void {
    dc.setColor(PICKER_BG, PICKER_BG);
    dc.fillRectangle(0, 0, dc.getWidth(), dc.getHeight());
}

function widestDigit(dc as Dc, f as FontDefinition) as Number {
    var widest = 0;
    for (var d = 0; d < 10; d++) {
        var dw = dc.getTextWidthInPixels(d.toString(), f);
        if (dw > widest) {
            widest = dw;
        }
    }
    return widest;
}

// Text fonts for the number, largest first: FONT_LARGE, FONT_MEDIUM,
// FONT_SMALL, FONT_TINY, FONT_XTINY. The number fonts were tried and looked
// wrong on fr955. Not an array (as a global it was built when the app
// started and stayed on the heap of the data field): the values of
// Graphics.FONT_* run in that order from FONT_LARGE (4) down to FONT_XTINY
// (0), so the font at index i is FONT_LARGE - i.
const PICKER_FONT_COUNT = 5;

// Fonts for the label, largest first: FONT_SYSTEM_SMALL, FONT_SYSTEM_TINY,
// FONT_SYSTEM_XTINY (the system faces are lighter than FONT_XTINY, which is
// bold on fr955), then FONT_XTINY as the last resort. The font at index i
// is FONT_SYSTEM_SMALL - i (values 11 to 9), the last one FONT_XTINY (0).
const TITLE_FONT_COUNT = 4;

// The number being entered and how it is drawn: shared by the delegate,
// the title, the factory and the rows, and pointing at none of them.
class DigitEntry {

    var length as Number;
    var digits as Array<Number>;
    var count as Number = 0;
    // Index of the column that currently stands for 0 (see digitAt).
    var base as Number = 0;
    // Font and cell width, chosen on the first draw for the phone number.
    var font as FontDefinition = Graphics.FONT_XTINY;
    var cell as Number = 0;
    // True when the entry is too narrow for the whole number: it shows
    // only the candidate and the title shows the number.
    var narrow as Boolean = false;

    function initialize(length as Number) {
        self.length = length;
        digits = new Array<Number>[length];
    }

    // The digit a column index stands for. The Picker keeps its own index
    // and ignores new :defaults, so to start every digit from 0 the column
    // is rotated instead: the index just accepted becomes the base and
    // shows 0 from then on. The column wraps around, so every digit stays
    // one to nine steps away.
    function digitAt(index as Number) as Number {
        return (index - base + 10) % 10;
    }

    // Appends the accepted digit and makes its index stand for 0.
    function append(digit as Number) as Void {
        if (count < length) {
            digits[count] = digit;
            count++;
        }
        base = (base + digit) % 10;
    }

    function toString() as String {
        var s = "";
        for (var i = 0; i < count; i++) {
            s += digits[i].toString();
        }
        return s;
    }

    // Picks the largest font whose cells for the phone number fit the
    // entry area; done once, on the first draw. Where none does (entries
    // of 30 to 120 px on 57 watches, 65 px on fr245), the entry is narrow:
    // the largest font for the candidate alone; failing that, the smallest
    // font.
    function fitFont(dc as Dc, w as Number, h as Number) as Void {
        if (cell > 0) {
            return;
        }
        var digitFont = null as FontDefinition?;
        var digitCell = 0;
        for (var i = 0; i < PICKER_FONT_COUNT; i++) {
            font = (Graphics.FONT_LARGE - i) as FontDefinition;
            cell = widestDigit(dc, font);
            if (dc.getFontHeight(font) > h) {
                continue;
            }
            if (numberWidth(PickupData.PHONE_LEN, cell) + 2 <= w) {
                return;
            }
            if (digitFont == null && cell + 2 <= w) {
                digitFont = font;
                digitCell = cell;
            }
        }
        // The title may have been drawn already, with the label alone.
        narrow = true;
        WatchUi.requestUpdate();
        if (digitFont != null) {
            font = digitFont;
            cell = digitCell;
        }
    }

    // Left x of the cell at a position, from the start of the number:
    // cells as wide as the widest digit (size), a third of that between
    // groups.
    function cellX(pos as Number, size as Number) as Number {
        return pos * size + (pos / PickupData.GROUP) * (size / 3);
    }

    // Width of the number in cells of the given size, for the sizing
    // length or the real one.
    function numberWidth(len as Number, size as Number) as Number {
        return cellX(len - 1, size) + size;
    }

    // Draws the number with its first cell at x0: the digits entered, the
    // candidate inverted at the current position, underscores for the
    // rest. Without a candidate (-1, in the title) the current position is
    // an underscore in a frame.
    function drawNumber(dc as Dc, x0 as Number, y as Number, f as FontDefinition,
            size as Number, candidate as Number) as Void {
        for (var pos = 0; pos < length; pos++) {
            var x = x0 + cellX(pos, size);
            if (pos == count && candidate >= 0) {
                drawCandidate(dc, x, y, f, size, candidate);
                continue;
            }
            dc.setColor(PICKER_FG, Graphics.COLOR_TRANSPARENT);
            if (pos < count) {
                dc.drawText(x + size / 2, y, f, digits[pos].toString(),
                    Graphics.TEXT_JUSTIFY_CENTER);
            } else {
                if (pos == count) {
                    dc.drawRoundedRectangle(x - 1, y, size + 2, dc.getFontHeight(f), 3);
                }
                dc.drawText(x + size / 2, y, f, "_", Graphics.TEXT_JUSTIFY_CENTER);
            }
        }
    }

    // The candidate digit in the cell at x, inverted.
    function drawCandidate(dc as Dc, x as Number, y as Number, f as FontDefinition,
            size as Number, digit as Number) as Void {
        dc.setColor(PICKER_FG, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - 1, y, size + 2, dc.getFontHeight(f), 3);
        dc.setColor(PICKER_BG, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + size / 2, y, f, digit.toString(), Graphics.TEXT_JUSTIFY_CENTER);
    }
}

// The label, as in the custom editor on main: with a thin muted rule
// under it, in the largest label font that fits the title area the Picker
// assigns, at the bottom of that area: on many round watches (fr245:
// 240x66 px from the top of the screen) the top of it is cut by the bezel.
// The rule can only run across that area, not edge to edge. The text is in
// the plain foreground colour: grey is dithered on MIP screens and reads
// as smudged at this size.
//
// While the entry shows only the candidate, the title shows the whole
// number instead of the label: at the bottom of the area, in the largest
// font that fits (the smallest when none does), with a frame at the
// current position. The underscores tell a code from a phone number, and
// the label was on the menu item just tapped.
//
// On the Instinct 2/2S/2X and Descent G1 (OCTAGON, see Screen.mc) the
// sub-window covers the right end of the area: everything here stays left
// of Screen.titleRight, past the rounded corner (CORNER_GAP), between _left
// and _left + w.
class MutedTitle extends WatchUi.Drawable {

    (:octagon)
    private const CORNER_GAP = 2;

    private var _text as String;
    private var _entry as DigitEntry;
    // Screen radius on a round watch, 0 on a rectangular one.
    private var _radius as Number = 0;
    (:octagon)
    private var _left as Number = 0;
    (:notOctagon)
    private const _left = 0;

    function initialize(text as String, entry as DigitEntry) {
        Drawable.initialize({});
        _text = text;
        _entry = entry;
        // No semi-octagon screen is round: no DeviceSettings there, a large
        // object (see digitPicker).
        if (!OCTAGON) {
            var settings = System.getDeviceSettings();
            if (settings.screenShape == System.SCREEN_SHAPE_ROUND) {
                _radius = settings.screenWidth / 2;
            }
        }
    }

    function draw(dc as Dc) as Void {
        fillBackground(dc);
        var w = dc.getWidth();
        var h = dc.getHeight();
        if (OCTAGON && (self has :clearOfSubWindow)) {
            w = self.clearOfSubWindow(w) as Number;
        }
        var entry = _entry;
        var font = Graphics.FONT_XTINY;
        // The entry is too narrow on every semi-octagon watch (OCTAGON):
        // the label is never drawn there.
        if (OCTAGON ? true : entry.narrow) {
            // Sized for the phone number, so the code shares its font.
            var size = 0;
            for (var i = 0; i < PICKER_FONT_COUNT; i++) {
                font = (Graphics.FONT_LARGE - i) as FontDefinition;
                size = widestDigit(dc, font);
                var fh = dc.getFontHeight(font);
                if (fh <= h && entry.numberWidth(PickupData.PHONE_LEN, size) + 2 <= widthAt(w, h - fh)) {
                    break;
                }
            }
            // OCTAGON ? ... : the main form, so that it costs other watches
            // nothing (the compiler does not drop "0 +").
            entry.drawNumber(dc,
                OCTAGON ? _left + (w - entry.numberWidth(entry.length, size)) / 2
                    : (w - entry.numberWidth(entry.length, size)) / 2,
                h - dc.getFontHeight(font), font, size, -1);
            return;
        }
        // "if (!OCTAGON)": the compiler drops the block on the semi-octagon
        // watches and leaves no test elsewhere; it does not drop code after
        // the return above, nor an else, under a condition folded to true.
        if (!OCTAGON) {
            for (var i = 0; i < TITLE_FONT_COUNT; i++) {
                font = (i < TITLE_FONT_COUNT - 1 ? Graphics.FONT_SYSTEM_SMALL - i
                    : Graphics.FONT_XTINY) as FontDefinition;
                if (dc.getFontHeight(font) + 3 <= h && dc.getTextWidthInPixels(_text, font) <= w) {
                    break;
                }
            }
            // Two pixels between the text and the rule on the last row.
            var top = h - dc.getFontHeight(font) - 3;
            dc.setColor(PICKER_FG, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, top < 0 ? 0 : top, font, _text, Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(PICKER_MUTED, Graphics.COLOR_TRANSPARENT);
            dc.drawLine(0, h - 1, w, h - 1);
        }
    }

    // The width of the area left of the sub-window, past the rounded
    // corner; sets _left.
    (:octagon)
    hidden function clearOfSubWindow(areaW as Number) as Number {
        var right = Screen.titleRight(areaW);
        _left = right < areaW ? CORNER_GAP : 0;
        return right - _left;
    }

    // The width of the area that the screen shows at a height within it.
    // The API does not give the position of the area; PICKER_TITLE_TOP,
    // generated from the device profiles (tools/gen-products.js), is its
    // top on the round watches whose number goes to the title (52 to 62 px
    // on epix 2 Pro, Approach S70 42 mm, Descent G2 and Mk3 43 mm) and 0
    // elsewhere, where it does start at the top edge (fr245, fenix 6).
    private function widthAt(w as Number, y as Number) as Number {
        var r = _radius;
        y += PICKER_TITLE_TOP;
        if (r == 0 || y >= r) {
            return w;
        }
        var dy = r - y;
        var chord = (2 * Math.sqrt(r * r - dy * dy)).toNumber();
        return chord < w ? chord : w;
    }
}

// The semi-octagon watches have no touch screen, so no signs (OCTAGON):
// only what digitPicker refers to.
(:octagon)
class SignDrawable extends EmptyDrawable {

    function initialize(plus as Boolean) {
        EmptyDrawable.initialize();
    }
}

// A + or - in the Picker's arrow area above or below the column: as large
// as the shorter side of a small area (16x8 px on fr955, so 8x8 there),
// three fifths of it in a large one (30x30 px on vivoactive 4). Drawn, not
// a glyph: the font's + and - came out small and faint.
(:notOctagon)
class SignDrawable extends WatchUi.Drawable {

    private var _plus as Boolean;

    function initialize(plus as Boolean) {
        Drawable.initialize({});
        _plus = plus;
    }

    function draw(dc as Dc) as Void {
        fillBackground(dc);
        var w = dc.getWidth();
        var h = dc.getHeight();
        var size = w < h ? w : h;
        if (size >= 16) {
            size = size * 3 / 5;
        }
        var thick = size / 5;
        if (thick < 2) {
            thick = 2;
        }
        // The stem can sit on the middle of the bar only when both have
        // the same parity (Venu X1: 27x19 px area, an 11 px sign with a
        // 2 px stem would lean half a pixel to the left).
        if ((size - thick) % 2 != 0) {
            size--;
        }
        var x = w / 2 - size / 2;
        var y = h / 2 - size / 2;
        var inset = (size - thick) / 2;
        dc.setColor(PICKER_FG, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(x, y + inset, size, thick);
        if (_plus) {
            dc.fillRectangle(x + inset, y, thick, size);
        }
    }
}

// One item of the column: the number so far with this item's digit as the
// candidate at the current position. Characters sit in fixed cells (as
// wide as the widest digit, a third of that for a group space) so the row
// does not shift as underscores turn into digits. In an entry too narrow
// for the whole number the row shows the candidate alone, centred: the
// title shows the number.
class DigitRow extends WatchUi.Drawable {

    private var _entry as DigitEntry;
    private var _index as Number;

    function initialize(entry as DigitEntry, index as Number) {
        Drawable.initialize({});
        _entry = entry;
        _index = index;
    }

    function draw(dc as Dc) as Void {
        fillBackground(dc);
        var entry = _entry;
        var w = dc.getWidth();
        var h = dc.getHeight();
        entry.fitFont(dc, w, h);
        var font = entry.font;
        var cell = entry.cell;
        var y = (h - dc.getFontHeight(font)) / 2;
        // Always narrow on the semi-octagon watches (see MutedTitle.draw).
        if (OCTAGON ? true : entry.narrow) {
            entry.drawCandidate(dc, (w - cell) / 2, y, font, cell, entry.digitAt(_index));
        } else if (!OCTAGON) {
            entry.drawNumber(dc, (w - entry.numberWidth(entry.length, cell)) / 2, y, font,
                cell, entry.digitAt(_index));
        }
    }
}

// The column: digits 0-9, each drawn by a DigitRow made when the Picker asks
// for it. The Picker asks only for the entry it shows (the selected one, one
// or two calls per step of the column) and drops the previous row at once,
// so one row lives at a time instead of ten. Not one shared row with a
// changing index: the Picker may hold several drawables, and they would all
// show the same digit.
class DigitFactory extends WatchUi.PickerFactory {

    private var _entry as DigitEntry;

    function initialize(entry as DigitEntry) {
        PickerFactory.initialize();
        _entry = entry;
    }

    function getSize() as Number {
        return 10;
    }

    function getValue(index as Number) as Object? {
        return _entry.digitAt(index);
    }

    function getDrawable(index as Number, selected as Boolean) as Drawable? {
        return new DigitRow(_entry, index);
    }
}

// Draws nothing: hides the Picker's "OK" confirm item, which with a single
// column would sit next to the digit all the time, and the arrows when the
// touch screen is off or the watch has Up and Down buttons. The area is
// left as the Picker painted it, not
// filled with PICKER_BG: on the watch both are black, and in the simulator
// a black patch next to the number would stand out for no reason.
class EmptyDrawable extends WatchUi.Drawable {

    function initialize() {
        Drawable.initialize({});
    }

    function draw(dc as Dc) as Void {
    }
}

// A picker that collects the digits of entry one at a time; it keeps no
// reference to the entry itself, the delegate updates it. A function, not a
// class of its own: a subclass of Picker with nothing but initialize cost
// its definition for no use.
function digitPicker(label as ResourceId, entry as DigitEntry) as WatchUi.Picker {
    // The tap zones get a + and - only on a touch-only watch. Not when
    // touch is turned off in the settings (isTouchScreen is false then),
    // and not on a watch with Up and Down buttons, which change the
    // digit anyway: on fr955 the signs fit only 8x8 px and are hard
    // to read.
    //
    // DeviceSettings is a large object and the memory peak of the app is
    // here, while the Picker is made. So it is not kept in a local (two
    // calls, each object gone at once), and the title, which reads it too,
    // is made first, before the other parts of the Picker exist. The
    // semi-octagon watches read none, and no label either: their title
    // never draws it.
    var signs = OCTAGON ? false : System.getDeviceSettings().isTouchScreen
        && (System.getDeviceSettings().inputButtons
            & (System.BUTTON_INPUT_UP | System.BUTTON_INPUT_DOWN)) == 0;
    var title = new MutedTitle(OCTAGON ? "" : WatchUi.loadResource(label) as String, entry);
    // One EmptyDrawable for every hidden item (three on a watch without
    // signs): it draws nothing, so it does not matter that the Picker gives
    // it the area of whichever item it laid out last.
    var empty = new EmptyDrawable();
    return new WatchUi.Picker({
        :title => title,
        :pattern => [new DigitFactory(entry)] as Array<PickerFactory>,
        :defaults => [0] as Array<Number>,
        :nextArrow => signs ? new SignDrawable(true) : empty,
        :previousArrow => signs ? new SignDrawable(false) : empty,
        :confirm => empty,
    });
}

// Feeds accepted digits to the entry; saves through the callback when the
// number is complete, pops without saving on cancel.
class DigitPickerDelegate extends WatchUi.PickerDelegate {

    private var _entry as DigitEntry;
    private var _onAccept as Method(digits as String) as Void;

    function initialize(entry as DigitEntry, onAccept as Method(digits as String) as Void) {
        PickerDelegate.initialize();
        _entry = entry;
        _onAccept = onAccept;
    }

    // Back drops the last digit, or leaves when there is none. The column
    // keeps whatever digit it shows: its index is not known here.
    function onCancel() as Boolean {
        var entry = _entry;
        if (entry.count == 0) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else {
            entry.count--;
            WatchUi.requestUpdate();
        }
        return true;
    }

    // Start appends the chosen digit and puts the column back on 0.
    function onAccept(values as Array) as Boolean {
        var entry = _entry;
        entry.append(values[0] as Number);
        if (entry.count >= entry.length) {
            _onAccept.invoke(entry.toString());
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        } else {
            WatchUi.requestUpdate();
        }
        return true;
    }
}
