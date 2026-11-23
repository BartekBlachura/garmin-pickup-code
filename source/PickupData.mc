import Toybox.Application.Properties;
import Toybox.Lang;

// Stored values and their display formatting. Properties are the single
// source of truth: the on-device settings menu writes them and the phone
// app edits the same keys. Code and phone are strings. The phone app cannot enforce a
// minimum length, so a value counts only with exactly CODE_LEN or PHONE_LEN
// digits; anything else reads as not set, also a value stored as a number
// (v0.3.1 did; reading those cost 127 B on every watch). The settings menu
// writes the keys itself (Properties.setValue): a setter here for each cost
// more than the call.
module PickupData {

    const PROP_CODE = "code";
    const PROP_PHONE = "phone";
    const CODE_LEN = 6;
    const PHONE_LEN = 9;
    // Which QR code the full-screen field shows: QR_OFF (always text, for
    // lockers that take the code and phone typed in), QR_INPOST or
    // QR_ALLEGRO (Allegro One Box). The values are stored, and listed in
    // settings/phone/settings.xml, so do not renumber them.
    const PROP_QR_TYPE = "qrType";
    const QR_OFF = 0;
    const QR_INPOST = 1;
    const QR_ALLEGRO = 2;
    const QR_COUNT = 3;
    // Boolean of v1.0 (InPost QR on or off); read only by migrate().
    const PROP_QR = "qr";
    // Digits per group on screen: "123 456", "500 000 000".
    const GROUP = 3;

    // Digits only, or "" when not set.
    function getCode() as String {
        return exactly(digitsOf(Properties.getValue(PROP_CODE)), CODE_LEN);
    }

    function getPhone() as String {
        return exactly(digitsOf(Properties.getValue(PROP_PHONE)), PHONE_LEN);
    }

    // Off by default; a stored value outside 0..QR_COUNT-1 reads as off.
    function getQrType() as Number {
        var value = Properties.getValue(PROP_QR_TYPE);
        if (value instanceof Number && value >= 0 && value < QR_COUNT) {
            return value;
        }
        return QR_OFF;
    }

    // v1.0 stored the InPost QR code as a boolean `qr`; a stored true becomes
    // QR_INPOST and `qr` is cleared, so this runs once.
    function migrate() as Void {
        var value = Properties.getValue(PROP_QR);
        if (value instanceof Boolean && value) {
            Properties.setValue(PROP_QR_TYPE, QR_INPOST);
            Properties.setValue(PROP_QR, false);
        }
    }

    // The digits when there are exactly len of them, otherwise "".
    function exactly(digits as String, len as Number) as String {
        return digits.length() == len ? digits : "";
    }

    // "500000000" -> "500 000 000". Returns "" for "".
    function groupDigits(digits as String) as String {
        var out = "";
        var len = digits.length();
        for (var i = 0; i < len; i += GROUP) {
            if (i > 0) {
                out += " ";
            }
            var end = i + GROUP < len ? i + GROUP : len;
            out += digits.substring(i, end) as String;
        }
        return out;
    }

    // Keeps the ASCII digits of a stored string: "+48 500-000 000" ->
    // "48500000000". "" for anything that is not a string (not set).
    function digitsOf(value as Properties.ValueType) as String {
        if (!(value instanceof String)) {
            return "";
        }
        var chars = value.toCharArray();
        var out = "";
        for (var i = 0; i < chars.size(); i++) {
            var c = chars[i];
            if (c >= '0' && c <= '9') {
                out += c.toString();
            }
        }
        return out;
    }
}
