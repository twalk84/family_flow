@echo off
REM ============================================================================
REM FAMILYFLOW BACKEND - GOOGLE CLOUD RUN DEPLOYMENT SCRIPT (Windows)
REM ============================================================================
REM This script deploys your backend to Google Cloud Run.
REM 
REM PREREQUISITES:
REM 1. Google Cloud SDK installed (https://cloud.google.com/sdk/docs/install)
REM 2. Run "gcloud init" and log in to your Google account
REM 3. Have your Anthropic API key ready
REM ============================================================================

echo.
echo ============================================================
echo FAMILYFLOW CLOUD RUN DEPLOYMENT
echo ============================================================
echo.

REM Check if gcloud is installed
where gcloud >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo ERROR: Google Cloud SDK not found!
    echo.
    echo Please install it from: https://cloud.google.com/sdk/docs/install
    echo Then run: gcloud init
    pause
    exit /b 1
)

REM Set variables - EDIT THESE
set PROJECT_ID=familyflow-backend
set SERVICE_NAME=familyflow-assistant
set REGION=us-central1

REM Prompt for API key
echo.
set /p ANTHROPIC_KEY="Enter your Anthropic API key (sk-ant-...): "

if "%ANTHROPIC_KEY%"=="" (
    echo ERROR: API key is required!
    pause
    exit /b 1
)

echo.
echo Configuration:
echo   Project ID:   %PROJECT_ID%
echo   Service Name: %SERVICE_NAME%
echo   Region:       %REGION%
echo   API Key:      %ANTHROPIC_KEY:~0,20%...
echo.

REM Confirm
set /p CONFIRM="Proceed with deployment? (y/n): "
if /i not "%CONFIRM%"=="y" (
    echo Deployment cancelled.
    pause
    exit /b 0
)

echo.
echo Step 1: Creating/selecting project...
gcloud projects describe %PROJECT_ID% >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo Creating new project: %PROJECT_ID%
    gcloud projects create %PROJECT_ID% --name="FamilyFlow Backend"
)
gcloud config set project %PROJECT_ID%

echo.
echo Step 2: Enabling required APIs...
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable artifactregistry.googleapis.com

echo.
echo Step 3: Deploying to Cloud Run...
echo This may take 3-5 minutes on first deploy...
echo.

gcloud run deploy %SERVICE_NAME% ^
    --source . ^
    --platform managed ^
    --region %REGION% ^
    --allow-unauthenticated ^
    --set-env-vars ANTHROPIC_API_KEY=%ANTHROPIC_KEY% ^
    --memory 512Mi ^
    --cpu 1 ^
    --timeout 60 ^
    --min-instances 0 ^
    --max-instances 10

if %ERRORLEVEL% neq 0 (
    echo.
    echo ERROR: Deployment failed!
    echo Check the error messages above.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo DEPLOYMENT SUCCESSFUL!
echo ============================================================
echo.
echo Your service URL is shown above (starts with https://)
echo.
echo To use in your Flutter app, run:
echo   flutter run --dart-define=ASSISTANT_BASE_URL=YOUR_URL_HERE
echo.
echo To view logs:
echo   gcloud run logs read --service=%SERVICE_NAME% --region=%REGION%
echo.
echo To update the API key later:
echo   gcloud run services update %SERVICE_NAME% --region=%REGION% --set-env-vars ANTHROPIC_API_KEY=new-key
echo.
pause
