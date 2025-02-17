from flask import Blueprint, request, jsonify
from datetime import datetime, timedelta
import os
from dotenv import load_dotenv
from supabase import create_client, Client
import logging
import sys

# Simple logger without custom configuration
logger = logging.getLogger(__name__)

# Load environment variables from .env file if it exists
load_dotenv()

health_bp = Blueprint('health', __name__)

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
        logger.info("Received sync request with data structure: %s", {k: type(v) for k, v in data.items()})
        
        # Extract device info
        device_info = data.get('device_info')
        if not device_info or 'device_id' not in device_info:
            return jsonify({'error': 'Device information is required'}), 400

        # First try to get existing device
        device_response = supabase.table('devices').select('id').eq('device_id', device_info['device_id']).execute()
        
        if device_response.data:
            # Device exists, get its ID
            device_id = device_response.data[0]['id']
            logger.info(f"Found existing device with ID: {device_id}")
            
            # Update device info
            supabase.table('devices').update({
                'device_name': device_info.get('device_name'),
                'device_model': device_info.get('device_model'),
                'os_version': device_info.get('os_version'),
                'last_active': datetime.utcnow().isoformat()
            }).eq('id', device_id).execute()
        else:
            # Insert new device
            logger.info("Creating new device record")
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
            logger.info(f"Inserting {len(heart_rate_records)} heart rate records")
            supabase.table('heart_rate_measurements').insert(heart_rate_records).execute()

        # Process step data with upsert logic
        step_data = data.get('steps', [])
        if step_data:
            try:
                step_records = []
                for reading in step_data:
                    try:
                        step_count = int(float(reading['step_count']))
                        record = {
                            'device_id': device_id,
                            'date': reading['date'],
                            'step_count': step_count,
                            'source': reading.get('source', 'HealthKit')
                        }
                        step_records.append(record)
                    except (ValueError, TypeError) as e:
                        logger.error(f"Error processing step record: {reading}, Error: {str(e)}")
                        continue

                if step_records:
                    logger.info(f"Upserting {len(step_records)} step records")
                    # Use ON CONFLICT DO UPDATE
                    result = supabase.table('step_counts').upsert(
                        step_records,
                        on_conflict='device_id,date'
                    ).execute()
                    logger.info(f"Step records upsert result: {result}")
                else:
                    logger.warning("No valid step records to insert")

            except Exception as e:
                logger.error(f"Error upserting step data: {str(e)}", exc_info=True)
                # Continue processing other data even if steps fail
                pass

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
            logger.info(f"Inserting {len(sleep_records)} sleep records")
            supabase.table('sleep_records').insert(sleep_records).execute()

        # Update sync status
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
            logger.info(f"Updating sync status for {len(sync_records)} metrics")
            supabase.table('sync_status').upsert(
                sync_records,
                on_conflict='device_id,metric_type'
            ).execute()

        return jsonify({
            'message': 'Health data synchronized successfully',
            'device_id': device_id,
            'metrics_synced': {
                'heart_rate': len(heart_rate_data),
                'steps': len(step_data),
                'sleep': len(sleep_data)
            }
        })

    except Exception as e:
        logger.error(f"Error in sync_health_data: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500

@health_bp.route('/devices/<device_id>/sync-status', methods=['GET'])
def get_sync_status(device_id):
    try:
        logger.info(f"Getting sync status for device: {device_id}")
        
        # First verify the device exists
        device_response = supabase.table('devices').select('id').eq('device_id', device_id).execute()
        if not device_response.data:
            return jsonify({'error': 'Device not found'}), 404
        
        device_internal_id = device_response.data[0]['id']
        logger.info(f"Found device with internal ID: {device_internal_id}")
        
        # Get all sync statuses for this device
        sync_response = supabase.table('sync_status')\
            .select('*')\
            .eq('device_id', device_internal_id)\
            .execute()
            
        logger.info(f"Retrieved sync records: {sync_response.data}")
        
        # Convert list of records to a more convenient format
        sync_status = {
            'heart_rate': None,
            'steps': None,
            'sleep': None
        }
        
        last_sync = None
        for record in sync_response.data:
            metric_type = record['metric_type']
            sync_time = record['last_sync_time']
            sync_status[metric_type] = sync_time
            
            # Update last_sync if this is the most recent sync
            if last_sync is None or sync_time > last_sync:
                last_sync = sync_time
                
        logger.info(f"Formatted sync status: {sync_status}, Last sync: {last_sync}")
            
        return jsonify({
            'sync_status': sync_status,
            'last_sync': last_sync
        })

    except Exception as e:
        logger.error(f"Error getting sync status: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500

@health_bp.route('/test', methods=['GET'])
def test_route():
    """Simple health check that doesn't require Supabase"""
    return jsonify({
        'status': 'ok',
        'message': 'Health API is running',
        'environment': os.environ.get('FLASK_ENV', 'unknown')
    }) 