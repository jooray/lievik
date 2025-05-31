import os
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from dotenv import load_dotenv
from flask_login import LoginManager
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.cron import CronTrigger
import atexit
import logging

# Load environment variables
load_dotenv()

# Initialize extensions
db = SQLAlchemy()
migrate = Migrate()
login_manager = LoginManager()
login_manager.login_view = 'main.login'
scheduler = None


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
    login_manager.init_app(app)

    # Initialize scheduler
    init_scheduler(app)

    # Register blueprints
    from lievik.routes import main_bp
    app.register_blueprint(main_bp)

    return app

@login_manager.user_loader
def load_user(user_id):
    from lievik.models import User # Import User model here to avoid circular dependency
    return User.query.get(int(user_id))

def init_scheduler(app):
    """Initialize APScheduler for background content ingestion."""
    global scheduler

    if scheduler is not None:
        return  # Already initialized

    scheduler = BackgroundScheduler(timezone=app.config.get('SCHEDULER_TIMEZONE', 'UTC'))

    # Add content ingestion job
    from lievik.core.content_ingestion import ContentIngestionService

    def run_content_ingestion():
        """Wrapper function for content ingestion that runs in app context."""
        with app.app_context():
            try:
                service = ContentIngestionService()
                # Get all active sources and run ingestion
                from lievik.models import Source
                sources = Source.query.filter_by(is_active=True).all()
                for source in sources:
                    service.ingest_from_source(source)
                app.logger.info("Scheduled content ingestion completed successfully")
            except Exception as e:
                app.logger.error(f"Scheduled content ingestion failed: {e}")

    # Schedule content ingestion based on config
    interval_hours = app.config.get('INGESTION_INTERVAL_HOURS', 1)
    scheduler.add_job(
        func=run_content_ingestion,
        trigger=IntervalTrigger(hours=interval_hours),
        id='content_ingestion',
        name='Content Ingestion Job',
        replace_existing=True,
        max_instances=1  # Prevent overlapping jobs
    )

    # Start the scheduler
    scheduler.start()
    app.logger.info(f"APScheduler started with content ingestion interval: {interval_hours} hours")

    # Shut down the scheduler when exiting the app
    atexit.register(lambda: scheduler.shutdown())
