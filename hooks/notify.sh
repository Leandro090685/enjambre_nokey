#!/bin/bash
# hooks/notify.sh — notificador de escritorio PORTABLE para el equipo Nokey.
#   Uso: notify.sh "titulo" "cuerpo"
# Detecta el entorno y dispara la PRIMERA via disponible. Todo best-effort, con timeout;
# nunca falla ni cuelga la sesion. No todos usan WSL: contempla Linux nativo y macOS tambien.
#
# Orden de intento:
#   0) NOKEY_NOTIFY_CMD  — override del dev (recibe titulo y cuerpo como $1 $2)
#   1) macOS             — osascript (display notification)
#   2) WSL -> Windows    — powershell.exe (BurntToast si esta; si no, balloon NotifyIcon)
#   3) Linux nativo GUI  — notify-send (libnotify), si hay DISPLAY/WAYLAND_DISPLAY
#   4) Fallback          — bell de terminal (\a)

title="${1:-Claude Code}"
body="${2:-}"

# 0) Override explicito del desarrollador.
if [ -n "$NOKEY_NOTIFY_CMD" ]; then
    sh -c "$NOKEY_NOTIFY_CMD" _ "$title" "$body" >/dev/null 2>&1 && exit 0
fi

# 1) macOS
if command -v osascript >/dev/null 2>&1; then
    et=${title//\"/\\\"}; eb=${body//\"/\\\"}
    timeout 5 osascript -e "display notification \"$eb\" with title \"$et\"" >/dev/null 2>&1 && exit 0
fi

# 2) WSL -> notificacion en Windows (se chequea antes que notify-send: en WSL no suele haber GUI Linux).
is_wsl=0
if [ -n "$WSL_DISTRO_NAME" ] || grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    is_wsl=1
fi
if [ "$is_wsl" = 1 ] && command -v powershell.exe >/dev/null 2>&1; then
    pt=${title//\'/\'\'}; pb=${body//\'/\'\'}   # escape de comillas simples para PowerShell
    ps_script="\$ErrorActionPreference='SilentlyContinue';
if (Get-Module -ListAvailable -Name BurntToast) {
  Import-Module BurntToast; New-BurntToastNotification -Text '$pt', '$pb';
} else {
  Add-Type -AssemblyName System.Windows.Forms;
  Add-Type -AssemblyName System.Drawing;
  \$n = New-Object System.Windows.Forms.NotifyIcon;
  \$n.Icon = [System.Drawing.SystemIcons]::Information;
  \$n.BalloonTipTitle = '$pt'; \$n.BalloonTipText = '$pb'; \$n.Visible = \$true;
  \$n.ShowBalloonTip(5000); Start-Sleep -Seconds 5; \$n.Dispose();
}"
    # En segundo plano para no bloquear el hook con el balloon (5s) ni el spawn de Windows.
    ( timeout 15 powershell.exe -NoProfile -NonInteractive -Command "$ps_script" >/dev/null 2>&1 & ) >/dev/null 2>&1
    exit 0
fi

# 3) Linux nativo con escritorio (libnotify).
if command -v notify-send >/dev/null 2>&1 && { [ -n "$DISPLAY" ] || [ -n "$WAYLAND_DISPLAY" ]; }; then
    timeout 5 notify-send "$title" "$body" >/dev/null 2>&1 && exit 0
fi

# 4) Fallback universal: bell de terminal.
{ printf '\a' > /dev/tty; } 2>/dev/null || printf '\a'
exit 0
