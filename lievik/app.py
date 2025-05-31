import os
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from dotenv import load_dotenv
from flask_login import LoginManager # Add this import

# Load environment variables
load_dotenv()

# Initialize extensions
db = SQLAlchemy()
migrate = Migrate()
login_manager = LoginManager() # Initialize LoginManager
login_manager.login_view = 'main.login' # Specify the login view


def create_app(config_name=None):
    """Application factory pattern."""
    app = Flask(__name__)

    # Configuration
    if config_name is None:
        config_name = os.getenv('FLASK_ENV', 'development')

    app.config.from_object(f'lievik.config.{config_name.title()}Config')

    # Initialize extensions with app
    db.init_app(app)
    migrate.init_app(app, db)
    login_manager.init_app(app) # Initialize LoginManager with app

    # Register blueprints
    from lievik.routes import main_bp
    app.register_blueprint(main_bp)

    return app

@login_manager.user_loader
def load_user(user_id):
    from lievik.models import User # Import User model here to avoid circular dependency
    return User.query.get(int(user_id))
