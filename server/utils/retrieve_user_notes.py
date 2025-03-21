import logging
from datetime import datetime, timedelta
from utils.supabase.init_supabase import init_supabase

# Configure logging
logger = logging.getLogger(__name__)

def retrieve_user_notes(user_id):
    """
    Retrieve user notes from the database for a given user ID.
    
    Args:
        user_id (str): The device ID of the user
        
    Returns:
        list: A list of user notes with timestamps
    """
    try:
        # Initialize Supabase
        supabase = init_supabase()
        
        # First get the internal device ID
        device_response = supabase.table('devices').select('id').eq('device_id', user_id).execute()
        
        if not device_response.data:
            logger.warning(f"Device not found for user ID: {user_id}")
            return []
            
        device_internal_id = device_response.data[0]['id']
        
        # Get all user notes, ordered by most recent first
        notes_response = supabase.table('user_notes')\
            .select('note, created_at')\
            .eq('device_id', device_internal_id)\
            .order('created_at', desc=True)\
            .execute()
        
        # Format notes with timestamps
        formatted_notes = []
        for note in notes_response.data:
            note_time = datetime.fromisoformat(note['created_at'].replace('Z', '+00:00'))
            formatted_notes.append({
                'timestamp': note_time.strftime('%Y-%m-%d %H:%M:%S UTC'),
                'note': note['note']
            })
            
        return formatted_notes
        
    except Exception as e:
        logger.error(f"Error retrieving notes for user {user_id}: {str(e)}", exc_info=True)
        return [] 