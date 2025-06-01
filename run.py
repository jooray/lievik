#!/usr/bin/env python3
"""
Main entry point for the Lievik Flask application.
"""

import os
import sys
import logging

# Add the project root to the Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# Configure root logger to show INFO level messages
logging.basicConfig(level=logging.INFO)

from lievik.app import create_app

app = create_app()
# Ensure Flask app's logger level is also set if it uses its own handler
app.logger.setLevel(logging.INFO)

if __name__ == '__main__':
    # Run the development server
    app.run(
        host=os.getenv('FLASK_HOST', '127.0.0.1'),
        port=int(os.getenv('FLASK_PORT', 5000)),
        debug=os.getenv('FLASK_DEBUG', 'True').lower() == 'true'
    )
