# Lightbits Server Maintenance Script

This script manages server maintenance tasks for Lightbits servers, including disabling/enabling servers and Lightbits services.

## Location

The script is located in the GitHub repository:
https://github.com/gagan-lb/lightbits_server_maintenance

## Prerequisites

- `git` installed on the local machine
- `sshpass` installed on the local machine
- SSH access to the target Lightbits servers
- Sudo privileges on the target servers

## Usage

1. Clone the GitHub repository:
   ```
   git clone https://github.com/gagan-lb/lightbits_server_maintenance.git
   ```

2. Change to the repository directory:
   ```
   cd lightbits_server_maintenance
   ```

3. Make the script executable:
   ```
   chmod +x lightbits_server_maintenance.sh
   ```

4. Run the script:
   ```
   ./lightbits_server_maintenance.sh
   ```

5. Follow the on-screen prompts to choose between pre-maintenance and post-maintenance tasks.

## Updating the Script

To update the script to the latest version:

1. Navigate to the repository directory:
   ```
   cd lightbits_server_maintenance
   ```

2. Pull the latest changes:
   ```
   git pull origin main
   ```

## Features

### Pre-Maintenance Tasks

- Connects to a specified Lightbits server
- Retrieves server information (hostname, IP, server name, current state)
- Offers to disable the server if it's currently enabled
- Provides an option to disable and stop Lightbits services

### Post-Maintenance Tasks

- Connects to a specified Lightbits server
- Checks the status of Lightbits services
- Offers to enable and start Lightbits services if they're not running
- Provides an option to enable the server

## Supported Lightbits Services

The script manages the following Lightbits services:

- api-service
- profile-generator
- node-manager
- cluster-manager
- discovery-service
- lightbox-exporter
- upgrade-manager
- etcd

## Security Note

This script uses `sshpass` to automate SSH connections. While convenient, this method is not considered secure for production environments. In production, it's recommended to use SSH keys for authentication instead of passwords.

## Customization

You can modify the script to add or remove services, change the order of operations, or add additional checks as needed for your specific Lightbits environment.

## Troubleshooting

If you encounter issues:

1. Ensure you have the correct hostname, username, and password for the target server.
2. Verify that you have the necessary permissions to perform the requested actions on the server.
3. Check the server's network connectivity and SSH configuration.

For any persistent issues, please contact your system administrator or Lightbits support.
