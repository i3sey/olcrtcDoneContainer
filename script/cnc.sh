#!/bin/bash

echo "ЕСЛИ У ВАС ЕСТЬ ПРОБЛЕМЫ - Я В КУРСЕ, ПРОЕКТ В БЕТЕ, ПО ПРОБЛЕМАМ В ЧАТ t.me/openlibrecommunity ИЛИ ВООБЩЕ НЕКУДА, ЖДИТЕ РЕЛИЗА"


set -e

CONTAINER_NAME="olcrtc-client"
IMAGE_NAME="${OLCRTC_IMAGE:-olcrtc:latest}"
IMAGE_ARCHIVE_URL_BASE="${OLCRTC_IMAGE_ARCHIVE_URL_BASE:-https://github.com/i3sey/olcrtcDoneContainer/releases/latest/download}"

SOCKS_IP="127.0.0.1"
SOCKS_PORT="8808"

while [[ $# -gt 0 ]]; do
    case $1 in
        --image=*)
            IMAGE_NAME="${1#*=}"
            shift
            ;;
        --image-archive-url-base=*)
            IMAGE_ARCHIVE_URL_BASE="${1#*=}"
            shift
            ;;
        --branch=*)
            echo "[!] --branch is deprecated; set OLCRTC_IMAGE or use --image instead"
            shift
            ;;
        *)
            shift
            ;;
    esac
done

echo "=== OlcRTC Client Deployment Script ==="
echo ""
echo "[*] Using image: $IMAGE_NAME"
echo ""

if ! command -v podman &> /dev/null; then
    echo "[!] Installing Podman..."

    if [ "$(id -u)" -eq 0 ]; then
        SUDO=""
    elif command -v sudo &> /dev/null; then
        SUDO="sudo"
    elif command -v doas &> /dev/null; then
        SUDO="doas"
    else
        echo "[X] No sudo/doas found and not running as root. Cannot install podman."
        exit 1
    fi

    if command -v apt &> /dev/null; then
        echo "[*] Detected apt (Debian/Ubuntu)"
        $SUDO apt update
        $SUDO apt install -y podman
    elif command -v dnf &> /dev/null; then
        echo "[*] Detected dnf (Fedora/RHEL)"
        $SUDO dnf install -y podman
    elif command -v yum &> /dev/null; then
        echo "[*] Detected yum (CentOS/RHEL)"
        $SUDO yum install -y podman
    elif command -v pacman &> /dev/null; then
        echo "[*] Detected pacman (Arch)"
        $SUDO pacman -Sy --noconfirm podman
    else
        echo "[X] Unsupported package manager. Install podman manually."
        exit 1
    fi
fi

echo "[+] Using Podman"
echo ""
echo "Select carrier:"
echo "  1) telemost"
echo "  2) jazz"
echo "  3) wbstream"
read -p "Enter choice [1-3, default: 1]: " CARRIER_CHOICE

case "$CARRIER_CHOICE" in
    2)
        CARRIER="jazz"
        ;;
    3)
        CARRIER="wbstream"
        ;;
    *)
        CARRIER="telemost"
        ;;
esac

echo "[*] Using carrier: $CARRIER"
echo ""

echo "Select transport:"
echo "  1) datachannel"
echo "  2) videochannel"
echo "  3) seichannel"
echo "  4) vp8channel"
read -p "Enter choice [1-4, default: 1]: " TRANSPORT_CHOICE

case "$TRANSPORT_CHOICE" in
    2)
        TRANSPORT="videochannel"
        ;;
    3)
        TRANSPORT="seichannel"
        ;;
    4)
        TRANSPORT="vp8channel"
        ;;
    *)
        TRANSPORT="datachannel"
        ;;
esac

echo "[*] Using transport: $TRANSPORT"
echo ""

if [ "$CARRIER" = "jazz" ]; then
    read -p "Enter Room ID (format: roomId:password from server): " ROOM_ID
else
    read -p "Enter Room ID: " ROOM_ID
fi

if [ -z "$ROOM_ID" ]; then
    echo "[X] Room ID cannot be empty"
    exit 1
fi

echo ""
read -p "Enter Encryption Key (hex): " KEY

if [ -z "$KEY" ]; then
    echo "[X] Encryption key cannot be empty"
    exit 1
fi

echo ""
read -p "DNS server [default: 1.1.1.1:53]: " DNS_INPUT
DNS=${DNS_INPUT:-1.1.1.1:53}

echo ""
read -p "SOCKS5 ip [default: 127.0.0.1]: " IP_INPUT
SOCKS_IP=${IP_INPUT:-127.0.0.1}

echo ""
read -p "SOCKS5 port [default: 8808]: " PORT_INPUT
SOCKS_PORT=${PORT_INPUT:-8808}

TRANSPORT_ARGS=()

