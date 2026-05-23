#requires -RunAsAdministrator

<#
.SYNOPSIS
    Activa o desactiva WinRM en equipos Windows (preparación para Ansible, administración remota).
.DESCRIPTION
    Configura el servicio WinRM, autenticación Basic, AllowUnencrypted, reglas de firewall,
    y opcionalmente un listener HTTPS con certificado auto-firmado.
    Ejecutar como Administrador.
.PARAMETER Port
    Puerto HTTP para WinRM (default: 5985).
.PARAMETER BasicAuth
    Habilita autenticación Basic (default: $true).
.PARAMETER AllowUnencrypted
    Permite tráfico sin cifrar para entorno LAN (default: $true).
.PARAMETER EnableHTTPS
    Crea listener HTTPS en 5986 con certificado auto-firmado.
.PARAMETER HTTPSPort
    Puerto HTTPS (default: 5986).
.PARAMETER Disable
    Revierte toda la configuración de WinRM (rollback).
.PARAMETER Force
    Re-aplica la configuración aunque ya esté activa.
.PARAMETER Quiet
    Solo muestra errores; output mínimo.
.EXAMPLE
    .\activar_winrm.ps1
.EXAMPLE
    .\activar_winrm.ps1 -EnableHTTPS -AllowUnencrypted:$false
.EXAMPLE
    .\activar_winrm.ps1 -Disable -Force
#>

