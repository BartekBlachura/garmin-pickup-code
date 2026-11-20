import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

// Full-screen field: for the InPost parcel locker the QR code of the stored
// values (QrCode), the white field around it being the quiet zone, and the
// code in a small font under the quiet zone where it fits in the circle (to
// type it in when the scanner fails); for any other locker, or while the
// code or the phone is not set, the code in the largest number font that
// fits with the phone number below. Smaller layouts show the code with a
// small label. Black on white for MIP readability in sunlight.
//
// The Instinct parts (OCTAGON, HANDS, :octagon, :hands) are built only for
// those watches; see Screen.mc.
//
// On round screens every text line is checked against the chord of the
// circle at that line's rows, taking into account where the field sits on
// the physical screen (from the obscurity flags). A field hanging from the
// top edge puts the phone in the narrow part and the code near the centre.
class PickupCodeView extends WatchUi.DataField {

    // Shown while no code is stored; number fonts have a "-" glyph.
    private const EMPTY_CODE = "------";

    // Cached from PickupData; see reload().
    var _code as String = "";
    private var _phone as String = "";
    // QR code of the stored values in the InPost format, null for any other
    // parcel locker and while the code or the phone is not set.
    private var _qr as Array<Number>? = null;
    // InPost pickup QR payload: "P|+48534941658|474624" (decoded from the
    // InPost app; qr.inpost.pl builds it from the same two values).
    private const QR_PREFIX = "P|+48";
    private const QR_SEPARATOR = "|";

    // Code fonts, largest first; the first one that fits the field is used:
    // numberThaiHot, numberHot, numberMedium, numberMild, large, medium,
    // small, xtiny. The text fonts LARGE and MEDIUM sit between the number
    // fonts and SMALL in size, which matters in quarter-screen fields
    // (vivoactive4s: 109 px wide, where NUMBER_MILD needs 107 px and LARGE
    // 88 px). Not an array, which cost 118 B of code to fill and its place
    // on the heap: the values of Graphics.FONT_* run in that order from
    // FONT_NUMBER_THAI_HOT (8) down to FONT_SMALL (2), so the font at index
    // i is FONT_NUMBER_THAI_HOT - i, and the last one FONT_XTINY (0;
    // FONT_TINY, 1, is not in the list).
    private const CODE_FONT_COUNT = 8;

    // Fonts for the second line, largest first, FONT_SMALL and FONT_XTINY:
    // the phone number on a full-screen field takes either, the "pickup
    // code" label in any smaller layout only the last one, LABEL_FONT. As
    // above, the font at index i is FONT_SMALL - 2 * i (values 2 and 0).
    const SECOND_FONT_COUNT = 2;

    private const LABEL_FONT = Graphics.FONT_XTINY;
    (:notOctagon)
    private const MIN_HEIGHT_FOR_LABEL = 170;
    // Full-screen fields down to the Instinct E 40mm (166 px) and the
    // Instinct 2S (156 px) have room for it.
    (:octagon)
    private const MIN_HEIGHT_FOR_LABEL = 150;
    private const EDGE_MARGIN = 3;
    // Digit glyphs occupy roughly the middle of the font line height; the
    // rows above and below are padding and may overlap the screen edge.
    private const GLYPH_INSET_DIV = 5;
    // On the semi-octagon screens the two cells of a row can differ by a
    // pixel (87/88 px on the Instinct 2). A line that fits one cell by less
    // than this is treated as not fitting, so both cells get the same font.
    // Elsewhere the label wraps as soon as it is wider than the field.
    (:octagon)
    private const CELL_TOLERANCE = 3;
    (:notOctagon)
    private const CELL_TOLERANCE = 0;
    // The digits of the number fonts start about this fraction of the line
    // height below its top (Instinct 2, from the .cft fonts: numberThaiHot
    // 56 px line, 7 px above the digits; numberHot 44 px, also 7 px, so
    // 2 px of SUB_GAP go there).
    private const CODE_TOP_DIV = 8;
    // Full screen with a sub-window: the digits start this far under the
    // ring around it (ScreenGeom.SUB_R, from the device image). With the
    // Instinct 2 model (a 3 px ring) it was 12 px, about 2 px under the ring
    // the image shows; 6 px there ran into it.
    private const SUB_GAP = 2;

