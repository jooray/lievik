import json
from lievik.tests.base import BaseTestCase
from lievik.app import db
from lievik.models import User, Channel, ChannelType, CrewConfiguration

class TestChannelRoutes(BaseTestCase):

    def setUp(self):
        super().setUp()
        self.user1 = self.create_test_user(username="user1", email="user1@example.com", password="password1")
        self.user2 = self.create_test_user(username="user2", email="user2@example.com", password="password2")

        self.crew_config1 = CrewConfiguration(name="Crew Config 1", config_yaml="yaml1")
        self.crew_config2 = CrewConfiguration(name="Crew Config 2", config_yaml="yaml2")
        db.session.add_all([self.crew_config1, self.crew_config2])
        db.session.commit()

        self.channel_type1 = ChannelType(name="Type 1", default_crew_configuration_id=self.crew_config1.id)
        self.channel_type2 = ChannelType(name="Type 2", default_crew_configuration_id=self.crew_config2.id)
        db.session.add_all([self.channel_type1, self.channel_type2])
        db.session.commit()

        # Pre-login user1 for most tests
        self.login(email="user1@example.com", password="password1")

    def test_create_channel(self):
        response = self.client.post('/api/channels',
                                    data=json.dumps({
                                        'name': 'User1 Channel 1',
                                        'language': 'en',
                                        'channel_type_id': self.channel_type1.id
                                        # crew_configuration_id will use default from channel_type1
                                    }),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 201)
        data = response.get_json()
        self.assertEqual(data['name'], 'User1 Channel 1')
        self.assertEqual(data['user_id'], self.user1.id)
        self.assertEqual(data['crew_configuration_id'], self.crew_config1.id) # Check default is picked up
        self.assertTrue(Channel.query.filter_by(name='User1 Channel 1', user_id=self.user1.id).first())

    def test_create_channel_with_specific_crew_config(self):
        response = self.client.post('/api/channels',
                                    data=json.dumps({
                                        'name': 'User1 Channel 2',
                                        'language': 'fr',
                                        'channel_type_id': self.channel_type1.id,
                                        'crew_configuration_id': self.crew_config2.id # Override default
                                    }),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 201)
        data = response.get_json()
        self.assertEqual(data['name'], 'User1 Channel 2')
        self.assertEqual(data['crew_configuration_id'], self.crew_config2.id)


    def test_create_channel_missing_fields(self):
        response = self.client.post('/api/channels',
                                    data=json.dumps({'name': 'Incomplete Channel'}),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 400)
        data = response.get_json()
        self.assertIn('Missing required fields', data['error'])

    def test_create_channel_invalid_channel_type(self):
        response = self.client.post('/api/channels',
                                    data=json.dumps({
                                        'name': 'Channel Invalid Type',
                                        'language': 'en',
                                        'channel_type_id': 9999
                                    }),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 404)
        self.assertIn('ChannelType not found', response.get_json()['error'])

    def test_create_channel_invalid_crew_config(self):
        response = self.client.post('/api/channels',
                                    data=json.dumps({
                                        'name': 'Channel Invalid Crew',
                                        'language': 'en',
                                        'channel_type_id': self.channel_type1.id,
                                        'crew_configuration_id': 9999
                                    }),
                                    content_type='application/json')
        self.assertEqual(response.status_code, 404)
        self.assertIn('Selected CrewConfiguration not found', response.get_json()['error'])


    def test_get_channels_for_user(self):
        # User1 already has channels created in other tests, or create some here
        ch1 = Channel(name="U1 CH Test Get 1", user_id=self.user1.id, language="en", channel_type_id=self.channel_type1.id, crew_configuration_id=self.crew_config1.id)
        ch2 = Channel(name="U1 CH Test Get 2", user_id=self.user1.id, language="es", channel_type_id=self.channel_type2.id, crew_configuration_id=self.crew_config2.id)
        # Channel for another user
        ch_other_user = Channel(name="U2 CH", user_id=self.user2.id, language="de", channel_type_id=self.channel_type1.id, crew_configuration_id=self.crew_config1.id)
        db.session.add_all([ch1, ch2, ch_other_user])
        db.session.commit()

        response = self.client.get('/api/channels')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()

        # Count channels created by user1 in this test and potentially others
        user1_channel_names = {c['name'] for c in data['channels']}
        self.assertIn("U1 CH Test Get 1", user1_channel_names)
        self.assertIn("U1 CH Test Get 2", user1_channel_names)
        self.assertNotIn("U2 CH", user1_channel_names) # Ensure user2's channel is not listed

    def test_get_specific_channel_owned_by_user(self):
        ch = Channel(name="Specific Channel U1", user_id=self.user1.id, language="it", channel_type_id=self.channel_type1.id, crew_configuration_id=self.crew_config1.id)
        db.session.add(ch)
        db.session.commit()

        response = self.client.get(f'/api/channels/{ch.id}')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data['name'], "Specific Channel U1")

    def test_get_specific_channel_not_owned_by_user(self):
        ch_other_user = Channel(name="OtherUserChannel", user_id=self.user2.id, language="pt", channel_type_id=self.channel_type1.id, crew_configuration_id=self.crew_config1.id)
        db.session.add(ch_other_user)
        db.session.commit()

        response = self.client.get(f'/api/channels/{ch_other_user.id}')
        self.assertEqual(response.status_code, 404) # first_or_404 due to user_id filter

    def test_get_specific_channel_not_found(self):
        response = self.client.get('/api/channels/99999')
        self.assertEqual(response.status_code, 404)

    def test_update_channel_owned_by_user(self):
        ch = Channel(name="ChannelToUpdate U1", user_id=self.user1.id, language="en", channel_type_id=self.channel_type1.id, crew_configuration_id=self.crew_config1.id)
        db.session.add(ch)
        db.session.commit()

        update_data = {
            'name': 'Updated Channel Name U1',
            'language': 'fr',
            'description_by_user': 'Updated description',
            'channel_type_id': self.channel_type2.id,
            'crew_configuration_id': self.crew_config2.id,
            'is_active': False
        }
        response = self.client.put(f'/api/channels/{ch.id}',
                                   data=json.dumps(update_data),
                                   content_type='application/json')
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data['name'], 'Updated Channel Name U1')
        self.assertEqual(data['language'], 'fr')
        self.assertEqual(data['description_by_user'], 'Updated description')
        self.assertEqual(data['channel_type_id'], self.channel_type2.id)
        self.assertEqual(data['crew_configuration_id'], self.crew_config2.id)
        self.assertEqual(data['is_active'], False)

        db.session.refresh(ch) # Refresh from DB
        self.assertEqual(ch.name, 'Updated Channel Name U1')


    def test_update_channel_not_owned_by_user(self):
        ch_other_user = Channel(name="Update OtherUserChannel", user_id=self.user2.id, language="de", channel_type_id=self.channel_type1.id, crew_configuration_id=self.crew_config1.id)
        db.session.add(ch_other_user)
        db.session.commit()

        response = self.client.put(f'/api/channels/{ch_other_user.id}',
                                   data=json.dumps({'name': 'Attempted Update'}),
                                   content_type='application/json')
        self.assertEqual(response.status_code, 404) # first_or_404 due to user_id filter

    def test_update_channel_invalid_type_or_crew(self):
        ch = Channel(name="ChannelForInvalidUpdate", user_id=self.user1.id, language="en", channel_type_id=self.channel_type1.id, crew_configuration_id=self.crew_config1.id)
        db.session.add(ch)
        db.session.commit()

        # Invalid ChannelType
        response_type = self.client.put(f'/api/channels/{ch.id}', data=json.dumps({'channel_type_id': 9000}), content_type='application/json')
        self.assertEqual(response_type.status_code, 404)
        self.assertIn("New ChannelType not found", response_type.get_json()['error'])

        # Invalid CrewConfiguration
        response_crew = self.client.put(f'/api/channels/{ch.id}', data=json.dumps({'crew_configuration_id': 9001}), content_type='application/json')
        self.assertEqual(response_crew.status_code, 404)
        self.assertIn("New CrewConfiguration not found", response_crew.get_json()['error'])


    def test_delete_channel_owned_by_user(self):
        ch = Channel(name="ChannelToDelete U1", user_id=self.user1.id, language="es", channel_type_id=self.channel_type1.id, crew_configuration_id=self.crew_config1.id)
        db.session.add(ch)
        db.session.commit()
        channel_id = ch.id

        response = self.client.delete(f'/api/channels/{channel_id}')
        self.assertEqual(response.status_code, 200)
        self.assertIsNone(Channel.query.get(channel_id))

    def test_delete_channel_not_owned_by_user(self):
        ch_other_user = Channel(name="Delete OtherUserChannel", user_id=self.user2.id, language="pt", channel_type_id=self.channel_type1.id, crew_configuration_id=self.crew_config1.id)
        db.session.add(ch_other_user)
        db.session.commit()

        response = self.client.delete(f'/api/channels/{ch_other_user.id}')
        self.assertEqual(response.status_code, 404) # first_or_404 due to user_id filter
        self.assertIsNotNone(Channel.query.get(ch_other_user.id))

    def test_unauthenticated_access_channels(self):
        self.logout() # Ensure no user is logged in

        # Create a channel to attempt to interact with
        ch_for_auth_test = Channel(name="AuthTestChannel", user_id=self.user1.id, language="en", channel_type_id=self.channel_type1.id, crew_configuration_id=self.crew_config1.id)
        db.session.add(ch_for_auth_test)
        db.session.commit()

        response_get_all = self.client.get('/api/channels')
        self.assertEqual(response_get_all.status_code, 302) # Redirects to login

        response_get_one = self.client.get(f'/api/channels/{ch_for_auth_test.id}')
        self.assertEqual(response_get_one.status_code, 302)

        response_post = self.client.post('/api/channels', data=json.dumps({'name': 'NoAuth'}), content_type='application/json')
        self.assertEqual(response_post.status_code, 302)

        response_put = self.client.put(f'/api/channels/{ch_for_auth_test.id}', data=json.dumps({'name': 'NoAuthUpdate'}), content_type='application/json')
        self.assertEqual(response_put.status_code, 302)

        response_delete = self.client.delete(f'/api/channels/{ch_for_auth_test.id}')
        self.assertEqual(response_delete.status_code, 302)

if __name__ == '__main__':
    unittest.main()
