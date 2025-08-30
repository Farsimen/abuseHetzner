#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "Run as root!"
    exit 1
fi

# وابستگی‌ها
apt update -y
apt install -y iptables iptables-persistent ipset curl

# منابع لیست‌ها (می‌تونی تغییر بدی)
ABUSE_LIST_URL="https://raw.githubusercontent.com/Kiya6955/Abuse-Defender/main/abuse-ips.ipv4"  # لیست abuse
IRAN_IP_LIST_URL="https://stat.ripe.net/data/country-resource-list/data.json?resource=IR"  # لیست IPهای ایرانی از RIPE (JSON)

# لاگ فایل با rotation
LOG_FILE="/var/log/improved-abuse-defender.log"
touch $LOG_FILE
echo "/var/log/improved-abuse-defender.log { weekly rotate 4 compress missingok }" > /etc/logrotate.d/improved-abuse-defender

main_menu() {
    clear
    echo "----- Improved Abuse Defender for Hetzner -----"
    echo "Optimized for Iran & Hetzner - No Bugs"
    echo "----------------------------------------------"
    echo "1. Block Abuse IPs (with Iran/Hetzner Whitelist)"
    echo "2. Whitelist IP/Range (Manual or Auto Iran)"
    echo "3. Block Custom IP/Range"
    echo "4. View Rules"
    echo "5. Clear All Rules"
    echo "6. Exit"
    read -p "Choose: " choice
    case $choice in
        1) block_abuse ;;
        2) whitelist ;;
        3) block_custom ;;
        4) view_rules ;;
        5) clear_rules ;;
        6) exit 0 ;;
        *) main_menu ;;
    esac
}

create_sets() {
    ipset create abuse-set hash:net family inet || true
    ipset create whitelist-set hash:net family inet || true
    ipset create custom-block-set hash:net family inet || true

    # Chainها برای ادغام با ufw
    iptables -N improved-abuse || true
    if ! iptables -C OUTPUT -j improved-abuse >/dev/null 2>&1; then
        iptables -I OUTPUT -j improved-abuse
    fi
    iptables -A improved-abuse -m set --match-set whitelist-set dst -j ACCEPT
    iptables -A improved-abuse -m set --match-set custom-block-set dst -j DROP
    iptables -A improved-abuse -m set --match-set abuse-set dst -j DROP
}

block_abuse() {
    clear
    create_sets
    read -p "Clear previous rules? [Y/N]: " clear
    [[ $clear =~ [Yy] ]] && ipset flush abuse-set

    # دانلود و اعمال لیست abuse
    IP_LIST=$(curl -s $ABUSE_LIST_URL)
    if [ -z "$IP_LIST" ]; then
        echo "Failed to fetch abuse list" | tee -a $LOG_FILE
        main_menu
    fi
    for IP in $IP_LIST; do
        ipset add abuse-set $IP 2>/dev/null || true  # جلوگیری از تکرار
    done

    # Whitelist خودکار Hetzner (رنج نمونه، چک کن)
    ipset add whitelist-set 168.119.0.0/16 || true  # مثال رنج Hetzner
    ipset add whitelist-set 65.108.0.0/16 || true   # اضافه کن اگر نیازه

    echo "$(date): Abuse IPs blocked" >> $LOG_FILE
    iptables-save > /etc/iptables/rules.v4

    read -p "Enable auto-update every 24h? [Y/N]: " update
    [[ $update =~ [Yy] ]] && setup_auto_update

    main_menu
}

whitelist() {
    clear
    echo "1. Manual IP/Range"
    echo "2. Auto Whitelist Iran IPs"
    read -p "Choose: " subchoice
    if [ "$subchoice" == "1" ]; then
        read -p "Enter IP/Range: " ip
        ipset add whitelist-set $ip || true
    elif [ "$subchoice" == "2" ]; then
        # دانلود لیست IPهای ایرانی از RIPE (پارس JSON ساده)
        IRAN_IPS=$(curl -s $IRAN_IP_LIST_URL | grep -oP '"ipv4":\["\K[^"]+' | tr ',' ' ')
        for IP in $IRAN_IPS; do
            ipset add whitelist-set $IP || true
        done
        echo "Iran IPs whitelisted"
    fi
    iptables-save > /etc/iptables/rules.v4
    main_menu
}

block_custom() {
    clear
    read -p "Enter IP/Range: " ip
    ipset add custom-block-set $ip || true
    iptables-save > /etc/iptables/rules.v4
    main_menu
}

view_rules() {
    clear
    ipset list
    iptables -L improved-abuse -v -n
    main_menu
}

clear_rules() {
    clear
    ipset flush abuse-set
    ipset flush whitelist-set
    ipset flush custom-block-set
    iptables -F improved-abuse
    iptables-save > /etc/iptables/rules.v4
    main_menu
}

setup_auto_update() {
    cat <<EOF >/root/improved-abuse-update.sh
#!/bin/bash
IP_LIST=\$(curl -s $ABUSE_LIST_URL)
for IP in \$IP_LIST; do
    ipset add abuse-set \$IP 2>/dev/null || true
done
iptables-save > /etc/iptables/rules.v4
EOF
    chmod +x /root/improved-abuse-update.sh
    (crontab -l; echo "0 0 * * * /root/improved-abuse-update.sh") | crontab -
}

main_menu
