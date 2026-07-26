@echo off
setlocal enabledelayedexpansion

echo.
echo ============================================================
echo   Kafka Lab -- Cluster Recovery
echo ============================================================
echo.

:: ── Step 1: Start Podman machine ─────────────────────────────
echo [1/11] Starting Podman machine...
podman machine start 2>nul
if errorlevel 1 (
    echo       Already running or started.
) else (
    echo       Podman machine started.
)
echo.

:: ── Step 2: Start Kind node container ────────────────────────
echo [2/11] Starting Kind node container (kafka-lab-control-plane)...
podman start kafka-lab-control-plane
if errorlevel 1 (
    echo.
    echo [ERROR] Could not start Kind node container.
    echo         Run: .\recreate-cluster.bat
    pause
    exit /b 1
)
echo.

:: ── Step 3: Switch kubectl context ───────────────────────────
echo [3/11] Switching kubectl context to kind-kafka-lab...
kubectl config use-context kind-kafka-lab
echo.

:: ── Step 4: Wait for node to be Ready ────────────────────────
echo [4/11] Waiting for node to be Ready (up to 60 seconds)...
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

:: ── Step 5: Create Kafka namespace ───────────────────────────
echo [5/11] Applying Kafka namespace...
kubectl apply -f kafka-namespace.yaml
echo.

:: ── Step 6: Install Strimzi Operator ─────────────────────────
echo [6/11] Installing Strimzi Operator...
kubectl apply -f https://strimzi.io/install/latest?namespace=kafka -n kafka 2>nul
echo       (Warnings about existing resources are normal on re-deploy)
echo.

:: ── Step 7: Wait for Strimzi operator to be Running ──────────
echo [7/11] Waiting for Strimzi operator pod to be Running (up to 3 minutes)...
set READY=0
for /L %%i in (1,1,18) do (
    if !READY!==0 (
        kubectl get pods -n kafka 2>nul | findstr /C:"strimzi-cluster-operator" | findstr /C:"Running" >nul 2>&1
        if !errorlevel!==0 (
            set READY=1
            echo       Strimzi operator is Running.
        ) else (
            echo       Not ready yet, waiting 10 seconds... [%%i/18]
            timeout /t 10 /nobreak >nul
        )
    )
)
if !READY!==0 (
    echo [ERROR] Strimzi operator did not start in time. Check: kubectl get pods -n kafka
    pause
    exit /b 1
)
echo.

:: ── Step 8: Deploy Kafka cluster and Kafka UI ────────────────
echo [8/11] Deploying Kafka cluster and Kafka UI...
kubectl apply -f kafka.yaml
kubectl apply -f kafka-ui.yaml
echo.

:: ── Step 9: Wait for Kafka cluster to be Ready ───────────────
echo [9/11] Waiting for Kafka cluster to be Ready (up to 5 minutes)...
set READY=0
for /L %%i in (1,1,30) do (
    if !READY!==0 (
        kubectl get kafka my-cluster -n kafka 2>nul | findstr /C:"True" >nul 2>&1
        if !errorlevel!==0 (
            set READY=1
            echo       Kafka cluster is Ready.
        ) else (
            echo       Not ready yet, waiting 10 seconds... [%%i/30]
            timeout /t 10 /nobreak >nul
        )
    )
)
if !READY!==0 (
    echo [ERROR] Kafka cluster did not become Ready in time.
    echo         Check: kubectl get kafka my-cluster -n kafka
    echo         Check: kubectl get pods -n kafka
    pause
    exit /b 1
)
echo.

:: ── Step 10: Deploy Kafka topic ──────────────────────────────
echo [10/11] Deploying Kafka topic...
kubectl apply -f kafka-topic.yaml
echo.

:: ── Step 11: Verify all resources ────────────────────────────
echo [11/11] Verifying deployed resources...
echo.
kubectl get kafka,kafkanodepool,kafkatopic,pods,svc,pvc -n kafka
echo.

:: ── Done ─────────────────────────────────────────────────────
echo ============================================================
echo   Recovery complete!
echo.
echo   Kafka UI is available at: http://localhost:30080
echo   Open it in your browser directly - no port-forward needed.
echo ============================================================
echo.
pause
