from datetime import datetime, timedelta
import logging
import sys
from supabase import create_client

# Simple logger without custom configuration
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


# Initialize Supabase client
try:
    supabase = init_supabase()
    logger.info("Supabase client initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize Supabase client: {str(e)}", exc_info=True)
    raise

def retrieve_user_metrics(user_id):
    """
    Retrieve the last complete day's health metrics and notes for a user.
    
    Args:
        user_id (str): The device_id of the user
        
    Returns:
        dict: Dictionary containing last day's heart rate stats, steps, sleep data, and recent notes
        or None if device not found
    """
    try:
        # First verify the device exists and get internal ID
        device_response = supabase.table('devices').select('id').eq('device_id', user_id).execute()
        if not device_response.data:
            logger.warning(f"Device not found for user_id: {user_id}")
            return None
        
        device_internal_id = device_response.data[0]['id']
        logger.info(f"Found device with internal ID: {device_internal_id}")
        
        # Get the most recent dates from each table
        latest_step_date = supabase.table('step_counts')\
            .select('date')\
            .eq('device_id', device_internal_id)\
            .order('date', desc=True)\
            .limit(1)\
            .execute()
            
        latest_heart_date = supabase.table('heart_rate_measurements')\
            .select('timestamp')\
            .eq('device_id', device_internal_id)\
            .order('timestamp', desc=True)\
            .limit(1)\
            .execute()
        
        # Find the most recent date among metrics
        latest_date = None
        if latest_step_date.data:
            latest_date = datetime.fromisoformat(latest_step_date.data[0]['date'])
        
        if latest_heart_date.data:
            heart_date = datetime.fromisoformat(latest_heart_date.data[0]['timestamp'].replace('Z', '+00:00')).date()
            if not latest_date or heart_date > latest_date.date():
                latest_date = datetime.combine(heart_date, datetime.min.time())
        
        if not latest_date:
            logger.warning(f"No metrics found for user_id: {user_id}")
            return None
            
        start_of_day = latest_date.replace(hour=0, minute=0, second=0, microsecond=0)
        end_of_day = latest_date.replace(hour=23, minute=59, second=59, microsecond=999999)
        
        # For sleep, we need to look at a wider window to catch sleep that starts the day before
        sleep_start_window = start_of_day - timedelta(days=7)  # Look back 7 days
        sleep_end_window = end_of_day
        
        logger.info(f"Retrieving metrics for date: {latest_date.date().isoformat()}")
        
        # Get heart rate data for the day and calculate statistics
        heart_rate_response = supabase.table('heart_rate_measurements')\
            .select('timestamp, bpm, source, context')\
            .eq('device_id', device_internal_id)\
            .gte('timestamp', start_of_day.isoformat())\
            .lte('timestamp', end_of_day.isoformat())\
            .order('timestamp', desc=True)\
            .execute()
        
        # Calculate heart rate statistics
        heart_rate_stats = {
            'date': latest_date.date().isoformat(),
            'peak': None,
            'low': None,
            'average': None,
            'measurements_count': 0
        }
        
        if heart_rate_response.data:
            bpm_values = [record['bpm'] for record in heart_rate_response.data]
            heart_rate_stats = {
                'date': latest_date.date().isoformat(),
                'peak': max(bpm_values),
                'low': min(bpm_values),
                'average': sum(bpm_values) / len(bpm_values),
                'measurements_count': len(bpm_values)
            }
        
        # Get step data for the day
        steps_response = supabase.table('step_counts')\
            .select('date, step_count, source')\
            .eq('device_id', device_internal_id)\
            .lte('date', latest_date.date().isoformat())\
            .order('date', desc=True)\
            .limit(1)\
            .execute()
        
        # Get sleep data with a wider window to catch the full night's sleep
        sleep_response = supabase.table('sleep_records')\
            .select('start_time, end_time, sleep_stage, source')\
            .eq('device_id', device_internal_id)\
            .gte('start_time', sleep_start_window.isoformat())\
            .lte('end_time', sleep_end_window.isoformat())\
            .order('end_time', desc=True)\
            .execute()
            
        # Process sleep records to find the most recent night's sleep
        sleep_records = sleep_response.data
        if sleep_records:
            # Create a dictionary to track unique sleep records by their start and end times
            unique_records = {}
            valid_sleep_found = False
            
            for record in sleep_records:
                # Skip undefined or unspecified sleep stages
                if record['sleep_stage'].lower() in ['undefined', 'unspecified', '']:
                    continue
                    
                valid_sleep_found = True
                start_time = datetime.fromisoformat(record['start_time'].replace('Z', '+00:00'))
                end_time = datetime.fromisoformat(record['end_time'].replace('Z', '+00:00'))
                
                # Create a unique key using start_time and end_time
                record_key = f"{start_time.isoformat()}-{end_time.isoformat()}"
                
                # Only process this record if we haven't seen it before
                if record_key not in unique_records:
                    unique_records[record_key] = {
                        'start_time': start_time,
                        'end_time': end_time,
                        'sleep_stage': record['sleep_stage'],
                        'duration': (end_time - start_time).total_seconds() / 60  # duration in minutes
                    }
            
            if not valid_sleep_found:
                sleep_data = None
            else:
                # Now process the unique records to find sleep sessions
                sleep_sessions = {}
                for record in unique_records.values():
                    # Use the end_time date as the session key
                    session_key = record['end_time'].date().isoformat()
                    
                    if session_key not in sleep_sessions:
                        sleep_sessions[session_key] = {
                            'total_duration': 0,
                            'stages': {},
                            'start_time': record['start_time'],
                            'end_time': record['end_time']
                        }
                    
                    session = sleep_sessions[session_key]
                    session['total_duration'] += record['duration']
                    
                    # Update session time bounds
                    session['start_time'] = min(session['start_time'], record['start_time'])
                    session['end_time'] = max(session['end_time'], record['end_time'])
                    
                    # Aggregate duration by sleep stage
                    stage = record['sleep_stage'].upper()  # Normalize stage names
                    if stage not in session['stages']:
                        session['stages'][stage] = 0
                    session['stages'][stage] += record['duration']
                
                # Find the most recent sleep session
                if sleep_sessions:
                    # Sort sessions by date and find the most recent one
                    sorted_sessions = sorted(sleep_sessions.items(), key=lambda x: x[0], reverse=True)
                    most_recent_session = sorted_sessions[0]  # Take the most recent session
                    
                    sleep_data = {
                        'date': most_recent_session[0],
                        'total_duration_minutes': round(most_recent_session[1]['total_duration'], 2),
                        'total_duration_hours': round(most_recent_session[1]['total_duration'] / 60, 2),
                        'start_time': most_recent_session[1]['start_time'].isoformat(),
                        'end_time': most_recent_session[1]['end_time'].isoformat(),
                        'stages': {
                            stage: round(duration, 2) 
                            for stage, duration in most_recent_session[1]['stages'].items()
                        }
                    }
                else:
                    sleep_data = None
        else:
            sleep_data = None
            
        # Get user notes from the last 30 days (keeping this the same for context)
        notes_end_date = datetime.utcnow()
        notes_start_date = notes_end_date - timedelta(days=30)
        notes_response = supabase.table('user_notes')\
            .select('note, created_at')\
            .eq('device_id', device_internal_id)\
            .gte('created_at', notes_start_date.isoformat())\
            .lte('created_at', notes_end_date.isoformat())\
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

        # Get user characteristics
        characteristics_response = supabase.table('user_characteristics')\
            .select('*')\
            .eq('device_id', device_internal_id)\
            .single()\
            .execute()

        characteristics_data = None
        if characteristics_response.data:
            char_data = characteristics_response.data
            # Map biological sex from numeric to string values
            biological_sex_map = {
                '2': 'male',
                '1': 'female',
                '0': 'undefined'
            }
            biological_sex = char_data.get('biological_sex')
            characteristics_data = {
                'date_of_birth': char_data.get('date_of_birth'),
                'biological_sex': biological_sex_map.get(biological_sex, 'undefined'),
                'blood_type': char_data.get('blood_type'),
                'last_updated': char_data.get('updated_at')
            }

        # Get latest body measurements
        measurements_response = supabase.table('body_measurements')\
            .select('measurement_type, value, unit, timestamp')\
            .eq('device_id', device_internal_id)\
            .order('timestamp', desc=True)\
            .execute()

        # Process body measurements to get latest value for each type
        body_measurements = {}
        if measurements_response.data:
            for measurement in measurements_response.data:
                measurement_type = measurement['measurement_type']
                # Only store if we haven't seen this type yet (since ordered by timestamp desc)
                if measurement_type not in body_measurements:
                    body_measurements[measurement_type] = {
                        'value': measurement['value'],
                        'unit': measurement['unit'],
                        'timestamp': measurement['timestamp']
                    }

        # Calculate BMI if we have both height and weight but no BMI measurement
        if 'height' in body_measurements and 'weight' in body_measurements and 'bmi' not in body_measurements:
            try:
                height_m = float(body_measurements['height']['value'])
                weight_kg = float(body_measurements['weight']['value'])
                if height_m > 0:
                    bmi = weight_kg / (height_m * height_m)
                    body_measurements['bmi'] = {
                        'value': round(bmi, 2),
                        'unit': 'kg/m²',
                        'timestamp': max(body_measurements['height']['timestamp'],
                                      body_measurements['weight']['timestamp']),
                        'calculated': True
                    }
            except (ValueError, TypeError) as e:
                logger.error(f"Error calculating BMI: {str(e)}")
        
        return {
            'heart_rate': heart_rate_stats,
            'steps': steps_response.data,
            'sleep': sleep_data,
            'notes': formatted_notes,
            'characteristics': characteristics_data,
            'body_measurements': body_measurements,
            'metadata': {
                'date': latest_date.date().isoformat(),
                'device_id': user_id,
                'time_range': 'daily',
                'start_date': start_of_day.isoformat(),
                'end_date': end_of_day.isoformat()
            }
        }

    except Exception as e:
        logger.error(f"Error retrieving metrics for user {user_id}: {str(e)}", exc_info=True)
        raise