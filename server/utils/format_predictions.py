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
    Filters out uncategorized and unrecognized predictions.
    
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
        
        system_instruction = """You are an expert clinical risk interpreter. Your task is to transform the raw output of a predictive disease model into a concise, interpretable summary for a mobile app frontend, with a focus on preventive health awareness rather than definitive diagnoses. You will receive input as a JSON object that includes:
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
For each VALID prediction (ignore any with "Description not found" or unknown descriptions), assign a risk category based primarily on the user's metrics and clinical notes, NOT just the probability score. The default assumption should be that the user is healthy. Only escalate risk levels if there are clear, concerning indicators in the metrics or notes.

Risk Levels should be assigned as follows:
High Risk: Only if there are multiple severe abnormalities in metrics (e.g., consistently very high blood pressure, concerning heart rate patterns) OR explicit concerning symptoms in the notes
Moderate Risk: If there are some concerning metrics or symptoms, but not severe enough to warrant immediate attention
Low Risk: The default level - assign this if metrics are normal or only slightly outside normal ranges

Disease Clustering:
Group similar or related diseases into these specific clusters ONLY:
- "Cardiovascular" (heart, circulation related)
- "Respiratory" (breathing, lung related)
- "Metabolic" (metabolism, diabetes, obesity related)
- "Neurological" (brain, nerve related)
- "Sleep" (sleep disorders, insomnia related)
- "Musculoskeletal" (muscle, bone, joint related)
DO NOT create any other cluster types.
If a prediction doesn't clearly fit into one of these clusters, exclude it completely.
DO NOT include any "Other" or "Uncategorized" clusters.
DO NOT include any predictions with "Description not found" or unclear descriptions.

Output Format:
Format your output as a JSON array of clusters. Each cluster should be an object with:
- cluster_name: string (must be one of the specified clusters above)
- diseases: array of objects with description and icd9_code (only include valid, recognized diseases)
- risk_level: string ("High Risk", "Moderate Risk", or "Low Risk")
- explanation: string that focuses on preventive health awareness. For example:
  - Low Risk: "Your metrics are normal. These conditions are listed for awareness and prevention."
  - Moderate Risk: "Some metrics suggest areas for lifestyle improvement to prevent these conditions."
  - High Risk: "Multiple concerning indicators suggest discussing these conditions with a healthcare provider."

Make sure your output is clear, concise, and formatted as valid JSON. Use the input data to support your risk interpretations.
If no valid predictions remain after filtering, return an empty array.

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
            
            # Additional validation to ensure we only have valid clusters
            valid_clusters = ["Cardiovascular", "Respiratory", "Metabolic", "Neurological", "Sleep", "Musculoskeletal"]
            filtered_response = [
                cluster for cluster in parsed_response 
                if cluster["cluster_name"] in valid_clusters 
                and all(disease.get("description") != "Description not found" 
                       and disease.get("description") is not None 
                       for disease in cluster["diseases"])
            ]
            
            if isinstance(parsed_response, dict) and "response" in parsed_response:
                # If we got a response wrapper, parse the inner content
                inner_response = json.loads(parsed_response["response"])
                return inner_response
            return filtered_response
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