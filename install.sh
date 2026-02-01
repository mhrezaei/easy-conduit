#!/bin/bash

# ==============================================================================
# Project: Easy-Conduit (v1.1.0)
# Description: Automated deployment for Conduit Proxy with Smart Delayed Geo-fencing.
# Features: UFW Auto-config, 12h Vetting Grace Period, Resource Optimization.
# Supported OS: Ubuntu, Debian, CentOS, Fedora
# Licensed under MIT
# ==============================================================================

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- Logging Functions ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Privilege Check ---
if [ "$EUID" -ne 0 ]; then
    log_error "Please run as root (use sudo)."
    exit 1
fi

# --- 1. OS Detection ---
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
    else
        log_error "Unsupported OS. Could not find /etc/os-release."
        exit 1
    fi
}

# --- 2. Resource Management (Swap for stability) ---
setup_swap() {
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 1900 ]; then
        log_info "Memory is below 2GB ($TOTAL_RAM MB). Ensuring 2GB swap..."
        if [ ! -f /swapfile ]; then
            fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
            chmod 600 /swapfile
            mkswap /swapfile
            swapon /swapfile
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
            log_success "Swap allocated."
        fi
    fi
}

# --- 3. Interactive Prompts ---
ask_questions() {
    echo -e "${YELLOW}--- Easy-Conduit Configuration ---${NC}"
    
    echo -e "${BLUE}Note: If enabled, Geo-fencing will start AFTER 12 hours of uptime to allow network vetting.${NC}"
    read -p "Restrict to Iran IPs only? (y/n, default: y): " GEO_RESTRICT
    GEO_RESTRICT=${GEO_RESTRICT:-y}

    read -p "Max clients (default: 200): " MAX_CLIENTS
    MAX_CLIENTS=${MAX_CLIENTS:-200}

    read -p "Bandwidth limit Mbps (default: 5): " BANDWIDTH
    BANDWIDTH=${BANDWIDTH:-5}

    read -p "Port (default: 443): " CONDUIT_PORT
    CONDUIT_PORT=${CONDUIT_PORT:-443}

    # Save configuration for the firewall script
    mkdir -p /opt/conduit
    echo "$GEO_RESTRICT" > /opt/conduit/.geo_config
    date +%s > /opt/conduit/.install_time
}

# --- 4. Install Dependencies & Network Setup ---
install_deps() {
    log_info "Installing system dependencies and configuring firewall..."
    case "$OS" in
        ubuntu|debian)
            apt-get update && apt-get install -y curl iptables ipset iptables-persistent ca-certificates gnupg lsb-release ufw
            # Configure UFW if present and active
            if command -v ufw > /dev/null; then
                ufw allow 22/tcp # Safety first
                ufw allow "$CONDUIT_PORT"/tcp
                ufw allow "$CONDUIT_PORT"/udp
                log_info "UFW detected: Port $CONDUIT_PORT allowed (TCP/UDP)."
            fi

            if ! command -v docker &> /dev/null; then
                mkdir -p /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(ls_release -cs) stable" > /etc/apt/sources.list.d/docker.list
                apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            fi
            ;;
        centos|fedora|rhel)
            yum install -y curl iptables ipset iptables-services
            if ! command -v docker &> /dev/null; then
                yum install -y yum-utils
                yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
                yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
            fi
            ;;
    esac
    systemctl enable --now docker
}

