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
        return jsonify({
            'message': 'Lievik Marketing Content Orchestrator',
            'version': '0.1.0',
            'status': 'running',
            'login_url': url_for('main.login'),
            'register_url': url_for('main.register')
        })


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
