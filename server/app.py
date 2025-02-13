from flask import Flask, jsonify
from flask_cors import CORS
import os
from routes.health import health_bp
from routes.risk_analysis import risk_analysis_bp, load_model
import threading
import logging

# Configure logging to only show Flask logs
logging.getLogger('werkzeug').setLevel(logging.INFO)
logging.getLogger('httpcore').setLevel(logging.WARNING)
logging.getLogger('httpx').setLevel(logging.WARNING)
logging.getLogger('h2').setLevel(logging.WARNING)
logging.getLogger('urllib3').setLevel(logging.WARNING)
logging.getLogger('supabase').setLevel(logging.WARNING)
logging.getLogger('transformers').setLevel(logging.WARNING)

# Load environment variables before creating app
from dotenv import load_dotenv
load_dotenv()

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes

# Configure Flask app
debug_mode = os.environ.get('FLASK_ENV') == 'development'
app.config.update(
    DEBUG=debug_mode,
    TEMPLATES_AUTO_RELOAD=True,
    TIMEOUT=300,  # 5 minutes timeout
    MAX_CONTENT_LENGTH=16 * 1024 * 1024  # 16MB max-limit
)

# Load ML model in a background thread during startup
def load_model_on_startup():
    with app.app_context():
        try:
            load_model()
        except Exception as e:
            app.logger.error(f"Failed to load model on startup: {e}")
            # Don't raise the exception - let the server start anyway
            # The risk analysis endpoint will return appropriate errors

# Start model loading in background thread
model_thread = threading.Thread(target=load_model_on_startup)
model_thread.start()

# Register blueprints
app.register_blueprint(health_bp, url_prefix='/api/health')
app.register_blueprint(risk_analysis_bp, url_prefix='/api')

# Basic error handling
@app.errorhandler(404)
def not_found(error):
    return jsonify({"error": "Resource not found"}), 404

@app.errorhandler(500)
def internal_error(error):
    return jsonify({"error": "Internal server error"}), 500

# Health check endpoint
@app.route('/health', methods=['GET'])
def health_check():
    return jsonify({"status": "healthy"}), 200

# Root endpoint
@app.route('/', methods=['GET'])
def root():
    return jsonify({"message": "Welcome to the Flask server"}), 200

if __name__ == '__main__':
    port = int(os.environ.get('PORT', 8000))
    app.run(host='0.0.0.0', port=port, debug=True)
