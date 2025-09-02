```bash
#!/bin/bash
set -e

# 默认模式：auto
MODE="auto"
if [ "$1" = "--manual" ]; then
    MODE="manual"
fi

# 检测系统类型
if [ -f /etc/debian_version ]; then
    OS="debian"
    RELEASE=$(lsb_release -cs 2>/dev/null || echo "bookworm")
elif [ -f /etc/redhat-release ]; then
    OS="centos"
    RELEASE=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | cut -d. -f1)
else
    echo "不支持的操作系统！"
    exit 1
fi

# 安装必要的工具
if [ "$OS" = "debian" ]; then
    apt-get update || true
    apt-get install -y bc locales
elif [ "$OS" = "centos" ]; then
    yum install -y bc glibc-langpack-zh
fi

# 定义多个镜像源
MIRRORS=(
    "mirrors.aliyun.com:阿里云"
    "mirrors.tuna.tsinghua.edu.cn:清华源"
    "mirrors.ustc.edu.cn:中科大源"
    "mirrors.huaweicloud.com:华为云"
    "mirrors.cloud.tencent.com:腾讯云"
)

# 函数：测试 ping 速度，返回平均延迟（ms），失败返回9999
test_speed() {
    local host=$1
    local ping_result=$(ping -c 3 -W 1 "$host" 2>/dev/null | grep 'rtt min/avg/max/mdev' | awk -F '/' '{print $5}')
    if [ -z "$ping_result" ]; then
        echo 9999
    else
        echo "$ping_result"
    fi
}

# 自动选择最快的源
select_fastest() {
    echo "正在测试镜像源速度..."
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
        echo "mirrors.aliyun.com"  # 默认使用阿里云
    else
        echo "$fastest_mirror"
    fi
}

# 手动选择源
select_manual() {
    echo "请选择镜像源："
    for i in "${!MIRRORS[@]}"; do
        label=$(echo "${MIRRORS[$i]}" | cut -d: -f2)
        echo "$((i+1))) $label"
    done
    read -p "输入编号: " choice
    if [ "$choice" -ge 1 ] && [ "$choice" -le ${#MIRRORS[@]} ] 2>/dev/null; then
        echo "${MIRRORS[$((choice-1))]}" | cut -d: -f1
    else
        echo "无效选择，使用默认阿里云。"
        echo "mirrors.aliyun.com"
    fi
}

# 选择镜像
if [ "$MODE" = "auto" ]; then
    SELECTED_MIRROR=$(select_fastest)
else
    SELECTED_MIRROR=$(select_manual)
fi
echo "选择的镜像源: $SELECTED_MIRROR"

# 更换源
echo "正在更换为 $SELECTED_MIRROR 源..."
if [ "$OS" = "debian" ]; then
    cp /etc/apt/sources.list /etc/apt/sources.list.bak 2>/dev/null || true
    cat > /etc/apt/sources.list << EOF
deb http://$SELECTED_MIRROR/debian $RELEASE main contrib non-free non-free-firmware
deb http://$SELECTED_MIRROR/debian $RELEASE-updates main contrib non-free non-free-firmware
deb http://$SELECTED_MIRROR/debian $RELEASE-backports main contrib non-free non-free-firmware
deb http://$SELECTED_MIRROR/debian-security $RELEASE-security main contrib non-free non-free-firmware
EOF
    apt-get update || { echo "更新源失败，请检查 /etc/apt/sources.list"; exit 1; }
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
    yum makecache || { echo "更新源失败，请检查 /etc/yum.repos.d/CentOS-Base.repo"; exit 1; }
fi

# 修改时区为上海
echo "正在修改时区为 Asia/Shanghai..."
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

# 设置系统语言为中文
echo "正在设置系统语言为中文 (zh_CN.UTF-8)..."
if [ "$OS" = "debian" ]; then
    echo "zh_CN.UTF-8 UTF-8" > /etc/locale.gen
    locale-gen zh_CN.UTF-8
    update-locale LANG=zh_CN.UTF-8
elif [ "$OS" = "centos" ]; then
    echo "LANG=zh_CN.UTF-8" > /etc/locale.conf
fi
export LANG=zh_CN.UTF-8

echo "源更换、时区修改和语言设置完成！"
echo "请运行 'source /etc/profile' 或重启终端以应用语言环境。"
```
