from utils.supabase.init_supabase import init_supabase, logger

def retrieve_user_recommendations(user_id: str) -> dict:
    """
    Retrieve past recommendations for a specific user, categorized by type and acceptance status.
    
    Args:
        user_id (str): The device_id of the user
        
    Returns:
        dict: Dictionary containing past recommendations categorized by type and acceptance status
    """
    try:
        # Initialize Supabase client
        supabase = init_supabase()
        
        # First verify the device exists and get internal ID
        device_response = supabase.table('devices').select('id').eq('device_id', user_id).execute()
        if not device_response.data:
            return None
            
        device_internal_id = device_response.data[0]['id']
        
        # Get all recommendations for this device
        recommendations_response = supabase.table('recommendations')\
            .select('*')\
            .eq('device_id', device_internal_id)\
            .order('created_at', desc=True)\
            .execute()
            
        # Organize recommendations by category and acceptance status
        categorized_recommendations = {
            'accepted': {
                'Sleep': [],
                'Steps': [],
                'Heart_Rate': []
            },
            'unaccepted': {
                'Sleep': [],
                'Steps': [],
                'Heart_Rate': []
            }
        }
        
        for rec in recommendations_response.data:
            category = rec['category']
            status = 'accepted' if rec['accepted'] else 'unaccepted'
            
            if category in categorized_recommendations[status]:
                categorized_recommendations[status][category].append({
                    'id': rec['id'],
                    'recommendation': rec['recommendation'],
                    'explanation': rec['explanation'],
                    'frequency': rec['frequency'],
                    'created_at': rec['created_at']
                })
        
        return categorized_recommendations
        
    except Exception as e:
        logger.error(f"Error retrieving recommendations for user {user_id}: {str(e)}", exc_info=True)
        return None

