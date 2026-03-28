#!/usr/bin/env bash

# e-install.sh — installs usb-eth-notify from GitHub
# Usage:
# /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ewaldj/usb-eth-notify/refs/heads/main/e-install.sh)"

set -euo pipefail

readonly VERSION="1.0"
readonly REPO_RAW_BASE="https://raw.githubusercontent.com/ewaldj/usb-eth-notify/refs/heads/main"
readonly TARGET_SCRIPT="/usr/local/bin/usb-eth-notify.sh"
readonly RULES_FILE="/etc/udev/rules.d/99-usb-eth.rules"

print_line() {
    printf '%s\n' "------------------------------------------------------------"
}

print_title() {
    echo
    print_line
    printf '%s\n' "$1"
    print_line
}

require_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        echo "This installer must be run as root."
        echo "Use:"
        echo "  sudo /bin/bash -c \"\$(curl -fsSL ${REPO_RAW_BASE}/e-install.sh)\""
        exit 1
    fi
}

check_connectivity() {
    if ! curl -fsSLI "${REPO_RAW_BASE}/usb-eth-notify.sh" >/dev/null; then
        echo "Error: unable to reach GitHub raw content."
        exit 1
    fi
}

install_script() {
    local tmp_file
    tmp_file="$(mktemp)"

    curl -fsSL "${REPO_RAW_BASE}/usb-eth-notify.sh" -o "$tmp_file"
    install -m 0755 "$tmp_file" "$TARGET_SCRIPT"
    rm -f "$tmp_file"

    echo "✔ Script installed: $TARGET_SCRIPT"
}

create_udev_rule() {
    cat >"$RULES_FILE" <<'EOF'
# /etc/udev/rules.d/99-usb-eth.rules
# When a USB Ethernet adapter is connected, call the notification script.
#
# Triggers on USB network interfaces (subsystem "net", parent device is USB).

ACTION=="add", SUBSYSTEM=="net", \
    ATTRS{idVendor}=="?*", ATTRS{idProduct}=="?*", \
    ENV{DEVPATH}="%p", RUN+="/usr/local/bin/usb-eth-notify.sh"
EOF

    chmod 0644 "$RULES_FILE"
    echo "✔ udev rule created: $RULES_FILE"
}

install_dependencies() {
    if ! command -v lsusb >/dev/null 2>&1; then
        echo "Installing usbutils (required for lsusb)..."
        apt-get update
        apt-get install -y usbutils
    fi
}

reload_udev() {
    udevadm control --reload-rules
    udevadm trigger
    echo "✔ udev rules reloaded"
}

finish_message() {
    echo
    echo "=== Installation completed ==="
    echo "Test with:"
    echo "  sudo /usr/local/bin/usb-eth-notify.sh"
    echo
    echo "Check logs with:"
    echo "  journalctl -t usb-eth-notify"
}

main() {
    print_title "USB Ethernet Notification Installer v${VERSION}"

    require_root
    check_connectivity
    install_script
    create_udev_rule
    install_dependencies
    reload_udev
    finish_message
}

main "$@"