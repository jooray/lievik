from flask import Blueprint, render_template, jsonify, request, redirect, url_for, flash
from lievik.app import db
from lievik.models import User, Channel, ContentItem, ChannelContentAffinity
from flask_login import login_user, logout_user, login_required, current_user

main_bp = Blueprint('main', __name__)

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
        db.session.execute('SELECT 1')
        db_status = 'connected'
    except Exception as e:
        db_status = f'error: {str(e)}'

    return jsonify({
        'status': 'healthy',
        'database': db_status
    })


@main_bp.route('/api/channels')
def get_channels():
    """Get all channels for the current user."""
    # For now, return all channels (authentication will be added later)
    channels = Channel.query.all()

    channel_data = []
    for channel in channels:
        channel_data.append({
            'id': channel.id,
            'name': channel.name,
            'description': channel.description_by_user,
            'language': channel.language,
            'type': channel.channel_type.name if channel.channel_type else None,
            'is_active': channel.is_active,
            'created_at': channel.created_at.isoformat() if channel.created_at else None
        })

    return jsonify({
        'channels': channel_data,
        'count': len(channel_data)
    })


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


@main_bp.route('/api/ingestion/trigger', methods=['POST'])
@login_required
def trigger_content_ingestion():
    """Manually trigger content ingestion for all sources or specific sources."""
    try:
        data = request.get_json() or {}
        source_ids = data.get('source_ids', [])

        from lievik.core.content_ingestion import ContentIngestionService
        from lievik.models import Source

        service = ContentIngestionService()
        results = []

        if source_ids:
            # Ingest from specific sources
            for source_id in source_ids:
                source = Source.query.get(source_id)
                if source and source.is_active:
                    try:
                        result = service.ingest_from_source(source)
                        results.append({
                            'source_id': source_id,
                            'source_name': source.name,
                            'status': 'success',
                            'items_processed': result.get('items_processed', 0)
                        })
                    except Exception as e:
                        results.append({
                            'source_id': source_id,
                            'source_name': source.name,
                            'status': 'error',
                            'error': str(e)
                        })
                else:
                    results.append({
                        'source_id': source_id,
                        'status': 'error',
                        'error': 'Source not found or inactive'
                    })
        else:
            # Ingest from all active sources
            sources = Source.query.filter_by(is_active=True).all()
            for source in sources:
                try:
                    result = service.ingest_from_source(source)
                    results.append({
                        'source_id': source.id,
                        'source_name': source.name,
                        'status': 'success',
                        'items_processed': result.get('items_processed', 0)
                    })
                except Exception as e:
                    results.append({
                        'source_id': source.id,
                        'source_name': source.name,
                        'status': 'error',
                        'error': str(e)
                    })

        return jsonify({
            'message': 'Content ingestion triggered',
            'results': results,
            'total_sources': len(results)
        })

    except Exception as e:
        return jsonify({
            'error': f'Failed to trigger content ingestion: {str(e)}'
        }), 500


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


@main_bp.route('/api/sources')
@login_required
def get_sources():
    """Get all content sources."""
    try:
        from lievik.models import Source
        sources = Source.query.all()

        sources_data = []
        for source in sources:
            sources_data.append({
                'id': source.id,
                'name': source.name,
                'source_type': source.source_type,
                'url': source.url,
                'is_active': source.is_active,
                'created_at': source.created_at.isoformat() if source.created_at else None,
                'last_ingestion': source.last_ingestion.isoformat() if source.last_ingestion else None
            })

        return jsonify({
            'sources': sources_data,
            'count': len(sources_data)
        })

    except Exception as e:
        return jsonify({
            'error': f'Failed to get sources: {str(e)}'
        }), 500


@main_bp.route('/api/crew/process', methods=['POST'])
@login_required
def trigger_crew_processing():
    """Manually trigger CrewAI processing for content items."""
    try:
        data = request.get_json() or {}
        content_item_ids = data.get('content_item_ids', [])
        channel_ids = data.get('channel_ids', [])

        from lievik.core.content_ingestion import ContentIngestionService

        service = ContentIngestionService()
        results = service.process_existing_content_with_crew(
            content_item_ids=content_item_ids if content_item_ids else None,
            channel_ids=channel_ids if channel_ids else None
        )

        return jsonify({
            'message': 'CrewAI processing triggered',
            'results': results
        })

    except Exception as e:
        return jsonify({
            'error': f'Failed to trigger CrewAI processing: {str(e)}'
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