# --- 5. Firewall Engine (Smart Geo-fencing with 12h Grace Period) ---
setup_firewall_script() {
    cat <<EOF > /usr/local/bin/conduit-fw-updater
#!/bin/bash
# Smart Firewall Logic for Easy-Conduit
IPSET_NAME="iran_ips"
TARGET_PORT="$CONDUIT_PORT"
INSTALL_TIME_FILE="/opt/conduit/.install_time"
CONFIG_FILE="/opt/conduit/.geo_config"

# Create/Refresh IPSet
ipset create \$IPSET_NAME hash:net -exist
ipset flush \$IPSET_NAME
curl -s https://www.ipdeny.com/ipblocks/data/countries/ir.zone >> /tmp/ir.list
curl -s https://raw.githubusercontent.com/herrbischoff/country-ip-blocks/master/ipv4/ir.cidr >> /tmp/ir.list
sort -u /tmp/ir.list | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$' | while read -r line; do
    ipset add \$IPSET_NAME "\$line" -exist
done
rm /tmp/ir.list

# Grace Period Logic (12 Hours = 43200 Seconds)
GEO_PREF=\$(cat \$CONFIG_FILE)
INSTALL_TIME=\$(cat \$INSTALL_TIME_FILE)
CURRENT_TIME=\$(date +%s)
ELAPSED=\$((CURRENT_TIME - INSTALL_TIME))
THRESHOLD=43200

if [ "\$GEO_PREF" == "y" ]; then
    if [ "\$ELAPSED" -gt "\$THRESHOLD" ]; then
        # Grace period ended, apply restriction
        iptables -D INPUT -p tcp --dport \$TARGET_PORT -m set ! --match-set \$IPSET_NAME src -j DROP 2>/dev/null
        iptables -D INPUT -p udp --dport \$TARGET_PORT -m set ! --match-set \$IPSET_NAME src -j DROP 2>/dev/null
        iptables -I INPUT -p tcp --dport \$TARGET_PORT -m set ! --match-set \$IPSET_NAME src -j DROP
        iptables -I INPUT -p udp --dport \$TARGET_PORT -m set ! --match-set \$IPSET_NAME src -j DROP
    else
        # Still in grace period for vetting
        REMAINING=\$(( (THRESHOLD - ELAPSED) / 60 ))
        iptables -D INPUT -p tcp --dport \$TARGET_PORT -m set ! --match-set \$IPSET_NAME src -j DROP 2>/dev/null
        iptables -D INPUT -p udp --dport \$TARGET_PORT -m set ! --match-set \$IPSET_NAME src -j DROP 2>/dev/null
        # Log to dmesg for troubleshooting if needed
        logger "Conduit: Still in Grace Period. \$REMAINING minutes left for vetting."
    fi
fi
EOF
    chmod +x /usr/local/bin/conduit-fw-updater
    /usr/local/bin/conduit-fw-updater
}

# --- 6. Docker Compose Setup ---
setup_conduit_docker() {
    log_info "Configuring Docker container..."
    mkdir -p /opt/conduit/data
    chmod -R 777 /opt/conduit/data
    
    cat <<EOF > /opt/conduit/docker-compose.yml
services:
  conduit-proxy:
    image: ghcr.io/ssmirr/conduit/conduit:2fd31d4
    container_name: conduit
    restart: unless-stopped
    network_mode: "host"
    user: root
    command:
      - start
      - --data-dir
      - /home/conduit/data
      - --max-clients
      - "$MAX_CLIENTS"
      - --bandwidth
      - "$BANDWIDTH"
    volumes:
      - /opt/conduit/data:/home/conduit/data
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
EOF
    cd /opt/conduit && docker compose up -d --force-recreate
}

# --- 7. Management CLI ---
setup_management_cli() {
    cat <<EOF > /usr/local/bin/conduit
#!/bin/bash
case "\$1" in
    status)
        docker ps -f name=conduit
        echo -e "\n--- Resource Usage ---"
        docker stats conduit --no-stream
        ;;
    logs)
        docker logs -f conduit
        ;;
    restart)
        cd /opt/conduit && docker compose restart
        /usr/local/bin/conduit-fw-updater
        echo "Service restarted."
        ;;
    update-ips)
        /usr/local/bin/conduit-fw-updater
        echo "IP list updated."
        ;;
    content)
        ls -lh /opt/conduit/data
        ;;
    uninstall)
        read -p "Are you sure you want to delete all data? (y/n): " confirm
        if [ "\$confirm" == "y" ]; then
            cd /opt/conduit && docker compose down
            rm -rf /opt/conduit /usr/local/bin/conduit /usr/local/bin/conduit-fw-updater
            echo "Conduit uninstalled."
        fi
        ;;
    help|*)
        echo -e "${GREEN}Easy-Conduit Manager Help${NC}"
        echo "Usage: conduit [command]"
        echo ""
        echo "Commands:"
        echo "  status      Check container health and stats"
        echo "  logs        View real-time traffic logs"
        echo "  restart     Restart service and refresh firewall"
        echo "  update-ips  Update IP lists and check grace period"
        echo "  content     View data directory content"
        echo "  uninstall   Remove everything from system"
        echo "  help        Show this help"
        ;;
esac
EOF
    chmod +x /usr/local/bin/conduit
}

# --- Execution Flow ---
detect_os
setup_swap
install_deps
ask_questions
setup_firewall_script
setup_conduit_docker
setup_management_cli

# Add Hourly Cronjob for Grace Period precision
(crontab -l 2>/dev/null | grep -v "conduit-fw-updater"; echo "0 * * * * /usr/local/bin/conduit-fw-updater > /dev/null 2>&1") | crontab -

log_success "Installation Finished. IMPORTANT: Geo-fencing (if selected) will activate in 12 hours."
echo -e "Use '${BLUE}conduit help${NC}' to manage your proxy."
