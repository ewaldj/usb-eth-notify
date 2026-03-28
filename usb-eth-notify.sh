#!/bin/bash
# /usr/local/bin/usb-eth-check.sh
# Checks USB Ethernet adapters and broadcasts a warning to all active terminal sessions if an adapter is running in USB 2.0 mode
# Writes directly to all active PTYs/TTYs.

DEVPATH="${DEVPATH:-}"

# --- Send message to all active terminals ---
notify_all() {
    local msg="$1"

    # Collect all active PTY/TTY devices from 'who'
    # 'who' output varies in column position, so grep for pts/N or ttyN
    local devs=()
    while IFS= read -r line; do
        local dev
        dev=$(echo "$line" | grep -oP '(pts/\d+|tty\d*)' | head -1)
        [[ -z "$dev" ]] && continue
        dev="/dev/${dev}"
        [[ -c "$dev" ]] && devs+=("$dev")
    done < <(who)

    [[ ${#devs[@]} -eq 0 ]] && return

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

# # --- Check one adapter by its full /sys path with USB3.0 info ---
# check_adapter() {
#     local syspath="$1"
#     local speed vendor product name
# 
#     speed=$(cat "${syspath}/speed"       2>/dev/null)
#     vendor=$(cat "${syspath}/idVendor"   2>/dev/null)
#     product=$(cat "${syspath}/idProduct" 2>/dev/null)
# 
#     [[ -z "$speed" ]] && return 1
# 
#     name=$(lsusb -d "${vendor}:${product}" 2>/dev/null \
#            | sed 's/^.*ID [0-9a-f:]*  *//' | head -1)
#     [[ -z "$name" ]] && name="USB Ethernet Adapter (${vendor}:${product})"
# 
#     local tag line2 
# 
#     if [[ "$speed" == "5000" || "$speed" == "10000" || "$speed" == "20000" ]]; then
#         tag="[ OK – USB 3.0 high-speed mode ]"
#         line2="Adapter detected: ${name}"
#     elif [[ "$speed" == "480" ]]; then
#         tag="[ WARNING – USB 2.0 low‑speed mode; flip the USB‑C connector or use a USB 3.0 port/adapter ]"
#         line2="Adapter detected: ${name}"
#     else
#         tag="  [????]"
#         line2="Adapter detected: ${name}"
#     fi
# 
#     local msg
# msg="${tag}
# ${line2}"
# 
#     notify_all "$msg"
#     logger -t usb-eth-notify "${tag} ${line2}"
# }






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
