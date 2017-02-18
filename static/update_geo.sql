CREATE OR REPLACE FUNCTION update_geo () RETURNS void AS $$
--    tweeterID = 829775912010854401

-- Not tested and sintaxis is correct 
    for r in  select tweet_id, author_location from tweets where city_id = 1 limit 10; 
        recd = getGeocode(r.author_location)
        UPDATE tweets SET city_id = recd.city_id, lat = recd.lat, lon = recd.lon
        WHERE tweet_id = r.tweet_id


$$ LANGUAGE SQL;



CREATE or replace FUNCTION getGeocode (location text) RETURNS  INTEGER AS $$
    import urllib2
    import os
    import json


    query = plpy.prepare("SELECT city_id FROM cachedgeocodes WHERE city = $1", ["text"])
    recds = plpy.execute(query, [location])
    if recds.nrows() > 0:
        return recds[0]['city_id']
    else:
        query = plpy.prepare("SELECT getGeoFromAPI($1)", ["text"])
        recds = plpy.execute(query,[location])
        if recds.nrows() > 0:
            return recds[0]['getgeofromapi']
        else:
            return 0


$$ LANGUAGE plpythonu;

CREATE or REPLACE FUNCTION getGeoFromAPI (location text) RETURNS  INTEGER AS $$
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
        query = plpy.prepare("INSERT INTO cachedgeocodes (city, state, lat, lon) VALUES ($1, $2, $3, $4) returning city_id", ["text", "text", "float", "float"])
        # recds = plpy.execute(query, [city+', '+state, country, geocode['lat'], geocode['lng']])
        recds = plpy.execute(query, [location, country, geocode['lat'], geocode['lng']])

        if recds.nrows() > 0:
            return recds[0]['city_id']
        else:
            return 0
    else:
        return 0


$$ LANGUAGE plpythonu;