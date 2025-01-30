from flask import Blueprint, request, jsonify
from datetime import datetime
import os
from dotenv import load_dotenv
from supabase import create_client, Client

load_dotenv()

health_bp = Blueprint('health', __name__)

# Initialize Supabase client
supabase: Client = create_client(
    os.getenv('SUPABASE_URL'),
    os.getenv('SUPABASE_KEY')
)

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