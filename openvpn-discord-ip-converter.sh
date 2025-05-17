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

process_region() {
    local region_dir="$1"
    local region_name
    region_name=$(basename "$region_dir")
    local input_file="${region_dir}/${region_name}-voice-resolved"
    
    if [[ ! -f "$input_file" ]]; then
        log_warn "${RED}${input_file}${NC} не найден – пропускаем регион ${MAGENTA}$region_name${NC}"
        line_skip
        return
    fi
    
    log_info "Обрабатываем регион: ${MAGENTA}$region_name${NC}"
    
    # Add region header comment
    echo "" >> "$CLIENT_ROUTES_TMP"
    echo "# Region: $region_name" >> "$CLIENT_ROUTES_TMP"
    echo "" >> "$SERVER_ROUTES_TMP"
    echo "# Region: $region_name" >> "$SERVER_ROUTES_TMP"
    
    while IFS=':' read -r hostname ip; do
        hostname=$(echo "$hostname" | xargs)
        ip=$(echo "$ip" | tr -d '\r' | xargs)
        [[ -z "$hostname" || -z "$ip" ]] && continue
        
        # Add route to client config
        echo "route $ip 255.255.255.255" >> "$CLIENT_ROUTES_TMP"
        
        # Add route to server config
        echo "push \"route $ip 255.255.255.255\"" >> "$SERVER_ROUTES_TMP"
        
        processed_lines=$((processed_lines + 1))
        percent=$(( processed_lines * 100 / total_lines ))
        echo -ne "${NC}Общий прогресс: ${percent}% (${processed_lines}/${total_lines})${NC}\r"
    done < "$input_file"
    
    log_success "Регион ${MAGENTA}$region_name${NC} успешно обработан!"
    line_skip
}

process_main_domain() {
    local domain_file="$1"
    local domain_name
    domain_name=$(basename "$domain_file" | sed 's/-resolved//')
    
    if [[ ! -f "$domain_file" ]]; then
        log_warn "${RED}${domain_file}${NC} не найден – пропускаем домен ${MAGENTA}$domain_name${NC}"
        line_skip
        return
    fi
    
    log_info "Обрабатываем домен: ${MAGENTA}$domain_name${NC}"
    
    # Add domain header comment
    echo "" >> "$CLIENT_ROUTES_TMP"
    echo "# Main Domain: $domain_name" >> "$CLIENT_ROUTES_TMP"
    echo "" >> "$SERVER_ROUTES_TMP"
    echo "# Main Domain: $domain_name" >> "$SERVER_ROUTES_TMP"
    
    while IFS=':' read -r hostname ip; do
        hostname=$(echo "$hostname" | xargs)
        ip=$(echo "$ip" | tr -d '\r' | xargs)
        [[ -z "$hostname" || -z "$ip" ]] && continue
        
        # Add route to client config
        echo "route $ip 255.255.255.255" >> "$CLIENT_ROUTES_TMP"
        
        # Add route to server config
        echo "push \"route $ip 255.255.255.255\"" >> "$SERVER_ROUTES_TMP"
        
        processed_lines=$((processed_lines + 1))
        percent=$(( processed_lines * 100 / total_lines ))
        echo -ne "${NC}Общий прогресс: ${percent}% (${processed_lines}/${total_lines})${NC}\r"
    done < "$domain_file"
    
    log_success "Домен ${MAGENTA}$domain_name${NC} успешно обработан!"
    line_skip
}

