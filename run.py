#!/usr/bin/env python3
"""
Main entry point for the Lievik Flask application.
"""

import os
import sys

# Add the project root to the Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lievik.app import create_app

app = create_app()

if __name__ == '__main__':
    # Run the development server
    app.run(
        host=os.getenv('FLASK_HOST', '127.0.0.1'),
        port=int(os.getenv('FLASK_PORT', 5000)),
        debug=os.getenv('FLASK_DEBUG', 'True').lower() == 'true'
    )
