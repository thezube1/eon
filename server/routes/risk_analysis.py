from flask import Blueprint, request, jsonify
from datetime import datetime, timedelta
import os
from dotenv import load_dotenv
from supabase import create_client, Client
import logging
import sys
from transformers import AutoTokenizer, AutoModelForSequenceClassification
import torch
import threading
import requests
import json
from functools import lru_cache
from utils.retrieve_user_metrics import retrieve_user_metrics
from utils.format_metrics import format_metrics
from utils.soap_generator import generate_soap_note
from utils.format_predictions import format_predictions

# Configure logging - suppress unnecessary logs
logging.basicConfig(level=logging.INFO)

# Set log levels for noisy libraries
logging.getLogger('werkzeug').setLevel(logging.WARNING)  # Flask's default logger
logging.getLogger('httpcore').setLevel(logging.WARNING)  # HTTP client
logging.getLogger('httpx').setLevel(logging.WARNING)     # HTTP client
logging.getLogger('h2').setLevel(logging.WARNING)        # HTTP/2
logging.getLogger('urllib3').setLevel(logging.WARNING)   # URL lib
logging.getLogger('supabase').setLevel(logging.WARNING)  # Supabase
logging.getLogger('google').setLevel(logging.WARNING)    # Google API
logging.getLogger('transformers').setLevel(logging.WARNING)  # Hugging Face
logging.getLogger('torch').setLevel(logging.WARNING)     # PyTorch
logging.getLogger('requests').setLevel(logging.WARNING)  # Requests

logger = logging.getLogger(__name__)

# Global variables for model management
model = None
tokenizer = None
model_lock = threading.Lock()

def load_model():
    """Load the CORe clinical diagnosis prediction model."""
    global model, tokenizer
    
    with model_lock:
        if model is not None and tokenizer is not None:
            logger.info("Model already loaded")
            return
            
        try:
            logger.info("Starting to load CORe clinical diagnosis prediction model...")
            start_time = datetime.now()
            
            cache_dir = os.getenv('TRANSFORMERS_CACHE', '/app/.cache/huggingface')
            logger.info(f"Using cache directory: {cache_dir}")
            
            model_name = "DATEXIS/CORe-clinical-diagnosis-prediction"
            tokenizer = AutoTokenizer.from_pretrained(model_name)
            model = AutoModelForSequenceClassification.from_pretrained(model_name)
            
            end_time = datetime.now()
            load_duration = (end_time - start_time).total_seconds()
            logger.info(f"Model loaded successfully! Loading took {load_duration:.2f} seconds")
            
        except Exception as e:
            logger.error(f"Error during model loading: {str(e)}", exc_info=True)
            raise

@lru_cache(maxsize=1000)
def get_icd9_description(code):
    """
    Get the description for an ICD-9 code using the NLM API.
    Uses caching to improve performance for repeated lookups.
    """
    try:
        # Format code with dot if needed (e.g., 001.1 instead of 0011)
        if len(code) >= 3:
            formatted_code = f"{code[:3]}.{code[3:]}" if len(code) > 3 else code
        else:
            formatted_code = code

        # Query the NLM API
        url = f"https://clinicaltables.nlm.nih.gov/api/icd9cm_dx/v3/search"
        params = {
            "terms": formatted_code,
            "ef": "long_name",
            "sf": "code_dotted"
        }
        
        response = requests.get(url, params=params, timeout=5)
        response.raise_for_status()
        
        data = response.json()
        if data and len(data) >= 3 and data[1]:  # Check if we got valid results
            # Return the first matching description
            descriptions = data[2].get("long_name", [])
            if descriptions:
                return descriptions[0].strip()
        
        return None
    except Exception as e:
        logger.error(f"Error fetching ICD-9 description for code {code}: {str(e)}")
        return None

risk_analysis_bp = Blueprint('risk_analysis', __name__)

