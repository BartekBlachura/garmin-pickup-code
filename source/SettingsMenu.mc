import Toybox.Application.Properties;
import Toybox.Lang;
import Toybox.WatchUi;

// On-device settings (AppBase.getSettingsView): a three-item menu where two
// items open the system Picker (digitPicker) for the pickup code or the
// phone number, and the third (a toggle) turns the InPost QR code on or off;
// the watches with analog hands (HANDS) show no QR code and no toggle.

class SettingsMenu extends WatchUi.Menu2 {

    function initialize() {
        Menu2.initialize({:title => WatchUi.loadResource(Rez.Strings.AppName) as String});
        addItem(new WatchUi.MenuItem(Rez.Strings.CodeLabel, null, :code, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.PhoneLabel, null, :phone, null));
        // No QR code under analog hands (PickupCodeView.reload).
        if (!HANDS) {
            addItem(new WatchUi.ToggleMenuItem(Rez.Strings.QrLabel, null, :qr, PickupData.isQr(), null));
        }
        refresh();
    }

    // Show the current values as sub-labels.
    function refresh() as Void {
        setSubLabel(:code, PickupData.getCode());
        setSubLabel(:phone, PickupData.getPhone());
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
            // The item has already switched itself.
            Properties.setValue(PickupData.PROP_QR, (item as WatchUi.ToggleMenuItem).isEnabled());
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
