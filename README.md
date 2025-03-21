# cPanel Migration Tool

A Bash-based tool for automating cPanel account migrations between servers with enhanced disk checks, cleanup, and warnings. This tool leverages SSH, sshpass, and Ansible to ensure seamless migration with minimal downtime.

The cPanel Migration Tool automates the process of migrating one or more cPanel accounts from a source server to a target server. It performs thorough disk space checks on both the source and target environments, automatically renames accounts to avoid domain conflicts, and logs every step of the migration process for troubleshooting. Designed for environments where downtime must be minimized, this tool is ideal for system administrators and technical support teams managing cPanel infrastructures.

## Features
- Automated Account Migration: Migrate single, multiple, or all cPanel accounts with one command.
- Enhanced Disk Space Checks: Verifies free disk space on source, jumpbox, and target before proceeding.
- Automatic Account Renaming: Detects conflicts on the target server and renames accounts automatically.
- Ansible Playbook Integration: Uses Ansible to restore migrated accounts reliably.
- Logging: All steps and outputs are logged for later review.

## Requirements
- Linux-based system (CentOS/Ubuntu, etc.)
- cPanel installed on both source and target servers
- SSH access to both servers
- sshpass installed on the system
- Ansible installed (version 2.9 or later recommended)

## Installation
Clone the repository or download the files manually:

    git clone https://github.com/NexteraMatt/cpanel-migration-tool.git

Ensure the necessary packages are installed:

    sudo apt-get install sshpass ansible

## Usage
1. **Configure the Tool**  
   Review and modify thresholds, disk paths, and other parameters in cpanel-migration.sh and cpanel_migration.yml as needed.

2. **Run the Migration**  
   Execute the main script as root:
   
       sudo ./cpanel-migration.sh
   
   Follow the on-screen prompts to enter source and target server details, SSH ports, and passwords (if not using SSH keys).

3. **Check Logs**  
   Migration logs are stored in /var/log/ with a timestamp, providing a record of the migration process for troubleshooting.

## Files
- cpanel-migration.sh – Main migration script that initiates the process.
- cpanel_migration.yml – Ansible playbook for handling the migration.
- migrate_account.yml – Task file used by the playbook for processing each account.
- cpanelmigrationscriptbackup – Backup of a previous version of the script.
- cpanel_migration.yml – Configuration file for the migration process.
- migrateaccbackup / cpanelymlbackup – Backup files for reference.

## Contributing
Contributions, bug reports, and feature requests are welcome! Please open an issue or submit a pull request on GitHub.

## License
This project is licensed under the MIT License. See the LICENSE file for details.
