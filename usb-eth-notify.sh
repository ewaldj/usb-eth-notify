#!/bin/bash

# - - - - - - - - - - - - - - - - - - - - - - - -
# usb-eth-notify.sh  by ewald@jeitler.cc 2026 https://www.jeitler.guru 
# - - - - - - - - - - - - - - - - - - - - - - - -
# Monitors USB Ethernet adapters and broadcasts warnings to all active terminals if a USB 2.0 link is detected. 
# No warning is issued when a USB 3.0 connection is present. 
# 
# Compatible with all terminal emulators and GUI environments on Debian/Raspberry Pi OS:
# XFCE, GNOME, KDE Plasma, LXDE, Mate, Cinnamon, Budgie, Openbox, i3, and more.
# Supports xfce4-terminal, gnome-terminal, xterm, urxvt, Alacritty, Kitty, Konsole, tmux, screen, SSH sessions, and physical TTYs.
# Works on any systemd-based Linux distribution
# - - - - - - - - - - - - - - - - - - - - - - - -

version = '1.1'

DEVPATH="${DEVPATH:-}"

# --- Send message to all active terminals ---
notify_all() {
    local msg="$1"

    local devs=()

    # === PRIMARY METHOD: Scan all /dev/pts/* ===
    # This finds ALL active pseudo-terminals, including xfce4-terminal!
    for dev in /dev/pts/*; do
        if [[ -c "$dev" ]]; then
            devs+=("$dev")
        fi
    done

    # === Additionally search for physical TTYs ===
    for dev in /dev/tty{0..9}; do
        if [[ -c "$dev" ]]; then
            devs+=("$dev")
        fi
    done

    # === Fallback: From 'who' (for SSH sessions not visible in /dev/pts) ===
    if command -v who &>/dev/null; then
        while IFS= read -r line; do
            local dev
            dev=$(echo "$line" | grep -oP '(pts/\d+|tty\d*)' | head -1)
            if [[ -n "$dev" ]]; then
                devs+=("/dev/${dev}")
            fi
        done < <(who 2>/dev/null)
    fi

    # Remove duplicates
    devs=($(printf '%s\n' "${devs[@]}" | sort -u))

    if [[ ${#devs[@]} -eq 0 ]]; then
        return
    fi

    # Write each line individually with \r\n so it renders correctly
    # on any TTY/PTY regardless of current cursor position
    for dev in "${devs[@]}"; do
        {
            printf '\r\n'
            while IFS= read -r line; do
                printf '%s\r\n' "$line"
            done <<< "$msg"
            printf '\r\n'
        } > "$dev" 2>/dev/null || true
    done
}

# --- Check one adapter by its full /sys path USB2.0 warning only ---
check_adapter() {
    local syspath="$1"
    local speed vendor product name

    speed=$(cat "${syspath}/speed"       2>/dev/null)
    vendor=$(cat "${syspath}/idVendor"   2>/dev/null)
    product=$(cat "${syspath}/idProduct" 2>/dev/null)

    [[ -z "$speed" ]] && return 1

    # USB 2.0
    [[ "$speed" != "480" ]] && return 0

    name=$(lsusb -d "${vendor}:${product}" 2>/dev/null \
           | sed 's/^.*ID [0-9a-f:]*  *//' | head -1)
    [[ -z "$name" ]] && name="USB Ethernet Adapter (${vendor}:${product})"

    local tag line2 msg
    tag="[ WARNING - USB 2.0 low-speed mode; flip the USB-C connector or use a USB 3.0 port/adapter ]"
    line2="Adapter detected: ${name}"

    msg="${tag}
${line2}"

    notify_all "$msg"
    logger -t usb-eth-notify "${tag} ${line2}"
}

# --- Walk up sysfs tree to find the USB device node (has idVendor + speed) ---
find_usb_parent() {
    local dir="$1"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "${dir}/idVendor" && -f "${dir}/speed" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 1
}

# --- Find all currently connected USB Ethernet adapters ---
find_all_adapters() {
    local found=0
    while IFS= read -r netdir; do
        local usbdev
        usbdev=$(find_usb_parent "$(dirname "$netdir")")
        [[ -n "$usbdev" ]] || continue
        check_adapter "$usbdev" && found=1
    done < <(find /sys/devices -name "net" -type d -path "*/usb*" 2>/dev/null)
    return $((1 - found))
}

# --- Main ---
if [[ -n "$DEVPATH" ]]; then
    # Called by udev -- DEVPATH set as environment variable
    sleep 2
    SYSPATH="/sys${DEVPATH}"
    usbdev=$(find_usb_parent "$SYSPATH")
    if [[ -n "$usbdev" ]]; then
        check_adapter "$usbdev"
    else
        find_all_adapters
    fi
else
    # Called at boot or manually -- check all present adapters
    find_all_adapters
fi