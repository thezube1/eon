from datetime import datetime
import logging
from supabase import create_client

# Configure logging
logger = logging.getLogger(__name__)

def init_supabase():
    """Initialize Supabase client with better error handling"""
    try:
        # Hardcoded Supabase credentials
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

def store_recommendations(device_id: str, recommendations: dict) -> bool:
    """
    Store recommendations in the Supabase database.
    Checks for existing recommendations to avoid duplicates.
    
    Args:
        device_id (str): The device_id of the user
        recommendations (dict): Dictionary containing recommendations by category
        
    Returns:
        bool: True if storage was successful, False otherwise
    """
    try:
        # First verify the device exists and get internal ID
        device_response = supabase.table('devices').select('id').eq('device_id', device_id).execute()
        if not device_response.data:
            logger.warning(f"Device not found for device_id: {device_id}")
            return False
        
        device_internal_id = device_response.data[0]['id']
        logger.info(f"Found device with internal ID: {device_internal_id}")
        
        # Get existing recommendations for this device
        existing_recommendations = supabase.table('recommendations')\
            .select('category, recommendation')\
            .eq('device_id', device_internal_id)\
            .execute()
            
        # Create a set of existing recommendation tuples (category, recommendation)
        existing_set = {
            (rec['category'], rec['recommendation']) 
            for rec in existing_recommendations.data
        }
        
        # Store each recommendation by category
        for category, category_recommendations in recommendations.items():
            for rec in category_recommendations:
                # Check if this recommendation already exists
                if (category, rec['recommendation']) in existing_set:
                    logger.info(f"Skipping duplicate recommendation for category {category}: {rec['recommendation']}")
                    continue
                
                recommendation_data = {
                    'device_id': device_internal_id,
                    'category': category,
                    'recommendation': rec['recommendation'],
                    'explanation': rec['explanation'],
                    'frequency': rec['frequency']
                }
                
                result = supabase.table('recommendations').insert(recommendation_data).execute()
                if not result.data:
                    logger.error(f"Failed to store recommendation: {recommendation_data}")
                    return False
                    
        logger.info(f"Successfully stored all new recommendations for device {device_id}")
        return True
        
    except Exception as e:
        logger.error(f"Error storing recommendations for device {device_id}: {str(e)}", exc_info=True)
        return False
