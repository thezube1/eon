from flask import Blueprint, request, jsonify, current_app
from google import genai
from google.genai import types
import json
import logging
import requests
from utils.retrieve_user_metrics import retrieve_user_metrics
from utils.soap_generator import generate_soap_note
from utils.store_recommendations import store_recommendations
from supabase import create_client

# Configure logging
logger = logging.getLogger(__name__)

# Create Blueprint
recommendations_bp = Blueprint('recommendations', __name__)

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

def generate_recommendations(soap_note: str, formatted_predictions: list) -> str:
    """
    Generate personalized health recommendations using Gemini model.
    
    Args:
        soap_note (str): The SOAP note containing patient data
        formatted_predictions (list): List of risk predictions and their explanations
        
    Returns:
        str: JSON string containing structured recommendations
    """
    client = genai.Client(
        vertexai=True,
        project="eon-health-450706",
        location="us-central1",
    )

    # Prepare input for Gemini
    input_text = f"""SOAP Note:
{soap_note}

Risk Analysis Results:
{json.dumps(formatted_predictions, indent=2)}"""

    text_part = types.Part.from_text(text=input_text)
    
    system_instruction = """You are a health recommendations generator. Based on the provided SOAP note and risk analysis, generate practical, actionable recommendations that anyone can implement in their daily life. Focus on three specific categories: Sleep, Steps, and Heart Rate.

Your task is to:
1. Analyze the SOAP note and risk predictions
2. Generate specific, actionable recommendations for each category
3. Return ONLY a valid JSON object in exactly this format (no other text before or after):

{
    "Sleep": [
        {
            "recommendation": "string",
            "explanation": "string",
            "frequency": "string"
        }
    ],
    "Steps": [
        {
            "recommendation": "string",
            "explanation": "string",
            "frequency": "string"
        }
    ],
    "Heart_Rate": [
        {
            "recommendation": "string",
            "explanation": "string",
            "frequency": "string"
        }
    ]
}

Guidelines:
1. Each category should have 2-4 recommendations
2. Recommendations should be specific and actionable
3. Focus on lifestyle changes that don't require special equipment
4. Avoid medical advice or treatment suggestions
5. Keep recommendations simple and achievable
6. Include clear frequency guidelines
7. Explanations should reference the data from the SOAP note or risk analysis
8. Return ONLY the JSON object - no other text, no markdown formatting

IMPORTANT: Your response must be a valid JSON object and nothing else. Do not include any explanatory text, markdown formatting, or code blocks."""

    model = "gemini-2.0-flash-001"
    contents = [
        types.Content(
            role="user",
            parts=[text_part]
        )
    ]
    
    generate_content_config = types.GenerateContentConfig(
        temperature=0.7,
        top_p=0.95,
        max_output_tokens=8192,
        response_modalities=["TEXT"],
        safety_settings=[
            types.SafetySetting(
                category="HARM_CATEGORY_HATE_SPEECH",
                threshold="OFF"
            ),
            types.SafetySetting(
                category="HARM_CATEGORY_DANGEROUS_CONTENT",
                threshold="OFF"
            ),
            types.SafetySetting(
                category="HARM_CATEGORY_SEXUALLY_EXPLICIT",
                threshold="OFF"
            ),
            types.SafetySetting(
                category="HARM_CATEGORY_HARASSMENT",
                threshold="OFF"
            )
        ],
        system_instruction=[types.Part.from_text(text=system_instruction)],
    )

    try:
        response = client.models.generate_content(
            model=model,
            contents=contents,
            config=generate_content_config,
        )
        
        # Get the response text and clean it
        response_text = response.text.strip()
        
        # Try to find JSON content if there's any extra text
        try:
            # First try to parse as is
            recommendations = json.loads(response_text)
        except json.JSONDecodeError:
            # If that fails, try to find JSON object in the text
            start_idx = response_text.find('{')
            end_idx = response_text.rfind('}') + 1
            
            if start_idx != -1 and end_idx != 0:
                json_content = response_text[start_idx:end_idx]
                try:
                    recommendations = json.loads(json_content)
                except json.JSONDecodeError:
                    logger.error(f"Failed to parse JSON content: {json_content}")
                    raise
            else:
                logger.error(f"No valid JSON found in response: {response_text}")
                raise ValueError("Generated content is not in valid JSON format")
        
        # Validate the structure of the recommendations
        required_categories = ["Sleep", "Steps", "Heart_Rate"]
        required_fields = ["recommendation", "explanation", "frequency"]
        
        for category in required_categories:
            if category not in recommendations:
                recommendations[category] = []
            if not isinstance(recommendations[category], list):
                recommendations[category] = []
            
            # Ensure each recommendation has all required fields
            for rec in recommendations[category]:
                for field in required_fields:
                    if field not in rec:
                        rec[field] = "Not specified"
        
        return recommendations
        
    except Exception as e:
        logger.error(f"Error generating recommendations: {str(e)}")
        # Return a basic structure if generation fails
        return {
            "Sleep": [{"recommendation": "Unable to generate recommendation", "explanation": "Error in processing", "frequency": "N/A"}],
            "Steps": [{"recommendation": "Unable to generate recommendation", "explanation": "Error in processing", "frequency": "N/A"}],
            "Heart_Rate": [{"recommendation": "Unable to generate recommendation", "explanation": "Error in processing", "frequency": "N/A"}]
        }

