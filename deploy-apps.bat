@echo off
setlocal enabledelayedexpansion

echo.
echo ============================================================
echo   Kafka Lab -- Deploy Apps
echo   Builds Docker images, loads into Kind and deploys to K8s
echo ============================================================
echo.
echo   Select what to deploy:
echo     1. Consumer only
echo     2. Producer only
echo     3. All (Consumer + Producer + KEDA ScaledObject)
echo.
set /p CHOICE="Enter choice [1/2/3]: "

:: ── Validate input ───────────────────────────────────────────
if "%CHOICE%"=="1" goto :set_consumer
if "%CHOICE%"=="2" goto :set_producer
if "%CHOICE%"=="3" goto :set_all
echo.
echo [ERROR] Invalid choice. Please enter 1, 2 or 3.
pause
exit /b 1

:set_consumer
set DEPLOY_CONSUMER=true
set DEPLOY_PRODUCER=false
set DEPLOY_KEDA=false
echo.
echo   Deploying: Consumer only
goto :start
:set_producer
set DEPLOY_CONSUMER=false
set DEPLOY_PRODUCER=true
set DEPLOY_KEDA=false
echo.
echo   Deploying: Producer only
goto :start
:set_all
set DEPLOY_CONSUMER=true
set DEPLOY_PRODUCER=true
set DEPLOY_KEDA=true
echo.
echo   Deploying: Producer + Consumer + KEDA ScaledObject
goto :start

:start
echo.
echo ============================================================

:: ── Step 1: Check kubectl context ────────────────────────────
echo [Step 1] Checking kubectl context...
kubectl config current-context 2>nul | findstr /C:"kind-kafka-lab" >nul
if errorlevel 1 (
    echo       Switching to kind-kafka-lab context...
    kubectl config use-context kind-kafka-lab
    if errorlevel 1 (
        echo [ERROR] Could not switch to kind-kafka-lab context.
        echo         Run .\recreate-cluster.bat first.
        pause
        exit /b 1
    )
) else (
    echo       Context is kind-kafka-lab. OK.
)
echo.

:: ── Step 2: Install KEDA if deploying consumer or all ────────
if "%DEPLOY_KEDA%"=="true" (
    echo [Step 2] Checking KEDA installation...
    kubectl get namespace keda >nul 2>&1
    if errorlevel 1 (
        echo       KEDA not found. Installing via Helm...
        helm repo add kedacore https://kedacore.github.io/charts 2>nul
        helm repo update 2>nul
        helm install keda kedacore/keda --namespace keda --create-namespace
        if errorlevel 1 (
            echo [ERROR] KEDA installation failed. Is Helm installed?
            echo         Run: winget install Helm.Helm
            pause
            exit /b 1
        )
        echo       KEDA installed successfully.
    ) else (
        echo       KEDA already installed. Skipping.
    )
    echo.
)

:: ── Step 3: Build images ──────────────────────────────────────
if "%DEPLOY_PRODUCER%"=="true" (
    echo [Step 3a] Building producer image...
    podman build -t kafka-producer:latest ./producer
    if errorlevel 1 (
        echo [ERROR] Producer image build failed.
        pause
        exit /b 1
    )
    echo       Producer image built successfully.
    echo.
)

if "%DEPLOY_CONSUMER%"=="true" (
    echo [Step 3b] Building consumer image...
    podman build -t kafka-consumer:latest ./consumer
    if errorlevel 1 (
        echo [ERROR] Consumer image build failed.
        pause
        exit /b 1
    )
    echo       Consumer image built successfully.
    echo.
)

:: ── Step 4: Load images into Kind ────────────────────────────
set KIND_EXPERIMENTAL_PROVIDER=podman

if "%DEPLOY_PRODUCER%"=="true" (
    echo [Step 4a] Loading producer image into Kind cluster...
    podman save kafka-producer:latest -o kafka-producer.tar
    kind load image-archive kafka-producer.tar --name kafka-lab
    del kafka-producer.tar
    echo       Producer image loaded.
    echo.
)

if "%DEPLOY_CONSUMER%"=="true" (
    echo [Step 4b] Loading consumer image into Kind cluster...
    podman save kafka-consumer:latest -o kafka-consumer.tar
    kind load image-archive kafka-consumer.tar --name kafka-lab
    del kafka-consumer.tar
    echo       Consumer image loaded.
    echo.
)

:: ── Step 5: Deploy to Kubernetes ─────────────────────────────
if "%DEPLOY_PRODUCER%"=="true" (
    echo [Step 5a] Deploying producer to Kubernetes...
    kubectl apply -f k8s/producer.yaml
    kubectl rollout restart deployment/kafka-producer -n kafka
    echo.
)

if "%DEPLOY_CONSUMER%"=="true" (
    echo [Step 5b] Deploying consumer to Kubernetes...
    kubectl apply -f k8s/consumer.yaml
    kubectl rollout restart deployment/kafka-consumer -n kafka
    echo.
)

if "%DEPLOY_KEDA%"=="true" (
    echo [Step 5c] Applying KEDA ScaledObject...
    kubectl apply -f k8s/keda-scaledobject.yaml
    echo.
)

:: ── Step 6: Wait and verify ───────────────────────────────────
echo [Step 6] Waiting for pods to be Running (up to 60 seconds)...
set READY=0
for /L %%i in (1,1,12) do (
    if !READY!==0 (
        set ALL_RUNNING=true
        if "%DEPLOY_PRODUCER%"=="true" (
            kubectl get pods -n kafka 2>nul | findstr /C:"kafka-producer" | findstr /C:"Running" >nul 2>&1
            if errorlevel 1 set ALL_RUNNING=false
        )
        if "%DEPLOY_CONSUMER%"=="true" (
            kubectl get pods -n kafka 2>nul | findstr /C:"kafka-consumer" | findstr /C:"Running" >nul 2>&1
            if errorlevel 1 set ALL_RUNNING=false
        )
        if "!ALL_RUNNING!"=="true" (
            set READY=1
            echo       Pods are Running.
        ) else (
            echo       Not ready yet, waiting 5 seconds... [%%i/12]
            timeout /t 5 /nobreak >nul
        )
    )
)
echo.

:: ── Step 7: Show status ───────────────────────────────────────
echo [Step 7] Current status:
echo.
kubectl get pods -n kafka
echo.
if "%DEPLOY_KEDA%"=="true" (
    kubectl get scaledobject -n kafka 2>nul
    echo.
)

:: ── Done ─────────────────────────────────────────────────────
echo ============================================================
echo   Deployment complete!
echo.
if "%DEPLOY_PRODUCER%"=="true" (
    echo   Producer logs : kubectl logs -n kafka deployment/kafka-producer -f
)
if "%DEPLOY_CONSUMER%"=="true" (
    echo   Consumer logs : kubectl logs -n kafka deployment/kafka-consumer -f
)
if "%DEPLOY_KEDA%"=="true" (
    echo   Autoscaling   : kubectl get scaledobject -n kafka -w
)
echo ============================================================
echo.
pause
