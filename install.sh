#!/usr/bin/env bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

OS=`hostnamectl | grep -i system | cut -d: -f2`

V6_PROXY=""
IP=`curl -sL -4 ip.sb`
if [[ "$?" != "0" ]]; then
    IP=`curl -sL -6 ip.sb`
    V6_PROXY="https://gh.hijk.art/"
fi

CONFIG_FILE="/etc/v2ray/config.json"

cur_dir=$(pwd)

# check root
[[ $EUID -ne 0 ]] && echo -e "${red}错误：${plain} 必须使用root用户运行此脚本！\n" && exit 1

# check os
if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
else
    echo -e "${red}未检测到系统版本，请联系脚本作者！${plain}\n" && exit 1
fi

os_version=""

# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}请使用 CentOS 7 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}请使用 Ubuntu 16 或更高版本的系统！${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}请使用 Debian 8 或更高版本的系统！${plain}\n" && exit 1
    fi
fi

colorEcho() {
    echo -e "${1}${@:2}${PLAIN}"
}

checkSystem() {
    result=$(id | awk '{print $1}')
    if [ $result != "uid=0(root)" ]; then
        colorEcho $RED " 请以root身份执行该脚本"
        exit 1
    fi

    if [ ! -f /etc/centos-release ];then
        res=`which yum`
        if [ "$?" != "0" ]; then
            colorEcho $RED " 系统不是CentOS"
            exit 1
         fi
         res=`which systemctl`
         if [ "$?" != "0" ]; then
            colorEcho $RED " 系统版本过低，请重装系统到高版本后再使用本脚本！"
            exit 1
         fi
    else
        result=`cat /etc/centos-release|grep -oE "[0-9.]+"`
        main=${result%%.*}
        if [ $main -lt 7 ]; then
            colorEcho $RED " 不受支持的CentOS版本"
            exit 1
         fi
    fi
}

slogon() {
    clear
    echo "#############################################################"
    echo -e "#               ${RED}CentOS 7/8 V2ray一键安装脚本${PLAIN}                 #"
    echo -e "# ${GREEN}作者${PLAIN}: 网络跳越(hijk)                                      #"
    echo -e "# ${GREEN}网址${PLAIN}: https://hijk.art                                    #"
    echo -e "# ${GREEN}论坛${PLAIN}: https://hijk.club                                   #"
    echo -e "# ${GREEN}TG群${PLAIN}: https://t.me/hijkclub                               #"
    echo -e "# ${GREEN}Youtube频道${PLAIN}: https://youtube.com/channel/UCYTB--VsObzepVJtc9yvUxQ #"
    echo "#############################################################"
    echo ""
}

getData() {
    while true
    do
        read -p " 请输入v2ray的端口[1-65535]:" PORT
        [ -z "$PORT" ] && PORT="21568"
        if [ "${PORT:0:1}" = "0" ]; then
            echo -e " ${RED}端口不能以0开头${PLAIN}"
            exit 1
        fi
        expr $PORT + 0 &>/dev/null
        if [ $? -eq 0 ]; then
            if [ $PORT -ge 1 ] && [ $PORT -le 65535 ]; then
                echo ""
                colorEcho $BLUE " 端口号： $PORT"
                echo ""
                break
            else
                colorEcho $RED " 输入错误，端口号为1-65535的数字"
            fi
        else
            colorEcho $RED " 输入错误，端口号为1-65535的数字"
        fi
    done
}

preinstall() {
    colorEcho $BLUE " 更新系统..."
    yum clean all
    #yum update -y

    colorEcho $BLUE " 安装必要软件"
    yum install -y epel-release telnet wget vim net-tools ntpdate unzip
    res=`which wget`
    [ "$?" != "0" ] && yum install -y wget
    res=`which netstat`
    [ "$?" != "0" ] && yum install -y net-tools
    yum install -y nginx
    systemctl enable nginx && systemctl start nginx

    if [ -s /etc/selinux/config ] && grep 'SELINUX=enforcing' /etc/selinux/config; then
        sed -i 's/SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
        setenforce 0
    fi
}

