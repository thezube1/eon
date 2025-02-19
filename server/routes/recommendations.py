from flask import Blueprint, request, jsonify, current_app
from google import genai
from google.genai import types
import json
import logging
import requests

# Configure logging
logger = logging.getLogger(__name__)

recommendations_bp = Blueprint('recommendations', __name__)

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
        
        if user_id:
            # Make internal request to risk analysis endpoint
            logger.info(f"Running risk analysis for user {user_id}")
            
            # Get the server's base URL from the request
            if request.headers.get('Host'):
                base_url = f"http://{request.headers['Host']}"
            else:
                base_url = "http://localhost:8000"  # Default fallback
                
            risk_analysis_response = requests.post(
                f"{base_url}/api/risk-analysis",
                json={"user_id": user_id},
                headers={"Content-Type": "application/json"}
            )
            
            if risk_analysis_response.status_code != 200:
                return jsonify(risk_analysis_response.json()), risk_analysis_response.status_code
                
            risk_analysis_data = risk_analysis_response.json()
            soap_note = risk_analysis_data.get('soap_note')
            formatted_predictions = risk_analysis_data.get('formatted_predictions')
        else:
            # Use directly provided data
            soap_note = data.get('soap_note')
            formatted_predictions = data.get('formatted_predictions')
        
        if not soap_note or not formatted_predictions:
            return jsonify({
                'error': 'Missing required data. Either provide user_id or both soap_note and formatted_predictions.'
            }), 400
            
        # Generate recommendations
        recommendations = generate_recommendations(soap_note, formatted_predictions)
        
        response_data = {
            'recommendations': recommendations,
            'source_data': {
                'soap_note': soap_note,
                'formatted_predictions': formatted_predictions
            }
        }
        
        # Add user_id to response if it was provided
        if user_id:
            response_data['user_id'] = user_id
            
        return jsonify(response_data), 200
        
    except Exception as e:
        logger.error(f"Error in recommendations generation: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500
