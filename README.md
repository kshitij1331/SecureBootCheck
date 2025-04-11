# SecureBootCheck

SecureBootCheck is a lightweight server connectivity and configuration audit tool written in Bash. It performs a series of prechecks on a list of servers including:

- Ping and SSH connectivity
- Sudo access
- OS identification (ID and major version)
- Disk space availability on /var/log and /tmp
- Port connectivity check from the target server to an external IP and port based on OS

## Features

- Works across Linux-based systems (tested on RHEL and Ubuntu)
- Customizes external connectivity checks based on OS type
- Writes results to a CSV file for easy auditing
- Easily parallelizable and automation-ready

## Use Case

Perfect for system administrators, DevOps engineers, or SREs who need to verify infrastructure readiness, perform audits, or pre-checks during onboarding or configuration compliance.

## Prerequisites

- `bash` shell or python installed
- SSH passwordless access (or keys setup)
- Sudo privileges on target servers
- `ping`, `ssh`, `df`, and standard Linux utilities available

## Installation

1. Clone the repository:

```bash
git clone https://github.com/kshitij1331/securebootcheck.git
cd SecureBootCheck
```

2. If using python install requirements:
```bash
pip install -r requirements.txt
```

If using bash make sure the script is executable:
```bash
chmod +x secure_pre_check_.sh
```


## Usage

1. Prepare a file named `server.txt` with one IP per line:

```
10.145.41.103
10.145.41.212
10.145.42.219
```

2. Run the script/code:
BASH:

```bash
./secure_pre_check.sh
```
PYTHON:
```bash
python secure_pre_check.py
```
3. Results will be saved in `precheck_results.csv`.

## Output CSV Format

| IP           | Reachability | Port 22 | SSH            | Sudo        | OS     | OS Version | Outbound Test Target (IP:Port) | Outbound Connectivity Result | /var/log | /tmp   | Error |
|--------------|--------------|---------|----------------|-------------|--------|-------------|-------------------------------------|---------------------------------------------|----------|--------|--------|
| 10.145.41.212 | Reachable   | Open    | Accessible     | Sudo Access | rhel   | 8           | 10.137.3.90:80                     | Reachable                                  | 3455M    | 11141M | N/A    |

## Notes

- The script uses `/dev/tcp` and `timeout` for connectivity checks.
- OS is detected using `/etc/os-release`.
- Script may require slight modifications depending on SSH credentials setup.

