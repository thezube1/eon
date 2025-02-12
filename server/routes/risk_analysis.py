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
import json

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# Global variables for model management
model = None
tokenizer = None
model_loading = False
model_lock = threading.Lock()
icd9_codes = None

def load_icd9_codes():
    """Load ICD9 codes from JSON file"""
    global icd9_codes
    try:
        codes_path = os.path.join(os.path.dirname(__file__), '../data/codes.json')
        with open(codes_path, 'r') as f:
            icd9_codes = json.load(f)
        logger.info("Successfully loaded ICD9 codes")
    except Exception as e:
        logger.error(f"Error loading ICD9 codes: {str(e)}")
        icd9_codes = {}

def get_code_description(code):
    """Get hierarchical description for an ICD9 code"""
    if not icd9_codes:
        load_icd9_codes()
    
    # Find the matching code entry
    for entry in icd9_codes:
        # Each entry is a list representing the hierarchy path
        # The last item contains the actual code we're looking for
        if len(entry) > 0 and len(entry[-1]) > 0:
            code_obj = entry[-1]
            if code_obj.get('code') == code:
                # Build hierarchical description
                hierarchy = []
                for level in entry:
                    if level and isinstance(level, dict):
                        desc = level.get('descr', '').strip()
                        if desc:
                            hierarchy.append(desc)
                
                # Return both full hierarchy and immediate description
                return {
                    'full_hierarchy': ' > '.join(hierarchy),
                    'description': code_obj.get('descr', 'Unknown'),
                    'parent_category': hierarchy[-2] if len(hierarchy) > 1 else None
                }
    
    return {
        'full_hierarchy': 'Unknown classification',
        'description': 'Description not found',
        'parent_category': None
    }

def load_model_in_background():
    global model, tokenizer, model_loading
    try:
        logger.info("Starting to load CORe clinical diagnosis prediction model...")
        start_time = datetime.now()
        
        cache_dir = os.getenv('TRANSFORMERS_CACHE', '/app/.cache/huggingface')
        logger.info(f"Using cache directory: {cache_dir}")
        
        try:
            logger.info("Loading model and tokenizer...")
            model_name = "DATEXIS/CORe-clinical-diagnosis-prediction"
            tokenizer = AutoTokenizer.from_pretrained(model_name)
            model = AutoModelForSequenceClassification.from_pretrained(model_name)
            
            end_time = datetime.now()
            load_duration = (end_time - start_time).total_seconds()
            logger.info(f"Model loaded successfully! Loading took {load_duration:.2f} seconds")
            
        except Exception as e:
            logger.error(f"Error during model loading: {str(e)}", exc_info=True)
            raise
            
    except Exception as e:
        logger.error(f"Error loading model: {str(e)}", exc_info=True)
        raise
    finally:
        model_loading = False
        logger.info("Model loading process completed")

risk_analysis_bp = Blueprint('risk_analysis', __name__)

@risk_analysis_bp.route('/risk-analysis', methods=['POST'])
def analyze_risk():
    """Analyze clinical text for potential diagnoses"""
    global model, tokenizer, model_loading
    
    try:
        # Check if model is still loading
        if model_loading:
            logger.info("Received request while model is still loading")
            return jsonify({'error': 'Model is still loading. Please try again in a few minutes.'}), 503
            
        # Start model loading if not started
        if model is None or tokenizer is None:
            with model_lock:
                if (model is None or tokenizer is None) and not model_loading:
                    logger.info("First request received - initiating model loading")
                    model_loading = True
                    thread = threading.Thread(target=load_model_in_background)
                    thread.start()
            return jsonify({'error': 'Model is initializing. Please try again in a few minutes.'}), 503
        
        # Process request if model is ready
        logger.info("Processing diagnosis prediction request")
        data = request.json
        clinical_text = data.get('prompt')
        if not clinical_text:
            logger.warning("Received request with missing clinical text")
            return jsonify({'error': 'Clinical text is required'}), 400
            
        logger.info("Generating diagnosis predictions")
        
        # Tokenize input
        tokenized_input = tokenizer(clinical_text, return_tensors="pt")
        
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
                code_info = get_code_description(label)
                results.append({
                    "icd9_code": label,
                    "description": code_info['description'],
                    "full_hierarchy": code_info['full_hierarchy'],
                    "parent_category": code_info['parent_category'],
                    "probability": score
                })
        
        # Sort by probability
        results.sort(key=lambda x: x["probability"], reverse=True)
        
        # Group results by parent category
        grouped_results = {}
        for result in results:
            parent = result['parent_category'] or 'Other'
            if parent not in grouped_results:
                grouped_results[parent] = []
            grouped_results[parent].append(result)
        
        logger.info(f"Generated {len(results)} predictions")
        return jsonify({
            "predictions": results,
            "grouped_predictions": grouped_results,
            "input_text": clinical_text
        }), 200
        
    except Exception as e:
        logger.error(f"Error in diagnosis prediction: {str(e)}", exc_info=True)
        return jsonify({'error': str(e)}), 500
