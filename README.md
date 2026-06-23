# KijaniKiosk Infrastructure Provisioning Script

## Overview

This provisioning script automates the deployment, security hardening, monitoring, and maintenance setup of the **KijaniKiosk platform** on a Linux server.

The script performs the following tasks:

- Creates required system users and groups
- Builds the application directory structure
- Configures secure file permissions and ACLs
- Deploys and hardens systemd services
- Configures firewall rules using UFW
- Enables persistent system logging
- Configures log rotation
- Creates health monitoring files
- Verifies successful deployment

The script is designed to be **idempotent**, meaning it can be safely re-run without creating duplicate users, groups, or directories.

---

