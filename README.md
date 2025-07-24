# Windows 11 Geolocation Control

> **Interactive PowerShell menu to manage Windows 11 geolocation & sensor settings, network adapters, and public‑IP geolocation checks.**

---

## Table of Contents

1. [Overview](#overview)  
2. [Features](#features)  
3. [Prerequisites](#prerequisites)  
4. [Installation](#installation)  
5. [Usage](#usage)  
6. [Configuration](#configuration)  
7. [How It Works](#how-it-works)  
8. [Menu Options](#menu-options)  
9. [External APIs & References](#external-apis--references)  
10. [License](#license)  

---

## Overview

This PowerShell script provides an interactive menu to:

- Disable/stop Windows geolocation & sensor-related services  
- Disable physical Wi‑Fi adapters  
- Apply registry lockdown for location and sensor settings  
- Check current service, adapter, and registry statuses  
- Query public IP, DNS configuration and lookup geolocation  
- Display detailed documentation links and expected results  

All actions include built‑in verification and colored console output for easy status checks.

---

## Features

- **Granular controls** for services, adapters, registry or any combination  
- **Status checks** after each change (service state, adapter status, registry values)  
- **Public IP & geolocation** lookup (uses [ipify](https://www.ipify.org/) & [ip-api.com](http://ip-api.com))  
- **Interactive menu** with clear prompts and progress bars  
- **Self‑documenting**: option to display detailed change summary with links  

---

## Prerequisites

- **OS**: Windows 11 (should work on Windows 10 but only tested on 11)  
- **Shell**: PowerShell 7+ or Windows PowerShell (≥5.1)  
- **Permissions**: **Must run as Administrator**  
- **Network**: Internet access for public IP/geolocation lookups  

---

## Installation

1. Clone this repository:
   ```powershell
   git clone https://github.com/your‑username/geolocation-control.git
   cd geolocation-control
