#!/bin/bash

# Color codes for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Print script header
echo -e "${BLUE}==================================================${NC}"
echo -e "${GREEN}     SNMPv3 Engine ID Extraction Tool${NC}"
echo -e "${BLUE}==================================================${NC}"
echo -e "This script helps extract Engine IDs from SNMPv3 trap PCAPs"
echo -e ""

# Function to list PCAP files in the current directory
list_pcap_files() {
    echo -e "${YELLOW}Available PCAP files:${NC}"
    pcap_files=($(find . -maxdepth 1 -name "*.pcap"))
    
    if [ ${#pcap_files[@]} -eq 0 ]; then
        echo -e "${RED}No PCAP files found in the current directory.${NC}"
        exit 1
    fi
    
    for i in "${!pcap_files[@]}"; do
        echo -e "  ${GREEN}$((i+1))${NC}. ${pcap_files[$i]#./}"
    done
    
    return 0
}

# Function to extract engine ID using tcpdump
extract_engine_id_hex() {
    local pcap_file=$1
    
    echo -e "\n${BLUE}Analyzing PCAP file using hex dump analysis...${NC}"
    
    # Extract the raw SNMP packet data
    hex_output=$(tcpdump -r "$pcap_file" -X 2>/dev/null)
    
    # Look for the engine ID pattern in the hex output
    # The engine ID typically follows the SNMP version 3 header
    if [[ $hex_output == *"CEadmin"* ]]; then
        # The engine ID is typically found near the username (NCEadmin)
        # Extract 30 bytes around the username mention
        engine_block=$(echo "$hex_output" | grep -B 2 -A 2 "CEadmin")
        
        # Output the raw block for manual analysis
        echo -e "${YELLOW}Found potential engine ID block:${NC}"
        echo "$engine_block"
        
        # Try to extract the engine ID based on the known format
        # Engine ID usually starts with 04 09 (type and length)
        engine_id=$(echo "$engine_block" | grep -o "04 09 [0-9a-f ]\{20,30\}" | head -1)
        
        if [ -n "$engine_id" ]; then
            # The engine ID value starts after the 04 09 prefix
            engine_id_value=${engine_id:6}
            echo -e "\n${GREEN}Extracted Engine ID:${NC} ${engine_id_value}"
        else
            echo -e "\n${YELLOW}Engine ID could not be automatically extracted.${NC}"
            echo -e "Please examine the hex block above and look for a byte sequence starting"
            echo -e "with 04 09 followed by the engine ID (typically 9 bytes)."
        fi
    else
        echo -e "${RED}Could not find SNMP user information in the PCAP.${NC}"
        echo -e "Try using a different method or manually inspect the file."
    fi
}

# Function to extract engine ID using tshark with specific decoding options
extract_engine_id_tshark() {
    local pcap_file=$1
    local username=$2
    local auth_protocol=$3
    local auth_password=$4
    local priv_protocol=$5
    local priv_password=$6
    
    echo -e "\n${BLUE}Attempting to decode SNMP trap with tshark...${NC}"
    
    # Check if tshark is installed
    if ! command -v tshark &> /dev/null; then
        echo -e "${RED}tshark command not found. Please install Wireshark tools.${NC}"
        return 1
    fi
    
    # Define the SNMP decode preferences
    snmp_user_config="snmp.users:[username=$username,auth=$auth_protocol,auth.password=$auth_password,priv=$priv_protocol,priv.password=$priv_password]"
    
    # Try to extract the engine ID using tshark
    engine_id=$(tshark -r "$pcap_file" -o "$snmp_user_config" -T fields -e snmp.engineID 2>/dev/null)
    
    if [ -n "$engine_id" ]; then
        echo -e "${GREEN}Successfully extracted Engine ID:${NC} $engine_id"
        return 0
    else
        echo -e "${YELLOW}tshark could not extract the Engine ID.${NC}"
        echo -e "Falling back to basic analysis..."
        extract_engine_id_hex "$pcap_file"
        return 1
    fi
}

# Main script starts here
list_pcap_files

# Ask user to select a PCAP file
echo -e "\n${BLUE}Please select a PCAP file by number:${NC}"
read -r file_number

# Validate input
if ! [[ "$file_number" =~ ^[0-9]+$ ]] || [ "$file_number" -lt 1 ] || [ "$file_number" -gt "${#pcap_files[@]}" ]; then
    echo -e "${RED}Invalid selection. Please run the script again.${NC}"
    exit 1
fi

selected_pcap="${pcap_files[$((file_number-1))]}"
echo -e "${GREEN}Selected:${NC} ${selected_pcap#./}"

# Ask if the user wants to try automatic extraction first
echo -e "\n${BLUE}Do you want to try automatic extraction first? (y/n)${NC}"
read -r auto_extract

if [[ "$auto_extract" =~ ^[Yy]$ ]]; then
    extract_engine_id_hex "$selected_pcap"
    
    echo -e "\n${BLUE}Do you want to try decryption with full parameters? (y/n)${NC}"
    read -r try_decrypt
    
    if [[ ! "$try_decrypt" =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Extraction completed.${NC}"
        exit 0
    fi
fi

# Get SNMPv3 parameters from user
echo -e "\n${BLUE}Please provide SNMPv3 parameters for decryption:${NC}"

# Username
echo -e "${YELLOW}Enter username (default: NCEadmin):${NC}"
read -r username
username=${username:-NCEadmin}

# Authentication protocol
echo -e "${YELLOW}Select authentication protocol:${NC}"
echo -e "  ${GREEN}1${NC}. MD5"
echo -e "  ${GREEN}2${NC}. SHA"
echo -e "  ${GREEN}3${NC}. SHA-224"
echo -e "  ${GREEN}4${NC}. SHA-256"
echo -e "  ${GREEN}5${NC}. SHA-384"
echo -e "  ${GREEN}6${NC}. SHA-512"
read -r auth_protocol_num

case "$auth_protocol_num" in
    1) auth_protocol="MD5" ;;
    2) auth_protocol="SHA" ;;
    3) auth_protocol="SHA-224" ;;
    4) auth_protocol="SHA-256" ;;
    5) auth_protocol="SHA-384" ;;
    6) auth_protocol="SHA-512" ;;
    *) auth_protocol="SHA" ;;
