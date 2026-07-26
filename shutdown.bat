@echo off
setlocal enabledelayedexpansion

echo.
echo ============================================================
echo   Kafka Lab -- Shutdown
echo   Stops Kind cluster, Podman machine and Podman Desktop
echo ============================================================
echo.

:: ── Step 1: Stop Kafka workloads gracefully ──────────────────
echo [1/4] Stopping Kafka workloads...
kubectl config use-context kind-kafka-lab >nul 2>&1
if errorlevel 1 (
    echo       Could not switch context — skipping workload shutdown.
) else (
    kubectl scale deployment/kafka-producer --replicas=0 -n kafka >nul 2>&1
    kubectl scale deployment/kafka-consumer --replicas=0 -n kafka >nul 2>&1
    echo       Producer and consumer scaled to 0.
)
echo.

:: ── Step 2: Stop the Kind node container ─────────────────────
echo [2/4] Stopping Kind node container (kafka-lab-control-plane)...
podman stop kafka-lab-control-plane >nul 2>&1
if errorlevel 1 (
    echo       Kind node was not running or already stopped.
) else (
    echo       Kind node stopped.
)
echo.

:: ── Step 3: Stop the Podman machine ──────────────────────────
echo [3/4] Stopping Podman machine...
podman machine stop
if errorlevel 1 (
    echo       Podman machine was already stopped.
) else (
    echo       Podman machine stopped.
)
echo.

:: ── Step 4: Quit Podman Desktop ──────────────────────────────
echo [4/4] Quitting Podman Desktop...
tasklist /FI "IMAGENAME eq podman-desktop.exe" 2>nul | findstr /C:"podman-desktop.exe" >nul
if errorlevel 1 (
    echo       Podman Desktop is not running.
) else (
    taskkill /IM podman-desktop.exe /F >nul 2>&1
    echo       Podman Desktop closed.
)
echo.

:: ── Done ─────────────────────────────────────────────────────
echo ============================================================
echo   Shutdown complete!
echo.
echo   To resume later, run:
echo     .\recover-cluster.bat
echo ============================================================
echo.
pause
