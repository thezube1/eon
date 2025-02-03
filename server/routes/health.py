from flask import Blueprint, request, jsonify
from datetime import datetime, timedelta
import os
from dotenv import load_dotenv
from supabase import create_client, Client
import logging
import sys

# Configure logging to output to stdout for Cloud Run
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# Load environment variables from .env file if it exists
load_dotenv()

health_bp = Blueprint('health', __name__)

def init_supabase():
    """Initialize Supabase client with better error handling"""
    try:
        # Log all environment variables (excluding sensitive values)
        env_vars = {k: '***' if 'KEY' in k or 'SECRET' in k else v 
                   for k, v in os.environ.items()}
        logger.debug(f"Environment variables: {env_vars}")
        
        supabase_url = os.environ.get('SUPABASE_URL')
        supabase_key = os.environ.get('SUPABASE_KEY')
        
        # Log environment variable status (without exposing sensitive data)
        logger.info(f"Supabase URL present: {bool(supabase_url)}")
        logger.info(f"Supabase Key present: {bool(supabase_key)}")
        
        if not supabase_url or not supabase_key:
            available_env_vars = ', '.join(k for k in os.environ.keys())
            logger.error(f"Missing required environment variables. Available environment variables: {available_env_vars}")
            raise ValueError("Supabase URL and key must be provided in environment variables")
        
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