esac

# Authentication password
echo -e "${YELLOW}Enter authentication password:${NC}"
read -r auth_password

# Privacy protocol
echo -e "${YELLOW}Select privacy protocol:${NC}"
echo -e "  ${GREEN}1${NC}. DES"
echo -e "  ${GREEN}2${NC}. AES"
echo -e "  ${GREEN}3${NC}. AES-192"
echo -e "  ${GREEN}4${NC}. AES-256"
read -r priv_protocol_num

case "$priv_protocol_num" in
    1) priv_protocol="DES" ;;
    2) priv_protocol="AES" ;;
    3) priv_protocol="AES192" ;;
    4) priv_protocol="AES256" ;;
    *) priv_protocol="AES" ;;
esac

# Privacy password
echo -e "${YELLOW}Enter privacy password:${NC}"
read -r priv_password

# Extract the engine ID using the provided parameters
extract_engine_id_tshark "$selected_pcap" "$username" "$auth_protocol" "$auth_password" "$priv_protocol" "$priv_password"

echo -e "\n${GREEN}Engine ID extraction process completed.${NC}"
echo -e "${BLUE}==================================================${NC}"

# Summary
echo -e "\n${BLUE}Summary:${NC}"
echo -e "  File: ${selected_pcap#./}"
echo -e "  Username: $username"
echo -e "  Auth Protocol: $auth_protocol"
echo -e "  Priv Protocol: $priv_protocol"
echo -e "${BLUE}==================================================${NC}"

exit 0 