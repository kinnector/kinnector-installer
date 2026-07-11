# Kinnector Installer

This repository contains setup scripts, package building pipelines, and system configuration templates for deploying Kinnector Agent (`kinnector-agent`) and Kinnector Core (`kinnector-core`) across Linux and Windows systems.

---

## Why this exists

Deploying EDR agents across heterogeneous operating systems requires consistent packaging, daemon initialization, and verification of kernel-level telemetry support. 

Kinnector Installer manages these deployment pipelines by producing standard packages (`.deb`, `.rpm`, `.msi`) and boot configurations (systemd unit files, Windows services, registry keys) that bootstrap the agent securely.

---

## Mental Model and Packaging Flow

```
[ Pre-compiled Binaries ] ──> [ Package Builder (dpkg / rpmbuild / WiX) ] ──> [ Bootstrapping System Service ]
```

The installer verifies environment pre-requisites, creates the required restricted-access paths (e.g. `/var/run/kinnector` with permissions `0o700`), loads policies, registers the agent daemon under the host's service manager, and configures kernel-level telemetry modules.

---

## Supported Package Formats

* **Debian / Ubuntu (`.deb`)**: Packaging definitions assembled via `dpkg-deb`.
* **RHEL / CentOS / Rocky Linux (`.rpm`)**: Assembled using `rpmbuild` spec files.
* **Windows (`.msi`)**: Assembled and configured using the WiX Toolset.

---

## Installation Methods

### 1. Scripted Installation (Linux)
A unified script downloads the pre-compiled agent matching the host architecture, validates kernel BTF support, and registers the systemd unit:

```bash
curl -sSL https://raw.githubusercontent.com/kinnector/kinnector-installer/main/install.sh | sudo bash
```

### 2. Manual Package Installation

#### Debian / Ubuntu
```bash
sudo dpkg -i kinnector-agent_amd64.deb
```

#### RHEL / Rocky Linux
```bash
sudo rpm -i kinnector-agent.rpm
```

---

## Host Operating System & Telemetry Modes

The installer verifies and configures the agent to operate in one of two modes depending on host kernel parameters:

| Distribution | Version | Core Kernel | Primary Telemetry Mode |
| :--- | :--- | :--- | :--- |
| **Ubuntu** | 22.04 LTS, 24.04 LTS | `5.15` / `6.8` | **BPF LSM** (Kernel Inline Enforcement) |
| **Ubuntu** | 20.04 LTS | `5.4` (HWE `5.8+`) | **User-mode Fallback** (Asynchronous) |
| **Debian** | 12 | `6.1` | **BPF LSM** (Kernel Inline Enforcement) |
| **Debian** | 11 | `5.10` | **User-mode Fallback** (Asynchronous) |
| **RHEL / Rocky** | 9.x | `5.14` | **BPF LSM** (Kernel Inline Enforcement) |
| **RHEL / Rocky** | 8.x | `4.18` | **User-mode Fallback** (Asynchronous) |
| **Fedora** | 39+ | `6.5+` | **BPF LSM** (Kernel Inline Enforcement) |

### Telemetry Mode Details

1. **BPF LSM Mode (Kernel Inline)**:
   - **Mechanism**: The kernel pauses executing system calls synchronously to evaluate agent security policies. If a rule is matched, the call is blocked immediately, returning `-EACCES` (Permission Denied).
   - **Security Guarantee**: Eliminates Time-of-Check to Time-of-Use (TOCTOU) race conditions.
   
2. **User-space Fallback Mode (Asynchronous)**:
   - **Mechanism**: System calls are intercepted asynchronously after initiation. The daemon processes telemetry out-of-band and performs containment reactively using signals (`SIGSTOP` or `SIGKILL`).
   - **Mitigation Requirement**: A 2-second cooldown is enforced during installer exit to capture grandchild processes before purging state tracking.