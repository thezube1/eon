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
