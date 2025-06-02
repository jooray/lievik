from flask import Blueprint, render_template, jsonify, request, redirect, url_for, flash, current_app # Import current_app
from lievik.app import db
from lievik.models import User, Channel, ContentItem, ChannelContentAffinity, ChannelType, CrewConfiguration
from flask_login import login_user, logout_user, login_required, current_user

main_bp = Blueprint('main', __name__)

def _serialize_channel(channel):
    return {
        'id': channel.id,
        'name': channel.name,
        'user_id': channel.user_id,
        'description_by_user': channel.description_by_user,
        'target_persona': channel.target_persona,
        'language': channel.language,
        'channel_type_id': channel.channel_type_id,
        'channel_type': channel.channel_type.name if channel.channel_type else None,
        'crew_configuration_id': channel.crew_configuration_id,
        'crew_configuration_name': channel.crew_configuration.name if channel.crew_configuration else None,
        'icon_url': channel.icon_url,
        'is_active': channel.is_active,
        'created_at': channel.created_at.isoformat() if channel.created_at else None
    }

def _serialize_channel_type(channel_type):
    return {
        'id': channel_type.id,
        'name': channel_type.name,
        'description': channel_type.description,
        'default_crew_configuration_id': channel_type.default_crew_configuration_id,
        'default_crew_configuration_name': channel_type.default_crew_configuration.name if channel_type.default_crew_configuration else None,
        # Consider adding a count of channels using this type, if useful, though it might require an extra query.
        # 'channel_count': len(channel_type.channels) # Example, might be performance intensive
    }

@main_bp.route('/')
def index():
    """Home page with dashboard overview."""
    if current_user.is_authenticated:
        return render_template('dashboard.html')
    else:
        return redirect(url_for('main.login'))


@main_bp.route('/health')
def health_check():
    """Health check endpoint."""
    try:
        # Test database connection
        from sqlalchemy import text
        db.session.execute(text('SELECT 1'))
        db_status = 'connected'
    except Exception as e:
        db_status = f'error: {str(e)}'

    return jsonify({
        'status': 'healthy',
        'database': db_status
    })


@main_bp.route('/api/channels', methods=['GET'])
@login_required
def get_channels():
    """Get all channels for the current user."""
    channels = Channel.query.filter_by(user_id=current_user.id).all()
    channel_data = [_serialize_channel(c) for c in channels]
    return jsonify({'channels': channel_data, 'count': len(channel_data)})


@main_bp.route('/api/channels', methods=['POST'])
@login_required
def create_channel():
    """Create a new channel for the current user."""
    data = request.json
    if not data:
        return jsonify({'error': 'No input data provided'}), 400

    required_fields = ['name', 'language', 'channel_type_id']
    missing_fields = [field for field in required_fields if field not in data]
    if missing_fields:
        return jsonify({'error': f'Missing required fields: {", ".join(missing_fields)}'}), 400

    channel_type = ChannelType.query.get(data.get('channel_type_id'))
    if not channel_type:
        return jsonify({'error': 'ChannelType not found'}), 404

    crew_id = data.get('crew_configuration_id')
    if not crew_id:
        crew_id = channel_type.default_crew_configuration_id

    if not crew_id:
        return jsonify({'error': 'Crew configuration ID is required and no default is set for the channel type'}), 400

    if not CrewConfiguration.query.get(crew_id):
        return jsonify({'error': 'Selected CrewConfiguration not found'}), 404

    new_channel = Channel(
        name=data['name'],
        language=data['language'],
        channel_type_id=data['channel_type_id'],
        user_id=current_user.id,
        crew_configuration_id=crew_id,
        description_by_user=data.get('description_by_user'),
        target_persona=data.get('target_persona'),
        icon_url=data.get('icon_url'),
        is_active=data.get('is_active', True)
    )
    db.session.add(new_channel)
    db.session.commit()
    return jsonify(_serialize_channel(new_channel)), 201


@main_bp.route('/api/channels/<int:channel_id>', methods=['GET'])
@login_required
def get_channel(channel_id):
    """Get a specific channel by ID."""
    channel = Channel.query.filter_by(id=channel_id, user_id=current_user.id).first_or_404()
    return jsonify(_serialize_channel(channel))


