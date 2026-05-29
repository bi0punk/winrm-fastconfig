# winrm-fastconfig

PowerShell script to quickly enable or disable WinRM on Windows machines to prepare them for Ansible or other remote management.

## Stack

PowerShell

## Usage

```powershell
# Enable WinRM (default HTTP port 5985)
.\activar_winrm.ps1

# Enable with HTTPS (self-signed cert)
.\activar_winrm.ps1 -EnableHttps

# Disable / rollback
.\activar_winrm.ps1 -Disable
```

## Features

- One-command WinRM activation
- Configurable HTTP port (default 5985)
- Basic authentication toggle
- Optional HTTPS with auto-generated self-signed certificate
- Firewall rule creation
- Complete rollback/disable mode
- Idempotent (skip if already configured, `-Force` to re-apply)

## License

MIT
