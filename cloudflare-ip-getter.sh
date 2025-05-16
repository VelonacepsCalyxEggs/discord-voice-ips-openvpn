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

# Process each IPv4 range
for cidr in $ipv4_cidrs; do
    # Extract network info
    ip=$(echo $cidr | cut -d'/' -f1)
    mask=$(echo $cidr | cut -d'/' -f2)
    
    # Add header comment for this range
    echo "# Range: $cidr" >> "$OUTPUT_FILE"
    
    # For smaller ranges only (to avoid generating too many IPs)
    if [ "$mask" -ge 24 ]; then
        log_info "Expanding $cidr to individual IPs..."
        
        # Calculate network values
        IFS=. read -r i1 i2 i3 i4 <<< "$ip"
        IFS=. read -r m1 m2 m3 m4 <<< $(ipcalc "$cidr" | grep -i "netmask" | awk '{print $2}')
        
        # Calculate network address
        net1=$((i1 & m1))
        net2=$((i2 & m2))
        net3=$((i3 & m3))
        net4=$((i4 & m4))
        
        # Calculate the number of IP addresses in this subnet
        ip_count=$((2**(32-mask)))
        
        # Generate IPs up to a reasonable limit
        if [ "$ip_count" -le 256 ]; then
            for ((i=0; i<ip_count; i++)); do
                host4=$((net4 + i))
                if [ "$host4" -gt 255 ]; then
                    # This is a simplified version; for full implementation we'd need to handle carry-over
                    # I'll probably re-make this part later...
                    continue
                fi
                echo "$net1.$net2.$net3.$host4" >> "$OUTPUT_FILE"
            done
        else
            # For larger ranges, just note the range
            echo "# Range too large to expand ($ip_count IPs)" >> "$OUTPUT_FILE"
            echo "$cidr" >> "$OUTPUT_FILE"
        fi
    else
        # For large ranges, just keep the CIDR notation
        echo "$cidr" >> "$OUTPUT_FILE"
    fi
    echo "" >> "$OUTPUT_FILE"
done

log_success "Cloudflare IPv4 ranges have been saved to $OUTPUT_FILE"