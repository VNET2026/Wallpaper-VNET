# Deploy_Wallpaper.ps1
# Aplica fondo de pantalla y pantalla de bloqueo corporativo VNET
# Patron A - Script unico, sin reinicio requerido
# Se ejecuta como SYSTEM via ESET PROTECT

# ============================================================
# CONFIGURACION DEL DESPLIEGUE
# Para un nuevo despliegue, cambia solo las lineas marcadas
# con "<< CAMBIAR EN PROXIMO DESPLIEGUE >>"
# ============================================================

$DeployName  = "wallpaper2"                                                                                    # << CAMBIAR EN PROXIMO DESPLIEGUE >> (opcional, para log separado)
$BaseDir     = "C:\ProgramData\VNET"
$WallDir     = "$BaseDir\wallpaper"
$LogDir      = "$BaseDir\logs"

# Imagenes en disco
$WallFile    = "$WallDir\wallpaper.jpg"                                                                      # << CAMBIAR EN PROXIMO DESPLIEGUE >>
$LockFile    = "$WallDir\Salvapantallas.jpg"                                                               # << CAMBIAR EN PROXIMO DESPLIEGUE >>

# URLs en GitHub release v1.0
$WallUrl     = "https://raw.githubusercontent.com/VNET2026/Wallpaper-VNET/main/wallpaper.jpg"                           # << CAMBIAR EN PROXIMO DESPLIEGUE >>
$LockUrl     = "https://raw.githubusercontent.com/VNET2026/Wallpaper-VNET/main/Salvapantallas.jpg"                    # << CAMBIAR EN PROXIMO DESPLIEGUE >>

# ============================================================

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

function Write-Log {
    param([string]$msg)
    if (-not (Test-Path $LogDir)) { New-Item -Path $LogDir -ItemType Directory -Force | Out-Null }
    $ts = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    "$ts - $env:COMPUTERNAME - $msg" | Out-File -Append "$LogDir\deploy_global.log"
    "$ts - $env:COMPUTERNAME - $msg" | Out-File -Append "$LogDir\deploy_$DeployName.log"
}

function Apply-UserSettings {
    param([string]$SID, [string]$ProfilePath, [bool]$LoadHive = $false)

    $hiveCargado = $false

    if ($LoadHive) {
        $hivePath = "$ProfilePath\NTUSER.DAT"
        if (-not (Test-Path $hivePath)) { return }
        try {
            reg load "HKU\$SID" $hivePath 2>$null
            Start-Sleep -Seconds 1
            $hiveCargado = $true
        } catch {
            Write-Log "ADVERTENCIA: No se pudo cargar hive de $ProfilePath"
            return
        }
    }

    try {
        # --- FONDO DE PANTALLA ---
        $desktopPath = "HKU:\$SID\Control Panel\Desktop"
        if (-not (Test-Path $desktopPath)) { New-Item -Path $desktopPath -Force | Out-Null }

        Set-ItemProperty -Path $desktopPath -Name "Wallpaper"      -Value $WallFile -Force
        Set-ItemProperty -Path $desktopPath -Name "WallpaperStyle" -Value "6" -Force
        Set-ItemProperty -Path $desktopPath -Name "TileWallpaper"  -Value "0" -Force

        Write-Log "Fondo de pantalla aplicado a: $ProfilePath"
    } catch {
        Write-Log "ADVERTENCIA: Error aplicando fondo a $ProfilePath : $_"
    } finally {
        if ($hiveCargado) {
            [gc]::Collect()
            Start-Sleep -Seconds 2
            reg unload "HKU\$SID" 2>$null
        }
    }
}

function Descargar-Archivo {
    param([string]$Url, [string]$Destino, [string]$Etiqueta)

    for ($i = 1; $i -le 5; $i++) {
        try {
            Invoke-WebRequest -Uri $Url -OutFile $Destino -UseBasicParsing
            Write-Log "$Etiqueta descargado correctamente en intento $i"
            return $true
        } catch {
            Write-Log "Intento $i fallido para $Etiqueta : $_"
            if ($i -lt 5) {
                $espera = Get-Random -Minimum 10 -Maximum 40
                Start-Sleep -Seconds $espera
            }
        }
    }
    return $false
}

Write-Log "========== INICIO WALLPAPER DEPLOY =========="

# Crear estructura de carpetas con permisos
foreach ($dir in @($BaseDir, $WallDir, $LogDir)) {
    if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
}
icacls $BaseDir /grant "Everyone:(OI)(CI)(F)" /T 2>$null

# Descargar imagen de escritorio
Write-Log "Descargando imagen de escritorio..."
if (-not (Descargar-Archivo -Url $WallUrl -Destino $WallFile -Etiqueta "Wallpaper escritorio")) {
    Write-Log "ERROR: No se pudo descargar imagen de escritorio tras 5 intentos"
    Exit 1
}