@risk_analysis_bp.route('/risk-analysis', methods=['POST'])
def analyze_risk():
    """Analyze clinical text and/or health metrics for potential diagnoses"""
    global model, tokenizer
    
    try:
        # Get user metrics and log them
        data = request.json
        user_id = data.get('user_id')
        formatted_metrics = None
        soap_note = None
        
        if user_id:
            logger.info(f"Retrieving metrics for user {user_id}")
            metrics = retrieve_user_metrics(user_id)
            if metrics:
                # Format and log the metrics
                formatted_metrics = format_metrics(metrics)
                logger.info("\nUser Health Metrics Summary:\n" + formatted_metrics)
            else:
                logger.warning(f"No metrics found for user {user_id}")
        
        # Process clinical text if provided
        clinical_text = data.get('prompt')
        
        # Generate SOAP note if we have either metrics or clinical text
        if clinical_text or formatted_metrics:
            input_text = ""
            if clinical_text:
                input_text += clinical_text
            if formatted_metrics:
                if input_text:
                    input_text += "\n\n"
                input_text += f"Health Metrics from the last 30 days:\n{formatted_metrics}"
            
            if input_text:
                # Generate SOAP note
                logger.info("Generating SOAP note")
                soap_note = generate_soap_note(input_text)
                logger.info("\nGenerated SOAP Note:\n" + soap_note)
        
        # Check if we have enough data for analysis
        if not soap_note and not clinical_text:
            logger.warning("No clinical text or SOAP note available for analysis")
            return jsonify({'error': 'Either clinical text or health metrics are required'}), 400
        
        # Check if model is loaded for risk analysis
        if model is None or tokenizer is None:
            logger.error("Model not loaded")
            return jsonify({'error': 'Model not initialized. Please try again later.'}), 503
            
        logger.info("Generating diagnosis predictions")
        
        # Use SOAP note for prediction if available, otherwise use clinical text
        prediction_text = soap_note if soap_note else clinical_text
        
        # Tokenize input with truncation
        tokenized_input = tokenizer(
            prediction_text,
            return_tensors="pt",
            truncation=True,
            max_length=512,
            padding=True
        )
        
        # Get model predictions
        with torch.no_grad():
            output = model(**tokenized_input)
        
        # Apply sigmoid to get probabilities
        predictions = torch.sigmoid(output.logits)
        
        # Use threshold to determine predicted labels
        threshold = 0.3  # Can be adjusted based on requirements
        predicted_indices = (predictions > threshold).nonzero()[:, 1].tolist()
        
        # Get predictions with scores and descriptions
        results = []
        for idx in predicted_indices:
            label = model.config.id2label[idx]
            score = float(predictions[0][idx])
            # Only include 3-digit ICD9 codes as recommended
            if len(label.split('.')[0]) == 3:  # Basic check for 3-digit codes
                # Get description from NLM API
                description = get_icd9_description(label.replace('.', ''))
                results.append({
                    "icd9_code": label,
                    "probability": score,
                    "description": description or "Description not found"
                })
        
        # Sort by probability
        results.sort(key=lambda x: x["probability"], reverse=True)
        
        # Create response data
        response_data = {
            "predictions": results,
            "input_text": clinical_text if clinical_text else None,
            "soap_note": soap_note,
            "metrics_summary": formatted_metrics if formatted_metrics else None,
            "analysis_text_used": "SOAP Note" if soap_note else "Clinical Text"
        }
        
        # Format predictions using Gemini
        logger.info("Formatting predictions with Gemini")
        formatted_predictions = format_predictions(response_data)
        if isinstance(formatted_predictions, dict) and "error" in formatted_predictions:
            logger.error(f"Error formatting predictions: {formatted_predictions['error']}")
            if "raw_response" in formatted_predictions:
                logger.debug(f"Raw response: {formatted_predictions['raw_response']}")
        else:
            logger.info(f"\nFormatted Predictions:\n{json.dumps(formatted_predictions, indent=2)}")
        
        # Add formatted predictions to response
        response_data["formatted_predictions"] = formatted_predictions
        
        return jsonify(response_data), 200
        
    except Exception as e:
        logger.error(f"Error in diagnosis prediction: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500
