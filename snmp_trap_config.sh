#!/bin/bash

# Colors for better readability
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Define global variables
DETECTED_ENGINE_ID=""
DETECTED_SOURCE_IP=""

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}   SNMP Trap Integration Setup Tool     ${NC}"
echo -e "${GREEN}========================================${NC}"

# Check for required tools
check_requirements() {
    local missing_tools=()
    
    for tool in snmpwalk snmpget tcpdump netstat grep awk; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done
    
    if [ ${#missing_tools[@]} -ne 0 ]; then
        echo -e "${RED}The following required tools are missing:${NC}"
        for tool in "${missing_tools[@]}"; do
            echo -e "  - $tool"
        done
        echo -e "${YELLOW}Please install these tools before proceeding.${NC}"
        echo -e "For example: sudo apt-get install net-snmp net-snmp-utils tcpdump"
        exit 1
    fi
}

# Display network interfaces and IP information
display_network_info() {
    echo -e "\n${BLUE}Current Network Interfaces:${NC}"
    ip -4 addr | grep -v 127.0.0.1 | grep "inet " | awk '{print $2, $NF}' | column -t
    
    echo -e "\n${BLUE}Current SNMP Configuration:${NC}"
    if [ -f "/etc/snmp/snmpd.conf" ]; then
        echo -e "SNMP configuration file exists at: /etc/snmp/snmpd.conf"
        grep -E "trap|inform|community|user|engineID" /etc/snmp/snmpd.conf 2>/dev/null
    else
        echo -e "${YELLOW}No SNMP configuration file found at /etc/snmp/snmpd.conf${NC}"
    fi
}

# Display available network interfaces and get user selection
select_interface() {
    echo -e "\n${BLUE}Available Network Interfaces:${NC}"
    
    # Get all available interfaces that are UP
    local interfaces=()
    local counter=1
    local default_interface=""
    local default_number=0
    
    # Read interfaces into an array, only including interfaces that are UP
    while read -r line; do
        # Extract interface name and check if it's UP
        local interface=$(echo "$line" | awk '{print $2}')
        local status=$(echo "$line" | grep -o "UP")
        
        # Skip loopback and interfaces that aren't UP
        if [[ "$interface" != "lo" && "$status" == "UP" ]]; then
            interfaces+=("$interface")
            echo -e "$counter) $interface"
            
            # Check if this is our default interface
            if [[ "$interface" == "ens160" ]]; then
                default_interface="ens160"
                default_number=$counter
            fi
            
            ((counter++))
        fi
    done < <(ip link show | grep -v "master")
    
    # If no interfaces found, use "any"
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No active interfaces found. Using 'any' to capture on all interfaces.${NC}"
        echo "any"
        return
    fi
    
    # If ens160 is not found, set first interface as default
    if [[ -z "$default_interface" && ${#interfaces[@]} -gt 0 ]]; then
        default_interface=${interfaces[0]}
        default_number=1
    fi
    
    # Prompt user to select an interface
    local selected_interface=""
    if [[ -n "$default_interface" ]]; then
        echo -e "\n${YELLOW}Default interface: ${GREEN}$default_interface${NC} (option $default_number)"
        read -p "Select interface to capture on [${default_number}]: " selection
        
        # If no selection made, use default
        if [[ -z "$selection" ]]; then
            selected_interface=$default_interface
        else
            # Convert selection to valid array index (1-based to 0-based)
            local idx=$((selection - 1))
            if [[ $idx -ge 0 && $idx -lt ${#interfaces[@]} ]]; then
                selected_interface=${interfaces[$idx]}
            else
                echo -e "${RED}Invalid selection, using default: $default_interface${NC}"
                selected_interface=$default_interface
            fi
        fi
    else
        # No default interface found, must select
        read -p "Select interface to capture on [1-${#interfaces[@]}]: " selection
        local idx=$((selection - 1))
        if [[ $idx -ge 0 && $idx -lt ${#interfaces[@]} ]]; then
            selected_interface=${interfaces[$idx]}
        else
            echo -e "${RED}Invalid selection, using first interface: ${interfaces[0]}${NC}"
            selected_interface=${interfaces[0]}
        fi
    fi
    
    # Final check to make sure interface exists and is up
    if ! ip link show dev "$selected_interface" &>/dev/null; then
        echo -e "${RED}Interface $selected_interface not found. Falling back to 'any'.${NC}"
        selected_interface="any"
    fi
    
    echo -e "${GREEN}Using interface: $selected_interface${NC}"
    echo $selected_interface
}

# Capture SNMP trap
capture_trap() {
    local snmp_port=1162
    
    # Let user select which interface to capture on
    local capture_interface=$(select_interface)
    
    echo -e "\n${BLUE}Capturing SNMP traps on port $snmp_port using interface $capture_interface...${NC}"
    echo -e "${YELLOW}Please send your test trap now.${NC}"
    echo -e "Press ENTER at any time to stop the capture."
    
    # Create a temporary file with proper permissions
    local capture_file="/tmp/snmp_capture_$$.pcap"
    sudo touch "$capture_file"
    sudo chmod 666 "$capture_file"
    
    # Check for sudo access
    echo -e "${YELLOW}Capture requires root privileges. You may be prompted for your password.${NC}"
    
    # Start tcpdump in the background on the selected interface
    # Check if tcpdump works with the selected interface
    if ! sudo tcpdump -i $capture_interface -n -c 1 -w /dev/null &>/dev/null; then
        echo -e "${RED}Error: Cannot capture on interface $capture_interface${NC}"
        echo -e "${YELLOW}Falling back to capturing on all interfaces ('any')${NC}"
        capture_interface="any"
    fi
    
    sudo tcpdump -i $capture_interface -n port $snmp_port -vv -w "$capture_file" &
    local tcpdump_pid=$!
    
    # Counter for the seconds
    local counter=0
    
    echo -e "Capturing packets..."
    
    # Loop until user presses Enter
    while true; do
        echo -ne "${YELLOW}Capturing for ${counter}s (Press ENTER to stop)${NC}\r"
        
        # Check if tcpdump process is still running
        if ! ps -p $tcpdump_pid &>/dev/null; then
            echo -e "\n${RED}Capture process stopped unexpectedly. Please check your interface.${NC}"
            break
        fi
        
        # Check if we've received any packets
        if [ -f "$capture_file" ] && [ -s "$capture_file" ] && [ "$(sudo tcpdump -r "$capture_file" 2>/dev/null | wc -l)" -gt 0 ]; then
            echo -ne "${GREEN}Packets captured! Capturing for ${counter}s (Press ENTER to stop)${NC}\r"
        fi
        
        # Check if the user pressed Enter (with a 1-second timeout)
        read -t 1 -n 1 && break
        
        # If read times out (user didn't press Enter), increment counter and continue
        ((counter++))
    done
    
    # Kill tcpdump if it's still running
    if ps -p $tcpdump_pid &>/dev/null; then
        sudo kill $tcpdump_pid 2>/dev/null
        wait $tcpdump_pid 2>/dev/null
    fi
    
    echo -e "\n\n${BLUE}Capture completed.${NC}"
    
    # Make sure file is accessible
    sudo chmod 666 "$capture_file" 2>/dev/null
    
    # Check if capture file exists and has content
    if [ ! -f "$capture_file" ] || [ ! -s "$capture_file" ]; then
        echo -e "${RED}Capture file is empty or does not exist.${NC}"
        read -p "Would you like to try again? (y/n): " retry
        if [[ $retry =~ ^[Yy]$ ]]; then
            sudo rm -f "$capture_file" 2>/dev/null
            capture_trap
            return
        fi
        return 1
    fi
    
    # Check if we captured any SNMP packets
    local packet_count=$(sudo tcpdump -r "$capture_file" 2>/dev/null | wc -l)
    
    if [ $packet_count -eq 0 ]; then
        echo -e "${RED}No SNMP traps were captured.${NC}"
        echo -e "Please verify that:"
        echo -e "  1. The trap sender is configured correctly"
        echo -e "  2. The trap is being sent to this machine's IP on interface $capture_interface"
        echo -e "  3. No firewall is blocking UDP port $snmp_port"
        
        read -p "Would you like to try again? (y/n): " retry
        if [[ $retry =~ ^[Yy]$ ]]; then
            sudo rm -f "$capture_file"
            capture_trap
            return
        fi
    else
        echo -e "${GREEN}Captured $packet_count packets.${NC}"
        echo -e "\n${BLUE}SNMP Trap Analysis:${NC}"
        
        # Analyze the captured traffic
        sudo tcpdump -r "$capture_file" -vvv -n 2>/dev/null | grep -A 20 "SNMP" | head -30
        
        # Extract SNMPv3 information if available and store in global variables
        DETECTED_ENGINE_ID=$(sudo tcpdump -r "$capture_file" -vvv -n 2>/dev/null | grep -o "engine ID [A-Fa-f0-9:]*" | head -1 | awk '{print $3}')
        DETECTED_SOURCE_IP=$(sudo tcpdump -r "$capture_file" -n 2>/dev/null | grep "IP" | head -1 | awk '{print $3}' | sed 's/.[0-9]*$//')
        local user_info=$(sudo tcpdump -r "$capture_file" -vvv -n 2>/dev/null | grep -A 2 "user " | head -3)
        local auth_info=$(sudo tcpdump -r "$capture_file" -vvv -n 2>/dev/null | grep -A 2 "auth " | head -3)
        
        if [ ! -z "$DETECTED_ENGINE_ID" ]; then
            echo -e "\n${GREEN}SNMPv3 Engine ID detected: $DETECTED_ENGINE_ID${NC}"
        fi
        
        if [ ! -z "$DETECTED_SOURCE_IP" ]; then
            echo -e "\n${GREEN}Source IP detected: $DETECTED_SOURCE_IP${NC}"
        fi
        
        if [ ! -z "$user_info" ]; then
            echo -e "\n${GREEN}SNMPv3 User Information:${NC}"
            echo "$user_info"
        fi
        
        if [ ! -z "$auth_info" ]; then
            echo -e "\n${GREEN}SNMPv3 Authentication Information:${NC}"
            echo "$auth_info"
        fi
    fi
    
    # Clean up the temporary file
    sudo rm -f "$capture_file"
    
    read -p "Did you successfully send the test trap? (y/n): " trap_sent
    if [[ $trap_sent =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Generate recommended configuration
generate_config() {
    local engine_id=$1
    local source_ip=$2
    
    if [ -z "$engine_id" ]; then
        read -p "Enter the SNMPv3 Engine ID (hex format): " engine_id
    fi
    
    if [ -z "$source_ip" ]; then
        read -p "Enter the source IP address of the trap sender: " source_ip
    fi
    
    read -p "Enter the SNMPv3 username: " username
    read -p "Enter the authentication protocol (MD5/SHA): " auth_protocol
    read -sp "Enter the authentication password: " auth_password
    echo
    read -p "Enter the privacy protocol (DES/AES): " priv_protocol
    read -sp "Enter the privacy password: " priv_password
    echo
    
    echo -e "\n${BLUE}Generating recommended snmpd.conf settings...${NC}"
    
    echo -e "\n${GREEN}Recommended SNMPv3 Configuration:${NC}"
    echo "# Add these lines to /etc/snmp/snmpd.conf"
    echo "createUser $username $auth_protocol \"$auth_password\" $priv_protocol \"$priv_password\""
    echo "engineID $engine_id"
    echo "authuser log,execute,net $username"
    echo "rwuser $username"
    
    echo -e "\n${YELLOW}To allow traps from $source_ip, add:${NC}"
    echo "com2sec -Cn trapcomm trapcommunity $source_ip public"
    echo "group trapgroup v3 trapcommunity"
    echo "view trapview included .1"
    echo "access trapgroup \"\" any noauth exact trapview none none"
    
    echo -e "\n${YELLOW}To configure the trap handler, add:${NC}"
    echo "traphandle default /usr/bin/logger -p local0.notice"
    
    echo -e "\n${BLUE}After updating the configuration, restart the SNMP service with:${NC}"
    echo "sudo systemctl restart snmpd"
    
    # Save the configuration to a file
    local config_file="snmpd_recommended.conf"
    {
        echo "# Recommended SNMPv3 Configuration"
        echo "createUser $username $auth_protocol \"$auth_password\" $priv_protocol \"$priv_password\""
        echo "engineID $engine_id"
        echo "authuser log,execute,net $username"
        echo "rwuser $username"
        echo ""
        echo "# Trap configuration"
        echo "com2sec -Cn trapcomm trapcommunity $source_ip public"
        echo "group trapgroup v3 trapcommunity"
        echo "view trapview included .1"
        echo "access trapgroup \"\" any noauth exact trapview none none"
        echo ""
        echo "# Trap handler"
        echo "traphandle default /usr/bin/logger -p local0.notice"
    } > "$config_file"
    
    echo -e "\n${GREEN}Configuration saved to $config_file${NC}"
}

# Test connectivity to trap source
test_connectivity() {
    read -p "Enter the source IP address of the trap sender: " source_ip
    
    echo -e "\n${BLUE}Testing connectivity to $source_ip...${NC}"
    
    if ping -c 3 -W 2 "$source_ip" &>/dev/null; then
        echo -e "${GREEN}Ping to $source_ip successful.${NC}"
    else
        echo -e "${RED}Ping to $source_ip failed.${NC}"
        echo -e "${YELLOW}This might be due to firewall settings or the host being down.${NC}"
    fi
    
    echo -e "\n${BLUE}Checking if SNMP ports are open...${NC}"
    nc -zv -w 2 "$source_ip" 161 &>/dev/null
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}SNMP port 161 is open on $source_ip.${NC}"
    else
        echo -e "${RED}SNMP port 161 is not accessible on $source_ip.${NC}"
    fi
    
    echo -e "\n${BLUE}Checking local SNMP trap port...${NC}"
    if netstat -ulpn 2>/dev/null | grep -q ":1162 "; then
        echo -e "${GREEN}Local SNMP trap port 1162 is open and listening.${NC}"
    else
        echo -e "${RED}Local SNMP trap port 1162 is not listening.${NC}"
        echo -e "${YELLOW}You may need to start the SNMP daemon with trap support on port 1162.${NC}"
    fi
}

# Main program flow
main() {
    check_requirements
    
    display_network_info
    
    echo -e "\n${BLUE}Would you like to test connectivity to the trap sender? (y/n)${NC}"
    read -p "> " test_conn
    if [[ $test_conn =~ ^[Yy]$ ]]; then
        test_connectivity
    fi
    
    echo -e "\n${BLUE}Would you like to capture a test trap? (y/n)${NC}"
    read -p "> " capture
    
    if [[ $capture =~ ^[Yy]$ ]]; then
        if capture_trap; then
            echo -e "\n${GREEN}Test trap captured successfully!${NC}"
            # The global variables DETECTED_ENGINE_ID and DETECTED_SOURCE_IP are set in capture_trap
        else
            echo -e "\n${YELLOW}No valid test trap captured.${NC}"
        fi
    fi
    
    echo -e "\n${BLUE}Would you like to generate recommended SNMPv3 configuration? (y/n)${NC}"
    read -p "> " gen_config
    
    if [[ $gen_config =~ ^[Yy]$ ]]; then
        generate_config "$DETECTED_ENGINE_ID" "$DETECTED_SOURCE_IP"
    fi
    
    echo -e "\n${GREEN}========================================${NC}"
    echo -e "${GREEN}   SNMP Trap Integration Complete!     ${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# Run the main program
main 