@recommendations_bp.route('/recommendations', methods=['POST'])
def get_recommendations():
    """Generate personalized health recommendations based on risk analysis"""
    try:
        data = request.json
        
        # Check if user_id is provided
        user_id = data.get('user_id')
        
        if not user_id:
            return jsonify({
                'error': 'Missing required data. Must provide user_id.'
            }), 400
            
        # Get risk analysis from database using GET endpoint
        logger.info(f"Getting stored risk analysis for user {user_id}")
        
        # Make internal request to risk analysis GET endpoint
        base_url = "https://eon-550878280011.us-central1.run.app"
        risk_analysis_response = requests.get(
            f"{base_url}/api/risk-analysis/{user_id}",
            headers={"Content-Type": "application/json"},
            verify=True
        )
        
        logger.info(f"Risk analysis response status: {risk_analysis_response.status_code}")
        
        if risk_analysis_response.status_code != 200:
            error_msg = f"Risk analysis failed with status {risk_analysis_response.status_code}"
            try:
                error_content = risk_analysis_response.text
                logger.error(f"Error response content: {error_content}")
                error_msg += f". Response: {error_content}"
            except:
                pass
            return jsonify({'error': error_msg}), risk_analysis_response.status_code
            
        try:
            risk_analysis_data = risk_analysis_response.json()
            logger.info("Successfully parsed risk analysis response")
            
            # Check if we have any predictions
            if not risk_analysis_data.get('predictions'):
                return jsonify({
                    'error': 'No risk analysis predictions available for this user.'
                }), 404
                
            formatted_predictions = risk_analysis_data['predictions']
            
            # Get SOAP note for the user
            metrics = retrieve_user_metrics(user_id)
            if metrics:
                formatted_metrics = json.dumps(metrics, indent=2)
                soap_note = generate_soap_note(formatted_metrics)
            else:
                logger.warning(f"No metrics found for user {user_id}, generating SOAP note from predictions only")
                soap_note = generate_soap_note(json.dumps(formatted_predictions, indent=2))
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to decode risk analysis response: {str(e)}")
            logger.error(f"Response content: {risk_analysis_response.text}")
            return jsonify({
                'error': 'Invalid response from risk analysis service'
            }), 500
            
        # Generate recommendations using stored predictions and generated SOAP note
        recommendations = generate_recommendations(soap_note, formatted_predictions)
        
        # Store recommendations in database
        storage_success = store_recommendations(user_id, recommendations)
        if not storage_success:
            logger.warning("Failed to store recommendations in database")
        
        response_data = {
            'recommendations': recommendations,
            'source_data': {
                'soap_note': soap_note,
                'formatted_predictions': formatted_predictions
            },
            'user_id': user_id
        }
            
        return jsonify(response_data), 200
        
    except Exception as e:
        logger.error(f"Error in recommendations generation: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500

@recommendations_bp.route('/recommendations/<device_id>', methods=['GET'])
def get_device_recommendations(device_id):
    """Retrieve all recommendations for a given device"""
    try:
        # First verify the device exists and get internal ID
        device_response = supabase.table('devices').select('id').eq('device_id', device_id).execute()
        if not device_response.data:
            return jsonify({'error': 'Device not found'}), 404
            
        device_internal_id = device_response.data[0]['id']
        logger.info(f"Found device with internal ID: {device_internal_id}")
        
        # Get all recommendations for this device
        recommendations_response = supabase.table('recommendations')\
            .select('*')\
            .eq('device_id', device_internal_id)\
            .order('created_at', desc=True)\
            .execute()
            
        # Group recommendations by category
        categorized_recommendations = {
            'Sleep': [],
            'Steps': [],
            'Heart_Rate': []
        }
        
        for rec in recommendations_response.data:
            category = rec['category']
            if category in categorized_recommendations:
                categorized_recommendations[category].append({
                    'id': rec['id'],
                    'recommendation': rec['recommendation'],
                    'explanation': rec['explanation'],
                    'frequency': rec['frequency'],
                    'accepted': rec['accepted']
                })
        
        return jsonify({
            'recommendations': categorized_recommendations,
            'user_id': device_id
        })
        
    except Exception as e:
        logger.error(f"Error retrieving recommendations: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500

@recommendations_bp.route('/recommendations/<int:recommendation_id>/acceptance', methods=['PUT'])
def update_recommendation_acceptance(recommendation_id):
    """Update the acceptance status of a recommendation"""
    try:
        data = request.json
        if 'accepted' not in data:
            return jsonify({'error': 'Missing accepted status in request body'}), 400
            
        accepted = bool(data['accepted'])
        
        # Update the recommendation
        result = supabase.table('recommendations')\
            .update({'accepted': accepted})\
            .eq('id', recommendation_id)\
            .execute()
            
        if not result.data:
            return jsonify({'error': 'Recommendation not found'}), 404
            
        return jsonify({'message': 'Recommendation updated successfully'}), 200
        
    except Exception as e:
        logger.error(f"Error updating recommendation acceptance: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500
