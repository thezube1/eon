from flask import Blueprint, request, jsonify
from datetime import datetime
import logging
from supabase import create_client, Client

logger = logging.getLogger(__name__)

def init_supabase():
    """Initialize Supabase client with better error handling"""
    try:
        # Hardcoded Supabase credentials
        supabase_url = "https://teywcjjsffwlvlawueze.supabase.co"
        supabase_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRleXdjampzZmZ3bHZsYXd1ZXplIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTczODI3NTYzNywiZXhwIjoyMDUzODUxNjM3fQ.U7bW40zIoMZEg335gMFWWlh43N7bODBLFmGk8PGeejM"
        
        logger.info("Initializing Supabase client with hardcoded credentials")
        
        # Initialize client with a timeout
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

notes_bp = Blueprint('notes', __name__)

@notes_bp.route('/devices/<device_id>/notes', methods=['POST'])
def create_note(device_id):
    try:
        data = request.get_json()
        logger.info(f"Attempting to create note for device: {device_id}")
        logger.info(f"Request data: {data}")
        
        if not data or 'note' not in data:
            logger.error("Note content missing from request")
            return jsonify({'error': 'Note content is required'}), 400

        # First verify the device exists
        logger.info("Checking if device exists...")
        device_response = supabase.table('devices').select('id').eq('device_id', device_id).execute()
        logger.info(f"Device lookup response: {device_response.data}")
        
        if not device_response.data:
            logger.error(f"Device not found: {device_id}")
            return jsonify({'error': 'Device not found'}), 404
        
        device_internal_id = device_response.data[0]['id']
        logger.info(f"Found device with internal ID: {device_internal_id}")
        
        # Create the note
        note_data = {
            'device_id': device_internal_id,
            'note': data['note'],
            'created_at': datetime.utcnow().isoformat()
        }
        logger.info(f"Attempting to insert note with data: {note_data}")
        
        result = supabase.table('user_notes').insert(note_data).execute()
        logger.info(f"Note creation result: {result.data}")
        
        return jsonify({
            'message': 'Note created successfully',
            'note': result.data[0]
        }), 201

    except Exception as e:
        logger.error(f"Error creating note: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500

@notes_bp.route('/devices/<device_id>/notes', methods=['GET'])
def get_notes(device_id):
    try:
        # First verify the device exists
        device_response = supabase.table('devices').select('id').eq('device_id', device_id).execute()
        if not device_response.data:
            return jsonify({'error': 'Device not found'}), 404
        
        device_internal_id = device_response.data[0]['id']
        
        # Get all notes for this device
        notes_response = supabase.table('user_notes')\
            .select('*')\
            .eq('device_id', device_internal_id)\
            .order('created_at', desc=True)\
            .execute()
            
        return jsonify({
            'notes': notes_response.data
        })

    except Exception as e:
        logger.error(f"Error retrieving notes: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500 