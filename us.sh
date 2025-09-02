```bash
#!/bin/bash
set -e

# Default mode: auto
MODE="auto"
if [ "$1" = "--manual" ]; then
    MODE="manual"
fi

# Detect OS type
if [ -f /etc/debian_version ]; then
    OS="debian"
    RELEASE=$(lsb_release -cs 2>/dev/null || echo "bookworm")
elif [ -f /etc/redhat-release ]; then
    OS="centos"
    RELEASE=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | cut -d. -f1)
else
    echo "Unsupported operating system!"
    exit 1
fi

# Install required tools
echo "Installing dependencies..."
if [ "$OS" = "debian" ]; then
    apt-get update || true
    apt-get install -y bc locales lsb-release
elif [ "$OS" = "centos" ]; then
    yum install -y bc glibc-langpack-zh
fi

# Define mirror sources
MIRRORS=(
    "mirrors.aliyun.com:Aliyun"
    "mirrors.tuna.tsinghua.edu.cn:Tsinghua"
    "mirrors.ustc.edu.cn:USTC"
    "mirrors.huaweicloud.com:HuaweiCloud"
    "mirrors.cloud.tencent.com:TencentCloud"
)

# Function: Test ping speed, return average latency (ms), or 9999 if failed
test_speed() {
    local host=$1
    local ping_result=$(ping -c 3 -W 1 "$host" 2>/dev/null | grep 'rtt min/avg/max/mdev' | awk -F '/' '{print $5}')
    if [ -z "$ping_result" ]; then
        echo 9999
    else
        echo "$ping_result"
    fi
}

# Function: Select fastest mirror
select_fastest() {
    echo "Testing mirror speeds..."
    local min_speed=9999
    local fastest_mirror=""
    for mirror in "${MIRRORS[@]}"; do
        host=$(echo "$mirror" | cut -d: -f1)
        label=$(echo "$mirror" | cut -d: -f2)
        speed=$(test_speed "$host")
        echo "$label: $speed ms"
        if [ "$speed" != "9999" ] && [ "$(echo "$speed < $min_speed" | bc -l)" = "1" ]; then
            min_speed=$speed
            fastest_mirror=$host
        fi
    done
    if [ -z "$fastest_mirror" ]; then
        echo "mirrors.aliyun.com"  # Default to Aliyun
    else
        echo "$fastest_mirror"
    fi
}

# Function: Manual mirror selection
select_manual() {
    echo "Select a mirror source:"
    for i in "${!MIRRORS[@]}"; do
        label=$(echo "${MIRRORS[$i]}" | cut -d: -f2)
        echo "$((i+1))) $label"
    done
    read -p "Enter number: " choice
    if [ "$choice" -ge 1 ] && [ "$choice" -le ${#MIRRORS[@]} ] 2>/dev/null; then
        echo "${MIRRORS[$((choice-1))]}" | cut -d: -f1
    else
        echo "Invalid choice, using default Aliyun."
        echo "mirrors.aliyun.com"
    fi
}

# Select mirror
if [ "$MODE" = "auto" ]; then
    SELECTED_MIRROR=$(select_fastest)
else
    SELECTED_MIRROR=$(select_manual)
fi
echo "Selected mirror: $SELECTED_MIRROR"

# Update source list
echo "Updating source to $SELECTED_MIRROR..."
if [ "$OS" = "debian" ]; then
    cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true
    cat > /etc/apt/sources.list << EOF
deb http://$SELECTED_MIRROR/debian $RELEASE main contrib non-free non-free-firmware
deb http://$SELECTED_MIRROR/debian $RELEASE-updates main contrib non-free non-free-firmware
deb http://$SELECTED_MIRROR/debian $RELEASE-backports main contrib non-free non-free-firmware
deb http://$SELECTED_MIRROR/debian-security $RELEASE-security main contrib non-free non-free-firmware
EOF
    apt-get update || { echo "Failed to update sources, check /etc/apt/sources.list"; exit 1; }
elif [ "$OS" = "centos" ]; then
    mkdir -p /etc/yum.repos.d/backup
    mv /etc/yum.repos.d/*.repo /etc/yum.repos.d/backup/ 2>/dev/null || true
    cat > /etc/yum.repos.d/CentOS-Base.repo << EOF
[base]
name=CentOS-\$releasever - Base - $SELECTED_MIRROR
baseurl=http://$SELECTED_MIRROR/centos/\$releasever/os/\$basearch/
gpgcheck=1
gpgkey=http://$SELECTED_MIRROR/centos/RPM-GPG-KEY-CentOS-Official

[updates]
name=CentOS-\$releasever - Updates - $SELECTED_MIRROR
baseurl=http://$SELECTED_MIRROR/centos/\$releasever/updates/\$basearch/
gpgcheck=1
gpgkey=http://$SELECTED_MIRROR/centos/RPM-GPG-KEY-CentOS-Official
EOF
    if [ "$RELEASE" = "7" ]; then
        sed -i 's/\$releasever/7/g' /etc/yum.repos.d/CentOS-Base.repo
    elif [ "$RELEASE" = "8" ]; then
        sed -i 's/\$releasever/8-stream/g' /etc/yum.repos.d/CentOS-Base.repo
    fi
    yum makecache || { echo "Failed to update sources, check /etc/yum.repos.d/CentOS-Base.repo"; exit 1; }
fi

# Set timezone to Asia/Shanghai
echo "Setting timezone to Asia/Shanghai..."
rm -f /etc/localtime
ln -s /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
if [ -f /etc/timezone ]; then
    echo "Asia/Shanghai" > /etc/timezone
fi
if command -v chronyd >/dev/null 2>&1; then
    chronyd -q 'pool ntp.aliyun.com iburst'
elif command -v ntpdate >/dev/null 2>&1; then
    ntpdate ntp.aliyun.com
fi

# Set system language to zh_CN.UTF-8
echo "Setting system language to zh_CN.UTF-8..."
if [ "$OS" = "debian" ]; then
    echo "zh_CN.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen zh_CN.UTF-8
    update-locale LANG=zh_CN.UTF-8
elif [ "$OS" = "centos" ]; then
    echo "LANG=zh_CN.UTF-8" > /etc/locale.conf
fi
export LANG=zh_CN.UTF-8

echo "Source update, timezone, and language setup completed!"
echo "Run 'source /etc/profile' or restart your terminal to apply the language settings."
```
