# Google Cloud Run Deployment Guide

## 📋 Overview

This guide walks you through deploying your FamilyFlow assistant backend to **Google Cloud Run** - Google's serverless container platform.

### Why Cloud Run?

- ✅ **Generous free tier:** 2 million requests/month free
- ✅ **Pay only for what you use:** Scales to zero when not in use
- ✅ **Fast cold starts:** ~1-2 seconds
- ✅ **Auto-scaling:** Handles traffic spikes automatically
- ✅ **HTTPS included:** Free SSL certificates
- ✅ **Global:** Deploy to any region

---

## 🛠️ Prerequisites

Before starting, you need:

1. **Google Account** (Gmail works)
2. **Anthropic API Key** from https://console.anthropic.com/
3. **Google Cloud SDK** (we'll install this)

---

## 📝 Step-by-Step Instructions

### Step 1: Get Your Anthropic API Key

1. Go to **https://console.anthropic.com/**
2. Sign up or log in
3. Click **API Keys** in the left sidebar
4. Click **Create Key**
5. Give it a name like "FamilyFlow Backend"
6. **Copy the key** (starts with `sk-ant-api03-...`)
7. **Save it somewhere safe** - you can't see it again!

---

### Step 2: Install Google Cloud SDK

#### Windows

1. Download the installer:
   **https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe**

2. Run the installer
   - Check "Install Bundled Python"
   - Check "Add to PATH"

3. After installation, open a **new** Command Prompt or PowerShell

4. Initialize gcloud:
   ```cmd
   gcloud init
   ```

5. Follow the prompts:
   - Log in with your Google account (browser will open)
   - Select or create a project (you can skip this, we'll create one)

#### Mac

```bash
# Using Homebrew (recommended)
brew install google-cloud-sdk

# Initialize
gcloud init
```

#### Linux

```bash
# Download and install
curl https://sdk.cloud.google.com | bash

# Restart your shell
exec -l $SHELL

# Initialize
gcloud init
```

---

### Step 3: Verify Installation

Open a terminal and run:

```bash
gcloud --version
```

You should see something like:
```
Google Cloud SDK 458.0.0
...
```

---

### Step 4: Prepare Your Backend Files

Make sure you have all these files in a folder called `backend`:

```
backend/
├── main.py
├── requirements.txt
├── Dockerfile
├── .dockerignore
├── deploy-gcloud.bat    (Windows)
├── deploy-gcloud.sh     (Mac/Linux)
```

---

### Step 5: Deploy Using the Script (Easiest)

#### Windows

1. Open Command Prompt
2. Navigate to your backend folder:
   ```cmd
   cd C:\path\to\backend
   ```
3. Run the deployment script:
   ```cmd
   deploy-gcloud.bat
   ```
4. Enter your Anthropic API key when prompted
5. Wait 3-5 minutes for deployment

#### Mac/Linux

1. Open Terminal
2. Navigate to your backend folder:
   ```bash
   cd /path/to/backend
   ```
3. Make the script executable:
   ```bash
   chmod +x deploy-gcloud.sh
   ```
4. Run it:
   ```bash
   ./deploy-gcloud.sh
   ```
5. Enter your Anthropic API key when prompted
6. Wait 3-5 minutes for deployment

---

### Step 5 (Alternative): Deploy Manually

If you prefer to run commands yourself:

```bash
# Navigate to backend folder
cd /path/to/backend

# Set your project ID (change this to something unique)
PROJECT_ID="familyflow-YOUR-NAME"

# Create the project (if it doesn't exist)
gcloud projects create $PROJECT_ID --name="FamilyFlow Backend"

# Select the project
gcloud config set project $PROJECT_ID

# Enable required APIs
gcloud services enable cloudbuild.googleapis.com
gcloud services enable run.googleapis.com
gcloud services enable artifactregistry.googleapis.com

# Deploy (replace YOUR_API_KEY with your actual key)
gcloud run deploy familyflow-assistant \
    --source . \
    --platform managed \
    --region us-central1 \
    --allow-unauthenticated \
    --set-env-vars ANTHROPIC_API_KEY=YOUR_API_KEY \
    --memory 512Mi \
    --cpu 1 \
    --timeout 60 \
    --min-instances 0 \
    --max-instances 10
```

---

### Step 6: Get Your Service URL

After deployment succeeds, you'll see output like:

```
Service [familyflow-assistant] revision [familyflow-assistant-00001-abc] 
has been deployed and is serving 100 percent of traffic.

Service URL: https://familyflow-assistant-abc123xyz-uc.a.run.app
```

**Copy that URL!** You'll need it for your Flutter app.

---

### Step 7: Test Your Deployment

#### Quick Test in Browser

Open your Service URL in a browser. You should see:

```json
{
  "service": "FamilyFlow Assistant API",
  "status": "running",
  "version": "1.0.0",
  "model": "claude-sonnet-4-20250514",
  "api_key_configured": true
}
```

#### Test with curl

```bash
# Health check
curl https://YOUR-SERVICE-URL/

# Test chat
curl -X POST https://YOUR-SERVICE-URL/assistant/chat \
  -H "Content-Type: application/json" \
  -d '{"text": "Add math homework for William due tomorrow"}'
```

Expected response:
```json
{
  "reply": "I'll add that math homework for William, due tomorrow!",
  "action": {
    "type": "add_assignment",
    "studentName": "William",
    "subjectName": "Math",
    "name": "Homework",
    "dueDate": "2025-12-21"
  }
}
```

#### Interactive API Docs

Go to `https://YOUR-SERVICE-URL/docs` for a Swagger UI where you can test the API interactively.

---

### Step 8: Update Your Flutter App

Now update your Flutter app to use the cloud backend:

#### For Development/Testing

```bash
flutter run --dart-define=ASSISTANT_BASE_URL=https://YOUR-SERVICE-URL
```

#### For Release Build

```bash
# Android
flutter build apk --release --dart-define=ASSISTANT_BASE_URL=https://YOUR-SERVICE-URL

# iOS
flutter build ios --release --dart-define=ASSISTANT_BASE_URL=https://YOUR-SERVICE-URL
```

#### Make It Permanent (Windows)

Create a file called `build_release.bat`:

```batch
@echo off
set ASSISTANT_URL=https://familyflow-assistant-abc123xyz-uc.a.run.app
flutter build apk --release --dart-define=ASSISTANT_BASE_URL=%ASSISTANT_URL%
echo.
echo APK built at: build\app\outputs\flutter-apk\app-release.apk
pause
```

#### Make It Permanent (Mac/Linux)

Create a file called `build_release.sh`:

```bash
#!/bin/bash
ASSISTANT_URL="https://familyflow-assistant-abc123xyz-uc.a.run.app"
flutter build apk --release --dart-define=ASSISTANT_BASE_URL=$ASSISTANT_URL
echo ""
echo "APK built at: build/app/outputs/flutter-apk/app-release.apk"
```

---

## 🔧 Managing Your Deployment

### View Logs

```bash
gcloud run logs read --service=familyflow-assistant --region=us-central1
```

Or view in the console: https://console.cloud.google.com/run

### Update API Key

```bash
gcloud run services update familyflow-assistant \
  --region=us-central1 \
  --set-env-vars ANTHROPIC_API_KEY=sk-ant-NEW-KEY-HERE
```

### Redeploy After Code Changes

```bash
cd /path/to/backend
gcloud run deploy familyflow-assistant --source . --region=us-central1
```

### Delete the Service (if needed)

```bash
gcloud run services delete familyflow-assistant --region=us-central1
```

### View Billing/Usage

Go to: https://console.cloud.google.com/billing

---

## 💰 Cost Breakdown

### Google Cloud Run Free Tier (Monthly)

| Resource | Free Amount | Your Likely Usage |
|----------|-------------|-------------------|
| Requests | 2 million | ~1,000-5,000 |
| CPU | 180,000 vCPU-seconds | ~1,000-5,000 |
| Memory | 360,000 GiB-seconds | ~1,000-5,000 |
| Networking | 1 GB egress | ~0.1 GB |

**For a family homeschool app, you'll almost certainly stay in the free tier!**

### Anthropic API Costs

| Model | Input | Output |
|-------|-------|--------|
| Claude Sonnet | $3/million tokens | $15/million tokens |

A typical request uses ~500 input tokens and ~200 output tokens.
**Estimated cost: $0.001-0.005 per request**, or **$1-5/month** for typical usage.

---

## 🐛 Troubleshooting

### "Permission denied" or "Unauthorized"

```bash
# Re-authenticate
gcloud auth login

# Set the project
gcloud config set project YOUR-PROJECT-ID
```

### "Billing account not configured"

1. Go to https://console.cloud.google.com/billing
2. Create a billing account (credit card required, but you won't be charged for free tier)
3. Link it to your project

### "Build failed"

Check the Cloud Build logs:
```bash
gcloud builds list --limit=5
gcloud builds log BUILD_ID
```

Common issues:
- Missing `requirements.txt`
- Syntax error in `main.py`
- Wrong Python version (we use 3.11)

### "Service not responding"

Check the service logs:
```bash
gcloud run logs read --service=familyflow-assistant --region=us-central1 --limit=50
```

### "API key not working"

1. Verify the key at https://console.anthropic.com/
2. Check it's set correctly:
   ```bash
   gcloud run services describe familyflow-assistant --region=us-central1 --format="value(spec.template.spec.containers[0].env)"
   ```
3. Update if needed:
   ```bash
   gcloud run services update familyflow-assistant --region=us-central1 --set-env-vars ANTHROPIC_API_KEY=correct-key
   ```

---

## ✅ Deployment Checklist

- [ ] Installed Google Cloud SDK
- [ ] Ran `gcloud init` and logged in
- [ ] Got Anthropic API key from console.anthropic.com
- [ ] Have all backend files ready
- [ ] Ran deployment script or manual commands
- [ ] Deployment succeeded (got Service URL)
- [ ] Tested `/` endpoint in browser (shows status)
- [ ] Tested `/assistant/chat` endpoint (returns action)
- [ ] Updated Flutter app with `--dart-define=ASSISTANT_BASE_URL=...`
- [ ] Tested assistant in Flutter app
- [ ] 🎉 Everything works!

---

## 🚀 You're Done!

Your FamilyFlow backend is now running on Google Cloud Run:

- ✅ **Always available** - 99.95% uptime SLA
- ✅ **Auto-scaling** - handles any load
- ✅ **Secure** - HTTPS by default
- ✅ **Cost-effective** - likely free for your usage
- ✅ **Low latency** - ~100-200ms response time

Your Flutter app is now **completely untethered** and works anywhere!
