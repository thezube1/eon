from flask import Blueprint, request, jsonify, current_app
from google import genai
from google.genai import types
import json
import logging
import requests
from utils.retrieve_user_metrics import retrieve_user_metrics
from utils.retrieve_user_notes import retrieve_user_notes
from utils.soap_generator import generate_soap_note
from utils.store_recommendations import store_recommendations
from utils.retrive_user_recommendations import retrieve_user_recommendations
from utils.supabase.init_supabase import init_supabase

# Configure logging
logger = logging.getLogger(__name__)

# Create Blueprint
recommendations_bp = Blueprint('recommendations', __name__)

# Initialize Supabase client
try:
    supabase = init_supabase()
    logger.info("Supabase client initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize Supabase client: {str(e)}", exc_info=True)
    raise

def generate_recommendations(soap_note: str, formatted_predictions: list, past_recommendations: dict = None, user_notes: list = None) -> str:
    """
    Generate personalized health recommendations using Gemini model.
    
    Args:
        soap_note (str): The SOAP note containing patient data
        formatted_predictions (list): List of risk predictions and their explanations
        past_recommendations (dict): Dictionary of past recommendations categorized by acceptance status
        user_notes (list): List of user notes with timestamps
        
    Returns:
        str: JSON string containing structured recommendations
    """
    client = genai.Client(
        vertexai=True,
        project="eon-health-450706",
        location="us-central1",
    )

    # Calculate recommended number of recommendations per category based on risk analysis
    category_recommendation_counts = {
        "Sleep": 0,
        "Steps": 0,
        "Heart_Rate": 0
    }
    
    # Map risk levels to numeric values for calculation
    risk_level_weights = {
        "Low Risk": 1,
        "Medium Risk": 2,
        "Moderate Risk": 2,
        "High Risk": 3
    }
    
    # Analyze predictions to determine recommendation counts
    for prediction in formatted_predictions:
        risk_level = prediction.get('risk_level', '').lower()
        diseases = prediction.get('diseases', [])
        cluster = prediction.get('cluster_name', '').lower()
        
        # Calculate base count from risk level and disease count
        risk_weight = risk_level_weights.get(risk_level, 1)
        disease_count = len(diseases)
        
        # Calculate recommendation count: 1-2 for low risk/few diseases, 2-3 for medium, 3-4 for high risk/many diseases
        rec_count = min(4, max(1, risk_weight + (disease_count // 3)))
        
        # Map cluster to health metric categories
        if 'sleep' in cluster:
            category_recommendation_counts['Sleep'] = max(category_recommendation_counts['Sleep'], rec_count)
        elif 'activity' in cluster or 'exercise' in cluster:
            category_recommendation_counts['Steps'] = max(category_recommendation_counts['Steps'], rec_count)
        elif 'heart' in cluster or 'cardio' in cluster:
            category_recommendation_counts['Heart_Rate'] = max(category_recommendation_counts['Heart_Rate'], rec_count)

    # Ensure at least 1 recommendation per category
    for category in category_recommendation_counts:
        if category_recommendation_counts[category] == 0:
            category_recommendation_counts[category] = 1

    # Prepare input for Gemini
    input_text = f"""SOAP Note:
{soap_note}

Risk Analysis Results:
{json.dumps(formatted_predictions, indent=2)}

Recommended recommendation counts per category:
{json.dumps(category_recommendation_counts, indent=2)}"""

    # Add past recommendations to input if available
    if past_recommendations:
        input_text += f"""

Past Accepted Recommendations:
{json.dumps(past_recommendations['accepted'], indent=2)}

Past Unaccepted Recommendations:
{json.dumps(past_recommendations['unaccepted'], indent=2)}"""

    # Add user notes to input if available
    if user_notes and len(user_notes) > 0:
        input_text += f"""

User Notes:
{json.dumps(user_notes, indent=2)}"""

    text_part = types.Part.from_text(text=input_text)
    
    system_instruction = f"""You are a health recommendations generator. Based on the provided SOAP note, risk analysis, past recommendations (if available), and user notes (if available), generate practical, actionable recommendations that anyone can implement in their daily life. Focus on three specific categories: Sleep, Steps, and Heart Rate.

Your task is to:
1. Analyze the SOAP note, risk predictions, and user notes
2. Generate recommendations according to the specified counts for each category:
   - Sleep: {max(2, category_recommendation_counts['Sleep'])} recommendations
   - Steps: {max(2, category_recommendation_counts['Steps'])} recommendations
   - Heart Rate: {max(2, category_recommendation_counts['Heart_Rate'])} recommendations

3. If user notes are provided:
   - Analyze the notes to understand the user's daily habits, physical/mental feelings, and activities
   - Adapt recommendations to align with the user's lifestyle and preferences mentioned in their notes
   - Directly reference specific habits or activities mentioned in the notes when relevant

4. If past recommendations are provided:
   - Study the accepted recommendations to understand user preferences
   - Avoid repeating exact recommendations that were previously unaccepted
   - Generate new recommendations that align with the style and complexity of accepted recommendations
   
5. Return ONLY a valid JSON object in exactly this format (no other text before or after):

{{
    "Sleep": [
        {{
            "recommendation": "string",
            "explanation": "string",
            "frequency": "string",
            "risk_cluster": "string"
        }}
    ],
    "Steps": [
        {{
            "recommendation": "string",
            "explanation": "string",
            "frequency": "string",
            "risk_cluster": "string"
        }}
    ],
    "Heart_Rate": [
        {{
            "recommendation": "string",
            "explanation": "string",
            "frequency": "string",
            "risk_cluster": "string"
        }}
    ]
}}

Guidelines:
1. Generate EXACTLY the number of recommendations specified for each category, but NEVER less than 2
2. Ensure all recommendations are UNIQUE and DISTINCT from each other - each recommendation should target a different aspect of health within its category
3. For each recommendation, specify the risk cluster it addresses from the risk analysis results
4. Recommendations should be specific and actionable
5. Focus on lifestyle changes that don't require special equipment
6. Avoid medical advice or treatment suggestions
7. Keep recommendations simple and achievable
8. Include clear frequency guidelines
9. Explanations should reference the data from the SOAP note, risk analysis, or user notes
10. If past accepted recommendations exist, maintain a similar style and complexity level
11. Ensure new recommendations are unique and not duplicates of past ones
12. Avoid extreme similarity between recommendations - each should offer a different approach or target a different aspect
13. When user notes mention specific activities, habits, preferences, or physical/mental feelings, tailor recommendations to address or incorporate these personal aspects
14. Return ONLY the JSON object - no other text, no markdown formatting

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
        #base_url = "http://localhost:8000"
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
            
            # Get past recommendations for the user
            past_recommendations = retrieve_user_recommendations(user_id)
            
            # Get user notes for the user
            user_notes = retrieve_user_notes(user_id)
            logger.info(f"Retrieved {len(user_notes)} notes for user {user_id}")
            
        except json.JSONDecodeError as e:
            logger.error(f"Failed to decode risk analysis response: {str(e)}")
            logger.error(f"Response content: {risk_analysis_response.text}")
            return jsonify({
                'error': 'Invalid response from risk analysis service'
            }), 500
            
        # Generate recommendations using stored predictions, generated SOAP note, past recommendations, and user notes
        recommendations = generate_recommendations(soap_note, formatted_predictions, past_recommendations, user_notes)
        
        # Store recommendations in database
        storage_success = store_recommendations(user_id, recommendations)
        if not storage_success:
            logger.warning("Failed to store recommendations in database")
        
        response_data = {
            'recommendations': recommendations,
            'source_data': {
                'soap_note': soap_note,
                'formatted_predictions': formatted_predictions,
                'past_recommendations': past_recommendations,
                'user_notes': user_notes
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
