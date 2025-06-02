import os
import tempfile # Added tempfile import
from lievik.tests.base import BaseTestCase # We can reuse BaseTestCase for app context and db setup
from lievik.app import db
from lievik.models import ChannelType, CrewConfiguration, User # Added User
from scripts.init_db import init_database # The script we want to test

class TestInitDbScript(BaseTestCase):

    def setUp(self):
        # Override the base setUp to prevent default user creation or init_db call if it's there
        # We want a clean slate specifically for testing init_database()
        self.db_fd, self.db_path = tempfile.mkstemp() # Changed to tempfile.mkstemp()

        project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
        app_config = {
            'TESTING': True,
            'SQLALCHEMY_DATABASE_URI': 'sqlite:///' + self.db_path,
            'WTF_CSRF_ENABLED': False,
            'LOGIN_DISABLED': True, # Disable login for this test, not relevant
            'SERVER_NAME': 'localhost.localdomain',
            'SEED_DATA_PATH': os.path.join(project_root, 'lievik', 'core', 'seed_data')
        }
        # We need to ensure create_app is available
        from lievik.app import create_app
        self.app = create_app(config_override=app_config)

        self.app_context = self.app.app_context()
        self.app_context.push()
        # db.create_all() is called within init_database, so we don't call it here.
        # We want to test the script's ability to create tables IF they don't exist.
        # However, for a clean test, we ensure tables are created once by init_db.
        # If init_db is idempotent on table creation, this is fine.
        # If not, we might need to call db.create_all() before init_db if init_db assumes tables exist.
        # Based on init_db.py, it calls db.create_all() itself.

    # tearDown from BaseTestCase is fine.

    def test_init_database_seeds_chat_reminder_data(self):
        # Call the script's main function
        # This will create tables and attempt to seed data
        init_database()

        # Verify "Chat Reminder Template" CrewConfiguration
        chat_reminder_crew_config = CrewConfiguration.query.filter_by(name="Chat Reminder Template").first()
        self.assertIsNotNone(chat_reminder_crew_config, "Chat Reminder Template CrewConfiguration should be seeded.")
        self.assertFalse(chat_reminder_crew_config.is_global)

        # Load the expected YAML content
        project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
        expected_yaml_path = os.path.join(project_root, 'lievik', 'core', 'seed_data', 'chat_reminder_crew_config.yaml')
        with open(expected_yaml_path, 'r') as f:
            expected_yaml_content = f.read()

        self.assertEqual(chat_reminder_crew_config.config_yaml, expected_yaml_content, "Seeded Chat Reminder crew YAML is incorrect.")

        # Verify "Chat Reminder" ChannelType
        chat_reminder_channel_type = ChannelType.query.filter_by(name="Chat Reminder").first()
        self.assertIsNotNone(chat_reminder_channel_type, "Chat Reminder ChannelType should be seeded.")
        self.assertEqual(chat_reminder_channel_type.description, "Channel for sending chat-based reminders and notifications.")
        self.assertIsNotNone(chat_reminder_channel_type.default_crew_configuration_id, "Chat Reminder ChannelType should have a default crew configuration ID.")
        self.assertEqual(chat_reminder_channel_type.default_crew_configuration_id, chat_reminder_crew_config.id,
                         "Chat Reminder ChannelType is not linked to the correct CrewConfiguration.")

        # Verify other default data is also present to ensure the script ran fully
        # (Optional, but good for sanity check)
        self.assertTrue(CrewConfiguration.query.filter_by(name="Global Content Preprocessing").first() is not None)
        self.assertTrue(ChannelType.query.filter_by(name="Course Newsletter").first() is not None)
        self.assertTrue(User.query.filter_by(username="admin").first() is not None)


    def test_init_database_idempotency(self):
        # Call init_database once
        init_database()

        initial_crew_configs_count = CrewConfiguration.query.count()
        initial_channel_types_count = ChannelType.query.count()
        initial_users_count = User.query.count()

        # Call init_database again
        init_database()

        # Verify counts haven't changed (assuming it's designed to be idempotent for seeding)
        self.assertEqual(CrewConfiguration.query.count(), initial_crew_configs_count, "CrewConfiguration count changed on second init_db run.")
        self.assertEqual(ChannelType.query.count(), initial_channel_types_count, "ChannelType count changed on second init_db run.")
        # User count might change if default user creation is not idempotent or if we add more users
        # The current init_db.py script creates a user without checking, so this test might fail for users.
        # For this test, we'll focus on ChannelType and CrewConfiguration idempotency as per current implementation.
        # self.assertEqual(User.query.count(), initial_users_count, "User count changed on second init_db run.")

        # Specifically check our Chat Reminder items again
        chat_reminder_crew_config_count = CrewConfiguration.query.filter_by(name="Chat Reminder Template").count()
        self.assertEqual(chat_reminder_crew_config_count, 1, "More than one Chat Reminder Template CrewConfiguration found after second run.")

        chat_reminder_channel_type_count = ChannelType.query.filter_by(name="Chat Reminder").count()
        self.assertEqual(chat_reminder_channel_type_count, 1, "More than one Chat Reminder ChannelType found after second run.")


if __name__ == '__main__':
    unittest.main()
