# FILE: backend/main.py
# =============================================================================
# FAMILYFLOW CLOUD ASSISTANT BACKEND
# =============================================================================
# Cloud backend that your Flutter app calls.
# Receives messages, calls Claude API, returns structured responses.
# =============================================================================

import os
import json
import logging
from datetime import datetime, timedelta
from typing import Optional, Tuple, Dict, Any

from fastapi import FastAPI, HTTPException, Request, Depends, Header
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel

import anthropic

# Firebase token verification (google-auth)
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------

ANTHROPIC_API_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
if not ANTHROPIC_API_KEY:
    logging.warning("⚠️ ANTHROPIC_API_KEY not set! The assistant will not work.")

# Optional: restrict to specific origins in production
ALLOWED_ORIGINS = os.environ.get("ALLOWED_ORIGINS", "*").split(",")

# Model to use
MODEL = os.environ.get("CLAUDE_MODEL", "claude-sonnet-4-20250514")

# Optional but recommended: enforce Firebase project ID match
# For Firebase ID tokens: aud == project_id, iss == https://securetoken.google.com/<project_id>
FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "").strip()

# -----------------------------------------------------------------------------
# LOGGING
# -----------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

# -----------------------------------------------------------------------------
# FASTAPI APP
# -----------------------------------------------------------------------------

app = FastAPI(
    title="FamilyFlow Assistant API",
    description="Cloud backend for FamilyFlow homeschool management app",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS if ALLOWED_ORIGINS != ["*"] else ["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],  # includes Authorization
)

# -----------------------------------------------------------------------------
# REQUEST/RESPONSE MODELS
# -----------------------------------------------------------------------------

class ChatRequest(BaseModel):
    text: str
    familyId: Optional[str] = None
    userId: Optional[str] = None
    userEmail: Optional[str] = None
    context: Optional[str] = None  # optional data context from app


class ChatResponse(BaseModel):
    reply: str
    action: Optional[dict] = None


# -----------------------------------------------------------------------------
# AUTH: Firebase ID token verification
# -----------------------------------------------------------------------------

FIREBASE_PROJECT_ID = os.environ.get("FIREBASE_PROJECT_ID", "").strip()

_google_request = google_requests.Request()

def require_firebase_user(
    authorization: Optional[str] = Header(default=None),
) -> Dict[str, Any]:
    """
    Requires Authorization: Bearer <Firebase ID token>
    Returns decoded claims if valid, otherwise raises 401.
    """
    if not authorization:
        raise HTTPException(status_code=401, detail="Missing Authorization header.")
    if not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Authorization must be: Bearer <token>")

    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Empty bearer token.")

    try:
        # If FIREBASE_PROJECT_ID is set, enforce aud via audience=
        if FIREBASE_PROJECT_ID:
            claims = google_id_token.verify_firebase_token(
                token,
                _google_request,
                audience=FIREBASE_PROJECT_ID,
            )
        else:
            claims = google_id_token.verify_firebase_token(token, _google_request)

    except Exception:
        # Don’t leak internals to the client; log server-side instead
        logger.exception("Invalid Firebase ID token")
        raise HTTPException(status_code=401, detail="Invalid Firebase ID token.")

    # Optional strict issuer check (audience already checked above if set)
    if FIREBASE_PROJECT_ID:
        iss = claims.get("iss")
        expected_iss = f"https://securetoken.google.com/{FIREBASE_PROJECT_ID}"
        if iss != expected_iss:
            raise HTTPException(status_code=401, detail="Token project mismatch.")

    return claims



# -----------------------------------------------------------------------------
# SYSTEM PROMPT
# -----------------------------------------------------------------------------

def build_system_prompt(context: Optional[str] = None) -> str:
    today = datetime.now().strftime("%Y-%m-%d")
    tomorrow = (datetime.now().replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(days=1)).strftime("%Y-%m-%d")

    base_prompt = f"""You are a helpful homeschool assistant for FamilyFlow.

TODAY'S DATE: {today}

You help parents manage their homeschool by:
- Adding assignments for students
- Adding new students and subjects
- Answering questions about their data
- Setting the teacher's mood

AVAILABLE ACTIONS (respond with JSON when the user wants to do something):

1. ADD ASSIGNMENT (single student):
   {{"type": "add_assignment", "studentName": "William", "subjectName": "Math", "name": "Chapter 5 Review", "dueDate": "{today}"}}

2. ADD STUDENT:
   {{"type": "add_student", "name": "Emma", "age": 10, "gradeLevel": "5th"}}

3. ADD SUBJECT:
   {{"type": "add_subject", "name": "Latin"}}

4. SET TEACHER MOOD:
   {{"type": "set_teacher_mood", "mood": "😊"}}
   Valid moods: 😫 😔 😐 😊 🔥 (or null to clear)

5. COMPLETE ASSIGNMENT:
   {{"type": "complete_assignment", "assignmentId": "abc123", "grade": 95}}

6. DELETE ASSIGNMENT:
   {{"type": "delete_assignment", "assignmentId": "abc123"}}

RESPONSE FORMAT:
- For questions: Just respond naturally with helpful text
- For commands: Include BOTH a friendly reply AND the JSON action
- Put the JSON action on its own line, clearly visible

IMPORTANT RULES:
- Use student and subject NAMES, not IDs (the app will resolve them)
- For dates: Use YYYY-MM-DD format
- If user says "due tomorrow", use dueDate: "{tomorrow}"
- If user says "due today", use dueDate: "{today}"
- Be concise and friendly
- If you're unsure what the user wants, ask for clarification
"""

    if context:
        base_prompt += f"""

CURRENT DATA IN THE APP:
{context}

Use this information to:
- Reference students/subjects by their exact names
- Know which assignments already exist
- Answer questions about completion rates, grades, etc.
"""

    return base_prompt


# -----------------------------------------------------------------------------
# CLAUDE API CALL
# -----------------------------------------------------------------------------

def call_claude(message: str, context: Optional[str] = None) -> Tuple[str, Optional[dict]]:
    if not ANTHROPIC_API_KEY:
        return "Sorry, the assistant is not configured. Please set the API key.", None

    client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)

    try:
        response = client.messages.create(
            model=MODEL,
            max_tokens=1024,
            system=build_system_prompt(context),
            messages=[{"role": "user", "content": message}],
        )

        reply_text = ""
        for block in response.content:
            if hasattr(block, "text"):
                reply_text += block.text

        action = extract_action(reply_text)
        if action:
            reply_text = clean_reply(reply_text)

        return reply_text.strip(), action

    except anthropic.APIError as e:
        logger.error(f"Anthropic API error: {e}")
        return f"Sorry, there was an API error: {str(e)}", None
    except Exception as e:
        logger.error(f"Unexpected error: {e}")
        return f"Sorry, something went wrong: {str(e)}", None


