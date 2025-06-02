import unittest
import tempfile
import os
from lievik.app import create_app, db
from lievik.models import User, Channel, ChannelType, CrewConfiguration # Add other models as needed for tests
from werkzeug.security import generate_password_hash

class BaseTestCase(unittest.TestCase):
    def setUp(self):
        self.db_fd, self.db_path = tempfile.mkstemp()

        # Determine the project root dynamically
        # Assuming this script is in lievik/tests/base.py
        project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

        app_config = {
            'TESTING': True,
            'SQLALCHEMY_DATABASE_URI': 'sqlite:///' + self.db_path,
            'WTF_CSRF_ENABLED': False,  # Disable CSRF for testing forms if any
            'LOGIN_DISABLED': False, # Ensure login is enabled for auth tests
            'SERVER_NAME': 'localhost.localdomain', # Required for url_for to work in tests without a request context
            # Add path to seed data if init_db logic needs it and is called in tests
            'SEED_DATA_PATH': os.path.join(project_root, 'lievik', 'core', 'seed_data')
        }
        self.app = create_app(config_override=app_config)

        self.app_context = self.app.app_context()
        self.app_context.push()
        self.client = self.app.test_client()

        db.create_all()

        # Optionally, create a default user for testing authenticated routes
        self.create_test_user()
        # Optionally, run init_db logic if it's idempotent and useful for all tests
        # from scripts.init_db import init_database
        # init_database() # Be careful if this has side effects or requires specific env vars

    def tearDown(self):
        db.session.remove()
        db.drop_all()
        self.app_context.pop()
        os.close(self.db_fd)
        os.unlink(self.db_path)

    def create_test_user(self, username="testuser", email="test@example.com", password="password"):
        user = User.query.filter_by(email=email).first()
        if not user:
            user = User(username=username, email=email)
            user.set_password(password)
            db.session.add(user)
            db.session.commit()
        return user

    def login(self, email="test@example.com", password="password"):
        return self.client.post('/login', data=dict(
            email=email,
            password=password
        ), follow_redirects=True)

    def logout(self):
        return self.client.get('/logout', follow_redirects=True)

if __name__ == '__main__':
    unittest.main()
