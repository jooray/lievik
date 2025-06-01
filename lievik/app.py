import os
from flask import Flask, current_app
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from dotenv import load_dotenv
from flask_login import LoginManager
from apscheduler.schedulers.background import BackgroundScheduler
from apscheduler.triggers.interval import IntervalTrigger
from apscheduler.triggers.cron import CronTrigger
import atexit
import logging
import yaml # Added for YAML loading

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

    # Seed initial data (like global crew config)
    with app.app_context():
        seed_initial_data(app)

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

def seed_initial_data(app):
    """
    Seed initial data for crew configurations.
    This should only run when the application first starts and tables exist.
    """
    with app.app_context():
        from lievik.models import CrewConfiguration # Import here to avoid circular dependency
        from sqlalchemy import inspect

        # Check if tables exist
        inspector = inspect(db.engine)
        if 'crew_configurations' not in inspector.get_table_names():
            app.logger.info("Database tables not yet created. Skipping initial data seeding.")
            return

        # Global Content Preprocessing Crew
        global_crew_name = "Global Content Preprocessing Crew"
        existing_global_crew = CrewConfiguration.query.filter_by(name=global_crew_name, is_global=True).first()

        if not existing_global_crew:
            # Load configuration from YAML file
            yaml_file_path = os.path.join(os.path.dirname(__file__), 'core', 'seed_data', 'global_crew_config.yaml')

            try:
                with open(yaml_file_path, 'r') as f:
                    # Load the entire file content as the config_yaml
                    config_yaml_content = f.read()

                global_crew_config = CrewConfiguration(
                    name=global_crew_name,
                    is_global=True,
                    config_yaml=config_yaml_content
                )
                db.session.add(global_crew_config)
                db.session.commit()
                app.logger.info(f"Created initial {global_crew_name} configuration from {yaml_file_path}")
            except FileNotFoundError:
                app.logger.error(f"Global crew configuration file not found at: {yaml_file_path}")
            except Exception as e:
                app.logger.error(f"Error loading global crew configuration: {e}")
        else:
            app.logger.info(f"{global_crew_name} configuration already exists")

def init_scheduler(app):
    """Initialize APScheduler for background content ingestion."""
    global scheduler

    if scheduler is not None:
        return  # Already initialized

    # Initialize scheduler with job defaults
    scheduler = BackgroundScheduler(
        timezone=app.config.get('SCHEDULER_TIMEZONE', 'UTC'),
        job_defaults=app.config.get('SCHEDULER_JOB_DEFAULTS', {})
    )

    # Add content ingestion job
    from lievik.core.content_ingestion import run_content_ingestion

    def run_scheduled_content_ingestion():
        """Enhanced wrapper function for scheduled content ingestion that runs in app context."""
        with app.app_context():
            try:
                current_app.logger.info("APScheduler: Starting scheduled content ingestion pipeline via run_scheduled_content_ingestion")

                # Run the complete pipeline as specified in Task 2.4:
                # 1. Fetch new Nostr events
                # 2. For each event, parse links (if any)
                # 3. Execute the Global Content Preprocessing Crew
                # 4. Store ContentItems and ProcessedWebContent
                results = run_content_ingestion() # This calls the function in content_ingestion.py

                current_app.logger.info(f"APScheduler: Scheduled content ingestion completed successfully: {results}")

                # Store ingestion metrics for monitoring
                from datetime import datetime
                app.config['LAST_INGESTION_TIME'] = datetime.utcnow()
                app.config['LAST_INGESTION_RESULTS'] = results

            except Exception as e:
                current_app.logger.error(f"APScheduler: Scheduled content ingestion failed: {e}", exc_info=True)
                app.config['LAST_INGESTION_ERROR'] = str(e)
                # Don't re-raise to prevent scheduler from stopping

    # Configure ingestion schedule based on configuration
    schedule_type = app.config.get('INGESTION_SCHEDULE_TYPE', 'interval')

    if schedule_type == 'cron':
        # Use cron-style scheduling
        from apscheduler.triggers.cron import CronTrigger
        cron_schedule = app.config.get('INGESTION_CRON_SCHEDULE', '0 */1 * * *')
        trigger = CronTrigger.from_crontab(cron_schedule)
        app.logger.info(f"Using cron schedule: {cron_schedule}")
    else:
        # Use interval-based scheduling (default)
        interval_hours = app.config.get('INGESTION_INTERVAL_HOURS', 1)
        trigger = IntervalTrigger(hours=interval_hours)
        app.logger.info(f"Using interval schedule: {interval_hours} hours")

    scheduler.add_job(
        func=run_scheduled_content_ingestion,
        trigger=trigger,
        id='content_ingestion',
        name='Content Ingestion Pipeline Job',
        replace_existing=True,
        max_instances=app.config.get('INGESTION_MAX_INSTANCES', 1),
        coalesce=app.config.get('INGESTION_COALESCE', True),
        misfire_grace_time=app.config.get('INGESTION_MISFIRE_GRACE_TIME', 300)
    )

    # Start the scheduler
    scheduler.start()
    app.logger.info("APScheduler started with enhanced content ingestion pipeline")

    # Shut down the scheduler when exiting the app
    atexit.register(lambda: scheduler.shutdown())
