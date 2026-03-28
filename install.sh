#!/bin/bash
# install.sh — Installs USB Ethernet notification on Debian Trixie
# Run as root: sudo bash install.sh

set -e

echo "=== USB Ethernet Notification — Installation ==="

# 1. Install script
install -m 755 usb-eth-notify.sh /usr/local/bin/usb-eth-notify.sh
echo "✔ Script installed: /usr/local/bin/usb-eth-notify.sh"

# 2. Install udev rule
install -m 644 99-usb-eth.rules /etc/udev/rules.d/99-usb-eth.rules
echo "✔ udev rule installed: /etc/udev/rules.d/99-usb-eth.rules"

# 3. Check dependency (usbutils for lsusb)
if ! command -v lsusb &>/dev/null; then
    echo "Installing usbutils (required for lsusb)..."
    apt-get install -y usbutils
fi

# 5. Reload udev
udevadm control --reload-rules
udevadm trigger
echo "✔ udev rules reloaded"

echo ""
echo "=== Installation completed ==="
echo "    Test with: sudo /usr/local/bin/usb-eth-notify.sh"
echo "    Log:       journalctl -u usb-eth-check.service"
