@echo off
setlocal enabledelayedexpansion

echo.
echo ============================================================
echo   Kafka Lab -- Recreate Kind Cluster
echo   This will DELETE and recreate the Kind cluster with
echo   correct port mappings for localhost:30080 access.
echo ============================================================
echo.
echo WARNING: This will destroy the existing cluster and all
echo          deployed resources. Press Ctrl+C to cancel.
echo.
pause

:: ── Step 1: Ensure Podman machine is running ─────────────────
echo [1/5] Starting Podman machine...
podman machine start 2>nul
if errorlevel 1 (
    echo       Already running or started.
) else (
    echo       Podman machine started.
)
echo.

:: ── Step 2: Delete existing Kind cluster ─────────────────────
echo [2/5] Deleting existing Kind cluster (kafka-lab)...
set KIND_EXPERIMENTAL_PROVIDER=podman
kind delete cluster --name kafka-lab 2>nul
if errorlevel 1 (
    echo       No existing cluster found, continuing...
) else (
    echo       Cluster deleted.
)
echo.

:: ── Step 3: Create new Kind cluster with port mappings ────────
echo [3/5] Creating new Kind cluster with port mappings...
echo       Using config: kind-config.yaml
echo       NodePort 30080 will be mapped to localhost:30080
echo.
set KIND_EXPERIMENTAL_PROVIDER=podman
kind create cluster --name kafka-lab --config kind-config.yaml
if errorlevel 1 (
    echo.
    echo [ERROR] Failed to create Kind cluster.
    echo         Make sure kind-config.yaml exists in the current directory.
    pause
    exit /b 1
)
echo.

:: ── Step 4: Switch kubectl context ───────────────────────────
echo [4/5] Switching kubectl context to kind-kafka-lab...
kubectl config use-context kind-kafka-lab
echo.

:: ── Step 5: Verify node is Ready ─────────────────────────────
echo [5/5] Waiting for node to be Ready (up to 60 seconds)...
set READY=0
for /L %%i in (1,1,12) do (
    if !READY!==0 (
        kubectl get nodes 2>nul | findstr /C:"Ready" >nul 2>&1
        if !errorlevel!==0 (
            set READY=1
            echo       Node is Ready.
        ) else (
            echo       Not ready yet, waiting 5 seconds... [%%i/12]
            timeout /t 5 /nobreak >nul
        )
    )
)
if !READY!==0 (
    echo [ERROR] Node did not become Ready in time. Check: kubectl get nodes
    pause
    exit /b 1
)
echo.

:: ── Done ─────────────────────────────────────────────────────
echo ============================================================
echo   Kind cluster recreated successfully!
echo.
echo   Next step: Run recover-cluster.bat to deploy
echo   Strimzi, Kafka, Kafka UI and topics.
echo.
echo   After recovery, Kafka UI will be at: http://localhost:30080
echo ============================================================
echo.
pause
