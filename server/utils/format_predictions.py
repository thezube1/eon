from google import genai
from google.genai import types
import json
import logging
import sys

# Simple logger without custom configuration
logger = logging.getLogger(__name__)

def format_predictions(data: dict) -> dict:
    """
    Format prediction data using Gemini AI to create a more usable summary.
    
    Args:
        data (dict): Dictionary containing predictions, metrics, and SOAP note
        
    Returns:
        dict: Formatted dictionary containing the model's interpretation
    """
    try:
        client = genai.Client(
            vertexai=True,
            project="eon-health-450706",
            location="us-central1",
        )

        # Convert input data to JSON string
        text_part = types.Part.from_text(text=json.dumps(data))
        
        system_instruction = """You are an expert clinical risk interpreter. Your task is to transform the raw output of a predictive disease model into a concise, interpretable summary for a mobile app frontend. You will receive input as a JSON object that includes:
analysis_text_used (e.g. "SOAP Note")
input_text (patient's self-report)
metrics_summary (aggregated wearable/lifestyle metrics)
predictions: a list of predicted diseases, where each prediction has:
"description" (e.g., "Coronary atherosclerosis of unspecified type of vessel, native or graft")
"icd9_code" (e.g., "414")
"probability" (a float between 0 and 1)
soap_note (a full SOAP note summarizing the case)

Your output should do the following:
Risk Categorization:
For each prediction, assign a risk category based on its probability:
High Risk: if probability ≥ 0.85
Moderate Risk: if probability is between 0.70 and 0.85
Low Risk: if probability < 0.70

Disease Clustering:
Group similar or related diseases into general clusters. For example, conditions related to heart health (like "Coronary atherosclerosis" and "Orthostatic hypotension") should be grouped under a "Cardiovascular" cluster.
Other clusters might include "Metabolic/Obesity," "Sleep Disorders," "Respiratory," "Neurological," etc.
If a prediction does not clearly fall into a known category (e.g., "Description not found" or ambiguous codes), assign it to an "Other" or "Uncategorized" group.

Output Format:
Format your output as a JSON array of clusters. Each cluster should be an object with:
- cluster_name: string
- diseases: array of objects with description and icd9_code
- risk_level: string ("High Risk", "Moderate Risk", or "Low Risk")
- explanation: string explaining the risk level

Make sure your output is clear, concise, and formatted as valid JSON. Use the input data to support your risk interpretations.

IMPORTANT: Return ONLY the JSON array, with no additional text or formatting."""

        model = "gemini-2.0-flash-001"
        contents = [
            types.Content(
                role="user",
                parts=[text_part]
            )
        ]
        
        generate_content_config = types.GenerateContentConfig(
            temperature=1,
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

        # Collect the complete response
        response_text = ""
        for chunk in client.models.generate_content_stream(
            model=model,
            contents=contents,
            config=generate_content_config,
        ):
            response_text += chunk.text
            
        # Clean up the response text
        response_text = response_text.strip()
        # Remove markdown code blocks if present
        if response_text.startswith("```"):
            # Remove the first line (```json or similar)
            response_text = "\n".join(response_text.split("\n")[1:])
        if response_text.endswith("```"):
            # Remove the last line (```)
            response_text = "\n".join(response_text.split("\n")[:-1])
        # Remove any remaining whitespace and quotes
        response_text = response_text.strip().strip('"')
        
        # Try to parse the response as JSON
        try:
            parsed_response = json.loads(response_text)
            if isinstance(parsed_response, dict) and "response" in parsed_response:
                # If we got a response wrapper, parse the inner content
                inner_response = json.loads(parsed_response["response"])
                return inner_response
            return parsed_response
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse Gemini response as JSON: {response_text}")
            logger.error(f"JSON decode error: {str(e)}")
            return {
                "error": "Failed to parse response",
                "raw_response": response_text[:1000]  # Include first 1000 chars of raw response for debugging
            }
            
    except Exception as e:
        logger.error(f"Error in format_predictions: {str(e)}", exc_info=True)
        return {
            "error": f"Error processing predictions: {str(e)}",
            "details": str(e.__class__.__name__)
        }