@health_bp.route('/devices/<device_id>/latest', methods=['GET'])
def get_latest_metrics(device_id):
    try:
        # First verify the device exists
        device_response = supabase.table('devices').select('id').eq('device_id', device_id).execute()
        if not device_response.data:
            return jsonify({'error': 'Device not found'}), 404
        
        device_internal_id = device_response.data[0]['id']
        
        # Get latest heart rate
        heart_rate_response = supabase.table('heart_rate_measurements')\
            .select('timestamp, bpm, source, context')\
            .eq('device_id', device_internal_id)\
            .order('timestamp', desc=True)\
            .limit(1)\
            .execute()
        
        # Get latest step count
        steps_response = supabase.table('step_counts')\
            .select('date, step_count, source')\
            .eq('device_id', device_internal_id)\
            .order('date', desc=True)\
            .limit(1)\
            .execute()
        
        # Get latest sleep record
        sleep_response = supabase.table('sleep_records')\
            .select('start_time, end_time, sleep_stage, source')\
            .eq('device_id', device_internal_id)\
            .order('end_time', desc=True)\
            .limit(1)\
            .execute()
        
        return jsonify({
            'heart_rate': heart_rate_response.data[0] if heart_rate_response.data else None,
            'steps': steps_response.data[0] if steps_response.data else None,
            'sleep': sleep_response.data[0] if sleep_response.data else None
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@health_bp.route('/devices/<device_id>/metrics', methods=['GET'])
def get_metrics_by_interval(device_id):
    try:
        # Get query parameters with defaults
        start_date = request.args.get('start_date', (datetime.utcnow() - timedelta(days=7)).isoformat())
        end_date = request.args.get('end_date', datetime.utcnow().isoformat())
        
        # First verify the device exists
        device_response = supabase.table('devices').select('id').eq('device_id', device_id).execute()
        if not device_response.data:
            return jsonify({'error': 'Device not found'}), 404
        
        device_internal_id = device_response.data[0]['id']
        
        # Get heart rate data within interval
        heart_rate_response = supabase.table('heart_rate_measurements')\
            .select('timestamp, bpm, source, context')\
            .eq('device_id', device_internal_id)\
            .gte('timestamp', start_date)\
            .lte('timestamp', end_date)\
            .order('timestamp', desc=True)\
            .execute()
        
        # Get step data within interval (using just the date part of timestamps)
        steps_response = supabase.table('step_counts')\
            .select('date, step_count, source')\
            .eq('device_id', device_internal_id)\
            .gte('date', start_date[:10])\
            .lte('date', end_date[:10])\
            .order('date', desc=True)\
            .execute()
        
        # Get sleep data within interval
        sleep_response = supabase.table('sleep_records')\
            .select('start_time, end_time, sleep_stage, source')\
            .eq('device_id', device_internal_id)\
            .gte('start_time', start_date)\
            .lte('end_time', end_date)\
            .order('end_time', desc=True)\
            .execute()
        
        return jsonify({
            'heart_rate': heart_rate_response.data,
            'steps': steps_response.data,
            'sleep': sleep_response.data,
            'metadata': {
                'start_date': start_date,
                'end_date': end_date,
                'device_id': device_id
            }
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@health_bp.route('/sync', methods=['POST'])
def sync_health_data():
    try:
        data = request.get_json()
        
        # Extract device info
        device_info = data.get('device_info')
        if not device_info or 'device_id' not in device_info:
            return jsonify({'error': 'Device information is required'}), 400

        # Check if device exists and upsert
        device_response = supabase.table('devices').select('id').eq('device_id', device_info['device_id']).execute()
        
        if not device_response.data:
            # Insert new device
            device_response = supabase.table('devices').insert({
                'device_id': device_info['device_id'],
                'device_name': device_info.get('device_name'),
                'device_model': device_info.get('device_model'),
                'os_version': device_info.get('os_version')
            }).execute()
        
        device_id = device_response.data[0]['id']

        # Process heart rate data
        heart_rate_data = data.get('heart_rate', [])
        if heart_rate_data:
            heart_rate_records = [{
                'device_id': device_id,
                'timestamp': reading['timestamp'],
                'bpm': reading['bpm'],
                'source': reading.get('source'),
                'context': reading.get('context')
            } for reading in heart_rate_data]
            supabase.table('heart_rate_measurements').insert(heart_rate_records).execute()

        # Process step data
        step_data = data.get('steps', [])
        if step_data:
            step_records = [{
                'device_id': device_id,
                'date': reading['date'],
                'step_count': reading['step_count'],
                'source': reading.get('source')
            } for reading in step_data]
            supabase.table('step_counts').upsert(step_records).execute()

        # Process sleep data
        sleep_data = data.get('sleep', [])
        if sleep_data:
            sleep_records = [{
                'device_id': device_id,
                'start_time': record['start_time'],
                'end_time': record['end_time'],
                'sleep_stage': record.get('sleep_stage'),
                'source': record.get('source')
            } for record in sleep_data]
            supabase.table('sleep_records').insert(sleep_records).execute()

        # Update sync status for each metric type
        current_time = datetime.utcnow().isoformat()
        sync_records = []
        
        if heart_rate_data:
            sync_records.append({
                'device_id': device_id,
                'metric_type': 'heart_rate',
                'last_sync_time': current_time
            })
        if step_data:
            sync_records.append({
                'device_id': device_id,
                'metric_type': 'steps',
                'last_sync_time': current_time
            })
        if sleep_data:
            sync_records.append({
                'device_id': device_id,
                'metric_type': 'sleep',
                'last_sync_time': current_time
            })

        if sync_records:
            supabase.table('sync_status').upsert(sync_records).execute()

        return jsonify({
            'message': 'Health data synchronized successfully',
            'device_id': device_id
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@health_bp.route('/devices/<device_id>/sync-status', methods=['GET'])
def get_sync_status(device_id):
    try:
        # First verify the device exists
        device_response = supabase.table('devices').select('id').eq('device_id', device_id).execute()
        if not device_response.data:
            return jsonify({'error': 'Device not found'}), 404
        
        device_internal_id = device_response.data[0]['id']
        
        # Get all sync statuses for this device
        sync_response = supabase.table('sync_status')\
            .select('metric_type, last_sync_time')\
            .eq('device_id', device_internal_id)\
            .execute()
        
        # Convert list of records to a more convenient format
        sync_status = {
            'heart_rate': None,
            'steps': None,
            'sleep': None
        }
        
        for record in sync_response.data:
            sync_status[record['metric_type']] = record['last_sync_time']
            
        return jsonify({
            'device_id': device_id,
            'sync_status': sync_status,
            'last_sync': max([ts for ts in sync_status.values() if ts is not None], default=None)
        })

    except Exception as e:
        return jsonify({'error': str(e)}), 500

@health_bp.route('/test', methods=['GET'])
def test_route():
    """Simple health check that doesn't require Supabase"""
    return jsonify({
        'status': 'ok',
        'message': 'Health API is running',
        'environment': os.environ.get('FLASK_ENV', 'unknown')
    }) 