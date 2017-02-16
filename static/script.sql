CREATE or replace FUNCTION getLat10 (location text) RETURNS  INTEGER AS $$
    import urllib2
    import os
    import json


    query = plpy.prepare("SELECT city_id FROM cachedgeocodes WHERE city = $1", ["text"])
    recds = plpy.execute(query, [location])
    if recds.nrows() > 0:
        return recds[0]['city_id']
    else:
        return 0


$$ LANGUAGE plpythonu;