def extract_action(text: str) -> Optional[dict]:
    import re

    patterns = [
        r'\{[^{}]*"type"\s*:\s*"[^"]+"[^{}]*\}',
        r'\{[^{}]*"action"\s*:\s*"[^"]+"[^{}]*\}',
        r'```json\s*(\{.*?\})\s*```',
        r'`(\{[^`]+\})`',
    ]

    for pattern in patterns:
        matches = re.findall(pattern, text, re.DOTALL | re.IGNORECASE)
        for match in matches:
            try:
                json_str = match if isinstance(match, str) else match
                json_str = json_str.strip()
                if not json_str.startswith("{"):
                    continue

                parsed = json.loads(json_str)

                action_type = parsed.get("type") or parsed.get("action")
                if action_type and isinstance(action_type, str):
                    if "action" in parsed and "type" not in parsed:
                        parsed["type"] = parsed.pop("action")
                    return parsed

            except json.JSONDecodeError:
                continue

    return None


def clean_reply(text: str) -> str:
    import re

    text = re.sub(r'```json\s*\{.*?\}\s*```', '', text, flags=re.DOTALL)
    text = re.sub(r'`\{[^`]+\}`', '', text)
    text = re.sub(r'\n\s*\{[^{}]*"type"\s*:[^{}]*\}\s*\n?', '\n', text, flags=re.DOTALL)
    text = re.sub(r'\n{3,}', '\n\n', text)

    return text.strip()


# -----------------------------------------------------------------------------
# API ENDPOINTS
# -----------------------------------------------------------------------------

@app.get("/")
async def root():
    return {
        "service": "FamilyFlow Assistant API",
        "status": "running",
        "version": "1.0.0",
        "model": MODEL,
        "api_key_configured": bool(ANTHROPIC_API_KEY),
        "firebase_project_locked": bool(FIREBASE_PROJECT_ID),
    }


@app.get("/health")
async def health():
    return {"status": "healthy"}


@app.post("/assistant/chat", response_model=ChatResponse)
async def assistant_chat(
    request: ChatRequest,
    claims: Dict[str, Any] = Depends(require_firebase_user),
):
    """
    Main chat endpoint (AUTH REQUIRED).
    Requires: Authorization: Bearer <Firebase ID token>
    """
    # Pull identity from token claims
    uid = claims.get("user_id") or claims.get("sub")
    email = claims.get("email")

    logger.info(f"Chat request: '{request.text[:100]}...' uid={uid} email={email}")

    if not request.text.strip():
        raise HTTPException(status_code=400, detail="Message text is required")

    # If the app didn't pass these, fill them from verified token
    if not request.userId:
        request.userId = str(uid) if uid else None
    if not request.userEmail and email:
        request.userEmail = str(email)

    reply, action = call_claude(request.text, request.context)

    logger.info(f"Response: reply='{reply[:100]}...', action={action}")

    return ChatResponse(reply=reply, action=action)


# -----------------------------------------------------------------------------
# ERROR HANDLERS
# -----------------------------------------------------------------------------

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {exc}")
    return JSONResponse(
        status_code=500,
        content={
            "reply": "Sorry, something went wrong on the server.",
            "action": None,
            "error": str(exc),
        },
    )


# -----------------------------------------------------------------------------
# RUN (local dev)
# -----------------------------------------------------------------------------

if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", 8080))

    print("=" * 60)
    print("FAMILYFLOW ASSISTANT API")
    print("=" * 60)
    print(f"Running on: http://0.0.0.0:{port}")
    print(f"API docs:   http://0.0.0.0:{port}/docs")
    print(f"Model:      {MODEL}")
    print(f"API key:    {'✅ Configured' if ANTHROPIC_API_KEY else '❌ NOT SET'}")
    print(f"Firebase:   {'✅ Locked to project ' + FIREBASE_PROJECT_ID if FIREBASE_PROJECT_ID else '⚠️ Not project-locked'}")
    print("=" * 60)

    uvicorn.run(app, host="0.0.0.0", port=port)