[CmdletBinding()]
param(
    [int]   $Port               = 5985,
    [bool]  $BasicAuth          = $true,
    [bool]  $AllowUnencrypted   = $true,
    [switch]$EnableHTTPS,
    [int]   $HTTPSPort          = 5986,
    [switch]$Disable,
    [switch]$Force,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

function Write-Message {
    param([string]$Text, [string]$Color = 'Gray')
    if (-not $Quiet) { Write-Host $Text -ForegroundColor $Color }
}

function Write-Success  { param([string]$Text) Write-Message $Text -Color Green }
function Write-Info     { param([string]$Text) Write-Message $Text -Color Cyan }
function Write-Warn     { param([string]$Text) Write-Message $Text -Color Yellow }
function Write-ErrorMsg { param([string]$Text) Write-Message $Text -Color Red }

# ---------------------------------------------------------------------------
# Get-WinRMState
# ---------------------------------------------------------------------------

function Get-WinRMState {
    $state = [PSCustomObject]@{
        ServiceRunning    = $false
        StartupType       = $null
        BasicAuth         = $false
        AllowUnencrypted  = $false
        HTTPListenerPort  = $null
        HTTPSListenerPort = $null
        FirewallRulesOK   = $false
        Configured        = $false
    }

    $svc = Get-Service WinRM -ErrorAction SilentlyContinue
    if ($svc) {
        $state.ServiceRunning   = $svc.Status -eq 'Running'
        $state.StartupType      = $svc.StartType
    }

    try {
        $auth = Get-Item WSMan:\localhost\Service\Auth\Basic -ErrorAction SilentlyContinue
        $state.BasicAuth = ($auth.Value -eq $true)
    } catch { }

    try {
        $unenc = Get-Item WSMan:\localhost\Service\AllowUnencrypted -ErrorAction SilentlyContinue
        $state.AllowUnencrypted = ($unenc.Value -eq $true)
    } catch { }

    try {
        $listeners = Get-ChildItem WSMan:\localhost\Listener -ErrorAction SilentlyContinue
        foreach ($l in $listeners) {
            $addr = $l | Select-Object -Property *
            if ($addr.Transport -eq 'HTTP')  { $state.HTTPListenerPort  = $addr.Port }
            if ($addr.Transport -eq 'HTTPS') { $state.HTTPSListenerPort = $addr.Port }
        }
    } catch { }

    try {
        $fw = Get-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue
        $state.FirewallRulesOK = ($fw.Count -gt 0)
    } catch { }

    $state.Configured = $state.ServiceRunning -and $state.HTTPListenerPort -eq $Port

    return $state
}

# ---------------------------------------------------------------------------
# Enable-WinRM
# ---------------------------------------------------------------------------

function Enable-WinRM {
    $changed = $false
    $state = Get-WinRMState

    if ($state.ServiceRunning) {
        Write-Message "[SKIP] El servicio WinRM ya está en ejecución." -Color DarkYellow
    } else {
        Write-Info "[INFO] Iniciando servicio WinRM..."
        Set-Service WinRM -StartupType Automatic
        Start-Service WinRM
        $changed = $true
        Write-Success "[OK] Servicio WinRM iniciado."
    }

    if (-not $state.HTTPListenerPort) {
        Write-Info "[INFO] Ejecutando Enable-PSRemoting para crear listener HTTP por defecto..."
        Enable-PSRemoting -Force -SkipNetworkProfileCheck
        $changed = $true
        Write-Success "[OK] Enable-PSRemoting completado."
    } else {
        Write-Message "[SKIP] Listener HTTP ya existe en puerto $($state.HTTPListenerPort)." -Color DarkYellow
    }

    Write-Info "[INFO] Habilitando autenticación Basic..."
    if ($PSVersionTable.PSVersion.Major -ge 5) {
        Set-Item WSMan:\localhost\Service\Auth\Basic $BasicAuth -Force
    } else {
        & winrm set winrm/config/service/auth "@{Basic=`"$BasicAuth`"}"
    }
    if ($state.BasicAuth -ne $BasicAuth) { $changed = $true }
    Write-Success "[OK] Basic Auth = $BasicAuth."

    Write-Info "[INFO] Estableciendo AllowUnencrypted..."
    Set-Item WSMan:\localhost\Service\AllowUnencrypted $AllowUnencrypted -Force
    if ($state.AllowUnencrypted -ne $AllowUnencrypted) { $changed = $true }
    Write-Success "[OK] AllowUnencrypted = $AllowUnencrypted."

    Write-Info "[INFO] Configurando reglas de firewall..."
    $fwGroup = 'Windows Remote Management'
    $existing = Get-NetFirewallRule -DisplayGroup $fwGroup -ErrorAction SilentlyContinue
    $portsHTTP = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $existing -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -eq $Port }

    if (-not $portsHTTP) {
        New-NetFirewallRule -DisplayName "WinRM HTTP ($Port)" -Group $fwGroup `
            -Direction Inbound -Protocol TCP -LocalPort $Port -Action Allow -Profile Domain,Private | Out-Null
        $changed = $true
        Write-Success "[OK] Regla firewall para puerto $Port (HTTP) creada."
    } else {
        Write-Message "[SKIP] Regla firewall HTTP ya existe." -Color DarkYellow
    }

    if ($EnableHTTPS) {
        $portsHTTPS = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $existing -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalPort -eq $HTTPSPort }

        if (-not $portsHTTPS) {
            New-NetFirewallRule -DisplayName "WinRM HTTPS ($HTTPSPort)" -Group $fwGroup `
                -Direction Inbound -Protocol TCP -LocalPort $HTTPSPort -Action Allow -Profile Domain,Private | Out-Null
            $changed = $true
            Write-Success "[OK] Regla firewall para puerto $HTTPSPort (HTTPS) creada."
        } else {
            Write-Message "[SKIP] Regla firewall HTTPS ya existe." -Color DarkYellow
        }

        Write-Info "[INFO] Creando listener HTTPS en puerto $HTTPSPort..."
        $existingHTTPS = Get-ChildItem WSMan:\localhost\Listener -ErrorAction SilentlyContinue |
            Where-Object { $_.Transport -eq 'HTTPS' }

        if (-not $existingHTTPS) {
            $cert = New-SelfSignedCertificate -DnsName "$env:COMPUTERNAME" `
                -CertStoreLocation Cert:\LocalMachine\My -FriendlyName "WinRM HTTPS" `
                -NotAfter (Get-Date).AddYears(5) -ErrorAction Stop
            $thumbprint = $cert.Thumbprint

            $configString = '@{Hostname="' + $env:COMPUTERNAME + '";CertificateThumbprint="' + $thumbprint + '"}'
            & winrm create "winrm/config/Listener?Address=*+Transport=HTTPS" $configString
            $changed = $true
            Write-Success "[OK] Listener HTTPS creado en puerto $HTTPSPort."
        } else {
            Write-Message "[SKIP] Listener HTTPS ya existe." -Color DarkYellow
        }
    }

    if ($changed) {
        Write-Info "[INFO] Reiniciando servicio WinRM para aplicar cambios..."
        Set-Service WinRM -StartupType Automatic
        Restart-Service WinRM -Force
        Write-Success "[OK] Servicio WinRM reiniciado."
    } else {
        Write-Message "[SKIP] Sin cambios — no se requiere reinicio." -Color DarkYellow
    }

    Write-Host ""
    Write-Host "[ESTADO FINAL]" -ForegroundColor Green
    Get-Service WinRM | Format-Table Name, Status, StartType -AutoSize
    Write-Host ""
    Get-ChildItem WSMan:\localhost\Listener | ForEach-Object {
        $props = $_ | Select-Object *
        Write-Host "  Transport : $($props.Transport)  |  Port : $($props.Port)  |  Hostname : $($props.Hostname)" -ForegroundColor Green
    }
    Write-Host ""
    $msg = "[OK] WinRM activado en puerto $Port (HTTP)"
    if ($EnableHTTPS) { $msg += " y $HTTPSPort (HTTPS)" }
    Write-Success "$msg."
}

# ---------------------------------------------------------------------------
# Disable-WinRM
# ---------------------------------------------------------------------------

function Disable-WinRM {
    Write-Warn "[WARN] Revirtiendo configuración de WinRM..."

    Write-Info "[INFO] Deshabilitando autenticación Basic..."
    Set-Item WSMan:\localhost\Service\Auth\Basic $false -Force

    Write-Info "[INFO] Deshabilitando AllowUnencrypted..."
    Set-Item WSMan:\localhost\Service\AllowUnencrypted $false -Force

    Write-Info "[INFO] Eliminando listeners..."
    Get-ChildItem WSMan:\localhost\Listener -ErrorAction SilentlyContinue | ForEach-Object {
        $path = $_.PSPath
        Remove-Item -Path $path -Recurse -Force
        Write-Success "[OK] Listener eliminado: $path"
    }

    Write-Info "[INFO] Eliminando reglas de firewall de WinRM..."
    Get-NetFirewallRule -DisplayGroup 'Windows Remote Management' -ErrorAction SilentlyContinue |
        Remove-NetFirewallRule
    Write-Success "[OK] Reglas de firewall eliminadas."

    Write-Info "[INFO] Deteniendo servicio WinRM..."
    Stop-Service WinRM -Force
    Set-Service WinRM -StartupType Manual -ErrorAction SilentlyContinue
    Write-Success "[OK] Servicio WinRM detenido."

    $certs = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue |
        Where-Object { $_.FriendlyName -eq 'WinRM HTTPS' }
    if ($certs) {
        Write-Info "[INFO] Eliminando certificados auto-firmados de WinRM..."
        $certs | Remove-Item -Force
        Write-Success "[OK] Certificados eliminados."
    }

    Write-Success "[OK] WinRM desactivado completamente."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

try {
    Write-Host "# winrm-fastconfig" -ForegroundColor Cyan
    Write-Host "# https://github.com/drbash/winrm-fastconfig`n" -ForegroundColor DarkGray

    if ($Disable) {
        if (-not $Force) {
            Write-Warn "[?] Esto desactivará WinRM por completo. Usa -Force para confirmar."
            exit 1
        }
        Disable-WinRM
        return
    }

    $state = Get-WinRMState

    if ($state.Configured -and -not $Force) {
        Write-Message "[SKIP] WinRM ya está configurado (puerto $Port). Usa -Force para re-aplicar." -Color DarkYellow
        Write-Host ""
        Get-Service WinRM | Format-Table Name, Status, StartType -AutoSize
        Get-ChildItem WSMan:\localhost\Listener | ForEach-Object {
            $props = $_ | Select-Object *
            Write-Host "  Transport : $($props.Transport)  |  Port : $($props.Port)  |  Hostname : $($props.Hostname)" -ForegroundColor Green
        }
        return
    }

    Enable-WinRM

} catch {
    Write-ErrorMsg "[ERROR] $($_.Exception.Message)"
    Write-ErrorMsg "[ERROR] Línea: $($_.InvocationInfo.ScriptLineNumber)"
    exit 1
}
