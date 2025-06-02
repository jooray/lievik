import json
from lievik.tests.base import BaseTestCase
from lievik.app import db
from lievik.models import ChannelType, CrewConfiguration, User, Channel # Added Channel for testing delete constraint

class TestChannelTypeRoutes(BaseTestCase):

    def setUp(self):
        super().setUp()
        # Create a prerequisite CrewConfiguration for ChannelType creation/update
        self.crew_config = CrewConfiguration(name="Test Default Crew", config_yaml="some_yaml_config")
        self.crew_config_2 = CrewConfiguration(name="Test Updated Crew", config_yaml="other_yaml_config")
        db.session.add_all([self.crew_config, self.crew_config_2])
        db.session.commit()
        self.user = User.query.filter_by(email="test@example.com").first()


    def test_create_channel_type(self):
        self.login()
        response = self.client.post('/api/channel-types',
                                    data=json.dumps({
                                        'name': 'New Test Channel Type',
                                        'description': 'A type for testing',
                                        'default_crew_configuration_id': self.crew_config.id
                                    }),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 201)
        data = response.get_json()
        self.assertEqual(data['name'], 'New Test Channel Type')
        self.assertTrue(ChannelType.query.filter_by(name='New Test Channel Type').first())

    def test_create_channel_type_missing_name(self):
        self.login()
        response = self.client.post('/api/channel-types',
                                    data=json.dumps({
                                        'description': 'A type for testing'
                                    }),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 400)
        data = response.get_json()
        self.assertIn('Missing required field: name', data['error'])

    def test_create_channel_type_duplicate_name(self):
        self.login()
        self.client.post('/api/channel-types',
                         data=json.dumps({'name': 'Duplicate Type', 'default_crew_configuration_id': self.crew_config.id}),
                         content_type='application/json')
        response = self.client.post('/api/channel-types',
                                    data=json.dumps({'name': 'Duplicate Type', 'default_crew_configuration_id': self.crew_config.id}),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 409)
        data = response.get_json()
        self.assertIn('ChannelType name already exists', data['error'])

    def test_create_channel_type_invalid_crew_config(self):
        self.login()
        response = self.client.post('/api/channel-types',
                                    data=json.dumps({'name': 'Type With Invalid Crew', 'default_crew_configuration_id': 9999}),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 404)
        data = response.get_json()
        self.assertIn('Default CrewConfiguration not found', data['error'])


    def test_get_all_channel_types(self):
        self.login()
        # Create some channel types
        ct1 = ChannelType(name="CT1", default_crew_configuration_id=self.crew_config.id)
        ct2 = ChannelType(name="CT2", default_crew_configuration_id=self.crew_config.id)
        db.session.add_all([ct1, ct2])
        db.session.commit()

        response = self.client.get('/api/channel-types')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data['count'], 2 + ChannelType.query.filter(ChannelType.name.contains("Reminder")).count()) # Account for seeded
        self.assertTrue(any(ct['name'] == 'CT1' for ct in data['channel_types']))
        self.assertTrue(any(ct['name'] == 'CT2' for ct in data['channel_types']))

    def test_get_specific_channel_type(self):
        self.login()
        ct = ChannelType(name="Specific CT", default_crew_configuration_id=self.crew_config.id)
        db.session.add(ct)
        db.session.commit()

        response = self.client.get(f'/api/channel-types/{ct.id}')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data['name'], 'Specific CT')

    def test_get_specific_channel_type_not_found(self):
        self.login()
        response = self.client.get('/api/channel-types/9999')
        self.assertEqual(response.status_code, 404)

    def test_update_channel_type(self):
        self.login()
        ct = ChannelType(name="Old Name CT", description="Old desc", default_crew_configuration_id=self.crew_config.id)
        db.session.add(ct)
        db.session.commit()

        response = self.client.put(f'/api/channel-types/{ct.id}',
                                   data=json.dumps({
                                       'name': 'New Name CT',
                                       'description': 'New desc',
                                       'default_crew_configuration_id': self.crew_config_2.id
                                   }),
                                   content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data['name'], 'New Name CT')
        self.assertEqual(data['description'], 'New desc')
        self.assertEqual(data['default_crew_configuration_id'], self.crew_config_2.id)

        updated_ct = ChannelType.query.get(ct.id)
        self.assertEqual(updated_ct.name, 'New Name CT')

    def test_update_channel_type_name_conflict(self):
        self.login()
        ct1 = ChannelType(name="Existing Name", default_crew_configuration_id=self.crew_config.id)
        ct2 = ChannelType(name="To Be Updated", default_crew_configuration_id=self.crew_config.id)
        db.session.add_all([ct1, ct2])
        db.session.commit()

        response = self.client.put(f'/api/channel-types/{ct2.id}',
                                   data=json.dumps({'name': 'Existing Name'}),
                                   content_type='application/json')
        self.assertEqual(response.status_code, 409) # Expecting conflict due to name change

    def test_update_channel_type_invalid_crew_config(self):
        self.login()
        ct = ChannelType(name="CT For Crew Update", default_crew_configuration_id=self.crew_config.id)
        db.session.add(ct)
        db.session.commit()
        response = self.client.put(f'/api/channel-types/{ct.id}',
                                   data=json.dumps({'default_crew_configuration_id': 9001}),
                                   content_type='application/json')
        self.assertEqual(response.status_code, 404)
        data = response.get_json()
        self.assertIn('New default CrewConfiguration not found', data['error'])

    def test_delete_channel_type(self):
        self.login()
        ct = ChannelType(name="To Delete CT", default_crew_configuration_id=self.crew_config.id)
        db.session.add(ct)
        db.session.commit()
        ct_id = ct.id

        response = self.client.delete(f'/api/channel-types/{ct_id}')
        self.assertEqual(response.status_code, 200)
        self.assertIsNone(ChannelType.query.get(ct_id))

    def test_delete_channel_type_in_use(self):
        self.login()
        ct_in_use = ChannelType(name="CT In Use", default_crew_configuration_id=self.crew_config.id)
        db.session.add(ct_in_use)
        db.session.commit()

        # Create a Channel that uses this ChannelType
        # Ensure user is available from BaseTestCase or create one
        channel = Channel(name="Test Channel Using Type",
                          user_id=self.user.id,
                          language="en",
                          channel_type_id=ct_in_use.id,
                          crew_configuration_id=self.crew_config.id) # crew_config might need to be channel's specific or type's default
        db.session.add(channel)
        db.session.commit()

        response = self.client.delete(f'/api/channel-types/{ct_in_use.id}')
        self.assertEqual(response.status_code, 409) # Conflict
        data = response.get_json()
        self.assertIn('Cannot delete ChannelType: It is currently in use', data['error'])
        self.assertIsNotNone(ChannelType.query.get(ct_in_use.id))

    def test_unauthenticated_access_channel_types(self):
        # Test GET all
        response = self.client.get('/api/channel-types')
        self.assertEqual(response.status_code, 302) # Redirects to login

        # Test GET specific (assuming one exists with ID 1 or use a known ID)
        # Create one first without login to ensure it exists if db is empty
        ct = ChannelType(name="Auth Test CT", default_crew_configuration_id=self.crew_config.id)
        db.session.add(ct)
        db.session.commit()
        response = self.client.get(f'/api/channel-types/{ct.id}')
        self.assertEqual(response.status_code, 302)

        # Test POST
        response = self.client.post('/api/channel-types', data=json.dumps({'name': 'No Auth Type'}), content_type='application/json')
        self.assertEqual(response.status_code, 302)

        # Test PUT
        response = self.client.put(f'/api/channel-types/{ct.id}', data=json.dumps({'name': 'No Auth Update'}), content_type='application/json')
        self.assertEqual(response.status_code, 302)

        # Test DELETE
        response = self.client.delete(f'/api/channel-types/{ct.id}')
        self.assertEqual(response.status_code, 302)

if __name__ == '__main__':
    unittest.main()
