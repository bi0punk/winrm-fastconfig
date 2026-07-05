# winrm-fastconfig

PowerShell script to quickly enable or disable WinRM on Windows machines, preparing them for Ansible or other remote management tools.

[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/tu-usuario/winrm-fastconfig/actions/workflows/ci.yml/badge.svg)](https://github.com/tu-usuario/winrm-fastconfig/actions/workflows/ci.yml)

## Tabla de Contenidos

- [Características](#características)
- [Stack](#stack)
- [Arquitectura](#arquitectura)
- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Uso](#uso)
- [Tests](#tests)
- [Configuración](#configuración)
- [CI](#ci)
- [Limitaciones / Roadmap](#limitaciones--roadmap)
- [Licencia](#licencia)

## Características

- Activación de WinRM con un solo comando
- Puerto HTTP configurable (default 5985)
- Soporte para HTTPS con certificado auto-firmado
- Creación automática de reglas de firewall
- Modo rollback completo (`-Disable`)
- Idempotente (skip si ya configurado, `-Force` para re-aplicar)

## Stack

- PowerShell 5.1+

## Arquitectura

```
winrm-fastconfig/
├── activar_winrm.ps1   # Script principal
├── tests/
├── .env.example
├── .github/workflows/ci.yml
└── README.md
```

## Requisitos

- Windows 10/11 o Windows Server 2016+
- PowerShell ejecutado como Administrador

## Instalación

```powershell
git clone https://github.com/tu-usuario/winrm-fastconfig.git
cd winrm-fastconfig
```

## Uso

```powershell
# Habilitar WinRM en HTTP (puerto 5985)
.\activar_winrm.ps1

# Habilitar con HTTPS (certificado auto-firmado)
.\activar_winrm.ps1 -EnableHttps

# Habilitar con puerto personalizado
.\activar_winrm.ps1 -Port 5986

# Deshabilitar / rollback
.\activar_winrm.ps1 -Disable
```

## Tests

```powershell
# PSScriptAnalyzer (lint)
Install-Module -Name PSScriptAnalyzer -Force
Invoke-ScriptAnalyzer -Path . -Recurse
```

## Configuración

| Parámetro      | Default | Descripción                           |
|----------------|---------|---------------------------------------|
| `-Port`        | 5985    | Puerto WinRM                          |
| `-EnableHttps` | false   | Configurar HTTPS con certificado      |
| `-Disable`     | false   | Deshabilitar WinRM y limpiar reglas   |
| `-Force`       | false   | Re-aplicar configuración existente    |

## CI

GitHub Actions ejecuta PSScriptAnalyzer lint en Windows latest en cada push y PR.

## Limitaciones / Roadmap

- [ ] Soporte para configuraciones de Kerberos
- [ ] Integración con DSC (Desired State Configuration)
- [ ] Tests con Pester

## Licencia

MIT
