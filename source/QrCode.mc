import Toybox.Lang;
import Toybox.StringUtil;

// QR Code encoder for one fixed symbol: version 2 (25x25 modules), error
// correction level M, byte mode, up to 26 bytes of data. That is what the
// InPost app puts on the phone: "P|+48<phone>|<code>" is 21 bytes, and a
// decoder does not care which version or mask the app used. The mask is
// fixed (pattern 0) rather than chosen by penalty score, which keeps the
// code small; any mask decodes. The work is also kept short, because the
// watchdog of the older watches (FR 245, fenix 6: watchdogCount 120000 in
// the profiles, vivoactive 4 has 240000) tripped on a version that
// multiplied in GF(256) by shifting and told function patterns apart by a
// function call per module: now the log and exp tables are built on the fly
// (512 B, dropped afterwards) and the reserved modules are a bit mask per
// row. The result is one Number per row, bit c set = module (r, c) is dark.
// The watches with analog hands show no QR code (PickupCodeView.reload) and
// build the stub at the end instead (HANDS, see Screen.mc).
(:noHands)
module QrCode {
    const N = 25;
    const DATA_CW = 28;
    const EC_CW = 16;
    // Digit base of the numbers packed in PATTERNS (4 characters per row).
    const BASE = 85;
    const OFFSET = 35;
    // The dark modules of the fixed patterns (finder patterns, timing lines,
    // alignment pattern, dark module, format information of level M and
    // mask 0): 25 rows of 25 bits, bit c = module in column c, 4 characters
    // a row, base-85 digits with OFFSET added (tools/gen-qr-patterns.js).
    const PATTERNS = "Y4sK>bGjJ^>KJ^>KJ^AL>bDiYA%L####2B3^#######c#######c#######c####&=4-$h75%7Mb$h4u&=7K##$+##',###d##'N";

    function encode(text as String) as Array<Number> {
        var bytes = text.toUtf8Array();
        var len = bytes.size();
        var cw = new [DATA_CW + EC_CW] as Array<Number>;
        // Mode 0100, 8-bit count, data, 0000 terminator, then pad bytes:
        // after the first codeword each one holds the low nibble of one
        // value and the high nibble of the next.
        cw[0] = 0x40 | (len >> 4);
        var prev = len;
        for (var j = 1; j < DATA_CW; j++) {
            if (j <= len + 1) {
                var next = j <= len ? bytes[j - 1] : 0;
                cw[j] = ((prev & 0xF) << 4) | (next >> 4);
                prev = next;
            } else {
                cw[j] = ((j - len) % 2 == 0) ? 0xEC : 0x11;
            }
        }
        // GF(256) with polynomial 0x11D: exp and log tables.
        var exp = new [256]b;
        var log = new [256]b;
        var x = 1;
        for (var i = 0; i < 255; i++) {
            exp[i] = x;
            log[x] = i;
            x <<= 1;
            if ((x & 0x100) != 0) {
                x ^= 0x11D;
            }
        }
        // Reed-Solomon generator polynomial, the product of (x - alpha^i)
        // for i = 0..15, highest power first (g[0] is the leading 1). No
        // coefficient of the intermediate products is zero, so a lookup in
        // the log table is always valid.
        var gen = new [EC_CW + 1]b;
        gen[0] = 1;
        for (var i = 0; i < EC_CW; i++) {
            for (var j = i + 1; j > 0; j--) {
                gen[j] ^= exp[(log[gen[j - 1]] + i) % 255];
            }
        }
        for (var j = 0; j < EC_CW; j++) {
            cw[DATA_CW + j] = 0;
        }
        for (var i = 0; i < DATA_CW; i++) {
            var f = cw[i] ^ cw[DATA_CW];
            for (var j = 0; j < EC_CW - 1; j++) {
                cw[DATA_CW + j] = cw[DATA_CW + j + 1];
            }
            cw[DATA_CW + EC_CW - 1] = 0;
            if (f != 0) {
                var lf = log[f];
                for (var j = 0; j < EC_CW; j++) {
                    cw[DATA_CW + j] ^= exp[(log[gen[j + 1]] + lf) % 255];
                }
            }
        }

        // The symbol, starting with the fixed patterns, and per row the mask
        // of the modules reserved for them, which carry no data.
        var p = StringUtil.convertEncodedString(PATTERNS, {
            :fromRepresentation => StringUtil.REPRESENTATION_STRING_PLAIN_TEXT,
            :toRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY
        }) as ByteArray;
        var m = new [N] as Array<Number>;
        var res = new [N] as Array<Number>;
        for (var r = 0; r < N; r++) {
            var a = 0;
            for (var i = 0; i < 4; i++) {
                a = a * BASE + p[4 * r + i] - OFFSET;
            }
            m[r] = a;
            var bits = 1 << 6;
            if (r < 9) {
                bits |= 0x1FF | (0xFF << 17);
            } else if (r > 16) {
                bits |= 0x1FF;
            }
            if (r > 15 && r < 21) {
                bits |= 0x1F << 16;
            }
            res[r] = r == 6 ? 0x1FFFFFF : bits;
        }
        // Data bits zigzag up and down in two-module columns, skipping the
        // timing column; remainder bits stay 0. Mask 0: (r + c) even.
        var k = 0;
        var up = true;
        for (var col = N - 1; col > 0; col -= 2) {
            if (col == 6) {
                col = 5;
            }
            for (var i = 0; i < N; i++) {
                var r = up ? N - 1 - i : i;
                for (var dc = 0; dc < 2; dc++) {
                    var c = col - dc;
                    if (((res[r] >> c) & 1) == 0) {
                        var bit = 0;
                        if (k < 8 * (DATA_CW + EC_CW)) {
                            bit = (cw[k >> 3] >> (7 - (k & 7))) & 1;
                        }
                        k++;
                        if (bit == (r + c) % 2) {
                            m[r] |= 1 << c;
                        }
                    }
                }
            }
            up = !up;
        }
        return m;
    }
}

// The watches with analog hands: only what the code that is never run there
// refers to.
(:hands)
module QrCode {
    const N = 25;

    function encode(text as String) as Array<Number> {
        return [] as Array<Number>;
    }
}
