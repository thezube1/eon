from google import genai
from google.genai import types

def generate_soap_note(input_text: str) -> str:
    """
    Generate a SOAP note using Gemini model based on input text.
    
    Args:
        input_text (str): The input text containing patient data
        
    Returns:
        str: Generated SOAP note response
    """
    client = genai.Client(
        vertexai=True,
        project="eon-health-450706",
        location="us-central1",
    )

    text_part = types.Part.from_text(text=input_text)
    
    system_instruction = """You are a clinical note generator. Your task is to create a SOAP note based on provided patient data that reflects both lifestyle metrics and subjective feedback. The SOAP note should have four clearly labeled sections:
Subjective (S):
Summarize the patient's chief complaint and self-reported symptoms (e.g., feelings of fatigue, dizziness, or stress).
Include relevant details from the patient history (e.g., recent changes in energy, sleep disturbances, or decreased activity levels).
Objective (O):
List measurable data such as vital signs and lifestyle metrics.
Include information like average resting heart rate, daily step count, sleep duration, and quality.
Note any observable changes compared to the patient's typical baseline.
Assessment (A):
Based on the subjective and objective information, provide an evaluation of potential underlying issues or risks (for example, possible cardiovascular strain or metabolic concerns).
Discuss how these findings might correlate with known risk factors.
Ensure the note is written in a clear, concise, and clinically appropriate tone. Format your output with distinct headings for each section."""

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

    response_text = ""
    for chunk in client.models.generate_content_stream(
        model=model,
        contents=contents,
        config=generate_content_config,
    ):
        response_text += chunk.text
        
    return response_text 