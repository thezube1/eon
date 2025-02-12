from flask import Flask, jsonify
from flask_cors import CORS
import os
from routes.health import health_bp
from routes.risk_analysis import risk_analysis_bp

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
