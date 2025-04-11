#!/bin/bash

USERNAME="root"
OUTPUT_FILE="precheck_results.csv"
SERVER_LIST="server.txt"

echo "IP,Reachability,Port 22,SSH,Sudo,OS,OS Version,Outbound Test Target (IP:Port),Outbound Connectivity Result,/var/log,/tmp,Error" > "$OUTPUT_FILE"

check_server() {
    local ip="$1"
    local reachability="Reachable"
    local port_22="Open"
    local ssh="Accessible"
    local sudo="N/A"
    local os="N/A"
    local os_version="N/A"
    local check_target="N/A"
    local target_status="N/A"
    local varlog="N/A"
    local tmpdir="N/A"
    local error=""

    # Ping check
    ping -c 1 "$ip" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        reachability="Not Reachable"
        echo "$ip,$reachability,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A" >> "$OUTPUT_FILE"
        return
    fi

    # Port 22 check
    nc -z -w 3 "$ip" 22 > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        port_22="Closed"
        ssh="Not Accessible"
        echo "$ip,$reachability,$port_22,$ssh,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A" >> "$OUTPUT_FILE"
        return
    fi

    # SSH commands
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$USERNAME@$ip" "exit" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        ssh="Not Accessible"
        echo "$ip,$reachability,$port_22,$ssh,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A" >> "$OUTPUT_FILE"
        return
    fi

    # Check sudo access
    ssh "$USERNAME@$ip" "sudo -n true" > /dev/null 2>&1
    [ $? -eq 0 ] && sudo="Sudo Access" || sudo="No Sudo Access"

    # Get OS and Version
    os_data=$(ssh "$USERNAME@$ip" "source /etc/os-release && echo \$ID,\$VERSION_ID" 2>/dev/null)
    os=$(echo "$os_data" | cut -d',' -f1)
    os_version_raw=$(echo "$os_data" | cut -d',' -f2)
    os_version=$(echo "$os_version_raw" | cut -d'.' -f1)

    # Port check based on OS
    if [[ "$os" == "rhel" ]]; then
        check_target="10.137.3.90:80"
        target_ip="10.137.3.90"
        target_port=80
    elif [[ "$os" == "ubuntu" ]]; then
        check_target="10.136.219.148:8081"
        target_ip="10.136.219.148"
        target_port=8081
    fi

    if [[ -n "$target_ip" && -n "$target_port" ]]; then
        port_check_cmd="timeout 3 bash -c '</dev/tcp/${target_ip}/${target_port}' && echo Reachable || echo Not Reachable"
        target_status=$(ssh "$USERNAME@$ip" "$port_check_cmd" 2>/dev/null)
    fi

    # Disk checks
    varlog=$(ssh "$USERNAME@$ip" "df -BM /var/log | tail -1 | awk '{print \$4}'" 2>/dev/null)
    tmpdir=$(ssh "$USERNAME@$ip" "df -BM /tmp | tail -1 | awk '{print \$4}'" 2>/dev/null)

    # Write to CSV
    echo "$ip,$reachability,$port_22,$ssh,$sudo,$os,$os_version,$check_target,$target_status,${varlog:-N/A},${tmpdir:-N/A},$error" >> "$OUTPUT_FILE"
}

export -f check_server
export USERNAME OUTPUT_FILE

# Run checks in parallel
cat "$SERVER_LIST" | xargs -P 10 -n 1 -I {} bash -c "check_server {}"