if [ "$TRANSPORT" = "videochannel" ]; then
    echo ""
    echo "--- Videochannel settings ---"

    echo ""
    echo "Video codec:"
    echo "  1) qrcode"
    echo "  2) tile (requires 1080x1080)"
    read -p "Enter choice [1-2, default: 1]: " VCODEC_CHOICE

    case "$VCODEC_CHOICE" in
        2)
            VIDEO_CODEC="tile"
            VIDEO_W=1080
            VIDEO_H=1080
            echo "[*] Tile codec selected - forcing 1080x1080"

            read -p "Tile module size in pixels 1..270 [default: 4]: " VTILE_MOD_INPUT
            VIDEO_TILE_MODULE=${VTILE_MOD_INPUT:-4}

            read -p "Tile Reed-Solomon parity percent 0..200 [default: 20]: " VTILE_RS_INPUT
            VIDEO_TILE_RS=${VTILE_RS_INPUT:-20}

            TRANSPORT_ARGS+=(-video-tile-module "$VIDEO_TILE_MODULE" -video-tile-rs "$VIDEO_TILE_RS")
            ;;
        *)
            VIDEO_CODEC="qrcode"

            read -p "Video width [default: 1920]: " VW_INPUT
            VIDEO_W=${VW_INPUT:-1920}

            read -p "Video height [default: 1080]: " VH_INPUT
            VIDEO_H=${VH_INPUT:-1080}

            read -p "QR error correction (low/medium/high/highest) [default: low]: " VQREC_INPUT
            VIDEO_QR_RECOVERY=${VQREC_INPUT:-low}

            read -p "QR fragment size bytes [default: 0 (auto)]: " VQRSZ_INPUT
            VIDEO_QR_SIZE=${VQRSZ_INPUT:-0}

            if [ "$VIDEO_QR_SIZE" -gt 0 ]; then
                TRANSPORT_ARGS+=(-video-qr-size "$VIDEO_QR_SIZE")
            fi
            TRANSPORT_ARGS+=(-video-qr-recovery "$VIDEO_QR_RECOVERY")
            ;;
    esac

    read -p "Video FPS [default: 30]: " VFPS_INPUT
    VIDEO_FPS=${VFPS_INPUT:-30}

    read -p "Video bitrate [default: 2M]: " VBRT_INPUT
    VIDEO_BITRATE=${VBRT_INPUT:-2M}

    read -p "Hardware acceleration (none/nvenc) [default: none]: " VHW_INPUT
    VIDEO_HW=${VHW_INPUT:-none}

    TRANSPORT_ARGS+=(-video-w "$VIDEO_W" -video-h "$VIDEO_H" -video-fps "$VIDEO_FPS" \
        -video-bitrate "$VIDEO_BITRATE" -video-hw "$VIDEO_HW" -video-codec "$VIDEO_CODEC")
fi

if [ "$TRANSPORT" = "vp8channel" ]; then
    echo ""
    echo "--- VP8channel settings ---"

    read -p "VP8 FPS [default: 25]: " VP8FPS_INPUT
    VP8_FPS=${VP8FPS_INPUT:-25}

    read -p "VP8 batch size (frames per tick) [default: 1]: " VP8BATCH_INPUT
    VP8_BATCH=${VP8BATCH_INPUT:-1}

    TRANSPORT_ARGS+=(-vp8-fps "$VP8_FPS" -vp8-batch "$VP8_BATCH")
fi

echo ""
echo "[*] Stopping old instance..."
podman stop $CONTAINER_NAME 2>/dev/null || true
podman rm $CONTAINER_NAME 2>/dev/null || true

if [ -z "${OLCRTC_IMAGE:-}" ]; then
    ARCH="$(uname -m)"
    case "$ARCH" in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            echo "[X] Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac

    IMAGE_TAR="$(mktemp -t olcrtc-image-XXXXXX.tar)"

    echo "[*] Downloading prebuilt image for $ARCH..."
    if command -v curl &> /dev/null; then
        curl -fL --retry 3 --retry-delay 2 -o "$IMAGE_TAR" "$IMAGE_ARCHIVE_URL_BASE/olcrtc-$ARCH.tar"
    elif command -v wget &> /dev/null; then
        wget -O "$IMAGE_TAR" "$IMAGE_ARCHIVE_URL_BASE/olcrtc-$ARCH.tar"
    else
        echo "[X] Need curl or wget to download the prebuilt image"
        exit 1
    fi

    echo "[*] Loading image into Podman..."
    podman load -i "$IMAGE_TAR"
    rm -f "$IMAGE_TAR"
else
    echo "[*] Pulling image..."
    podman pull "$IMAGE_NAME"
fi

echo "[*] Starting OlcRTC client..."
podman run -d \
    --name $CONTAINER_NAME \
    --restart unless-stopped \
    -p $SOCKS_IP:$SOCKS_PORT:$SOCKS_PORT \
    $IMAGE_NAME \
    olcrtc -mode cnc -carrier "$CARRIER" -id "$ROOM_ID" -key "$KEY" \
        -link direct -transport "$TRANSPORT" -dns "$DNS" -data data \
        -socks-host 0.0.0.0 -socks-port "$SOCKS_PORT" "${TRANSPORT_ARGS[@]}"

sleep 2

echo ""
echo "[+] Client started successfully!"
echo ""
echo "Container name: $CONTAINER_NAME"
echo "Carrier:        $CARRIER"
echo "Transport:      $TRANSPORT"
echo "Room ID:        $ROOM_ID"
echo "SOCKS5 proxy:   $SOCKS_IP:$SOCKS_PORT"
echo ""
echo "View logs:"
echo "  podman logs -f $CONTAINER_NAME"
echo ""
echo "Stop client:"
echo "  podman stop $CONTAINER_NAME"
echo ""
echo "Test proxy:"
echo "  export all_proxy=socks5h://$SOCKS_IP:$SOCKS_PORT"
echo "  curl -fsSL https://ifconfig.me"
echo ""