    // Instinct Crossover and Crossover AMOLED (HANDS, see Screen.mc): the
    // analog hands rest at 9:15 over a data field, a bar across the middle
    // of the screen with a hub of radius 20 (176 px) or 21 (390 px,
    // `analogHands` in the profile). HANDS_R is half the height of what
    // they cover, HANDS_GAP how far they reach into the rows of fields that
    // end or start at the middle. The code on a full-screen field ends
    // 1/HANDS_CLEAR_DIV of the screen height above them: flush with them,
    // the hub cut into the bottom of the digits. Crossover AMOLED: the row
    // under a top field starts at HANDS_ROW_TOP of HANDS_ROW_REF px in
    // every such layout of the profile.
    (:hands)
    private const HANDS_R = 21;
    private const HANDS_GAP = 20;
    private const HANDS_CLEAR_DIV = 25;
    private const HANDS_ROW_TOP = 85;
    private const HANDS_ROW_REF = 390;

    var _round as Boolean = false;
    private var _screenW as Number = 0;
    private var _screenH as Number = 0;
    // Instinct geometry (see Screen), generated per watch (ScreenGeom):
    // constants rather than locals, because a data field's call stack is
    // small and fits() runs two calls deep under onUpdate with its many
    // locals (Stack Overflow on the Instinct), and rather than members
    // worked out at start, which cost the Instinct 2 memory it does not
    // have. _subR is 0 on a watch without a sub-window. On the other watches
    // the same names are constants of 0 (see Screen.mc).
    (:octagon)
    private const _subCx = ScreenGeom.SUB_CX;
    (:octagon)
    private const _subCy = ScreenGeom.SUB_CY;
    (:octagon)
    private const _subR = ScreenGeom.SUB_R;
    // Rows under the top field, by height (see onUpdate).
    (:octagon)
    private const _midH0 = ScreenGeom.MID_H0;
    (:octagon)
    private const _midY0 = ScreenGeom.MID_Y0;
    (:octagon)
    private const _midH1 = ScreenGeom.MID_H1;
    (:octagon)
    private const _midY1 = ScreenGeom.MID_Y1;
    (:notOctagon)
    private const _midH0 = 0;
    (:notOctagon)
    private const _midY0 = 0;
    (:notOctagon)
    private const _midH1 = 0;
    (:notOctagon)
    private const _midY1 = 0;
    (:notOctagon)
    private const _subCy = 0;
    (:notOctagon)
    private const _subR = 0;
    // Both Crossovers: the hands cover rows _handsTop to _handsBottom.
    (:hands)
    private var _handsTop as Number = 0;
    (:hands)
    private var _handsBottom as Number = 0;
    (:noHands)
    private const _handsTop = 0;
    (:noHands)
    private const _handsBottom = 0;
    // Semi-octagon screens: left and top of the QR code in the field, where
    // the device image shows the screen, and the centre of the code to its
    // right (tools/qr-layout.js); the other watches centre the QR code.
    (:octagon)
    private const QR_X = QrLayout.X;
    (:octagon)
    private const QR_Y = QrLayout.Y;
    (:octagon)
    private const QR_CODE_X = QrLayout.CX;
    (:notOctagon)
    private const QR_X = 0;
    (:notOctagon)
    private const QR_Y = 0;
    (:notOctagon)
    private const QR_CODE_X = 0;
    // Lines of the second line of text (see wrapLabel).
    private var _lines as Number = 1;

    function initialize() {
        DataField.initialize();
        var s = System.getDeviceSettings();
        _round = s.screenShape == System.SCREEN_SHAPE_ROUND;
        _screenW = s.screenWidth;
        _screenH = s.screenHeight;
        if (HANDS && (self has :initHands)) {
            self.initHands();
        }
        reload();
    }

    (:hands)
    hidden function initHands() as Void {
        _handsTop = _screenH / 2 - HANDS_R;
        _handsBottom = _screenH / 2 + HANDS_R;
    }

    function onShow() as Void {
        reload();
    }

    // Re-read the stored values (after on-device or phone settings changed).
    function reload() as Void {
        var code = PickupData.getCode();
        _code = code.length() > 0 ? code : EMPTY_CODE;
        var phone = PickupData.getPhone();
        _phone = phone.length() > 0
            ? (WatchUi.loadResource(Rez.Strings.PhonePrefix) as String) + " "
                + PickupData.groupDigits(phone)
            : "";
        // No QR code under analog hands (HANDS): they cross the middle of
        // the screen and a QR code cannot be split around them.
        _qr = HANDS ? null
            : (PickupData.isQr() && code.length() > 0 && phone.length() > 0)
                ? QrCode.encode(QR_PREFIX + phone + QR_SEPARATOR + code)
                : null;
    }

