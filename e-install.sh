#!/usr/bin/env bash

# e-install.sh — installs usb-eth-notify from GitHub
# Usage:
# /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ewaldj/usb-eth-notify/refs/heads/main/e-install.sh)"

set -euo pipefail

readonly VERSION="1.1"
readonly REPO_RAW_BASE="https://raw.githubusercontent.com/ewaldj/usb-eth-notify/refs/heads/main"
readonly TARGET_SCRIPT="/usr/local/bin/usb-eth-notify.sh"
readonly RULES_FILE="/etc/udev/rules.d/99-usb-eth.rules"
readonly SERVICE_FILE="/etc/systemd/system/usb-eth-notify.service"

SUDO=""

print_line() {
    printf '%s\n' "------------------------------------------------------------"
}

print_title() {
    echo
    print_line
    printf '%s\n' "$1"
    print_line
}

require_root_or_sudo() {
    if [[ "${EUID}" -eq 0 ]]; then
        return
    fi

    if ! command -v sudo >/dev/null 2>&1; then
        echo "Error: root access is required and sudo is not installed."
        exit 1
    fi

    echo "Root access is required for installation."
    sudo -v
    SUDO="sudo"
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
    $SUDO install -m 0755 "$tmp_file" "$TARGET_SCRIPT"
    rm -f "$tmp_file"

    echo "✔ Script installed: $TARGET_SCRIPT"
}

create_udev_rule() {
    local tmp_file
    tmp_file="$(mktemp)"

    cat >"$tmp_file" <<'EOF'
# /etc/udev/rules.d/99-usb-eth.rules
# When a USB Ethernet adapter is connected, call the notification script.
#
# Triggers on USB network interfaces (subsystem "net", parent device is USB).

ACTION=="add", SUBSYSTEM=="net", \
    ATTRS{idVendor}=="?*", ATTRS{idProduct}=="?*", \
    ENV{DEVPATH}="%p", RUN+="/usr/local/bin/usb-eth-notify.sh"
EOF

    $SUDO install -m 0644 "$tmp_file" "$RULES_FILE"
    rm -f "$tmp_file"

    echo "✔ udev rule created: $RULES_FILE"
}


create_service() {
    local tmp_file
    tmp_file="$(mktemp)"

    cat >"$tmp_file" <<'EOF'
[Unit]
Description=Check USB Ethernet adapter USB version and notify users
# Start after getty/login manager so TTYs are available
After=getty.target multi-user.target systemd-user-sessions.service
Wants=multi-user.target

[Service]
Type=oneshot
# Wait briefly so the MOTD appears first, then show our message
ExecStartPre=/bin/sleep 3
ExecStart=/usr/local/bin/usb-eth-notify.sh
# Ignore errors if no adapter is present
SuccessExitStatus=0 1
RemainAfterExit=no
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    $SUDO install -m 0644 "$tmp_file" "$SERVICE_FILE"
    rm -f "$tmp_file"

    echo "✔ service file created: $SERVICE_FILE"
}

# 6. systemd-Service  activate & start 
systemctl daemon-reload
systemctl enable --now usb-eth-notify.service
echo "✔  systemd-Service aktiviert"


install_dependencies() {
    if ! command -v lsusb >/dev/null 2>&1; then
        echo "Installing usbutils (required for lsusb)..."
        $SUDO apt-get update
        $SUDO apt-get install -y usbutils
    fi
}

reload_udev() {
    $SUDO udevadm control --reload-rules
    $SUDO udevadm trigger
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

    require_root_or_sudo
    check_connectivity
    install_script
    create_udev_rule
    install_dependencies
    reload_udev
    finish_message
}

main "$@"