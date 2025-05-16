#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# Make sure output directory exists
mkdir -p ./cloudflare

OUTPUT_FILE="./cloudflare/cloudflare-ip-list"

log_info "Querying Cloudflare API for IP ranges..."

# Fetch IP data from Cloudflare API
response=$(curl -s "https://api.cloudflare.com/client/v4/ips")

# Check if curl request was successful
if [ $? -ne 0 ]; then
    log_error "Failed to fetch data from Cloudflare API"
    exit 1
fi

# Extract IPv4 CIDRs using grep and sed/awk
ipv4_cidrs=$(echo "$response" | grep -o '"ipv4_cidrs":\[[^]]*\]' | sed 's/"ipv4_cidrs":\[//; s/\]//; s/"//g; s/,/ /g')

log_info "Processing IPv4 ranges..."

# Clear output file
> "$OUTPUT_FILE"

# Process each IPv4 range - only extract the IP part
for cidr in $ipv4_cidrs; do
    # Extract just the IP part (before the slash)
    ip=$(echo $cidr | cut -d'/' -f1)
    
    # Write just the IP to the file
    echo "$ip" >> "$OUTPUT_FILE"
done

log_success "Cloudflare IPv4 addresses have been saved to $OUTPUT_FILE"

# Yup, I definately overcomplicated the older version of this...