# Descargar imagen de pantalla de bloqueo
Write-Log "Descargando imagen de pantalla de bloqueo..."
if (-not (Descargar-Archivo -Url $LockUrl -Destino $LockFile -Etiqueta "Lockscreen")) {
    Write-Log "ERROR: No se pudo descargar imagen de lockscreen tras 5 intentos"
    Exit 1
}

# ============================================================
# PANTALLA DE BLOQUEO - configuracion global via HKLM
# ============================================================
Write-Log "Configurando pantalla de bloqueo con imagen: $LockFile"
try {
    # Metodo 1 - Politica clasica (Windows 10 antiguo)
    $lockPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization"
    if (-not (Test-Path $lockPath)) { New-Item -Path $lockPath -Force | Out-Null }
    Set-ItemProperty -Path $lockPath -Name "LockScreenImage"            -Value $LockFile -Force
    Set-ItemProperty -Path $lockPath -Name "LockScreenOverlaysDisabled" -Value 1 -Force

    # Metodo 2 - PersonalizationCSP (Windows 10/11 versiones recientes)
    $cspPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\PersonalizationCSP"
    if (-not (Test-Path $cspPath)) { New-Item -Path $cspPath -Force | Out-Null }
    Set-ItemProperty -Path $cspPath -Name "LockScreenImagePath"   -Value $LockFile -Force
    Set-ItemProperty -Path $cspPath -Name "LockScreenImageUrl"    -Value $LockFile -Force
    Set-ItemProperty -Path $cspPath -Name "LockScreenImageStatus" -Value 1 -Force

    # Metodo 3 - Pantalla de inicio de sesion (fondo difuminado desactivado)
    $logonPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
    if (-not (Test-Path $logonPath)) { New-Item -Path $logonPath -Force | Out-Null }
    Set-ItemProperty -Path $logonPath -Name "DisableAcrylicBackgroundOnLogon" -Value 1 -Force

    Write-Log "Pantalla de bloqueo e inicio de sesion configuradas correctamente"
} catch {
    Write-Log "ADVERTENCIA: Error configurando pantalla de bloqueo: $_"
}

# ============================================================
# FONDO DE PANTALLA - aplicar a todos los perfiles de usuario
# ============================================================
if (-not (Get-PSDrive -Name HKU -ErrorAction SilentlyContinue)) {
    New-PSDrive -Name HKU -PSProvider Registry -Root HKEY_USERS | Out-Null
}

$perfilesUsuarios = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" |
    Get-ItemProperty |
    Where-Object {
        $_.ProfileImagePath -like "C:\Users\*" -and
        $_.ProfileImagePath -notlike "*systemprofile*" -and
        $_.ProfileImagePath -notlike "*LocalService*" -and
        $_.ProfileImagePath -notlike "*NetworkService*"
    }

$aplicados = 0
foreach ($perfil in $perfilesUsuarios) {
    $sid         = $perfil.PSChildName
    $profilePath = $perfil.ProfileImagePath

    if (Test-Path "HKU:\$sid") {
        Apply-UserSettings -SID $sid -ProfilePath $profilePath -LoadHive $false
    } else {
        Apply-UserSettings -SID $sid -ProfilePath $profilePath -LoadHive $true
    }
    $aplicados++
}

# Aplicar al perfil Default para futuros usuarios nuevos
Write-Log "Aplicando a perfil Default..."
Apply-UserSettings -SID "DEFAULT_TEMP" -ProfilePath "C:\Users\Default" -LoadHive $true

# ============================================================
# REFRESCO INMEDIATO - aplicar sin cerrar sesion
# ============================================================
$explorer = Get-Process "explorer" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($explorer) {
    try {
        $taskRefresh  = New-ScheduledTaskAction -Execute "rundll32.exe" -Argument "user32.dll,UpdatePerUserSystemParameters ,1 ,True"
        $taskTrigger  = New-ScheduledTaskTrigger -AtLogOn
        $taskSettings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 00:01:00

        # Usar SID S-1-5-32-545 = Usuarios/Users en cualquier idioma
        $taskPrincipal = New-ScheduledTaskPrincipal -GroupId "S-1-5-32-545" -RunLevel Limited

        Register-ScheduledTask `
            -TaskName "VNET_RefreshWallpaper" `
            -Action $taskRefresh `
            -Trigger $taskTrigger `
            -Settings $taskSettings `
            -Principal $taskPrincipal `
            -Force | Out-Null

        Start-ScheduledTask -TaskName "VNET_RefreshWallpaper"
        Start-Sleep -Seconds 5
        Unregister-ScheduledTask -TaskName "VNET_RefreshWallpaper" -Confirm:$false -ErrorAction SilentlyContinue
        Write-Log "Refresco de escritorio ejecutado correctamente"
    } catch {
        Write-Log "ADVERTENCIA: No se pudo refrescar escritorio: $_"
    }
}

Write-Log "Total perfiles procesados: $aplicados"
Write-Log "========== WALLPAPER DEPLOY COMPLETADO =========="
Exit 0