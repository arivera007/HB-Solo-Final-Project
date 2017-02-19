CREATE OR REPLACE FUNCTION update_geo () RETURNS void AS 
$BODY$
--    tweeterID = 829775912010854401
DECLARE
    r tweets%rowtype;
    recd geoResult%rowtype;
BEGIN
    FOR r in  select * from tweets where city_id = 1 limit 10
    LOOP
        recd = getGeocode(r.author_location);
        UPDATE tweets SET city_id = recd.city_id, lat = recd.lat, lon = recd.lon
        WHERE tweet_id = r.tweet_id;
    END LOOP;
END
$BODY$
LANGUAGE 'plpgsql';