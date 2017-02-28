import unittest
import Model
import HBtweeter

import server


class HBTweets_IntegrationTestCase(unittest.TestCase):

    def setUp(self):
        """ Stuff to do before every test. """
        self.client = server.app.test_client()
        server.app.config['TESTING'] = True
        Model.connect_to_db(server.app)

    def test_home(self):
        result = self.client.get('/')
        self.assertEqual(200, result.status_code)
        self.assertIn('<h1>TRACKING TWEETS AND THEIR LOCATION</h1>', result.data)

    def test_map(self):
        result = self.client.get('/map')
        self.assertEqual(200, result.status_code)
        self.assertIn('<div id="tweets-map"', result.data)

    def test_read_db(self):
        result = server.read_db()
        self.assertGreaterEqual(len(result), 1)  # Checking is bringing results
        self.assertNotEqual(result[0], 0)        # Checking is a "viable" geocode


class HBTweets_UnitTestCase(unittest.TestCase):

    def setUp(self):
        """ Stuff to do before every test. """
        Model.connect_to_db(Model.app)

    def test_get_search_tweets(self):
        """ Testing obtaining one tweet from Tweeter """
        self.assertEqual(HBtweeter.get_search_tweets("Trump", 1), 1)

    def test_getGeoCode(self):
        """ Testing the stored procedure that checks cached geocodes. """
        f = Model.db.text('select getgeocode(:location)')
        recds = Model.db.session.execute(f, {'location': 'San Francisco, CA'}).fetchone()
        self.assertEqual('(24,37.7749295,-122.4194155)', recds['getgeocode'])

    def test_psql_getGeoFromAPI(self):
        """ Testing the stored procedure that calls google Map for geocode. """
        f = Model.db.text('select getGeoFromAPI(:location)')
        recds = Model.db.session.execute(f, {'location': 'San Francisco, CA'}).fetchone()
        self.assertIn(',37.7749295,-122.4194155)', recds['getgeofromapi'])  # Column city is not Unique, so it returns a new city_id when I run this Stored Procedure from here.

    # Testing the API call from outside psql
    def GoogleGeo():
        """
        Make a call to Googla Map API with an specific address.
        >>> test_GoogleGeo()
        37.4219493 -122.0847727
        """
        import urllib2
        import os
        import json

        address = "1600+Amphitheatre+Parkway,+Mountain+View,+CA"
        key = os.environ['GOOGLE_MAP_API_GEOCODE']
        url = "https://maps.googleapis.com/maps/api/geocode/json?address=%s&key=%s" % (address, key)

        response = urllib2.urlopen(url)
        jsongeocode = json.loads(response.read())
        geocode = jsongeocode["results"][0]['geometry']['location']

        # pdb.set_trace()

        return (geocode['lat'], geocode['lng'])
        # make this function a test for the API, this should be:
        # 37.4219493 -122.0847727

if __name__ == "__main__":
    unittest.main()
