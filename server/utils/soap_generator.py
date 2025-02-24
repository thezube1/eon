from google import genai
from google.genai import types

def generate_soap_note(input_text: str) -> str:
    """
    Generate a SOAP note using Gemini model based on input text.
    Focuses on objective data and user-reported symptoms without speculation.
    
    Args:
        input_text (str): The input text containing patient data and notes
        
    Returns:
        str: Generated SOAP note response
    """
    client = genai.Client(
        vertexai=True,
        project="eon-health-450706",
        location="us-central1",
    )

    text_part = types.Part.from_text(text=input_text)
    
    system_instruction = """You are a clinical note generator. Your task is to create a factual, data-driven SOAP note based on provided health metrics and user notes. Focus only on presenting the available data without speculation or interpretation. The SOAP note should have four clearly labeled sections:

Subjective (S):
- Include only user-reported symptoms and experiences from their notes
- Present notes chronologically, prioritizing recent notes
- Do not include any personal identifying information
- If no notes are available, state "No subjective data provided"

Objective (O):
- List only the measurable health metrics provided
- Include biological sex if provided in characteristics data
- For each metric, include only the data points that are available
- Clearly indicate when data is missing or incomplete
- Format metrics in clear, readable units (e.g., "Heart Rate: 72 BPM")
- Present sleep data in hours and minutes
- Present step counts as whole numbers
- Present biological sex as "Sex: [value]" at the beginning of the section

Assessment (A):
- Focus on summarizing the objective findings and recent subjective reports
- Do not speculate about possible causes or conditions
- Note any significant changes or patterns only if explicitly shown in the data
- If data is insufficient for assessment, state "Limited data available for assessment"

Plan (P):
- Simply state "Continued monitoring of health metrics"
- Do not make any medical recommendations or suggestions

Important Guidelines:
1. Only include information that is explicitly provided in the input data
2. Use clear, clinical language without speculation
3. Maintain a neutral, factual tone
4. Clearly indicate when data is missing or incomplete
5. Format all numbers consistently and clearly
6. Do not include any personal health advice or recommendations
7. Do not attempt to diagnose or suggest possible conditions

Return the SOAP note in a clear, structured format with each section clearly labeled."""

    model = "gemini-2.0-flash-001"
    contents = [
        types.Content(
            role="user",
            parts=[text_part]
        )
    ]
    
    generate_content_config = types.GenerateContentConfig(
        temperature=0.7,  # Reduced from 1.0 to be more consistent
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

    response = client.models.generate_content(
        model=model,
        contents=contents,
        config=generate_content_config,
    )
    
    return response.text 