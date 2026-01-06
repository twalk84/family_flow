# FILE: backend/Dockerfile
# =============================================================================
# FAMILYFLOW ASSISTANT API - DOCKER IMAGE
# =============================================================================
# Build: docker build -t familyflow-assistant .
# Run:   docker run -p 8080:8080 -e ANTHROPIC_API_KEY=sk-ant-xxx familyflow-assistant

FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install dependencies first (for caching)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY main.py .

# Expose port
EXPOSE 8080

# Set environment variables
ENV PORT=8080
ENV PYTHONUNBUFFERED=1

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Run the application
CMD ["python", "main.py"]
