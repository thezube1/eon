# Use Python 3.11 slim image as base
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Install curl for healthcheck
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Copy requirements first to leverage Docker cache
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application
COPY . .

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV FLASK_APP=app.py
ENV FLASK_ENV=production
ENV PORT=8000
ENV WORKERS=2
ENV TIMEOUT=120

# Expose the port the app runs on
EXPOSE 8000

# Use different commands for development and production
CMD if [ "$FLASK_ENV" = "development" ] ; then \
        flask run --host=0.0.0.0 --port=$PORT --reload ; \
    else \
        exec gunicorn --bind :$PORT --workers $WORKERS --timeout $TIMEOUT --access-logfile - --error-logfile - --log-level debug app:app ; \
    fi 