process_main_ip_list() {
    local ip_file="$1"
    
    if [[ ! -f "$ip_file" ]]; then
        log_warn "${RED}${ip_file}${NC} не найден!"
        line_skip
        return
    fi
    
    log_info "Обрабатываем основные IP Discord..."
    
    # Add domain header comment
    echo "" >> "$CLIENT_ROUTES_TMP"
    echo "# Main Discord IPs" >> "$CLIENT_ROUTES_TMP"
    echo "" >> "$SERVER_ROUTES_TMP"
    echo "# Main Discord IPs" >> "$SERVER_ROUTES_TMP"
    
    while read -r ip; do
        # Skip empty lines or comments
        [[ -z "$ip" || "$ip" == \#* ]] && continue
        
        # Get clean IP
        ip=$(echo "$ip" | tr -d '\r' | xargs)
        
        # Add route to client config
        echo "route $ip 255.255.255.255" >> "$CLIENT_ROUTES_TMP"
        
        # Add route to server config
        echo "push \"route $ip 255.255.255.255\"" >> "$SERVER_ROUTES_TMP"
        
        processed_lines=$((processed_lines + 1))
        percent=$(( processed_lines * 100 / total_lines ))
        echo -ne "${NC}Общий прогресс: ${percent}% (${processed_lines}/${total_lines})${NC}\r"
    done < "$ip_file"
    
    log_success "Основные IP Discord успешно обработаны!"
    line_skip
}

process_cloudflare_ips() {
    local cloudflare_file="cloudflare/cloudflare-ip-list"
    
    if [[ ! -f "$cloudflare_file" ]]; then
        log_warn "${RED}${cloudflare_file}${NC} не найден!"
        line_skip
        return
    fi
    
    log_info "Обрабатываем IP адреса Cloudflare..."
    
    # Collect and combine IPs into CIDR blocks
    grep -v "^$\|^#" "$cloudflare_file" | tr -d '\r' | xargs -n1 | combine_ips_to_cidr | while read -r ip netmask; do
        # Add route to client config
        echo "route $ip $netmask" >> "$CLIENT_ROUTES_TMP"
        
        # Add route to server config
        echo "push \"route $ip $netmask\"" >> "$SERVER_ROUTES_TMP"
        
        processed_lines=$((processed_lines + 1))
    done
    
    log_success "IP адреса Cloudflare успешно обработаны и объединены!"
    line_skip
}

process_custom_ips() {
    local custom_file="custom/ip-list"
    
    if [[ ! -f "$custom_file" ]]; then
        log_warn "${RED}${custom_file}${NC} не найден!"
        line_skip
        return
    fi
    
    # Add header comment
    echo "" >> "$CLIENT_ROUTES_TMP"
    echo "# Custom IPs" >> "$CLIENT_ROUTES_TMP"
    echo "" >> "$SERVER_ROUTES_TMP"
    echo "# Custom IPs" >> "$SERVER_ROUTES_TMP"
    
    while read -r ip; do
        # Skip empty lines or comments
        [[ -z "$ip" || "$ip" == \#* ]] && continue
        
        # Get clean IP
        ip=$(echo "$ip" | tr -d '\r' | xargs)
        
        # Get appropriate IP and netmask
        read -r clean_ip netmask <<< $(get_appropriate_netmask "$ip")
        
        # Skip unresolved hostnames with warning
        if [[ "$netmask" == "UNRESOLVED" ]]; then
            log_warn "Не удалось разрешить имя хоста: $ip"
            continue
        fi
        
        # Add route to client config
        echo "route $clean_ip $netmask" >> "$CLIENT_ROUTES_TMP"
        
        # Add route to server config
        echo "push \"route $clean_ip $netmask\"" >> "$SERVER_ROUTES_TMP"
        
        processed_lines=$((processed_lines + 1))
        percent=$(( processed_lines * 100 / total_lines ))
        echo -ne "${NC}Общий прогресс: ${percent}% (${processed_lines}/${total_lines})${NC}\r"
    done < "$custom_file"
    
    log_success "Пользовательские IP адреса успешно обработаны!"
    line_skip
}

# Convert IP to numeric value for sorting and calculations
ip_to_int() {
    local ip="$1"
    local a b c d
    IFS=. read -r a b c d <<< "$ip"
    echo "$((a*256**3 + b*256**2 + c*256 + d))"
}

# Convert numeric value back to IP address
int_to_ip() {
    local ip_int="$1"
    local a b c d
    d=$((ip_int % 256)); ip_int=$((ip_int / 256))
    c=$((ip_int % 256)); ip_int=$((ip_int / 256))
    b=$((ip_int % 256)); ip_int=$((ip_int / 256))
    a=$ip_int
    echo "$a.$b.$c.$d"
}

# Calculate netmask from CIDR prefix length
cidr_to_netmask() {
    local bits="$1"
    local mask=$((0xffffffff << (32 - bits)))
    local a b c d
    d=$((mask & 0xff)); mask=$((mask >> 8))
    c=$((mask & 0xff)); mask=$((mask >> 8))
    b=$((mask & 0xff)); mask=$((mask >> 8))
    a=$mask
    echo "$a.$b.$c.$d"
}

# Try to combine IP addresses into CIDR blocks
combine_ips_to_cidr() {
    local tmpfile=$(mktemp)
    local tmpout=$(mktemp)
    
    log_info "Combining IP addresses into CIDR blocks..."
    
    # First, sort and deduplicate all IPs
    sort -u > "$tmpfile"
    
    # Use ipcalc or similar tool to combine IPs if available
    if command -v aggregate-cidr &> /dev/null; then
        aggregate-cidr < "$tmpfile" > "$tmpout"
        cat "$tmpout"
    elif command -v cidr &> /dev/null; then
        cidr -s < "$tmpfile" > "$tmpout"
        cat "$tmpout"
    else
        # Simple combining for common network blocks
        awk -F. '
        function print_cidr(net, mask) {
            printf "%s %s\n", net, mask
        }
        
        # Process each IP
        {
            if ($0 ~ /\.[0-9]+\.0\.0$/) {
                # Class A networks
                print_cidr($1".0.0.0", "255.0.0.0")
                next
            } else if ($0 ~ /\.[0-9]+\.[0-9]+\.0$/) {
                # Class B networks
                print_cidr($1"."$2".0.0", "255.255.0.0")
                next
            } else if ($0 ~ /\.[0-9]+\.[0-9]+\.[0-9]+$/ && $4 % 16 == 0) {
                # Try to combine into /28 blocks
                block = $1"."$2"."$3"."int($4/16)*16
                print_cidr(block, "255.255.255.240")
                next
            }
            # Default case - single IP
            print_cidr($0, "255.255.255.255")
        }' "$tmpfile" | sort | uniq > "$tmpout"
        cat "$tmpout"
    fi
    
    rm "$tmpfile" "$tmpout"
}

# Function to determine appropriate netmask based on IP address pattern
get_appropriate_netmask() {
    local ip="$1"
    
    # Check if it's a hostname (contains non-digit and non-dot characters)
    if [[ "$ip" =~ [^0-9\.] ]]; then
        # Try to resolve the hostname
        local resolved_ip
        resolved_ip=$(dig +short "$ip" | head -n1)
        
        # If resolved successfully, use the IP with host mask
        if [[ -n "$resolved_ip" ]]; then
            echo "$resolved_ip 255.255.255.255"
            return
        else
            # If can't resolve, flag it
            echo "$ip UNRESOLVED"
            return
        fi
    fi
    
    # Common network addresses with standard netmasks
    case "$ip" in
        # Class A networks (ending in .0.0.0)
        *".0.0.0") echo "$ip 255.0.0.0" ;;
        
        # Class B networks (ending in .0.0)
        *".0.0") echo "$ip 255.255.0.0" ;;
        
        # Class C networks (ending in .0)
        *".0") echo "$ip 255.255.255.0" ;;
        
        # Host addresses (anything else)
        *) echo "$ip 255.255.255.255" ;;
    esac
}

