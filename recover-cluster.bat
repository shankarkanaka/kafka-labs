@echo off
setlocal enabledelayedexpansion

echo.
echo ============================================================
echo   Kafka Lab -- Cluster Recovery
echo ============================================================
echo.

:: ── Step 1: Start Podman machine ─────────────────────────────
echo [1/9] Starting Podman machine...
podman machine start 2>nul
if errorlevel 1 (
    echo       Already running or started.
) else (
    echo       Podman machine started.
)
echo.

:: ── Step 2: Start Kind node container ────────────────────────
echo [2/9] Starting Kind node container (kafka-lab-control-plane)...
podman start kafka-lab-control-plane
if errorlevel 1 (
    echo.
    echo [ERROR] Could not start Kind node container.
    echo         Run: kind create cluster --name kafka-lab
    pause
    exit /b 1
)
echo.

:: ── Step 3: Switch kubectl context ───────────────────────────
echo [3/9] Switching kubectl context to kind-kafka-lab...
kubectl config use-context kind-kafka-lab
echo.

:: ── Step 4: Wait for node to be Ready ────────────────────────
echo [4/9] Waiting for node to be Ready (up to 60 seconds)...
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
echo [5/9] Applying Kafka namespace...
kubectl apply -f kafka-namespace.yaml
echo.

:: ── Step 6: Install Strimzi Operator ─────────────────────────
echo [6/9] Installing Strimzi Operator...
kubectl create -f https://strimzi.io/install/latest?namespace=kafka -n kafka 2>nul
echo       (Warnings about existing resources are normal on re-deploy)
echo.

:: ── Step 7: Wait for Strimzi operator to be Running ──────────
echo [7/9] Waiting for Strimzi operator pod to be Running (up to 3 minutes)...
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

:: ── Step 8: Deploy Kafka cluster ─────────────────────────────
echo [8/9] Deploying Kafka cluster, Kafka UI and topic...
kubectl apply -f kafka.yaml
kubectl apply -f kafka-ui.yaml
kubectl apply -f kafka-topic.yaml
echo.

:: ── Step 9: Verify all resources ─────────────────────────────
echo [9/9] Verifying deployed resources...
echo.
kubectl get kafka,kafkanodepool,kafkatopic,pods,svc,pvc -n kafka
echo.

:: ── Done ─────────────────────────────────────────────────────
echo ============================================================
echo   Recovery complete!
echo.
echo   Kafka UI will be available at: http://localhost:8080
echo   Run this command to access it:
echo     kubectl port-forward svc/kafka-ui 8080:8080 -n kafka
echo ============================================================
echo.
pause
