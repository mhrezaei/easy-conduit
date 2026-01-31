#!/bin/bash

# ==============================================================================
# Project: Conduit One-Click Installer & Manager (V0.1.0 - Permissions Fix)
# Description: Automated deployment for Conduit Proxy with Geo-fencing.
# Supported OS: Ubuntu, Debian, CentOS, Fedora
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
        log_error "Unsupported OS."; exit 1
    fi
}

# --- 2. Resource Management ---
setup_swap() {
    TOTAL_RAM=$(free -m | awk '/^Mem:/{print $2}')
    if [ "$TOTAL_RAM" -lt 1900 ]; then
        log_info "Setting up 2GB Swap for stability..."
        if [ ! -f /swapfile ]; then
            fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
            chmod 600 /swapfile
            mkswap /swapfile
            swapon /swapfile
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
    fi
}

# --- 3. Interactive Prompts ---
ask_questions() {
    echo -e "${YELLOW}--- Conduit Configuration ---${NC}"
    read -p "Restrict to Iran IPs only? (y/n, default: y): " GEO_RESTRICT
    GEO_RESTRICT=${GEO_RESTRICT:-y}
    read -p "Max clients (default: 200): " MAX_CLIENTS
    MAX_CLIENTS=${MAX_CLIENTS:-200}
    read -p "Bandwidth limit Mbps (default: 5): " BANDWIDTH
    BANDWIDTH=${BANDWIDTH:-5}
    read -p "Port (default: 443): " CONDUIT_PORT
    CONDUIT_PORT=${CONDUIT_PORT:-443}
}

# --- 4. Install Dependencies ---
install_deps() {
    log_info "Installing dependencies..."
    case "$OS" in
        ubuntu|debian)
            apt-get update && apt-get install -y curl iptables ipset iptables-persistent ca-certificates gnupg lsb-release
            if ! command -v docker &> /dev/null; then
                mkdir -p /etc/apt/keyrings
                curl -fsSL https://download.docker.com/linux/$OS/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg --yes
                echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
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

# --- 5. Firewall Engine ---
setup_firewall_script() {
    cat <<EOF > /usr/local/bin/conduit-fw-updater
#!/bin/bash
IPSET_NAME="iran_ips"
TARGET_PORT="$CONDUIT_PORT"
ipset create \$IPSET_NAME hash:net -exist
ipset flush \$IPSET_NAME
curl -s https://www.ipdeny.com/ipblocks/data/countries/ir.zone >> /tmp/ir.list
curl -s https://raw.githubusercontent.com/herrbischoff/country-ip-blocks/master/ipv4/ir.cidr >> /tmp/ir.list
sort -u /tmp/ir.list | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}(/[0-9]{1,2})?$' | while read -r line; do
    ipset add \$IPSET_NAME "\$line" -exist
done
rm /tmp/ir.list
if [ "$GEO_RESTRICT" == "y" ]; then
    iptables -D INPUT -p tcp --dport \$TARGET_PORT -m set ! --match-set \$IPSET_NAME src -j DROP 2>/dev/null
    iptables -D INPUT -p udp --dport \$TARGET_PORT -m set ! --match-set \$IPSET_NAME src -j DROP 2>/dev/null
    iptables -I INPUT -p tcp --dport \$TARGET_PORT -m set ! --match-set \$IPSET_NAME src -j DROP
    iptables -I INPUT -p udp --dport \$TARGET_PORT -m set ! --match-set \$IPSET_NAME src -j DROP
fi
EOF
    chmod +x /usr/local/bin/conduit-fw-updater
    /usr/local/bin/conduit-fw-updater
}

# --- 6. Docker Compose Setup with Permission Fix ---
setup_conduit_docker() {
    mkdir -p /opt/conduit/data
    # IMPORTANT: Granting permissions to the data folder so container can write keys
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
    cd /opt/conduit && docker compose up -d
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
    content)
        echo "Listing files in data directory:"
        ls -lh /opt/conduit/data
        ;;
    update-ips)
        /usr/local/bin/conduit-fw-updater
        echo "IP list updated."
        ;;
    help)
        echo -e "${YELLOW}Conduit Manager Help${NC}"
        echo "Usage: conduit [command]"
        echo ""
        echo "Commands:"
        echo "  status      Check if container is running and see CPU/RAM"
        echo "  logs        View real-time proxy logs"
        echo "  restart     Restart the container and refresh firewall"
        echo "  content     Show files in the data directory (keys, stats)"
        echo "  update-ips  Force refresh the Iran IP list"
        echo "  uninstall   Remove everything from the system"
        ;;
    uninstall)
        read -p "Delete all data? (y/n): " confirm
        if [ "\$confirm" == "y" ]; then
            cd /opt/conduit && docker compose down
            rm -rf /opt/conduit /usr/local/bin/conduit /usr/local/bin/conduit-fw-updater
            echo "Uninstalled."
        fi
        ;;
    *)
        echo "Unknown command. Use 'conduit help'."
        ;;
esac
EOF
    chmod +x /usr/local/bin/conduit
}

# --- Execution ---
detect_os
setup_swap
install_deps
ask_questions
setup_firewall_script
setup_conduit_docker
setup_management_cli
# Cronjob
(crontab -l 2>/dev/null | grep -v "conduit-fw-updater"; echo "0 4 * * * /usr/local/bin/conduit-fw-updater > /dev/null 2>&1") | crontab -

log_success "Installation Finished. Use 'conduit status' to check."