log_info "Обрабатываем региональные голосовые серверы..."
for region_dir in regions/*; do
    if [[ -d "$region_dir" ]]; then
        process_region "$region_dir"
    fi
done

log_info "Обрабатываем основные домены Discord..."
if [[ -d "main_domains" ]]; then
    # Process the discord-main-ip-list file (contains only IPs)
    if [[ -f "main_domains/discord-main-ip-list" ]]; then
        process_main_ip_list "main_domains/discord-main-ip-list"
    else
        log_warn "Файл discord-main-ip-list не найден!"
    fi
    
    # Process any other resolved files (excluding the ipset-list)
    for domain_file in main_domains/*-resolved; do
        if [[ -f "$domain_file" && ! "$domain_file" == *"ipset-list"* ]]; then
            process_main_domain "$domain_file"
        fi
    done
else
    log_warn "Директория main_domains не найдена!"
fi

log_info "Обрабатываем IP адреса Cloudflare..."
if [[ -f "cloudflare/cloudflare-ip-list" ]]; then
    process_cloudflare_ips
else
    log_warn "Файл cloudflare/cloudflare-ip-list не найден!"
    log_info "Запустите сначала cloudflare-ip-getter.sh для получения IP адресов Cloudflare"
fi

log_info "Обрабатываем пользовательские IP адреса..."
if [[ -f "custom/ip-list" ]]; then
    process_custom_ips
else
    log_warn "Файл custom/ip-list не найден!"
    log_info "Создайте файл custom/ip-list для добавления собственных маршрутов"
fi

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