@main_bp.route('/api/channels/<int:channel_id>', methods=['PUT'])
@login_required
def update_channel(channel_id):
    """Update a specific channel by ID."""
    channel = Channel.query.filter_by(id=channel_id, user_id=current_user.id).first_or_404()
    data = request.json
    if not data:
        return jsonify({'error': 'No input data provided'}), 400

    channel.name = data.get('name', channel.name)
    channel.language = data.get('language', channel.language)
    channel.description_by_user = data.get('description_by_user', channel.description_by_user)
    channel.target_persona = data.get('target_persona', channel.target_persona)
    channel.icon_url = data.get('icon_url', channel.icon_url)

    if 'is_active' in data and isinstance(data['is_active'], bool):
        channel.is_active = data['is_active']

    if data.get('channel_type_id'):
        new_channel_type_id = data.get('channel_type_id')
        if not ChannelType.query.get(new_channel_type_id):
            return jsonify({'error': 'New ChannelType not found'}), 404
        channel.channel_type_id = new_channel_type_id

    if data.get('crew_configuration_id'):
        new_crew_config_id = data.get('crew_configuration_id')
        if not CrewConfiguration.query.get(new_crew_config_id):
            return jsonify({'error': 'New CrewConfiguration not found'}), 404
        channel.crew_configuration_id = new_crew_config_id

    db.session.commit()
    return jsonify(_serialize_channel(channel))


@main_bp.route('/api/channels/<int:channel_id>', methods=['DELETE'])
@login_required
def delete_channel(channel_id):
    """Delete a specific channel by ID."""
    channel = Channel.query.filter_by(id=channel_id, user_id=current_user.id).first_or_404()
    db.session.delete(channel)
    db.session.commit()
    return jsonify({'message': 'Channel deleted successfully'}), 200


# ChannelType CRUD operations
@main_bp.route('/api/channel-types', methods=['GET'])
@login_required
def get_channel_types():
    """Get all channel types."""
    channel_types = ChannelType.query.all()
    types_data = [_serialize_channel_type(ct) for ct in channel_types]
    return jsonify({'channel_types': types_data, 'count': len(types_data)})


@main_bp.route('/api/channel-types', methods=['POST'])
@login_required
def create_channel_type():
    """Create a new channel type."""
    data = request.json
    if not data:
        return jsonify({'error': 'No input data provided'}), 400

    if 'name' not in data:
        return jsonify({'error': 'Missing required field: name'}), 400

    if ChannelType.query.filter_by(name=data['name']).first():
        return jsonify({'error': 'ChannelType name already exists'}), 409

    crew_config_id = data.get('default_crew_configuration_id')
    if crew_config_id and not CrewConfiguration.query.get(crew_config_id):
        return jsonify({'error': 'Default CrewConfiguration not found'}), 404

    new_channel_type = ChannelType(
        name=data['name'],
        description=data.get('description'),
        default_crew_configuration_id=crew_config_id
    )
    db.session.add(new_channel_type)
    db.session.commit()
    return jsonify(_serialize_channel_type(new_channel_type)), 201


@main_bp.route('/api/channel-types/<int:channel_type_id>', methods=['GET'])
@login_required
def get_channel_type(channel_type_id):
    """Get a specific channel type by ID."""
    channel_type = ChannelType.query.get_or_404(channel_type_id)
    return jsonify(_serialize_channel_type(channel_type))


@main_bp.route('/api/channel-types/<int:channel_type_id>', methods=['PUT'])
@login_required
def update_channel_type(channel_type_id):
    """Update a specific channel type by ID."""
    channel_type = ChannelType.query.get_or_404(channel_type_id)
    data = request.json
    if not data:
        return jsonify({'error': 'No input data provided'}), 400

    new_name = data.get('name', channel_type.name)
    if new_name != channel_type.name and ChannelType.query.filter_by(name=new_name).first():
        return jsonify({'error': 'New ChannelType name already exists'}), 409
    channel_type.name = new_name

    channel_type.description = data.get('description', channel_type.description)

    if 'default_crew_configuration_id' in data:
        new_crew_config_id = data.get('default_crew_configuration_id')
        if new_crew_config_id is not None and not CrewConfiguration.query.get(new_crew_config_id):
            return jsonify({'error': 'New default CrewConfiguration not found'}), 404
        channel_type.default_crew_configuration_id = new_crew_config_id

    db.session.commit()
    return jsonify(_serialize_channel_type(channel_type))


