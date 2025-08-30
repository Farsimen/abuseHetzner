#!/bin/bash

if [[ $EUID -ne 0 ]]; then
    echo "Run as root!"
    exit 1
fi

# وابستگی‌ها
apt update -y
apt install -y iptables iptables-persistent ipset curl jq  # jq برای پارس JSON

# منابع لیست‌ها (قابل تغییر در شخصی‌سازی)
ABUSE_LIST_URL="https://raw.githubusercontent.com/Kiya6955/Abuse-Defender/main/abuse-ips.ipv4"
IRAN_IP_LIST_URL="https://stat.ripe.net/data/country-resource-list/data.json?resource=IR"

# لاگ فایل با rotation
LOG_FILE="/var/log/improved-abuse-defender.log"
touch $LOG_FILE
echo "/var/log/improved-abuse-defender.log { weekly rotate 4 compress missingok }" > /etc/logrotate.d/improved-abuse-defender

main_menu() {
    clear
    echo "----- Improved Abuse Defender for Hetzner & Iran -----"
    echo "Version: 1.1 - With Full Menu"
    echo "-----------------------------------------------------"
    echo "1. Install & Block Abuse IPs (with Iran/Hetzner Whitelist)"
    echo "2. Whitelist IP/Range (Manual or Auto Iran)"
    echo "3. Block Custom IP/Range"
    echo "4. View Rules"
    echo "5. Customize (Change URLs or Add Whitelist)"
    echo "6. Test Rules (Temporary Apply)"
    echo "7. Disable Temporarily (Flush Rules)"
    echo "8. Clear All (Uninstall Rules)"
    echo "9. Exit"
    read -p "Choose: " choice
    case $choice in
        1) install_and_block ;;
        2) whitelist ;;
        3) block_custom ;;
        4) view_rules ;;
        5) customize ;;
        6) test_rules ;;
        7) disable_temp ;;
        8) clear_rules ;;
        9) exit 0 ;;
        *) main_menu ;;
    esac
}

create_sets() {
    ipset create abuse-set hash:net family inet || true
    ipset create whitelist-set hash:net family inet || true
    ipset create custom-block-set hash:net family inet || true

    iptables -N improved-abuse || true
    if ! iptables -C OUTPUT -j improved-abuse >/dev/null 2>&1; then
        iptables -I OUTPUT -j improved-abuse
    fi
    iptables -A improved-abuse -m set --match-set whitelist-set dst -j ACCEPT
    iptables -A improved-abuse -m set --match-set custom-block-set dst -j DROP
    iptables -A improved-abuse -m set --match-set abuse-set dst -j DROP
}

install_and_block() {
    clear
    create_sets
    read -p "Clear previous rules? [Y/N]: " clear
    [[ $clear =~ [Yy] ]] && ipset flush abuse-set

    IP_LIST=$(curl -s $ABUSE_LIST_URL)
    if [ -z "$IP_LIST" ]; then
        echo "Failed to fetch abuse list" | tee -a $LOG_FILE
        main_menu
    fi
    for IP in $IP_LIST; do
        ipset add abuse-set $IP 2>/dev/null || true
    done

    # Whitelist خودکار Hetzner (رنج نمونه)
    ipset add whitelist-set 168.119.0.0/16 || true
    ipset add whitelist-set 65.108.0.0/16 || true

    echo "$(date): Installed and blocked abuse IPs" >> $LOG_FILE
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
        IRAN_IPS=$(curl -s $IRAN_IP_LIST_URL | jq -r '.data.resources.ipv4[]')
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
    read -p "Press Enter to return" dummy
    main_menu
}

customize() {
    clear
    read -p "New Abuse List URL (current: $ABUSE_LIST_URL): " new_abuse
    [ ! -z "$new_abuse" ] && ABUSE_LIST_URL=$new_abuse

    read -p "New Iran IP List URL (current: $IRAN_IP_LIST_URL): " new_iran
    [ ! -z "$new_iran" ] && IRAN_IP_LIST_URL=$new_iran

    read -p "Add extra Whitelist IP/Range: " extra_ip
    [ ! -z "$extra_ip" ] && ipset add whitelist-set $extra_ip || true

    echo "$(date): Customized settings" >> $LOG_FILE
    iptables-save > /etc/iptables/rules.v4
    main_menu
}

test_rules() {
    clear
    echo "Testing rules temporarily..."
    install_and_block  # اعمال موقتی
    view_rules
    read -p "Revert changes? [Y/N]: " revert
    [[ $revert =~ [Yy] ]] && disable_temp
    main_menu
}

disable_temp() {
    clear
    ipset flush abuse-set
    ipset flush custom-block-set
    echo "$(date): Temporarily disabled" >> $LOG_FILE
    iptables-save > /etc/iptables/rules.v4
    main_menu
}

clear_rules() {
    clear
    ipset destroy abuse-set 2>/dev/null
    ipset destroy whitelist-set 2>/dev/null
    ipset destroy custom-block-set 2>/dev/null
    iptables -F improved-abuse 2>/dev/null
    iptables -D OUTPUT -j improved-abuse 2>/dev/null
    iptables -X improved-abuse 2>/dev/null
    crontab -l | grep -v "/root/improved-abuse-update.sh" | crontab -
    rm /root/improved-abuse-update.sh 2>/dev/null
    iptables-save > /etc/iptables/rules.v4
    echo "All cleared/uninstalled"
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
    (crontab -l 2>/dev/null; echo "0 0 * * * /root/improved-abuse-update.sh") | crontab -
}

main_menu
