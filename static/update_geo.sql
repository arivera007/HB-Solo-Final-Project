CREATE OR REPLACE FUNCTION update_geo () RETURNS void AS 
$BODY$
--    tweeterID = 829775912010854401
DECLARE
    r tweets%rowtype;
    recd geoResult%rowtype;
BEGIN
    FOR r in  select * from tweets where city_id = 1 limit 5
    LOOP
        IF r.author_location != '' THEN
            raise notice '%', r.author_location;
            recd = getGeocode(r.author_location);
            raise notice '%', recd;
            UPDATE tweets SET city_id = cast(recd.city_id as int), lat = recd.lat, lon = recd.lon
            WHERE tweet_id = r.tweet_id;
        END IF;
    END LOOP;
END
$BODY$
LANGUAGE 'plpgsql';