installV2ray() {
    colorEcho $BLUE " 安装v2ray..."
    bash <(curl -sL ${V6_PROXY}https://raw.githubusercontent.com/hijkpw/scripts/master/goV2.sh)

    if [ ! -f $CONFIG_FILE ]; then
        colorEcho $RED " $OS 安装V2ray失败，请到 https://hijk.art 网站反馈"
        exit 1
    fi

    sed -i -e "s/port\":.*[0-9]*,/port\": ${PORT},/" $CONFIG_FILE
    alterid=`shuf -i50-80 -n1`
    sed -i -e "s/alterId\":.*[0-9]*/alterId\": ${alterid}/" $CONFIG_FILE
    uid=`grep id $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
    ntpdate -u time.nist.gov
    
    systemctl enable v2ray
    systemctl restart v2ray
    sleep 3
    res=`ss -ntlp| grep ${PORT} | grep v2ray`
    if [ "${res}" = "" ]; then
        colorEcho $RED " 端口号：${PORT}， v2启动失败，请检查端口是否被占用！"
        exit 1
    fi
    colorEcho $GREEN " v2ray安装成功！"
}

setFirewall() {
    systemctl status firewalld > /dev/null 2>&1
    if [[ $? -eq 0 ]];then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-port=${PORT}/tcp
        firewall-cmd --permanent --add-port=${PORT}/udp
        firewall-cmd --reload
    else
        nl=`iptables -nL | nl | grep FORWARD | awk '{print $1}'`
        if [[ "$nl" != "3" ]]; then
            iptables -I INPUT -p tcp --dport 80 -j ACCEPT
            iptables -I INPUT -p tcp --dport ${PORT} -j ACCEPT
            iptables -I INPUT -p udp --dport ${PORT} -j ACCEPT
        fi
    fi
}

installBBR() {
    result=$(lsmod | grep bbr)
    if [ "$result" != "" ]; then
        colorEcho $YELLOW " BBR模块已安装"
        INSTALL_BBR=false
        return;
    fi

    res=`hostnamectl | grep -i openvz`
    if [ "$res" != "" ]; then
        colorEcho $YELLOW " openvz机器，跳过安装"
        INSTALL_BBR=false
        return
    fi

    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    result=$(lsmod | grep bbr)
    if [[ "$result" != "" ]]; then
        colorEcho $GREEN " BBR模块已启用"
        INSTALL_BBR=false
        return
    fi

    colorEcho $BLUE " 安装BBR模块..."
    if [[ "$V6_PROXY" = "" ]]; then
        rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
        rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm
        yum --enablerepo=elrepo-kernel install kernel-ml -y
        grub2-set-default 0
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
        INSTALL_BBR=true
    fi
}

info() {
    if [ ! -f $CONFIG_FILE ]; then
        echo -e " ${RED}未安装v2ray!${PLAIN}"
        exit 1
    fi

    port=`grep port $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    res=`netstat -nltp | grep ${port} | grep v2ray`
    [ -z "$res" ] && status="${RED}已停止${PLAIN}" || status="${GREEN}正在运行${PLAIN}"
    uid=`grep id $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    alterid=`grep alterId $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    res=`grep network $CONFIG_FILE`
    [ -z "$res" ] && network="tcp" || network=`grep network $CONFIG_FILE| cut -d: -f2 | tr -d \",' '`
    security="auto"
    
    raw="{
  \"v\":\"2\",
  \"ps\":\"\",
  \"add\":\"$IP\",
  \"port\":\"${port}\",
  \"id\":\"${uid}\",
  \"aid\":\"$alterid\",
  \"net\":\"tcp\",
  \"type\":\"none\",
  \"host\":\"\",
  \"path\":\"\",
  \"tls\":\"\"
}"
    link=`echo -n ${raw} | base64 -w 0`
    link="vmess://${link}"

    echo ============================================
    echo -e " ${BLUE}v2ray运行状态：${PLAIN} ${status}"
    echo -e " ${BLUE}v2ray配置文件：${PLAIN} ${RED}$CONFIG_FILE${PLAIN}"
    echo ""
    echo -e " ${RED}v2ray配置信息：${PLAIN}               "
    echo -e "   ${BLUE}IP(address):${PLAIN}   ${RED}${IP}${PLAIN}"
    echo -e "   ${BLUE}端口(port)：${PLAIN} ${RED}${port}${PLAIN}"
    echo -e "   ${BLUE}id(uuid)：${PLAIN} ${RED}${uid}${PLAIN}"
    echo -e "   ${BLUE}额外id(alterid)：${PLAIN}  ${RED}${alterid}${PLAIN}"
    echo -e "   ${BLUE}加密方式(security)：${PLAIN}  ${RED}$security${PLAIN}"
    echo -e "   ${BLUE}传输协议(network)：${PLAIN}  ${RED}${network}${PLAIN}"
    echo
    echo -e " ${BLUE}vmess链接:${PLAIN}  $link"
}

