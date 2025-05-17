#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

line_skip()   { echo -e ". . ."; }
log_info()    { echo -e "${CYAN}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

# Configuration file paths
CLIENT_CONFIG="./openvpn/client.ovpn"
SERVER_CONFIG="./openvpn/server.conf"

# Create temp files for route definitions
CLIENT_ROUTES_TMP=$(mktemp)
SERVER_ROUTES_TMP=$(mktemp)

# Add comments to the top of the route sections
echo "# Discord routes - Generated $(date)" > "$CLIENT_ROUTES_TMP"
echo "# Discord routes - Generated $(date)" > "$SERVER_ROUTES_TMP"

log_info "Counting files for progress tracking..."

# Count total lines for progress tracking
total_lines=0

# Count lines in region files
for region_dir in regions/*; do
    region_name=$(basename "$region_dir")
    input_file="${region_dir}/${region_name}-voice-resolved"
    if [[ -f "$input_file" ]]; then
        lines_in_file=$(wc -l < "$input_file")
        total_lines=$((total_lines + lines_in_file))
    fi
done

# Count lines in main_domains files
if [[ -d "main_domains" ]]; then
    # Count discord-main-ip-list 
    if [[ -f "main_domains/discord-main-ip-list" ]]; then
        lines_in_file=$(grep -v "^$" "main_domains/discord-main-ip-list" | wc -l)
        total_lines=$((total_lines + lines_in_file))
    fi
    
    # Count any resolved files
    for domain_file in main_domains/*-resolved; do
        if [[ -f "$domain_file" && ! "$domain_file" == *"ipset-list"* ]]; then
            lines_in_file=$(wc -l < "$domain_file")
            total_lines=$((total_lines + lines_in_file))
        fi
    done
fi

# Count lines in Cloudflare IP list
if [[ -f "cloudflare/cloudflare-ip-list" ]]; then
    lines_in_file=$(grep -v "^$" "cloudflare/cloudflare-ip-list" | wc -l)
    total_lines=$((total_lines + lines_in_file))
    log_info "Found ${lines_in_file} Cloudflare IP addresses"
fi

# Count lines in custom IP list
if [[ -f "custom/ip-list" ]]; then
    lines_in_file=$(grep -v "^$" "custom/ip-list" | wc -l)
    total_lines=$((total_lines + lines_in_file))
    log_info "Found ${lines_in_file} custom IP addresses"
fi

processed_lines=0

# Modified approach: collect all IPs first, then combine them by category

# Create these functions right after the logging functions
collect_region_ips() {
    local region_dir="$1"
    local output_file="$2"
    local region_name=$(basename "$region_dir")
    local input_file="${region_dir}/${region_name}-voice-resolved"
    
    if [[ ! -f "$input_file" ]]; then
        log_warn "${RED}${input_file}${NC} не найден – пропускаем регион ${MAGENTA}$region_name${NC}"
        return
    fi
    
    log_info "Собираем IP-адреса региона: ${MAGENTA}$region_name${NC}"
    
    # Add region header comment to tracking file
    echo "# Region: $region_name" >> "$output_file.meta"
    
    # Extract IPs into collection file
    while IFS=':' read -r hostname ip; do
        ip=$(echo "$ip" | tr -d '\r' | xargs)
        [[ -z "$ip" ]] && continue
        echo "$ip" >> "$output_file"
    done < "$input_file"
    
    processed_lines=$((processed_lines + $(wc -l < "$input_file")))
    percent=$(( processed_lines * 100 / total_lines ))
    echo -ne "${NC}Общий прогресс: ${percent}% (${processed_lines}/${total_lines})${NC}\r"
    
    log_success "IP-адреса региона ${MAGENTA}$region_name${NC} собраны!"
}

collect_main_domain_ips() {
    local domain_file="$1"
    local output_file="$2"
    local domain_name=$(basename "$domain_file" | sed 's/-resolved//')
    
    if [[ ! -f "$domain_file" ]]; then
        log_warn "${RED}${domain_file}${NC} не найден – пропускаем домен ${MAGENTA}$domain_name${NC}"
        return
    fi
    
    log_info "Собираем IP-адреса домена: ${MAGENTA}$domain_name${NC}"
    
    # Add domain header comment to tracking file
    echo "# Main Domain: $domain_name" >> "$output_file.meta"
    
    # Extract IPs into collection file
    while IFS=':' read -r hostname ip; do
        ip=$(echo "$ip" | tr -d '\r' | xargs)
        [[ -z "$ip" ]] && continue
        echo "$ip" >> "$output_file"
    done < "$domain_file"
    
    processed_lines=$((processed_lines + $(wc -l < "$domain_file")))
    percent=$(( processed_lines * 100 / total_lines ))
    echo -ne "${NC}Общий прогресс: ${percent}% (${processed_lines}/${total_lines})${NC}\r"
    
    log_success "IP-адреса домена ${MAGENTA}$domain_name${NC} собраны!"
}

collect_main_ip_list() {
    local ip_file="$1"
    local output_file="$2"
    
    if [[ ! -f "$ip_file" ]]; then
        log_warn "${RED}${ip_file}${NC} не найден!"
        return
    fi
    
    log_info "Собираем основные IP-адреса Discord..."
    
    # Add header comment to tracking file
    echo "# Main Discord IPs" >> "$output_file.meta"
    
    # Extract IPs into collection file
    while read -r ip; do
        # Skip empty lines or comments
        [[ -z "$ip" || "$ip" == \#* ]] && continue
        ip=$(echo "$ip" | tr -d '\r' | xargs)
        echo "$ip" >> "$output_file"
    done < "$ip_file"
    
    processed_lines=$((processed_lines + $(grep -vc "^$\|^#" "$ip_file")))
    percent=$(( processed_lines * 100 / total_lines ))
    echo -ne "${NC}Общий прогресс: ${percent}% (${processed_lines}/${total_lines})${NC}\r"
    
    log_success "Основные IP-адреса Discord собраны!"
}

collect_cloudflare_ips() {
    local cloudflare_file="$1"
    local output_file="$2"
    
    if [[ ! -f "$cloudflare_file" ]]; then
        log_warn "${RED}${cloudflare_file}${NC} не найден!"
        return
    fi
    
    log_info "Собираем IP-адреса Cloudflare..."
    
    # Add header comment to tracking file
    echo "# Cloudflare IPs" >> "$output_file.meta"
    
    # Extract IPs into collection file
    while read -r ip; do
        # Skip empty lines or comments
        [[ -z "$ip" || "$ip" == \#* ]] && continue
        ip=$(echo "$ip" | tr -d '\r' | xargs)
        echo "$ip" >> "$output_file"
    done < "$cloudflare_file"
    
    processed_lines=$((processed_lines + $(grep -vc "^$\|^#" "$cloudflare_file")))
    percent=$(( processed_lines * 100 / total_lines ))
    echo -ne "${NC}Общий прогресс: ${percent}% (${processed_lines}/${total_lines})${NC}\r"
    
    log_success "IP-адреса Cloudflare собраны!"
}

collect_custom_ips() {
    local custom_file="$1"
    local output_file="$2"
    
    if [[ ! -f "$custom_file" ]]; then
        log_warn "${RED}${custom_file}${NC} не найден!"
        return
    fi
    
    log_info "Собираем пользовательские IP-адреса..."
    
    # Add header comment to tracking file
    echo "# Custom IPs" >> "$output_file.meta"
    
    # First resolve any hostnames to IPs
    while read -r entry; do
        # Skip empty lines or comments
        [[ -z "$entry" || "$entry" == \#* ]] && continue
        
        # Get clean entry
        entry=$(echo "$entry" | tr -d '\r' | xargs)
        
        # Check if it's a hostname
        if [[ "$entry" =~ [^0-9\.] ]]; then
            # Try to resolve
            resolved_ip=$(dig +short "$entry" | head -n1)
            if [[ -n "$resolved_ip" ]]; then
                echo "$resolved_ip" >> "$output_file"
            else
                log_warn "Не удалось разрешить: $entry"
            fi
        else
            echo "$entry" >> "$output_file"
        fi
    done < "$custom_file"
    
    processed_lines=$((processed_lines + $(grep -vc "^$\|^#" "$custom_file")))
    percent=$(( processed_lines * 100 / total_lines ))
    echo -ne "${NC}Общий прогресс: ${percent}% (${processed_lines}/${total_lines})${NC}\r"
    
    log_success "Пользовательские IP-адреса собраны!"
}

# Process the collected IPs for each category
process_collected_ips() {
    local input_file="$1"
    local meta_file="$1.meta"
    local category="$2"
    
    log_info "Объединяем IP-адреса категории ${MAGENTA}$category${NC} в блоки CIDR..."
    
    # Add category header to config files
    echo "" >> "$CLIENT_ROUTES_TMP"
    echo "# $category (Optimized)" >> "$CLIENT_ROUTES_TMP"
    echo "" >> "$SERVER_ROUTES_TMP"
    echo "# $category (Optimized)" >> "$SERVER_ROUTES_TMP"
    
    # If we have metadata comments, add them
    if [[ -f "$meta_file" ]]; then
        cat "$meta_file" >> "$CLIENT_ROUTES_TMP"
        cat "$meta_file" >> "$SERVER_ROUTES_TMP"
    fi
    
    # Apply CIDR combining
    if [[ -f "$input_file" && -s "$input_file" ]]; then
        cat "$input_file" | combine_ips_to_cidr | while read -r ip netmask; do
            # Add route to client config
            echo "route $ip $netmask" >> "$CLIENT_ROUTES_TMP"
            
            # Add route to server config
            echo "push \"route $ip $netmask\"" >> "$SERVER_ROUTES_TMP"
        done
        log_success "IP-адреса категории ${MAGENTA}$category${NC} оптимизированы!"
    else
        log_warn "Нет IP-адресов для категории ${MAGENTA}$category${NC}."
    fi
}

# Add this function near the top of your script after the logging functions

# Function to convert IP to an integer for sorting/comparison
ip_to_int() {
    local ip="$1"
    local a b c d
    IFS=. read -r a b c d <<< "$ip"
    echo "$((a*256**3 + b*256**2 + c*256 + d))"
}

# Function to convert integer back to IP
int_to_ip() {
    local ip_int="$1"
    local a b c d
    d=$((ip_int % 256)); ip_int=$((ip_int / 256))
    c=$((ip_int % 256)); ip_int=$((ip_int / 256))
    b=$((ip_int % 256)); ip_int=$((ip_int / 256))
    a=$ip_int
    echo "$a.$b.$c.$d"
}

# Determine appropriate netmask for an IP address
get_appropriate_netmask() {
    local ip="$1"
    
    # Check if it ends with multiple zeros
    if [[ "$ip" =~ \.0\.0\.0$ ]]; then
        echo "$ip 255.0.0.0"     # Class A
    elif [[ "$ip" =~ \.0\.0$ ]]; then
        echo "$ip 255.255.0.0"   # Class B
    elif [[ "$ip" =~ \.0$ ]]; then
        echo "$ip 255.255.255.0" # Class C
    else
        echo "$ip 255.255.255.255" # Host address
    fi
}

# Function to combine IPs into CIDR blocks
combine_ips_to_cidr() {
    local tmpfile=$(mktemp)
    local tmpsorted=$(mktemp)
    
    # Sort and deduplicate the IP addresses
    sort -u > "$tmpfile"
    
    # Convert IPs to integers for proper sorting
    while read -r ip; do
        # Skip empty lines or comments
        [[ -z "$ip" || "$ip" == \#* ]] && continue
        
        # Clean the IP
        ip=$(echo "$ip" | tr -d '\r' | xargs)
        
        # Convert to integer and store with original IP for sorting
        int_val=$(ip_to_int "$ip")
        echo "$int_val $ip"
    done < "$tmpfile" | sort -n > "$tmpsorted"

    # Track ranges of consecutive IPs
    local start_ip=""
    local prev_int=0
    local count=0
    local block_size=0

    # Process sorted IPs to find ranges
    while read -r int_val ip; do
        # First IP in potential block
        if [[ -z "$start_ip" ]]; then
            start_ip="$ip"
            prev_int=$int_val
            count=1
            continue
        fi
        
        # Check if this IP is consecutive with previous
        if [[ $((int_val - prev_int)) -eq 1 ]]; then
            # Part of current block
            count=$((count + 1))
            prev_int=$int_val
        else
            # End of a block, determine if it can be a CIDR
            if [[ $count -ge 2 ]]; then
                # Calculate netmask bits - find largest power of 2 that fits
                local mask_bits=32
                local block_size=$count
                local start_int=$(ip_to_int "$start_ip")
                
                # Find largest power of 2 that fits the block
                while [[ $block_size -gt 1 ]]; do
                    mask_bits=$((mask_bits - 1))
                    block_size=$((block_size / 2))
                done
                
                # Check if block is aligned to its size
                if [[ $((start_int % (1 << (32 - mask_bits)))) -eq 0 ]]; then
                    # Can represent as CIDR
                    local netmask=$(cidr_to_netmask "$mask_bits")
                    echo "$start_ip $netmask"
                else
                    # Not properly aligned, use individual IPs
                    local cur_int=$start_int
                    for ((i=0; i<count; i++)); do
                        local cur_ip=$(int_to_ip "$cur_int")
                        echo "$cur_ip 255.255.255.255"
                        cur_int=$((cur_int + 1))
                    done
                fi
            else
                # Single IP
                echo "$start_ip 255.255.255.255"
            fi
            
            # Start new block
            start_ip="$ip"
            prev_int=$int_val
            count=1
        fi
    done < "$tmpsorted"
    
    # Handle the last block
    if [[ -n "$start_ip" ]]; then
        if [[ $count -ge 2 ]]; then
            # Calculate netmask bits - find largest power of 2 that fits
            local mask_bits=32
            local block_size=$count
            local start_int=$(ip_to_int "$start_ip")
            
            while [[ $block_size -gt 1 ]]; do
                mask_bits=$((mask_bits - 1))
                block_size=$((block_size / 2))
            done
            
            # Check if block is aligned
            if [[ $((start_int % (1 << (32 - mask_bits)))) -eq 0 ]]; then
                local netmask=$(cidr_to_netmask "$mask_bits")
                echo "$start_ip $netmask"
            else
                # Output individual IPs
                local cur_int=$start_int
                for ((i=0; i<count; i++)); do
                    local cur_ip=$(int_to_ip "$cur_int")
                    echo "$cur_ip 255.255.255.255" 
                    cur_int=$((cur_int + 1))
                done
            fi
        else
            # Single IP
            echo "$start_ip 255.255.255.255"
        fi
    fi
    
    # Clean up
    rm -f "$tmpfile" "$tmpsorted"
}

# Convert CIDR prefix length to netmask
cidr_to_netmask() {
    local bits=$1
    local mask=$((0xffffffff << (32 - bits)))
    local a=$((mask >> 24 & 0xff))
    local b=$((mask >> 16 & 0xff))
    local c=$((mask >> 8 & 0xff))
    local d=$((mask & 0xff))
    echo "$a.$b.$c.$d"
}

# Create temp directories for IP collection
mkdir -p ./temp_ip_collection
rm -rf ./temp_ip_collection/*

# Define collection files
REGIONS_IPS="./temp_ip_collection/regions_ips"
MAIN_DOMAINS_IPS="./temp_ip_collection/main_domains_ips"
MAIN_IP_LIST="./temp_ip_collection/main_ip_list"
CLOUDFLARE_IPS="./temp_ip_collection/cloudflare_ips"
CUSTOM_IPS="./temp_ip_collection/custom_ips"

# Clear collection files
> "$REGIONS_IPS"
> "$REGIONS_IPS.meta"
> "$MAIN_DOMAINS_IPS"
> "$MAIN_DOMAINS_IPS.meta"
> "$MAIN_IP_LIST"
> "$MAIN_IP_LIST.meta"
> "$CLOUDFLARE_IPS"
> "$CLOUDFLARE_IPS.meta"
> "$CUSTOM_IPS"
> "$CUSTOM_IPS.meta"

# Collection phase
log_info "Фаза 1: Сбор IP-адресов по категориям..."

# Collect regions
for region_dir in regions/*; do
    if [[ -d "$region_dir" ]]; then
        collect_region_ips "$region_dir" "$REGIONS_IPS"
    fi
done

# Collect main domains
if [[ -d "main_domains" ]]; then
    if [[ -f "main_domains/discord-main-ip-list" ]]; then
        collect_main_ip_list "main_domains/discord-main-ip-list" "$MAIN_IP_LIST"
    fi
    
    for domain_file in main_domains/*-resolved; do
        if [[ -f "$domain_file" && ! "$domain_file" == *"ipset-list"* ]]; then
            collect_main_domain_ips "$domain_file" "$MAIN_DOMAINS_IPS"
        fi
    done
fi

# Collect Cloudflare IPs
if [[ -f "cloudflare/cloudflare-ip-list" ]]; then
    collect_cloudflare_ips "cloudflare/cloudflare-ip-list" "$CLOUDFLARE_IPS"
fi

# Collect custom IPs
if [[ -f "custom/ip-list" ]]; then
    collect_custom_ips "custom/ip-list" "$CUSTOM_IPS"
fi

# Processing phase
log_info "Фаза 2: Оптимизация IP-адресов и создание маршрутов..."

# Process each category
process_collected_ips "$REGIONS_IPS" "Regional Discord Servers"
process_collected_ips "$MAIN_DOMAINS_IPS" "Main Discord Domains"
process_collected_ips "$MAIN_IP_LIST" "Main Discord IPs"
process_collected_ips "$CLOUDFLARE_IPS" "Cloudflare IPs"
process_collected_ips "$CUSTOM_IPS" "Custom IPs"

log_info "Обновляем конфигурационные файлы OpenVPN..."

# Create backup of original files
cp "$CLIENT_CONFIG" "${CLIENT_CONFIG}.bak"
cp "$SERVER_CONFIG" "${SERVER_CONFIG}.bak"

# Update client config
awk -v routes="$(cat $CLIENT_ROUTES_TMP)" '
/# BEGIN_DISCORD_ROUTES/{print; print routes; next}
/# END_DISCORD_ROUTES/{print; next}
/# Discord routes/{next}
/(^route |IP-ADRESSES)/{next} 
{print}' "${CLIENT_CONFIG}.bak" > "$CLIENT_CONFIG"

# Update server config
awk -v routes="$(cat $SERVER_ROUTES_TMP)" '
/# BEGIN_DISCORD_ROUTES/{print; print routes; next}
/# END_DISCORD_ROUTES/{print; next}
/# Discord routes/{next}
/^push "route /{next}
{print}' "${SERVER_CONFIG}.bak" > "$SERVER_CONFIG"

# Clean up temp files
rm "$CLIENT_ROUTES_TMP" "$SERVER_ROUTES_TMP"

log_success "Готово! Конфигурационные файлы OpenVPN обновлены маршрутами Discord серверов."
log_info "Резервные копии сохранены как ${CLIENT_CONFIG}.bak и ${SERVER_CONFIG}.bak"