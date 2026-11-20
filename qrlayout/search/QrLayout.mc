import Toybox.Graphics;
import Toybox.Lang;

// Where the full-screen field puts the QR code and the code under it, found
// at run time. monkey.jungle points the watches whose fonts tools/qr-layout.js
// cannot measure here (vector fonts), and every watch that has no fixed
// layout in qrlayout/fixed; the others have the result of this search as
// constants. When this changes, change tools/qr-layout.js too.
module QrLayout {
    // Module size: the 25 modules plus a module of margin on each side must
    // fit the square inscribed in a round screen, so that the finder
    // patterns in the corners keep some quiet zone from the bezel.
    const QR_DIV = QrCode.N + 2;
    // Quiet zone below the QR code that the code text keeps clear, in
    // modules: 3 instead of the 4 of the specification (decoders need
    // about one; the sides have 2-4 at the corners anyway, cut by the
    // circle). With 4, FR 55, the fenix 5 Plus family and Venu Sq had no
    // room for the code, and most 260 px watches only for xtiny. Where the
    // code fits under no font with QR_QUIET, QR_QUIET_MIN is tried before
    // the module shrinks (fenix 5 Plus: its xtiny is 26 px; Venu Sq 2:
    // module 10 instead of 9).
    const QR_QUIET = 3;
    const QR_QUIET_MIN = 2;
    // Smallest module the code text may shrink the QR code to: the size
    // of the 260 px MIP watches, which is already small for a scanner.
    const QR_MIN_MODULE = 6;

    // The module size of the QR code in pixels, the index of the code's font
    // in the second-line fonts of PickupCodeView (-1 where none fits) and the y of the
    // code. The code goes under the quiet zone, in the largest of the small
    // fonts that fits there inside the circle, to type it in when the
    // scanner fails. Where none fits, the quiet zone shrinks to
    // QR_QUIET_MIN, then the module by a pixel at a time down to
    // QR_MIN_MODULE until one does (Venu Sq: 8 -> 6); where none fits even
    // then, the QR keeps its full size without the code.
    function find(view as PickupCodeView, dc as Dc, w as Number, h as Number,
            offX as Number, offY as Number) as Array<Number> {
        var side = w < h ? w : h;
        if (view._round) {
            side = (side * 7071) / 10000;
        }
        var m = side / QR_DIV;
        var font = -1;
        var top = 0;
        var group1 = view._code.substring(0, 3) as String;
        var group2 = view._code.substring(3, 6) as String;
        for (var mm = m; font < 0 && (mm == m || mm >= QR_MIN_MODULE); mm--) {
            for (var q = QR_QUIET; font < 0 && q >= QR_QUIET_MIN; q--) {
                var t = (h - mm * QrCode.N) / 2 + mm * (QrCode.N + q);
                for (var i = 0; i < view.SECOND_FONT_COUNT && font < 0; i++) {
                    var f = (Graphics.FONT_SMALL - 2 * i) as FontDefinition;
                    var fontH = dc.getFontHeight(f);
                    var cw = view.codeWidth(dc, group1, group2, f);
                    if (t + fontH <= h && view.fits(offX, offY + t, fontH, cw, w, 0)) {
                        font = i;
                        top = t;
                        m = mm;
                    }
                }
            }
        }
        return [m, font, top] as Array<Number>;
    }
}
