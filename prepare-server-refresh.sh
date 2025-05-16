#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Logging functions
line_skip()   { echo -e ". . ."; }
log_info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# Configuration - set these environment variables or use defaults
OPENVPN_SERVER_CONF=${OPENVPN_SERVER_CONF:-"/etc/openvpn/server.conf"}
OPENVPN_CLIENT_CONF=${OPENVPN_CLIENT_CONF:-"/etc/openvpn/client.ovpn"}

# Ensure OpenVPN directory exists
mkdir -p ./openvpn

run_step() {
    local script="$1"
    local desc="$2"
    
    if [[ ! -x "$script" ]]; then
        chmod +x "$script"
    fi
    
    log_info "Starting $desc..."
    if bash "$script"; then
        log_success "$desc completed successfully!"
    else
        log_error "$desc failed with code $?"
        exit 1
    fi
    line_skip
}

# Step 1: Resolve main domains
run_step "./main-domains-resolver.sh" "Main domains resolution"

# Step 2: Generate voice domains
run_step "./voice-domains-generator.sh" "Voice domains generation"

# Step 3: Get Cloudflare IPs
run_step "./cloudflare-ip-getter.sh" "Cloudflare IP retrieval"

# Step 4: Copy server config from source location
log_info "Copying server configuration from ${MAGENTA}$OPENVPN_SERVER_CONF${NC}..."
if [[ -f "$OPENVPN_SERVER_CONF" ]]; then
    cp "$OPENVPN_SERVER_CONF" ./openvpn/server.conf
    log_success "Server configuration copied successfully"
else
    log_error "Source server configuration not found at $OPENVPN_SERVER_CONF"
    exit 1
fi
line_skip

# Step 5: Copy client config if exists
log_info "Copying client configuration from ${MAGENTA}$OPENVPN_CLIENT_CONF${NC}..."
if [[ -f "$OPENVPN_CLIENT_CONF" ]]; then
    cp "$OPENVPN_CLIENT_CONF" ./openvpn/client.ovpn
    log_success "Client configuration copied successfully"
else
    log_warn "Source client configuration not found at $OPENVPN_CLIENT_CONF"
    log_info "Will use default template if present"
fi
line_skip

# Step 6: Update OpenVPN configuration with Discord IPs
run_step "./openvpn-discord-ip-converter.sh" "OpenVPN configuration update"

# Step 7: Copy the updated configs back to original location
log_info "Copying updated server configuration back to ${MAGENTA}$OPENVPN_SERVER_CONF${NC}..."
if cp ./openvpn/server.conf "$OPENVPN_SERVER_CONF"; then
    log_success "Updated server configuration deployed successfully"
else
    log_error "Failed to deploy server configuration"
    exit 1
fi

if [[ -f "./openvpn/client.ovpn" && -f "$OPENVPN_CLIENT_CONF" ]]; then
    log_info "Copying updated client configuration back to ${MAGENTA}$OPENVPN_CLIENT_CONF${NC}..."
    if cp ./openvpn/client.ovpn "$OPENVPN_CLIENT_CONF"; then
        log_success "Updated client configuration deployed successfully"
    else
        log_error "Failed to deploy client configuration"
        exit 1
    fi
fi
line_skip

log_success "All steps completed successfully!"
log_info "OpenVPN configurations have been updated with the latest Discord and Cloudflare IPs"

# Restart OpenVPN service if needed (uncomment to use)
# log_info "Restarting OpenVPN service..."
# systemctl restart openvpn@server || log_error "Failed to restart OpenVPN service"