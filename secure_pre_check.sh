#!/bin/bash
# Script to automatically verify SSH access, sudo privileges, disk usage, and outbound connectivity on a list of servers.

USER="root"

# Clear previous outputs and add header to CSV
echo "hostname,ping_status,ssh_status,os_name,os_version,sudo_status,var_log_usage,tmp_usage,outbound_status" > final_status.csv
> sudo_success_status.txt
> sudo_failed_status.txt
> ssh_failed_status.txt
> ssh_failed_status1.txt

# Iterate over all servers listed in server.txt
for SERVER in $(cat server.txt); do
    [[ -z "$SERVER" || "$SERVER" =~ ^# ]] && continue

    echo "🔍 Checking $SERVER..."

    ping_status=$(ping -c 1 "$SERVER" &>/dev/null && echo "success" || echo "fail")

    if [[ "$ping_status" == "success" ]]; then
        ssh_status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$USER@$SERVER" "echo ok" 2>/dev/null)

        if [[ "$ssh_status" == "ok" ]]; then
            os_name=$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$USER@$SERVER" "source /etc/os-release && echo \$ID" 2>/dev/null)
            os_version=$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$USER@$SERVER" "source /etc/os-release && echo \$VERSION_ID" 2>/dev/null)
            sudo_status=$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$USER@$SERVER" "sudo -nv" &>/dev/null && echo "ok" || echo "not_ok")

            # Disk usage for /var/log and /tmp
            var_log_usage=$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$USER@$SERVER" "df -h /var/log | awk 'NR==2 {print \$5}'" 2>/dev/null)
            tmp_usage=$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$USER@$SERVER" "df -h /tmp | awk 'NR==2 {print \$5}'" 2>/dev/null)

            # Outbound test
            if [[ "$os_name" == "rhel" ]]; then
                target_ip="10.137.3.90"
                target_port=80
            elif [[ "$os_name" == "ubuntu" ]]; then
                target_ip="10.136.219.148"
                target_port=8081
            fi

            if [[ -n "$target_ip" && -n "$target_port" ]]; then
                outbound_status=$(ssh "$USER@$SERVER" "timeout 3 bash -c '</dev/tcp/${target_ip}/${target_port}' && echo Repo Reachable || echo Repo Not Reachable" 2>/dev/null)
            else
                outbound_status="unknown"
            fi

            echo "$SERVER,$ping_status,$ssh_status,$os_name,$os_version,$sudo_status,$var_log_usage,$tmp_usage,$outbound_status" >> final_status.csv

            if [[ "$sudo_status" == "ok" ]]; then
                echo "$SERVER : $os_name $os_version : $USER sudo access ok" >> sudo_success_status.txt
            else
                echo "$SERVER : $os_name $os_version : $USER sudo access not ok" >> sudo_failed_status.txt
            fi
        else
            if timeout 3 bash -c "</dev/tcp/$SERVER/22" 2>/dev/null; then
                echo "$SERVER,$ping_status,ssh_key_issue,,,,,," >> final_status.csv
                echo "$SERVER : ping success : SSH port open : SSH key issue" >> ssh_failed_status.txt
            else
                echo "$SERVER,$ping_status,ssh_port_closed,,,,,," >> final_status.csv
                echo "$SERVER : ping success : SSH port not open" >> ssh_failed_status1.txt
            fi
        fi
    else
        if timeout 2 bash -c "</dev/tcp/$SERVER/22" 2>/dev/null; then
            ssh_status=$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$USER@$SERVER" "echo ok" 2>/dev/null)

            if [[ "$ssh_status" == "ok" ]]; then
                os_name=$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$USER@$SERVER" "source /etc/os-release && echo \$ID" 2>/dev/null)
                os_version=$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$USER@$SERVER" "source /etc/os-release && echo \$VERSION_ID" 2>/dev/null)
                sudo_status=$(ssh -o BatchMode=yes -o ConnectTimeout=3 "$USER@$SERVER" "sudo -nv" &>/dev/null && echo "sudo ok" || echo "sudo not_ok")

                var_log_usage=$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$USER@$SERVER" "df -h /var/log | awk 'NR==2 {print \$5}'" 2>/dev/null)
                tmp_usage=$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$USER@$SERVER" "df -h /tmp | awk 'NR==2 {print \$5}'" 2>/dev/null)

                if [[ "$os_name" == "rhel" ]]; then
                    target_ip="10.137.3.90"
                    target_port=80
                elif [[ "$os_name" == "ubuntu" ]]; then
                    target_ip="10.136.219.148"
                    target_port=8081
                fi

                if [[ -n "$target_ip" && -n "$target_port" ]]; then
                    outbound_status=$(ssh -o BatchMode=yes -o ConnectTimeout=2 "$USER@$SERVER" "timeout 3 bash -c '</dev/tcp/${target_ip}/${target_port}' && echo Repo Reachable || echo Repo Not Reachable" 2>/dev/null)
                else
                    outbound_status="unknown"
                fi

                echo "$SERVER,$ping_status,$ssh_status,$os_name,$os_version,$sudo_status,$var_log_usage,$tmp_usage,$outbound_status" >> final_status.csv

                if [[ "$sudo_status" == "ok" ]]; then
                    echo "$SERVER : ping failed : $os_name $os_version : $USER sudo access ok" >> sudo_success_status.txt
                else
                    echo "$SERVER : ping failed : $os_name $os_version : $USER sudo access not ok" >> sudo_failed_status.txt
                fi
            else
                echo "$SERVER,$ping_status,ssh_key_issue,,,,,," >> final_status.csv
                echo "$SERVER : ping failed : SSH port open : SSH key issue" >> ssh_failed_status1.txt
            fi
        else
            echo "$SERVER,$ping_status,ssh_port_closed,,,,,," >> final_status.csv
            echo "$SERVER : ping failed : SSH port not open" >> ssh_failed_status1.txt
        fi
    fi
done