@main_bp.route('/api/channel-types/<int:channel_type_id>', methods=['DELETE'])
@login_required
def delete_channel_type(channel_type_id):
    """Delete a specific channel type by ID."""
    channel_type = ChannelType.query.get_or_404(channel_type_id)

    if Channel.query.filter_by(channel_type_id=channel_type_id).first():
        return jsonify({'error': 'Cannot delete ChannelType: It is currently in use by one or more Channels'}), 409

    db.session.delete(channel_type)
    db.session.commit()
    return jsonify({'message': 'ChannelType deleted successfully'}), 200


@main_bp.route('/api/content-items')
def get_content_items():
    """Get recent content items."""
    content_items = ContentItem.query.order_by(ContentItem.created_at.desc()).limit(20).all()

    items_data = []
    for item in content_items:
        items_data.append({
            'id': item.id,
            'raw_content': item.raw_content[:200] + '...' if item.raw_content and len(item.raw_content) > 200 else item.raw_content,
            'link_url': item.link_url,
            'language_detected': item.language_detected,
            'publication_date': item.publication_date.isoformat() if item.publication_date else None,
            'created_at': item.created_at.isoformat() if item.created_at else None
        })

    return jsonify({
        'content_items': items_data,
        'count': len(items_data)
    })


@main_bp.route('/api/stats')
def get_stats():
    """Get system statistics."""
    try:
        user_count = User.query.count()
        channel_count = Channel.query.count()
        content_item_count = ContentItem.query.count()
        active_channels = Channel.query.filter_by(is_active=True).count()

        return jsonify({
            'users': user_count,
            'channels': channel_count,
            'active_channels': active_channels,
            'content_items': content_item_count
        })
    except Exception as e:
        return jsonify({
            'error': f'Could not fetch stats: {str(e)}'
        }), 500


@main_bp.route('/register', methods=['GET', 'POST'])
def register():
    if current_user.is_authenticated:
        return redirect(url_for('main.index'))
    if request.method == 'POST':
        username = request.form.get('username')
        email = request.form.get('email')
        password = request.form.get('password')

        if User.query.filter_by(username=username).first():
            flash('Username already exists', 'error')
            return redirect(url_for('main.register'))
        if User.query.filter_by(email=email).first():
            flash('Email already registered', 'error')
            return redirect(url_for('main.register'))

        new_user = User(username=username, email=email)
        new_user.set_password(password)
        db.session.add(new_user)
        db.session.commit()
        flash('Registration successful. Please log in.', 'success')
        return redirect(url_for('main.login'))
    return render_template('register.html')  # We'll create this template later


@main_bp.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('main.index'))
    if request.method == 'POST':
        email = request.form.get('email')
        password = request.form.get('password')
        user = User.query.filter_by(email=email).first()
        if user and user.check_password(password):
            login_user(user)
            return redirect(url_for('main.index'))
        else:
            flash('Invalid email or password', 'error')
    return render_template('login.html')  # We'll create this template later


@main_bp.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('main.index'))





@main_bp.route('/api/ingestion/status')
@login_required
def get_ingestion_status():
    """Get status of content ingestion jobs."""
    try:
        from lievik.app import scheduler

        if scheduler is None:
            return jsonify({'error': 'Scheduler not initialized'}), 500

        # Get information about the content ingestion job
        job = scheduler.get_job('content_ingestion')

        if job is None:
            return jsonify({'error': 'Content ingestion job not found'}), 404

        return jsonify({
            'job_id': job.id,
            'job_name': job.name,
            'next_run_time': job.next_run_time.isoformat() if job.next_run_time else None,
            'trigger': str(job.trigger),
            'pending': job.pending,
            'max_instances': job.max_instances
        })

    except Exception as e:
        return jsonify({
            'error': f'Failed to get ingestion status: {str(e)}'
        }), 500


@main_bp.route('/api/crew/status')
@login_required
def get_crew_status():
    """Get status information about CrewAI processing."""
    try:
        from lievik.models import ContentItem, Channel
        from datetime import datetime, timedelta

        # Get recent content items counts
        now = datetime.utcnow()
        last_24h = now - timedelta(hours=24)
        last_week = now - timedelta(days=7)

        recent_items = ContentItem.query.filter(ContentItem.created_at >= last_24h).count()
        weekly_items = ContentItem.query.filter(ContentItem.created_at >= last_week).count()
        total_items = ContentItem.query.count()

        active_channels = Channel.query.filter_by(is_active=True).count()
        total_channels = Channel.query.count()

        return jsonify({
            'content_items': {
                'last_24h': recent_items,
                'last_week': weekly_items,
                'total': total_items
            },
            'channels': {
                'active': active_channels,
                'total': total_channels
            },
            'crew_ai': {
                'global_preprocessing_enabled': True,
                'channel_evaluation_enabled': True,
                'processing_mode': 'automatic'
            }
        })

    except Exception as e:
        return jsonify({
            'error': f'Failed to get CrewAI status: {str(e)}'
        }), 500