    // No compute(): the field shows static data, and DataField's own does
    // nothing (an empty one here cost its code and a place in the class).

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_WHITE);
        dc.clear();
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);

        var flags = getObscurityFlags();
        var atTop = (flags & OBSCURE_TOP) != 0;
        var atBottom = (flags & OBSCURE_BOTTOM) != 0;
        var atLeft = (flags & OBSCURE_LEFT) != 0;
        var atRight = (flags & OBSCURE_RIGHT) != 0;
        var offX = edgeOffset(atLeft, atRight, _screenW, w);
        // Crossover AMOLED: in every layout with a row of fields under the
        // top field the profile lets the top field run 12 to 39 px (6 Fields
        // B) into that row, which covers it. Its text must end where the
        // row starts. The Crossover's top fields (87 px) end at the hands.
        if (HANDS && atTop && !atBottom && h < _handsTop) {
            h = (_screenH * HANDS_ROW_TOP) / HANDS_ROW_REF;
        }

        // Vertical position on the screen. A field that touches neither the
        // top nor the bottom edge sits in one of the middle rows of its
        // layout; the flags do not say which. In the device profiles the
        // layouts are symmetric, middle rows share one height, rows are
        // 2 px apart and the top/bottom fields are at least 17% of the
        // screen. From that, the largest possible number of middle rows
        // gives the farthest the field can be from the centre; check every
        // line against both extremes. Fields of 30% or more are centred
        // (single middle row).
        var offYs = [edgeOffset(atTop, atBottom, _screenH, h)] as Array<Number>;
        if (OCTAGON && !atTop && !atBottom) {
            // The semi-octagon layouts are not symmetric. A short field
            // without these flags is the strip at the bottom (110x27 at
            // y 149 on the Instinct 2, 5 Fields), which the middle-row
            // guess put at y 31, under the sub-window; it got no font. A
            // taller one is a row under the top field: its y, by its height,
            // is in ScreenGeom from the profile (Instinct 2: 65 px at y 56
            // in 4 Fields A, 76 px at y 72), as no rule found it (the bottom
            // of the sub-window put the 4 Fields A row 20 px too low, and
            // its label ran under the ring). Other heights: not above the
            // sub-window.
            offYs[0] = h * 10 < _screenH * 3 ? _screenH - h
                : h == _midH0 ? _midY0
                : h == _midH1 ? _midY1
                : (offYs[0] > _subCy + _subR ? offYs[0] : _subCy + _subR);
        } else if (!atTop && !atBottom && h * 10 < _screenH * 3) {
            var edgeMin = (_screenH * 17) / 100;
            var rows = (_screenH - 2 * edgeMin + 2) / (h + 2);
            if (rows >= 2) {
                var mid = (_screenH - h) / 2;
                var off = ((rows - 1) * (h + 2)) / 2;
                offYs = [mid - off, mid + off] as Array<Number>;
            }
        }

        // Full screen (the field touches every edge, or on rectangular
        // devices, which report no flags, has the full screen height:
        // venusq's single field is 220x240 on a 240x240 screen): label on
        // top, code, phone below. Any smaller layout: just the code with a
        // small "pickup code" label, no phone.
        var full = (atTop && atBottom && atLeft && atRight) || h >= _screenH;
        var group1 = _code.substring(0, 3) as String;
        var group2 = _code.substring(3, 6) as String;
        var qr = _qr;
        if (full && qr != null) {
            // Module size, and the code under the QR code in a small font
            // to type it in when the scanner fails (none where no font
            // fits): fixed per watch, or found at run time, depending on
            // the QrLayout the jungle picks (tools/qr-layout.js). On the
            // semi-octagon screens the module is in quarter pixels (see
            // drawQr) and the code goes right of the QR code in two lines,
            // "123" over "456", centred on QR_CODE_X, an ascent apart (as
            // drawSecond), in one of the code fonts.
            var lay = QrLayout.find(self, dc, w, h, offX, offYs[0]);
            drawQr(dc, qr, w, h, lay[0]);
            if (lay[1] >= 0) {
                // An index in the code fonts on the semi-octagons, in the
                // second-line fonts elsewhere.
                var font = (OCTAGON
                    ? (lay[1] < CODE_FONT_COUNT - 1 ? Graphics.FONT_NUMBER_THAI_HOT - lay[1]
                        : Graphics.FONT_XTINY)
                    : Graphics.FONT_SMALL - 2 * lay[1]) as FontDefinition;
                if (OCTAGON) {
                    dc.drawText(QR_CODE_X, lay[2], font, group1, Graphics.TEXT_JUSTIFY_CENTER);
                    dc.drawText(QR_CODE_X, lay[2] + Graphics.getFontAscent(font), font, group2,
                        Graphics.TEXT_JUSTIFY_CENTER);
                } else {
                    drawCode(dc, lineX(0, w, codeWidth(dc, group1, group2, font)), lay[2],
                        group1, group2, font);
                }
            }
            return;
        }
        var showLabel = full && h >= MIN_HEIGHT_FOR_LABEL;
        var labelH = showLabel ? dc.getFontHeight(LABEL_FONT) : 0;
        // The second line: the phone (none while it is not set), or the
        // label; a field too narrow for it shows the code alone. Its fonts
        // are the second-line fonts from this index: both for the phone, the last
        // one (LABEL_FONT) for the label.
        var second = wrapLabel(dc,
            full ? _phone : WatchUi.loadResource(Rez.Strings.CodeLabel) as String, w);
        var hasSecond = second.length() > 0;
        var firstSecondFont = full ? 0 : SECOND_FONT_COUNT - 1;

        // Order of the two lines. Full screen: phone under the code. Smaller
        // layouts: label above the code, and only when that does not fit in
        // the circle (a field at the bottom edge) label below the code.
        var orderCount = full ? 1 : 2;

        // Vertical start of a block of the given height: centred, or pushed
        // towards the screen centre when the field touches only one
        // horizontal edge.
        var pushDown = atTop && !atBottom;
        var pushUp = atBottom && !atTop;
        if (OCTAGON && full) {
            // Always centred: the Instinct E 40mm profile flags its single
            // field as top-left only.
            pushDown = false;
            pushUp = false;
        }

        // Horizontal alignment of the lines: 0 = centred in the field. A
        // column cell (cut by the circle on one side only) may instead
        // align to its inner edge, towards the screen centre, where the
        // circle is wider: 1 = left edge (right-hand cell), 2 = right edge
        // (left-hand cell). Centred is tried first and the inner alignment
        // is used only when it allows a larger code font.
        var inner = 0;
        if (!full) {
            if (atLeft && !atRight) {
                inner = 2;
            } else if (atRight && !atLeft) {
                inner = 1;
            }
        }
        var alignCount = inner == 0 ? 1 : 2;

        // Candidate A: two lines (code and second line stacked): code font
        // index (-1 while none fits), second font or null, block top, code
        // and second line y, alignment.
        var sCi = -1;
        var sFont = null as FontDefinition?;
        var sY = 0;
        var sCodeY = 0;
        var sSecondY = 0;
        var sAlign = 0;
        // Pass 0: code fonts from largest, each with the second line in its
        // fonts from largest. Pass 1: code fonts without the second line.
        for (var pass = hasSecond ? 0 : 1; pass < 2 && sCi < 0; pass++) {
            for (var ci = 0; ci < CODE_FONT_COUNT && sCi < 0; ci++) {
                var codeFont = (ci < CODE_FONT_COUNT - 1 ? Graphics.FONT_NUMBER_THAI_HOT - ci
                    : Graphics.FONT_XTINY) as FontDefinition;
                var codeH = dc.getFontHeight(codeFont);
                var codeW = codeWidth(dc, group1, group2, codeFont);

                var piEnd = pass == 0 ? SECOND_FONT_COUNT : firstSecondFont + 1;
                for (var pi = firstSecondFont; pi < piEnd && sCi < 0; pi++) {
                    var phoneFont = pass == 0
                        ? (Graphics.FONT_SMALL - 2 * pi) as FontDefinition : null;
                    // The label may be on two lines, drawn an ascent apart
                    // (see wrapLabel, drawSecond).
                    var phoneH = phoneFont != null
                        ? dc.getFontHeight(phoneFont)
                            + (_lines - 1) * Graphics.getFontAscent(phoneFont)
                        : 0;

                    var blockH = labelH + codeH + phoneH;
                    if (blockH > h) {
                        continue;
                    }
                    var y = blockStart(h, blockH, pushDown, pushUp);
                    if (HANDS && full) {
                        // Label and code above the hands, phone below them.
                        y = _handsTop - _screenH / HANDS_CLEAR_DIV
                            + codeH / GLYPH_INSET_DIV - codeH - labelH;
                    }
                    if (OCTAGON && full && _subR > 0) {
                        // Centred, the top of the digits ran into the
                        // sub-window: they start about 1/CODE_TOP_DIV of
                        // the line height down. Then the block goes just
                        // low enough for them to clear it, the label beside
                        // the window (see drawLabel); a block that does not
                        // fit like that tries the next font.
                        if (y + labelH < _subCy + _subR + SUB_GAP - codeH / CODE_TOP_DIV) {
                            y = _subCy + _subR + SUB_GAP - codeH / CODE_TOP_DIV - labelH;
                        }
                        if (y + blockH > h - EDGE_MARGIN) {
                            continue;
                        }
                    }
                    var firstY = y + labelH;
                    var phoneW = phoneFont != null
                        ? dc.getTextDimensions(second, phoneFont)[0] : 0;
                    for (var ai = 0; ai < alignCount && sCi < 0; ai++) {
                        var align = ai * inner;
                        for (var oi = 0; oi < orderCount; oi++) {
                            var secondFirst = oi + 1 < orderCount;
                            var codeY = secondFirst ? firstY + phoneH : firstY;
                            var phoneY = secondFirst ? firstY : firstY + codeH;
                            if (HANDS && full) {
                                phoneY = _handsBottom;
                            }
                            if (fitsAll(offX, offYs, codeY, codeH, codeW, w, align)
                                && (phoneFont == null
                                    || fitsAll(offX, offYs, phoneY, phoneH, phoneW, w, align))) {
                                sCi = ci;
                                sFont = phoneFont;
                                sY = y;
                                sCodeY = codeY;
                                sSecondY = phoneY;
                                sAlign = align;
                                break;
                            }
                        }
                    }
                }
            }
        }

        // Candidate B (smaller layouts only): the label on two lines beside
        // the code (see drawBeside, which draws it when it wins).
        if (!full && drawBeside(dc, offX, offYs, h, inner, pushDown, pushUp, sCi, sFont)) {
            return;
        }
        if (sCi >= 0) {
            var codeFont = (sCi < CODE_FONT_COUNT - 1 ? Graphics.FONT_NUMBER_THAI_HOT - sCi
                : Graphics.FONT_XTINY) as FontDefinition;
            if (showLabel) {
                if (OCTAGON) {
                    // In a helper: no more locals in onUpdate (see _subCx).
                    if (self has :drawLabel) {
                        self.drawLabel(dc, offX, offYs[0], sY, labelH, sAlign, w);
                    }
                } else {
                    var label = WatchUi.loadResource(Rez.Strings.CodeLabel) as String;
                    dc.drawText(lineX(sAlign, w, dc.getTextWidthInPixels(label, LABEL_FONT)),
                        sY, LABEL_FONT, label, Graphics.TEXT_JUSTIFY_LEFT);
                }
            }
            drawCode(dc, lineX(sAlign, w, codeWidth(dc, group1, group2, codeFont)),
                sCodeY, group1, group2, codeFont);
            if (sFont != null) {
                drawSecond(dc, sAlign, w, sSecondY, sFont, second);
            }
            return;
        }

        // Nothing fits (tiny field): draw the plain code and let it clip.
        dc.drawText(w / 2, h / 2, Graphics.FONT_XTINY, _code,
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    // The "pickup code" label above the code on a full-screen field. When
    // the centred label runs into the sub-window in the top right corner it
    // is centred in the room left of the window instead: from past the
    // rounded corner to the window's leftmost point (at the label's rows,
    // just under the window's centre, its edge is within 2 px of that).
    (:octagon)
    hidden function drawLabel(dc as Dc, offX as Number, offY as Number, y as Number,
            labelH as Number, align as Number, fieldW as Number) as Void {
        var label = WatchUi.loadResource(Rez.Strings.CodeLabel) as String;
        var labelW = dc.getTextWidthInPixels(label, LABEL_FONT);
        var x = lineX(align, fieldW, labelW);
        if (!fits(offX, offY + y, labelH, labelW, fieldW, align)) {
            x = EDGE_MARGIN + Screen.cornerInset(_screenH,
                offY + y + labelH / GLYPH_INSET_DIV);
            if (_subCx - _subR - EDGE_MARGIN - x > labelW) {
                x = (x + _subCx - _subR - EDGE_MARGIN - labelW) / 2;
            }
        }
        dc.drawText(x, y, LABEL_FONT, label, Graphics.TEXT_JUSTIFY_LEFT);
    }

    // The label of a smaller field on two lines ("Kod" over "odbioru") when
    // it is wider than the field: narrow but tall fields, such as the bottom
    // cells of 4 Fields B and 5 Fields on the Instinct 2 (87 px). Unchanged
    // otherwise (the phone on a full screen is narrower than the screen).
    // Sets _lines.
    hidden function wrapLabel(dc as Dc, text as String, fieldW as Number) as String {
        _lines = 1;
        var i = text.find(" ");
        if (i == null
                || dc.getTextWidthInPixels(text, LABEL_FONT)
                    <= fieldW - 2 * EDGE_MARGIN - CELL_TOLERANCE) {
            return text;
        }
        _lines = 2;
        return (text.substring(0, i) as String) + "\n"
            + (text.substring(i + 1, text.length()) as String);
    }

    // Candidate B: the label on two lines ("Kod" over "odbioru", an ascent
    // apart, centred on each other) left of the code, half a digit from it.
    // Narrower than on one line (as it was off the semi-octagons up to
    // v0.6), so the code gets a larger font: numberMedium instead of medium
    // in the middle field of 4 Fields A on the Instinct 2, numberMild
    // instead of large on the fenix 6S and the Forerunner 955 in many
    // layouts. The label comes first, as in candidate A: B wins over A
    // (code font sCi, second line sFont) with a larger code font, and in
    // any font when A has no label. The code line must fit as in onUpdate
    // (at every offset in offYs; one on the semi-octagons, which keeps
    // their call depth) and the label block too, at its own rows and x,
    // inside the field. Draws it and returns true when it wins. Few locals,
    // as in fits().
    hidden function drawBeside(dc as Dc, offX as Number, offYs as Array<Number>, h as Number,
            inner as Number, pushDown as Boolean, pushUp as Boolean, sCi as Number,
            sFont as FontDefinition?) as Boolean {
        // Always on two lines (no field is 0 px wide).
        var label = wrapLabel(dc, WatchUi.loadResource(Rez.Strings.CodeLabel) as String, 0);
        var lblW = dc.getTextDimensions(label, LABEL_FONT)[0];
        var lblH = dc.getFontHeight(LABEL_FONT) + Graphics.getFontAscent(LABEL_FONT);
        var w = dc.getWidth();
        // Fonts larger than A's, any when A has no label (sFont is null
        // then, also when nothing fits).
        if (sFont == null) {
            sCi = CODE_FONT_COUNT;
        }
        for (var ci = 0; ci < sCi && lblH <= h; ci++) {
            var font = (ci < CODE_FONT_COUNT - 1 ? Graphics.FONT_NUMBER_THAI_HOT - ci
                : Graphics.FONT_XTINY) as FontDefinition;
            var codeH = dc.getFontHeight(font);
            var y = blockStart(h, codeH, pushDown, pushUp);
            var ly = y + (codeH - lblH) / 2;
            ly = ly < 0 ? 0 : (ly > h - lblH ? h - lblH : ly);
            // The digit width; the code as codeWidth (bitmap fonts: the
            // groups are as wide as the whole code).
            var gap = dc.getTextWidthInPixels("0", font);
            var lineW = lblW + gap / 2 + dc.getTextWidthInPixels(_code, font) + gap / 3;
            for (var a = 0; a < 2; a += (inner == 0 ? 2 : 1)) {
                var x = lineX(a * inner, w, lineW);
                // Every offset in a loop here, not through fitsAll: one call
                // level more (onUpdate, drawBeside, fitsAll, fits) overflowed
                // the stack on the FR 955.
                var i = 0;
                while (codeH <= h && i < offYs.size()
                        && fits(offX, offYs[i] + y, codeH, lineW, w, a * inner)
                        && fits(offX + x - EDGE_MARGIN, offYs[i] + ly, lblH, lblW, w, 1)) {
                    i++;
                }
                if (i == offYs.size()) {
                    // Centred on x + lblW / 2: lineX in a field 2x + lblW wide.
                    drawSecond(dc, 0, 2 * x + lblW, ly, LABEL_FONT, label);
                    drawCode(dc, x + lblW + gap / 2, y, _code.substring(0, 3) as String,
                        _code.substring(3, 6) as String, font);
                    return true;
                }
            }
        }
        return false;
    }

    // The second line of candidate A (phone or label), each of its lines
    // centred on the block (the label may be on two, see wrapLabel). Two
    // lines go an ascent apart, not a font height as drawText puts them:
    // the font height leaves a gap of about a line between "Kod" and
    // "odbioru". align and fieldW are reused: no more locals.
    hidden function drawSecond(dc as Dc, align as Number, fieldW as Number, y as Number,
            font as FontDefinition, text as String) as Void {
        var tw = dc.getTextDimensions(text, font)[0];
        align = lineX(align, fieldW, tw) + tw / 2;
        fieldW = text.find("\n");
        if (fieldW == null) {
            dc.drawText(align, y, font, text, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        dc.drawText(align, y, font, text.substring(0, fieldW), Graphics.TEXT_JUSTIFY_CENTER);
        dc.drawText(align, y + Graphics.getFontAscent(font), font,
            text.substring(fieldW + 1, text.length()), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // The QR code centred in the field with modules of m pixels.
    // Consecutive dark modules of a row are one rectangle. On the
    // semi-octagon screens it sits at QR_X, QR_Y and m is in quarter pixels:
    // module i spans pixels i * m / 4 to (i + 1) * m / 4, so 3.5 px modules
    // alternate 3 and 4 px (decoders read that: the grid is found from the
    // finder and alignment patterns).
    private function drawQr(dc as Dc, qr as Array<Number>, w as Number, h as Number,
            m as Number) as Void {
        var x0 = OCTAGON ? QR_X : (w - m * QrCode.N) / 2;
        var y0 = OCTAGON ? QR_Y : (h - m * QrCode.N) / 2;
        for (var r = 0; r < QrCode.N; r++) {
            var bits = qr[r];
            var c = 0;
            while (bits != 0) {
                if ((bits & 1) == 1) {
                    var run = 1;
                    while (((bits >> run) & 1) == 1) {
                        run++;
                    }
                    dc.fillRectangle(OCTAGON ? x0 + c * m / 4 : x0 + c * m,
                        OCTAGON ? y0 + r * m / 4 : y0 + r * m,
                        OCTAGON ? (c + run) * m / 4 - c * m / 4 : run * m,
                        OCTAGON ? (r + 1) * m / 4 - r * m / 4 : m);
                    c += run;
                    bits >>= run;
                } else {
                    c++;
                    bits >>= 1;
                }
            }
        }
    }

    // Left x of a line of the given width in the field, for an alignment
    // (see onUpdate): 0 centred, 1 at the left edge, 2 at the right edge.
    private function lineX(align as Number, fieldW as Number, lineW as Number) as Number {
        if (align == 1) {
            return EDGE_MARGIN;
        }
        if (align == 2) {
            return fieldW - EDGE_MARGIN - lineW;
        }
        return (fieldW - lineW) / 2;
    }

    // Width of the two digit groups with the gap between them.
    function codeWidth(dc as Dc, group1 as String, group2 as String,
            font as FontDefinition) as Number {
        return dc.getTextWidthInPixels(group1, font)
            + dc.getTextWidthInPixels("0", font) / 3
            + dc.getTextWidthInPixels(group2, font);
    }

    // Draws the two digit groups starting at x.
    private function drawCode(dc as Dc, x as Number, y as Number, group1 as String,
            group2 as String, font as FontDefinition) as Void {
        var gap = dc.getTextWidthInPixels("0", font) / 3;
        dc.drawText(x, y, font, group1, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(x + dc.getTextWidthInPixels(group1, font) + gap, y, font, group2,
            Graphics.TEXT_JUSTIFY_LEFT);
    }

    private function blockStart(h as Number, blockH as Number, pushDown as Boolean,
            pushUp as Boolean) as Number {
        if (pushDown) {
            // The hands' gap only for a field that ends at them, not a top
            // field cut short above a row (see onUpdate).
            if (HANDS && h >= _handsTop) {
                return h - blockH - HANDS_GAP;
            }
            return h - blockH - EDGE_MARGIN;
        }
        if (pushUp) {
            if (HANDS) {
                return HANDS_GAP;
            }
            return EDGE_MARGIN;
        }
        return (h - blockH) / 2;
    }

    // Screen offset of a field along one axis, from which screen edges it
    // touches: at the low edge, at the high edge, or centred otherwise.
    private function edgeOffset(atLow as Boolean, atHigh as Boolean,
            screenSize as Number, fieldSize as Number) as Number {
        if (atHigh && !atLow) {
            return screenSize - fieldSize;
        }
        if (atLow == atHigh) {
            return (screenSize - fieldSize) / 2;
        }
        return 0;
    }

    // fits() for every candidate vertical offset of the field.
    private function fitsAll(offX as Number, offYs as Array<Number>, localY as Number,
            lineH as Number, lineW as Number, fieldW as Number, align as Number) as Boolean {
        for (var i = 0; i < offYs.size(); i++) {
            if (!fits(offX, offYs[i] + localY, lineH, lineW, fieldW, align)) {
                return false;
            }
        }
        return true;
    }

    // True when a text line of the given width, aligned in the field as
    // lineX() does and occupying screen rows [screenY, screenY + lineH),
    // lies inside the field width and, on a round screen, inside the circle
    // at the row farthest from the centre (ignoring the font padding rows).
    (:notOctagon)
    function fits(offX as Number, screenY as Number, lineH as Number,
            lineW as Number, fieldW as Number, align as Number) as Boolean {
        if (lineW > fieldW - 2 * EDGE_MARGIN) {
            return false;
        }
        if (!_round) {
            return true;
        }
        // Float arithmetic throughout: with integers the two columns of a
        // layout (centred at 64.5 and 195.5 on a 260 px screen) rounded
        // differently and could end up with different fonts.
        var r = _screenW / 2.0;
        var cx = _screenW / 2.0;
        var cy = _screenH / 2.0;
        var inset = lineH / GLYPH_INSET_DIV;
        var dTop = (screenY + inset - cy).abs();
        var dBottom = (screenY + lineH - inset - cy).abs();
        var d = dTop > dBottom ? dTop : dBottom;
        if (d >= r) {
            return false;
        }
        var half = Math.sqrt(r * r - d * d) - EDGE_MARGIN;
        var left = offX + (fieldW - lineW) / 2.0;
        if (align != 0) {
            left = offX + lineX(align, fieldW, lineW);
        }
        var right = left + lineW;
        var dLeft = (cx - left).abs();
        var dRight = (right - cx).abs();
        return (dLeft > dRight ? dLeft : dRight) <= half;
    }

    // fits() on the semi-octagon screens: inside the field width (less
    // CELL_TOLERANCE in a cell narrower than the screen), clear of the
    // rounded corners and of the sub-window in the top right corner. Few
    // locals on purpose (see _subCx): the stack is small here.
    (:octagon)
    function fits(offX as Number, screenY as Number, lineH as Number,
            lineW as Number, fieldW as Number, align as Number) as Boolean {
        var avail = fieldW - 2 * EDGE_MARGIN;
        if (fieldW < _screenW) {
            avail -= CELL_TOLERANCE;
        }
        if (lineW > avail) {
            return false;
        }
        var inset = lineH / GLYPH_INSET_DIV;
        // Float, as on round screens: the two cells of a row round alike.
        var left = offX + (fieldW - lineW) / 2.0;
        if (align != 0) {
            left = offX + lineX(align, fieldW, lineW);
        }
        var right = left + lineW;
        var top = screenY + inset;
        var bottom = screenY + lineH - inset;
        // Cut corners: the row farthest into the corner band, from the top
        // or bottom edge. Same geometry as Screen.cornerInset, inlined to
        // stay at this call depth.
        var d = top < _screenH / 2 ? top : _screenH - bottom;
        if (d < ScreenGeom.CORNER_C) {
            var ins = EDGE_MARGIN + (d <= 0 ? ScreenGeom.CORNER_C
                : ScreenGeom.CORNER_A - Math.sqrt((ScreenGeom.CORNER_R2
                    - (ScreenGeom.CORNER_A - d) * (ScreenGeom.CORNER_A - d)).toFloat()).toNumber());
            if (left < ins || right > _screenW - ins) {
                return false;
            }
        }
        // Sub-window in the top right corner.
        if (_subR > 0 && bottom > _subCy - _subR && top < _subCy + _subR) {
            d = bottom <= _subCy ? _subCy - bottom : (top >= _subCy ? top - _subCy : 0);
            if (right > _subCx - EDGE_MARGIN
                    - Math.sqrt((_subR * _subR - d * d).toFloat()).toNumber()) {
                return false;
            }
        }
        return true;
    }
}
