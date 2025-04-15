import paramiko
import logging
import csv
import os
import socket
import subprocess
from concurrent.futures import ProcessPoolExecutor, as_completed

# Configure logging
log_file_path = "precheck.log"
logging.basicConfig(level=logging.INFO,
                    format='%(asctime)s - %(levelname)s - %(message)s',
                    handlers=[logging.FileHandler(log_file_path)])

global_username = "root"

def read_server_list(file_path):
    with open(file_path, 'r') as file:
        return [line.strip() for line in file.readlines()]

def ping_server(ip):
    response = os.system(f"ping -n 1 {ip}" if os.name == "nt" else f"ping -c 1 {ip}")
    return response == 0

def check_ssh_port_22(ip):
    try:
        with socket.create_connection((ip, 22), timeout=5):
            return True
    except:
        return False

def check_ssh_connectivity(ip):
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(ip, username=global_username, timeout=5)
        ssh.close()
        return True
    except Exception as e:
        logging.error(f"SSH connection failed for {ip}: {e}")
        return False

def open_ssh_session(ip):
    try:
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(ip, username=global_username, timeout=5)
        return ssh
    except Exception as e:
        logging.error(f"Failed to open SSH session for {ip}: {e}")
        return None

def check_sudo_access(ssh):
    try:
        stdin, stdout, stderr = ssh.exec_command("sudo -n true")
        return stdout.channel.recv_exit_status() == 0
    except:
        return False

def get_disk_space(ssh, path):
    try:
        stdin, stdout, stderr = ssh.exec_command(f"df -BM {path} | tail -1 | awk '{{print $4}}'")
        return stdout.read().decode().strip() or "N/A"
    except:
        return "N/A"

def get_os(ssh):
    try:
        stdin, stdout, stderr = ssh.exec_command("cat /etc/os-release | grep -E '^(ID|VERSION_ID)='")
        os_info = stdout.read().decode().strip().split("\n")
        os_name, os_version = "Unknown", "Unknown"
        for line in os_info:
            if line.startswith("ID="):
                os_name = line.split("=")[1].replace('"', '').strip()
            elif line.startswith("VERSION_ID="):
                os_version_raw = line.split("=")[1].replace('"', '').strip()
                os_version = os_version_raw.split(".")[0]
        return os_name, os_version
    except:
        return "Unknown", "Unknown"

def check_port_from_target(ssh, target_ip, target_port):
    try:
        cmd = f"timeout 3 bash -c '</dev/tcp/{target_ip}/{target_port}' && echo Reachable || echo Not Reachable"
        stdin, stdout, stderr = ssh.exec_command(cmd)
        return stdout.read().decode().strip()
    except Exception as e:
        return f"Error: {e}"

def check_server(ip):
    result = {
        'IP': ip,
        'Reachability': 'N/A',
        'Port 22': 'N/A',
        'SSH': 'N/A',
        'Sudo': 'N/A',
        'OS': 'N/A',
        'OS Version': 'N/A',
        'Outbound Test Target (IP:Port)': 'N/A',
        'Outbound Connectivity Result': 'N/A',
        '/var/log': 'N/A',
        '/tmp': 'N/A',
        'Error': ''
    }

    try:
        result['Reachability'] = 'Reachable' if ping_server(ip) else 'Not Reachable'
    except Exception as e:
        result['Error'] += f"Ping failed: {e} | "

    try:
        result['Port 22'] = 'Open' if check_ssh_port_22(ip) else 'Closed'
    except Exception as e:
        result['Error'] += f"Port 22 check failed: {e} | "

    ssh_accessible = False
    try:
        ssh_accessible = check_ssh_connectivity(ip)
        result['SSH'] = 'Accessible' if ssh_accessible else 'Not Accessible'
    except Exception as e:
        result['Error'] += f"SSH connectivity check failed: {e} | "

    ssh = open_ssh_session(ip) if ssh_accessible else None

    if ssh:
        try:
            result['Sudo'] = 'Sudo Access' if check_sudo_access(ssh) else 'No Sudo Access'
        except Exception as e:
            result['Error'] += f"Sudo check failed: {e} | "

        try:
            os_name, os_version = get_os(ssh)
            result['OS'] = os_name
            result['OS Version'] = os_version
        except Exception as e:
            result['Error'] += f"OS detection failed: {e} | "

        try:
            if result['OS'] == 'rhel':
                target_ip = '10.137.3.90'
                target_port = 80
            elif result['OS'] == 'ubuntu':
                target_ip = '10.136.219.148'
                target_port = 8081
            else:
                target_ip, target_port = None, None

            if target_ip and target_port:
                result['Outbound Test Target (IP:Port)'] = f"{target_ip}:{target_port}"
                outbound_result = check_port_from_target(ssh, target_ip, target_port)
                result['Outbound Connectivity Result'] = "Reachable" if "Reachable" in outbound_result else "Not Reachable"
        except Exception as e:
            result['Error'] += f"Outbound port check failed: {e} | "

        try:
            result['/var/log'] = get_disk_space(ssh, '/var/log')
        except Exception as e:
            result['Error'] += f"/var/log space check failed: {e} | "

        try:
            result['/tmp'] = get_disk_space(ssh, '/tmp')
        except Exception as e:
            result['Error'] += f"/tmp space check failed: {e} | "

        ssh.close()

    return result

def precheck_utility(servers, log_file):
    results = []
    max_workers = min(32, os.cpu_count() * 2)

    with ProcessPoolExecutor(max_workers=max_workers) as executor:
        future_to_server = {executor.submit(check_server, server): server for server in servers}
        for future in as_completed(future_to_server):
            results.append(future.result())

    fieldnames = ['IP', 'Reachability', 'Port 22', 'SSH', 'Sudo', 'OS', 'OS Version',
                  'Outbound Test Target (IP:Port)', 'Outbound Connectivity Result',
                  '/var/log', '/tmp', 'Error']

    with open(log_file, 'w', newline='') as csvfile:
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        writer.writeheader()
        for result in results:
            writer.writerow({key: result.get(key, 'N/A') for key in fieldnames})

if __name__ == '__main__':
    servers = read_server_list('server.txt')
    log_file = 'precheck_results.csv'
    precheck_utility(servers, log_file)