@main_bp.route('/api/status')
def api_status():
    """API status endpoint."""
    return jsonify({
        'message': 'Lievik Marketing Content Orchestrator',
        'version': '0.1.0',
        'status': 'running',
        'login_url': url_for('main.login'),
        'register_url': url_for('main.register')
    })


@main_bp.route('/api/content/ingest', methods=['POST'])
@login_required
def trigger_content_ingestion():
    """Manually trigger content ingestion for all sources."""
    try:
        from lievik.core.content_ingestion import content_ingestion_service

        # Run content ingestion for current user
        results = content_ingestion_service.ingest_all_sources(user_id=current_user.id)

        return jsonify({
            'status': 'success',
            'message': 'Content ingestion completed',
            'results': results
        })

    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'Content ingestion failed: {str(e)}'
        }), 500


@main_bp.route('/api/content/ingest/source/<int:source_id>', methods=['POST'])
@login_required
def trigger_source_ingestion(source_id):
    """Manually trigger content ingestion for a specific source."""
    try:
        from lievik.core.content_ingestion import content_ingestion_service
        from lievik.models import Source

        # Get the source and verify ownership
        source = Source.query.filter_by(id=source_id, user_id=current_user.id).first()
        if not source:
            return jsonify({
                'status': 'error',
                'message': 'Source not found or access denied'
            }), 404

        # Run content ingestion for this specific source
        results = content_ingestion_service.ingest_from_source(source)

        return jsonify({
            'status': 'success',
            'message': f'Content ingestion completed for source: {source.name}',
            'results': results
        })

    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'Source ingestion failed: {str(e)}'
        }), 500


@main_bp.route('/api/content/process', methods=['POST'])
@login_required
def trigger_content_crew_processing():
    """Manually trigger CrewAI processing for existing content items."""
    try:
        from lievik.core.content_ingestion import content_ingestion_service

        data = request.get_json() or {}
        content_item_ids = data.get('content_item_ids')  # Optional: specific items
        channel_ids = data.get('channel_ids')  # Optional: specific channels

        # Run CrewAI processing
        results = content_ingestion_service.process_existing_content_with_crew(
            content_item_ids=content_item_ids,
            channel_ids=channel_ids
        )

        return jsonify({
            'status': 'success',
            'message': 'CrewAI processing completed',
            'results': results
        })

    except Exception as e:
        return jsonify({
            'status': 'error',
            'message': f'CrewAI processing failed: {str(e)}'
        }), 500


@main_bp.route('/api/scheduler/control', methods=['POST'])
@login_required
def control_scheduler():
    """Control the content ingestion scheduler (start/stop/restart)."""
    try:
        from lievik.app import scheduler

        data = request.get_json() or {}
        action = data.get('action', '').lower()

        if scheduler is None:
            return jsonify({'error': 'Scheduler not initialized'}), 500

        if action == 'start':
            if scheduler.running:
                return jsonify({'message': 'Scheduler is already running', 'status': 'running'})
            scheduler.start()
            return jsonify({'message': 'Scheduler started successfully', 'status': 'running'})

        elif action == 'stop':
            if not scheduler.running:
                return jsonify({'message': 'Scheduler is already stopped', 'status': 'stopped'})
            scheduler.shutdown(wait=False)
            return jsonify({'message': 'Scheduler stopped successfully', 'status': 'stopped'})

        elif action == 'restart':
            if scheduler.running:
                scheduler.shutdown(wait=False)
            # Reinitialize scheduler
            from lievik.app import init_scheduler
            from flask import current_app
            init_scheduler(current_app)
            return jsonify({'message': 'Scheduler restarted successfully', 'status': 'running'})

        elif action == 'pause_job':
            job_id = data.get('job_id', 'content_ingestion')
            scheduler.pause_job(job_id)
            return jsonify({'message': f'Job {job_id} paused successfully', 'status': 'paused'})

        elif action == 'resume_job':
            job_id = data.get('job_id', 'content_ingestion')
            scheduler.resume_job(job_id)
            return jsonify({'message': f'Job {job_id} resumed successfully', 'status': 'running'})

        else:
            return jsonify({'error': f'Unknown action: {action}. Valid actions: start, stop, restart, pause_job, resume_job'}), 400

    except Exception as e:
        return jsonify({'error': f'Scheduler control failed: {str(e)}'}), 500