bbrReboot() {
    if [ "$INSTALL_BBR" == "true" ]; then
        echo  
        colorEcho $BLUE " 为使BBR模块生效，系统将在30秒后重启"
        echo  
        echo -e " 您可以按 ctrl + c 取消重启，稍后输入 ${RED}reboot${PLAIN} 重启系统"
        sleep 30
        reboot
    fi
}

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install wget curl -y
    else
        apt install wget curl -y
    fi
}

install_v2ray() {
    echo -e "${green}开始安装or升级v2ray${plain}"
    bash <(curl -sL https://raw.githubusercontent.com/mxfade/v2Ray_ui/master/centos_install_v2ray.sh)
    if [[ $? -ne 0 ]]; then
        echo -e "${red}v2ray安装或升级失败，请检查错误信息${plain}"
        exit 1
    fi
    systemctl enable v2ray
    systemctl start v2ray
}

close_firewall() {
    if [[ x"${release}" == x"centos" ]]; then
        systemctl stop firewalld
        systemctl disable firewalld
    elif [[ x"${release}" == x"ubuntu" ]]; then
        ufw disable
    elif [[ x"${release}" == x"debian" ]]; then
        iptables -P INPUT ACCEPT
        iptables -P OUTPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -F
    fi
}

install_v2-ui() {
    systemctl stop v2-ui
    cd /usr/local/
    if [[ -e /usr/local/v2-ui/ ]]; then
        rm /usr/local/v2-ui/ -rf
    fi
    last_version=$(curl -Ls "https://api.github.com/repos/nbwxbo/v2-ui/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    echo -e "检测到v2-ui最新版本：${last_version}，开始安装"
    wget -N --no-check-certificate -O /usr/local/v2-ui-linux.tar.gz https://github.com/mxfade/v2Ray_ui/raw/master/v2-ui-linux.tar.gz
    if [[ $? -ne 0 ]]; then
        echo -e "${red}下载v2-ui失败，请确保你的服务器能够下载Github的文件，如果多次安装失败，请参考手动安装教程${plain}"
        exit 1
    fi
    tar zxvf v2-ui-linux.tar.gz
    rm v2-ui-linux.tar.gz -f
    cd v2-ui
    chmod +x v2-ui
    cp -f v2-ui.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable v2-ui
    systemctl start v2-ui
    echo -e "${green}v2-ui v${last_version}${plain} 安装完成，面板已启动，"
    echo -e ""
    echo -e "如果是全新安装，默认网页端口为 ${green}65432${plain}，用户名和密码默认都是 ${green}admin${plain}"
    echo -e "请自行确保此端口没有被其他程序占用，${yellow}并且确保 65432 端口已放行${plain}"
    echo -e ""
    echo -e "如果是更新面板，则按你之前的方式访问面板"
    echo -e ""
    curl -o /usr/bin/v2-ui -Ls https://raw.githubusercontent.com/mxfade/v2Ray_ui/master/v2-ui.sh
    chmod +x /usr/bin/v2-ui
    echo -e "v2-ui 管理脚本使用方法: "
    echo -e "----------------------------------------------"
    echo -e "v2-ui              - 显示管理菜单 (功能更多)"
    echo -e "v2-ui start        - 启动 v2-ui 面板"
    echo -e "v2-ui stop         - 停止 v2-ui 面板"
    echo -e "v2-ui restart      - 重启 v2-ui 面板"
    echo -e "v2-ui status       - 查看 v2-ui 状态"
    echo -e "v2-ui enable       - 设置 v2-ui 开机自启"
    echo -e "v2-ui disable      - 取消 v2-ui 开机自启"
    echo -e "v2-ui log          - 查看 v2-ui 日志"
    echo -e "v2-ui update       - 更新 v2-ui 面板"
    echo -e "v2-ui install      - 安装 v2-ui 面板"
    echo -e "v2-ui uninstall    - 卸载 v2-ui 面板"
    echo -e "----------------------------------------------"
}

echo -e "${green}开始安装${plain}"
install_base
echo -n "系统版本:  "
cat /etc/centos-release

checkSystem
getData
preinstall
installBBR
installV2ray
setFirewall
info
bbrReboot
install_v2-ui
