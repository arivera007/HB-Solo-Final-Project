-- CREATE TYPE geoResult AS (city_id int, lat float, lon float);

CREATE or replace FUNCTION getGeocode (location text) RETURNS SETOF geoResult AS $$
    import urllib2
    import os
    import json


    query = plpy.prepare("SELECT city_id, lat, lon FROM cachedgeocodes WHERE city = $1", ["text"])
    recds = plpy.execute(query, [location])
    if recds.nrows() > 0:
        return recds
    else:
        query = plpy.prepare("SELECT getGeoFromAPI($1)", ["text"])
        recds = plpy.execute(query,[location])
        return recds[0] # My problem is here.


$$ LANGUAGE plpythonu;

CREATE or REPLACE FUNCTION getGeoFromAPI (location text) RETURNS SETOF geoResult AS $$
    import urllib2
    import os
    import json

    address = '+'.join(location.split(' ')).rstrip('+') # incase we get extra + for the empty spaces
    key = ''

    url = "https://maps.googleapis.com/maps/api/geocode/json?address=%s&key=%s" % (address, key)

    response = urllib2.urlopen(url)
    jsonresponse = json.loads(response.read())
    if jsonresponse['status']  == 'OK':
        geocode = jsonresponse["results"][0]['geometry']['location']
        # We might not need these two, since I am puting the original location.
        #city = [x["long_name"] for x in jsonresponse['results'][0]["address_components"] if x["types"][0] == "locality"][0]
        #state = [x["short_name"] for x in jsonresponse['results'][0]["address_components"] if x["types"][0] == "administrative_area_level_1"][0]
        country = [x["long_name"] for x in jsonresponse['results'][0]["address_components"] if x["types"][0] == "country"][0]

        # Change to COuntry instead of state, city to city_state ??
        query = plpy.prepare("INSERT INTO cachedgeocodes (city, state, lat, lon) VALUES ($1, $2, $3, $4) returning city_id, lat, lon", ["text", "text", "float", "float"])
        # recds = plpy.execute(query, [city+', '+state, country, geocode['lat'], geocode['lng']])
        recds = plpy.execute(query, [location, country, geocode['lat'], geocode['lng']])
        if recds.nrows > 0:
            return recds
#            return [{'city_id': recds[0]['city_id'], 'lat':geocode['lat'], 'lon':geocode['lng']}]
#            return {'city_id': 1, 'lat':geocode['lat'], 'lon':geocode['lng']}

    null_recd = [{'city_id':0, 'lat':0, 'lon':0}]
    return null_recd


$$ LANGUAGE plpythonu;