@main_bp.route('/api/scheduler/status')
@login_required
def get_detailed_scheduler_status():
    """Get detailed status of the content ingestion scheduler."""
    try:
        from lievik.app import scheduler
        from flask import current_app

        if scheduler is None:
            return jsonify({'error': 'Scheduler not initialized'}), 500

        # Get scheduler status
        status_data = {
            'scheduler_running': scheduler.running,
            'scheduler_state': scheduler.state,
            'timezone': str(scheduler.timezone)
        }

        # Get job information
        jobs = []
        for job in scheduler.get_jobs():
            job_data = {
                'id': job.id,
                'name': job.name,
                'next_run_time': job.next_run_time.isoformat() if job.next_run_time else None,
                'trigger': str(job.trigger),
                'pending': job.pending,
                'max_instances': job.max_instances,
                'coalesce': job.coalesce,
                'misfire_grace_time': job.misfire_grace_time
            }
            jobs.append(job_data)

        status_data['jobs'] = jobs

        # Get last ingestion results if available
        last_time = current_app.config.get('LAST_INGESTION_TIME')
        last_results = current_app.config.get('LAST_INGESTION_RESULTS')
        last_error = current_app.config.get('LAST_INGESTION_ERROR')

        if last_time:
            status_data['last_ingestion'] = {
                'time': last_time.isoformat(),
                'results': last_results,
                'error': last_error
            }

        # Get configuration
        status_data['configuration'] = {
            'schedule_type': current_app.config.get('INGESTION_SCHEDULE_TYPE'),
            'interval_hours': current_app.config.get('INGESTION_INTERVAL_HOURS'),
            'cron_schedule': current_app.config.get('INGESTION_CRON_SCHEDULE'),
            'max_instances': current_app.config.get('INGESTION_MAX_INSTANCES'),
            'coalesce': current_app.config.get('INGESTION_COALESCE'),
            'misfire_grace_time': current_app.config.get('INGESTION_MISFIRE_GRACE_TIME'),
            'process_content_immediately': current_app.config.get('PROCESS_CONTENT_IMMEDIATELY')
        }

        return jsonify(status_data)

    except Exception as e:
        return jsonify({'error': f'Failed to get scheduler status: {str(e)}'}), 500


@main_bp.route('/api/content/pipeline/trigger', methods=['POST'])
@login_required
def trigger_full_content_pipeline():
    """
    Manually trigger the complete content ingestion pipeline as specified in Task 2.4.
    This triggers the background job immediately and returns without waiting for completion.
    """
    try:
        from lievik.app import scheduler
        from datetime import datetime # Import datetime

        if scheduler is None:
            return jsonify({
                'status': 'error',
                'message': 'Scheduler not initialized'
            }), 500

        data = request.get_json() or {}
        # user_only = data.get('user_only', True) # This parameter is not used by the scheduled job directly

        job = scheduler.get_job('content_ingestion')

        if job is None:
            return jsonify({
                'status': 'error',
                'message': 'Content ingestion job not found in scheduler'
            }), 404

        # Check if job is already running (APScheduler's pending attribute might not be reliable for this)
        # It's better to rely on max_instances=1 and let the scheduler handle it.
        # If you need more sophisticated check, it would require external state tracking.

        # Trigger the job to run immediately by setting its next_run_time to now
        now_in_scheduler_tz = datetime.now(scheduler.timezone)
        scheduler.modify_job('content_ingestion', next_run_time=now_in_scheduler_tz)
        current_app.logger.info(f"Manual trigger: Modified 'content_ingestion' job to run at {now_in_scheduler_tz}")

        return jsonify({
            'status': 'success',
            'message': 'Content ingestion pipeline triggered to run now via scheduler.',
            'job_status': 'triggered',
            'next_run_time_set_to': now_in_scheduler_tz.isoformat()
        })

    except Exception as e:
        current_app.logger.error(f"Failed to trigger content pipeline: {e}", exc_info=True)
        return jsonify({
            'status': 'error',
            'message': f'Failed to trigger source refresh: {str(e)}'
        }), 500
