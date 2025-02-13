from datetime import datetime, timedelta
import logging
import sys
from supabase import create_client

# Configure logging - suppress unnecessary logs
logging.basicConfig(level=logging.INFO)

# Set log levels for noisy libraries
logging.getLogger('httpcore').setLevel(logging.WARNING)
logging.getLogger('httpx').setLevel(logging.WARNING)
logging.getLogger('h2').setLevel(logging.WARNING)
logging.getLogger('urllib3').setLevel(logging.WARNING)
logging.getLogger('supabase').setLevel(logging.WARNING)

logger = logging.getLogger(__name__)

def init_supabase():
    """Initialize Supabase client with better error handling"""
    try:
        # Hardcoded Supabase credentials (same as in health.py)
        supabase_url = "https://teywcjjsffwlvlawueze.supabase.co"
        supabase_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRleXdjampzZmZ3bHZsYXd1ZXplIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTczODI3NTYzNywiZXhwIjoyMDUzODUxNjM3fQ.U7bW40zIoMZEg335gMFWWlh43N7bODBLFmGk8PGeejM"
        
        logger.info("Initializing Supabase client")
        client = create_client(supabase_url, supabase_key)
        
        # Test the connection
        client.table('devices').select('id').limit(1).execute()
        logger.info("Successfully tested Supabase connection")
        
        return client
    except Exception as e:
        logger.error(f"Failed to initialize Supabase client: {str(e)}", exc_info=True)
        raise

# Initialize Supabase client
try:
    supabase = init_supabase()
    logger.info("Supabase client initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize Supabase client: {str(e)}", exc_info=True)
    raise

def retrieve_user_metrics(user_id):
    """
    Retrieve health metrics for a user from the last 30 days.
    
    Args:
        user_id (str): The device_id of the user
        
    Returns:
        dict: Dictionary containing heart rate, steps, and sleep data
        or None if device not found
    """
    try:
        # Calculate date range
        end_date = datetime.utcnow()
        start_date = end_date - timedelta(days=30)
        
        # First verify the device exists and get internal ID
        device_response = supabase.table('devices').select('id').eq('device_id', user_id).execute()
        if not device_response.data:
            logger.warning(f"Device not found for user_id: {user_id}")
            return None
        
        device_internal_id = device_response.data[0]['id']
        logger.info(f"Found device with internal ID: {device_internal_id}")
        
        # Get heart rate data
        heart_rate_response = supabase.table('heart_rate_measurements')\
            .select('timestamp, bpm, source, context')\
            .eq('device_id', device_internal_id)\
            .gte('timestamp', start_date.isoformat())\
            .lte('timestamp', end_date.isoformat())\
            .order('timestamp', desc=True)\
            .execute()
        
        # Get step data
        steps_response = supabase.table('step_counts')\
            .select('date, step_count, source')\
            .eq('device_id', device_internal_id)\
            .gte('date', start_date.date().isoformat())\
            .lte('date', end_date.date().isoformat())\
            .order('date', desc=True)\
            .execute()
        
        # Get sleep data
        sleep_response = supabase.table('sleep_records')\
            .select('start_time, end_time, sleep_stage, source')\
            .eq('device_id', device_internal_id)\
            .gte('start_time', start_date.isoformat())\
            .lte('end_time', end_date.isoformat())\
            .order('end_time', desc=True)\
            .execute()
        
        return {
            'heart_rate': heart_rate_response.data,
            'steps': steps_response.data,
            'sleep': sleep_response.data,
            'metadata': {
                'start_date': start_date.isoformat(),
                'end_date': end_date.isoformat(),
                'device_id': user_id
            }
        }

    except Exception as e:
        logger.error(f"Error retrieving metrics for user {user_id}: {str(e)}", exc_info=True)
        raise