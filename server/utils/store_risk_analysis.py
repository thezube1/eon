from datetime import datetime
import logging
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

def store_risk_analysis(device_id: str, analysis_text_used: str, formatted_predictions: list) -> bool:
    """
    Store the formatted risk analysis predictions in Supabase.
    If a cluster already exists for the device, merge any new diseases into it.
    
    Args:
        device_id (str): The device_id of the user
        analysis_text_used (str): The type of analysis used (e.g., "SOAP Note" or "Clinical Text")
        formatted_predictions (list): List of prediction clusters from format_predictions
        
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
        
        # Store each prediction cluster
        for cluster in formatted_predictions:
            # Check if this cluster already exists for this device
            existing_cluster = supabase.table('risk_analysis_predictions')\
                .select('*')\
                .eq('device_id', device_internal_id)\
                .eq('cluster_name', cluster['cluster_name'])\
                .order('created_at', desc=True)\
                .limit(1)\
                .execute()
            
            if existing_cluster.data:
                # Cluster exists, merge new diseases with existing ones
                existing_diseases = existing_cluster.data[0]['diseases']
                new_diseases = cluster['diseases']
                
                # Create a set of existing ICD9 codes
                existing_icd9_codes = {disease['icd9_code'] for disease in existing_diseases}
                
                # Add only new diseases that don't exist in the current set
                merged_diseases = existing_diseases.copy()
                for disease in new_diseases:
                    if disease['icd9_code'] not in existing_icd9_codes:
                        merged_diseases.append(disease)
                        existing_icd9_codes.add(disease['icd9_code'])
                
                # Update the existing cluster with merged diseases
                update_data = {
                    'diseases': merged_diseases,
                    'risk_level': cluster['risk_level'],  # Update risk level with latest
                    'explanation': cluster['explanation'],  # Update explanation with latest
                    'created_at': datetime.utcnow().isoformat()  # Update timestamp
                }
                
                logger.info(f"Updating existing cluster: {cluster['cluster_name']} with merged diseases")
                result = supabase.table('risk_analysis_predictions')\
                    .update(update_data)\
                    .eq('id', existing_cluster.data[0]['id'])\
                    .execute()
                    
                if not result.data:
                    logger.error(f"Failed to update cluster: {cluster['cluster_name']}")
                    return False
            else:
                # No existing cluster, create new one
                prediction_data = {
                    'device_id': device_internal_id,
                    'cluster_name': cluster['cluster_name'],
                    'risk_level': cluster['risk_level'],
                    'explanation': cluster['explanation'],
                    'diseases': cluster['diseases'],
                    'created_at': datetime.utcnow().isoformat()
                }
                
                logger.info(f"Creating new prediction cluster: {cluster['cluster_name']}")
                result = supabase.table('risk_analysis_predictions').insert(prediction_data).execute()
                
                if not result.data:
                    logger.error(f"Failed to store prediction cluster: {cluster['cluster_name']}")
                    return False
                
        logger.info(f"Successfully processed {len(formatted_predictions)} prediction clusters")
        return True
        
    except Exception as e:
        logger.error(f"Error storing risk analysis for device {device_id}: {str(e)}", exc_info=True)
        return False
