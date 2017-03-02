CREATE LANGUAGE plpythonu;

CREATE TYPE geoResult AS (city_id int, lat float, lon float);

CREATE or replace FUNCTION getGeocode (location text) RETURNS geoResult AS $$
    import urllib2
    import os
    import json


    query = plpy.prepare("SELECT city_id, lat, lon FROM cachedgeocodes WHERE city = $1", ["text"])
    recds = plpy.execute(query, [location])
    if recds.nrows() > 0:  # & recds.status() == SPI_OK_SELECT (Maybe is 5):
        return recds[0]
    else:
        query = plpy.prepare("SELECT getGeoFromAPI($1)", ["text"])
        recds = plpy.execute(query,[location])
#        plpy.notice(recds) 
        return recds[0]['getgeofromapi'] # Get the row data from the plpy object returning from the function call.


$$ LANGUAGE plpythonu;

CREATE or REPLACE FUNCTION getGeoFromAPI (location text) RETURNS geoResult AS $$
    import urllib2
    import os
    import json

    address = '+'.join(location.split(' ')).rstrip('+') # In case we get extra + for the empty spaces
    key = ''

    url = "https://maps.googleapis.com/maps/api/geocode/json?address=%s&key=%s" % (address, key)

    # In case any error getting the location, I do nothing and return None instead of 0,0,0.
    try:
        response = urllib2.urlopen(url)
    except urllib2.HTTPError:
        return {'city_id':None, 'lat':None, 'lon':None}
    except plpy.SPIError:   # Or any other error
        return {'city_id':None, 'lat':None, 'lon':None}

    jsonresponse = json.loads(response.read())
    if jsonresponse['status']  == 'OK':
        geocode = jsonresponse["results"][0]['geometry']['location']
        # Maybe add if country = USA here, but I think this should be handled by a calling object.
        try:
            country = next(x["long_name"] for x in jsonresponse['results'][0]["address_components"] if "country" in x["types"])
        except StopIteration: # Look for base exception
            country = location

        query = plpy.prepare("INSERT INTO cachedgeocodes (city, country, lat, lon) VALUES ($1, $2, $3, $4) returning city_id, lat, lon", ["text", "text", "float", "float"])
        recds = plpy.execute(query, [location, country, geocode['lat'], geocode['lng']])
        if recds.nrows > 0 : # and recds.status() = SPI_OK_INSERT
            return recds[0]
    elif jsonresponse['status']  == 'ZERO_RESULTS':
        return {'city_id':0, 'lat':0, 'lon':0}

    # Anything else could be an network error or database error. I return None instead of 0,0,0
    return {'city_id':None, 'lat':None, 'lon':None}


$$ LANGUAGE plpythonu;