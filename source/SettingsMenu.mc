import Toybox.Application.Properties;
import Toybox.Lang;
import Toybox.WatchUi;

// On-device settings (AppBase.getSettingsView): a three-item menu where two
// items open the system Picker (digitPicker) for the pickup code or the
// phone number, and the third cycles the QR code setting (off, InPost,
// Allegro One), its sub-label showing the current choice; the watches with
// analog hands (HANDS) show no QR code and no such item.

class SettingsMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => WatchUi.loadResource(Rez.Strings.AppName) as String});
        addItem(new WatchUi.MenuItem(Rez.Strings.CodeLabel, null, :code, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.PhoneLabel, null, :phone, null));
        // No QR code under analog hands (PickupCodeView.reload).
        if (!HANDS) {
            addItem(new WatchUi.MenuItem(Rez.Strings.QrLabel, null, :qr, null));
        }
        refresh();
    }

    // Show the current values as sub-labels.
    function refresh() as Void {
        setSubLabel(:code, PickupData.getCode());
        setSubLabel(:phone, PickupData.getPhone());
        if (!HANDS) {
            var qrType = PickupData.getQrType();
            var item = getItem(findItemById(:qr));
            if (item != null) {
                item.setSubLabel(WatchUi.loadResource(
                    qrType == PickupData.QR_INPOST ? Rez.Strings.QrInPost
                    : qrType == PickupData.QR_ALLEGRO ? Rez.Strings.QrAllegro
                    : Rez.Strings.QrOff) as String);
            }
        }
    }

    private function setSubLabel(id as Symbol, digits as String) as Void {
        var item = getItem(findItemById(id));
        if (item != null) {
            item.setSubLabel(digits.length() > 0
                ? PickupData.groupDigits(digits)
                : WatchUi.loadResource(Rez.Strings.NotSet) as String);
        }
    }
}

class SettingsMenuDelegate extends WatchUi.Menu2InputDelegate {

    private var _menu as SettingsMenu;

    function initialize(menu as SettingsMenu) {
        Menu2InputDelegate.initialize();
        _menu = menu;
    }

    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        if (id == :code) {
            edit(Rez.Strings.CodeLabel, PickupData.CODE_LEN, method(:onCode));
        } else if (id == :phone) {
            edit(Rez.Strings.PhoneLabel, PickupData.PHONE_LEN, method(:onPhone));
        } else if (id == :qr) {
            Properties.setValue(PickupData.PROP_QR_TYPE,
                (PickupData.getQrType() + 1) % PickupData.QR_COUNT);
            _menu.refresh();
        }
    }

    // Every edit starts from an empty number. The font is sized for the
    // phone number in both pickers, so the code is not drawn larger.
    private function edit(label as ResourceId, length as Number,
            onAccept as Method(digits as String) as Void) as Void {
        var entry = new DigitEntry(length);
        WatchUi.pushView(digitPicker(label, entry), new DigitPickerDelegate(entry, onAccept),
            WatchUi.SLIDE_LEFT);
    }

    function onCode(digits as String) as Void {
        Properties.setValue(PickupData.PROP_CODE, digits);
        _menu.refresh();
    }

    function onPhone(digits as String) as Void {
        Properties.setValue(PickupData.PROP_PHONE, digits);
        _menu.refresh();
    }
}
