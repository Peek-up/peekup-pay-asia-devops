#!/bin/bash
set -e

echo "Starting PeekupPay services..."

# Install requirements
pip install -r requirements.txt

# Always start Django server
echo "Starting Django server..."
python manage.py runserver 0.0.0.0:8000 &
DJANGO_PID=$!

# Conditionally start Celery services
if [ "$START_CELERY_WORKER" = "true" ]; then
    echo "Starting Celery workers and beat..."


    # Ensure log directory exists
    mkdir -p /var/log/celery

    if [ -d /var/log/celery ] && [ -w /var/log/celery ]; then
        echo "/var/log/celery directory is ready."
    else
        echo "ERROR: /var/log/celery could not be created or is not writable." >&2
        exit 1
    fi


    
    # Start Celery workers
    celery -A config worker -l info -Q short_task_queue > /var/log/celery/short_task_queue.log 2>&1 &
    celery -A config worker -l info -Q long_task_queue > /var/log/celery/long_task_queue.log 2>&1 &
    celery -A config worker -l info -Q celery &
    
    # Start Celery beat
    celery -A config beat -l info > /var/log/celery/beat.log 2>&1 &
    
    echo "All Celery services started"
else
    echo "Celery services disabled (START_CELERY_WORKER=false)"
fi

# Wait for Django process (main process)
wait $DJANGO_PID
