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
    // Whether the full-screen field shows the InPost QR code; off for other
    // parcel lockers, where the same code and phone are typed in.
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

    // Off by default; a stored value that is not a boolean reads as off.
    function isQr() as Boolean {
        var value = Properties.getValue(PROP_QR);
        return value instanceof Boolean ? value : false;
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
