--
-- PostgreSQL database dump
--

-- Dumped from database version 9.5.5
-- Dumped by pg_dump version 9.5.5

SET statement_timeout = 0;
SET lock_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: plpgsql; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpgsql; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpgsql IS 'PL/pgSQL procedural language';


--
-- Name: plpythonu; Type: EXTENSION; Schema: -; Owner: 
--

CREATE EXTENSION IF NOT EXISTS plpythonu WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION plpythonu; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION plpythonu IS 'PL/PythonU untrusted procedural language';


SET search_path = public, pg_catalog;

--
-- Name: georesult; Type: TYPE; Schema: public; Owner: user
--

CREATE TYPE georesult AS (
	city_id text,
	lat double precision,
	lon double precision
);


ALTER TYPE georesult OWNER TO "user";

--
-- Name: addtoenv(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION addtoenv() RETURNS integer
    LANGUAGE plpythonu
    AS $$

import os
os.environ['key'] = 'Adriana'

return 1
$$;


ALTER FUNCTION public.addtoenv() OWNER TO "user";

--
-- Name: getgeocode(text); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION getgeocode(location text) RETURNS georesult
    LANGUAGE plpythonu
    AS $_$
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


$_$;


ALTER FUNCTION public.getgeocode(location text) OWNER TO "user";

--
-- Name: getgeofromapi(text); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION getgeofromapi(location text) RETURNS georesult
    LANGUAGE plpythonu
    AS $_$
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
    except plpy.SPIError:
        return {'city_id':None, 'lat':None, 'lon':None}

    jsonresponse = json.loads(response.read())
    if jsonresponse['status']  == 'OK':
        geocode = jsonresponse["results"][0]['geometry']['location']
        # In case I want to filter the good addresses, I could learn to check the results in "types".
        # type_of_place = [x["types"] for x in jsonresponse['results'][0]["address_components"] if "political" in x["types"]]
        country = [x["long_name"] for x in jsonresponse['results'][0]["address_components"] if "country" in x["types"]]
        # Maybe add if country = USA here, but I think this should be handled by a calling object.
        country = country[0] if len(country) > 0 else location  

        # Change to COuntry instead of state, city to city_state ??
        query = plpy.prepare("INSERT INTO cachedgeocodes (city, state, lat, lon) VALUES ($1, $2, $3, $4) returning city_id, lat, lon", ["text", "text", "float", "float"])
        recds = plpy.execute(query, [location, country, geocode['lat'], geocode['lng']])
        if recds.nrows > 0 : # and recds.status() = SPI_OK_INSERT
            return recds[0]
    elif jsonresponse['status']  == 'ZERO_RESULTS':
        return {'city_id':0, 'lat':0, 'lon':0}

    # Anything else could be an network error or database error. I return None instead of 0,0,0
    return {'city_id':None, 'lat':None, 'lon':None}


$_$;


ALTER FUNCTION public.getgeofromapi(location text) OWNER TO "user";

--
-- Name: getgooglegeo(text); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION getgooglegeo(location text) RETURNS integer
    LANGUAGE plpythonu
    AS $_$
    import urllib2
    import os
    import json

    address = '+'.join(location.split(' ')).rstrip('+') # incase we get extra + for the empty spaces
    key = ''
    print os.environ

    url = "https://maps.googleapis.com/maps/api/geocode/json?address=%s&key=%s" % (address, key)

    response = urllib2.urlopen(url)
    jsonresponse = json.loads(response.read())
    if jsonresponse['status']  == 'OK':
        geocode = jsonresponse["results"][0]['geometry']['location']
        city = [x["long_name"] for x in jsonresponse['results'][0]["address_components"] if x["types"][0] == "locality"][0]
        state = [x["short_name"] for x in jsonresponse['results'][0]["address_components"] if x["types"][0] == "administrative_area_level_1"][0]
        country = [x["long_name"] for x in jsonresponse['results'][0]["address_components"] if x["types"][0] == "country"][0]

        # Change to COuntry instead of state, city to city_state ??
        query = plpy.prepare("INSERT INTO cachedgeocodes (city, state, lat, lon) VALUES ($1, $2, $3, $4) returning city_id", ["text", "text", "float", "float"])

        recds = plpy.execute(query, [city+' , '+state, country, geocode['lat'], geocode['lng']])


        return recds[0]['city_id']
    else:
        return 0


$_$;


ALTER FUNCTION public.getgooglegeo(location text) OWNER TO "user";

--
-- Name: getlat(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION getlat() RETURNS double precision
    LANGUAGE plpythonu
    AS $$
    import urllib2

    address="1600+Amphitheatre+Parkway,+Mountain+View,+CA"
    key="AIzaSyBY4R1yfldyOBd0bgctr8A12qLIs0JnLdU"
    url="https://maps.googleapis.com/maps/api/geocode/json?address=%s&key=%s" % (address, key)

    response = urllib2.urlopen(url)
    jsongeocode = response.read()    

    return jsongeocode["geometry"]["location"]["lat"]
$$;


ALTER FUNCTION public.getlat() OWNER TO "user";

--
-- Name: getlat10(text); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION getlat10(location text) RETURNS integer
    LANGUAGE plpythonu
    AS $_$
    import urllib2
    import os
    import json


    query = plpy.prepare("SELECT city_id FROM cachedgeocodes WHERE city = $1", ["text"])
    recds = plpy.execute(query, [location])
    if recds.nrows() > 0:
        return recds[0]['city_id']
    return 0


$_$;


ALTER FUNCTION public.getlat10(location text) OWNER TO "user";

--
-- Name: getlat2(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION getlat2() RETURNS double precision
    LANGUAGE plpythonu
    AS $$
    import urllib2

    address="1600+Amphitheatre+Parkway,+Mountain+View,+CA"
    key="AIzaSyBY4R1yfldyOBd0bgctr8A12qLIs0JnLdU"
    url="https://maps.googleapis.com/maps/api/geocode/json?address=%s&key=%s" % (address, key)

    response = urllib2.urlopen(url)
    jsongeocode = response.read()    

    return jsongeocode["results"][0]['geometry']['location']['lat']
$$;


ALTER FUNCTION public.getlat2() OWNER TO "user";

--
-- Name: getlat3(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION getlat3() RETURNS double precision
    LANGUAGE plpythonu
    AS $$
    import urllib2

    address="1600+Amphitheatre+Parkway,+Mountain+View,+CA"
    key=os.environ['GOOGLE_MAP_API_GEOCODE']
    url="https://maps.googleapis.com/maps/api/geocode/json?address=%s&key=%s" % (address, key)

    response = urllib2.urlopen(url)
    jsongeocode = response.read()

    return jsongeocode["results"][0]['geometry']['location']['lat']
$$;


ALTER FUNCTION public.getlat3() OWNER TO "user";

--
-- Name: getlat4(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION getlat4() RETURNS double precision
    LANGUAGE plpythonu
    AS $$
    import urllib2
    import os

    address="1600+Amphitheatre+Parkway,+Mountain+View,+CA"
    key=os.environ['GOOGLE_MAP_API_GEOCODE']
    url="https://maps.googleapis.com/maps/api/geocode/json?address=%s&key=%s" % (address, key)

    response = urllib2.urlopen(url)
    jsongeocode = response.read()

    return jsongeocode["results"][0]['geometry']['location']['lat']
$$;


ALTER FUNCTION public.getlat4() OWNER TO "user";

--
-- Name: getlat5(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION getlat5() RETURNS double precision
    LANGUAGE plpythonu
    AS $$
    import urllib2
    import os
    import json

    address = "1600+Amphitheatre+Parkway,+Mountain+View,+CA"
    key = os.environ['GOOGLE_MAP_API_GEOCODE']
    url = "https://maps.googleapis.com/maps/api/geocode/json?address=%s&key=%s" % (address, key)

    response = urllib2.urlopen(url)
    jsongeocode = json.loads(response.read())
    geocode = jsongeocode["results"][0]['geometry']['location']

    pdb.set_trace()

    return geocode['lat'], geocode['lng']
$$;


ALTER FUNCTION public.getlat5() OWNER TO "user";

--
-- Name: getlat6(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION getlat6() RETURNS double precision
    LANGUAGE plpythonu
    AS $$
    import urllib2
    import os
    import json

    address = "1600+Amphitheatre+Parkway,+Mountain+View,+CA"
    key = 'AIzaSyBY4R1yfldyOBd0bgctr8A12qLIs0JnLdU'
    url = "https://maps.googleapis.com/maps/api/geocode/json?address=%s&key=%s" % (address, key)

    response = urllib2.urlopen(url)
    jsongeocode = json.loads(response.read())
    geocode = jsongeocode["results"][0]['geometry']['location']

    pdb.set_trace()

    return geocode['lat'], geocode['lng']
$$;


ALTER FUNCTION public.getlat6() OWNER TO "user";

--
-- Name: getlat7(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION getlat7() RETURNS double precision
    LANGUAGE plpythonu
    AS $$
    import urllib2
    import os
    import json

    address = "1600+Amphitheatre+Parkway,+Mountain+View,+CA"
    key = 'AIzaSyBY4R1yfldyOBd0bgctr8A12qLIs0JnLdU'
    url = "https://maps.googleapis.com/maps/api/geocode/json?address=%s&key=%s" % (address, key)

    response = urllib2.urlopen(url)
    jsongeocode = json.loads(response.read())
    geocode = jsongeocode["results"][0]['geometry']['location']

    return geocode['lat'], geocode['lng']
$$;


ALTER FUNCTION public.getlat7() OWNER TO "user";

--
-- Name: getxxgeocode(text); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION getxxgeocode(location text) RETURNS integer
    LANGUAGE plpythonu
    AS $_$
    import urllib2
    import os
    import json


    query = plpy.prepare("SELECT city_id FROM cachedgeocodes WHERE city = $1", ["text"])
    recds = plpy.execute(query, [location])
    if recds.nrows() > 0:
        return recds[0]['city_id']
    else:
        query = plpy.prepare("select getGeoFromAPI($1)", ["text"])
        return plpy.execute(query,[location])


$_$;


ALTER FUNCTION public.getxxgeocode(location text) OWNER TO "user";

--
-- Name: random_color(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION random_color() RETURNS character varying
    LANGUAGE plpythonu
    AS $$
  return ('blue', 'red')
$$;


ALTER FUNCTION public.random_color() OWNER TO "user";

--
-- Name: testenviron(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION testenviron() RETURNS text
    LANGUAGE plpythonu
    AS $$

nothing = plpy.execute("select addToEnv()")

import os
key = os.environ['key']
return key

$$;


ALTER FUNCTION public.testenviron() OWNER TO "user";

--
-- Name: update_geo(); Type: FUNCTION; Schema: public; Owner: user
--

CREATE FUNCTION update_geo() RETURNS void
    LANGUAGE plpgsql
    AS $$
--    tweeterID = 829775912010854401
DECLARE
    r tweets%rowtype;
    recd geoResult%rowtype;
BEGIN
    raise notice 'HELLO';
    FOR r in  select * from tweets where city_id = 1 AND author_location <> ''
    LOOP
        raise notice 'WTF';
        IF r.author_location != '' THEN
            raise notice '%', r.author_location;
            recd = getGeocode(r.author_location);
            raise notice '%', recd;
            raise notice '***************************************';
            UPDATE tweets SET city_id = cast(recd.city_id as int), lat = recd.lat, lon = recd.lon
            WHERE tweet_id = r.tweet_id;
        END IF;
    END LOOP;
END
$$;


ALTER FUNCTION public.update_geo() OWNER TO "user";

SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: cachedgeocodes; Type: TABLE; Schema: public; Owner: user
--

CREATE TABLE cachedgeocodes (
    city_id integer NOT NULL,
    city character varying(50) NOT NULL,
    state character varying(50) NOT NULL,
    lat double precision NOT NULL,
    lon double precision NOT NULL
);


ALTER TABLE cachedgeocodes OWNER TO "user";

--
-- Name: cachedgeocodes_city_id_seq; Type: SEQUENCE; Schema: public; Owner: user
--

CREATE SEQUENCE cachedgeocodes_city_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE cachedgeocodes_city_id_seq OWNER TO "user";

--
-- Name: cachedgeocodes_city_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: user
--

ALTER SEQUENCE cachedgeocodes_city_id_seq OWNED BY cachedgeocodes.city_id;


--
-- Name: tweets; Type: TABLE; Schema: public; Owner: user
--

CREATE TABLE tweets (
    tweet_id bigint NOT NULL,
    user_id bigint,
    text character varying(150) NOT NULL,
    lat double precision,
    lon double precision,
    author_location character varying(50),
    city_id integer,
    sentiment integer
);


ALTER TABLE tweets OWNER TO "user";

--
-- Name: tweets_tweet_id_seq; Type: SEQUENCE; Schema: public; Owner: user
--

CREATE SEQUENCE tweets_tweet_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER TABLE tweets_tweet_id_seq OWNER TO "user";

--
-- Name: tweets_tweet_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: user
--

ALTER SEQUENCE tweets_tweet_id_seq OWNED BY tweets.tweet_id;


--
-- Name: city_id; Type: DEFAULT; Schema: public; Owner: user
--

ALTER TABLE ONLY cachedgeocodes ALTER COLUMN city_id SET DEFAULT nextval('cachedgeocodes_city_id_seq'::regclass);


--
-- Name: tweet_id; Type: DEFAULT; Schema: public; Owner: user
--

ALTER TABLE ONLY tweets ALTER COLUMN tweet_id SET DEFAULT nextval('tweets_tweet_id_seq'::regclass);


--
-- Data for Name: cachedgeocodes; Type: TABLE DATA; Schema: public; Owner: user
--

COPY cachedgeocodes (city_id, city, state, lat, lon) FROM stdin;
2	Marin County, CA	USA	35.5549999999999997	-122.454999999999998
3	San Jose , CA	country	37.3382081999999969	-121.886328599999999
4	Santa Clara , CA	U	37.3541079000000025	-121.955235599999995
5	Los Altos , CA	United States	37.3852182999999982	-122.114129800000001
6	San Mateo , CA	United States	37.5629916999999978	-122.325525400000004
7	Millbrae , CA	United States	37.5985468000000012	-122.387194199999996
8	East Palo Alto , CA	United States	37.4688273000000009	-122.141075099999995
10	Santa Rosa , CA	United States	38.4404290000000017	-122.7140548
15	Santa Rosa , CA	United States	38.4404290000000017	-122.7140548
16	Santa Rosa , CA	United States	38.4404290000000017	-122.7140548
17	Santa Rosa , CA	United States	38.4404290000000017	-122.7140548
18	Palo Alto, CA	United States	37.4418834000000018	-122.143019499999994
19	Lower Haight, San Francisco	United States	37.7720655999999977	-122.431152600000004
20	Menlo Park, CA	United States	37.4529598000000021	-122.181725200000002
21	the edge of the universe	United States	42.3242343000000005	-71.1064492000000001
22	guns and roses	United States	32.7809760999999966	-96.7933391999999913
23	edge of the universe	United States	42.3242343000000005	-71.1064492000000001
1	nowhere	nowhere	0	0
24	San Francisco, CA	United States	37.7749294999999989	-122.419415499999999
31	San Mateo, CA	United States	37.5629916999999978	-122.325525400000004
32	San Fernando, CA	United States	34.281946099999999	-118.438971899999999
35	Santa Barbara, CA	United States	34.420830500000001	-119.698190100000005
37	San Francisco	United States	37.7749294999999989	-122.419415499999999
38	Oakland, CA	United States	37.8043637000000032	-122.271113700000001
39	Toronto, Ontario	Canada	43.6532259999999965	-79.3831842999999964
40	Virginia Beach, VA	United States	36.8529263	-75.9779849999999897
41	Portland, OR	United States	45.5230621999999983	-122.676481600000002
42	Ireland	Ireland	53.1423672000000025	-7.6920535999999986
43	San Jose, CA	United States	37.3382081999999969	-121.886328599999999
44	United States	United States	37.0902400000000014	-95.7128909999999991
45	Olmsted Falls, Ohio	United States	41.3750489999999971	-81.9081936999999982
46	Boise, ID	United States	43.6187102000000024	-116.214606799999999
47	Rockefeller University	United States	40.7629123000000035	-73.9558291000000025
48	Albuquerque nm 	United States	35.0853335999999985	-106.605553400000005
49	Ontario	Canada	51.2537749999999974	-85.3232138999999989
50	Southern California	United States	34.9592083000000002	-116.419388999999995
51	Scotland	United Kingdom	56.4906711999999871	-4.20264579999999999
52	NEW YORK USA	United States	40.7127837000000028	-74.0059413000000035
53	Tokyo, Japan	Japan	35.6894874999999985	139.691706399999987
54	Washington, DC	United States	38.9071922999999984	-77.0368706999999944
55	Columbus, Ohio	United States	39.9611755000000031	-82.9987941999999919
56	USA	United States	37.0902400000000014	-95.7128909999999991
57	Columbus, OH	United States	39.9611755000000031	-82.9987941999999919
58	Ann Arbor, MI	United States	42.2808256	-83.7430377999999962
59	Boston 	United States	42.3600824999999972	-71.0588800999999961
60	NYC	United States	40.7127837000000028	-74.0059413000000035
61	California	United States	36.7782610000000005	-119.417932399999998
62	Buffalo, NY	United States	42.8864467999999874	-78.8783688999999981
63	Hampton, NH and Keene, NH	United States	42.9489154999999982	-70.7917236000000116
64	Massachusetts, USA	United States	42.4072107000000003	-71.3824374000000006
65	Arlington, TX	United States	32.7356869999999986	-97.1080655999999891
66	Midwest, USA	United States	43.4113604000000066	-106.2800242
67	Crestview Hills, KY	United States	39.027282900000003	-84.5849437999999907
68	New Jersey, USA	United States	40.0583237999999966	-74.4056611999999973
69	New York I Dubai 	United Arab Emirates	25.1185420000000015	55.2000630000000001
70	Kalamazoo, MI	United States	42.2917069000000012	-85.5872286000000031
71	California, USA	United States	36.7782610000000005	-119.417932399999998
72	NoVa	Macedonia (FYROM)	41.3329866999999993	21.5393308999999995
73	New York, NY	United States	40.7127837000000028	-74.0059413000000035
74	Madison, WI	United States	43.0730517000000006	-89.4012302000000005
75	Silver Spring, MD	United States	38.9906657000000081	-77.0260880000000014
76	Bronx, NY	United States	40.844781900000001	-73.864826800000003
77	Dardanelle Arkansas	United States	35.223140800000003	-93.1579531999999944
78	Austin, Texas	United States	30.2671530000000004	-97.743060799999995
79	Albany, NY	United States	42.6525792999999993	-73.7562317000000007
80	MexCity	Mexico	19.4258027999999996	-99.1595385999999905
81	Nueva York, USA	United States	40.7127837000000028	-74.0059413000000035
82	Washington, USA	United States	47.7510740999999967	-120.740138599999995
83	Michigan, USA	United States	44.3148442999999972	-85.6023642999999907
84	New York, USA	United States	40.7127837000000028	-74.0059413000000035
85	Wimbledon	United Kingdom	51.4183388999999877	-0.220628800000000014
86	Lived in California & Maryland	United States	35.4818270000000027	-120.664748000000003
87	London, UK	United Kingdom	51.5073508999999987	-0.127758299999999991
88	Kentucky, USA	United States	37.8393331999999987	-84.2700178999999991
89	Florida, USA	United States	27.6648274000000001	-81.5157535000000024
90	Cleveland, Ohio	United States	41.4993199999999973	-81.6943605000000019
91	Wisconsin, USA	United States	43.7844397000000001	-88.7878678000000008
92	Duluth, MN	United States	46.7866718999999875	-92.1004851999999943
93	City of Angels 	United States	34.0522342000000009	-118.243684900000005
94	Chicago	United States	41.8781135999999989	-87.6297981999999962
95	The Noble Kingdom of Bronx	United States	40.8294277999999977	-73.8696819999999974
96	Worcestershire UK	United Kingdom	52.2545225000000002	-2.26683820000000003
97	Fullerton, CA	United States	33.8703596000000005	-117.924296600000005
98	Lincoln, IL	United States	40.1483768000000012	-89.364818299999996
99	Pittsburgh, PA	United States	40.4406247999999877	-79.9958864000000034
100	Indiana, USA	United States	40.2671940999999975	-86.1349019000000027
101	Tampa, FL	United States	27.9505750000000006	-82.4571775999999943
102	Minneapolis, MN	United States	44.9777529999999999	-93.2650107999999989
103	Mers les Bains	France	50.0660719999999984	1.38928699999999994
104	Springfield, PA	United States	39.9306677000000008	-75.3201878000000136
105	Kremlin	Russia	55.7520232999999976	37.6174993999999998
106	Austin, TX	United States	30.2671530000000004	-97.743060799999995
107	Pennsylvania, USA	United States	41.2033216000000024	-77.1945247000000023
108	Searcy, AR	United States	35.2468203999999972	-91.7336845999999895
109	Coronado/San Diego	United States	32.6858853000000025	-117.183089100000004
110	Paris	France	48.8566140000000004	2.35222189999999998
111	Seattle	United States	47.6062094999999985	-122.332070799999997
112	Tyngsboro, MA	United States	42.6766695999999968	-71.4244223999999974
113	Chattanooga, TN	United States	35.0456296999999992	-85.3096800999999942
114	Nashville, TN 	United States	36.1626637999999971	-86.7816016000000019
115	Los Angeles	United States	34.0522342000000009	-118.243684900000005
116	Deutschland	Germany	51.1656910000000025	10.4515259999999994
117	The Future	United States	37.7885056000000006	-122.443542899999997
118	Northern Illinois	United States	41.9343246999999977	-88.7760936999999899
119	Avondale, AZ	United States	33.4355977000000024	-112.349602099999998
120	Wadsworth, Ohio	United States	41.0256101000000015	-81.7298519000000141
122	Tracy, CA	United States	37.7396512999999985	-121.425222700000006
123	Chile	Chile	-35.6751470000000026	-71.5429689999999994
124	Michigan	United States	44.3148442999999972	-85.6023642999999907
125	Virgin Islands, USA	U.S. Virgin Islands	18.3357649999999985	-64.8963349999999934
126	Silicon Valley	United States	37.3874739999999974	-122.0575434
127	Pakistan	Pakistan	30.3753209999999996	69.3451159999999902
128	San Antonio	United States	29.4241218999999994	-98.4936281999999892
129	verified account	United States	41.0450670000000031	-81.4373480000000143
130	Orlando, FL	United States	28.5383354999999987	-81.3792365000000046
131	Independence, MO	United States	39.0911161000000007	-94.4155067999999886
132	Glenview, IL	United States	42.0697509000000025	-87.7878407999999979
133	Manhattan, NY	United States	40.7830603000000025	-73.9712487999999979
134	Queens, NY	United States	40.7282239000000033	-73.7948516000000012
135	Illinois	United States	40.6331248999999985	-89.3985282999999953
136	Poconos PA	United States	41.0700077999999991	-75.4344727000000006
137	Reality 	United States	37.7636865999999998	-122.429033500000003
138	München	Germany	48.1351252999999986	11.5819805999999996
139	Seattle, WA	United States	47.6062094999999985	-122.332070799999997
140	Estados Unidos	United States	37.0902400000000014	-95.7128909999999991
141	Miami, FL	United States	25.7616797999999996	-80.1917901999999998
142	Tree Town, USA	United States	42.2808256	-83.7430377999999962
143	Long Island/Tampa	United States	27.9834776000000005	-82.5370781000000022
144	New Jersey	United States	40.0583237999999966	-74.4056611999999973
145	New York City	United States	40.7127837000000028	-74.0059413000000035
146	Calgary, AB	Canada	51.0486150999999992	-114.070845899999995
147	Simpson College	United States	41.3649879999999968	-93.5636260000000135
148	Toronto	Canada	43.6532259999999965	-79.3831842999999964
149	Boston, MA	United States	42.3600824999999972	-71.0588800999999961
150	San Diego, CA	United States	32.7157380000000018	-117.1610838
151	Everywhere	United States	33.7589187999999965	-84.3640828999999997
152	the roch	United States	42.6251505999999978	-89.0179332000000016
153	Berkeley, CA	United States	37.8715925999999996	-122.272746999999995
154	 Las Vegas	United States	36.1699411999999967	-115.139829599999999
155	Windermere BC Canada	Canada	50.4625249999999994	-115.988646099999997
156	Columbia-Shuswap, British Columbia	Canada	51.5199009000000032	-118.093514099999993
157	Milwaukee, Wisconsin, USA	United States	43.038902499999999	-87.9064735999999982
158	East Tennessee	United States	35.5174913000000032	-86.580447300000003
159	Flux	United States	37.7719992000000033	-122.411003100000002
160	Peru	Peru	-9.18996699999999933	-75.0151520000000005
161	Vancouver, BC 	Canada	49.2827290999999974	-123.120737500000004
162	Utah	United States	39.3209800999999999	-111.093731099999999
163	Naples, FL	United States	26.1420357999999986	-81.7948102999999946
164	Memphis Tennessee	United States	35.1495342999999991	-90.0489800999999943
165	Vancouver, British Columbia	Canada	49.2827290999999974	-123.120737500000004
166	SF Bay Area	United States	37.8271784000000011	-122.291307799999998
167	Houston, TX	United States	29.7604267	-95.3698028000000022
168	Louisville, KY	United States	38.2526646999999969	-85.758455699999999
169	Manhattan	United States	40.7830603000000025	-73.9712487999999979
170	"Coastal elite" 	United States	28.3721652999999989	-80.6676338999999984
171	Carmel, IN	United States	39.9783710000000028	-86.1180434999999989
172	ÜT: 33.893384,-118.038617	United States	38.6315389000000025	-112.121412300000003
173	Bikini Bottom	United States	42.0978360999999879	-88.2774812999999909
174	221B Baker Street	United Kingdom	51.5237715000000023	-0.158538499999999999
175	Poughkeepsie, NY	United States	41.7003713000000005	-73.9209701000000052
176	Los Angeles, CA	United States	34.0522342000000009	-118.243684900000005
177	NE Pennsylvania	United States	42.2156130999999988	-79.8342162999999942
178	Somerville, MA	United States	42.3875967999999972	-71.0994967999999972
179	rural zionsville, indiana	United States	39.9504811999999987	-86.2414964999999967
180	Connecticut, US	United States	41.6032207000000014	-73.0877490000000023
181	Pismo Beach, CA	United States	35.1427533000000025	-120.641282700000005
182	Atlanta	United States	33.7489953999999983	-84.3879823999999985
183	Florida	United States	27.6648274000000001	-81.5157535000000024
184	District of Columbia, USA	United States	38.9071922999999984	-77.0368706999999944
185	Columbia, South Carolina	United States	34.0007104000000027	-81.0348144000000019
186	Midwest	United States	43.4113604000000066	-106.2800242
187	Lima-Perú	Peru	-12.2720956000000001	-76.2710833000000008
188	Hong Kong	Hong Kong	22.3964280000000002	114.109497000000005
189	Hooterville New York	United States	43.3738710000000012	-76.152552
190	Granada, Spain	Spain	37.1773363000000003	-3.59855709999999984
191	NY 	United States	40.7127837000000028	-74.0059413000000035
192	Tacoma, WA	United States	47.2528768000000028	-122.444290600000002
193	in the rain 	Germany	48.6901541000000009	10.9208893000000007
194	Eugene, Oregon	United States	44.0520690999999971	-123.086753599999994
195	Missouri, USA	United States	37.9642528999999982	-91.8318333999999936
196	Grapevine, TX	United States	32.9342918999999981	-97.0780653999999998
197	Elk Grove, CA	United States	38.4087992999999983	-121.371617799999996
198	Papillion, NE	United States	41.1544432000000029	-96.0422377999999952
199	Chicago, IL	United States	41.8781135999999989	-87.6297981999999962
200	Dayton, OH	United States	39.7589478000000014	-84.1916068999999965
201	Greensburg, IN	United States	39.337272200000001	-85.4835810000000009
202	Massachusetts	United States	42.4072107000000003	-71.3824374000000006
203	America	United States	37.0902400000000014	-95.7128909999999991
204	South West Florida	United States	27.6648274000000001	-81.5157535000000024
205	Arlington, VA	United States	38.8799696999999966	-77.106769799999995
206	bay area	United States	37.8271784000000011	-122.291307799999998
207	207	United States	29.7631380000000014	-81.4605270999999931
208	Ghent New York, USA	United States	42.3292525000000026	-73.6156734999999998
209	Rome, NY	United States	43.2128473	-75.455730299999999
210	USA 	United States	37.0902400000000014	-95.7128909999999991
211	South Minneapolis baby!!!	United States	44.9776239999999987	-93.2730382999999961
212	Colorado, USA	United States	39.5500506999999999	-105.782067400000003
213	 Utah 	United States	39.3209800999999999	-111.093731099999999
214	New York	United States	40.7127837000000028	-74.0059413000000035
215	New Haven, CT	United States	41.3082739999999973	-72.927883499999993
216	MANHATTAN	United States	40.7830603000000025	-73.9712487999999979
217	Ames, IA	United States	42.0307811999999998	-93.6319130999999913
218	Las Vegas, NV	United States	36.1699411999999967	-115.139829599999999
219	Austin	United States	30.2671530000000004	-97.743060799999995
220	Kansas City, Mo.	United States	39.0997265000000027	-94.5785666999999961
221	New Mexico	United States	34.5199402000000006	-105.870090099999999
222	Jersey	Jersey	49.2144389999999987	-2.13125000000000009
223	Denver	United States	39.739235800000003	-104.990251000000001
224	Worcester, MA	United States	42.2625931999999978	-71.8022933999999964
225	Texas, USA	United States	31.9685987999999988	-99.9018130999999983
226	Albuquerque, NM, USA	United States	35.0853335999999985	-106.605553400000005
227	Murrayville, Georgia	United States	34.4187082999999987	-83.9057391999999993
228	new york	United States	40.7127837000000028	-74.0059413000000035
229	DTLA	United States	34.0407129999999967	-118.246769299999997
230	Stamford CT	United States	41.0534302000000011	-73.5387340999999992
231	U.S.A.	United States	37.0902400000000014	-95.7128909999999991
232	Columbus, OH, USA	United States	39.9611755000000031	-82.9987941999999919
233	Philadelphia, PA	United States	39.9525839000000005	-75.1652215000000012
234	Maryland, USA	United States	39.0457548999999986	-76.6412711999999914
235	Roanoke, VA	United States	37.2709704000000031	-79.9414265999999998
236	New York , US	United States	40.7127837000000028	-74.0059413000000035
237	Bensalem Pa.	United States	40.0994424999999879	-74.9325682999999998
238	Detroit	United States	42.3314269999999979	-83.0457538
239	Brooklyn, NY	United States	40.6781784000000002	-73.9441578999999933
240	Washington DC, USA	United States	38.9071922999999984	-77.0368706999999944
241	Great Lakes	United States	43.1240448000000001	-89.3499344999999892
242	West Coast	United States	62.411363399999999	-149.072971499999994
243	Toledo, OH	United States	41.6639382999999981	-83.5552120000000116
244	Wakefield, MA	United States	42.5039395000000013	-71.0723390999999936
245	Ottawa, Canada	Canada	45.4215295999999995	-75.6971930999999927
246	Vermont	United States	44.5588028000000023	-72.577841499999991
247	St. Louis	United States	38.6270025000000032	-90.1994041999999894
248	Upstate NY	United States	40.7263542000000029	-73.9865532999999971
249	Philadelphia, PA, US	United States	39.9525839000000005	-75.1652215000000012
250	SoCal	United States	34.9592083000000002	-116.419388999999995
251	Los Angeles, CA.	United States	34.0522342000000009	-118.243684900000005
252	Ontario, Canada	Canada	51.2537749999999974	-85.3232138999999989
253	Boulder, CO	United States	40.0149856000000028	-105.270545600000005
254	México	Mexico	23.6345010000000002	-102.552784000000003
255	Ellenwood, Georgia	United States	33.6097249999999974	-84.2873661999999939
256	California's Central Valley	United States	40.1998776999999876	-122.201107500000006
257	Canada	Canada	56.1303660000000022	-106.346771000000004
258	Philadelphia	United States	39.9525839000000005	-75.1652215000000012
259	LA	United States	34.0522342000000009	-118.243684900000005
260	Miami Beach, FL	United States	25.790654	-80.1300454999999943
261	Tustin, CA	United States	33.745851100000003	-117.826166000000001
262	Minnesota, USA	United States	46.7295530000000028	-94.6858998000000014
263	Virginia, USA	United States	37.4315733999999978	-78.6568941999999964
264	Global Citizen of Earth 	United States	40.7249193999999974	-73.9968806999999913
265	Land O' Lakes, FL	United States	28.2188991999999992	-82.4575938000000122
266	Blue Ridge Mountains	United States	35.7647091999999986	-82.2652846000000011
267	Dallas, TX	United States	32.776664199999999	-96.7969878999999906
268	Třebíč, Czech Republik, EU	Czechia	49.2147869	15.8795515999999992
269	Tucson, AZ	United States	32.2217429000000024	-110.926479
270	Philly!	United States	39.9525839000000005	-75.1652215000000012
271	Visalia, CA	United States	36.3302284000000029	-119.292058499999996
272	Sydney, Australia, Earth	Australia	-33.8633060000000015	151.209317300000009
273	Tír na nÓg 	United States	40.7518130999999997	-73.9939541999999904
274	Chicago, IL USA	United States	41.8781135999999989	-87.6297981999999962
275	With the Cowboys & Indians	United States	33.1106655000000032	-96.8279895999999951
276	Virginia	United States	37.4315733999999978	-78.6568941999999964
277	Nowhere in particular. 	United States	39.645623999999998	-84.1473730000000018
278	Cary, NC	United States	35.7915399999999977	-78.7811169000000007
279	Canada  YYZ	Canada	43.6777176000000082	-79.6248197000000033
280	US	United States	37.0902400000000014	-95.7128909999999991
281	Sunshine State, U.S.	United States	27.6648274000000001	-81.5157535000000024
282	Trenton, NJ	United States	40.2170533999999975	-74.7429383999999999
283	CT	United States	41.6032207000000014	-73.0877490000000023
284	Beaverton, OR	United States	45.4870619999999874	-122.803710199999998
285	Mount Parnassus	Greece	38.535555500000001	22.6216666000000011
286	Washington, D.C.	United States	38.9071922999999984	-77.0368706999999944
287	Reston, Virginia	United States	38.9586307000000005	-77.3570027999999894
288	Tampa, FL -Nationwide	United States	27.9476392000000011	-82.4572026000000022
289	Atlanta, GA	United States	33.7489953999999983	-84.3879823999999985
290	Long Beach, CA	United States	33.7700504000000024	-118.193739500000007
291	Texas USA	United States	31.9685987999999988	-99.9018130999999983
292	Great Southwest	United States	32.8305819999999997	-97.3265169999999955
293	Brownsville, TX	United States	25.9017471999999991	-97.4974837999999977
294	White House	United States	38.8976763000000005	-77.0365297999999967
295	Alpharetta, Georgia	United States	34.0753762000000009	-84.294089900000003
296	New York City, U.S.A.	United States	40.7127837000000028	-74.0059413000000035
297	Portage, MI	United States	42.2011538000000002	-85.5800021999999956
298	Brown city michigan	United States	43.2122486000000023	-82.9896604000000053
299	Brisbane, Australia	Australia	-27.4697707000000015	153.025123500000007
300	Ireland	Ireland	53.1423672000000025	-7.6920535999999986
301	Ireland	Ireland	53.1423672000000025	-7.6920535999999986
302	Ireland	Ireland	53.1423672000000025	-7.6920535999999986
303	Guadalajara, Mexico	Mexico	20.659698800000001	-103.349609200000003
304	Georgia, USA	United States	32.1656221000000002	-82.9000750999999951
305	Carbondale, Ill.	United States	37.7272727000000003	-89.2167500999999987
306	Minnesota 	United States	46.7295530000000028	-94.6858998000000014
307	Castro, San Francisco	United States	37.7609082000000029	-122.435004300000003
308	Mountain Home, Arkansas	United States	36.3353948999999972	-92.3813459999999935
309	Indianapolis, IN	United States	39.7684029999999993	-86.1580680000000001
310	Vancouver, BC	Canada	49.2827290999999974	-123.120737500000004
311	South Carolina, USA	United States	33.8360810000000001	-81.1637245000000007
312	Dallas/Fort Worth	United States	32.7554883000000032	-97.3307657999999947
313	nashville	United States	36.1626637999999971	-86.7816016000000019
314	Arizona	United States	34.0489280999999977	-111.093731099999999
315	NYC, NY	United States	40.7127837000000028	-74.0059413000000035
316	Boston	United States	42.3600824999999972	-71.0588800999999961
317	Squamish BC Canada	Canada	49.7016338999999974	-123.155812100000006
324	NJ	United States	40.0583237999999966	-74.4056611999999973
325	Charlotte, NC	United States	35.2270869000000033	-80.8431266999999991
326	Newark, N.J.	United States	40.7356570000000033	-74.1723666999999978
327	Home	United States	39.8675692999999995	-104.873008799999994
328	Arkansas	United States	35.2010500000000022	-91.8318333999999936
329	Westchester County, New York	United States	41.1220193999999992	-73.7948516000000012
330	Tennessee, USA	United States	35.5174913000000032	-86.580447300000003
331	Colorado 	United States	39.5500506999999999	-105.782067400000003
332	Issaquah, WA	United States	47.5301011000000031	-122.032619100000005
333	Washington State	United States	47.7510740999999967	-120.740138599999995
334	Hawthorne, CA	United States	33.9164031999999978	-118.352574799999999
335	New York City!	United States	40.7127837000000028	-74.0059413000000035
336	August 31st 	United States	33.4158732000000001	-82.1416980999999993
337	Liberty Hill, Texas	United States	30.6649118999999999	-97.9225160999999957
338	cape cod, ma	United States	41.6687896999999978	-70.2962407999999925
339	Montana, USA	United States	46.8796821999999977	-110.362565799999999
340	The Great State of Texas	United States	30.4919176000000007	-97.7240494999999925
341	Rapid Valley, South Dakota	United States	44.0624879000000007	-103.146289899999999
342	Westchester County, NY	United States	41.1220193999999992	-73.7948516000000012
343	At home~ With my Uncle!	United States	42.5424373999999972	-71.738763899999995
344	Hollywood, USA	United States	32.8686979000000008	-96.664495500000001
345	Louveciennes	France	48.8618900000000025	2.11252700000000004
346	Manahawkin, New Jersey	United States	39.6953969999999998	-74.2587527000000023
347	Coachella, california	United States	33.680300299999999	-116.173894000000004
348	San Francisco Bay Area	United States	37.8271784000000011	-122.291307799999998
349	Incline Village, NV	United States	39.2496829999999974	-119.952684700000006
350	Cabot, AR	United States	34.9745320000000035	-92.0165336000000025
351	arizona	United States	34.0489280999999977	-111.093731099999999
352	NC	United States	35.7595730999999972	-79.0192996999999906
353	Baird,Texas	United States	32.3940168000000028	-99.3942435999999958
354	Hyde Park, Chicago	United States	41.7942949999999982	-87.5907009999999957
355	The Land	United States	28.3739489999999996	-81.5518440000000027
356	Boston, Hub of the Universe	United States	42.3600824999999972	-71.0588800999999961
357	Portland, Oregon	United States	45.5230621999999983	-122.676481600000002
358	Kansas City, MO	United States	39.0997265000000027	-94.5785666999999961
359	Glenmora, Louisiana	United States	30.9765796999999985	-92.5851401999999979
360	Illinois, USA	United States	40.6331248999999985	-89.3985282999999953
361	Denver, CO	United States	39.739235800000003	-104.990251000000001
362	Jamaica	Jamaica	18.1095809999999986	-77.2975079999999934
363	nyc	United States	40.7127837000000028	-74.0059413000000035
364	Trump Tower	United States	40.7624283999999975	-73.9737939999999981
365	Connecticut, USA	United States	41.6032207000000014	-73.0877490000000023
366	Palmdale, CA	United States	34.5794343000000026	-118.116461299999997
367	left of centerstage	United States	38.6392200000000017	-90.2316789999999997
368	MN	United States	46.7295530000000028	-94.6858998000000014
369	EARTH	United States	34.2331373000000028	-102.410749300000006
370	Knoxville, TN, USA	United States	35.9606384000000006	-83.9207391999999999
371	Springfield IL	United States	39.7817213000000081	-89.6501480999999956
372	 East coast 	United States	41.8873607000000021	-87.6184064999999919
373	Highway City, CA	United States	36.8108300000000028	-119.883889999999994
374	Islamic States of America	United States	40.7294175999999979	-73.9837677999999954
375	Misquamicut, RI	United States	41.323281999999999	-71.8037269000000009
376	earth	United States	34.2331373000000028	-102.410749300000006
377	Warren, New Jersey	United States	40.6342489000000029	-74.5004795999999914
378	Central WI	United States	41.8873890000000131	-87.7656499999999937
379	TEXAS	United States	31.9685987999999988	-99.9018130999999983
380	Alexandria, Virginia	United States	38.8048355000000029	-77.0469214000000022
381	Texas	United States	31.9685987999999988	-99.9018130999999983
382	Western NY	United States	43.3447294999999997	-75.3878524999999939
383	Sacramento, CA	United States	38.5815719000000001	-121.494399599999994
384	North Carolina, USA	United States	35.7595730999999972	-79.0192996999999906
385	Greenville, SC	United States	34.8526175999999879	-82.3940103999999991
386	Beverly Hills, CA	United States	34.0736204000000029	-118.400356299999999
387	Hillcrest, San Diego, Ca	United States	32.7478637999999975	-117.164709400000007
388	Minnesota	United States	46.7295530000000028	-94.6858998000000014
389	ÜT: 38.745053,-75.190742	United States	40.1856720999999979	-111.613219599999994
390	Tennessee	United States	35.5174913000000032	-86.580447300000003
391	Joshua Tree, CA	United States	34.1347280000000026	-116.3130661
392	City island, New York City	United States	40.8468202000000034	-73.7874982999999958
393	West Virginia, USA	United States	38.5976262000000006	-80.4549025999999969
394	Lumberton, NJ	United States	39.9676482000000135	-74.8003877000000017
395	In The Real World	United States	37.3929055999999989	-122.034889399999997
396	Wakefield, Quebec, Canada	Canada	45.6411033999999987	-75.9284650999999968
397	Livingston, TX	United States	30.7110289999999999	-94.9329898000000014
398	Fort Worth Texas 	United States	32.7554883000000032	-97.3307657999999947
399	Van Nuys, Los Angeles	United States	34.1898565999999988	-118.451357000000002
400	Tiller, OR / Bangkok, Thailand	Thailand	13.7407450999999998	100.558642899999995
401	New York, New York	United States	40.7127837000000028	-74.0059413000000035
402	Tri-cities WA	United States	46.2349998999999983	-119.223301399999997
403	Smoky Mountains, Tennessee 	United States	35.6531943000000027	-83.5070202999999935
404	L.A. California	United States	34.0522342000000009	-118.243684900000005
405	Cocoa Village,FL	United States	28.354867200000001	-80.727678300000008
406	Lakeside, CA	United States	32.8572717999999995	-116.922248800000006
407	¡MOZART, el más grande!	Brazil	-7.25084219999999835	-35.878661000000001
408	Arizona, United States	United States	34.0489280999999977	-111.093731099999999
409	Georgia, Texas, New Mexico	United States	31.9162788000000006	-106.589920199999995
410	Columbus, Ohio, USA	United States	39.9611755000000031	-82.9987941999999919
411	Western USA 	United States	36.6371434000000065	-121.091909999999999
412	New South Wales, Australia	Australia	-31.2532183000000003	146.921098999999998
413	TEXAS, USA	United States	31.9685987999999988	-99.9018130999999983
414	on the road to nonesuch	United States	32.8231585999999993	-96.747238799999991
415	Salt Lake City, Utah	United States	40.7607793000000029	-111.891047400000005
416	L.A	United States	34.0522342000000009	-118.243684900000005
417	Raleigh, NC	United States	35.7795897000000025	-78.6381786999999974
418	Santa Cruz, CA	United States	36.9741171000000008	-122.030796300000006
419	Rocky Mountain Empire.	United States	39.5841160000000016	-104.807118200000005
420	London	United Kingdom	51.5073508999999987	-0.127758299999999991
421	wisconsin	United States	43.7844397000000001	-88.7878678000000008
422	your phone screen	United States	40.3187500000000014	-74.3002800000000008
423	Wilson, NC	United States	35.7212688999999983	-77.9155394999999942
424	Arcadia, FL	United States	27.2158826000000005	-81.8584163999999959
425	texas	United States	31.9685987999999988	-99.9018130999999983
426	Pennsylvania	United States	41.2033216000000024	-77.1945247000000023
427	Perry, OH	United States	41.760325899999998	-81.1409321999999946
428	Mexico	Mexico	23.6345010000000002	-102.552784000000003
429	Clayton, NC	United States	35.6507110000000011	-78.4563914000000011
430	Silicon Valley CA	United States	37.3874739999999974	-122.0575434
431	Peoria, AZ	United States	33.5805955000000012	-112.237377899999998
432	Otisville, MI	United States	43.1661367000000027	-83.5243976000000004
433	San Antonio, TX	United States	29.4241218999999994	-98.4936281999999892
434	LI, NY	United States	40.7891419999999982	-73.1349609999999899
435	pennsylvania	United States	41.2033216000000024	-77.1945247000000023
436	North Carolina	United States	35.7595730999999972	-79.0192996999999906
437	selmer,tn 	United States	35.1700834000000029	-88.5922703999999896
438	Salt Lake City, UT	United States	40.7607793000000029	-111.891047400000005
439	Seattle 	United States	47.6062094999999985	-122.332070799999997
440	New Jersey coast	United States	39.9652553000000026	-74.3118211999999971
441	Panama City Beach Fl	United States	30.1765913999999995	-85.8054879000000028
442	Bakersfield, California	United States	35.3732921000000005	-119.018712500000007
443	Southern CT	United States	41.3325655000000012	-72.947462399999992
444	United States of America 	United States	37.0902400000000014	-95.7128909999999991
445	A magical place	United States	35.9280492999999979	-78.5566810000000117
446	Washington DC, Santiago, Chile	Chile	-33.3935486000000026	-70.79356709999999
447	Sydney, Australia	Australia	-33.8688197000000031	151.209295499999996
448	Depew, NY	United States	42.9039476000000022	-78.6922514999999976
449	St. Louis, Missouri	United States	38.6270025000000032	-90.1994041999999894
450	India	India	20.5936839999999997	78.9628799999999984
451	Hoboken, NJ	United States	40.7439905000000024	-74.032362599999999
452	Tallahassee, FL	United States	30.4382559000000015	-84.2807328999999896
453	Bethlehem, PA	United States	40.6259316000000013	-75.370457899999991
454	Charlottesville, VA	United States	38.0293058999999971	-78.4766781000000151
455	South Dallas|The Dale 	United States	39.6621694000000033	-104.955119199999999
456	Collin County, TX 	United States	33.1795212999999976	-96.4929796999999922
457	Toronto Ontario Canada	Canada	43.6532259999999965	-79.3831842999999964
458	South Jersey	Jersey	49.2144389999999987	-2.13125000000000009
459	Forest Hills, MI	United States	42.9486611000000025	-85.4824840999999935
460	Berkeley, CA, USA	United States	37.8715925999999996	-122.272746999999995
461	kenya	Kenya	-0.0235590000000000001	37.9061930000000018
462	St Louis, MO	United States	38.6270025000000032	-90.1994041999999894
463	San Rafael, CA	United States	37.9735346000000007	-122.531087400000004
464	Des Moines, IA	United States	41.6005448000000015	-93.6091064000000017
465	ÜT: 30.020371,-90.416424	United States	41.5060760000000002	-112.015372400000004
466	Edgewood, MD	United States	39.4187194000000005	-76.2944016000000005
467	Philadelphia 	United States	39.9525839000000005	-75.1652215000000012
468	West Midlands, England	United Kingdom	52.4750743000000028	-1.82983300000000004
469	Ohio, USA	United States	40.4172871000000029	-82.9071230000000128
470	10313 San Carlos Av. SouthGate	United States	33.9400673999999967	-118.206126999999995
471	LAKE PLACID, FLORIDA 	United States	27.2930999000000014	-81.3628501999999969
472	High Plains	United States	40.4344557999999878	-111.903069299999999
473	Jacksonville, FL  USA	United States	30.3321837999999993	-81.6556509999999918
474	Puebla, México	Mexico	19.0412967000000002	-98.2061995999999908
475	 United States of America	United States	37.0902400000000014	-95.7128909999999991
476	Seattle Washington	United States	47.6062094999999985	-122.332070799999997
477	Oregon	United States	43.8041333999999978	-120.554201199999994
478	West Orange, NJ	United States	40.7985698999999968	-74.2390827999999914
479	Manchester, England	United Kingdom	53.4807593000000026	-2.24263050000000019
480	Upstate NY // Omaha, NE	United States	42.7487124000000023	-73.8054980999999941
481	Earth	United States	34.2331373000000028	-102.410749300000006
482	Northern Arizona	United States	35.1830854000000031	-111.654964899999996
483	Cedar Rapids, IA	United States	41.9778795000000002	-91.6656231999999989
484	Lynnwood, WA	United States	47.8209300999999982	-122.315131300000004
485	ARIZONA	United States	34.0489280999999977	-111.093731099999999
486	so cal	United States	34.9592083000000002	-116.419388999999995
487	St. Augustine Florida	United States	29.9012436999999984	-81.3124340999999902
488	Casa Grande,Arizona	United States	32.8795021999999975	-111.757352100000006
489	San DIego, CA	United States	32.7157380000000018	-117.1610838
490	Allentown, PA	United States	40.6084304999999972	-75.4901832999999982
491	Anywhere but here 	United States	47.8458036000000035	-122.297512400000002
492	In The Pines	United States	26.0077649999999991	-80.2962555000000009
493	East Village, Manhattan	United States	40.7264772999999991	-73.9815337000000142
494	Lake Wobegon, MN	United States	45.739167700000003	-94.9545518999999985
495	DC	United States	38.9071922999999984	-77.0368706999999944
496	Heath, TX	United States	32.8365147000000022	-96.4749869999999987
497	New York / Massachusetts	United States	42.0742435000000015	-70.6543095999999906
498	Denton, TX	United States	33.2148412000000022	-97.1330682999999908
499	Tkaronto | Toronto, Ontario	Canada	43.7137442999999877	-79.3650145000000009
500	Lancaster, PA	United States	40.0378754999999984	-76.305514400000007
501	Bremerton WA	United States	47.5650066999999979	-122.626976799999994
502	St Martin, MS	United States	30.4379758000000002	-88.8680853000000042
503	 Vermont	United States	44.5588028000000023	-72.577841499999991
504	Palm Coast, FL	United States	29.5844524	-81.2078698999999915
505	Berkeley, California	United States	37.8715925999999996	-122.272746999999995
506	phoenix az	United States	33.4483771000000019	-112.074037300000001
507	PHX, ARIZONA	United States	33.4483771000000019	-112.074037300000001
508	Cafeteria, USA	United States	40.7405211000000023	-73.997998999999993
509	Provo, UT	United States	40.2338438000000025	-111.658533700000007
510	Nevada, USA	United States	38.8026096999999979	-116.419388999999995
511	New England	United States	43.9653889000000007	-70.8226540999999941
512	Erie , Pennsylvania	United States	42.1292240999999876	-80.0850590000000011
513	Houston Texas	United States	29.7604267	-95.3698028000000022
514	New York, London, Tokyo, LA	United States	40.7246670999999978	-74.0023977999999971
515	Vegan since 2007 in California	United States	38.5602299999999971	-121.486723999999995
516	New York , New York	United States	36.1023714999999967	-115.174555900000001
517	citrus heights CA	United States	38.7071247000000014	-121.281061100000002
518	The universe	United States	36.1568830000000005	-95.9915299999999974
519	Puyallup, WA	United States	47.1853784999999988	-122.292897400000001
520	Outside Gitmo	United States	19.9026482000000016	-75.1001686999999976
521	austin	United States	30.2671530000000004	-97.743060799999995
522	Tatooine...	Tunisia	32.9210902000000019	10.4508956000000008
523	TEXAS!!!!	United States	31.9685987999999988	-99.9018130999999983
524	 Earth	United States	34.2331373000000028	-102.410749300000006
525	sunny side o' the street	United States	37.9022008000000028	-77.0332172999999898
526	St Helens, Tasmania	Australia	-41.3166670000000025	148.233332999999988
527	Shady Shores Texas	United States	33.1651199000000005	-97.0294531999999919
528	Indianapolis	United States	39.7684029999999993	-86.1580680000000001
529	Yucaipa, CA	United States	34.0336250000000007	-117.043086500000001
530	ottawa, canada	Canada	45.4215295999999995	-75.6971930999999927
531	NE GA 	United States	32.1656221000000002	-82.9000750999999951
532	Jackson, MS	United States	32.2987572999999983	-90.1848102999999952
533	E Las Olas, Fort Lauderdale, FL	United States	26.1195078000000009	-80.1239711999999997
534	United States of America	United States	37.0902400000000014	-95.7128909999999991
535	Petaluma CA	United States	38.2324169999999981	-122.636652400000003
536	The Earth	United States	34.2331373000000028	-102.410749300000006
537	Raleigh, North Carolina	United States	35.7795897000000025	-78.6381786999999974
538	Orange County, California	United States	33.717470800000001	-117.831142799999995
539	Texas Hill Country	United States	30.0077771999999996	-95.6425136000000009
540	Munising, MI	United States	46.4110573999999971	-86.6479360999999955
541	San Carlos, CA	United States	37.5071591000000026	-122.260522199999997
542	Monmouth, ME 	United States	44.2386819999999972	-70.0356068999999906
543	7thward New Orleans	United States	29.9769268000000011	-90.0676696000000021
544	Fort Smith, AR	United States	35.3859241999999981	-94.3985474999999923
545	Antarctica	Antarctica	-82.8627518999999921	135
546	Augusta, GA	United States	33.473497799999997	-82.0105147999999957
547	Lakewood, OH	United States	41.481993199999998	-81.7981908000000004
548	Broomall, PA	United States	39.9679330000000022	-75.3470480000000009
549	New Hampshire	United States	43.1938516000000021	-71.5723952999999966
550	Egypt	Egypt	26.8205530000000003	30.8024979999999999
551	dirtywaters	United States	37.7766897999999998	-122.416352200000006
552	350 Spelman Lane	United States	33.745046600000002	-84.4116504999999933
553	Kraków	Poland	50.0646500999999873	19.9449798999999999
554	Beatty Or USA	United States	42.4418149999999983	-121.270831400000006
555	Norway	Norway	60.4720239999999905	8.46894599999999897
556	Missouri 	United States	37.9642528999999982	-91.8318333999999936
557	Lives in Cowboy Country	United States	33.8608820999999978	-118.152222399999999
558	farm station.	United States	40.2346554000000083	-75.0561859999999967
559	Wonderland	United States	42.4136427999999981	-70.9915996999999948
560	Santa Rosa California	United States	38.4404290000000017	-122.7140548
561	Hemet, CA	United States	33.7475202999999979	-116.971968399999994
562	Alabama/Texas	United States	30.8153755999999994	-95.1122372999999897
563	Highland Park, CA	United States	34.1157564000000022	-118.185404199999994
564	Portland, Oregon, USA	United States	45.5230621999999983	-122.676481600000002
565	Houston,Texas	United States	29.7604267	-95.3698028000000022
566	Las Vegas	United States	36.1699411999999967	-115.139829599999999
567	Heart of Manhattan	United States	40.7652440999999968	-73.9902902999999981
568	Colorado & California	United States	39.5500506999999999	-105.782067400000003
569	Cardiff, Wales	United Kingdom	51.4815810000000127	-3.17908999999999997
570	Standing with the Constitution	United States	46.0869408000000007	-100.630127099999996
571	Miami, Florida	United States	25.7616797999999996	-80.1917901999999998
572	Toronto, ON, Canada	Canada	43.6532259999999965	-79.3831842999999964
573	long island ny	United States	40.7891419999999982	-73.1349609999999899
574	Indianapolis, Indiana	United States	39.7684029999999993	-86.1580680000000001
575	North America	North America	54.5259613999999999	-105.255118699999997
576	West Tx	United States	31.8023831000000001	-97.0916691999999983
577	Ft lauderdale	United States	26.1224385999999988	-80.1373174000000148
578	Howards Grove, Wisconsin, USA	United States	43.8338831000000013	-87.8200886999999994
579	Straughn Indiana, USA	United States	39.8089350999999994	-85.2913558999999992
580	Malta	Malta	35.937496000000003	14.3754159999999995
581	California, & Texas 	United States	36.7782610000000005	-119.417932399999998
582	LA area	United States	34.0522342000000009	-118.243684900000005
583	Round Rock, Texas	United States	30.5082550999999995	-97.6788959999999946
584	Tierra Nueva	Mexico	21.6684353999999999	-100.576029300000002
585	Los Angeles/New York	United States	34.0483215000000001	-118.254849300000004
586	West Stockbridge MA USA	United States	42.3338097000000033	-73.3677581999999973
587	the nearest Luby's	United States	30.1713907999999904	-95.4523173999999983
588	Naperville	United States	41.7508391000000003	-88.1535351999999932
589	Burlington,ont	Canada	43.3255195999999998	-79.7990319000000028
590	Hobart, Australia	Australia	-42.8821377000000012	147.327194899999995
591	Not Islington, London 	United Kingdom	51.5492774000000011	-0.108230199999999999
592	Ottawa, ON	Canada	45.4215295999999995	-75.6971930999999927
593	Pa	United States	41.2033216000000024	-77.1945247000000023
594	Left Coast. USA	United States	41.9340157999999974	-87.661010399999995
595	SEATTLE	United States	47.6062094999999985	-122.332070799999997
596	Mexico 	Mexico	23.6345010000000002	-102.552784000000003
597	The Empire State	United States	40.748440500000001	-73.9856643999999903
598	Great Falls, Montana	United States	47.4941835999999995	-111.283344900000003
599	Plainwell, MI	United States	42.4400357000000028	-85.648903500000003
600	St Paul, MN	United States	44.9537029000000032	-93.0899577999999934
601	san antonio, tx	United States	29.4241218999999994	-98.4936281999999892
602	Alabama, USA, Mississippi, USA	United States	33.4959788999999972	-88.3839210999999949
603	México 	Mexico	23.6345010000000002	-102.552784000000003
604	southwest usa	United States	37.0902400000000014	-95.7128909999999991
605	Edmond, OK	United States	35.6528323	-97.478095400000015
606	San Diego	United States	32.7157380000000018	-117.1610838
607	Sherman, TX	United States	33.6356618000000012	-96.6088804999999979
608	Kelso, Washington	United States	46.1467790000000022	-122.908444500000002
609	Montgomery, AL	United States	32.3668052000000017	-86.2999688999999961
610	Salt Lake City	United States	40.7607793000000029	-111.891047400000005
611	Brooklyn	United States	40.6781784000000002	-73.9441578999999933
612	Macon, GA	United States	32.8406945999999991	-83.6324022000000014
613	Miami Florida	United States	25.7616797999999996	-80.1917901999999998
614	Northeast, USA	United States	37.0902400000000014	-95.7128909999999991
615	SOCAL, USA	United States	34.9592083000000002	-116.419388999999995
616	arizona/illinois	United States	41.6509651999999875	-87.5383492000000132
617	Anchorage, AK	United States	61.2180555999999996	-149.900277799999998
618	Nashville, TN	United States	36.1626637999999971	-86.7816016000000019
619	Sydney, New South Wales	Australia	-33.8688197000000031	151.209295499999996
620	Twin Cities, MN	United States	44.9374831000000015	-93.2009997999999911
621	the cutting edge	United States	31.5429658000000011	-97.1498878000000019
622	ATL 	United States	33.7489953999999983	-84.3879823999999985
623	Bowling green massacre	United States	41.3797787999999969	-83.6300825999999944
624	Auckland, NZ	New Zealand	-36.8484596999999994	174.763331499999993
625	Alameda, CA	United States	37.7652064999999979	-122.241635500000001
626	Canada & International	Canada	56.1303660000000022	-106.346771000000004
627	3rd Rock from the Sun	United States	33.3945681000000008	-104.522928100000001
628	A Southern Gal	United States	34.0099868000000001	-118.337462299999999
629	Saint Louis	United States	38.6270025000000032	-90.1994041999999894
630	Near Vancouver	Canada	49.2827290999999974	-123.120737500000004
631	Vail, AZ	United States	32.0005282999999991	-110.700920600000003
632	Central Oregon 	United States	42.1857745000000008	-122.695808
633	Logan, UT	United States	41.736980299999999	-111.833835899999997
634	Portland, OREGON	United States	45.5230621999999983	-122.676481600000002
635	US Florida & Belize	United States	27.6648274000000001	-81.5157535000000024
636	MA 	United States	42.4072107000000003	-71.3824374000000006
637	Kelowna BC	Canada	49.8879518999999974	-119.496010600000005
638	Troy, MICHIGAN	United States	42.606409499999998	-83.1497750999999994
639	Kenya	Kenya	-0.0235590000000000001	37.9061930000000018
640	    Australia	Australia	-25.2743980000000015	133.775136000000003
641	North Ridgeville, Ohio	United States	41.3894905000000008	-82.0190320999999898
642	East Atlanta	United States	33.7366043999999974	-84.3357991999999967
643	hell on earth	United States	38.3291954999999973	-121.979503699999995
644	Edmonton, Alberta, Canada	Canada	53.5443890000000025	-113.490926700000003
645	Central Virginia	United States	38.4852928000000034	-78.9514509999999916
646	Vernon, Florida 	United States	30.622970200000001	-85.7121530999999948
647	Valley Stream, NY	United States	40.6642699000000007	-73.7084644999999909
648	Dyersburg, TN	United States	36.0345159000000024	-89.385628099999991
649	Uncertain,Texas, USA	United States	32.7120882999999978	-94.1212964999999997
650	Four Corners, OR	United States	44.927897999999999	-122.983705900000004
651	Temecula, CA	United States	33.4936391000000029	-117.148364799999996
652	Copenhagen	Denmark	55.6760968000000034	12.5683371000000008
653	Canonsburg, PA	United States	40.262570199999999	-80.1872796999999906
654	Trump's America	United States	30.2309208999999903	-92.5311775999999924
655	Oregon, USA	United States	43.8041333999999978	-120.554201199999994
656	Pacific Northwest	United States	46.5180823999999973	-123.826451199999994
657	Maryland USA	United States	39.0457548999999986	-76.6412711999999914
658	Pacifica, CA	United States	37.613825300000002	-122.486919400000005
659	Europe	Europe	54.5259613999999999	15.2551187000000006
660	NY/Maine	United States	42.1925746000000004	-76.0610360999999955
661	Murphy, TX	United States	33.0151205000000019	-96.6130485999999991
662	Medicine Hat Ab Canada	Canada	50.040548600000001	-110.676425800000004
663	Henderson, NV	United States	36.0395247000000012	-114.981721300000004
664	Fort Lauderdale	United States	26.1224385999999988	-80.1373174000000148
665	The Empire State 	United States	40.748440500000001	-73.9856643999999903
666	Sacramento	United States	38.5815719000000001	-121.494399599999994
667	NONE	Italy	44.9334927000000022	7.54074940000000016
668	Mayo	Ireland	53.9345809999999872	-9.35164560000000122
669	Beacon, NY	United States	41.5048158000000029	-73.9695832000000024
670	Hill City, SD	United States	43.9324854999999985	-103.575192999999999
671	Switzerland	Switzerland	46.8181879999999992	8.22751199999999905
672	San Clemente, CA	United States	33.4269728000000015	-117.611992499999999
673	new jersey	United States	40.0583237999999966	-74.4056611999999973
674	Port St John, FL 	United States	28.4769457999999993	-80.7886656999999957
675	Northern Ireland	United Kingdom	54.7877148999999974	-6.49231449999999999
676	Oklahoma, USA	United States	35.0077519000000024	-97.0928770000000014
677	Albuquerque	United States	35.0853335999999985	-106.605553400000005
678	Ventura, CA	United States	34.2746459999999971	-119.229031599999999
679	Beverly Hills Mi	United States	42.5161310000000014	-83.2625577000000021
680	brasil	Brazil	-14.235004	-51.9252800000000008
681	New York City, NY	United States	40.7127837000000028	-74.0059413000000035
682	 USA	United States	37.0902400000000014	-95.7128909999999991
683	dc's only home depot	United States	38.9208177000000006	-76.9907766999999978
684	Salem, MA	United States	42.5195399999999992	-70.8967154999999991
685	Hollywood	United States	34.0928091999999978	-118.328661400000001
686	Washington DC	United States	38.9071922999999984	-77.0368706999999944
687	On the go	United States	41.6617833999999974	-70.7923674000000034
688	kalamazoo	United States	42.2917069000000012	-85.5872286000000031
689	Roamin Around	United States	44.0811690000000027	-103.225855999999993
690	Valdosta State University	United States	30.8477871999999991	-83.289566999999991
691	Panama City Fl	United States	30.1588129000000009	-85.6602058
692	NY & N.J #RESIST 	United States	40.7127837000000028	-74.0059413000000035
693	São Paulo	Brazil	-23.5505199000000012	-46.6333093999999875
694	Western Mass	United States	42.1536301000000009	-72.5466485999999975
695	$in City 	United States	39.9525167999999979	-75.1630284000000017
696	New Orleans	United States	29.9510657999999914	-90.0715323000000012
697	Canada 	Canada	56.1303660000000022	-106.346771000000004
698	Detroit, MI	United States	42.3314269999999979	-83.0457538
699	South	United States	44.4669941000000009	-73.1709603999999985
700	Altstaetten	Switzerland	47.3774633000000023	9.54691329999999994
701	Cincinnati, OH	United States	39.1031181999999973	-84.5120196000000021
702	Northeast Ohio	United States	40.4172871000000029	-82.9071230000000128
703	Boston & Cooperstown,NY	United States	42.3600824999999972	-71.0588800999999961
704	Pasadena, CA	United States	34.1477848999999978	-118.144515499999997
705	akron	United States	41.0814446999999987	-81.5190052999999892
706	Sicily, Italy	Italy	37.3979296999999988	14.6587820999999998
707	Knoxville, TN	United States	35.9606384000000006	-83.9207391999999999
708	Greece	Greece	39.0742079999999987	21.824311999999999
709	Dublin, OH, USA	United States	40.0992293999999987	-83.1140771000000029
710	Miami Beach, Florida	United States	25.790654	-80.1300454999999943
711	Northeast	Iceland	65.471371199999993	-17.0280279000000014
712	Oak Lawn, IL	United States	41.7199779999999976	-87.7479527999999931
713	Toronto, Canada	Canada	43.6532259999999965	-79.3831842999999964
714	Murfreesboro, TN	United States	35.8456212999999977	-86.390270000000001
715	Los Angeles * Las Vegas 	United States	34.0479403000000005	-118.222820200000001
716	Richmond B.C.	Canada	49.166589799999997	-123.133568999999994
717	Missouri City, TX	United States	29.6185669000000011	-95.5377215000000035
718	Wyoming via North Dakota	United States	47.4954046000000076	-101.3767438
719	Safe Place	United States	38.2109329999999972	-85.751583999999994
720	Chicago, IL 	United States	41.8781135999999989	-87.6297981999999962
721	Medina, OH	United States	41.1432450000000003	-81.8552195999999981
722	Wichita Falls, TX	United States	33.9137084999999985	-98.4933872999999949
723	Decatur, GA	United States	33.7748275000000007	-84.2963122999999968
724	Oakland, California	United States	37.8043637000000032	-122.271113700000001
725	new hyde park ny	United States	40.7351018000000025	-73.6879081999999954
726	WEST SIDE	United States	29.7408977999999991	-95.5827333999999951
727	Ventura, California 	United States	34.2746459999999971	-119.229031599999999
728	Las Vegas, Nevada	United States	36.1699411999999967	-115.139829599999999
729	Den Haag	Netherlands	52.0704977999999983	4.30069989999999969
730	Terry in CT	United States	41.0489674000000022	-73.5032676000000009
731	León, Guanajuato; México	Mexico	21.1250077000000012	-101.685960499999993
732	North of the Wall	United States	40.1692940000000007	-74.0228030000000103
733	Cape Town, South Africa	South Africa	-33.9248685000000023	18.4240552999999991
734	Pioneer, CA	United States	38.4318550999999999	-120.571871900000005
735	Medford, OR	United States	42.3265152000000029	-122.875594899999996
736	brooklyn	United States	40.6781784000000002	-73.9441578999999933
737	Doral, FL	United States	25.8195423999999996	-80.3553301999999974
738	California, PA	United States	40.0656291000000024	-79.8917138999999992
739	Los Angeles/Las Vegas	United States	34.0479403000000005	-118.222820200000001
740	Tampa Bay, FL 	United States	27.763383000000001	-82.5436722000000032
741	Alabama, USA	United States	32.3182314000000019	-86.9022980000000018
742	New Orleans, LA	United States	29.9510657999999914	-90.0715323000000012
743	Alaska, USA	United States	64.2008412999999933	-149.493673300000012
744	Near Seattle, WA, USA	United States	47.6062094999999985	-122.332070799999997
745	Hollywood, CA USA	United States	34.0928091999999978	-118.328661400000001
746	Minneapolis	United States	44.9777529999999999	-93.2650107999999989
747	Georgia	United States	32.1656221000000002	-82.9000750999999951
748	avondale, az	United States	33.4355977000000024	-112.349602099999998
749	Anywhere but here	United States	47.8458036000000035	-122.297512400000002
750	Mobile, AL	United States	30.6953657	-88.0398911999999996
751	fullerton	United States	33.8703596000000005	-117.924296600000005
752	West Michigan	United States	44.3148442999999972	-85.6023642999999907
753	Sunnyside, NY	United States	40.7432759000000004	-73.9196323999999976
754	Netherland	Netherlands	52.1326329999999984	5.29126599999999936
755	worldwide	Canada	43.8169837000000086	-79.532156999999998
756	Winter Haven, Florida	United States	28.0222434999999983	-81.7328566999999993
757	Lansing, MI	United States	42.7325349999999986	-84.5555346999999955
758	Denver, co	United States	39.739235800000003	-104.990251000000001
759	Watertown, MA	United States	42.3709299000000001	-71.1828320999999988
760	OAK PARK, IL	United States	41.885031699999999	-87.7845025000000021
761	nomadic	United States	41.8299578999999966	-72.6092453999999918
762	Cocoa Florida 	United States	28.3861159000000001	-80.7419983999999999
763	ny	United States	40.7127837000000028	-74.0059413000000035
764	CA, previously VT & OR	United States	34.0611808000000025	-118.290878300000003
765	Tupelo, MS	United States	34.2576066000000026	-88.7033859000000007
766	Ohio	United States	40.4172871000000029	-82.9071230000000128
767	Loma Linda,  Ca	United States	34.0483473999999973	-117.261152699999997
768	Everywhere.	United States	33.7589187999999965	-84.3640828999999997
769	Madison	United States	43.0730517000000006	-89.4012302000000005
770	West Palm Beach, FL	United States	26.7153424000000008	-80.0533745999999979
771	California Global	United States	37.6163116999999971	-122.3901106
772	Fort Collins, CO	United States	40.5852602000000005	-105.084423000000001
773	washington, dc 	United States	38.9071922999999984	-77.0368706999999944
774	Delmar, NY	United States	42.6220234999999974	-73.8326232000000005
775	MA	United States	42.4072107000000003	-71.3824374000000006
776	Small Town, North Carolina	United States	35.2801670999999999	-76.8532689999999974
777	St. Louis, MO	United States	38.6270025000000032	-90.1994041999999894
778	Providence, RI	United States	41.8239890999999986	-71.4128343000000001
779	Australia	Australia	-25.2743980000000015	133.775136000000003
780	My own little world 	United States	40.9126389999999986	-111.892747999999997
781	Revere, MA	United States	42.408430199999998	-71.0119947999999965
782	United States 	United States	37.0902400000000014	-95.7128909999999991
783	Sartell, MN	United States	45.621631800000003	-94.2069364999999976
784	Sydney NSW Australia	Australia	-33.8688197000000031	151.209295499999996
785	Ajax, Ontario, Canada	Canada	43.8508552999999992	-79.0203731999999945
786	Anthem, Arizona	United States	33.8543346000000014	-112.125137199999998
787	Johnstown, PA	United States	40.3267406999999878	-78.9219697999999994
788	Proudly Canadian	Canada	43.5991801999999993	-79.6623565000000013
789	Lafayette, IN	United States	40.4167022000000031	-86.8752868999999919
790	Morton Grove, Illinois	United States	42.0405852000000024	-87.7825620999999927
791	 Panama City Beach, Florida	United States	30.1765913999999995	-85.8054879000000028
792	New Hampshire, USA	United States	43.1938516000000021	-71.5723952999999966
793	PDX	United States	45.5897693999999873	-122.595094200000005
794	High Wycombe, England	United Kingdom	51.6286109999999994	-0.748228999999999922
795	Argentina	Argentina	-38.4160970000000006	-63.616671999999987
796	Germany	Germany	51.1656910000000025	10.4515259999999994
797	Terrebonne, OR	United States	44.3528980999999973	-121.177812900000006
798	NC, USA	United States	35.7595730999999972	-79.0192996999999906
799	Kansas	United States	39.0119019999999992	-98.4842464999999976
800	Lille, France	France	50.629249999999999	3.0572560000000002
801	San Antonio TX	United States	29.4241218999999994	-98.4936281999999892
802	Asheville, NC	United States	35.5950581000000028	-82.5514869000000004
803	Maryland	United States	39.0457548999999986	-76.6412711999999914
804	Rochester, NY	United States	43.1610299999999967	-77.6109218999999939
805	Alameda, CA and Sonora, CA	United States	37.552205899999997	-122.329959799999997
806	Oldham Lancs UK	United Kingdom	53.5409298000000007	-2.11136590000000002
807	here	United States	40.725158399999998	-74.0049309999999991
808	Cambridge	United Kingdom	52.2053370000000001	0.121816999999999995
809	Eric	Belgium	51.1829547999999974	3.09386420000000006
810	Honolulu	United States	21.306944399999999	-157.858333299999998
811	Murfreesboro tn	United States	35.8456212999999977	-86.390270000000001
812	 NY & NJ 	United States	40.7127837000000028	-74.0059413000000035
813	Studio City, CA	United States	34.1395596999999995	-118.3870991
814	Osaka	Japan	34.693737800000001	135.502165100000013
815	Macomb Twp	United States	42.6651965000000004	-82.9286427999999916
816	Hamilton, New Zealand	New Zealand	-37.7870011999999988	175.279253000000011
817	Denver, Colorado	United States	39.739235800000003	-104.990251000000001
818	Los Angeles, California	United States	34.0522342000000009	-118.243684900000005
819	Philly	United States	39.9525839000000005	-75.1652215000000012
820	Nairobi. Winnipeg	Kenya	-1.32271019999999995	36.9260693000000018
821	Minnesota/Wisconsin	United States	43.628014499999999	-94.9143238999999994
822	French Quarter, New Orleans	United States	29.9584426000000015	-90.0644106999999963
823	Venezuela	Venezuela	6.42375000000000007	-66.589730000000003
824	Ny	United States	40.7127837000000028	-74.0059413000000035
825	J.David Stevens 	United States	39.1607284999999976	-86.5460669999999936
826	Gorgeous Green Mtns of Vermont	United States	44.7916669999999968	-72.5827779999999905
827	Summerville, SC	United States	33.0185038999999989	-80.1756480999999894
828	Charleston, SC	United States	32.7764748999999966	-79.9310512000000131
829	Bradenton, Florida	United States	27.4989278000000006	-82.5748193999999955
830	Brigadoon	United States	37.9873515999999967	-84.5209080999999998
831	Bliss 	United States	42.5770022999999966	-78.2528190000000023
832	Cambridge, MA	United States	42.3736158000000032	-71.1097334999999902
833	Phoenix, AZ	United States	33.4483771000000019	-112.074037300000001
834	Haddonfield, NJ	United States	39.8915021999999979	-75.0376706999999925
835	Mississippi	United States	32.3546679000000026	-89.3985282999999953
836	Greenville, South Carolina	United States	34.8526175999999879	-82.3940103999999991
837	Rhode Island, USA	United States	41.5800945000000013	-71.4774290999999948
838	Worldwide	Canada	43.8169837000000086	-79.532156999999998
839	Hollywood, FL	United States	26.0112014000000009	-80.1494900999999942
840	St. Paul, MN	United States	44.9537029000000032	-93.0899577999999934
841	Nebraska, USA	United States	41.4925374000000033	-99.9018130999999983
842	berkeley/oakland	United States	37.8687660000000008	-122.256557999999998
843	Seattle / Vancouver	United States	47.5983889000000033	-122.329908599999996
844	Tyler, TX	United States	32.3512600999999975	-95.3010623999999922
845	Heaven Hills	United States	41.2211309999999997	-74.4536689999999908
846	T w i t t er 	Eritrea	15.1793840000000007	39.7823339999999988
847	Denver. , U.S.A.	United States	39.739235800000003	-104.990251000000001
848	Redondo Beach, CA	United States	33.8491816000000014	-118.388407799999996
849	Inland Empire	United States	34.9592083000000002	-116.419388999999995
850	Sud America	United States	43.9695147999999989	-99.9018130999999983
851	Rosenberg, TX	United States	29.5571824999999997	-95.8085622999999913
852	Metro Detroit	United States	42.8105356000000015	-83.0790865000000025
853	NEW FOUND LAND, CANADA	Canada	53.1355091000000002	-57.6604364000000018
854	Independent Nation of New York	United States	40.7353179999999995	-73.988472999999999
855	 CANADA	Canada	56.1303660000000022	-106.346771000000004
856	Port Washington, NY	United States	40.8256561000000033	-73.6981857999999903
857	canada	Canada	56.1303660000000022	-106.346771000000004
858	Luling, LA	United States	29.9321498000000012	-90.3664693999999997
859	Villa Villekulla	United States	30.6711373999999992	-81.4639368999999931
860	white swan, WA 	United States	46.3829037000000071	-120.731180100000003
861	Mason, MI	United States	42.5792027000000033	-84.4435845
862	Johnson City, TN	United States	36.3134397000000035	-82.3534726999999975
863	Panama City, FL	United States	30.1588129000000009	-85.6602058
864	Bakersfield, CA	United States	35.3732921000000005	-119.018712500000007
865	Vienna, Austria	Austria	48.2081743000000031	16.3738188999999998
866	chester/preston	United Kingdom	53.7654396000000006	-2.68211850000000007
867	Aotearoa	United States	28.4057916000000006	-81.5865869999999944
868	North Canton, OH	United States	40.8758910000000029	-81.4023356000000007
869	Helena, Montana	United States	46.5883706999999987	-112.024505399999995
870	Port Jeffeson Station, NY	United States	40.9253763999999975	-73.0473283999999978
871	Denver, Colorado, USA	United States	39.739235800000003	-104.990251000000001
872	North Dakota, USA	United States	47.5514926000000031	-101.002011899999999
873	Brooklyn, NY, USA	United States	40.6781784000000002	-73.9441578999999933
874	Westcoast	United States	62.411363399999999	-149.072971499999994
875	SoCal, USA	United States	34.9592083000000002	-116.419388999999995
876	Terre	France	44.784550000000003	1.98447700000000005
877	Newton, Massachusetts	United States	42.3370413000000028	-71.2092213999999899
878	Northern California, USA	United States	38.8375215000000011	-120.895824200000007
879	Harrisonburg, VA	United States	38.4495688000000015	-78.8689155
880	Utah, USA	United States	39.3209800999999999	-111.093731099999999
881	Monterey, Ca.    #Monterey	United States	36.6002378000000022	-121.894676099999998
882	Malmo	Sweden	55.6049810000000022	13.0038219999999995
883	Eden Prairie, MN	United States	44.8546856000000034	-93.4707859999999897
884	Georgetown, TX	United States	30.6332617999999997	-97.6779841999999974
885	Baltimore, MD	United States	39.2903847999999982	-76.6121892999999972
886	Delaware	United States	38.9108324999999979	-75.5276698999999923
887	vancouver 	Canada	49.2827290999999974	-123.120737500000004
888	Pensacola, FL	United States	30.4213089999999902	-87.2169149000000061
889	Washington, DC & New York City	United States	38.9071922999999984	-77.0368706999999944
890	Stamford, CT	United States	41.0534302000000011	-73.5387340999999992
891	california usa	United States	36.7782610000000005	-119.417932399999998
892	Terra	United States	41.352999699999998	-83.1584428999999972
893	Frankfort, KY	United States	38.2009054999999975	-84.8732835000000136
894	San Francisco, Ca.	United States	37.7749294999999989	-122.419415499999999
895	Boston, MA USA	United States	42.3600824999999972	-71.0588800999999961
896	Erebor	Netherlands	51.4072144000000009	5.54453019999999963
897	prince rupert british columbia	Canada	54.3150367000000003	-130.32081869999999
898	Newton, MA	United States	42.3370413000000028	-71.2092213999999899
899	Dutchess County, NY	United States	41.7784371999999991	-73.7477856999999943
900	Augusta, Georgia	United States	33.473497799999997	-82.0105147999999957
901	Chicago, Il	United States	41.8781135999999989	-87.6297981999999962
902	newport news	United States	37.0870821000000035	-76.4730121999999994
903	Internet. Europe, BeNeLux	Netherlands	52.3700209999999871	5.77675420000000006
904	Joplin MO USA	United States	37.0842271000000068	-94.5132809999999921
905	Atlanta, Georgia	United States	33.7489953999999983	-84.3879823999999985
906	Way up north Wisconsin 	United States	43.0764386999999971	-89.3762757000000079
907	Southaven	United States	34.9918587000000016	-90.0022957999999988
908	Jacksonville, Florida	United States	30.3321837999999993	-81.6556509999999918
909	SW Pennsylvania	United States	41.2033216000000024	-77.1945247000000023
910	West Valley, Utah	United States	40.691613199999999	-112.0010501
911	fingering the lakes	United States	42.7238362000000009	-76.9297353999999984
912	Coppell, TX 75019	United States	32.9618763000000001	-96.9960924999999889
913	Central Florida	United States	28.0582984999999994	-81.8661441999999937
914	Cape May NJ	United States	38.9351125000000025	-74.9060052999999897
915	chicago, il	United States	41.8781135999999989	-87.6297981999999962
916	Milano, Lombardia	Italy	45.4654219000000026	9.18592429999999993
917	Seattle,WA	United States	47.6062094999999985	-122.332070799999997
918	New York, NY 	United States	40.7127837000000028	-74.0059413000000035
919	Stuart, FL	United States	27.1975480000000012	-80.2528257000000025
920	Taiwan	Taiwan	23.6978100000000005	120.960515000000001
921	Corpus Christi, TX	United States	27.8005828000000008	-97.396380999999991
922	Richmond, VA	United States	37.5407245999999972	-77.4360480999999936
923	Federal Way, WA	United States	47.3223221000000009	-122.312622200000007
924	The SEA	United States	37.4075646000000006	-122.120541700000004
925	Palermo	Italy	38.1156878999999975	13.3612670999999992
926	Spring, TX	United States	30.0799404999999993	-95.4171600999999896
927	Planet Aurora	United States	39.6951729999999969	-104.832262900000003
928	Jefferson City, MO	United States	38.5767017000000081	-92.1735163999999969
929	Truckee, CA	United States	39.3279619999999994	-120.183253300000004
930	west coast BC Canada	Canada	49.7560167999999976	-123.937411600000004
931	Atchison, KS	United States	39.5630521000000002	-95.1216355999999905
932	Tempe, AZ	United States	33.4255104000000003	-111.940005400000004
933	Savannah, GA	United States	32.0835407000000004	-81.0998341999999894
934	Phoenixville, PA	United States	40.1303821999999997	-75.5149127999999905
935	Fort Lauderdale, FL	United States	26.1224385999999988	-80.1373174000000148
936	 AZ	United States	34.0489280999999977	-111.093731099999999
937	Lake Country, British Columbia	Canada	50.0548556000000033	-119.414788299999998
938	KCMO	United States	39.0997265000000027	-94.5785666999999961
939	washington, dc	United States	38.9071922999999984	-77.0368706999999944
940	Global	United States	34.1140497000000025	-83.9811014
941	U.S.	United States	37.0902400000000014	-95.7128909999999991
942	Peace 	United States	35.789285999999997	-78.6374519999999961
943	Arizona, USA	United States	34.0489280999999977	-111.093731099999999
944	PHOENIX, AZ	United States	33.4483771000000019	-112.074037300000001
945	Elizabethtown, KY	United States	37.7030645999999976	-85.8649407999999994
946	Roxbury, NJ	United States	40.8693272000000007	-74.6634639999999905
947	Vancouver, WA	United States	45.6318397000000004	-122.671606299999993
948	Snellville, GA	United States	33.8573280000000025	-84.0199108000000052
949	Pennsylvania 	United States	41.2033216000000024	-77.1945247000000023
950	Polo Grounds	United States	35.3900079000000005	-119.121617599999993
951	Melbourne	Australia	-37.8136110000000087	144.963055999999995
952	Spokane, WA	United States	47.6587802000000025	-117.426046600000006
953	Rosedale, Louisiana	United States	30.441305100000001	-91.4520541999999921
954	*At The Farm or Traveling* 	United States	35.1543631999999988	-90.0606636999999921
955	rigaud, quebec	Canada	45.4830737999999997	-74.2821989999999914
956	Santa Monica. Ca.	United States	34.0194542999999996	-118.491191200000003
957	Near the beach, New Jersey	United States	38.9554605999999879	-74.8510538000000025
958	Lucas, Texas (north of Dallas)	United States	32.8107723999999976	-96.82346059999999
959	Maryland USA  	United States	39.0457548999999986	-76.6412711999999914
960	ÜT: 33.96803,-118.42298	United States	38.6315389000000025	-112.121412300000003
961	Hiraeth 	Australia	-30.7501847999999995	151.448498999999998
962	Pittsburgh	United States	40.4406247999999877	-79.9958864000000034
963	Ireland 	Ireland 	53.1423672000000025	-7.6920535999999986
964	Kansas, USA	United States	39.0119019999999992	-98.4842464999999976
965	Rhode Island	United States	41.5800945000000013	-71.4774290999999948
966	nuneaton	United Kingdom	52.5204889999999978	-1.46538199999999996
967	Polk County, FL	United States	27.8617346999999995	-81.6911558999999983
968	Indiana USA	United States	40.2671940999999975	-86.1349019000000027
969	Vermont, USA	United States	44.5588028000000023	-72.577841499999991
970	Springfield, MA	United States	42.1014831000000029	-72.5898109999999974
971	Minnesota, WI	United States	43.4510700000000014	-88.6976526999999919
972	Monterey, CA	United States	36.6002378000000022	-121.894676099999998
973	Millcreek, UT	United States	40.6868914000000004	-111.8754907
974	Dallas, GA. U.S.A.	United States	33.9244531000000009	-84.8413055999999983
975	Southeastern United States	United States	40.0707887000000014	-75.4268251000000021
976	Louisiana 	United States	30.9842976999999991	-91.9623326999999904
977	Mountain View, CA	United States	37.386051700000003	-122.083851100000004
978	St. John's, NL	Canada	47.5615096000000008	-52.7125768000000008
979	Newark OH	United States	40.0581205000000011	-82.4012642
980	Merritt Island, Fl	United States	28.3180687999999989	-80.6659841999999969
981	Amsterdam	Netherlands	52.3702157000000028	4.89516790000000057
982	The Delta	Canada	49.0952154999999877	-123.026475899999994
983	Tiny Town - New England	United Kingdom	50.6132407999999998	-4.38821749999999966
984	East Lansing, MI	United States	42.7369792000000004	-84.4838654000000133
985	Compton, CA	United States	33.8958492000000007	-118.220071200000007
986	The Garden State	United States	40.0583237999999966	-74.4056611999999973
987	Indiana	United States	40.2671940999999975	-86.1349019000000027
988	Kentuckiana	United States	40.4614663999999991	-89.4008965999999958
989	luxembourg	Luxembourg	49.8152729999999977	6.12958299999999934
990	Columbus Ga	United States	32.4609763999999998	-84.9877094
991	houston tx	United States	29.7604267	-95.3698028000000022
992	South Florida	United States	27.6648274000000001	-81.5157535000000024
993	Missouri	United States	37.9642528999999982	-91.8318333999999936
994	Port Orange, FL	United States	29.1383164999999984	-80.995610499999998
995	NJ // MO	United States	40.6789836000000022	-74.3314676999999904
996	Baltimore	United States	39.2903847999999982	-76.6121892999999972
997	Somewhere in Ohio	United States	40.6603544000000028	-82.5521945999999929
998	New England, USA	United States	43.9653889000000007	-70.8226540999999941
999	Pittsburgh PA	United States	40.4406247999999877	-79.9958864000000034
1000	Asakusa, Tokyo	Japan	35.7118769	139.796697099999989
1001	Plymouth, MI	United States	42.3714252999999985	-83.4702132000000034
1002	Houston,TX	United States	29.7604267	-95.3698028000000022
1003	Kenosha, Wi	United States	42.5847424999999973	-87.8211853999999903
\.


--
-- Name: cachedgeocodes_city_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('cachedgeocodes_city_id_seq', 1003, true);


--
-- Data for Name: tweets; Type: TABLE DATA; Schema: public; Owner: user
--

COPY tweets (tweet_id, user_id, text, lat, lon, author_location, city_id, sentiment) FROM stdin;
829537916301012993	17904317	Trump protesters #StreetSnap #StreetFashion #casualwear #fancy #artiseverywhere #style #fashion… https://t.co/aahqHTfAvz	-122.419167000000002	37.7791670000000011	San Francisco, CA 	\N	\N
829758160445517824	2255362627	SF Protesters - portrait one. This woman was the first thing I photographed at the Trump… https://t.co/II71khsigF	-122.417829999999995	37.7802450000000007	Marin County, California	\N	\N
829590173763506176	15856895	"Bridges Not Walls" (New header photo for my anti-Trump Twitter account at… https://t.co/IgO4zpH2cL	-122.418000000000006	37.7749999999999986	Eugene, OR	\N	\N
831328699010121728	785474108356173824	RT @2ALAW: Let's Make This Go Viral 🌏\n\nRetweet If You Stand With Ivanka Trump!! \n\n#Trump\n@IvankaTrump 🇺🇸 https://t.co/8wgbeeb95S	43.3738710000000012	-76.152552	Hooterville New York	189	\N
829459581281660928	18540388	Dina Cehand protests U.S. President Donald Trump's executive order imposing a temporary… https://t.co/KuUqOgGZof	-122.411944439999999	37.7791666700000022	37.819284,-122.246917	\N	\N
829241515427889153	17904317	Refugees in Trump out #Protest #NoBanNoWall  #solidarity #diversity #empathy #EndOligarchy… https://t.co/g1LNhHQgux	-122.419167000000002	37.7791670000000011	San Francisco, CA 	\N	\N
829173455350292481	17904317	Hey Trump Chaos isn't normal! #Protest #NoBanNoWall #✊ #solidarity #diversity #empathy… https://t.co/Jrajqw83Ez	-122.419167000000002	37.7791670000000011	San Francisco, CA 	\N	\N
829167808386838528	17904317	Love Trump's Boarder #CounterProtest #Trump2017 #trump2016 #TrumpVoter… https://t.co/gmUabqrUmA	-122.419167000000002	37.7791670000000011	San Francisco, CA 	\N	\N
829093515133075457	2255362627	Thousands in front of city hall protest Trump's travel ban from seven Muslim countries.… https://t.co/VyPmxugidl	-122.417829999999995	37.7802450000000007	Marin County, California	\N	\N
829092346146885633	17934129	well deserved. some of the best coverage on the Trump regime I’ve seen https://t.co/BsTrawQ3id	-122.419420000000002	37.7749299999999977		1	\N
829051239690289152	4493297413	Pussies Against Trump! 😼#ibitegrabbers #youcantgrabthis #FDT #latepost #nobannowall… https://t.co/oJBnVFajFj	-122.417829999999995	37.7802450000000007	Hayward, CA	\N	\N
831328698888433664	33629859	RT @MicahZenko: The Trump WH daily security practices would get employees fired from any Fortune 100 company I've studied. https://t.co/ihj…	37.1773363000000003	-3.59855709999999984	Granada, Spain	190	\N
828716607337857024	17904317	No Ban No Wall No Hate No Trump \n#Protest #NoBanNoWall #✊ #solidarity #diversity #empathy… https://t.co/YumQJwFryj	-122.419167000000002	37.7791670000000011	San Francisco, CA 	\N	\N
828502921197256705	33142966	Central Valley Man, Daughter Arrive in California Following Block on Trump’s Travel Ban https://t.co/OanNBRGYIh	-122.419415999999998	37.7749290000000002	Sacramento, CA	\N	\N
828453493589540864	194238865	Signed petition prop signed by audience members to ban #trump during my performance at the… https://t.co/yCwxC1HdUc	-122.418000000000006	37.7749999999999986	San Francisco	\N	\N
831328698490056705	495852051	RT @JuddLegum: 1. This story I published this morning is the most important thing I've written in awhile https://t.co/SKF9u4Pcr5	40.7127837000000028	-74.0059413000000035	NY 	191	\N
828440904574828544	17904317	Resist Trump's executive hate crimes  \n#Protestsign #NoBanNoWall #resistance #DumpTrump… https://t.co/UTs3xgvVvr	-122.417829999999995	37.7802450000000007	San Francisco, CA 	\N	\N
831328697831534592	635708971	RT @businessinsider: Trump aides briefed him on North Korea's missile test in front of paying Mar-A-Lago members https://t.co/BVXx21HzVW ht…	0	0	Harlem Shogunate	0	\N
831328697714044928	1449400993	RT @AltStateDpt: Not acceptable. If you attacked Clinton's emails &amp; now defend Trump, please admit you're blindly defending him without cri…	47.2528768000000028	-122.444290600000002	Tacoma, WA	192	\N
831328697097584642	2450613956	RT @AC360: Refugees flee U.S. seeking asylum in Canada due to #Trump presidency, via  @sarasidnerCNN https://t.co/MpQ2hvYrGc https://t.co/w…	48.6901541000000009	10.9208893000000007	in the rain 	193	\N
828306079465488385	17904317	I am a gold star mother resisting the Trump agenda #Protestsign #NoBanNoWall #resistance… https://t.co/fAEADQe9Bs	-122.419167000000002	37.7791670000000011	San Francisco, CA 	\N	\N
828298610920062976	2255362627	Muslims marched to an SF rally to protest Trump's immigration ban. #protest  #protesters #rally… https://t.co/M5xQAkKYAV	-122.417829999999995	37.7802450000000007	Marin County, California	\N	\N
831328697063858177	2357539088	RT @alwaystheself: You realize this means that on average, 1 out of every 2 white individuals you encounter is a Trump supporter. \n\nONE OUT…	44.0520690999999971	-123.086753599999994	Eugene, Oregon	194	\N
828277040285618178	17904317	Walls don't unite people! Trump free zone #Protestsign #NoBanNoWall #resistance… https://t.co/kO768vllMi	-122.419167000000002	37.7791670000000011	San Francisco, CA 	\N	\N
828169809791741952	17904317	The only wall I'll pay for is a prison wall for Trump! #Protestsign #NoBanNoWall #resistance… https://t.co/uyD9aJmsEh	-122.419167000000002	37.7791670000000011	San Francisco, CA 	\N	\N
828120351330725888	17904317	Postcards to Trump #postcards #Postcardstotrump #Protestsign #NoBanNoWall #resistance… https://t.co/TYej7XQ8AM	-122.417829999999995	37.7802450000000007	San Francisco, CA 	\N	\N
828088095845318657	17904317	Baby Trump &amp; Papa Putin #notrump #NoBanNoWall #resistance #EndCapitalism #PoliticalButton… https://t.co/qhQz2UgQfC	-122.413498000000004	37.7798609999999968	San Francisco, CA 	\N	\N
828078385230393345	17904317	Trump &amp; Co. are evil! #notrump #NoBanNoWall #resistance #EndCapitalism… https://t.co/kw4ZuyjMxK	-122.417829999999995	37.7802450000000007	San Francisco, CA 	\N	\N
828062039780294657	17904317	Trump make America great again leave the White House #notrump #NoBanNoWall #resistance… https://t.co/ZtRVAbx3gd	-122.417829999999995	37.7802450000000007	San Francisco, CA 	\N	\N
831328697001005056	922017799	America’s Biggest Creditors Dump Treasuries in Warning to Trump https://t.co/5cJF02uaRy via @markets #economy Seems trust in US is tanking📉🤔	36.7782610000000005	-119.417932399999998	California	61	\N
828061532588216320	17904317	Resist Trump! Socialist alternative #notrump #NoBanNoWall #resistance #EndCapitalism… https://t.co/9RiA19n1H2	-122.417829999999995	37.7802450000000007	San Francisco, CA 	\N	\N
828057368156106757	17904317	DUMP TRUMP #NoBanNoWall #resistance #makedonalddrumpfagain… https://t.co/lGY2DOAXGB	-122.417829999999995	37.7802450000000007	San Francisco, CA 	\N	\N
828049708148862976	46016762	I guess we know what Trump and Putin talked about now. https://t.co/473cL436Bp	-122.42595618	37.7698350100000013	San Francisco, CA	\N	\N
828020613927280640	1084178412	Protest TRUMP\n🇺🇸🇺🇸🇺🇸🇺🇸🇺🇸🇺🇸🇺🇸🇺🇸\n#impeachTRUMP #resistance #rally #protest #NOban #nowall @ Civic… https://t.co/reN7dlqrmp	-122.417829999999995	37.7802450000000007	San Francisco, CA	\N	\N
829475094212730880	29283	#NoDAPL protest at San Francisco Federal Bldg continues til 6 pm #Trump #StandingRock #DakotaAccessPipeline… https://t.co/jRH5sKNZBW	37.7749294999999989	-122.419415499999999	San Francisco	37	\N
828826243965427716	24445207	Project Include wins #Crunchies Include Award, blasts tech co's working w/ Trump administration, says diversity is… https://t.co/suKonIERli	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
828040711660462080	39310251	SF sends a message to President Trump in a peaceful demonstration at Civic Center Plaza #NoBanNoWall https://t.co/5ysUBnyySU	37.7749294999999989	-122.419415499999999	San Francisco	37	\N
828038088806920192	46016762	"What'd you do to resist Trump on Saturday?"\n"Oh... uh... lotsa stuff." https://t.co/SD8JGEn5Ij	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
827973383086182400	46016762	Interesting take, but a well-functioning bureaucracy executing Trump's agenda would be the death knell of the Repub… https://t.co/8Tjrje265j	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
831328696975949824	701915942436077568	@TrumpPence_86 @datrumpnation1 Most Trump supporters have no problem with decent, law abiding immigrants.	37.9642528999999982	-91.8318333999999936	Missouri, USA	195	\N
834233727177916416	401670747	RT @TimOBrien: And thank YOU, American taxpayers, for helping fund the Trumps' travel so this new venture could launch--while POTUS stays c…	51.5073508999999987	-0.127758299999999991	London, UK	87	\N
834233727001718784	720357938703896577	RT @Lawrence: One of the conservative anti-Trump voices silenced by @FoxNews joins @TheLastWord tonight 10pm.	32.1656221000000002	-82.9000750999999951	Georgia, USA	304	\N
834233726938800128	245897081	RT @IvoHDaalder: When Russian FM Lavrov speaks of a "post-Western order" he means "post-American." Trump Administration, please take notice.	37.7272727000000003	-89.2167500999999987	Carbondale, Ill.	305	\N
834233726867480576	482070636	RT @molly_knight: Alex Jones believes the Newtown massacre was fake, and has encouraged harassment of victims' families. Congrats to Trump…	46.7295530000000028	-94.6858998000000014	Minnesota 	306	\N
834233726691373056	832239649296936960	RT @KottiPillar: Two Russian officials have admitted to colluding with Donald Trump campaign https://t.co/AiZ234fCTT via @PalmerReport	44.3148442999999972	-85.602364300000005	Michigan, USA	83	\N
829819402635849729	17113333	RT @lenagroeger: Why am I not surprised. \n\nhttps://t.co/XC3tGWpZVn https://t.co/nAhQNfgw2I	-122.419420000000002	37.7749299999999977		1	\N
834233725940490240	755577279183396864	RT @mmpadellan: Tweeps, there's a great page called @Trump_Regrets. Ppl who voted 4 trump &amp; are disappointed. DON'T TAUNT THEM. Reach out.…	37.7609082000000029	-122.435004300000003	Castro, San Francisco	307	\N
829819401595543552	2210067337	RT @SenSanders: Today’s news that Trump denounced an historic U.S.-Russia arms treaty in a call with Putin is extremely troubling. https://…	-122.419420000000002	37.7749299999999977		1	\N
829819400588926976	1537715586	RT @sdonnan: This gets right to the point... https://t.co/V0nhdtJBe5	-122.419420000000002	37.7749299999999977		1	\N
829819400379367425	187351126	RT @2ALAW: Islam Chants Death To America\n\nGeneral Mattis..Hold My Beer🍺\n\n#Trump 🇺🇸 https://t.co/jz8bz6auPA	-122.419420000000002	37.7749299999999977		1	\N
834233725609267200	39741214	RT @Staciopath: Lara Trump is Jewish. Vanessa Trump is Jewish. Ivanka &amp; Jared are Jewish. If the Trumps are anti semitic, they suck at it.…	36.3353948999999972	-92.3813459999999935	Mountain Home, Arkansas	308	\N
834233725500215301	2927039072	RT @activist360: Bravo Max Karlsson! Meet the 22-yr-old fighting lying lunatic bigot Trump &amp; his terror bullsh*t about Sweden https://t.co/…	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834233725386899457	3907110138	RT @JohnTrumpFanKJV: 202-224-2235\nLet's call John McCain and let him know that it is Wrong to criticize President Trump on Foreign Soil.	39.7684029999999993	-86.1580680000000001	Indianapolis, IN	309	\N
834233725105889281	44416770	RT @RawStory: Maryland teachers forced to remove iconic pro-diversity posters for being ‘anti-Trump’ https://t.co/7xlsVsTSMs https://t.co/U…	49.2827290999999974	-123.120737500000004	Vancouver, BC	310	\N
834235062786936837	807039567832449024	RT @SheriffClarke: Under Obama, Holder &amp; Lynch, cops were criminals, crooks were victims. Rule of law will prevail with President Trump htt…	27.9505750000000006	-82.4571775999999943	Tampa, FL	101	\N
834236046439092224	712841640	RT @dwaynecobb: ⚡️ “Anne Frank Center condemns GOP(R)Trump; Sean Spicer responds”\n\nhttps://t.co/ThYk8gPCEw	49.7016338999999974	-123.155812100000006	Squamish BC Canada	317	\N
829820746524454912	213892275	RT @bi_politics: One of the largest middlemen in pharma shared a video showing why it should remain secretive https://t.co/Um9XsGVswZ https…	-122.419420000000002	37.7749299999999977		1	\N
834242846815293440	38868552	RT @DavidYankovich: #CongressCanRequest Trump's taxes.\n\n@BillPascrell is leading this charge.\n\nRT if you believe Trump's taxes should be re…	40.0583237999999966	-74.4056611999999973	NJ	324	\N
829820745391992832	1350989725	RT @FoxNews: .@POTUS to Meet With Canadian PM @JustinTrudeau on Monday\nhttps://t.co/IByKYW5JCx	-122.419420000000002	37.7749299999999977		1	\N
827597809721307137	14893345	B\nE\nN\nG\nH\nA\nZ\nIt was never actually about Benghazi\n\nhttps://t.co/adPeLqrHB2	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
827565033471176704	19429478	Hey Mormons, soon your tithing $ will be going to support Trump and pro-Trump Senators &amp; more Prop 8-type hate. https://t.co/94orBlypwi	37.7749294999999989	-122.419415499999999	San Francisco	37	\N
827559954701619200	46016762	Imagine the first time Trump has to address a mass shooting. Then imagine the NRA talking about what a problem ment… https://t.co/h8EUFTZJpN	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
827553223099588609	46016762	If Trump makes the "every word interspersed by a 👏" tweet style illegal... well it won't make up for everything, but it'll go a long way.	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
829819402795282432	198614936	Can someone do a #Trump and #Buffett stuck in elevator sketch please and teach Rich doesn't have to be Mean.@sarahschneider @TBTL @MMFlint	43.6532259999999965	-79.3831842999999964	Toronto, Ontario	39	\N
829819401876684801	4847825488	@ChrisCuomo @jaketapper  don't mind calling President Trump a liar when he isn't! https://t.co/NHiew1X25a	36.8529263	-75.9779850000000039	Virginia Beach, VA	40	\N
829819401423712258	3290217551	RT @AIIAmericanGirI: Starbucks offers to pay legal fees for employees affected by Trump's temporary travel order @BIZPACReview\nhttps://t.co…	53.1423672000000025	-7.6920535999999986	Ireland	42	\N
829819401167704064	88978035	RT @CostantiniWW1: Spicer says Kellyanne Conway "has been counseled" for telling Americans via Fox News to buy Ivanka Trump clothing. Won't…	37.3382081999999969	-121.886328599999999	San Jose, CA	43	\N
829819400945414144	2408219798	RT @thehill: Trump’s immigration ban cost business travel industry $185M: report https://t.co/G37J5qEFQ5 https://t.co/zakCf0Rsox	0	0	Wherever My Feet Land	0	\N
829819400681304066	805636147649138689	RT @JoeTrippi: The Mysterious Disappearance of the Biggest Scandal in Washington https://t.co/QVU4V267w1 via @motherjones	37.0902400000000014	-95.7128909999999991	United States	44	\N
829819400647737346	23490211	RT @BeSeriousUSA: The Mysterious Disappearance of the Biggest Scandal in Washington | What happened to the Trump-Russia story?\n#resist http…	41.3750489999999971	-81.9081936999999982	Olmsted Falls, Ohio	45	\N
829819400609992709	388655565	RT @MarkSimoneNY: Sen. Blumenthal was in Vietnam, Elizabeth Warren is an Indian, Hillary only used one device, and they think Trump is a li…	43.6187102000000024	-116.214606799999999	Boise, ID	46	\N
829820747149225984	15462317	RT @Quinnae_Moon: Calling the free speech brigade: https://t.co/q3tmCYU3so	34.9592083000000002	-116.419388999999995	Southern California	50	\N
829820745320656896	163135622	RT @hansilowang: BREAKING: #9thCircuit says there WILL be an order on Trump's travel ban case before COB today (Thu). Courts usually close…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
829820745165500416	445014480	RT @PattyMurray: President Trump has selected a nominee for Secretary @HHSGov who would take women’s health and rights in the wrong directi…	39.9611755000000031	-82.9987942000000061	Columbus, Ohio	55	\N
829820745014403072	28577889	RT @KatyTurNBC: "This is president so outrageous, so ridiculous...its going to catch up with him" - Rep Maxine Waters https://t.co/vBmnQFrT…	37.0902400000000014	-95.7128909999999991	USA	56	\N
829820744943099905	2697441728	RT @Lyn_Samuels: Former FBI Agent: We Must Get to the Truth on Russia and Trump https://t.co/Gu2V4AfQEJ	0	0	Unmitigated Shithole ofAmerica	0	\N
831329859406327810	825115978723893248	RT @DafnaLinzer: A must read. Warning came from Sally Yates who Trump fired less than two weeks into the job https://t.co/BZdxM2aFfj	0	0	Your grocer's produce section	0	\N
831329858319966210	49091342	RT @jenilynn1001: 😂😂😂😂Liberal MSM mad because Trump called on the Daily Caller. 8 years of this please!! \n👏🏻👏🏻👏🏻👏🏻👏🏻👏🏻👏🏻👏🏻👏🏻👏🏻	44.9776239999999987	-93.2730382999999961	South Minneapolis baby!!!	211	\N
831329858273869824	583981596	RT @TVietor08: The whole fucking campaign was about Hillary's emails and now Trump's team is violating the Presidential Records Act by usin…	39.5500506999999999	-105.782067400000003	Colorado, USA	212	\N
831329858173095938	170957286	RT @matthewamiller: Flynn is going to be fired soon and Trump is going to try and move on, but it's clearer than ever there needs to be an…	39.3209800999999999	-111.093731099999999	 Utah 	213	\N
831329857787269120	839402840	NY Times NEWTop story: From Trump’s Mar-a-Lago to Facebook, a National Security… https://t.co/7UcDdIk3Lw, see more https://t.co/PWlm2gmhoG	40.7127837000000028	-74.0059413000000035	New York	214	\N
829820742686486529	937639507	RT @NewssTrump: BREAKING: President Trump Just Signed An Executive Order That Prevents Illegals From Using Welfare. Do You Support… https:/…	-122.419420000000002	37.7749299999999977		1	\N
831329857011335169	53061958	@IvankaTrump Yes, Trump and the Anti-Trump!!	40.7830603000000025	-73.9712487999999979	MANHATTAN	216	\N
831329856663199744	3983898252	RT @TVietor08: The whole fucking campaign was about Hillary's emails and now Trump's team is violating the Presidential Records Act by usin…	42.0307811999999998	-93.6319131000000056	Ames, IA	217	\N
834242846366515200	801151532959993856	TRUMP DAILY: Ivanka Trump through the years #Trump https://t.co/ypUmseOwTb	35.2270869000000033	-80.8431266999999991	Charlotte, NC	325	\N
829820740878815232	1354501574	RT @thehill: Government ethics office website down after Conway promotes Ivanka Trump clothing line https://t.co/gK4Yl6gbeB https://t.co/ZY…	-122.419420000000002	37.7749299999999977		1	\N
829820740719489024	3719341463	RT @SenSanders: Congress must not allow President Trump to unleash a dangerous and costly nuclear arms race.	-122.419420000000002	37.7749299999999977		1	\N
829820739679354880	3229591018	RT @BraddJaffy: Elijah Cummings asks Jason Chaffetz to refer Kellyanne Conway for possible disciplinary action after TV plug of Ivanka Trum…	-122.419420000000002	37.7749299999999977		1	\N
829820739394093057	782763528906219520	RT @DavidCornDC: Why has the Russia-Trump story gone dark? Why is the DC press corps not going wild about this? https://t.co/ndJQESbXKd	-122.419420000000002	37.7749299999999977		1	\N
829820739159076865	815655471570821120	RT @NBCNightlyNews: NEW: Rep. Cummings asks for Oversight Cmte. to refer Kellyanne Conway for potential discipline for promotion of Ivanka…	-122.419420000000002	37.7749299999999977		1	\N
829820738261639169	746503836471197696	RT @SymoneDSanders: Folks keep asking what Trump signed today. 1) We don't really know, but 2) we should be concerned. Actually concerned i…	-122.419420000000002	37.7749299999999977		1	\N
829820737636663296	499319815	RT @JaydenMichele: I think Trump and Kellyanne be fuckin.	-122.419420000000002	37.7749299999999977		1	\N
829820737183707136	713149544662347776	RT @mspoint1106: BREAKING 2/9/17: The 9th Cir has reached a decision on trump's travel ban &amp; will announce it before close of business toda…	-122.419420000000002	37.7749299999999977		1	\N
829820736948858880	154433522	RT @owillis: wont happen but if the gop is considering dumping trump for pence, ford only lost 1976 by 57 electoral votes	-122.419420000000002	37.7749299999999977		1	\N
829820736156078080	757623424583737344	RT @Phil_Lewis_: He actually said: 'If there is a silver lining in this shit, it's that people of all walks of life are uniting together (a…	-122.419420000000002	37.7749299999999977		1	\N
829820735443103744	93661140	RT @MarkSimoneNY: Sen. Blumenthal was in Vietnam, Elizabeth Warren is an Indian, Hillary only used one device, and they think Trump is a li…	-122.419420000000002	37.7749299999999977		1	\N
829820735262773249	885873277	RT @indivisible410: Protests at Johns Hopkins today, and in universities around the country, against Trump's immigration ban #NoBanNoWall #…	-122.419420000000002	37.7749299999999977		1	\N
829820741835223040	734028559	RT @SenSanders: Today’s news that Trump denounced an historic U.S.-Russia arms treaty in a call with Putin is extremely troubling. https://…	32.7356869999999986	-97.1080656000000033	Arlington, TX	65	\N
829820741826834432	16877196	RT @JoyAnnReid: I think this is what my Jewish friends call "chutzpah." Trump dodged the draft. McCain nearly gave his life as a POW. They'…	43.4113603999999995	-106.2800242	Midwest, USA	66	\N
829820741793280000	1101997326	Former spy chief calls Trump's travel ban 'recruiting tool for extremists' https://t.co/PmnMzSnDim	39.027282900000003	-84.5849438000000049	Crestview Hills, KY	67	\N
829820741784915968	807426616578179072	TRACKING SYSTEMS: Trump Surprises Muslim Immigrants With Special ‘Trick’ Up His Sleeve https://t.co/SJuzcGHrsl	40.0583237999999966	-74.4056611999999973	New Jersey, USA	68	\N
829820740597858304	139525580	RT @jabdi: Muslim U.S. Olympian Ibtihaj Muhammad says she was held by U.S. Customs https://t.co/lIYFtYapGJ	25.1185420000000015	55.2000630000000001	New York I Dubai 	69	\N
829820740258107392	1123639140	RT @thehill: Trump’s immigration ban cost business travel industry $185M: report https://t.co/MK4c9cVCX1 https://t.co/ZMEqFVkJf5	42.2917069000000012	-85.5872286000000031	Kalamazoo, MI	70	\N
829820740216107008	3018187163	RT @PostRoz: Chaffetz/Cummings say Trump has "inherent conflict" in disciplining Conway over promotion of his daughter's business, ask OGE…	36.7782610000000005	-119.417932399999998	California, USA	71	\N
829820739545034752	4306732883	Trump slams Blumenthal, says 'misrepresented' Gorsuch comments https://t.co/lt4rtcqQ35 https://t.co/t83TAwFMu2	37.0902400000000014	-95.7128909999999991	United States	44	\N
829820739339558912	1871348034	RT @SenSanders: Today’s news that Trump denounced an historic U.S.-Russia arms treaty in a call with Putin is extremely troubling. https://…	41.3329866999999993	21.5393308999999995	NoVa	72	\N
829820739259924480	16377959	RT @jayrosen_nyu: Wow. https://t.co/V4Zk6itiCP Two of the journalists who worked on this were with Knight-Ridder when it did the most skept…	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
829820728606412800	807041299354361860	TRACKING SYSTEMS: Trump Surprises Muslim Immigrants With Special ‘Trick’ Up His Sleeve https://t.co/EhHnZqne0s	42.8864467999999874	-78.8783688999999981	Buffalo, NY	62	\N
829820739163455495	16456004	WASHINGTON (AP) -- White House says Trump `absolutely' continues to support adviser Conway after she promoted Ivanka Trump brand #NBC15	43.0730517000000006	-89.4012302000000005	Madison, WI	74	\N
829820739096346625	101532348	RT @thinkprogress: It was long, painstaking work. But this is what accountability looks like. https://t.co/lbsPc6snOJ https://t.co/7Cm0IlwB…	38.990665700000001	-77.0260880000000014	Silver Spring, MD	75	\N
829820736558620672	40988391	RT @FoxBusiness: .@Reince Priebus: Trump's goal is to be the 'President of the American worker.' https://t.co/p4wnLrGjGI	0	0	Arizona, Trump 2016	0	\N
829820735392772096	2531122806	@cnnbrk This is the new world we live N. Illegals need 2 get there papers N order. PERIOD. STOP. Free pass N2 the US is over. Thks Trump.	40.844781900000001	-73.864826800000003	Bronx, NY	76	\N
829820735312928770	942422990	@8shot_ @JasperAvi Oh, look a newly hatched Trump egg. I do wonder how he pays you all.	35.223140800000003	-93.1579531999999944	Dardanelle Arkansas	77	\N
829820735292055556	92538730	Melania Trump's new lawsuit and attempt to cash in on her mega-celebrity,  Whodathunkit? \nhttps://t.co/t5p3nn6bm2 via @TheEconomist	30.2671530000000004	-97.743060799999995	Austin, Texas	78	\N
831329856533065729	105183788	RT @IMPL0RABLE: #TheResistance\n\nRumor has it the Trump admin really doesn't like SNL's parodies of Sessions &amp; Spicer by women. So do not re…	36.1699411999999967	-115.139829599999999	Las Vegas, NV	218	\N
831329856449286144	1904550620	@TraceySRogers1 @TuckerCarlson @Chadwick_Moore thanks to the support from Obama, Clinton Network &amp; Soros - behind the scenes attack on Trump	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
829820734381846529	2330654508	RT @NBCNightlyNews: NEW: Rep. Cummings asks for Oversight Cmte. to refer Kellyanne Conway for potential discipline for promotion of Ivanka…	-122.419420000000002	37.7749299999999977		1	\N
829820734159478784	807854219780726785	RT @thehill: Meghan McCain fires back at Trump: "How dare anyone question the honor of my father" https://t.co/xw7iM4JhAq https://t.co/wVoo…	-122.419420000000002	37.7749299999999977		1	\N
831329856436703233	33347217	RT @warkin: I'm hearing from White House sources that #MICHAELFLYNN is secure with Trump, aided today by @NancyPelosi demanding action.	30.2671530000000004	-97.743060799999995	Austin	219	\N
831329856415793152	1163310757	@NBCNews take Trump and Pence with you.	42.4072107000000003	-71.3824374000000006	Massachusetts, USA	64	\N
831329856382259201	807095	Michael Flynn is said to have misled senior officials about his conversation with a Russian diplomat\nhttps://t.co/GTxIxqEUvr	40.7127837000000028	-74.0059413000000035	New York City	145	\N
831329856247963648	720773694755311616	RT @MeLoseBrainUhOh: Trump is playing a very delicate game of chess where he throws the chessboard across the room &amp; digs into a bucket of…	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
829820732561641472	315207449	RT @The_Last_NewsPa: Liberals Compared Trump To Hitler, So a Survivor From Nazi Germany RESPONDED… https://t.co/JWXPgbXJxD https://t.co/OTp…	-122.419420000000002	37.7749299999999977		1	\N
831329855967002625	14861004	Justice warned Trump team about Flynn contacts: https://t.co/tmZmR27WEI https://t.co/4IC4liiHtt	39.0997265000000027	-94.5785666999999961	Kansas City, Mo.	220	\N
831329855853572096	703785057836662785	RT @ananavarro: Hour ago, Conway said Flynn has Trump's trust. Minutes ago, Spicer said, not so much. WH has political menopause. Cold 1 mi…	39.5500506999999999	-105.782067400000003	Colorado, USA	212	\N
831329855534927872	364563540	RT @democracynow: Trump Adviser Stephen Miller Repeats Trump Lie About Voter Fraud in 2016 Election https://t.co/7ED89lG66p https://t.co/Vs…	34.5199402000000006	-105.870090099999999	New Mexico	221	\N
831329855497175040	151909909	@TVietor08 @chrislhayes I'm SOOO surprised. I'm sure the Trump'ers don't really understand that though, Murica 🍺🍔🍟	49.2144389999999987	-2.13125000000000009	Jersey	222	\N
831329855350386689	15181002	RT @ananavarro: Hour ago, Conway said Flynn has Trump's trust. Minutes ago, Spicer said, not so much. WH has political menopause. Cold 1 mi…	39.739235800000003	-104.990251000000001	Denver	223	\N
831329854855532544	864584708	Media attacking Trump over ICE raids? https://t.co/bJ5BwJkKJT https://t.co/sneVOwTdNa	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
829820730741288961	824703026833354752	RT @BrittPettibone: Little lives matter. Thank you President Trump. \n#NationalPizzaDay https://t.co/PuSbdIykdg	-122.419420000000002	37.7749299999999977		1	\N
829820730674081792	2950465257	RT @Phil_Lewis_: He actually said: 'If there is a silver lining in this shit, it's that people of all walks of life are uniting together (a…	-122.419420000000002	37.7749299999999977		1	\N
831329854775754752	3404163009	RT @epicciuto: It hasn't been just a few days Trump has dragged his heels on firing Flynn. He fired the messenger. https://t.co/sbQy76vScP	42.2625931999999978	-71.8022933999999964	Worcester, MA	224	\N
831329853987291136	305301404	RT @BernieSanders: Our job: Break up the major financial institutions, not appoint more Wall Street executives to the administration as Tru…	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
831329853634863104	6842112	Justice warned Trump team about Flynn contacts https://t.co/xs5RluuZo3 https://t.co/4tF75mVATO	35.0853335999999985	-106.605553400000005	Albuquerque, NM, USA	226	\N
829820729541611520	14691092	RT @mattzap: BREAKING: Appeals court spokesman says order on Trump's immigration ban "will be filed in this case before the close of busine…	-122.419420000000002	37.7749299999999977		1	\N
831329853605552128	3031635662	Top story: From Trump’s Mar-a-Lago to Facebook, a National Security Crisis in t… https://t.co/6ptsrPgz4V, see more https://t.co/JSVa7nhkBK	34.4187082999999987	-83.9057391999999993	Murrayville, Georgia	227	\N
831329852972269568	803672700	RT @dmcrane: Congress Must Act As Intelligence Experts Warn Russia Is Listening In Trump's Situation Room via @politicususa https://t.co/NJ…	37.0902400000000014	-95.7128909999999991	USA	56	\N
831329852674314241	130595733	RT @sadmexi: Me: "I hate trumpets."\nDonald Trump: "I hate trumpets."\nMe: https://t.co/ugADLYIVQv	37.8271784000000011	-122.291307799999998	bay area	206	\N
831329852322099200	77537884	RT @AC360: .@jorgeramosnews : "Donald Trump is ripping families apart" https://t.co/uowk7Qnl0D https://t.co/2RQ15XrIMU	40.7127837000000028	-74.0059413000000035	new york	228	\N
831329852297007104	88199127	RT @TEN_GOP: This woman came here legally and she supports Trump on immigration. Please, spread her word. \n#DayWithoutLatinos https://t.co/…	37.0902400000000014	-95.7128909999999991	United States	44	\N
829820727469617153	64813601	RT @SandraTXAS: If only regressive liberals cared as much about homeless veterans as refugees and illegal immigrants\n\n#immigration\n#MAGA\n#T…	-122.419420000000002	37.7749299999999977		1	\N
831329852154322944	1928468941	RT @fox5dc: #BREAKING: (AP) -- Federal judge issues preliminary injunction barring Trump travel ban from being implemented in Virginia #5at…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
831329852057800704	60648909	RT @TVietor08: The whole fucking campaign was about Hillary's emails and now Trump's team is violating the Presidential Records Act by usin…	34.0407129999999967	-118.246769299999997	DTLA	229	\N
829820725900910592	1636396116	RT @oneprotestinc: Trump’s Pick For Interior Is No Friend Of Endangered Species. https://t.co/tmCMjHLjV2	-122.419420000000002	37.7749299999999977		1	\N
829820725586513921	26664138	RT @hansilowang: BREAKING: #9thCircuit says there WILL be an order on Trump's travel ban case before COB today (Thu). Courts usually close…	-122.419420000000002	37.7749299999999977		1	\N
831329851734888449	32327130	RT @gaywonk: Kellyanne Conway is a master of dodging basic questions about Trump. News networks should stop booking her. https://t.co/x0E1f…	41.0534302000000011	-73.5387340999999992	Stamford CT	230	\N
831329851667775488	721820289147928578	@Joy_Villa @andresoriano congrats beautiful lady you wear the dress well! 🙌🇺🇸🙌	37.0902400000000014	-95.7128909999999991	United States	44	\N
831329851512549376	1414548181	RT @vvega1008: My beef for tonight: Why is Trump being treated with kid gloves? Are you not an adult? You at 70, right? GROW UP, or GTFO.	37.0902400000000014	-95.7128909999999991	U.S.A.	231	\N
829820724462383105	1465450662	RT @ABCWorldNews: .@PressSec Sean Spicer says Pres. Trump has "no regrets" about the comments he's made about federal judges. https://t.co/…	-122.419420000000002	37.7749299999999977		1	\N
829820723988271104	961306278	RT @politico: Democrats call for President Trump's Labor pick Andrew Puzder to withdraw https://t.co/9siSrRHPnS https://t.co/4vrJbFy0rV	-122.419420000000002	37.7749299999999977		1	\N
829820723845804035	111593173	RT @ChrisJZullo: Wonder if Kellyanne Conway realizes when she says "Go Buy Ivanka's Stuff" that Trump supporters can't afford it, hence the…	-122.419420000000002	37.7749299999999977		1	\N
831329851227459584	393601610	RT @johnnydollar01: Brian Williams @KatyTurNBC @wolfblitzer Attack Daily Caller Reporter For Not Asking Trump The Question They Wanted\nhttp…	0	0	Obamaville	0	\N
829820723766165504	613667224	RT @Conservatexian: News post: "Your guide to shoddy reporting on the Trump administration since his inauguration" https://t.co/tmWcuIjd8z	-122.419420000000002	37.7749299999999977		1	\N
831329850833174529	135166251	This dude on @BachelorABC the kind of asshole that voted Trump, then gets angry at losing his healthcare.	39.9611755000000031	-82.9987942000000061	Columbus, OH, USA	232	\N
829820723484979201	174559667	RT @SInow: Five Patriots say they won't visit President Trump at the White House. Here’s why: https://t.co/I5R8wjk1dg https://t.co/jfBLSOif…	-122.419420000000002	37.7749299999999977		1	\N
831329850740899840	16287595	RT @xor: Journalists, please don't follow Trump into calling it "the Winter White House." It's a business he still runs.	39.9525839000000005	-75.1652215000000012	Philadelphia, PA	233	\N
831329850657009665	759218015019859973	RT @samsteinhp: The guy who literally wrote the book on NH election fraud thinks Trump's claims of NH election fraud are bonkers https://t.…	39.0457548999999986	-76.6412712000000056	Maryland, USA	234	\N
831329850594119680	276620353	RT @JoshuaMellin: 🌝 #Chicago protesters moon Trump Tower 💩#DumpTrump \n🍑#rumpsagainsttrump @realDonaldTrump @TrumpChicago https://t.co/wlbWv…	37.2709704000000031	-79.9414265999999998	Roanoke, VA	235	\N
831329849734230016	861595705	RT @AC360: .@jorgeramosnews : "Donald Trump is ripping families apart" https://t.co/uowk7Qnl0D https://t.co/2RQ15XrIMU	40.7127837000000028	-74.0059413000000035	New York , US	236	\N
829820721912090624	28674156	RT @DailyCaller: Executive Order Signed By Trump Will Take Aim At MS-13 https://t.co/qYDLsRlLZJ https://t.co/WnPFNS4nMb	-122.419420000000002	37.7749299999999977		1	\N
831329849604190208	74095133	RT @GDBlackmon: You mean aside from fake tears and incoherent rage?:  Inside Chuck Schumer’s Plan to Take on President Trump https://t.co/2…	40.0994425000000021	-74.9325682999999998	Bensalem Pa.	237	\N
831329849465851904	836845836	RT @JohnJHarwood: President Trump's current job approval in Gallup poll, by race: blacks 11%; Hispanics 19%; whites 53%	42.3314269999999979	-83.0457538	Detroit	238	\N
831329849415450624	50179789	RT @Phil_Lewis_: Get you someone that looks at you the way Ivanka Trump looks at Justin Trudeau https://t.co/sxTAlpi4av	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
831329848866066439	21833728	House Democrats Demand Investigation of Trump's National Security Adviser  https://t.co/XwfBWiKX1c	38.9071922999999984	-77.0368706999999944	Washington DC, USA	240	\N
831329848568197120	17690747	Impeachment now. The President knew the Russians had Flynn by the balls, and denied denied lied.  Impeach Trump now.	43.1240448000000001	-89.3499345000000034	Great Lakes	241	\N
831329848211685376	44758412	RT @steph93065: .@gracels  Its the left that is unhinged (violent riots) while the media and hollywood tell dumb kids Trump is Hitler.	62.411363399999999	-149.072971499999994	West Coast	242	\N
831329848157102080	42718610	RT @MyDaughtersArmy: Notice how Trudeau does the 'alpha shoulder grab' before Trump can do the 'alpha rip his arm off' handshake.\nhttps://t…	36.7782610000000005	-119.417932399999998	California	61	\N
829858464977543168	62265109	RT @iowa_trump: To the left: just when did 9th Circuit judges hear security briefings that justify President Trump's temporary immigration…	-122.419420000000002	37.7749299999999977		1	\N
831329848077512707	281698957	RT @thinkprogress: Trump administration invents new story to support claims of massive voter fraud https://t.co/Uy0UTOhIoU https://t.co/ZOn…	42.3875967999999972	-71.0994967999999972	Somerville, MA	178	\N
831329848022888451	3169035834	RT @activist360: Leave it to Führer Trump's dirt dumb bigot base to think the hashtag #DayWithoutLatinos is in reference to a new white sup…	41.6639382999999981	-83.5552119999999974	Toledo, OH	243	\N
831329847779655680	747064245515354112	RT @TVietor08: The whole fucking campaign was about Hillary's emails and now Trump's team is violating the Presidential Records Act by usin…	40.4406247999999877	-79.9958864000000034	Pittsburgh, PA	99	\N
831329847175684096	386502392	Dear white, Christian Trump supporters: How can we talk to each other? https://t.co/LSgKzmUdvg via @HuffPostPol	37.0902400000000014	-95.7128909999999991	USA	56	\N
829858464428068865	97793731	RT @JaySekulow: Appeals Court decision on Pres. #Trump's Executive order is disappointing and puts our nation in grave danger. https://t.co…	-122.419420000000002	37.7749299999999977		1	\N
829858464369410050	4071568993	RT @jonfavs: WINNERS: the rule of law, the judiciary, the separation of powers, the Constitution, American values, democracy. \n\nLOSERS: Tru…	-122.419420000000002	37.7749299999999977		1	\N
831329845347020804	792803253406822400	RT @JarrettStepman: Spot on analysis from @SebGorka at @Heritage: War on ISIS About Ideology https://t.co/MYzW5BaC1e via @SiegelScribe @Dai…	40.7263542000000029	-73.9865532999999971	Upstate NY	248	\N
829858463979360259	19244932	RT @AltStateDpt: Pulitzer Prize winning @PolitiFact shows the full scope of Trump's lies. Only 4% of Trump statements rate TRUE. https://t.…	-122.419420000000002	37.7749299999999977		1	\N
831329844998856704	14689197	Christie frustrated at 'unforced errors' by Trump staff https://t.co/G2I6FYr1cM	39.9525839000000005	-75.1652215000000012	Philadelphia, PA, US	249	\N
829858463958331398	77316818	RT @TheMichaelRock: Trump: the travel ban was constitutional. \n\nJudges: yeah, but we hate you.	-122.419420000000002	37.7749299999999977		1	\N
831329844914843648	1906936178	@YvetteFelarca  Trump is out president, did you miss that	34.9592083000000002	-116.419388999999995	SoCal	250	\N
831329844738740224	36555827	And Republicans have credibility with the clown like Trump in office? Forcing @seanspicer to lie about the size of… https://t.co/zrRreFESRo	34.0522342000000009	-118.243684900000005	Los Angeles, CA.	251	\N
831329844679958528	826723595581808640	RT @TVietor08: The whole fucking campaign was about Hillary's emails and now Trump's team is violating the Presidential Records Act by usin…	51.2537749999999974	-85.3232138999999989	Ontario, Canada	252	\N
831329844096962560	797449011724570625	RT @thehill: Federal judge says court proceedings will continue on Trump’s travel ban https://t.co/RCCxWmDppH https://t.co/d5LX743tH4	0	0	PHILIPPINES@yahoo.COME&VISIT.	0	\N
829858462985240577	617692639	RT @mitchellvii: The Left doesn't care about Terrorism.  They didn't give a damn when 49 gays were massacred in Orlando.  Only Trump cared.	-122.419420000000002	37.7749299999999977		1	\N
831638796693221376	922005800	RT @denormalize: Today Trump removed all open data (9GB) from the White House https://t.co/ELRMxTgdb2 but I grabbed it all Jan 20! Will dis…	40.0149856000000028	-105.270545600000005	Boulder, CO	253	\N
831638796621996033	737841105954164737	RT @realDonaldTrump: 'Remarks by President Trump at Signing of H.J. Resolution 41'\nhttps://t.co/Q3MoCGAc54 https://t.co/yGDDTKm9Br	23.6345010000000002	-102.552784000000003	México	254	\N
831638796504592386	838285555	The Rachel Maddox show  Saw resignation of Flynn. Hard to believe the top administration didn't know especially Trump.	33.6097249999999974	-84.2873661999999939	Ellenwood, Georgia	255	\N
831638795736981505	2550890816	Donald Trump lifts anti-corruption rules in 'gift to the American oil lobby' https://t.co/SImg7qBCAW	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
831638795644723204	29223072	Trump knew Flynn misled officials on Russia calls for 'weeks,' White House says https://t.co/YdoIEkkU5k #impeachtrump #impeachpence	40.7127837000000028	-74.0059413000000035	NYC	60	\N
829858462511271936	360245130	RT @wpjenna: Trump is changing the presidency more than the presidency is changing Trump:\nhttps://t.co/4hYEtO495t with @ktumulty	-122.419420000000002	37.7749299999999977		1	\N
829858462381330432	291709958	RT @BuzzFeed: People turned Trump’s "SEE YOU IN COURT" tweet into a huge meme https://t.co/Br4Ks6nNSJ https://t.co/Q3zLwYYcZ1	-122.419420000000002	37.7749299999999977		1	\N
831638795468419072	4535283420	RT @goldengateblond: Flynn wasn't an outlier. Remember Trump’s staff rewrote the GOP platform to eliminate references to arming Ukraine. ht…	40.1998777000000018	-122.201107500000006	California's Central Valley	256	\N
829858462364413952	705497015594029056	RT @FoxNews: .@Judgenap: Court's Ruling on Immigration Order Is 'Intellectually Dishonest'\nhttps://t.co/DlqVFvwwPS	-122.419420000000002	37.7749299999999977		1	\N
831638795359485952	826916334604779530	@realDonaldTrump Trump and his treasonous Administration continues to fail. Hopefully he will be impeached or resign well before 2018.	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
831638794977714176	4487940026	RT @RealJeremyNolt: Funny to watch the Dems turn on one of their stars, Tulsi Gabbard, for meeting w/ Trump. How long until the media tells…	56.1303660000000022	-106.346771000000004	Canada	257	\N
831638794923286528	536503190	RT @dcexaminer: Gallup poll finds clear majorities of Americans see Trump as strong leader who keeps promises https://t.co/sJIgtGOoav by @e…	37.0902400000000014	-95.7128909999999991	USA	56	\N
829858461773082624	272432907	RT @gretchenwhitmer: Michigan Attorney General Bill Schuette supported President Trump's illegal ban. The judges repudiated not only @POTUS…	-122.419420000000002	37.7749299999999977		1	\N
829858461370376192	705583838328541184	RT @mitchellvii: These Liberal jurists are not interpreting law, they are rewriting law.  The law in the case is abundantly clear - Trump h…	-122.419420000000002	37.7749299999999977		1	\N
829858461030694914	1053684374	RT @CollinRugg: To all the liberals saying Trump is a "loser"\n\n#ThrowbackThursday https://t.co/JAoY6xUsAj	-122.419420000000002	37.7749299999999977		1	\N
829858460971917312	3271379414	RT @zachjgreen: Poor Trump. It's not easy to be a dictator in a democracy.	-122.419420000000002	37.7749299999999977		1	\N
831638794432438272	43108370	Protesters Rally Outside Schumer’s Office to Push For Anti-Trump Town Halls https://t.co/kZCQE0E8Ie https://t.co/Sa6IbSTsvj	39.9525839000000005	-75.1652215000000012	Philadelphia	258	\N
831638794197569536	64112085	RT @Anomaly100: UH OH!: Trump’s Personal And Official Accounts Just Unfollowed Kellyanne Conway (IMAGES) https://t.co/StozkqAhrV #Flynnghaz…	34.0522342000000009	-118.243684900000005	LA	259	\N
829858460393144320	29191107	RT @chelseahandler: Trump says his daughter has been treated ‘so unfairly’ by Nordstrom. Oh, was she detained for 19 hours when she tried t…	-122.419420000000002	37.7749299999999977		1	\N
831638794075987968	788163095889842176	Bill Gates: Global health plans at risk under Trump https://t.co/4LwQRqxb5z https://t.co/z9Dq1neSM5	25.790654	-80.1300454999999943	Miami Beach, FL	260	\N
831638793836908544	86123044	RT @DafnaLinzer: Exclusive: Sources tell NBC News that @vp was only told of DOJ warning about Flynn late on Feb. 9th, 11 days after White H…	33.745851100000003	-117.826166000000001	Tustin, CA	261	\N
831638793102950401	328260787	RT @GottaLaff: Spicer: Trump is "unbelievably decisive." https://t.co/Htn2AdXUwq	46.7295530000000028	-94.6858998000000014	Minnesota, USA	262	\N
831638792968749057	811787183652749313	Exclusive: U.S. arrests Mexican immigrant in Seattle covered by Obama program https://t.co/Ky0UyOQCma	37.4315733999999978	-78.6568941999999964	Virginia, USA	263	\N
829858459784982528	829495306123407360	RT @CoryBooker: I don't believe that, never said it &amp; believe the accusation is usually an attempt to silence or delegitimize a constructiv…	-122.419420000000002	37.7749299999999977		1	\N
831638792792580098	16209662	RT @RawStory: Trump promoted dangerous anti-vaxxer myth while discussing autism with educators https://t.co/MmM58SWhuu https://t.co/KbAxauP…	40.7249193999999974	-73.9968807000000055	Global Citizen of Earth 	264	\N
831638792759033858	3317649485	ProgressiveArmy: RT TheBpDShow: A Profile of The Lies and Propaganda Of Stephen Miller; Trump's Minister of Truth: https://t.co/2iPRH03pN0…	28.2188991999999992	-82.4575937999999979	Land O' Lakes, FL	265	\N
831638792733851648	16181407	Ethics office: White House should investigate Conway for Ivanka Trump plug:Kellyanne Doesn't Know Her Boundaries.  https://t.co/8yvRV7TDV8	37.0902400000000014	-95.7128909999999991	United States	44	\N
829858459378188288	90280824	RT @MakeItPlain: Parents Outraged After #Trump Falsely Claims Their Daughter Was Killed in a Terrorist Attack https://t.co/uYcL2sET0d #poli…	-122.419420000000002	37.7749299999999977		1	\N
831638792591200257	542568755	Bill Gates: Global health plans at risk under Trump https://t.co/H3GAOLNKyz https://t.co/HGfuC8maBJ	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
831638792507371520	240786850	RT @anamariecox: "Trump ran a campaign based on intelligence security" is a bad premise but holy cow this post https://t.co/6h1psYm7a1 http…	35.7647091999999986	-82.2652846000000011	Blue Ridge Mountains	266	\N
831638792125702144	19599101	@kurteichenwald but wait I thought Trump was Putin's puppet.	37.0902400000000014	-95.7128909999999991	United States	44	\N
829858459067699200	33105768	RT @ChrisJZullo: Donald Trump says 9th circuit is putting the security of our nation at stake but more Americans died by armed toddlers tha…	-122.419420000000002	37.7749299999999977		1	\N
831638791924375559	826493557255110656	@Kmslrr @jaketapper @amyklobuchar Trump = Nixon, only worst and faster. https://t.co/MD4lFvX65O	40.7282239000000033	-73.7948516000000012	Queens, NY	134	\N
831638791865630720	729745131918626817	RT @foxandfriends: Trump, GOP lawmakers eye 'illegal' leaks in wake of Flynn resignation https://t.co/orYkLpyE2v	32.776664199999999	-96.7969879000000049	Dallas, TX	267	\N
831638791718830080	1064418926	RT @chicagotribune: Russia deploys cruise missile in violation of Cold War-era arms treaty, Trump official says https://t.co/37pO2LuIUb htt…	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
829858458560241665	720427434760212480	RT @JrcheneyJohn: President Trump Responds to the 👉9th CIRCUS COURT OF APPEALS 👉 Who has a reputation for their rulings being OVERTURNED #M…	-122.419420000000002	37.7749299999999977		1	\N
831638791584677894	1395505981	RT @BetteMidler: Trump &amp; Trudeau discussed trade &amp; security. I’d also like to discuss it, because I would feel more secure if we traded Tru…	49.2147869	15.8795515999999992	Třebíč, Czech Republik, EU	268	\N
831638791366463489	354932609	Protesters Rally Outside Schumer’s Office to Push For Anti-Trump Town Halls: Protesters called on New…… https://t.co/XIjIy2651s	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
831638790884110336	609793904	RT @FedcourtJunkie: Scoop: ICE arrested DACA recipient in Seattle on Fri, still holding him. Came here at age 7, no crim record. Could be a…	32.2217429000000024	-110.926479	Tucson, AZ	269	\N
831638790825402369	827910559760838657	Bill Gates: Global health plans at risk under Trump https://t.co/z6qVZyHDEg https://t.co/tG8Buq0Ns4	42.3600824999999972	-71.0588800999999961	Boston, MA	149	\N
829858461513023488	55220637	RT @ErickFernandez: @realDonaldTrump Trump White House right now... https://t.co/fgZfphGh8b	-35.6751470000000026	-71.5429689999999994	Chile	123	\N
829858461282365440	468785268	RT @okayplayer: MAJOR: Preliminary impeachment papers filed against Trump. https://t.co/77UonZ1Vs3 https://t.co/7KwJHktVu8	\N	\N	#860 Born & Raised 	\N	\N
829858461064318980	819731072	RT @zachjgreen: Poor Trump. It's not easy to be a dictator in a democracy.	44.3148442999999972	-85.602364300000005	Michigan	124	\N
829858460900663301	89680313	Appeals Court Rejects Bid To Reinstate Trump's Travel Ban https://t.co/izcSkWDeAW by #CoryBooker via @c0nvey	40.0583237999999966	-74.4056611999999973	New Jersey, USA	68	\N
829858460678361088	757057617898328064	Produced and directed by donald trump https://t.co/OHtsTdVGEZ	18.3357649999999985	-64.8963349999999934	Virgin Islands, USA	125	\N
831638790728998912	3317649485	ProgressiveArmy: RT TheBpDShow: Special Edition - Trump's National Security Advisor, Michael Flynn, Resigns #FlynnResignation: …	28.2188991999999992	-82.4575938000000122	Land O' Lakes, FL	265	\N
829858458077904896	2217063241	RT @thehill: Trump paused Putin call to ask aides to explain nuclear arms treaty with Russia: report https://t.co/81bfhiWbJB https://t.co/N…	-122.419420000000002	37.7749299999999977		1	\N
829858458061197312	826210565265752068	RT @FoxBusiness: .@michellemalkin: Not only are they taking aim at Pres. #Trump's authority, this is a wholesale overturning of statute, pr…	-122.419420000000002	37.7749299999999977		1	\N
829858458014982145	1205791842	RT @WSJopinion: The Non-Silence of Elizabeth Warren: The next Democratic President is going to get the Trump treatment. https://t.co/WOYMet…	-122.419420000000002	37.7749299999999977		1	\N
831638790389301248	816977735356710912	With President Trump in his fourth full week in office upheaval is now standard... https://t.co/Wmp8svfEPf by #BethKassab via @c0nvey	28.5383354999999987	-81.3792365000000046	Orlando, FL	130	\N
831638789923729408	844587194	RT @Amy_Siskind: 5/23 @RepHolding of NC voted against Trump releasing his tax returns too. https://t.co/EhfBSYrDMB	39.9525839000000005	-75.1652215000000012	Philly!	270	\N
829858457717182464	142743993	RT @TEN_GOP: Hillary, you forgot about 6. Pres. Trump's 3-0-6 electoral votes. Landslide victory. Thank you for reminding us!\n'9th Circuit'…	-122.419420000000002	37.7749299999999977		1	\N
831638789596422144	149318455	RT @IngrahamAngle: Flynn Flap Brings Out Long GOP Knives for Trump https://t.co/TeaOu9S3Sw via @LifeZette	36.3302284000000029	-119.292058499999996	Visalia, CA	271	\N
831638789479084032	942186769	RT @Amy_Siskind: 12/23 @DevinNunes from CA no less, voted against Trump releasing his tax returns https://t.co/IjJOy4TZ9W	0	0	NO LISTS, NO BIZ, WILL BLOCK	0	\N
829858457167728641	18021721	RT @JoyAnnReid: This Trump scorcher from @FrankieBoyle though ... https://t.co/qXnvwmmL9w	-122.419420000000002	37.7749299999999977		1	\N
829858456853217280	724594033033666561	RT @FoxNewsInsider: CAIR Planning Lawsuit Against Trump Over Immigration Ban\nhttps://t.co/MeEZ6bSHWd	-122.419420000000002	37.7749299999999977		1	\N
829858456647512064	123818454	RT @gauravsabnis: Trump just told the court, see you in court. In caps. This guy is the president! 🙄 https://t.co/D6eguH7TLR	-122.419420000000002	37.7749299999999977		1	\N
831638789026050049	1706231244	RT @Anomaly100: UH OH!: Trump’s Personal And Official Accounts Just Unfollowed Kellyanne Conway (IMAGES) https://t.co/StozkqAhrV #Flynnghaz…	0	0	Farside Chicken Ranch	0	\N
831638788996812800	158066358	RT @Adweek: John Oliver is educating Trump on major issues with D.C. ad buy during morning cable news shows: https://t.co/Oi35IvRMkj https:…	30.2671530000000004	-97.743060799999995	Austin, TX	106	\N
831638788971524096	2153863514	I feel like we just breezed passed the fact that Trump SCOTCH TAPES HIS FUCKING TIES.\n\nLet's get back to the real issues.\n\n#TrumpTapesTies	34.0522342000000009	-118.243684900000005	LA	259	\N
829858456135933952	813942384144875520	RT @3lectric5heep: BREAKING VIDEO : President Trump Responds to 9th Circuit Ruling https://t.co/9RQfRL18Ts @3lectric5heep	-122.419420000000002	37.7749299999999977		1	\N
829858456114982913	3309750788	RT @LOLGOP: This is holding Conway to a standard Trump constantly breaks. In fact, we have no idea how often he breaks it without his tax r…	-122.419420000000002	37.7749299999999977		1	\N
829858455943000064	760004348135018496	RT @mitchellvii: The Left doesn't care about Terrorism.  They didn't give a damn when 49 gays were massacred in Orlando.  Only Trump cared.	-122.419420000000002	37.7749299999999977		1	\N
829858455833952257	942287282	RT @BraddJaffy: Reuters: Trump told Putin the U.S.-Russia nuclear arms START treaty was a bad deal—after asking aides what it was https://t…	-122.419420000000002	37.7749299999999977		1	\N
831638788761792513	168466173	RT @BetteMidler: Trump &amp; Trudeau discussed trade &amp; security. I’d also like to discuss it, because I would feel more secure if we traded Tru…	-33.8633060000000015	151.209317300000009	Sydney, Australia, Earth	272	\N
831638788426309632	200339644	A scary development for DACA recipients! US arrests Mex immigrant in Seattle covered by Obama program https://t.co/rztc8qQAnI via @Reuters	32.776664199999999	-96.7969878999999906	Dallas, TX	267	\N
834234234898366464	771868219946721280	RT @RawStory: WATCH: Angela Rye absolutely destroys CNN conservative who credits #Trump with fighting bigotry https://t.co/DdvXKZyqYI https…	33.8360810000000001	-81.1637245000000007	South Carolina, USA	311	\N
834236048582533122	287947472	RT @RealJack: Massive riots now breaking out over the last few days in #Sweden. How many times does President Trump have to be right? https…	37.0902400000000014	-95.7128909999999991	United States	44	\N
829858453216751616	798654799382122496	RT @LuxuriousAdven: Appeals court deals yet another blow to Donald Trump's travel ban targeting Muslims https://t.co/X03Fuu5LZs via @HuffPo…	-122.419420000000002	37.7749299999999977		1	\N
829858453027893248	796451054883717120	RT @JoyAnnReid: .@CNN is reporting that at least one of the appeals court judges hearing Trump's travel ban case has needed extra security…	-122.419420000000002	37.7749299999999977		1	\N
834236048561446913	23685282	RT @JohnWDean: Nice recap by @Will_Bunch of why Trump's Russian entanglements could be worse than Watergate: https://t.co/puO5zejeFI	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834242845942898688	29862148	Check this out:"Trump Appears Set to Reverse Protections for Transgender Students" https://t.co/j8oRUWzvh5	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
829858456714752000	1628768906	Hillary Clinton trolls Trump on his court losses: '3-0' https://t.co/tnx1tjtg8y	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
829858455393595394	555265952	Trump YemenGhazi catastrophe investigated by Kelly Spam Con Away. Local Media cover cock fight in Keokuk.… https://t.co/p4TLSJoHaC	41.3649879999999968	-93.5636259999999993	Simpson College	147	\N
829858455284482048	275376860	@kylegriffin1 She don't care. Neither does Trump	43.6532259999999965	-79.3831842999999964	Toronto	148	\N
829858455146131457	30807460	RT @latimes: Leader of Muslim civil rights group on 9th Circuit ruling on Trump's travel ban: https://t.co/G9JLDgP3Y4 https://t.co/iycRe0m8…	41.8781135999999989	-87.6297981999999962	Chicago	94	\N
829858454793748489	2760391434	RT @chelseahandler: Trump says his daughter has been treated ‘so unfairly’ by Nordstrom. Oh, was she detained for 19 hours when she tried t…	42.3600824999999972	-71.0588800999999961	Boston, MA	149	\N
829858454659411968	2417510562	RT @lsarsour: Trump's Muslim ban stays blocked. Unanimous decision from 9th circuit court! Great news! #NoBanNoWall 🙌🏽🙌🏽	32.7157380000000018	-117.1610838	San Diego, CA	150	\N
829858454131077120	72578711	RT @Greg_Palast: Sat @ 7AM PT on @AMJoyShow: I'll be talking #Trump, #Crosscheck &amp; #ElectionFraud w/ @JoyAnnReid https://t.co/Maf0zaz5EB #A…	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
829858453996740608	711924773115338752	RT @thinkprogress: Democrats will never lead the resistance against Trump, but they can join it https://t.co/M1wBNkCn42 https://t.co/Mui7uv…	40.7830603000000025	-73.9712487999999979	Manhattan, NY	133	\N
829858453761904640	216786228	RT @rickhasen: Page 22, 9th Circuit throws some shade on the Trump Administration not having its act together https://t.co/o9pp2XrlxM	33.7589187999999965	-84.3640828999999997	Everywhere	151	\N
829858453623537664	1894341344	RT @wondermann5: trump: My travel ban will be reinstated \n\nNinth Circuit Court of Appeals: https://t.co/wbh2379eTG	42.6251505999999978	-89.0179332000000016	the roch	152	\N
829858453292199938	732379630091403265	Dershowitz: Lawsuit Against Trump Order Still Has ‘A Very, Very, Uphill Fight’ To Win at SCOTUS https://t.co/3MSQbpqISp #Trump2016	37.0902400000000014	-95.7128909999999991	United States	44	\N
829858452952473600	17207314	RT @kalebhorton: Today, Trump crossed the rubicon. Once you say this to your country, there is no going back, and there is no normal. https…	41.8781135999999989	-87.6297981999999962	Chicago	94	\N
831638782843768832	116096328	RT @Amy_Siskind: 15/23 David Reichert from WA no less.  Def vote this fool out too for voting against Trump releasing his tax returns https…	0	0	It's not flat here.	0	\N
831328714759737348	70873025	RT @TheRickyDavila: Sally Yates warned the *trump regime that Flynn was trouble and how was she thanked? Oh yea, she was fired. #Resist\nhtt…	-122.419420000000002	37.7749299999999977		1	\N
831328714466148353	343405613	RT @RealJack: TRUMP EFFECT: All 5 major Wall Street averages finished in RECORD TERRITORY today! https://t.co/hgIJzrjZT0	-122.419420000000002	37.7749299999999977		1	\N
831328714143170561	2918923293	RT @CNNPolitics: Poll: 40% of Americans approve of President Donald Trump's job as president so far, compared to 55% who disapprove https:/…	-122.419420000000002	37.7749299999999977		1	\N
831328714034147329	821147814898126848	RT @SenSanders: Surprise, surprise. Many of Trump's major financial appointments come directly from Wall Street – architects of the rigged…	-122.419420000000002	37.7749299999999977		1	\N
831328713937735682	164254243	RT @linnyitssn: Dear Media, unless you seriously believe General Flynn did something Trump didn't know, this would be the right time to dis…	-122.419420000000002	37.7749299999999977		1	\N
831328713920880641	2967194934	RT @DanEggenWPost: 2/x\nMar-a-Lago snafus: \nhttps://t.co/AsDbJsasHa\nTrump acting the part: \nhttps://t.co/ARgUetY0ai\nPuzder woes: \nhttps://t.…	-122.419420000000002	37.7749299999999977		1	\N
831328713102983168	11262752	RT @SenSanders: We suffer from a grotesque level of income and wealth inequality that Trump's policies will make even worse.	-122.419420000000002	37.7749299999999977		1	\N
831638782524809216	25137996	RT @WaysMeansCmte: By a vote of 23-15, Republicans just voted to not request President Trump's tax returns from the Treasury Department.	45.4870620000000017	-122.803710199999998	Beaverton, OR	284	\N
831328712826183682	47791293	RT @kylegriffin1: This happened: Trump worked his response to NK's missile launch in Mar-a-Lago's dining room—in front of the diners https:…	-122.419420000000002	37.7749299999999977		1	\N
831638782390714369	496383725	RT @FedcourtJunkie: Scoop: ICE arrested DACA recipient in Seattle on Fri, still holding him. Came here at age 7, no crim record. Could be a…	40.0583237999999966	-74.4056611999999973	New Jersey, USA	68	\N
831328712385773568	1832685542	RT @molly_knight: WaPo bombshell: Sally Yates warned Trump that Flynn was likely compromised by Russia. She was fired days later. https://t…	-122.419420000000002	37.7749299999999977		1	\N
831638782315081728	876541285	“Really hard to overstate level of misery radiating from several members of White House staff over last few days,” https://t.co/H0kSKPp30O	38.535555500000001	22.6216666000000011	Mount Parnassus	285	\N
831638782243807233	824434492731486208	Bill Gates: Global health plans at risk under Trump https://t.co/EnLQIVqPcP https://t.co/LW7ySjcAU3	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
831638781992300545	776815651	RT @shaneharris: This is a serving general wondering whether the U.S. government is "stable." https://t.co/HHpnv9abgx https://t.co/5SbXkCwa…	38.9071922999999984	-77.0368706999999944	Washington, D.C.	286	\N
831638781941932033	1955132936	Trump on Flynn Resignation: 'So Many Illegal Leaks Coming Out of Washington' https://t.co/N1xbFihxOs\n\nVRA	38.9586307000000005	-77.3570028000000036	Reston, Virginia	287	\N
831638781899911168	23384997	RT @NBCNews: JUST IN: Sources tell NBC News that VP Pence was informed of DOJ warning about Flynn 11 days after White House and Pres. Trump…	36.7782610000000005	-119.417932399999998	California, USA	71	\N
831638781799301122	3054041804	RT @SarahJohnsonGOP: Marco Rubio has a message for Hollywood stars protesting Trump https://t.co/iSsqrJTQNU https://t.co/GRUaxNG8Qj	27.9476392000000011	-82.4572026000000022	Tampa, FL -Nationwide	288	\N
831638781740544000	463227379	RT @dmspeech: Putin trying to distract for BFF Trump #RussianGOP https://t.co/xJ55Bo8Tem	36.7782610000000005	-119.417932399999998	California	61	\N
831328710573772800	803110101401747460	RT @samueloakford: Mar-a-Lago member who pays Trump hundreds of thousands of dollars posts pics of - and identifies - US official carrying…	-122.419420000000002	37.7749299999999977		1	\N
831638781388165120	3019724101	Tom Brady Says Patriots Visiting Trump's White House Isn't Political: After a number of New England Patriots…… https://t.co/AxzgK4iuQZ	33.7489953999999983	-84.3879823999999985	Atlanta, GA	289	\N
831328709542031360	3383915847	RT @atrumptastrophe: World security at it's finest, ladies and gentlemen. #trump #japan #northkorea https://t.co/yePZ0P7xVt	-122.419420000000002	37.7749299999999977		1	\N
831328708766101504	4591927037	RT @DebraMessing: “How Trump can be held accountable for violating the Constitution, even if Congress doesn’t care” by @JuddLegum https://t…	-122.419420000000002	37.7749299999999977		1	\N
831328708162179072	192108196	RT @A_L: Whoa: buried in an EO signed two days before ~that~ EO, T excluded non-citizens/LPRs from Privacy Act PII provision https://t.co/3…	-122.419420000000002	37.7749299999999977		1	\N
831328708006965250	994386145	RT @FoxNews: Trace Gallagher: “There is zero evidence showing that immigration agents are doing more under the Trump admin than during the…	-122.419420000000002	37.7749299999999977		1	\N
831328707616714752	2593332564	RT @verge: A US-born NASA scientist was detained at the border until he unlocked his phone https://t.co/y0U3e4pYCN https://t.co/BfaR0wgq86	-122.419420000000002	37.7749299999999977		1	\N
831328707214180357	1141357820	RT @PaulBegala: If the Trump WH is going to fire people just because they may be vulnerable to Russian blackmail, this won't end well for @…	-122.419420000000002	37.7749299999999977		1	\N
831328709936349184	2284241036	RT @BarstoolBigCat: Breaking down the all 22, Trudeau grabbing on to Trump's arm gave him all the leverage he needed to avoid the cuck. Tap…	43.6532259999999965	-79.3831842999999964	Toronto, Ontario	39	\N
831328709474816000	44655602	RT @DavidCornDC: Hypocrisy in the Trump White House? How can that be? https://t.co/OcNZuRlE8F	39.3209800999999999	-111.093731099999999	Utah	162	\N
831328708896161792	755225547219795968	RT @OffGridMedia: California Democrats arrogant insult to Americans across the countryl' https://t.co/uGv3C5tfm0 via @BreitbartNews	26.1420357999999986	-81.7948102999999946	Naples, FL	163	\N
831328708736724993	104631905	RT @TVietor08: The whole fucking campaign was about Hillary's emails and now Trump's team is violating the Presidential Records Act by usin…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
831328708732579840	2772058818	RT @molly_knight: WaPo bombshell: Sally Yates warned Trump that Flynn was likely compromised by Russia. She was fired days later. https://t…	35.1495342999999991	-90.0489800999999943	Memphis Tennessee	164	\N
831328708585611264	40421947	RT @IMPL0RABLE: #TheResistance\n\nRumor has it the Trump admin really doesn't like SNL's parodies of Sessions &amp; Spicer by women. So do not re…	49.2827290999999974	-123.120737500000004	Vancouver, British Columbia	165	\N
831328708338262016	2408058516	RT @TVietor08: The whole fucking campaign was about Hillary's emails and now Trump's team is violating the Presidential Records Act by usin…	0	0	✶ ✶ ✶ ✶	0	\N
831328707969179648	15335778	RT @A_L: Whoa: buried in an EO signed two days before ~that~ EO, T excluded non-citizens/LPRs from Privacy Act PII provision https://t.co/3…	37.8271784000000011	-122.291307799999998	SF Bay Area	166	\N
831328707776180224	14552215	@dcbergin56  I thought that gwb was stupid , but Trump is a whole nother level below stupid. That level's name is not said aloud.	29.7604267	-95.3698028000000022	Houston, TX	167	\N
831328706987560960	110799048	RT @JuddLegum: 1. Just published a piece about a new strategy to hold Trump accountable. Critically, it doesn't involve Republicans https:/…	36.7782610000000005	-119.417932399999998	California	61	\N
831638781312667648	260690940	RT @FedcourtJunkie: Full exclusive on ICE arrest of DACA recipient who came from Mexico as a child. His lawyers hope it was a mistake https…	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
831638781274976256	184341939	RT @SarahLerner: BF: What do you want for Valentine's Day?\n\nMe: I WANT THE WHOLE TRUMP ADMINISTRATION TO TOPPLE LIKE A HOUSE OF CARDS CAN Y…	33.7700504000000024	-118.193739500000007	Long Beach, CA	290	\N
831638780985561088	4724956086	RT @DefendEvropa: 'You will CRUSH the people' &amp; 'repalce Europe's people' Hungarian PM slams 'GLOBALIST ELITE' for open-door migration http…	25.7616797999999996	-80.1917901999999998	Miami, FL	141	\N
831638780880773120	2822619188	RT @NumbersMuncher: I feel like Dan Rather is going with this angle for every single Trump story. https://t.co/0oJpJJMfXg	31.9685987999999988	-99.9018130999999983	Texas USA	291	\N
831638780700459009	389880004	@Grimeandreason For example, civ servants working to slow Trump, it's an act of risky defiance, not an extant network running the show	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
831638780612399105	954825379	RT @LauraLeeBordas: BREAKING: Shep Smith To Be Canned Because He Can’t Control His Hate For Donald Trump @FOXNews hate Shep&amp; Harp Boycot ht…	32.8305819999999997	-97.3265169999999955	Great Southwest	292	\N
831638780264247296	780612340186091520	@slagathoratprom @thehill @SenJohnMcCain 3/Al Franken says most all talk about Trump behind his back. I feel They are just using him to	37.0902400000000014	-95.7128909999999991	United States	44	\N
831328705783984129	250322100	@billmaher try to get over it.  Trump won its president trump now	-122.419420000000002	37.7749299999999977		1	\N
831328704886403074	14586497	RT @FDRLST: 16 Fake News Stories Reporters Have Run Since Trump Won https://t.co/8McwpzN6WL	-122.419420000000002	37.7749299999999977		1	\N
831638780100505600	86483454	RT @Bianca_Dezordi: All Of Us Certainly Wonder What Kind Of First Lady Will Melania Trump Be? https://t.co/iXKwdRjoD5	25.9017471999999991	-97.4974837999999977	Brownsville, TX	293	\N
831638779970596866	823275743283179520	President Trump Signs H.J. Res. 41: https://t.co/XgUvHMwhtM via @YouTube	38.8976763000000005	-77.0365297999999967	White House	294	\N
831638779949641731	34093461	RT @michikokakutani: Remember this story....\nSecret Ledger in Ukraine Lists Cash for Donald Trump’s Campaign Chief Manafort. via @nytimes h…	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
831328703766491142	785536497084661760	RT @activist360: When Trump said of Goldman Sachs and banksters that he'd 'take them on', all intelligent ppl knew he was talking about hir…	-122.419420000000002	37.7749299999999977		1	\N
831638779916075008	316788501	RT @belalunaetsy: Please remember: Trump did not fire Flynn \n\nTrump fired the woman who warned him about Flynn https://t.co/l2ReLBRV9L	34.0753762000000009	-84.294089900000003	Alpharetta, Georgia	295	\N
831638779895103488	822918126299938817	RT @DCeezle: People hated Hillary for having ties to Wall Street.\n\nYet no one seems to mind that Wall Street's balls are resting on Trump's…	37.0902400000000014	-95.7128909999999991	United States	44	\N
831328702969438214	959369839	RT @AC360: Refugees flee U.S. seeking asylum in Canada due to #Trump presidency, via  @sarasidnerCNN https://t.co/MpQ2hvYrGc https://t.co/w…	-122.419420000000002	37.7749299999999977		1	\N
831328702940188675	315948500	RT @realDonaldTrump: Today I will meet with Canadian PM Trudeau and a group of leading business women to discuss women in the workforce. ht…	-122.419420000000002	37.7749299999999977		1	\N
831638779869929474	17783436	This beloved scientist says Trump is wrong about immigration https://t.co/aWTLInHZFS via @nbcnews	40.7127837000000028	-74.0059413000000035	New York City, U.S.A.	296	\N
831328701858062336	595799102	RT @Cernovich: Deep State v Trump. If Flynn is removed, there will be another war. That is why opposition media wants him out. https://t.co…	-122.419420000000002	37.7749299999999977		1	\N
831328700209602561	3309927150	RT @HeyTammyBruce: Is the left putting the nation at risk by obstructing Trump's immigration order? My comments this morning: https://t.co/…	-122.419420000000002	37.7749299999999977		1	\N
831328699886641152	395475144	RT @JuddLegum: Trump, who promised to rarely leave the White House and never vacation, prepares to spend third straight weekend in Mar-a-la…	-122.419420000000002	37.7749299999999977		1	\N
831328705658179584	45231220	RT @matthewamiller: Flynn is going to be fired soon and Trump is going to try and move on, but it's clearer than ever there needs to be an…	38.6315389000000025	-112.121412300000003	ÜT: 33.893384,-118.038617	172	\N
831328705435856897	1348029342	RT @ItsChinRogers: Glenn Beck has always kept bodyguards for his paranoia du jour. Sad that Beck lies so easily and without hesitation. #Tr…	42.0978361000000021	-88.2774813000000051	Bikini Bottom	173	\N
831328705083502592	45058631	Republican Congressman Hints At Trump Impeachment If Flynn Lied For The President https://t.co/FVD2YzcgkJ	40.7127837000000028	-74.0059413000000035	NYC	60	\N
831328704819318785	9069612	RT @TVietor08: The whole fucking campaign was about Hillary's emails and now Trump's team is violating the Presidential Records Act by usin…	0	0	TOL, but really TDZ	0	\N
831328704747991040	2734154836	RT @pbpost: BREAKING: Trump might return to Palm Beach for third straight weekend\nhttps://t.co/h3UzjnZeS7 https://t.co/xoZ5Uswyf9	51.5237715000000023	-0.158538499999999999	221B Baker Street	174	\N
831328704424976391	749329877233504257	RT @MrJamesonNeat: #CongressDoYourJob impeach Trump https://t.co/LVmnsBv057	41.7003713000000005	-73.9209701000000052	Poughkeepsie, NY	175	\N
831328704198500354	431820831	Trump’s Shul https://t.co/QRz3dQbMh4	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
831328702751449088	145477243	RT @SenSanders: Trump is backtracking on every economic promise that he made to the American people. https://t.co/4bICbwUZ2v	33.7489953999999983	-84.3879823999999985	Atlanta	182	\N
831328702323650560	805593247133405186	RT @JordanUhl: Sally Yates was fired for 'not being loyal' while Mike Flynn conspired with Russia.\n\nIn Trump's America, treason is better t…	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
831328701627392004	2938546401	RT @ABCWorldNews: Canadian Prime Minister Trudeau says it's not his job to 'lecture' President Trump on Syrian refugees. https://t.co/SB4SK…	27.6648274000000001	-81.5157535000000024	Florida	183	\N
831328701421740032	16062372	RT @frankrichny: Best incentive for Trump standing by Flynn: To deny Flynn the incentive to leak all he knows about what Russia has on POTU…	37.7749294999999989	-122.419415499999999	San Francisco	37	\N
831328701086367745	756684636982349824	RT @Healthtechtalkn: Read The Healthcare Technology Daily ▸ today's top stories via @jdschlick @masonphysics @Paul_BolinskyII #trump https:…	38.9071922999999984	-77.0368706999999944	District of Columbia, USA	184	\N
831328700964696064	16155872	A Stunning Display of Dishonesty from the National Press and Radical-Left Politicians https://t.co/9J55bGkPUh Nothing on Obama lies on Trump	34.0007104000000027	-81.0348144000000019	Columbia, South Carolina	185	\N
831328700637515776	2202072090	RT @JoyAnnReid: Important bottom line in this piece: Jared Kushner is no moderating influence on Trump. He's a full Bannon believer. https:…	43.4113603999999995	-106.2800242	Midwest	186	\N
831328699811295235	1069802306	RT @Phil_Lewis_: Get you someone that looks at you the way Ivanka Trump looks at Justin Trudeau https://t.co/sxTAlpi4av	-12.2720956000000001	-76.2710833000000008	Lima-Perú	187	\N
831328699664437248	115907262	RT @PhilipRucker: Journalist @AprilDRyan tells WaPo that Trump aide Omarosa Manigault “physically intimidated” her outside Oval Office http…	22.3964280000000002	114.109497000000005	Hong Kong	188	\N
831328699253403648	431820831	Trump’s Shul https://t.co/WrFltlucC0	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
831328698662002689	780743799182024708	RT @leahmcelrath: So this just happened: Jake Tapper called out Trump advisor Roger Stone for lying: https://t.co/qLcgXrnAnR	-122.419420000000002	37.7749299999999977		1	\N
831328696527122433	785511711663161344	RT @DanEggenWPost: 2/x\nMar-a-Lago snafus: \nhttps://t.co/AsDbJsasHa\nTrump acting the part: \nhttps://t.co/ARgUetY0ai\nPuzder woes: \nhttps://t.…	-122.419420000000002	37.7749299999999977		1	\N
831328696430641156	1596679669	RT @ChrisRulon: .@SarahKSilverman Jewish aide wrote Trump Holocaust statement: report #oops https://t.co/IBwqMtBMEV	-122.419420000000002	37.7749299999999977		1	\N
831328696267112450	2698642382	RT @nytimes: From President Trump’s Mar-a-Lago to Facebook, a national security crisis in the open https://t.co/Xm1g84NE0p	-122.419420000000002	37.7749299999999977		1	\N
831328696208392192	923964859	RT @MattMurph24: Trudeau speaking in 2 languages while Trump can't even speak in one.	-122.419420000000002	37.7749299999999977		1	\N
831328695361142784	259747747	RT @mila_bowen: Congressman: Rarely used law could make Trump tax returns public https://t.co/K5CfUPNxWn via @CNN @ChrisCuomo @MSNBC @abcac…	-122.419420000000002	37.7749299999999977		1	\N
831329862711463936	214296813	RT @EJDionne: #Trump's #Flynn nightmare: Flynn can't be trusted but dumping him won't end the questions about Trump &amp; Russia.\nhttps://t.co/…	-122.419420000000002	37.7749299999999977		1	\N
831329861847359488	58664114	RT @drujohnston: Under Trump American Cheese is finally living up to it's name. Orange, tasteless and has a complete meltdown after being s…	-122.419420000000002	37.7749299999999977		1	\N
831329860882661377	14800696	RT @edatpost: Told about Trump reviewing N Korea details in the open on Saturday, @SenFeinstein let out a big sigh. "Not good" she said, sh…	-122.419420000000002	37.7749299999999977		1	\N
831328696644558849	29351788	RT @matthewamiller: Flynn is going to be fired soon and Trump is going to try and move on, but it's clearer than ever there needs to be an…	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
831328696422240257	74772716	RT @JuddLegum: 1. This story I published this morning is the most important thing I've written in awhile https://t.co/SKF9u4Pcr5	32.9342918999999981	-97.0780653999999998	Grapevine, TX	196	\N
831328696292167680	32297637	RT @juliaioffe: If Trump fires Flynn, does Flynn start talking? Is that a consideration of the White House?	38.4087992999999983	-121.371617799999996	Elk Grove, CA	197	\N
831328695847514112	15397002	RT @LarzMarie: Donald Trump and his staff are Vanderpump Rules characters and the White House is SUR	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
831328695675666432	1935181976	There must be some kind of rarefied air being circulated through the air ducts of the Capitol Bldg.Trump should not… https://t.co/qbOY9eZadg	41.1544432000000029	-96.0422377999999952	Papillion, NE	198	\N
831328695339999232	800535028866220033	Senate Democrats question security of Donald Trump's phone - CNET https://t.co/TFyfSTCVzO https://t.co/TVkKEd2JxX	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
831328695302356992	3231211783	RT @BlissTabitha: #FakeNews Muslim Olympian 'detained because of President Trump's travel ban' was detained under Obama https://t.co/7II7iq…	37.0902400000000014	-95.7128909999999991	United States	44	\N
831328695092649984	23077947	RT @Ohio_Politics: Ohio @SenRobPortman and @SenSherrodBrown split votes on @RealDonaldTrump Treasury pick. https://t.co/Yfxb8MWS58 https://…	39.7589478000000014	-84.1916068999999965	Dayton, OH	200	\N
831329862635896835	801825680266760192	RT @AC360: .@jorgeramosnews : "Donald Trump is ripping families apart" https://t.co/uowk7Qnl0D https://t.co/2RQ15XrIMU	39.337272200000001	-85.4835810000000009	Greensburg, IN	201	\N
831329862539436032	465800348	@Lollardfish He just looks so great compared to Trump.	42.4072107000000003	-71.3824374000000006	Massachusetts	202	\N
831329862501535744	478197603	RT @realDonaldTrump: Today I will meet with Canadian PM Trudeau and a group of leading business women to discuss women in the workforce. ht…	37.0902400000000014	-95.7128909999999991	America	203	\N
831329862245810176	21469302	RT @JonRiley7: It's not enough to fire General Flynn. Trump's team making secret deals with Russia before the inauguration is grounds for i…	27.6648274000000001	-81.5157535000000024	South West Florida	204	\N
831329861419540481	705942450	RT @Darren32895836: Dems stay home frm work to coil up in safe spaces after learning Joy Villa dress designer is Pro Donald Trump , Gay , &amp;…	38.8799696999999966	-77.106769799999995	Arlington, VA	205	\N
831329861335609344	130595733	RT @sadmexi: If you saw Donald Trump getting jumped by 42 people, what would you do?	37.8271784000000011	-122.291307799999998	bay area	206	\N
831329861268537344	533619242	RT @JordanUhl: Sally Yates was fired for 'not being loyal' while Mike Flynn conspired with Russia.\n\nIn Trump's America, treason is better t…	29.7631380000000014	-81.4605270999999931	207	207	\N
831329861235044352	279682329	RT @Karoli: BOMBSHELL: Acting AG Sally Yates Warned Trump Administration About Flynn | Crooks and Liars https://t.co/LczEsHZzzR	42.3292525000000026	-73.6156734999999998	Ghent New York, USA	208	\N
831329859666378753	23079800	RT @matthewamiller: Flynn is going to be fired soon and Trump is going to try and move on, but it's clearer than ever there needs to be an…	0	0	Born: Ho-Ho-Kus, NJ	0	\N
831329859599216640	16712241	RT @thehill: Trump's official inauguration poster had a glaring typo: https://t.co/PywdxQLhEl https://t.co/g1kJRxTQg2	43.2128473	-75.455730299999999	Rome, NY	209	\N
831329859569905666	1948811262	RT @TEN_GOP: This woman came here legally and she supports Trump on immigration. Please, spread her word. \n#DayWithoutLatinos https://t.co/…	37.0902400000000014	-95.7128909999999991	USA 	210	\N
831329859532099585	3299435929	Top story: From Trump’s Mar-a-Lago to Facebook, a National Security Crisis in t… https://t.co/ggIjHNECQJ, see more https://t.co/6RIs1VM5JR	37.0902400000000014	-95.7128909999999991	United States	44	\N
831329859255296001	1571678724	RT @ananavarro: Hour ago, Conway said Flynn has Trump's trust. Minutes ago, Spicer said, not so much. WH has political menopause. Cold 1 mi…	-122.419420000000002	37.7749299999999977		1	\N
831329859016257537	2473105433	RT @ActualEPAFacts: Will someone finally tell Trump no?? https://t.co/hB3K2rXCQz	-122.419420000000002	37.7749299999999977		1	\N
831329858215096320	17698060	RT @mlcalderone: Omarosa threatened @AprilDRyan, saying Trump officials had dossiers on her and several African American journalists: https…	-122.419420000000002	37.7749299999999977		1	\N
831329856264691712	721165578	RT @RepJayapal: Another judge, in another state, strikes down Trump's unconstitutional travel ban! Welcome to the fight, Virginia! https://…	-122.419420000000002	37.7749299999999977		1	\N
831329855832735744	741270822933782528	RT @WSJ: Beijing watches for how Trump handles North Korea\nhttps://t.co/W4PWUnZPkg	-122.419420000000002	37.7749299999999977		1	\N
831329855488811008	4421960175	RT @TVietor08: The whole fucking campaign was about Hillary's emails and now Trump's team is violating the Presidential Records Act by usin…	-122.419420000000002	37.7749299999999977		1	\N
831329855182630912	710580943564709888	RT @thehill: JUST IN: Republican lawmaker: Flynn "should step down" if he misled Trump https://t.co/IQOzLLTY51 https://t.co/DHJ7ZUjPql	-122.419420000000002	37.7749299999999977		1	\N
831329854532497408	415221425	RT @marylcaruso: .Just his look at Trump's hand says it all!\n#TrudeauMeetsTrump https://t.co/gXemPE29TA	-122.419420000000002	37.7749299999999977		1	\N
831329853957881856	2777995764	RT @asamjulian: MSM hates Flynn, Conway, Bannon, and Miller the most because they are unflinching defenders of Trump's nationalist policies…	-122.419420000000002	37.7749299999999977		1	\N
831329852775096322	796742622530404352	RT @climatehawk1: Why we must stop the Trump administration’s #climate #science denial | @DeSmogBlog https://t.co/sFAzdhmTHx #ActOnClimate…	-122.419420000000002	37.7749299999999977		1	\N
831329858965950464	2284614762	RT @beelman_matt: 🔥RIENCE ATTEMPTING COUP🔥President Trump &amp; General Flynn🔥WE STAND UNITED w/TRUMP!🔥\n#StandWithFlynn @realDonaldTrump @Donal…	37.0902400000000014	-95.7128909999999991	United States	44	\N
831329857191735296	1310965273	President Trump Has Done Almost Nothing https://t.co/8t5eBWu1n8	41.3082739999999973	-72.927883499999993	New Haven, CT	215	\N
834541113167982594	4904130164	Great, looks like Trump is gonna remove protections for trans students :/	39.7684029999999993	-86.1580680000000001	Indianapolis, IN	309	\N
834541113134428162	106143594	@TheMeemStreams @grafton_rusty there was NO terror attack in Sweden! Trump made it up. Lol	53.5443890000000025	-113.490926700000003	Edmonton, Alberta, Canada	644	\N
834541113021177857	788941335550128128	RT @MiguelCulone: @timkaine @Pontifex @GOLD_CUP45 @Bohicamf1 No Catholic would ever support abortion you loser. #ProLife #AmericaFirst #MAG…	41.2033216000000024	-77.1945247000000023	Pennsylvania 	949	\N
834541112589242368	726259958539390976	RT @SophiaMillerC: Trump-Russia: Senate Intel Committee goes after Michael Flynn and Donald Trump’s tax returns https://t.co/hYvcuBHrGJ htt…	34.0489280999999977	-111.093731099999999	Arizona, USA	943	\N
834541111578292224	437365052	RT @pharris830: Trump’s Staff Is Resorting To This Trick To Keep Trump From Throwing Twitter Tantrums https://t.co/eZEKt7kICP via @anteksil…	47.6062094999999985	-122.332070799999997	Seattle Washington	476	\N
834541111486119936	625668578	RT @DenMcH: SCOOP: Trump set to appoint former NYC accountant and recent night school JD Louis Tully to the federal bench https://t.co/IiDf…	35.3900079000000005	-119.121617599999993	Polo Grounds	950	\N
834541111330951168	169785728	Add #Trump's #Russia problem to the list of issues vexing Republicans at town halls: https://t.co/tUD1sKrl7s #healthcare #immigration	38.9071922999999984	-77.0368706999999944	Washington, D.C.	286	\N
834541111108521984	26208524	RT @CindyStorer: Gorka called my friend Mike @MichaelSSmithII to threaten him. I heard it. https://t.co/Mo4wEQ5Ttp	-37.8136110000000016	144.963055999999995	Melbourne	951	\N
831329851927834624	161399976	RT @TedGenoways: We have to admit: With every passing minute, the likelihood grows that Trump not only knew about but directed Flynn's call…	-122.419420000000002	37.7749299999999977		1	\N
831329848941494274	2192236919	RT @ChrisJZullo: How long can Congress ignore Donald Trump and his administrations blatant conflict of interest and misuse of tax dollars #…	-122.419420000000002	37.7749299999999977		1	\N
831329847796391938	702881049936703488	RT @BrianCBock: Why isn’t @wolfblitzer and @CNN talking about the likelihood that Flynn, Pence and Trump are all on the same page and they…	-122.419420000000002	37.7749299999999977		1	\N
831329846672322560	1062550070	RT @eosnos: Every Trump visit to Mar-a-Lago reportedly costs taxpayers $3+ million. If he keeps up current pace, public will pay $15+millio…	-122.419420000000002	37.7749299999999977		1	\N
831329846357803010	2427623580	RT @JordanUhl: Sally Yates was fired for 'not being loyal' while Mike Flynn conspired with Russia.\n\nIn Trump's America, treason is better t…	-122.419420000000002	37.7749299999999977		1	\N
831329845934178305	15023267	RT @politicususa: Trump Just Humiliated Himself In Front Of Canadian PM Justin Trudeau And The Entire World via @politicususa https://t.co/…	-122.419420000000002	37.7749299999999977		1	\N
831329845695033345	1369461836	RT @FedcourtJunkie: Breaking: Judge Robart says en banc review of Trump travel ban should NOT slow down proceedings in Seattle, orders both…	-122.419420000000002	37.7749299999999977		1	\N
831329845456039936	3224662738	RT @Phil_Lewis_: Get you someone that looks at you the way Ivanka Trump looks at Justin Trudeau https://t.co/sxTAlpi4av	-122.419420000000002	37.7749299999999977		1	\N
831329847037329412	9405632	RT @RobertMackey: Well, at least Trump didn't just hire 64 temporary foreign workers to wait tables at Mar-a-Lago. Oh wait - https://t.co/V…	42.5039395000000013	-71.0723390999999936	Wakefield, MA	244	\N
831329846965989377	2525341886	Trudeau pitched women business plan to Trump – and got Ivanka https://t.co/gImG3LJFrX	45.4215295999999995	-75.6971931000000069	Ottawa, Canada	245	\N
831329846575976449	71643224	RT @conradhackett: Canadians with no confidence in \nBush (2003) 39%\nBush (2007) 70%\n\nObama (2009) 9%\nObama (2016) 15%\n\nTrump (2016) 80% htt…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
831329846521270272	496648238	RT @joshtpm: my latest &gt;&gt; Trump's Russia Channel Now Has the White House in Full Crisis https://t.co/yFSwVzyg2W via @TPM	36.1699411999999967	-115.139829599999999	Las Vegas, NV	218	\N
831329845447626752	153638023	RT @leahmcelrath: THIS.\n\nJournalists, PLEASE do not disrespect the White House and simultaneously give Trump free advertising.\n\nSay NO to k…	44.5588028000000023	-72.5778415000000052	Vermont	246	\N
831329845372129280	100285197	RT @lrozen: Trump not firing Flynn suggests that Flynn was acting with Trump's consent. including in denying to the elected VP the nature o…	38.6270025000000032	-90.1994042000000036	St. Louis	247	\N
831329845007179776	2403016908	RT @AC360: .@jorgeramosnews : "Donald Trump is ripping families apart" https://t.co/uowk7Qnl0D https://t.co/2RQ15XrIMU	-122.419420000000002	37.7749299999999977		1	\N
831329844529074177	25281508	RT @RJSprouse: @pbump can we deport Trump for the safety of America?	-122.419420000000002	37.7749299999999977		1	\N
831329844470353920	1295656814	RT @DafnaLinzer: A must read. Warning came from Sally Yates who Trump fired less than two weeks into the job https://t.co/BZdxM2aFfj	-122.419420000000002	37.7749299999999977		1	\N
831638797506994177	810479257	RT @jacksonpbn: Dear members of Buhari House of Lies, stop disturbing us with Buhari/Trump phone calls. We want to see Buhari!	-122.419420000000002	37.7749299999999977		1	\N
831638796395491328	3395460531	RT @BraddJaffy: Sources tell NBC News that Pence was only told of the DOJ warning about Flynn late on Feb. 9th, 11 days after the White Hou…	-122.419420000000002	37.7749299999999977		1	\N
831638793996423168	158555462	RT @belalunaetsy: Please remember: Trump did not fire Flynn \n\nTrump fired the woman who warned him about Flynn https://t.co/l2ReLBRV9L	-122.419420000000002	37.7749299999999977		1	\N
831638793270751233	807322840219394049	RT @RealJack: Donald Trump doesn't put up with incompetence. If you don't think he's going to get out government working for us again, you…	-122.419420000000002	37.7749299999999977		1	\N
829820730481184768	250380376	Trump Tweet On Judge’s Legitimacy Crossed A Line: #Cleveland Federal Judge https://t.co/wpJ6P1ELJO	41.4993199999999973	-81.6943605000000019	Cleveland, Ohio	90	\N
831638790582079488	4138868054	RT @Amy_Siskind: 5/23 @RepHolding of NC voted against Trump releasing his tax returns too. https://t.co/EhfBSYrDMB	-122.419420000000002	37.7749299999999977		1	\N
831638790531854336	798243410595483649	RT @true_pundit: Bergdahl Says Trump Violated His Due Process Rights By Calling Him ‘A Dirty, Rotten Traitor’ #TruePundit https://t.co/3kwq…	-122.419420000000002	37.7749299999999977		1	\N
831638789583941632	565112744	RT @youlivethrice: Yes this jerk Shepard Smith is like the @CNN Anti-Trump rabid dogs. @bobsacard @FoxNews   @foxandfriends https://t.co/7T…	-122.419420000000002	37.7749299999999977		1	\N
831638788891934721	420396740	RT @PamKeith2016: Would now be a good time to remind everyone that Trump TURNED OFF THE RECORDER during his first "official" call with Puti…	-122.419420000000002	37.7749299999999977		1	\N
831638787935633409	820355810	RT @RichardTBurnett: Next for Trump: get all Muslim Brotherhood holdouts from Obama out of administration! Retweet if you agree please...👍🏻😎	-122.419420000000002	37.7749299999999977		1	\N
831638786111111168	551741950	RT @DavidCornDC: Spicer says Trump has been tougher on Russia re Ukraine than Obama. That's absurd. He refused to criticize Putin re Ukrain…	-122.419420000000002	37.7749299999999977		1	\N
831638785062494209	2548385760	RT @BeSeriousUSA: Congress had a chance to get Trump’s tax returns. Republicans voted it down. Is Flynn just tip of iceberg?\n#resist  https…	-122.419420000000002	37.7749299999999977		1	\N
831638783250558978	1372996296	RT @AltStateDpt: 23 Reps on the wrong side of history. They had a chance to confidentially review Trump's taxes for conflict.\n\nThey chose p…	-122.419420000000002	37.7749299999999977		1	\N
831638783057555456	46721764	RT @jbarro: I'm sure Pence has given at least a little thought to the ways Trump could implode and cause Pence to become president. How cou…	-122.419420000000002	37.7749299999999977		1	\N
828295466185945088	384162955	@GloriaLaRiva on #puzder #devos &amp; #mattis at #NoBanNoWall protest. Down with Trump's program! https://t.co/Fx5puOCQ5o	37.7749294999999989	-122.419415499999999	San Francisco	37	\N
831638788417925121	1381489394	RT @redneckcatlover: #Obama's shadow govt. "assassinated" #MichaelFlynn. #TheResistence is doing an #InsideJob 2 overthrow #Trump. ##MAGA #…	40.7518130999999997	-73.9939542000000046	Tír na nÓg 	273	\N
831638788325650432	22082265	Each day there are so many other disturbing developments that our ability to retain n maintain some order #resist \n\nhttps://t.co/godtfZaUEh	41.8781135999999989	-87.6297981999999962	Chicago, IL USA	274	\N
831638787667193857	155944733	RT @DavidYankovich: Check out Amy's timeline. She is tweeting out everyone who voted AGAINST Trump releasing his tax returns.\n\nTake note- t…	33.1106655000000032	-96.8279895999999951	With the Cowboys & Indians	275	\N
831638787218358274	806538285564698624	RT @BobTolin: Dems did not win, Rinos need to stand behind Trump or there will be a civil war and we the people will win https://t.co/iuWtG…	37.4315733999999978	-78.6568941999999964	Virginia	276	\N
831638786652114944	142721190	Reminder: Trump said he will focus on criminals and “bad ones,” but his definition of bad guy is very broad https://t.co/yMyqLzGP59	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
831638785968467968	389901236	RT @mmpadellan: Whomever is leaking info from the WH? Nice job. Keep up #TheResistance. We have infiltrated. #TuesdayThoughts\nhttps://t.co/…	39.645623999999998	-84.1473730000000018	Nowhere in particular. 	277	\N
831638785037303809	2178771822	RT @Mediaite: 'Don't Tell Me to Stop!': Ana Navarro Fights with Trump Supporter in Heated CNN Exchange https://t.co/dSq8GpahIW (VIDEO) http…	35.7915399999999977	-78.7811169000000007	Cary, NC	278	\N
831638785028980738	17541792	RT @FoxNews: Chaffetz investigating security protocols at Trump's Mar-a-Lago resort  https://t.co/KXh85NDKhT via @foxnewspolitics https://t…	43.6777176000000011	-79.6248197000000033	Canada  YYZ	279	\N
831638784496238592	2804286628	Judge grants injunction against Trump travel ban in Virginia https://t.co/jGbyZ4o1cM https://t.co/IYJDVr312m	37.0902400000000014	-95.7128909999999991	US	280	\N
831638784378814468	14425599	RT @PolitiFactFL: Trump security adviser Michael Flynn repeated wildly wrong claim about FL Democrats, Sharia law #Flynnresignation https:/…	27.6648274000000001	-81.5157535000000024	Sunshine State, U.S.	281	\N
831638783577595904	3312464120	Protesters Rally Outside Schumer’s Office to Push For Anti-Trump Town Halls: Protesters called on New York's… https://t.co/87v06QyWjK	40.2170533999999975	-74.7429383999999999	Trenton, NJ	282	\N
831638783045070848	190939080	Teacher Posts "The Only Good Trump Supporter Is a Dead Trump Supporter" https://t.co/bqbE8Lu0gv	41.6032207000000014	-73.0877490000000023	CT	283	\N
831638781358960641	2295712925	RT @politico: “We’re currently offering 4-to-1 for Trump to be impeached in the first six months.” https://t.co/R1uVREaUac https://t.co/APn…	-122.419420000000002	37.7749299999999977		1	\N
831638781224747014	799678925781680128	RT @teammoulton: "There is no question that Russia wanted Trump to become President." @sethmoulton	-122.419420000000002	37.7749299999999977		1	\N
831638780373184512	785691412146688001	RT @barry_corindia: White House says Trump knew three weeks ago that Flynn lied about contacts with Russia - LA Times https://t.co/AfHiJroA…	-122.419420000000002	37.7749299999999977		1	\N
831638779651883008	398341582	RT @WillMcAvoyACN: The White House has confirmed that Trump was informed about Flynn's actions weeks ago. How many classified briefings has…	-122.419420000000002	37.7749299999999977		1	\N
829775912010854401	635653	@NimbleBit uh, is that a replica of Trump Tower?	-122.419420000000002	37.7749299999999977	Lower Haight, San Francisco	19	\N
829583184102780928	46016762	Union members like Trump, and it'll cost them. Fools and money and all that. https://t.co/XAaGLVGcRM	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
828792665831399426	10727	All female SNL #trump troup coming soon: https://t.co/KVsjnXM9Ss	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
828446282427412480	16284556	@alednotjones Hah. Good game. Trump loves the Patriots and they love him. many parallels to election night. Good guys lose at the last sec	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
828421659686170624	598288085	Brady got the world going against him w that Trump shit #DirtyBirds #BlowOut	37.8043637000000032	-122.271113700000001	Oakland, CA	38	\N
828330896038072320	19429478	hey @realDonaldTrump have you seen your numbers? They are a total disaster. https://t.co/UogI8wrENz	37.7749294999999989	-122.419415499999999	San Francisco	37	\N
828319996765888512	740913	I just learned Melania Trump received a H-1B visa due to her skilled expertise as a fashion model.	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
831328715896287232	457715866	https://t.co/zK9NDg2qpZ Should have stayed a Civilian, Draft Dodging, Bankruptcy King!	36.1699411999999967	-115.139829599999999	 Las Vegas	154	\N
828061932103954432	76652672	Crowds chant #NoBanNoWall, hold signs and sing at a protest drawing thousands outside of City Hall.… https://t.co/R9tGoc42vK	37.5629916999999978	-122.325525400000004	San Mateo, CA	31	\N
828050940741578752	15506256	"Move Trump, get out the way Trump  get out the way get out the way" #NoBanNoWall	37.7749294999999989	-122.419415499999999	San Francisco	37	\N
827937272813101058	64010070	@shanetroach no, I think you're thinking of the initial tech summit Trump held awhile back. Was just a meeting (Cook was there too)	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
827935717540061184	64010070	@shanetroach FYI Bezos isn't on the Business Advisory Council. https://t.co/D7OpjKteZe	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
827933584774160385	64010070	@troyrcosentino *Trump repeals Dodd-Frank while giving JP Morgan CEO a handy under the table*	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
827920093468192768	46016762	When people who buy into Amway realize they won't be millionaires, you get @Trump_Regrets.	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
827626029346729984	14893345	Because fuck it, it’s Friday: Colby Keller, a “Communist” (?!?) best (and only) known for being naked on camera, continues to support Trump.	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
827616781254537216	46016762	What @SenFeinstein is doing is critical, even though it won't pass. We need legislation to codify the norms Trump h… https://t.co/lNR0joOxQs	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
829819401847181314	1711067155	RT @DavidCornDC: Why has the Russia-Trump story gone dark? Why is the DC press corps not going wild about this? https://t.co/ndJQESbXKd	45.5230621999999983	-122.676481600000002	Portland, OR	41	\N
829819400207396864	191084281	RT @DavidCornDC: Important story: Nuclear experts are freaked out by Trump's ignorance of this key treaty https://t.co/lXNaAY617k via @Moth…	40.7629123000000035	-73.9558291000000025	Rockefeller University	47	\N
829819399754248193	2286053444	RT @JoyAnnReid: Especially on the same day details of Trump's Putin phone call leaked. And while a Putin challenger lies comatose due to pr…	35.0853335999999985	-106.605553400000005	Albuquerque nm 	48	\N
829820747598147587	893479800	RT @SenSanders: Congress must not allow President Trump to unleash a dangerous and costly nuclear arms race.	51.2537749999999974	-85.3232138999999989	Ontario	49	\N
829820747354927105	216851245	@lifesnotPhayre And he's probably not going because Gisele is vehemently against Trump and is most likely taking her advice	0	0	Wherever life takes me	0	\N
829820746776137733	20982317	The true story of how Teen Vogue got mad, got woke, and began terrifying men like Donald Trump https://t.co/20D9LJAA49 via @qz	56.4906712000000013	-4.20264579999999999	Scotland	51	\N
829820746662866944	2331405372	RT @Phil_Lewis_: He actually said: 'If there is a silver lining in this shit, it's that people of all walks of life are uniting together (a…	0	0	hoeverywhere	0	\N
829820745949777920	1692174140	RT @CR: The full case for why courts have no jurisdiction over Trump's immigration order https://t.co/9uqGmzmn9o	40.7127837000000028	-74.0059413000000035	NEW YORK USA	52	\N
829820745941266432	2929865768	RT @Cosmopolitan: Parents Outraged After Trump Falsely Claims Their Daughter Was Killed in a Terrorist Attack https://t.co/eNjCotnj7M https…	35.6894874999999985	139.691706399999987	Tokyo, Japan	53	\N
829820744817328129	1390667438	@POTUS racist people always want to be around their racist friends. Trump give racist racist and hypocrite people voice . Now it's your turn	39.9611755000000031	-82.9987942000000061	Columbus, OH	57	\N
829820744590778368	201083416	RT @PostRoz: Chaffetz/Cummings say Trump has "inherent conflict" in disciplining Conway over promotion of his daughter's business, ask OGE…	42.2808256	-83.7430377999999962	Ann Arbor, MI	58	\N
829820744410468352	25375647	RT @nprpolitics: #BreakingNews: The 9th Circuit Court of Appeals announced it will rule on the stay of President Trump's executive order to…	42.3600824999999972	-71.0588800999999961	Boston 	59	\N
829820744062234624	153488703	@We_R_TheMedia @CBSNews @ScottPelley is a liar. He goes on air and states Trump's opinion is false. Then says 24% of attacks weren't covered	40.7127837000000028	-74.0059413000000035	NYC	60	\N
829820743366029315	16919818	RT @docrocktex26: Being GOP Speaker in the midst of this Trump "led" clusterfuck is a career ender. Paul Ryan's got spray tan all over his…	36.7782610000000005	-119.417932399999998	California	61	\N
829820742380421124	806862164459974662	LIBERAL LUNATIC: Wife leaves husband of 22 years because he voted for Donald Trump https://t.co/V33egQA0RY	42.8864468000000016	-78.8783688999999981	Buffalo, NY	62	\N
829820742279782401	3052159982	RT @adamrsweet: little did Donald Trump realize the Mexicans had devised crafty plan to get past his wall https://t.co/IO49m4Foje	42.9489154999999982	-70.7917235999999974	Hampton, NH and Keene, NH	63	\N
829820742078435328	4072327265	Donald Trump I want to know how the hell Russia hacked the American election,and dammit I want details appoint special prosecutor.	42.4072107000000003	-71.3824374000000006	Massachusetts, USA	64	\N
829820735120093185	22882829	RT @baratunde: Today's Republican Party is being exposed as true cowards. They repeatedly choose to stand with Trump against their own repu…	42.6525792999999993	-73.7562317000000007	Albany, NY	79	\N
829820734973292548	19252402	RT @owillis: people in the white house are leaking to AP on trump and if he wasn't an odious monster it would be sad. but LOL https://t.co/…	19.4258027999999996	-99.1595386000000047	MexCity	80	\N
829820734134419456	798195374787739649	TARGETING TRUMP: Iran Threatens To Bomb U.S. Base In Bahrain If America Makes A “Mistake” https://t.co/EGboYavz9x	40.7127837000000028	-74.0059413000000035	Nueva York, USA	81	\N
829820733752619008	320132071	Trump is just speeding up the process to WW3. Its bound to happen eventually	47.7510740999999967	-120.740138599999995	Washington, USA	82	\N
829820733714993153	780601021928046593	RT @nicklocking: The Trump family is Mandelbrot Shittiness. You can keep looking deeper and things just keep getting shittier. https://t.co…	44.3148442999999972	-85.602364300000005	Michigan, USA	83	\N
829820733673107461	824298716710445057	RT @thegarance: Trump Hotel Washington DC cocktail server job posting says "proficiency in other languages would be an asset." https://t.co…	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
829820732007907328	52319005	RT @MiekeEoyang: Trump about to send ISIS detainees to GTMO. https://t.co/f8cShJlN8J	0	0	beyond time and space	0	\N
829820731961835523	82124296	RT @realDonaldTrump: 'Majority in Leading EU Nations Support Trump-Style Travel Ban' \nPoll of more than 10,000 people in 10 countries...htt…	51.418338900000002	-0.220628800000000014	Wimbledon	85	\N
829820731924107264	713392368607567873	RT @rollingitout: It's been cheaper to do biz w/ "Made In China" bc prev bad deals USA made but Trump will be changing that &amp; back to #Made…	35.4818270000000027	-120.664748000000003	Lived in California & Maryland	86	\N
829820731634700290	160984682	RT @anyaparampil: Iran tests defensive missile. Media: IRAN IS TESTING TRUMP. QUESTIONABLE TIMING?\n\nIsrael bombs civilians. Media: silent.…	51.5073508999999987	-0.127758299999999991	London, UK	87	\N
829820731592699906	29045665	RT @LouDobbs: Poll: Americans Trust @realDonaldTrump Administration More Than News Media https://t.co/4BJua9Ohgr #MAGA #TrumpTrain @POTUS #…	37.8393331999999987	-84.2700178999999991	Kentucky, USA	88	\N
829820730980327428	804886459480162304	RT @_News_Trump: 🇺🇸 @usa_news_24 👈 Anna Wintour Says Despite Politics, Melania Trump Will Appear in Vogue https://t.co/uXnlHJ0Jcy 👈 see her…	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
829820730384605184	710903460934254592	RT @TEN_GOP: The left has fiercely attacked Melania and Ivanka Trump, Kellyanne Conway and Betsy DeVos.The way they treat women is disgusti…	36.7782610000000005	-119.417932399999998	California, USA	71	\N
829820730317631488	44414983	@6abc @TomWellborn And trump bitching about it via tweets shortly after. Terrible! Unfair! Bad! Failing!	43.7844397000000001	-88.7878678000000008	Wisconsin, USA	91	\N
829820729508110336	2207421134	Twitter Melts Down After Trump Tweets About “EASY D” https://t.co/4e5wC9Uui7 #EasyD makes sense to me	46.7866719000000018	-92.1004851999999943	Duluth, MN	92	\N
829820728702701568	27592328	RT @bannerite: Everyday news outlets are talking about Nordstrom they aren't talking about Russian interference in our election or Trump's…	0	0	www.facebook.com/jennaleetv	0	\N
829820728643956736	1024142564	RT @BraddJaffy: Sen. John McCain statement — responding to President Trump's tweet saying McCain should not be talking about success/failur…	34.0522342000000009	-118.243684900000005	City of Angels 	93	\N
829820727599697920	17050594	BREAKING: A Federal Appeals Court appears ready to issue its ruling on @POTUS Trump's travel ban.  @WGNNews will have it asap.	41.8781135999999989	-87.6297981999999962	Chicago	94	\N
829820727540985856	24702792	RT @DavidCornDC: House Democrats finally take bold action on the Trump-Russia scandal. https://t.co/GN7H4xtJjr https://t.co/zUp0h85JkM	40.8294277999999977	-73.8696819999999974	The Noble Kingdom of Bronx	95	\N
829820726601510913	56165695	RT @Rocky1542: Why is #trump berating #Nordstrom when he can go after this shoddy company for making it's crap in China? #NotMyPresidentTru…	52.2545225000000002	-2.26683820000000003	Worcestershire UK	96	\N
829820726169436161	808027656507846657	RT @NYMag: Like a nice white pantsuit, or a newspaper tote bag, or a pair of boys’ gloves (size small) https://t.co/iqYCRDgGnI	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
829820725447925760	823647182389592064	RT @katiecouric: .@SenWarren on Trump's cabinet nominees: "You bet I'm going to be in here fighting." https://t.co/F0L6JOSkTY https://t.co/…	33.8703596000000005	-117.924296600000005	Fullerton, CA	97	\N
829820724596572161	766691948082192384	@TheViewExchange @BraddJaffy @donnabrazile love these little Russian troll trump lovers. Please, everyone, block them &amp; silence their voices	40.1483768000000012	-89.364818299999996	Lincoln, IL	98	\N
829820724592439297	807426616578179072	TARGETING TRUMP: Iran Threatens To Bomb U.S. Base In Bahrain If America Makes A “Mistake” https://t.co/wqjyt3xNFG	40.0583237999999966	-74.4056611999999973	New Jersey, USA	68	\N
829820723728367616	26237341	RT @CNNSitRoom: Former spy chief Clapper says he's not aware of any intelligence necessitating Trump's ban https://t.co/P4UTOqUQaG https://…	40.4406248000000019	-79.9958864000000034	Pittsburgh, PA	99	\N
829820722956492800	790601488599027713	Sen. Tim Scott: Liberal Left Activists ‘Do not Want To Be Tolerant’ https://t.co/ODqqMJTbzm https://t.co/GRc43sFWDP	40.2671940999999975	-86.1349019000000027	Indiana, USA	100	\N
829820722809823235	4890902349	RT @MrJamesonNeat: 'Go Buy Ivanka's Stuff' fits right in line with the taxpayers paying the $100k hotel bill for Eric Trump's business trav…	27.9505750000000006	-82.4571775999999943	Tampa, FL	101	\N
829820722189004800	20195562	RT @ZekeJMiller: WASHINGTON (AP) - White House says Trump 'absolutely' continues to support adviser Conway after she promoted Ivanka Trump…	40.7127837000000028	-74.0059413000000035	NYC	60	\N
829820721941581825	53850908	RT @SInow: Five Patriots say they won't visit President Trump at the White House. Here’s why: https://t.co/I5R8wjk1dg https://t.co/jfBLSOif…	44.9777529999999999	-93.2650107999999989	Minneapolis, MN	102	\N
829820721908088832	21859714	RT @DavidCornDC: Why has the Russia-Trump story gone dark? Why is the DC press corps not going wild about this? https://t.co/ndJQESbXKd	50.0660719999999984	1.38928699999999994	Mers les Bains	103	\N
829820721908084736	20779058	Sirius XM: Stop profiting off of white extremism and cut all ties with Steve Bannon! @SiriusXM https://t.co/we42ajOPt5	39.9306677000000008	-75.3201877999999994	Springfield, PA	104	\N
829820721857753088	828265399582126080	@CassandraRules Well if you attack trump you get a pass from the media on taking bribes, supporting Al Queda, treason...	55.7520232999999976	37.6174993999999998	Kremlin	105	\N
829820721291460617	17049899	Won't be surprised if Trump replaces the orig immigration order with a new one... today.... if the orig is put on hold.	30.2671530000000004	-97.743060799999995	Austin, TX	106	\N
829858465296347136	3122188727	RT @chelseahandler: Trump says he hasn’t had one call complaining about the Dakota Access Pipeline. He must have T-Mobile.	41.2033216000000024	-77.1945247000000023	Pennsylvania, USA	107	\N
829858465266941955	820752617047461890	RT @DrJillStein: Appeals court decision makes America great again! Rejects bid to resume Trump's Muslim ban. #NoMuslimBan	35.2468203999999972	-91.7336846000000037	Searcy, AR	108	\N
829858465178718208	26016523	RT @JoyAnnReid: .@CNN is reporting that at least one of the appeals court judges hearing Trump's travel ban case has needed extra security…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
829858464956563457	3301022112	RT @thehill: GOP senator blasts "notoriously left-wing court" after Trump ruling https://t.co/FTbGNS2oel https://t.co/f090LU3Ooh	37.0902400000000014	-95.7128909999999991	USA	56	\N
829858464868360192	75081190	RT @KurtSchlichter: It's adorable liberals think getting a court to force the US to admit people from dangerous countries is going to make…	36.7782610000000005	-119.417932399999998	California	61	\N
829858464771878912	19563077	@DrMartyFox Trump failed to provide EVIDENCE of either a threat or this as a solution. Minimal threat doesn't NOT trigger MASSIVE solution	32.6858853000000025	-117.183089100000004	Coronado/San Diego	109	\N
829858464679616512	805222807491801088	Hillary taunts Trump after appeals court immigration ruling https://t.co/S2IV6nZVZ9 https://t.co/w32yD5n64a	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
829858464063188994	879506898	RT @SenSanders: Hopefully, this ruling teaches President Trump a lesson in American history and how our democracy is supposed to work here…	48.8566140000000004	2.35222189999999998	Paris	110	\N
829858463975038977	73511238	RT @iamthebagman2: Didn't he say that about the Trump University case.  Right before he wrote a $25 million dollar check? https://t.co/lRN2…	47.6062094999999985	-122.332070799999997	Seattle	111	\N
829858463853453313	377135976	RT @summersash26: A message from Sally Yates ...to Trump #9thCircuit https://t.co/bXeuyYHPgN	42.6766695999999968	-71.4244223999999974	Tyngsboro, MA	112	\N
829858463547260930	1158286658	Appeals Court Refuses to Reinstate President Trump’s Travel Ban https://t.co/eBk5JKong4 https://t.co/aCjNBWZLrw	35.0456296999999992	-85.3096800999999942	Chattanooga, TN	113	\N
829858463186567168	2345400449	RT @DRUDGE_REPORT: BUCHANAN: TRUMP MUST BREAK JUDICIAL POWER... https://t.co/eJCk8ECUn9	36.1626637999999971	-86.7816016000000019	Nashville, TN 	114	\N
829858463039754240	1628768906	Bush administration lawyer John Yoo says Trump lost because executive order was haphazard and rushed https://t.co/Wrv3qFpBC9	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
829858462825869312	817447266134933504	RT @NBCNews: Jason Chaffetz: Kellyanne Conway's statements about Ivanka Trump fashion line "appear to violate federal ethics regulations" h…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
829858462746152962	821167149985263617	RT @TheRussky: Should we forward this to Trump? #notmypresident #democracy #trump  https://t.co/2L3fzAewoB	51.1656910000000025	10.4515259999999994	Deutschland	116	\N
829858462590967808	216894455	RT @sibylrites: Under the #9thCircuit interpretation of federal law if Mexico's armed forces invaded the southwest Trump wouldn't be allowe…	0	0	~ @TalesofSpritza	0	\N
834541252980772864	382514964	This made me LOL no really. Let's support magical resistance https://t.co/wKzXB3ymDY	47.6062094999999985	-122.332070799999997	Seattle, WA	139	\N
829858462570074112	211565054	RT @ekorin: @theplumlinegs So… not only did they uphold the prior court’s decision, but also noted Trump’s words could constitute discrimin…	37.7885056000000006	-122.443542899999997	The Future	117	\N
829858462565822464	35526494	RT @SenSanders: Hopefully this ruling against Trump’s immigration ban will restore some of the damage he's done to our nation's reputation…	41.9343246999999977	-88.7760937000000041	Northern Illinois	118	\N
829858462381199360	190070914	RT @marcushjohnson: Trump lost the popular vote, he lost the Muslim Ban, and he has the lowest new President approvals ever. So much losing…	33.4355977000000024	-112.349602099999998	Avondale, AZ	119	\N
829858462108618753	17467736	RT @DavidColeACLU: I guess that's three more "so-called judges," huh Pres. Trump?	42.2808256	-83.7430377999999962	Ann Arbor, MI	58	\N
829858462100099072	2710763978	.@Keith_B94 @imkwazy @HAGOODMANAUTHOR No, I don't think they've referenced "Fucktard v. Trump", but I'll look into it.	47.7510740999999967	-120.740138599999995	Washington, USA	82	\N
829858461940846593	2922327491	RT @DanRather: Court ruling against President Trump is a learning moment for Americans &amp; for the world about our system of checks and balan…	41.0256101000000015	-81.7298518999999999	Wadsworth, Ohio	120	\N
829858460615335936	33564741	RT @MichaelMathes: 9th Circuit immigration ruling is unanimous 3-0 against Trump -- and a lesson on constitutional law. https://t.co/A6aZsv…	37.3874739999999974	-122.0575434	Silicon Valley	126	\N
829858460556738561	2957145632	RT @AC360: "See you in court," Trump tweets after court rules 3-0 against travel ban https://t.co/wBAKLXLJvr https://t.co/tETGEiJzMr	30.3753209999999996	69.3451160000000044	Pakistan	127	\N
829858460309266432	798890670	RT @C_Coolidge: Survey has 4 questions. Dr. Stein &amp; Gov Johnson are in the 4th question. Mrs. Clinton &amp; Mr. Trump are in all 4. https://t.c…	29.4241218999999994	-98.4936282000000034	San Antonio	128	\N
829858460225388545	17397658	RT @NBCNews: Listen to audio of President Trump reacting to appeals court ruling against reinstating his travel ban executive order. via @K…	41.0450670000000031	-81.4373480000000001	verified account	129	\N
829858459982114818	285330317	RT @mmfa: Trump administration forced cable news outlets to use state television to cover Jeff Sessions' swearing-in ceremony: https://t.co…	28.5383354999999987	-81.3792365000000046	Orlando, FL	130	\N
829858459789119489	84449303	RT @MaxineWaters: The Mysterious Disappearance of the Biggest Scandal in Washington https://t.co/2rHL2nSkmD via @motherjones	0	0	Los Angeles from Chicago	0	\N
829858459768201216	3327332779	@realDonaldTrump Just like you said Mr. Trump, "we are a nation of laws ".	39.0911161000000007	-94.4155068000000028	Independence, MO	131	\N
829858459554287617	27656610	RT @thinkprogress: Jason Chaffetz uses meeting with Trump to promote disposal of public lands\nhttps://t.co/74pvHm8P0r https://t.co/ikxYv87H…	42.0697509000000025	-87.7878407999999979	Glenview, IL	132	\N
829858459403300864	818401433305436160	@realDonaldTrump @MrTommyCampbell \n\nAnyone who is Truly on The Trump Team should know why he is obligated to Retweet this poll. \n\n#MAGA	40.7830603000000025	-73.9712487999999979	Manhattan, NY	133	\N
829858459365564421	783480283983073280	RT @Catalinapby1: @KingAJ40 @POTUS @realDonaldTrump President Trump.  Please do not back down from these corrupt judges.  They stand agains…	37.0902400000000014	-95.7128909999999991	United States	44	\N
829858459164221441	375695229	@SenSchumer We DO NOT want to see you working with trump. We want to see you work and ensure that he fails. He is evil. Do not forget that.	40.7282239000000033	-73.7948516000000012	Queens, NY	134	\N
829858459097128962	228399021	RT @AltNatParkSer: Remember when Kelly Ann Conway actually spoke the TRUTH about Trump? \n\n•Credit: @OccupyDemocrats.• https://t.co/tk2dGX4T…	40.6331248999999985	-89.3985282999999953	Illinois	135	\N
829858458866425858	68082607	"SEE YOU IN COURT": Trump defiant after appeals court ruled against reinstating his... https://t.co/1O9Sn501oM by #cnnbrk via @c0nvey	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
829858458648375296	246452808	RT @mitchellvii: Trump has actually maneuvered the Democrats into standing up for terrorism.  They actually think they've won.  Lol, fools!	41.0700077999999991	-75.4344727000000006	Poconos PA	136	\N
829858458585407489	24173738	RT @ResistanceParty: 🚨9th Circuit Court of Appeals ruled against Trump on Immigration Order.🚨\nThe rule of Law wins!\n\n#TheResistance	37.7636865999999998	-122.429033500000003	Reality 	137	\N
829858458535092224	1628768906	Trump shows some interest in a dead immigration bill — the one Republicans killed https://t.co/03XiMPcFif	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
829858458472157184	742132138280026112	RT @NPR: A federal appeals court has unanimously rejected a Trump administration request allow its travel ban to take effect\n\nhttps://t.co/…	37.0902400000000014	-95.7128909999999991	United States	44	\N
829858458413326336	711924773115338752	RT @CNNPolitics: The legal drama over the ban is the first episode in what may be a series of challenges to Trump's governing style https:/…	40.7830603000000025	-73.9712487999999979	Manhattan, NY	133	\N
829858458233036801	2345831702	RT @DavidCornDC: Why has the Russia-Trump story gone dark? Why is the DC press corps not going wild about this? https://t.co/ndJQESbXKd	36.7782610000000005	-119.417932399999998	California, USA	71	\N
829858457964670977	787774580	RT @CNNPolitics: The legal drama over the ban is the first episode in what may be a series of challenges to Trump's governing style https:/…	48.1351252999999986	11.5819805999999996	München	138	\N
829858457750679552	50184074	Appeals court deals yet another blow to DT's travel ban targeting Muslims https://t.co/fXkLdgsZtq #Trump &amp; #presidentBannon ready to bite	47.6062094999999985	-122.332070799999997	Seattle, WA	139	\N
829858457645838336	800762110720380928	🇺🇸 @usa_news_24 👈  Plots and wiretaps: Jakarta poll exposes proxy war for presidency https://t.co/R5euPYp17V https://t.co/gJ2wc0i08L	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
829858457415274496	14196754	Trump Focuses on Aviation Infrastructure Woes During Meeting With US Airline CEOs. https://t.co/hWCR7dIvai https://t.co/BM6k54Avrm	25.7616797999999996	-80.1917901999999998	Miami, FL	141	\N
829858456555364353	796823922310258689	Trump questioning our system of checks and balances has consequences #NoBanNoWall #WeWillPersist https://t.co/LscAEy6r3p	42.2808256	-83.7430377999999962	Tree Town, USA	142	\N
829858456303706113	747937979704950784	RT @NewYorker: On some days, Trump comes across like Frank Costanza—a crotchety old guy from Queens railing at the world. https://t.co/BETH…	42.4072107000000003	-71.3824374000000006	Massachusetts, USA	64	\N
829858456207257600	72215771	RT @NPR: A federal appeals court has unanimously rejected a Trump administration request allow its travel ban to take effect\n\nhttps://t.co/…	27.9834776000000005	-82.5370781000000022	Long Island/Tampa	143	\N
829858455817162753	22950604	RT @ChrisJZullo: Donald Trump says 9th circuit is putting the security of our nation at stake but more Americans died by armed toddlers tha…	40.0583237999999966	-74.4056611999999973	New Jersey	144	\N
829858455586500608	4777661	@M_Araneo_Reddy Thanks. Most of the black conservative opposition to Trump I've seen has been Baptist, but I'll look into it.	40.7127837000000028	-74.0059413000000035	New York City	145	\N
829858455468978176	15877389	@wilw AND GO TO TRUMP UNIVERSITY TO GET A DOCTORATE IN #ALTERNATIVEFACTS!	51.0486150999999992	-114.070845899999995	Calgary, AB	146	\N
829858455452147713	764630419	@lizziekatje @BogusPotusTrump @puppymnkey Travel ban denied!! Impeach his royal Trump tard!	37.0902400000000014	-95.7128909999999991	United States	44	\N
831328716340883457	51620543	RT @Enrique_Acevedo: The Obama way vs. the Trump way of handling an international crisis. No judgment, just facts. https://t.co/nV5y2UAKPD	37.8715925999999996	-122.272746999999995	Berkeley, CA	153	\N
831328715321716736	374087169	Seattle judge set to move forward on Trump immigration case https://t.co/z39siGstce https://t.co/MAZgOVWCWx	37.0902400000000014	-95.7128909999999991	United States	44	\N
831328712855478272	498164010	RT @samueloakford: Mar-a-Lago member who pays Trump hundreds of thousands of dollars posts pics of - and identifies - US official carrying…	50.4625249999999994	-115.988646099999997	Windermere BC Canada	155	\N
831328712415014912	803034243395788800	RT @MousseauJim: Hahaha. The liberal propagandists at CTV hard at work trying to make Canadians think that Trump is afraid of Trudeau. Moro…	51.5199009000000032	-118.093514099999993	Columbia-Shuswap, British Columbia	156	\N
831328712293507072	735297696982925312	RT @activist360: Canadians have Trudeau and we're stuck w/ nimrod narcissist Trump — an habitually lying, 280 pound bigoted blob of orange…	44.3148442999999972	-85.6023642999999907	Michigan, USA	83	\N
831328712171876353	2151999774	RT @eosnos: Every Trump visit to Mar-a-Lago reportedly costs taxpayers $3+ million. If he keeps up current pace, public will pay $15+millio…	0	0	northside OKC  DTX	0	\N
831328712134098945	274089351	RT @Boothie68: Haunt Trump for us Liam https://t.co/7TMYYeQQ8M	43.038902499999999	-87.9064735999999982	Milwaukee, Wisconsin, USA	157	\N
831328711895085056	823208313374601217	lol...so Comic Nonsense News is trying to stir trouble among celebrities now?  lol  Did they run out of Trump issue… https://t.co/Gda8tPtQ3b	35.5174913000000032	-86.580447300000003	East Tennessee	158	\N
831328711739863041	385771776	RT @JoyAnnReid: Again, Trump was headed to Ohio, which he won, to celebrate signing a bill that will allow coal companies to pollute his vo…	37.7719992000000033	-122.411003100000002	Flux	159	\N
831328711723143168	703990775223169025	RT @votedforthe45th: Trump loses his first negotiation, Trudeau heads back to Canada without Rosie, Whoopi, Miley or any other deportables…	37.0902400000000014	-95.7128909999999991	USA	56	\N
831328711689515008	3394909000	RT @DanEggenWPost: 2/x\nMar-a-Lago snafus: \nhttps://t.co/AsDbJsasHa\nTrump acting the part: \nhttps://t.co/ARgUetY0ai\nPuzder woes: \nhttps://t.…	-9.18996699999999933	-75.0151520000000005	Peru	160	\N
831328710456401922	44416770	RT @RawStory: CNN host hands Trump adviser his ass: ‘Nine cases does not rampant widespread voter fraud make’ https://t.co/OkSwKFSgR3 https…	49.2827290999999974	-123.120737500000004	Vancouver, BC 	161	\N
831328706614403075	103760972	RT @molly_knight: WaPo bombshell: Sally Yates warned Trump that Flynn was likely compromised by Russia. She was fired days later. https://t…	38.2526646999999969	-85.758455699999999	Louisville, KY	168	\N
831328706572537856	796701900443975680	RT @thehill: Dem demands Trump release transcripts of Flynn calls with Russia’s ambassador https://t.co/MUbolha5gH https://t.co/jshtzs741j	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
831328706362798081	618669870	RT @PTSantilli: Of all people, Moby has the scoop on Trump https://t.co/lyiX2iENOc	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
831328706199244804	3065244365	RT @D100Radio: Senate confirms Trump's picks for Treasury, VA secretaries - Treasury Secretary Steven Mnuchin: 3 things to know https://t.c…	0	0	dostthoutennis@gmail.com	0	\N
831328706165604355	88374158	Moby--yes THAT Moby--says he has knowledge that the Trump dossier is all real, and then some. https://t.co/SAxkJHvbWr	40.7830603000000025	-73.9712487999999979	Manhattan	169	\N
831328706073288704	539595746	RT @jbendery: Reporters just shouted questions about Flynn as Trump walked out. Ignored, of course.	28.3721652999999989	-80.6676338999999984	"Coastal elite" 	170	\N
831328705846849537	187897675	RT @andylassner: Flynn story can bring down Trump. If Flynn's pushed out he'll talk. If he's kept, press will persist and we'll know what R…	39.9783710000000028	-86.1180434999999989	Carmel, IN	171	\N
831328704030720000	22319726	I finally found a bigger conundrum than how Trump got elected: \nWhat the fuck is @Sen_JoeManchin’s problem?\n#FakeDemocrat	42.2156130999999988	-79.8342162999999942	NE Pennsylvania	177	\N
831328703787458560	66066411	RT @EWDolan: Yale historian warns America only has a year — maybe less — to save the republic from Trump https://t.co/sYXENhXGoZ	0	0	EARTH as often as Possible!	0	\N
831328703774875648	41263392	RT @mlcalderone: Omarosa threatened @AprilDRyan, saying Trump officials had dossiers on her and several African American journalists: https…	42.3875967999999972	-71.0994967999999972	Somerville, MA	178	\N
831328703581929473	67364035	RT @PalmerReport: Sally Yates tried to warn Donald Trump about Michael Flynn and Russia before he fired her https://t.co/INVTcHH5xq	39.9504811999999987	-86.2414964999999967	rural zionsville, indiana	179	\N
831328703456100352	15102878	RT @mlcalderone: Omarosa threatened @AprilDRyan, saying Trump officials had dossiers on her and several African American journalists: https…	41.6032207000000014	-73.0877490000000023	Connecticut, US	180	\N
831328702910787585	3044982962	Analysis | Republicans railed against Clinton’s ‘extremely careless’ behavior. Now they’ve got a Trump problem. https://t.co/cceypoc3br	35.1427533000000025	-120.641282700000005	Pismo Beach, CA	181	\N
831638779790229510	784602400497754117	RT @MMFlint: Let's be VERY clear: Flynn DID NOT make that Russian call on his own. He was INSTRUCTED to do so.He was TOLD to reassure them.…	42.2011538000000002	-85.5800021999999956	Portage, MI	297	\N
831638779769323520	784605452290158592	RT @politicususa: Paul Krugman Says Trump is a Horror but a Horror Made Possible by GOP Corruption https://t.co/uA2HqQGCZd #p2 #p2b #ctl	43.2122486000000023	-82.9896604000000053	Brown city michigan	298	\N
831638779760881666	86123044	RT @brianbeutler: Weird Trump and McGahn didn’t loop Pence in until after reporters had the story, when a simple clarification could’ve cle…	33.745851100000003	-117.826166000000001	Tustin, CA	261	\N
831638779760779264	5929252	RT @BetteMidler: Trump &amp; Trudeau discussed trade &amp; security. I’d also like to discuss it, because I would feel more secure if we traded Tru…	-27.4697707000000015	153.025123500000007	Brisbane, Australia	299	\N
831638779517603840	2312494016	RT @DRUDGE_REPORT: Archbishop says it's amazing 'how hostile press is' to Trump... https://t.co/1KlysuyR58	0	0	facebook.com/tradcatknights	0	\N
834234322215387139	464277676	RT @JuddLegum: Trump hiring freeze forces suspension of Military child care programs https://t.co/ESytpmM5ub https://t.co/94d6xEghqi	32.7554883000000032	-97.3307657999999947	Dallas/Fort Worth	312	\N
834236048360108032	276349732	RT @Mikel_Jollett: Let's be very clear: Milo was an editor at Breitbart hired by Trump's closest advisor Steve Bannon.\n\nThis hatred is in t…	36.1626637999999971	-86.7816016000000019	nashville	313	\N
834236048267898880	3679531575	RT @tedlieu: Lyin' @realDonaldTrump has made 132 false or misleading claims as @POTUS. This is NOT okay. https://t.co/TQfFtFYipB #ResistTru…	34.0489280999999977	-111.093731099999999	Arizona	314	\N
834236047684952064	824013279055859712	RT @2ALAW: Watch: What Happens When muslims Challenge Russians To A Street Style Fight.\n\nRetweet..If This Gave You Great Viewing Pleasure!👊…	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834236047508795392	19848243	RT @Lawrence: One of the conservative anti-Trump voices silenced by @FoxNews joins @TheLastWord tonight 10pm.	40.7127837000000028	-74.0059413000000035	NYC, NY	315	\N
834236047244541953	141446950	RT @LOLGOP: Took Trump hours to condemn peaceful protesters who want health care for the sick after waiting weeks to condemn antisemites.	42.3600824999999972	-71.0588800999999961	Boston	316	\N
834236046908997633	822075977857638400	RT @foxandfriends: Trump tours African-American museum, speaks out on anti-Semitism https://t.co/etISEHsMky	42.3600824999999972	-71.0588800999999961		\N	\N
834236046560727040	750440231288143872	RT @samswey: Headline today should read:\n"Trump says Anti-Semitism has to stop, doesn't present a plan to stop it."	36.1699411999999967	-115.139829599999999	Las Vegas, NV	218	\N
834242845129265153	711627609344516096	RT @JohnTrumpFanKJV: 202-224-2235\nLet's call John McCain and let him know that it is Wrong to criticize President Trump on Foreign Soil.	27.6648274000000001	-81.5157535000000024	Florida	183	\N
834242844512632832	23956022	ABOUT TIME!! BREAKING: Trump U.S. District Attorney to Pursue TREASON Charges Against Barack Obama https://t.co/2G7JPicZ31	40.7356570000000033	-74.1723666999999978	Newark, N.J.	326	\N
834242843183046656	801151532959993856	TRUMP DAILY: It’s Now Nearly Impossible to Find Donald Trump Products at Full Price #Trump https://t.co/Js32OXkkz4	35.2270869000000033	-80.8431266999999991	Charlotte, NC	325	\N
834242842914648064	703320943469445120	RT @AriaWilsonGOP: Welcome to Sweden! Here’s what happened last night . . . still want to mock Trump? https://t.co/roGwb6w4pn https://t.co/…	39.8675692999999995	-104.873008799999994	Home	327	\N
834242842893508609	206178888	@StvenGoldstein whatever your faith, u didn't represent it well on @OutFrontCNN. U do represent hate well.  Afraid Trump will help someone?	35.2010500000000022	-91.8318333999999936	Arkansas	328	\N
834242975047761920	147749076	"The Donald Trump Song"\nhttps://t.co/arA0srITxb via @sapanv @EastIndiaComedy #Resistance #TheResistance #Resist	41.1220193999999992	-73.7948516000000012	Westchester County, New York	329	\N
834242974976335875	14053295	RT @jimmyhawk9: Its becoming clear that voting for Donald Trump was an act of dereliction of one's duty as a citizen and effectively treaso…	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
834242974355750912	2188838743	@jonfavs @realDonaldTrump THIS IS AN INCREDIBLE ARTICLE. MUST READ. TRUTH IS SPEAKING. Holding Trump Accountable https://t.co/iMR5HPSicz	37.0902400000000014	-95.7128909999999991	United States	44	\N
834242974271864833	777157368316583936	RT @HamiltonElector: Journos should ask @PressSec this question at next briefing: Does Trump or any family mbr owe money to any Russian ind…	35.5174913000000032	-86.580447300000003	Tennessee, USA	330	\N
834242973911105536	27125886	RT @thehill: Official Sweden Twitter account fact-checks Trump in day-long tweetstorm: https://t.co/59jEVOOjTd https://t.co/LAkGCEMB5t	39.5500506999999999	-105.782067400000003	Colorado 	331	\N
834242973604798465	19421564	RT @AltStateDpt: Trump Russia story is increasingly sordid &amp; building. It will be interesting to see who breaks first.\n\n#KeepResisting http…	47.5301011000000031	-122.032619100000005	Issaquah, WA	332	\N
834242973600796672	517225657	RT @washingtonpost: "Never fjorget": Colbert mocks Trump’s Sweden flub, honors "all the people who did not suffer" https://t.co/jlN1DGaALg	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834242973541863424	818711990835232768	OOPS: Dem Official might have just committed a MASSIVE ethics violation against Trump… https://t.co/Hl7LvlHh5W https://t.co/Nj7DAj3eC5	40.7127837000000028	-74.0059413000000035	Nueva York, USA	81	\N
834242973080498181	379541912	RT @JohnTrumpFanKJV: John McCain should have fought hard against Barack Hussein.\nHe should be Supporting President Trump. \nInstead McCain d…	47.7510740999999967	-120.740138599999995	Washington State	333	\N
834242972938018816	801151532959993856	TRUMP DAILY: Fashion folk celebrate inclusivity in shadow of Brexit and Trump #Trump https://t.co/V1UMFCjUhu	35.2270869000000033	-80.8431266999999991	Charlotte, NC	325	\N
834242972862410752	3167923560	NATO to US: Yes, sir, Mr. Trump https://t.co/mBuNNlEzYC via @DCExaminer	33.9164031999999978	-118.352574799999999	Hawthorne, CA	334	\N
834242972787101697	431171274	RT @Pappiness: H.R. McMaster has earned universal praise and is known for questioning his superiors. \n\nIt's only a matter of time before Tr…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834242972514414593	480817557	RT @SenSchumer: President Trump's mass deportation plan is causing panic and is against our nation's commitment to welcoming immigrants; it…	40.7127837000000028	-74.0059413000000035	NYC	60	\N
834242972359258113	703320943469445120	RT @CollinRugg: Rioting Breaks out in Sweden.\n\nRemember days ago when the left was mocking Trump saying "Last night in Sweden"?\n\nDon't hear…	39.8675692999999995	-104.873008799999994	Home	327	\N
834242972355014656	583840465	RT @vonotnott: How can I say this politely? Oh nevermind, #FuckTrump\n\nhttps://t.co/dnBKNs2SnD	40.7127837000000028	-74.0059413000000035	New York City!	335	\N
834242972313071616	921521460	RT @jacobsoboroff: .@RepCardenas says he was excluded from ICE immigration briefing. "This administration is not about transparency." https…	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834242971688124416	912977874	RT @kylegriffin1: Trump's 1st month in office includes:\n\nGolf—25 hrs\nForeign relations—21 hrs\nTweeting—13 hrs\nIntel briefings—6 hrs\nhttps:/…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834242971633545216	579872855	3 Generals Bound by Iraq Will Guide Trump on Security - New York Times https://t.co/6tmQ5ooyjO	37.0902400000000014	-95.7128909999999991	United States	44	\N
834242970803171329	311188381	RT @Amy_Siskind: Stay on this story. If Trump was complicit in any way with hacking our election, it's a criminal act.  https://t.co/J3tVx3…	40.2671940999999975	-86.1349019000000027	Indiana, USA	100	\N
834242970639532032	3194375035	RT @jimmyfallon: Get emotional watching #ThisIsUs and get happy staying on #NBC for #FallonTonight. Milo, Will and Future and the 1st ep of…	33.4158732000000001	-82.1416980999999993	August 31st 	336	\N
834242969993695232	23035763	@MarcSnetiker @realDonaldTrump Those that resort to  name calling have already lost. I pray you will see how good Trump is soon.	30.6649118999999999	-97.9225160999999957	Liberty Hill, Texas	337	\N
834242969679040514	21680144	Reports of Trump Admin Plans to Rescind Trans Students Guidance | Human Rights Campaign https://t.co/Ea4S9pzXpw	37.0902400000000014	-95.7128909999999991	USA	56	\N
834242969184124929	819253072207745027	RT @politico: Thousands of new immigration officers could lead to a spike in deportations https://t.co/HSiEG0n6aD https://t.co/zngLLzItet	26.1420357999999986	-81.7948102999999946	Naples, FL	163	\N
834242969154756608	4926072985	RT @thehill: Fourth Republican lawmaker backs bill requiring Trump to get Congressional approval before lifting Russian sanctions https://t…	37.0902400000000014	-95.7128909999999991	USA	56	\N
834242968731136000	801151532959993856	TRUMP DAILY: Trump Somehow Found a Way to Insult Women at the Unveiling of An Airplane #Trump https://t.co/vn8c3fsQL6	35.2270869000000033	-80.8431266999999991	Charlotte, NC	325	\N
834242967883902978	602371247	RT @mmpadellan: It is my sincere wish to be the emissary of Karma, to turn EVERY rotten, hateful trump tweet or statement back on him, so h…	41.6687896999999978	-70.2962408000000067	cape cod, ma	338	\N
834242967636303872	4795375836	RT @tjm0072003: @DrJohn76533054 @mrnwright16 Any Trump Supporter that Watches Oscars Hollywood Circle Jerk is assisting the ENEMY\n#BoycottO…	46.8796821999999977	-110.362565799999999	Montana, USA	339	\N
834242967632228353	2153342610	RT @smartvalueblog: RT I believe the best Social Program is a Job. #USA #Americans #America #PJNET #NRA #2A #Trump #Cruz #Congress @GOP htt…	30.4919176000000007	-97.7240495000000067	The Great State of Texas	340	\N
834242967460265984	15397067	RT @democracynow: .@chilledasad100: Protests sweeping Britain are "an incredible rejection of Donald Trump and his agenda" https://t.co/mgz…	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
834242967435038720	83722627	RT @kylegriffin1: Trump, or someone w/ account access, continues to delete tweets—possibly violating the Presidential Records Act: https://…	44.0624879000000007	-103.146289899999999	Rapid Valley, South Dakota	341	\N
834242967049236481	763921271604195328	RT @tedlieu: More evidence from @nytimes that the failing @realDonaldTrump is lying about contacts with Russia. https://t.co/uJWYvkxVOO	56.1303660000000022	-106.346771000000004	Canada	257	\N
834245757486133249	773614050483826688	Donald J. Trump on Twitter: "The so-called angry crowds in home districts of some Republic… https://t.co/kcBil4ppki https://t.co/RoIsIMpPxr	40.7624283999999975	-73.9737939999999981	Trump Tower	364	\N
834242966877245440	761733384565616640	RT @olgaNYC1211: Seems the whole Trump team is in bed with the Kremlin and the Russian mob.. 🤦🏼‍♀️\nMust Read 👇🏼\n#Carterpage #TrumpLeaks #Tr…	41.1220193999999992	-73.7948516000000012	Westchester County, NY	342	\N
834242966231212033	579883082	Lawmakers Call on Trump to End 'Blank Check for War' - Common Dreams https://t.co/wWHstt0MFG	32.7157380000000018	-117.1610838	San Diego, CA	150	\N
834242965262462976	801151532959993856	TRUMP DAILY: The Worldwide Struggle to Translate Trump #Trump https://t.co/yn7khpEVAu	35.2270869000000033	-80.8431266999999991	Charlotte, NC	325	\N
834242964016734208	3054377702	RT @DeplorableDame: @TuckerCarlson @SunsaraTaylor @realDonaldTrump @FoxNews It's freaking lunatics like her that scare me, not Trump!	42.5424373999999972	-71.738763899999995	At home~ With my Uncle!	343	\N
834242963827929088	579870842	'Sad!': Trump goes after 'so-called angry crowds' in GOP districts - USA TODAY https://t.co/WeVDfJ5fu5	32.8686979000000008	-96.664495500000001	Hollywood, USA	344	\N
834242963463102464	829804206227730432	RT @RawStory: Military bases forced to cancel child care programs due to Trump hiring freeze https://t.co/ttzc75k1kf https://t.co/2iEeznYlEF	48.8618900000000025	2.11252700000000004	Louveciennes	345	\N
834242962821349376	2367571697	RT @kikissalon1: @scumbags please retweet @SenFranken @PrincessBravato @Impeach_D_Trump @IMPL0RABLE @funder @IMPL0RABLE @dumptrump33 https:…	39.6953969999999998	-74.2587527000000023	Manahawkin, New Jersey	346	\N
834245768923926528	32317433	RT @soledadobrien: Actually Donald Trump suggested execution for 5 young black men in Central Park jogger case. They were wrongfully convic…	33.680300299999999	-116.173894000000004	Coachella, california	347	\N
834245768462561280	16043254	RT @leahmcelrath: Reminder: \n\n1. Churkin was first invited Trump to Russia in the 1980's.\n2. U.S. is investigating Trump &amp; Russia.\n3. Putin…	37.8271784000000011	-122.291307799999998	San Francisco Bay Area	348	\N
834245767632084992	298225019	RT @DavidYankovich: According to Pew research, 71% of voters think Trump is a poor role model.\n\nThat is a failure on the most basic, human…	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834245767346860032	187694410	When Trump tweeted to Putin that he always knew he was a smart man, that was collusion! Trump knew! #impeachment https://t.co/gDQh8qpUm7	39.2496829999999974	-119.952684700000006	Incline Village, NV	349	\N
834245766608715776	4445498741	RT @LouDobbs: End Tax Free Status?  Bishop Urges Catholics to Defy @POTUS https://t.co/2IXVEVhJF6 #MAGA @realDonaldTrump #TrumpTrain #Ameri…	34.9745320000000035	-92.0165336000000025	Cabot, AR	350	\N
834245766512140289	22846618	RT @JuddLegum: The Anne Frank Center is not impressed with Trump today https://t.co/9tHcMxunSY https://t.co/ykYUoqpuAK	34.0489280999999977	-111.093731099999999	arizona	351	\N
834245765903945728	14189683	RT @ColinKahl: We have 2 governments right now. One trying to reassure anxious allies &amp; a 2nd w/Bannon at the helm doing this: https://t.co…	47.6062094999999985	-122.332070799999997	Seattle	111	\N
834245765593755649	90839118	RT @AltCaStateParks: POTUS has deep respect for the first amendment and has deep respect for the press\n-Sean Spicer\n\nThe press is the enemy…	35.7595730999999972	-79.0192997000000048	NC	352	\N
834245765337870339	861927176	Trump Attacks “So-Called Angry” Americans Worried About Losing Their Health Insurance via @politicususa https://t.co/hdbriOej23	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
834245765119799296	823042346438848512	RT @seanhannity: Liberal snowflakes are at it again... protesting President Donald Trump across the country… Find out what @THEHermanCain h…	32.3940168000000028	-99.3942435999999958	Baird,Texas	353	\N
834245764931018754	257594609	RT @Mikel_Jollett: Let's be very clear: Milo was an editor at Breitbart hired by Trump's closest advisor Steve Bannon.\n\nThis hatred is in t…	41.7942949999999982	-87.5907009999999957	Hyde Park, Chicago	354	\N
834245764364828672	2896393101	Trump has spent these last weeks rescinding rights thru Executive Orders, authorizing roundups-of people, creating chaos at airports.	30.2671530000000004	-97.743060799999995	Austin, TX	106	\N
834245764226359300	268635552	RT @ananavarro: Overheard-\n\nHim: 3 types of folks these days. Ppl who ❤ Trump; protest him; or too afraid to protest.\n\nHer: U forget those…	28.3739489999999996	-81.5518440000000027	The Land	355	\N
834245762854813696	1372962091	RT @AlwaysActions: #Paris is in total chaos, it\nlooks like a war zone. Still\nthink Trump is overreacting\nwhen he calls for a ban on\nRadical…	42.3600824999999972	-71.0588800999999961	Boston, Hub of the Universe	356	\N
834245762280222720	757318332706009088	@VanJones68 Meanwhile Cheeto 45 @realDonaldTrump Fleeces America with his Mar-A-Lago and Trump Tower trips and protection. What a fraud	40.4406248000000019	-79.9958864000000034	Pittsburgh, PA	99	\N
834245761831276544	1564878943	RT @businessinsider: Trump's lawyer has told 4 different stories about the Russia-Ukraine peace plan debacle https://t.co/VW5EU7rlCM https:…	45.5230621999999983	-122.676481600000002	Portland, Oregon	357	\N
834245761739132929	33333196	"Trump, GOP lawmakers scrap Stream Protection Rule" https://t.co/xVMgqqxMFn	44.3148442999999972	-85.602364300000005	Michigan, USA	83	\N
834245761361649664	814692955374108673	RT @DavidYankovich: #CongressCanRequest Trump's taxes.\n\n@BillPascrell is leading this charge.\n\nRT if you believe Trump's taxes should be re…	39.0997265000000027	-94.5785666999999961	Kansas City, MO	358	\N
834245761244160002	816444644712214530	@Harrison_rein @the_renee @nia4_trump @NathanDWilsonFL women and children who wear suicide vests	30.9765796999999985	-92.5851401999999979	Glenmora, Louisiana	359	\N
834245761080504320	796916008560644096	RT @nedprice: I resigned from @CIA last week. I wrote about why in the @washingtonpost:  https://t.co/HXJhRCkw3O	47.7510740999999967	-120.740138599999995	Washington, USA	82	\N
834245761038704641	769877140846370817	RT @MPlummer89: @kolin_benson We need a leader that can set this straight and get these ppl out of our country! It is treasonous!!! Let Tru…	40.6331248999999985	-89.3985282999999953	Illinois, USA	360	\N
834245760887697410	829376495277666304	RT @DevinePatriot: @SonofLiberty357 Get a load of how 'great' Sweden is!!! Retweet if you agree President Trump is once again on top of wor…	37.9642528999999982	-91.8318333999999936	Missouri, USA	195	\N
834245760799629313	1133174126	RT @truthout: Front-runner for #Trump Science Adviser Post Agreed Not to Disclose Fossil Fuel Funding https://t.co/FxMAmSFL8C #FossilFuels	39.739235800000003	-104.990251000000001	Denver, CO	361	\N
834245760250179584	26761343	Trump Gearing Up for Massive Deportation of Undocumented Migrants.https://t.co/iXhDhnfVOR #latinamerica #feedly	18.1095809999999986	-77.2975079999999934	Jamaica	362	\N
834245760229240832	355577666	RT @DavidYankovich: #CongressCanRequest Trump's taxes.\n\n@BillPascrell is leading this charge.\n\nRT if you believe Trump's taxes should be re…	51.2537749999999974	-85.3232138999999989	Ontario	49	\N
834245759851655173	265002311	'Sad!': Trump goes after 'so-called angry crowds' in GOP districts  https://t.co/zxfo97eBBs via @usatoday   following a so called president	41.8781135999999989	-87.6297981999999962	Chicago	94	\N
834245759465816064	822566327479140356	RT @washingtonpost: Anne Frank Center slams Trump: "Do not make us Jews settle for crumbs of condescension" https://t.co/qhbOpBWpFZ	39.0457548999999986	-76.6412712000000056	Maryland, USA	234	\N
834245759293865985	80630645	RT @travishelwig: When Trump won, did you vow to "STAY ENGAGED?" Well, today is the LAST DAY to register for LA's March 7th elections: http…	40.7127837000000028	-74.0059413000000035	nyc	363	\N
834245757737644033	804681935507230722	If anyone is Hitler like, it's the left. Trump supports Isreal &amp; the Jewish people. Hitler supported Muslims because they hated Jews.	37.0902400000000014	-95.7128909999999991	USA	56	\N
834246565409665024	3023037872	The Mistake We Make When We Think About Donald Trump - TIME https://t.co/WQhTk7heEm	37.0902400000000014	-95.7128909999999991	United States	44	\N
834245757473546240	2744936164	RT @FoxNews: "[@POTUS] is more dangerous than Hitler ever could have been." @RefuseFascism organizer talks to @TuckerCarlson https://t.co/v…	51.2537749999999974	-85.3232138999999989	Ontario, Canada	252	\N
834245757473529856	2943845715	RT @JordanUhl: Trump at Inauguration: "We're giving government back to you, the people."\n\nTrump today: https://t.co/nnI3LDQmnY	41.6032207000000014	-73.0877490000000023	Connecticut, USA	365	\N
834245757045583872	862495562	RT @BroderickGreer: Notice that Trump is never in the company of mainstream black intellectuals, activists, or civic leaders https://t.co/u…	39.739235800000003	-104.990251000000001	Denver	223	\N
834245756076781568	16350758	BREAKING: TRUMP'S AMERICA IS OVER! JANET YELLEN IS ABOUT TO DO SOMETHING... https://t.co/nm2G5YYH8p	34.5794343000000026	-118.116461299999997	Palmdale, CA	366	\N
834245755653259269	839040121	Trump's words are a band-aid after refusing day after day to apologize. - Anne Frank Center	40.0583237999999966	-74.4056611999999973	New Jersey, USA	68	\N
834245755649064961	136655165	RT @TomSteyer: Donald Trump, who paid $25 million to settle a fraud lawsuit, wants to deport people for traffic tickets. https://t.co/37o68…	38.6392200000000017	-90.2316789999999997	left of centerstage	367	\N
834245755632283651	136655165	RT @CharlesMBlow: This Trump admin is a cancer on this nation. Don't try to convince me otherwise. Your efforts are futile, and my convicti…	38.6392200000000017	-90.2316789999999997	left of centerstage	367	\N
834245755531558912	736292033728512000	RT @NAFSA: "The US travel ban would be bad news for American universities" https://t.co/Y54J5eidFm (via @guardian)	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834245755434983424	199601800	RT @MaxineWaters: Trump cannot assure us no one on his team communicated w/ Russia last year. What does he know? Where are his taxes? #krem…	36.7782610000000005	-119.417932399999998	California	61	\N
834245755137306624	39880958	@seanhannity @cnn @FoxNews remember the gunman who was taken down by Secret Service at Trump rally while they rushed Trump off the stage	46.7295530000000028	-94.6858998000000014	MN	368	\N
834245754755616773	50741632	Retweeted Washington Post (@washingtonpost):\n\nTrump’s deputy national security adviser was once accused of... https://t.co/LfjmGcEvXS	34.2331373000000028	-102.410749300000006	EARTH	369	\N
834245754675949570	221568800	RT @ProgressOutlook: Trump's political staff will review EPA scientific findings before making them public. Looming authoritarian censorshi…	35.9606384000000006	-83.9207391999999999	Knoxville, TN, USA	370	\N
834245754055180289	3317657956	RT @RealAlexJones: Infowars is under attack we will NOT be defeated!  https://t.co/JqCKuSI416 …  -  https://t.co/mcGvOTX1Cj …  #USA #censor…	39.781721300000001	-89.6501480999999956	Springfield IL	371	\N
834245753639927808	1276407132	RT @immigrant4trump: Video: Don Lemon Argues That Sweden’s 50 Percent Surge in Rape is Not ‘Skyrocketing’ #Maga #Trump https://t.co/ktxjSjI…	41.8873607000000021	-87.6184065000000061	 East coast 	372	\N
834245753275052032	97459853	Protesters Ready for Trump’s First Visit to New York as President, via @nytimes https://t.co/TfDjxqQIkc	44.9777529999999999	-93.2650107999999989	Minneapolis, MN	102	\N
834245752654278658	2442212562	RT @AndreaChalupa: Indie movie theaters nationwide to protest Trump by screening "1984" https://t.co/TUWxWmDIyV	37.0902400000000014	-95.7128909999999991	USA	56	\N
834245752599650305	380769970	RT @RawStory: Ivanka Trump hit with lien in New York for failure to pay taxes on her high end jewelry business https://t.co/5CtzDUXpT8 http…	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834245752557760512	9790012	RT @IMPL0RABLE: #TheResistance\n\n💥PRIORITIES💥\n\n1⃣️ Impeach Trump &amp; Pence.\n2⃣️ Investigate GOP for Russian ties.\n3⃣️ Declare election invalid…	36.8108300000000028	-119.883889999999994	Highway City, CA	373	\N
834245752423604229	111934563	@aseitzwald Trump would rip him apart	44.9777529999999999	-93.2650107999999989	Minneapolis, MN	102	\N
834245751169392640	242954420	RT @yottapoint: In just 1 month, Trump has cost taxpayers over 1/10th of Obama's entire 8-year travel expense https://t.co/8szRlrtGIj	40.7294175999999979	-73.9837677999999954	Islamic States of America	374	\N
834245751085621248	465724115	RT @SocialMedia411: Trump's first month: Golf - 25 hours. Tweeting - 13 hours. Intel briefings - 6 hours.  https://t.co/vUkPN2MFkd	41.323281999999999	-71.8037269000000009	Misquamicut, RI	375	\N
834245750896939012	3685449739	@VanJones68 Make it your goal to report at least one illegal alien. Together we can defeat illegal immigration!\n\nICE: 1-866-347-2423\n\n#Trump	34.2331373000000028	-102.410749300000006	earth	376	\N
834245749768609792	55265262	'Thank you, Jesus': What new NSA pick says about Trump https://t.co/nZG9JQOsY2 via @msnbc WOW, great review on #MSNBC #Shocking	40.6342489000000029	-74.5004796000000056	Warren, New Jersey	377	\N
834245749407903744	57578695	RT @SavageNation: RT CassandraRules: Notorious ‘Never Trump’ Org Funded Group Behind Milo Controversy https://t.co/HTrBhcfdyx	41.8873889999999989	-87.7656499999999937	Central WI	378	\N
834245749223387141	28135772	@Lawrence Good point ... The appointment of general McMaster may well clip the wings of Steve Bannon ... Till Trump gets a brain itch 😕😳🙈gah	31.9685987999999988	-99.9018130999999983	TEXAS	379	\N
834245748313169920	1220921700	RT @tonyposnanski: So if it is true that the people opposing town halls are "paid liberals"\n\nThat would mean Clinton is bringing more jobs…	39.9611755000000031	-82.9987942000000061	Columbus, OH	57	\N
834245748145397761	42403615	RT @kylegriffin1: 33 days.\n\n132 false or misleading claims from Trump.\n\n0 days without a false statement https://t.co/24V21Vw2Mw\nhttps://t.…	38.8048355000000029	-77.0469214000000022	Alexandria, Virginia	380	\N
834245748053139456	250131859	RT @seanhannity: The liberal media is now claiming Pres Trump will cause violence for daring to call them out... @CLewandowski_ and @BoDiet…	40.7127837000000028	-74.0059413000000035	NY 	191	\N
834245745255579651	2300674015	@StefanMolyneux\n\n🚨BREAKING: Infowars getting censored thru AdRoll ban.\n(~$5M Rev)\n\nAccess to info is killing left.\nhttps://t.co/XCmjE4D9mK	32.776664199999999	-96.7969879000000049	Dallas, TX	267	\N
834245744727056384	66033904	RT @smartvalueblog: RT Arrest &amp; Abolish these Anti-American Racist Hate Groups. #USA #Americans #PJNET #NRA #Trump #Cruz #Congress @GOP htt…	37.0902400000000014	-95.7128909999999991	USA	56	\N
834245744097849344	50741632	RT @washingtonpost: Trump’s deputy national security adviser was once accused of violating voter registration laws https://t.co/LAL3dtwkxc	34.2331373000000028	-102.410749300000006	EARTH	369	\N
834245743972069376	4194513621	RT @ArethadKitson: #ResistTrumpTuesdays\n@jasoninthehouse Do your job and investigate Trump https://t.co/zWgm81Aw0m	37.4315733999999978	-78.6568941999999964	Virginia	276	\N
834245743116374016	32478466	RT @ed_hooley: JOHN MCCAIN CUSSES OUT &amp; VICIOUSLY ATTACKS Female Reporter Who Asks Question #meetthepress #SundayMorning\n#Trump https://t.c…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834246583726125056	1564878943	RT @alfranken: It doesn't end with Flynn. Call for an investigation into the Trump Admin's connection with Russia. https://t.co/fyKwhA9eZ9	45.5230621999999983	-122.676481600000002	Portland, Oregon	357	\N
834246583130656768	727625948607205376	World gets uglier #txpolitics #austin #immigration #atx Amnesty blames Trump, others in global rollback of rights. https://t.co/CbMgPaewhc	30.2671530000000004	-97.743060799999995	Austin, TX	106	\N
834246582749057024	96012070	RT @travishelwig: When Trump won, did you vow to "STAY ENGAGED?" Well, today is the LAST DAY to register for LA's March 7th elections: http…	40.7127837000000028	-74.0059413000000035	New York	214	\N
834246582350528514	733119134641201152	RT @DineshDSouza: Snowflakes beware! I'm on my way to @columbia, where we're going to talk Trump, conservatism, and campus activism. https:…	31.9685987999999988	-99.9018130999999983	Texas	381	\N
834246582119825410	2871375418	RT @theblaze: Maxine Waters says Trump’s cabinet is full of ‘scumbags’  https://t.co/khrhFig3Je https://t.co/AdzIkWlg0U	43.3447294999999997	-75.3878524999999939	Western NY	382	\N
834246581821923329	253779135	Top story: Donald J. Trump on Twitter: "The so-called angry crowds in home dist… https://t.co/Kz5sRnuMvo, see more https://t.co/AcepukfM8z	37.0902400000000014	-95.7128909999999991	USA	56	\N
834246581708677120	28131515	RT @PoliticusSarah: Opinion: Three White Terrorist Arrests In One Week – Where’s Trump Outrage? via @politicususa https://t.co/0gupR4hKmG #…	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
834246581587046401	774679330756538368	RT @HRC: Reports that Trump Admin will rescind trans student protections. Shocking this kind of harm would even be subject of debate. #Love…	38.5815719000000001	-121.494399599999994	Sacramento, CA	383	\N
834246581541036032	2943845715	RT @rabiasquared: The start of a new fake story. Watch it repeated by WH officials. Maybe including Trump himself. https://t.co/fzyaZQFuGf	41.6032207000000014	-73.0877490000000023	Connecticut, USA	365	\N
834246581536825346	2227949787	“Trump denounces recent wave of anti-Semitic attacks”\n\nhttps://t.co/dK7WBZaatT	35.7595730999999972	-79.0192997000000048	North Carolina, USA	384	\N
834246581259898880	4781576424	RT @mitchellvii: Ivanka Trump’s Perfume Soars to No.1 Bestseller on Amazon Despite Boycotts | Heat Street https://t.co/zBBruV7R7C	36.1699411999999967	-115.139829599999999	Las Vegas, NV	218	\N
834246579695603712	718269470414925825	RT @RealJack: Donald Trump is a genius. He mentions Sweden and now people are seeing all the refugee rape &amp; crime taking place in Sweden. #…	40.6331248999999985	-89.3985282999999953	Illinois, USA	360	\N
834246579297075200	800154834422800384	RT @erikaheidewald: Trump has been egging on this anti-Semitic conspiracy theory for months: https://t.co/2DSL8TeItq	31.9685987999999988	-99.9018130999999983	Texas	381	\N
834246579095793664	792781333433122816	RT @Scommentary1: Me vs Trump 3 https://t.co/dArA2tA4s7	34.8526176000000021	-82.3940103999999991	Greenville, SC	385	\N
834246578760200196	3040499232	Why does trump always brings up Hilary ? Can you fuckin not.	34.0736204000000029	-118.400356299999999	Beverly Hills, CA	386	\N
834246577380290560	17010331	I liked a @YouTube video https://t.co/D615TEvxDc LIVE: President Trump Updates and Breaking News	32.7478637999999975	-117.164709400000007	Hillcrest, San Diego, Ca	387	\N
834246576893681664	1935944298	RT @kylegriffin1: CIA officer resigns over Trump.\n\n"I cannot in good faith serve this administration as an intelligence professional." http…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834246576570822660	266365813	RT @AltCaStateParks: POTUS has deep respect for the first amendment and has deep respect for the press\n-Sean Spicer\n\nThe press is the enemy…	46.7295530000000028	-94.6858998000000014	Minnesota	388	\N
834246576558243840	16065676	RT @washingtonpost: Anne Frank Center slams Trump: "Do not make us Jews settle for crumbs of condescension" https://t.co/qhbOpBWpFZ	40.1856720999999979	-111.613219599999994	ÜT: 38.745053,-75.190742	389	\N
834246576507863040	828705357597913089	@antonia4347 @SunsaraTaylor @PressSec trump divide this country.  At least speak the truth.	41.6032207000000014	-73.0877490000000023	Connecticut, USA	365	\N
834246576335888384	22621383	RT @truthandtruth70: @realDonaldTrump National Security Council Spokesman Resigns Over Donald Trump’s ‘Disturbing’ Actions. #Hardball https…	35.5174913000000032	-86.580447300000003	Tennessee	390	\N
834246576268836865	3073654150	RT @NYCRevClub: #Altfacts brownies can't rationalize w/ @SunsaraTaylor. No debate w/ Nazis. The message is clear: The Trump regime is fasci…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834246575215960064	814600948601405440	RT @democraticbear: Once again, Rep. Maxine Waters (D) CA has stated the reality of Trump's people:  "Scum."  Most certainly, again, she is…	34.1347280000000026	-116.3130661	Joshua Tree, CA	391	\N
834246575153152000	301954928	RT @RawStory: Ivanka Trump hit with lien in New York for failure to pay taxes on her high end jewelry business https://t.co/5CtzDUXpT8 http…	40.8468202000000034	-73.7874982999999958	City island, New York City	392	\N
834246574767239169	3160690753	RT @washingtonpost: Anne Frank Center slams Trump: "Do not make us Jews settle for crumbs of condescension" https://t.co/qhbOpBWpFZ	38.5976262000000006	-80.4549025999999969	West Virginia, USA	393	\N
834246574008041473	780756790883459072	RT @Mikel_Jollett: Let's be very clear: Milo was an editor at Breitbart hired by Trump's closest advisor Steve Bannon.\n\nThis hatred is in t…	39.9676481999999993	-74.8003877000000017	Lumberton, NJ	394	\N
834246573605351424	821866522771472384	RT @AltStateDpt: Trump Russia story is increasingly sordid &amp; building. It will be interesting to see who breaks first.\n\n#KeepResisting http…	37.3929055999999989	-122.034889399999997	In The Real World	395	\N
834246572523266049	21135188	RT @iancapstick: I'm not surprised by the Bay's refusal to drop Trump, they have a long history of being on the wrong side of history. #bay…	45.6411033999999987	-75.9284650999999968	Wakefield, Quebec, Canada	396	\N
834246572468756480	375220132	RT @jimmyhawk9: Its becoming clear that voting for Donald Trump was an act of dereliction of one's duty as a citizen and effectively treaso…	30.7110289999999999	-94.9329898000000014	Livingston, TX	397	\N
834246570820386816	217071524	RT @kylegriffin1: 33 days.\n\n132 false or misleading claims from Trump.\n\n0 days without a false statement https://t.co/24V21Vw2Mw\nhttps://t.…	32.7554883000000032	-97.3307657999999947	Fort Worth Texas 	398	\N
834246570048573440	317429844	RT @MarilynHobson2: If it against #President Trump then ya.  Their fake news. Our #Government wouldn't trust him as far as I can trust him…	34.1898565999999988	-118.451357000000002	Van Nuys, Los Angeles	399	\N
834246569922662401	798885406771007488	RT @RawStory: Ivanka Trump hit with lien in New York for failure to pay taxes on her high end jewelry business https://t.co/5CtzDUXpT8 http…	47.6062094999999985	-122.332070799999997	Seattle, WA	139	\N
834246569591463936	30877995	RT @seanhannity: Up next I get @IngrahamAngle’s reaction to the Trump administration's new immigration guidelines #Hannity	34.2331373000000028	-102.410749300000006	earth	376	\N
834246569197203456	21544938	RT @BraddJaffy: Crowd asks Rep. Steve Womack (R-AR) to investigate Trump/Russia. \n\nWait for it... https://t.co/4siV7A0cOR	13.7407450999999998	100.558642899999995	Tiller, OR / Bangkok, Thailand	400	\N
834246568664526849	26861554	RT @rolandsmartin: PREACH! @Trevornoah Says @RealDonaldTrump Doesn’t Have the ‘Balls’ to Go on an Unfriendly Show... https://t.co/1nz0JDb71p	40.7127837000000028	-74.0059413000000035	New York, New York	401	\N
834246568102424576	821809719299801088	RT @carp558: @JrcheneyJohn @jojoh888 @BreitbartNews Sweden took in over 100 k Muslims .and now Muslims are destroying that country. TRUMP i…	46.2349998999999983	-119.223301399999997	Tri-cities WA	402	\N
834246566315712512	798189278350032896	RT @Johnatsrs1949: Massive riots now breaking out over the last few days in #Sweden. How many times does President Trump have to be right?…	35.6531943000000027	-83.5070202999999935	Smoky Mountains, Tennessee 	403	\N
834246566269448192	72955121	RT @BFriedmanDC: Seb Gorka, Trump's senior WH counterterrorism advisor, says "the alpha males are back." Here's a chart about that. https:/…	34.0522342000000009	-118.243684900000005	L.A. California	404	\N
834246566181474304	818606053743034368	RT @DavidYankovich: #CongressCanRequest Trump's taxes.\n\n@BillPascrell is leading this charge.\n\nRT if you believe Trump's taxes should be re…	28.354867200000001	-80.7276782999999938	Cocoa Village,FL	405	\N
834246566177230849	800377702641324032	President Trump. Your attacks on the media are unnecessary. Are you afraid of them? Seems so!	32.8572717999999995	-116.922248800000006	Lakeside, CA	406	\N
834246565699125248	287720616	Listening to @JackKingston make excuses for #Trump. At this point, if you ur a @GOP defending #notmypresident, I think ur hiding something.	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834246564948410368	315250630	Top story: Donald J. Trump on Twitter: "The so-called angry crowds in home dist… https://t.co/uPCLwkWaWv, see more https://t.co/uZl7tpwfTb	43.6532259999999965	-79.3831842999999964	Toronto	148	\N
834246564826583040	54809316	RT @Brasilmagic: School Asks Teachers To Take Down Pro-Diversity Posters, Saying They're 'Anti-Trump'  https://t.co/RraWpf0G7p	-7.25084220000000013	-35.878661000000001	¡MOZART, el más grande!	407	\N
834246563841110017	1022550523	RT @Resist_Chicago: FBI probes Trump-Russia companies after Trump’s bank caught laundering Russian money https://t.co/HOYDV6N1rV #TrumpRuss…	33.7589187999999965	-84.3640828999999997	Everywhere	151	\N
834246563664887808	818485580711477250	RT @NOTaNastyWoman2: @thehill  for proving that as our closest neighbor you aren't letting us down even in light of the nightmare trump has…	56.1303660000000022	-106.346771000000004	Canada	257	\N
834246561227952128	167953637	RT @ananavarro: Overheard-\n\nHim: 3 types of folks these days. Ppl who ❤ Trump; protest him; or too afraid to protest.\n\nHer: U forget those…	34.0489280999999977	-111.093731099999999	Arizona, United States	408	\N
834246561030868992	284210345	RT @ed_hooley: JOHN MCCAIN CUSSES OUT &amp; VICIOUSLY ATTACKS Female Reporter Who Asks Question #meetthepress #SundayMorning\n#Trump https://t.c…	31.9162788000000006	-106.589920199999995	Georgia, Texas, New Mexico	409	\N
834246560510832640	21053383	RT @nedprice: I resigned from @CIA last week. I wrote about why in the @washingtonpost:  https://t.co/HXJhRCkw3O	39.9611755000000031	-82.9987942000000061	Columbus, Ohio, USA	410	\N
834246560397537280	66033904	RT @smartvalueblog: RT We The People - Don’t Tread On Me. #USA #America #Patriots #military #NRA #2A #PJNET #Trump #Cruz #Congress @GOP htt…	37.0902400000000014	-95.7128909999999991	USA	56	\N
834246560254865408	830483955065315328	RT @kylegriffin1: New statement from the Anne Frank Center: "Trump's sudden ackowlegement of Anti-Semitism is like a band-aid for cancer."…	32.7157380000000018	-117.1610838	San Diego, CA	150	\N
834246559428726784	761334042109280256	Scott Pruitt and Donald Trump hate this color. https://t.co/VO0jIoUSmv	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834246558203928576	546856214	What do you think? Feedback welcomed. :) Donald J. Trump on Twitter: "The so-ca… https://t.co/Nwsv4ZqAC8, see more https://t.co/mvbufj6NJY	42.4072107000000003	-71.3824374000000006	Massachusetts	202	\N
834246558182895620	219997270	Big Pharma collaboration with Obamacare betrayed America  https://t.co/ydMNdw337g\n\nCriminal ? Cronyism Should be!	36.6371433999999994	-121.091909999999999	Western USA 	411	\N
834246558099132416	3609952274	RT @TheLastRefuge2: Secretary John Kelly Implements President Trump Immigration Policy, Issues Updated Guidance… https://t.co/qQZVLb3s5d ht…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834246558052937728	100005598	RT @kylegriffin1: Trump's 1st month in office includes:\n\nGolf—25 hrs\nForeign relations—21 hrs\nTweeting—13 hrs\nIntel briefings—6 hrs\nhttps:/…	40.0583237999999966	-74.4056611999999973	New Jersey	144	\N
834246557608218624	825623525289365505	RT @MMFlint: Read my new post, "Do These Ten Things and Trump Will Be Toast." My 10-point Action Plan to stop @realDonaldTrump. https://t.c…	-31.2532183000000003	146.921098999999998	New South Wales, Australia	412	\N
834246557042094081	3385951406	Thin-Skin #ManBaby #Drumpf Completely Flips Out In Tuesday Evening Twitter Meltdown @dcmason09 https://t.co/eiPGkrTSDq	31.9685987999999988	-99.9018130999999983	TEXAS, USA	413	\N
834246556714938368	86317143	RT @AnnCoulter: Sweden "baffled" by Trump remarks. But they're also "baffled" by rape stats: Sweden: 77% of rapes committed Muslims. https:…	32.8231585999999993	-96.7472388000000052	on the road to nonesuch	414	\N
834246556047941632	397056559	RT @ScottAdamsSays: President Trump already fixed Obama's California drought. He's over-delivering! #Trump https://t.co/aFVm2CiFMO	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
834246555800592385	84550274	RT @RCDefense: Why Trump Needs to Deploy Missile Defenses | @dgoure of @LexNextDC @TheNatlInterest https://t.co/fJsECfuVnL https://t.co/ZZc…	38.8799696999999966	-77.106769799999995	Arlington, VA	205	\N
834248263507312640	69011128	President Trump Issues Memorandum On “Construction Of American Pipelines” #pipeline #construction https://t.co/EPQycUzgNR	40.7607793000000029	-111.891047400000005	Salt Lake City, Utah	415	\N
834248263003877376	175675537	This America is better than Trump's America. #resist https://t.co/RlvUBzUdM9	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
834248262983020544	2980829343	RT @IMPL0RABLE: #TheResistance\n\n💥PRIORITIES💥\n\n1⃣️ Impeach Trump &amp; Pence.\n2⃣️ Investigate GOP for Russian ties.\n3⃣️ Declare election invalid…	51.2537749999999974	-85.3232138999999989	Ontario, Canada	252	\N
834248262513262592	2386032312	RT @StandingRockST: "...tribes have had to rise up and forcibly remind the federal government to honor Indian treaties."\nhttps://t.co/t2EKe…	41.8781135999999989	-87.6297981999999962	Chicago	94	\N
834248262127386626	30335514	RT @FoxNews: Trump adviser says new travel ban will have 'same basic policy outcome'  https://t.co/TCFugQLGr2 https://t.co/0rycQ8jueQ	32.1656221000000002	-82.9000750999999951	Georgia, USA	304	\N
834248261607174144	540517561	RT @nytimes: Trump says that his campaign had no contact with Russia. Russian officials contradict him. https://t.co/UAlUgULTnQ	34.0522342000000009	-118.243684900000005	L.A	416	\N
834248261267505152	2582088067	RT @washingtonpost: Anne Frank Center slams Trump: "Do not make us Jews settle for crumbs of condescension" https://t.co/qhbOpBWpFZ	35.7795897000000025	-78.6381786999999974	Raleigh, NC	417	\N
834248260768260096	599741233	RT @LAmag: Trump Just Made Life Hell for Undocumented Immigrants: https://t.co/XR9WNy4deu https://t.co/aXIo6X0fnv	36.9741171000000008	-122.030796300000006	Santa Cruz, CA	418	\N
834248260210487297	503279480	RT @washingtonpost: "Never fjorget": Colbert mocks Trump’s Sweden flub, honors "all the people who did not suffer" https://t.co/jlN1DGaALg	37.4315733999999978	-78.6568941999999964	Virginia, USA	263	\N
834248260172800007	22961333	RT @saletan: Priebus confirms WH knew of Flynn's FBI interview, not just that he misled Pence. Did Trump ignore felony evidence? https://t.…	37.0902400000000014	-95.7128909999999991	US	280	\N
834248259724013568	138619342	RT @ColinKahl: We have 2 governments right now. One trying to reassure anxious allies &amp; a 2nd w/Bannon at the helm doing this: https://t.co…	37.0902400000000014	-95.7128909999999991	USA	56	\N
834248259577184256	1522753381	RT @mikandynothem: Ann Frank Center=MORONS\nTrump is no enemy of people of Israel  like Obama. @netanyahu knows Trump loves Israel and the J…	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834248259497496580	25614085	RT @MariyaAlexander: Rare footage of President Trump operating his well-oiled machine https://t.co/dG7gfeYBDx	39.5841160000000016	-104.807118200000005	Rocky Mountain Empire.	419	\N
834248259409498116	49615510	RT @thehill: GOP rep defends town hall protesters after Trump tweet: "They are our fellow Americans with legitimate concerns" https://t.co/…	51.5073508999999987	-0.127758299999999991	London	420	\N
834248259212345344	24428699	Trump snowflake Hannity whines daily the media being too tough on his buddy Trump yet tonight is talking about "Lib… https://t.co/5boRGCuEjX	37.0902400000000014	-95.7128909999999991	USA	56	\N
834248259178754049	37405939	RT @thehill: GOP rep defends town hall protesters after Trump tweet: "They are our fellow Americans with legitimate concerns" https://t.co/…	43.7844397000000001	-88.7878678000000008	wisconsin	421	\N
834248258813845504	598813780	RT @cnn24hour: .@JulianCastro on Trump's immigration plan: "It's an unleashed the hounds type of executive order" https://t.co/DHWx5rPgZh	40.3187500000000014	-74.3002800000000008	your phone screen	422	\N
834266663382052865	351153807	@Impeach_D_Trump -how they cut out polling centers in key locations and leaked false info on HRC	33.1651199000000005	-97.0294532000000061	Shady Shores Texas	527	\N
834248258767712256	2902282243	RT @kylegriffin1: Trump’s deputy national security adviser KT McFarland was once accused of violating voter registration laws https://t.co/…	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834248258130165765	827528672080965635	@FoxNews @POTUS Thank you Mr. Trump and your staff for protecting us.It's sick what the Demo's have created no regard for us at all.	35.7212688999999983	-77.9155394999999942	Wilson, NC	423	\N
834248257656217603	590229968	Huge Hope! #KeepKratomLegal PINKERTON: A New Vision for Big Pharma and for the American Patient in the Trump Era https://t.co/9wKKMda06F	27.2158826000000005	-81.8584163999999959	Arcadia, FL	424	\N
834248257379381248	22077308	RT @danny_dire_: some kids on my block made an anti-trump protest with toy dinosaurs and i'm dying https://t.co/fZKhe6fgqu	31.9685987999999988	-99.9018130999999983	texas	425	\N
834248256079220736	89559652	RT @AIIAmericanGirI: PINKERTON: A New Vision for Big Pharma and for the American Patient in the Trump Era\nhttps://t.co/8pkKnP13rN	41.2033216000000024	-77.1945247000000023	Pennsylvania	426	\N
834248256070762497	511272778	RT @thehill: Official Sweden Twitter account fact-checks Trump in day-long tweetstorm: https://t.co/59jEVOOjTd https://t.co/LAkGCEMB5t	41.760325899999998	-81.1409321999999946	Perry, OH	427	\N
834248255689064449	213528902	RT @CNNPolitics: President Trump's aides don't want to admit the President is golfing https://t.co/OyVC0KhRdZ https://t.co/GScN3nwAjD	23.6345010000000002	-102.552784000000003	Mexico	428	\N
834248255655526401	803429987760087044	RT @cm_harper: @lawrence @DavidCornDC Great discussion w/ #StevenGoldstein on Trump's heartless &amp; hollow anti-Semitic remarks. Basic human…	40.0583237999999966	-74.4056611999999973	New Jersey, USA	68	\N
834248255475064832	824296559563055104	RT @nedprice: I resigned from @CIA last week. I wrote about why in the @washingtonpost:  https://t.co/HXJhRCkw3O	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834248255445823489	37563444	RT @TheRickyDavila: When *trump says FAKE NEWS,\nWe say FAKE ELECTION! https://t.co/g3kf7hKHYD	37.0902400000000014	-95.7128909999999991	United States	44	\N
834248254149820416	825794714347642880	Do these 10 things, and Trump will be toast, via @mmflint https://t.co/kpGC5uo4D0 via @HuffPostPol	35.6507110000000011	-78.4563914000000011	Clayton, NC	429	\N
834248253923143680	330643630	RT @Cutiepi2u: Young Trump Supporter With No Shame - YouTube https://t.co/nfeYWiVjBh	37.3874739999999974	-122.0575434	Silicon Valley CA	430	\N
834248253851906049	382234749	RT @TomthunkitsMind: We need to know who Trump owes and who might own him, and we need to know it now. https://t.co/E70rvDR8wr https://t.co…	33.5805955000000012	-112.237377899999998	Peoria, AZ	431	\N
834248253700964354	531244825	RT @theblaze: Maxine Waters says Trump’s cabinet is full of ‘scumbags’  https://t.co/khrhFig3Je https://t.co/AdzIkWlg0U	43.1661367000000027	-83.5243976000000004	Otisville, MI	432	\N
834248253323431937	154881723	#Fleekist, #Latest_News, #Today_News Donald Trump Doesn’t Want Anyone To Know How Much Time He Spends Playing Golf https://t.co/oR0WsI3ETi	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834248253319307264	48241625	RT @greenhousenyt: HYPOCRISY: Trump has made 132 false or misleading claims in 33 days—4 a day. Yet he calls the press dishonest. SAD! http…	29.4241218999999994	-98.4936282000000034	San Antonio, TX	433	\N
834248253256376321	64948728	RT @AdamWeinstein: Trump train last week:\nTHE CONSTITUTION DOESN'T PROTECT NONCITIZENS\n\nTrump train this week:\nMILO'S FREE SPEECH RIGHTS HA…	40.7891419999999982	-73.1349610000000041	LI, NY	434	\N
834248252664971265	71458561	RT @KellyannePolls: #Poll: 73% of Americans want Democrats to work with Trump https://t.co/0PnZupoU5G	41.2033216000000024	-77.1945247000000023	pennsylvania	435	\N
834248252614705153	477224996	RT @4free_Ukraine: The anguish Trump causes. Why? Many have fled violence in Mexico. Here, deported man kills self rather than return. http…	35.7595730999999972	-79.0192997000000048	North Carolina	436	\N
834248252405010434	56773392	RT @kylegriffin1: "Trump quacks, walks, and talks like an anti-Semite. That makes him an anti-Semite." —Anne Frank Center Exec. Dir. Steven…	51.5073508999999987	-0.127758299999999991	London	420	\N
834248252383846400	807371148807708672	@daveweigel: Have you heard about Trump, @Disney, and the #DisneyDeathStar? @pplsaction https://t.co/bUqyDIHUcd https://t.co/2XxDZVP1S8	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834248252354465792	11724882	RT @BraddJaffy: Crowd asks Rep. Steve Womack (R-AR) to investigate Trump/Russia. \n\nWait for it... https://t.co/4siV7A0cOR	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834248252295872512	790630861481865217	RT @RealAlexJones: Infowars is under attack we will NOT be defeated!  https://t.co/JqCKuSI416 …  -  https://t.co/mcGvOTX1Cj …  #USA #censor…	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834248250764959745	213321659	Pastor walks out on Trump’s ‘demonic’ Florida rally: ‘My 11-year-old daughter was sobbing in fear’ https://t.co/YiKRrFhuub	35.1700834000000029	-88.5922704000000039	selmer,tn 	437	\N
834248250349723648	133570135	😂🤣 MAGA just got conned by one of the YUGEST cons. Must've paid for one of those Trump U certificates. https://t.co/Cm5wQOLCTf	29.7604267	-95.3698028000000022	Houston, TX	167	\N
834248249544368131	17433344	RT @RT_America: #TheBigPicture: Trump Doubles Down on Forever War [VIDEO] https://t.co/aPNviPjKD1 @Thom_Hartmann	40.7607793000000029	-111.891047400000005	Salt Lake City, UT	438	\N
834248249489883136	813568904664596480	RT @MaxineWaters: Trump cannot assure us no one on his team communicated w/ Russia last year. What does he know? Where are his taxes? #krem…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834248249422733312	18122583	RT @MaxineWaters: Rep. Maxine Waters: Trump advisors with Russia ties are ... https://t.co/FaNWNsqvFj via @msnbc	47.6062094999999985	-122.332070799999997	Seattle 	439	\N
834248248974000133	52085836	RT @regenias: https://t.co/r3MvZeyETC Mr Trump!	29.7604267	-95.3698028000000022	Houston, TX	167	\N
834248248793690113	517946537	RT @politico: Trump, who attacked Obama for golfing and personal travel, spends his first month outdoing his predecessor https://t.co/CS4pa…	39.9652553000000026	-74.3118211999999971	New Jersey coast	440	\N
834248248609095680	828240215798083584	RT @MaddowBlog: Programming Note! MSNBC special on Trump's first month tomorrow!\n10pm ET, right after TRMS. https://t.co/Mdq385dGJ1	40.6331248999999985	-89.3985282999999953	Illinois, USA	360	\N
834248248474767361	806398134830120961	Donald Trump Doesn't Want Anyone To Know How Much Time He Spends Playing Golf -  https://t.co/wWloVNofLo https://t.co/pyiixYP4tL	37.0902400000000014	-95.7128909999999991	United States	44	\N
834248248160354304	1045666867	RT @RepublicanPunk: "Trump isn't responding strong enough to anti-Semitism." - People who applauded Obama for abandoning Israel at the U.N.	30.1765913999999995	-85.8054879000000028	Panama City Beach Fl	441	\N
834248248067960834	28390598	Trump loves the White House's meatoaf https://t.co/rwI3xaed76 https://t.co/lUGkXYctkC	35.3732921000000005	-119.018712500000007	Bakersfield, California	442	\N
834248247812169728	1435351	He won't make it long. I doubt Trump has read his book, but once they translate it into pictures for him, he will n… https://t.co/pBSDLQp24W	41.3325655000000012	-72.9474624000000063	Southern CT	443	\N
834248247241822209	4841147176	RT @POTUS: 'President Trump: Putting Coal Country Back to Work'\nhttps://t.co/t8mgQJq0fL	37.0902400000000014	-95.7128909999999991	United States of America 	444	\N
834248247208075264	4106311	RT @bryanbehar: Lost during press conference: Trump's refusal to admit anti-Semitic acts exist. Instead blames it on his own opponents tryi…	35.9280492999999979	-78.5566809999999975	A magical place	445	\N
834248247115915266	719697764939100161	RT @JoyAnnReid: The Trump travel ban could cost American universities bigly... https://t.co/yK3dzBeqC9 https://t.co/5hTX2CkW2d	-33.3935486000000026	-70.7935671000000042	Washington DC, Santiago, Chile	446	\N
834248246801207296	23060198	RT @AmarAmarasingam: The Anne Frank Center's response to Trump finally acknowledging Antisemitism is epic. \n#Trump #Antisemitism https://t.…	-33.8688197000000031	151.209295499999996	Sydney, Australia	447	\N
834248246646149122	717695079876575232	RT @FoxNews: "I had a very short list &amp; @POTUS was always on that short list." @AlvedaCKing explains why she strongly supports Pres Trump.…	40.6331248999999985	-89.3985282999999953	Illinois, USA	360	\N
834248246583255040	3247217313	HUD official fired for criticizing Trump @CNNPolitics https://t.co/AWebNxpwff	42.9039476000000022	-78.6922514999999976	Depew, NY	448	\N
834248245631086592	814600948601405440	RT @kylegriffin1: Trump’s deputy national security adviser KT McFarland was once accused of violating voter registration laws https://t.co/…	34.1347280000000026	-116.3130661	Joshua Tree, CA	391	\N
834248244930629632	221615865	RT @soledadobrien: Actually Donald Trump suggested execution for 5 young black men in Central Park jogger case. They were wrongfully convic…	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
834248244918153220	276606945	RT @GavinNewsom: RECAP-McConnell's ok with:\n-Attacks on judiciary\n-Hateful Muslim ban\n-Attacks on media\n-Praise for Putin\n...cool.\nhttps://…	35.7595730999999972	-79.0192997000000048	North Carolina	436	\N
834248244846850050	38577427	Mother/Daughter team. 2 Scotch-Irish Corkers fighting Trump's racist and sexist agenda. #resist #defy… https://t.co/iqb7uXmhNH	40.7263542000000029	-73.9865532999999971	Upstate NY	248	\N
834248244477751297	410401191	@cinfell @wanderingaltjew @roachman61 @kylegriffin1 Bannon is nothing. Trump is not a puppet. Hilary would've been a puppet though.	38.6270025000000032	-90.1994042000000036	St. Louis, Missouri	449	\N
834248244456730624	2259388104	RT @washingtonpost: Anne Frank Center slams Trump: "Do not make us Jews settle for crumbs of condescension" https://t.co/qhbOpBWpFZ	20.5936839999999997	78.9628799999999984	India	450	\N
834248244402204672	1499843648	I used to enjoy reading the fly but he's straight up trump's asshole now	40.7439905000000024	-74.032362599999999	Hoboken, NJ	451	\N
834248243856945153	2841589881	@alexhazanov Well they didn't cast a protest vote, so I'm not talking about them, am I? But there were enough of them to elect Trump. /1)	46.7295530000000028	-94.6858998000000014	Minnesota, USA	262	\N
834248243592589312	15926947	Like to Mock Our Weddings Pages? Get in Line, via @nytimes https://t.co/CsmplJye93	47.6062094999999985	-122.332070799999997	Seattle	111	\N
834248243580125184	120516616	RT @washingtonpost: "Never fjorget": Colbert mocks Trump’s Sweden flub, honors "all the people who did not suffer" https://t.co/jlN1DGaALg	30.4382559000000015	-84.2807329000000038	Tallahassee, FL	452	\N
834248243391426560	3390289323	RT @cnn24hour: .@JulianCastro: Trump's immigration policy "is making it worse for families across the U.S." (correct handle) https://t.co/K…	40.6259316000000013	-75.3704579000000052	Bethlehem, PA	453	\N
834248243290730498	14954398	RT @nedprice: I resigned from @CIA last week. I wrote about why in the @washingtonpost:  https://t.co/HXJhRCkw3O	38.0293058999999971	-78.4766781000000009	Charlottesville, VA	454	\N
834248242779058177	739530738	RT @PostOpinions: "That was a truly demoralizing moment, and one I never expected to see." - ex-CIA Edward Price who quit after Trump https…	39.6621694000000033	-104.955119199999999	South Dallas|The Dale 	455	\N
834248242661462017	15434250	RT @IgnatiusPost: The Trump bubble bursts in Moscow’s markets https://t.co/vgQKbLwWv0	39.739235800000003	-104.990251000000001	Denver, CO	361	\N
834248242233692160	827030628537233408	Anne Frank Center director never once took issue with BOs treatment of Israel but attacks Trump  \nhttps://t.co/ZzvuvnmomL via @MailOnline	37.0902400000000014	-95.7128909999999991	United States	44	\N
834248241969369088	831337514	Where are the civil lawsuits against Trump? Hurry up!	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
834248241860509697	869028632	RT @danny_dire_: some kids on my block made an anti-trump protest with toy dinosaurs and i'm dying https://t.co/fZKhe6fgqu	30.2671530000000004	-97.743060799999995	Austin, TX	106	\N
834248802181722113	820717123618148352	RT @wsatx: Senator John Cornyn, TX:  Trump can go on being Trump “as long as we’re able to get things done." Texas forever https://t.co/K0l…	33.1795212999999976	-96.4929797000000065	Collin County, TX 	456	\N
834248801951035392	215108502	RT @JYSexton: Just once I'd love news out of the Trump White House or family to not be directly opposed to human decency or morality. Just…	43.6532259999999965	-79.3831842999999964	Toronto Ontario Canada	457	\N
834248801632264192	225140727	RT @ChrisCrocker: Donald Trump is Donald Trump. \n\nSee how I didn't have to try hard to insult him?	49.2144389999999987	-2.13125000000000009	South Jersey	458	\N
834248800994746369	2328248490	RT @Mark_Beech: New dates added to @rogerwaters Us &amp; Them @rogerwaterstour see also https://t.co/X2mLQ0BAVR https://t.co/zy1GIH7URf	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834248800294359041	2769451	RT @DRUDGE_REPORT: WIRE:  BANNON AND PENCE CLASH ON EU VIEW... https://t.co/xhJPwww5bQ	42.9486611000000025	-85.4824840999999935	Forest Hills, MI	459	\N
834248800218648576	403873968	RT @thehill: Official Sweden Twitter account fact-checks Trump in day-long tweetstorm: https://t.co/59jEVOOjTd https://t.co/LAkGCEMB5t	37.8715925999999996	-122.272746999999995	Berkeley, CA, USA	460	\N
834248799904288768	98844970	RT @ananavarro: Overheard-\n\nHim: 3 types of folks these days. Ppl who ❤ Trump; protest him; or too afraid to protest.\n\nHer: U forget those…	-0.0235590000000000001	37.9061930000000018	kenya	461	\N
834248798901768192	4727286793	@burytheleft You're a typical Trump troll who can't take the truth	38.6270025000000032	-90.1994042000000036	St Louis, MO	462	\N
834248798637531136	3060792647	RT @LifeZette: Leftist Group Prints Guide on Amplifying Trump Resistance https://t.co/8Yv0ss5pKY	42.4072107000000003	-71.3824374000000006	Massachusetts, USA	64	\N
834248798603878400	301257541	RT @flmolly: Oh goody. Trump's personal #fakenews. How long before Jones has press credentials? A west wing job? https://t.co/0zZ5NoD8QV	37.9735346000000007	-122.531087400000004	San Rafael, CA	463	\N
834248797207293954	896677214	RT @robreiner: Someday, hopefully soon, Trump supporters will come to realize that he is not their president either. Freedom and justice fo…	41.6005448000000015	-93.6091064000000017	Des Moines, IA	464	\N
834248796473348096	116344417	RT @JackPosobiec: I notice you didn't say anything when your supporters were attacking Trump supporters in the streets and burning cities h…	41.5060760000000002	-112.015372400000004	ÜT: 30.020371,-90.416424	465	\N
834248796204843008	2376513237	RT @thinkprogress: Trump’s first month travel expenses cost taxpayers just less than what Obama spent in a year https://t.co/bb2oD8p2Os htt…	39.4187194000000005	-76.2944016000000005	Edgewood, MD	466	\N
834248796074700800	1598851068	RT @politico: Trump, who attacked Obama for golfing and personal travel, spends his first month outdoing his predecessor https://t.co/CS4pa…	32.7157380000000018	-117.1610838	San Diego, CA	150	\N
834248795592462336	96893355	Lemme find out trump really making America great again.. 😂😂😂💁🏼‍♂️	39.9525839000000005	-75.1652215000000012	Philadelphia 	467	\N
834248794455830529	732308371618025474	RT @DailyCaller: MLK’s Niece Blames ‘FAKE NEWS’ For African-Americans Thinking Trump’s Racist [VIDEO] https://t.co/u3czjNnxG2 https://t.co/…	52.4750743000000028	-1.82983300000000004	West Midlands, England	468	\N
834248794447319040	2485192498	RT @PostOpinions: "That was a truly demoralizing moment, and one I never expected to see." - ex-CIA Edward Price who quit after Trump https…	37.7749294999999989	-122.419415499999999	San Francisco	37	\N
834248793918992384	779441588661608448	RT @altNOAA: #GOP leaders in hiding. They need to repeal and replace Trump, or they will be repealed and replaced by their constituents.	40.4172871000000029	-82.9071229999999986	Ohio, USA	469	\N
834248793872691200	52950933	RT @ChangFrick: For my english readers: Donald Trump is correct – I live in an immigrant area in Sweden and it is not working well https://…	33.9400673999999967	-118.206126999999995	10313 San Carlos Av. SouthGate	470	\N
834248792962654208	73803494	RT @JuddLegum: When Trump sends tweets like this, you know it's working https://t.co/ySgE9GJxoC	40.7127837000000028	-74.0059413000000035	New York	214	\N
834248792027172865	63820326	RT @GavinNewsom: RECAP-McConnell's ok with:\n-Attacks on judiciary\n-Hateful Muslim ban\n-Attacks on media\n-Praise for Putin\n...cool.\nhttps://…	47.6062094999999985	-122.332070799999997	Seattle, WA	139	\N
834248791503015936	10089382	RT @JuddLegum: Trump’s first month travel expenses cost taxpayers just about what Obama spent in a year https://t.co/HYBO2HBiqQ https://t.c…	40.0149856000000028	-105.270545600000005	Boulder, CO	253	\N
834248791482068992	16488144	RT @HRC: Reports that Trump Admin will rescind trans student protections. Shocking this kind of harm would even be subject of debate. #Love…	28.5383354999999987	-81.3792365000000046	Orlando, FL	130	\N
834248791159144448	805243172	RT @ScottPresler: Trump had Blacks For Trump behind him. \n\nHillary had father of the Orlando shooter, who murdered 49 gays. \n\n#swedenincide…	27.2930999000000014	-81.3628501999999969	LAKE PLACID, FLORIDA 	471	\N
834248790940987397	1950739177	@WinkyEmoticon so do you take Trump literally but not seriously, or seriously but not literally? btw, how does one take Olbermann seriously?	40.4344558000000021	-111.903069299999999	High Plains	472	\N
834248790580273152	28534205	RT @karma1244: Trump Establishes Program to Support the Victims of Criminal Illegals https://t.co/2CxGyaCBat	37.8393331999999987	-84.2700178999999991	Kentucky, USA	88	\N
834248790202806276	2249182070	RT @mmpadellan: .@NonnaSJF trump should be made to ANSWER for his selection of Bannon, connected to an admitted pedophile...amongst many OT…	30.3321837999999993	-81.655651000000006	Jacksonville, FL  USA	473	\N
834248789615587328	811002529022676992	RT @AmyMek: Dear Anne Frank Center,\n\nJews in America stand with our President Trump &amp; his good friend Prime Minister Benjamin Netanyahu. #J…	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834248788327833600	709161467401019392	RT @LouDobbs: Pres. Trump kicks off month #2: Focuses on O'Care, extreme vetting &amp; tax overhaul – where are Ryan &amp; McConnell? Join #Dobbs o…	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834248788206301184	34663425	@Trump_Columbo He has gentle eyes.	46.7295530000000028	-94.6858998000000014	Minnesota, USA	262	\N
834266504694743045	2765658385	DONALD TRUMP...Can you see the movie "A day without Mexicans"? https://t.co/S0wrCEuaPP https://t.co/j0XoiHvTWi	19.0412967000000002	-98.206199600000005	Puebla, México	474	\N
834266504573091840	3648946277	RT @ZaRdOz420WPN: Donald Trump impeachment rallies will take place across US on 'President's Day' national holiday\n#P4SED \nhttps://t.co/TdN…	37.0902400000000014	-95.7128909999999991	 United States of America	475	\N
834266504350740484	437365052	RT @JordanUhl: Trump likes to pick and choose polls, calling all negative ones "fake."\n\nBut it's clear. Major disapproval. https://t.co/NDv…	47.6062094999999985	-122.332070799999997	Seattle Washington	476	\N
834266504031989760	2622551	RT @therealezway: Are you trying to defeat Trump? You're probably doing it wrong. #RESIST https://t.co/khmQWW8WN5	36.7782610000000005	-119.417932399999998	California	61	\N
834266503331487746	3747829993	@PARISDENNARD @AC360 @CNN @POTUS @realDonaldTrump @NMAAHC Tell me 1 thing Paris. Just 1 thing you think Trump has done wrong. Can you?	43.8041333999999978	-120.554201199999994	Oregon	477	\N
834266502610055168	83696994	RT @ChangFrick: For my english readers: Donald Trump is correct – I live in an immigrant area in Sweden and it is not working well https://…	32.7157380000000018	-117.1610838	San Diego, CA	150	\N
834266502383681536	121213096	When were we ever told we were electing the entire #Trump family, #TrumpOrganization &amp; #CelebrityApprentice staff into the #WhiteHouse?	40.7985698999999968	-74.2390828000000056	West Orange, NJ	478	\N
834266501628563456	17588289	.@RachelMaddowSho @NBCNews: 'Unorthodox Thinker': Trump's New NSA Speaks Truth to Power https://t.co/nEV0MfU63L	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
834266501381251072	268756849	RT @mehdirhasan: Also, don't forget, unlike with Trump, Obama's travel expenses weren't paid mainly to...Obama. https://t.co/c1CvrnPfta	53.4807593000000026	-2.24263050000000019	Manchester, England	479	\N
834266500265553921	23671041	RT @morninggloria: Trump thinks you're dumb enough to believe that thousands of journalists from competing outlets are all conspiring to li…	42.7487124000000023	-73.8054980999999941	Upstate NY // Omaha, NE	480	\N
834266499875471360	634274768	RT @molly_knight: Alex Jones believes the Newtown massacre was fake, and has encouraged harassment of victims' families. Congrats to Trump…	34.2331373000000028	-102.410749300000006	Earth	481	\N
834266499103674369	2161162902	RT @kylegriffin1: New statement from the Anne Frank Center: "Trump's sudden ackowlegement of Anti-Semitism is like a band-aid for cancer."…	35.1830854000000031	-111.654964899999996	Northern Arizona	482	\N
834266498797547522	366813829	RT @CharlotteAlter: Each of these blue dots represents an @IndivisibleTeam group resisting Trump. Heavy presence in midwest, South, East Te…	41.9778795000000002	-91.6656231999999989	Cedar Rapids, IA	483	\N
834266498319347713	826172928064524288	RT @TeamTrump: WATCH: How Donald Trump's hat became an icon https://t.co/bBD7ljfNMW BUY YOURS HERE: https://t.co/jAE4b8fdCp #MAGA #TeamTrum…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266497165979648	259726127	RT @FoxNews: President #Trump has had biggest #Dow gain in a president's 1st 30 days since 1909 https://t.co/9SWXWegxMC	40.7127837000000028	-74.0059413000000035	New York	214	\N
834266496658448384	398862727	Trump adviser says new travel ban will have 'same basic policy outcome' https://t.co/rjzCaHoie4	47.8209300999999982	-122.315131300000004	Lynnwood, WA	484	\N
834266496612368385	24247106	RT @KyanaBelle: Remind @SenateGOP @HouseGOP @GOP we KNOW they're helping keep trump incompetency/crimes hidden, putting #PartyAboveCountry…	40.7127837000000028	-74.0059413000000035	new york	228	\N
834266494485819393	254777469	Liberals Trash First Lady Melania Trump for Leading Lord’s Prayer at a Rally, Call Her a “Whore”… https://t.co/vFX5dhXAsD	37.0902400000000014	-95.7128909999999991	USA	56	\N
834266492988334080	46596461	RT @American_Girl_0: #News   Tucker Carlson Mocks Lunatic ‘Refuse Fascism’ Organizer Who Claims “Trump Is More Dangerous Than Hitler”… http…	34.0489280999999977	-111.093731099999999	ARIZONA	485	\N
834266492816367616	1057893264	Developing: Trump Just Found The Leak! Look What Trump Will Do To Them Now https://t.co/RYfxn5GeTk	36.7782610000000005	-119.417932399999998	California	61	\N
834266492770226176	4882382038	Trump is not the enemy. Election Night  https://t.co/4wYPVqBy72	47.6062094999999985	-122.332070799999997	Seattle, WA	139	\N
834266492472541184	825107425900580869	Trump: Ambassador Churkin played key role in working with US on global security issues https://t.co/MzfIUEepOl https://t.co/Ghmp7iMjob	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834266492455657472	3933992962	'Scumbags organized around making money': California congresswoman tears into Trump's 'Kremlin clan'… https://t.co/bhfO5vcMY4	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834266491981803520	95360702	RT @HumblestBee: .@votevets They're completely uncaring about who they hurt and the Trump base needs to wake up.	37.0902400000000014	-95.7128909999999991	USA	56	\N
834266490878595072	23808467	RT @AmyMek: Allah refers 2 Jews as "pigs &amp; apes"! Muhammad believed rats 2 be "mutated Jews"\n\nUnlike Dems, Trump is fighting 2 Protect Jews…	34.9592083000000002	-116.419388999999995	so cal	486	\N
834266662698356736	3592503441	President Trump getting things done\nhttps://t.co/AvMAcrCtzq	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
834266490417209344	3319681690	RT @Mark_Beech: New dates added to @rogerwaters Us &amp; Them @rogerwaterstour see also https://t.co/X2mLQ0BAVR https://t.co/zy1GIH7URf https:/…	29.9012436999999984	-81.3124341000000044	St. Augustine Florida	487	\N
834266489628680193	2391939410	RT @ggrushko: Cost of #Trump's travel to #MaraLago approximately $10M - CBS News\nhttps://t.co/yhvvkmXrWv https://t.co/pDnhG6xlzq	32.8795021999999975	-111.757352100000006	Casa Grande,Arizona	488	\N
834266489490399232	29036917	RT @FoxNews: Rory McIlroy slammed by fans, media for golfing with President #Trump https://t.co/oQpDvCYHKk	35.5174913000000032	-86.580447300000003	Tennessee, USA	330	\N
834266489171505152	780753313524441088	RT @RawStory: Melania Trump strips all references to her plans to profit off being First Lady from defamation lawsuit https://t.co/DEIrPAU0…	47.6062094999999985	-122.332070799999997	Seattle, WA	139	\N
834266489079238656	29851314	Retweeted David Jones (@DavidJo52951945):\n\nTrump orders new crackdown on illegal immigrants will all 11 million... https://t.co/YaDLaqZw95	40.7127837000000028	-74.0059413000000035	New York	214	\N
834266489020506112	500437077	RT @infowars: Emergency! InfoWars Under Massive Censorship Attack! -\nRead More: https://t.co/cZTxtJndjq https://t.co/6b3UEoW1xo	32.7157380000000018	-117.1610838	San DIego, CA	489	\N
834266488370405376	321519979	RT @latimes: Trump denounces anti-Semitism after Jewish community centers receive 68 bomb threats in six weeks https://t.co/JokNquMwrf http…	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
834266488349589504	33914769	RT @MaxineWaters: Rep. Maxine Waters: Trump advisors with Russia ties are ... https://t.co/FaNWNsqvFj via @msnbc	41.2033216000000024	-77.1945247000000023	Pennsylvania	426	\N
834266486952824832	717553584490037250	RT @Brasilmagic: Ivanka Trump hit with lien in New York for failure to pay taxes on her high end jewelry business https://t.co/Gs3bhDie6N	40.6084304999999972	-75.4901832999999982	Allentown, PA	490	\N
834266486252384256	2226555218	RT  Stockholm Rioters Destroy Cars After Trump Cites Sweden's 'Problems' - KERO 23ABC News	56.1303660000000022	-106.346771000000004	Canada	257	\N
834266485241630721	2324323459	Trump's Right: Law-Breaking 'Sanctuary Cities' Must Obey The Law https://t.co/68GlfNGReg	39.9525839000000005	-75.1652215000000012	Philadelphia, PA	233	\N
834266485208018945	53291216	@jimmykimmel reruns this week reminded of how awesome he used to be b4 he turned political &amp; just makes fun of Trump 20 minutes every night.	37.0902400000000014	-95.7128909999999991	USA	56	\N
834266485077913605	3248190776	RT @nickbilton: Comey statements on Clinton emails:\nMarch 2016,\nApril,\nMay,\nJune,\nJuly,\nAug,\nSep,\nOct,\nNov,\n\nComey statements on Trump's ti…	47.8458036000000035	-122.297512400000002	Anywhere but here 	491	\N
834266485027647492	223810775	RT @SallyAlbright: In light of Trump's appointments, it seems the winning strategy for appealing to WWC voters was just to flat out lie to…	26.0077649999999991	-80.2962555000000009	In The Pines	492	\N
834266483924533248	22106033	RT @lauriecrosswell: Having Jeff Sessions investigate Trump would be like assigning\n@oreillyfactor to investigate Roger Ailes.	40.7264772999999991	-73.9815337	East Village, Manhattan	493	\N
834266483584880641	2221686996	RT @tonyposnanski: So if it is true that the people opposing town halls are "paid liberals"\n\nThat would mean Clinton is bringing more jobs…	45.739167700000003	-94.9545518999999985	Lake Wobegon, MN	494	\N
834266483559653376	125453969	RT @emmarieNYT: Lois Jampole of Hammond, La., (L) &amp; Rheta Barnes of Roseland, La., came to Sen. Cassidy's town hall to ask about President…	38.9071922999999984	-77.0368706999999944	DC	495	\N
834266483194617856	14479164	RT @olgaNYC1211: Can someone explain why Leninist Bannon is threatening the EU? \n\n#NOTNORMAL #Trumprussia #Trumpleaks #scumbags  https://t.…	37.0902400000000014	-95.7128909999999991	USA	56	\N
834266482993426432	332624154	RT @sarahmargon: It's hard enough to be a teenager w/o having the feds require you use a bathroom that doesn't match your gender ID https:/…	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834266481894502401	34383891	RT @JoyAnnReid: Trump's win is allowing Republicans to implement every extreme idea they've ever had, on healthcare, reproduction, taxes. m…	32.8365147000000022	-96.4749869999999987	Heath, TX	496	\N
834266481852547073	108346932	RT @SocialPowerOne1: Trump’s visit to a Black history museum cannot reset his racism https://t.co/KaxhtpUl8N	42.0742435000000015	-70.6543096000000048	New York / Massachusetts	497	\N
834266481324089344	3238516760	RT @tenebrini: Everyone but Trump tells the truth. Nobody lies in politics, ever. Just Trump. Trust mainstream media to be honest, fucking…	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834266480992595968	2391401280	Trump hiring freeze forces suspension of military child care programs https://t.co/Vjj9XGUfb8	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266480954970112	827557479802286080	@Republican4Hil @DeplorableMink @islamlie2 I'm 46 sister. I don't hang with anybody but my President Trump. Sawk it… https://t.co/CGgMT1WicG	33.2148412000000022	-97.133068300000005	Denton, TX	498	\N
834266478958485507	28191911	RT @jacobinmag: Our movement will exhaust itself if it’s only fueled by outrage. We need to win people to a vision of a better world https:…	43.7137443000000019	-79.3650145000000009	Tkaronto | Toronto, Ontario	499	\N
834266477226237952	796319663655370753	"if #trump has things to hide, well i know them now https://t.co/RSoA4w5tFt"	40.0583237999999966	-74.4056611999999973	New Jersey, USA	68	\N
834266477133959172	2326625166	RT @Mark_Beech: New dates added to @rogerwaters Us &amp; Them @rogerwaterstour see also https://t.co/X2mLQ0BAVR https://t.co/zy1GIH7URf	40.7127837000000028	-74.0059413000000035	New York City	145	\N
834266476878127105	2363592546	RT @kylegriffin1: Trump’s deputy national security adviser KT McFarland was once accused of violating voter registration laws https://t.co/…	40.0378754999999984	-76.305514400000007	Lancaster, PA	500	\N
834266476546707459	708898201969897473	RT @sahilkapur: GOP Rep. Mark Sanford says Trump has fueled intolerance, misled on the murder rate and terror coverage &amp; is unprepared for…	47.5650066999999979	-122.626976799999994	Bremerton WA	501	\N
834266476282527744	832950647473442817	2.225% of Trump's first term has elapsed.	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266475934257152	138520965	'Scumbags organized around making money': California congresswoman tears into Trump's 'Kremlin clan'… https://t.co/AIfa5LoTmv	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834266475649200128	121597316	Bay Area seeks ways to manage anxiety in age of President #Trump https://t.co/M9swyp0uHi via @jonkauffman https://t.co/UhnFER3cjX	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
834266475305254912	755786432917024768	RT @JoyAnnReid: Trump's win is allowing Republicans to implement every extreme idea they've ever had, on healthcare, reproduction, taxes. m…	30.4379758000000002	-88.8680853000000042	St Martin, MS	502	\N
834266474063810560	825739263258009601	Trump have not resind resigned from presedent of the USA. We wait for 32 days and 13 hour. #TheResistance	34.2331373000000028	-102.410749300000006	Earth	481	\N
834266474063790081	23098409	RT @RawStory: ‘This is fake news’: Rick Santorum melts down on CNN and blames Obama for anti-Semitism under Trump https://t.co/V2xpxk1uGj h…	44.5588028000000023	-72.5778415000000052	 Vermont	503	\N
834266473338118145	708743981270609921	Is this even #fakenews? No one has come forward to tell us how #Trump behaves when losing at golf \nI have, however,… https://t.co/7knicA3qoO	29.5844524	-81.2078699000000057	Palm Coast, FL	504	\N
834266473187012609	1100273010	RT @cmkshama: #StandingRock may be raided tomorrow. Solidarity to courageous sisters &amp; brothers on front line! #NoDAPL #DefundDAPL https://…	37.8715925999999996	-122.272746999999995	Berkeley, California	505	\N
834266472885088258	761238040656306177	.@GeorgeTakei Right George! You would know what President Trump THINKS about Sweden. You're a mind reader. YOU said it. YOU own it.	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266472603979776	78460168	RT @GetTMarked: Utah Sen. Lee to review Trump's Chinese trademark - KUTV 2News https://t.co/m4zVBTPjRs	37.8271784000000011	-122.291307799999998	San Francisco Bay Area	348	\N
834266472327188481	16984560	RT @ThomasB00001: Hey Trump, Americans still despise you. Just a friendly reminder that you suck at the job you said you'd be great at. #Ha…	33.4483771000000019	-112.074037300000001	phoenix az	506	\N
834266472293793796	271056619	Man Sentenced for Defacing Trump's Walk-of-Fame Star. {Shame,slap on the wrist fine &amp;probation for a Felony offense} https://t.co/IeXEKhBAPp	37.0902400000000014	-95.7128909999999991	U.S.A.	231	\N
834266472192962560	790219023581454337	Farrakhan WARNS Donald Trump come to Chicago with ARMY &amp; *KILL* Black YOUTH * WATCH GOD *\n\nhttps://t.co/6c4CXHJFox	37.0902400000000014	-95.7128909999999991	US	280	\N
834266471895142400	24173882	@stanmcintire  establishment Rs need to understand that if they continue 2 break promises 2 Trump voters, they will hand over power 2 Dems	33.4483771000000019	-112.074037300000001	PHX, ARIZONA	507	\N
834266471756730368	766614932896964608	Farrakhan WARNS Donald Trump come to Chicago with ARMY &amp; *KILL* Black YOUTH * WATCH GOD *\n\nhttps://t.co/LgHa7VDKUg	37.0902400000000014	-95.7128909999999991	US	280	\N
834266471664644096	44845845	RT @Mikel_Jollett: The reason Milo is important is bc he was Bannon's prodigy. You know who else is Bannon's prodigy?\n\nDonald Trump.\n\nhttps…	40.7405211000000023	-73.997998999999993	Cafeteria, USA	508	\N
834266471295483904	767593647055319041	@DRUDGE_REPORT: Libertarian Congressman Emerges as Leading Critic of Trump... https://t.co/UOx0yrn7Cd	40.2338438000000025	-111.658533700000007	Provo, UT	509	\N
834266470783864832	1090292791	@funder But will make selves, friends, corps, CEOs richer. Average Americans &amp; planet be damned. Trump was right... lot of killers here.	37.4315733999999978	-78.6568941999999964	Virginia, USA	263	\N
834266470511173632	796327035929063424	"if #trump has things to hide, well i know them now https://t.co/qKPjaww3KQ"	38.8026096999999979	-116.419388999999995	Nevada, USA	510	\N
834266469705871361	16119842	The mistake Trump can’t ever walk back https://t.co/86S1h0Q7ej via @GQMagazine https://t.co/Bnz8WkZIP8	40.7127837000000028	-74.0059413000000035	New York City	145	\N
834266678871552000	472470717	RT @mitchellvii: Despite Trump's repeated statements of support for Israel, asshat Liberals insist that somehow he is this raging anti-Semi…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266678796038144	738399937734397952	RT @ReiserWilliam: @cheekoguy @nia4_trump @Oprah @Madonna @AshleyJudd @TheEllenShow Ashley Judd is a disgrace to the State of Kentucky &amp; Th…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266678624129026	25688579	RT @PalmerReport: Donald Trump’s alleged Russian handler flies to Moscow, as Senate Intel Committee closes in: https://t.co/FATI3nGMSr #Tru…	43.9653889000000007	-70.8226540999999941	New England	511	\N
834266677378482176	26901657	RT @PapaESoCo: Donald Trump is too busy showboating to do the hard work of creating jobs and rebuilding America https://t.co/LoivQkA1Xh #BL…	42.1292241000000018	-80.0850590000000011	Erie , Pennsylvania	512	\N
834266675797180416	134916242	But historians have been pointing out how America''s hands are tied. Trump has the mission of making America unquestionably top again.	29.7604267	-95.3698028000000022	Houston Texas	513	\N
834266674429837313	1281452935	RT @thehill: George Clooney: Trump and Bannon are "Hollywood elitists" https://t.co/F30Om7bf51 https://t.co/hGH2phx5Im	40.7246670999999978	-74.0023977999999971	New York, London, Tokyo, LA	514	\N
834266673322422272	16562075	RT @JohnWDean: Nice recap by @Will_Bunch of why Trump's Russian entanglements could be worse than Watergate: https://t.co/puO5zejeFI	38.5602299999999971	-121.486723999999995	Vegan since 2007 in California	515	\N
834266673024753664	815871284	RT @vvega1008: Look at all the so-called evangelicals supporting Trump. They turn a blind eye to his sexual assualt, perversions, lies, rac…	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834266672240406533	56894163	RT @AltStateDpt: RT- On a day when Trump claims to be against bigotry &amp; hate, his hateful actions speak louder than his hollow words.\n\n#Res…	36.1023714999999967	-115.174555900000001	New York , New York	516	\N
834266670667493376	768531012208893952	There's enough people against Trump and GOP to walk thru those doors and physically throw all of them out of our White House and Senate	38.7071247000000014	-121.281061100000002	citrus heights CA	517	\N
834266670432714752	34383891	RT @JordanUhl: Trump likes to pick and choose polls, calling all negative ones "fake."\n\nBut it's clear. Major disapproval. https://t.co/NDv…	32.8365147000000022	-96.4749869999999987	Heath, TX	496	\N
834266670382325766	71545482	RT @mitchellvii: No wonder Liberals believe all these lies about Trump, they think SNL is actual news!	42.4072107000000003	-71.3824374000000006	Massachusetts, USA	64	\N
834266669207867392	16930193	RT @tedlieu: More evidence from @nytimes that the failing @realDonaldTrump is lying about contacts with Russia. https://t.co/uJWYvkxVOO	36.1568830000000005	-95.9915299999999974	The universe	518	\N
834266668452896769	4675501766	RT @soledadobrien: Same poll: 68 percent say Trump should be willing to compromise and find ways to work with Democrats in Congress. https:…	47.1853784999999988	-122.292897400000001	Puyallup, WA	519	\N
834266668171923456	635195109	BREAKING VIDEO : Swedish Citizen Says "Trump is Right" About Sweden https://t.co/v2ak10pKC1	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266668142465024	101266017	RT @SocialPowerOne1: New York Just Filed A Tax Warrant Against Ivanka Trump For Dodging Taxes https://t.co/783oGmJ6hx	19.9026482000000016	-75.1001686999999976	Outside Gitmo	520	\N
834266667559559172	165837168	RT @JBurtonXP: Swedes EVISCERATE Trump by smugly mocking his anti-immigration comments as fire and bloodshed flare up once again in their c…	30.2671530000000004	-97.743060799999995	austin	521	\N
834266667328892928	3299792738	@RabbleTheGamer @RinTinTinFoil @johngreentweet @thehill I didn't make any accusations about Trump voters. You did.	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266666955657216	30266529	RT @ABCWorldNews: Donald Trump's "America First" policy has an admirer in Zimbabwe President Robert Mugabe https://t.co/Ypf8nERp4s https://…	32.9210902000000019	10.4508956000000008	Tatooine...	522	\N
834266666850717698	1413803720	RT @DanielIeBregoIi: I haven't heard a bitch say she foreign since Donald Trump been in office 😂😂😂	31.9685987999999988	-99.9018130999999983	TEXAS!!!!	523	\N
834266665508544513	268547631	RT @SusieMadrak: "The least anti-Semitic person you'll ever meet" tried to humiliate Jon Stewart by pointing out his birth name was Leibowi…	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834266665416265729	611336226	RT @MatthewACherry: *Trump at the National Museum Of African American History And Culture @NMAAHC*\n\nReporter: Did you check out John Lewis'…	34.2331373000000028	-102.410749300000006	 Earth	524	\N
834266664640212992	5271931	RT @MMFlint: Read my new post, "Do These Ten Things and Trump Will Be Toast." My 10-point Action Plan to stop @realDonaldTrump. https://t.c…	37.9022008000000028	-77.033217300000004	sunny side o' the street	525	\N
834266664015327232	246446101	Lawmakers pressed on Donald Trump's policies at town halls https://t.co/wSWVbTIw0E via @nbcnews	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834266663444844544	1404087277	RT @washingtonpost: Anne Frank Center slams Trump: "Do not make us Jews settle for crumbs of condescension" https://t.co/qhbOpBWpFZ	-41.3166670000000025	148.233332999999988	St Helens, Tasmania	526	\N
834267883999997953	24700526	Donald Trump's America https://t.co/9kghyjBHWo	33.7366043999999974	-84.3357991999999967	East Atlanta	642	\N
834266661922422784	216357473	https://t.co/F2FJRMRunJ - CIA analyst quits, blames President Trump https://t.co/ZX0Rc5BGKP	39.7684029999999993	-86.1580680000000001	Indianapolis	528	\N
834266660966129665	189003372	Ukraine Lawmaker Who Worked With Trump Associates Faces Treason Inquiry https://t.co/CKTqBHHd8Y	34.0336250000000007	-117.043086500000001	Yucaipa, CA	529	\N
834266660848730113	816185093035266049	Major Elements of Trump’s New Immigration Policies - The Trump administration has significantly hardened the co... https://t.co/vWx1rHnWLb	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
834266660005556225	76126379	RT @KaivanShroff: RECORD: White House petition to have Trump release his tax returns is first in history to pass 1 million signatures https…	34.0489280999999977	-111.093731099999999	Arizona	314	\N
834266658013327361	2785097203	RT @michaeldweiss: Now that Firtash is being extradited to the US, Paul Manafort may have reason to worry: https://t.co/Baqhdub5Vz https://…	45.4215295999999995	-75.6971931000000069	ottawa, canada	530	\N
834266656130072576	750180799	RT @AdamWeinstein: Trump train last week:\nTHE CONSTITUTION DOESN'T PROTECT NONCITIZENS\n\nTrump train this week:\nMILO'S FREE SPEECH RIGHTS HA…	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834266652749361152	738399937734397952	RT @cheekoguy: @ReiserWilliam @nia4_trump @Oprah @Madonna @AshleyJudd @TheEllenShow They'd love her to pieces. Literally.	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266652040626177	17600254	RT @NewRepublic: The role Trump loves most isn't president, but circus ringmaster. https://t.co/eQeJI3wYKF https://t.co/mevC87Anpr	32.1656221000000002	-82.9000750999999951	NE GA 	531	\N
834266651856105472	386119635	RT @politico: Trump forgets his Obama criticisms https://t.co/rZthigCfsu via @jdawsey1 https://t.co/ebRmJSQy8S	32.2987572999999983	-90.1848102999999952	Jackson, MS	532	\N
834266651185000448	34744730	RT @GayPatriot: 🚨🚨🚨Day 34 of the Trump Administration 🚨🚨🚨\n\nI'm still not in a gay concentration camp or being electrocuted by Mike Pence\n\n#…	26.1195078000000009	-80.1239711999999997	E Las Olas, Fort Lauderdale, FL	533	\N
834266650958557185	2422751880	'Panic, fear, &amp; terror' over Trump changes... - The Dept. of Homeland Security has outlined changes to immigrat... https://t.co/YglwfcdAMi	37.0902400000000014	-95.7128909999999991	United States of America	534	\N
834266650958495744	2422751880	Donald Trump makes GOP town halls great again - The same day red-state GOP lawmakers were screamed at about Tru... https://t.co/ROaHCBf3cA	37.0902400000000014	-95.7128909999999991	United States of America	534	\N
834266650929139714	2422751880	After days of questions, Trump denounces... - For some critics of the Trump White House, the President's commen... https://t.co/v2swOMlB4G	37.0902400000000014	-95.7128909999999991	United States of America	534	\N
834266650572582912	721045281396011008	Here's why Donald Trump can't come clean on Russia https://t.co/OKXmzrdziq via @MotherJones	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266650111193088	22727231	RT @kylegriffin1: New statement from the Anne Frank Center: "Trump's sudden ackowlegement of Anti-Semitism is like a band-aid for cancer."…	38.2324169999999981	-122.636652400000003	Petaluma CA	535	\N
834266649880559617	18662449	RT @travishelwig: When Trump won, did you vow to "STAY ENGAGED?" Well, today is the LAST DAY to register for LA's March 7th elections: http…	34.2331373000000028	-102.410749300000006	The Earth	536	\N
834266649264058368	16419173	RT @kylegriffin1: "Trump quacks, walks, and talks like an anti-Semite. That makes him an anti-Semite." —Anne Frank Center Exec. Dir. Steven…	35.7795897000000025	-78.6381786999999974	Raleigh, North Carolina	537	\N
834266649180069888	2916782918	RT @saletan: Priebus confirms WH knew of Flynn's FBI interview, not just that he misled Pence. Did Trump ignore felony evidence? https://t.…	39.739235800000003	-104.990251000000001	Denver, CO	361	\N
834266649058476034	715022648598728704	RT @rebeccaallen: @JonRiley7 👍 ICYMI: "Trump and his minions... their views come out of a playbook written in German." \nhttps://t.co/6xdAtr…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266648248872961	784673634052825088	Rep. Maxine Waters: Trump advisors with Russia ties are ... https://t.co/cuqlj9j8vR via @msnbc	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
834266646843944961	142119757	Hillary Clinton Finally Stepped in to Advise President Trump https://t.co/Oh2of6MSZz	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266646491516928	121503012	You people voted for Trump, he said what he was going to do. Bad move.	36.1699411999999967	-115.139829599999999	Las Vegas, NV	218	\N
834266645723910146	940503344	RT @BrentBozell: A warped Hollywood leftist goes on a disgusting attack. Don't hold your breath waiting for liberals to condemn. https://t.…	33.717470800000001	-117.831142799999995	Orange County, California	538	\N
834266644826423297	825472409209884672	RT @whyiamcrazy: @aravosis We are a military family. This would kill my ability to be employed. Can't afford any other child care. But trum…	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834266644331524096	74371860	I wonder how much he spent to buy the United States and who got the money and made the deal? Hmmm, Trump? https://t.co/qhHCV2k1TQ	30.0077771999999996	-95.6425136000000009	Texas Hill Country	539	\N
834266643240882176	3287069258	RT @washingtonpost: 100 days of Trump claims: In the 33 days so far, we’ve counted 132 false or misleading claims https://t.co/wBC5ZLoJDg	33.7700504000000024	-118.193739500000007	Long Beach, CA	290	\N
834266643228405760	802588734	RT @Squeakie6: Maybe, as Trump/GOP policies actually start to affect people, Trump supporters will change their minds. https://t.co/Oi9TDj8…	46.4110573999999971	-86.6479360999999955	Munising, MI	540	\N
834266642871787521	225233387	Meet the seven Russian operatives who have dropped dead during Donald Trump-Russia scandal https://t.co/jmmW3aSPTG via @PalmerReport	45.4870620000000017	-122.803710199999998	Beaverton, OR	284	\N
834266640921485312	2200344380	RT @Mikel_Jollett: Let's be very clear: Milo was an editor at Breitbart hired by Trump's closest advisor Steve Bannon.\n\nThis hatred is in t…	37.5071591000000026	-122.260522199999997	San Carlos, CA	541	\N
834266640841900037	464982966	In Trump's future looms a familiar shutdown threat https://t.co/gTggrBZ3rI	37.0902400000000014	-95.7128909999999991	USA	56	\N
834266640653156352	747939236	RT @thehill: George Clooney: Trump and Bannon are "Hollywood elitists" https://t.co/F30Om7bf51 https://t.co/hGH2phx5Im	44.2386819999999972	-70.0356069000000048	Monmouth, ME 	542	\N
834266640552443905	61246898	President Donald Trump https://t.co/qoWEx2T2j1	29.9769268000000011	-90.0676696000000021	7thward New Orleans	543	\N
834266639759720448	796327331270889472	"if #trump has things to hide, well i know them now https://t.co/meqa6jNb3U"	33.7489953999999983	-84.3879823999999985	Atlanta, GA	289	\N
834266638111358976	1790752315	@JordanUhl bc politicians of all background&amp;thru history have never,EVER done this "pick and choose". Only Trump.Proves he's satan!!!11!!!	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834266638090395648	1651611576	RT @politico: Trump, who attacked Obama for golfing and personal travel, spends his first month outdoing his predecessor https://t.co/CS4pa…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834266637956182017	342340826	@newtpeters I'm acting dying bc my boy Mac sings (raps?) Donald Trump. I think it's funny.	35.3859241999999981	-94.3985475000000065	Fort Smith, AR	544	\N
834266636416753665	746759190798958593	RT @RealAlexJones: Infowars is under attack we will NOT be defeated!  https://t.co/JqCKuSI416 …  -  https://t.co/mcGvOTX1Cj …  #USA #censor…	-82.8627519000000063	135	Antarctica	545	\N
834266635645120512	722508677488324608	RT @mikandynothem: ✔ RETWEET✔ if you are proud of President Trump for FIRING Acting AG Yates! I love this guy! This Presidency is going to…	33.473497799999997	-82.0105147999999957	Augusta, GA	546	\N
834266635246649344	743522619010457600	"Trump Report as of Tuesday February 21 at 11:30 - @RandomizerTest" - #ArtificialIntelligence #AI	41.481993199999998	-81.7981908000000004	Lakewood, OH	547	\N
834266634126753794	553998829	@jasoninthehouse please do your job and investigate White House, specifically Trump's,  ties to a Russia! Do your job,  sir!	39.9679330000000022	-75.3470480000000009	Broomall, PA	548	\N
834266633497636865	367495633	RT @RBReich: You might want to send this to anyone you know who voted for Trump. \n(Thx to Rosa Figueroa who posted this responding to one o…	43.1938516000000021	-71.5723952999999966	New Hampshire	549	\N
834266632578928641	2391939410	RT @LibAmericaOrg: Trump’s First 30 Days: Fake News, Spin, And Outright Lies (VIDEO) https://t.co/ws0MGwgVdR https://t.co/Lc8MDPLKrz	32.8795021999999975	-111.757352100000006	Casa Grande,Arizona	488	\N
834266632549601280	423903701	RT @TimOBrien: And thank YOU, American taxpayers, for helping fund the Trumps' travel so this new venture could launch--while POTUS stays c…	45.4870620000000017	-122.803710199999998	Beaverton, OR	284	\N
834266856038998016	33119023	RT @kylegriffin1: Trump's 1st month in office includes:\n\nGolf—25 hrs\nForeign relations—21 hrs\nTweeting—13 hrs\nIntel briefings—6 hrs\nhttps:/…	32.1656221000000002	-82.9000750999999951	Georgia, USA	304	\N
834266855556710400	759845601882157056	RT @TomthunkitsMind: Trump Water. https://t.co/IvyK2KIDpy	40.4172871000000029	-82.9071229999999986	Ohio, USA	469	\N
834266855539871744	55167974	RT @TomthunkitsMind: We need to know who Trump owes and who might own him, and we need to know it now. https://t.co/E70rvDR8wr https://t.co…	26.8205530000000003	30.8024979999999999	Egypt	550	\N
834266853329477632	71643224	Candidate Trump promised to deport 11 million immigrants in the US illegally\n\nhttps://t.co/Bh7DUVhzcD https://t.co/HuuAUzTY0U	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834266853308563456	281192214	RT @danny_dire_: some kids on my block made an anti-trump protest with toy dinosaurs and i'm dying https://t.co/fZKhe6fgqu	37.7766897999999998	-122.416352200000006	dirtywaters	551	\N
834266852981358593	154390404	RT @ChefJamGodDamn: Donald Trump did the same. Bye. https://t.co/m8Ur5Yz1ua	33.745046600000002	-84.4116504999999933	350 Spelman Lane	552	\N
834266852272570370	260848405	RT @SgBz: Thanks to Trump, US troops are losing daycare for their children https://t.co/Ex7TCly9FI #p2 #tcot	40.0583237999999966	-74.4056611999999973	New Jersey, USA	68	\N
834266852188581888	2935675967	https://t.co/Zjpaa6yCcp \rThe proof is in the pudding right here	40.7127837000000028	-74.0059413000000035	New York	214	\N
834266851588841476	51611871	RT @mrochabrun: .@DHSgov just confirmed our @propublica story: the US wants to deport migrants to Mexico even if they aren't Mexican https:…	50.0646501000000015	19.9449798999999999	Kraków	553	\N
834266851475591169	628776245	Trump is turning the poor ICE workers into the American ISIS or in this case ICEss' (pronounced: Isis) https://t.co/oUB1939gGU	35.7595730999999972	-79.0192997000000048	North Carolina, USA	384	\N
834266850884218880	257597528	RT @washingtonpost: 100 days of Trump claims: In the 33 days so far, we’ve counted 132 false or misleading claims https://t.co/wBC5ZLoJDg	37.4315733999999978	-78.6568941999999964	Virginia	276	\N
834266850439557121	17494767	RT @AmyMek: Pathetic, SELF-HATING Liberal Jews (JINOS) oppose Trump, a President that wants 2 protect them from the new Nazis👉🏻MUSLIMS\nAnne…	42.4418149999999983	-121.270831400000006	Beatty Or USA	554	\N
834266850007605249	1031346560	RT @mitchellvii: Despite Trump's repeated statements of support for Israel, asshat Liberals insist that somehow he is this raging anti-Semi…	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834266849395105792	240619680	RT @JesseCharlesLee: African-American History Museum would've been good place for Trump to apologize to 1st black POTUS for calling him ill…	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834266848225001472	929844332	@tynkann @pspoole @Lauren_Southern the shit trump was talking about the otther day.	60.4720239999999976	8.46894600000000075	Norway	555	\N
834266847159541760	1362931315	RT @CharlesMBlow: This Trump admin is a cancer on this nation. Don't try to convince me otherwise. Your efforts are futile, and my convicti…	37.9642528999999982	-91.8318333999999936	Missouri 	556	\N
834266846916341760	15299119	Trump's lawyer has told 4 different stories about the Russia-Ukraine peace plan debacle https://t.co/1zOjeqS7dj (&amp; they're all фигня)	45.5230621999999983	-122.676481600000002	Portland, OR	41	\N
834266846857723904	2363592546	RT @JYSexton: Just once I'd love news out of the Trump White House or family to not be directly opposed to human decency or morality. Just…	40.0378754999999984	-76.305514400000007	Lancaster, PA	500	\N
834266846798897154	28982798	RT @netw3rk: except for constantly doing anti-semitic things why would anyone think trump is anti-semitic https://t.co/01thDzJYQj	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
834266845343473666	2187061903	RT @crazylary51: IF THE #WHITEHOUSE POLICE STATE #REPUBLICAN #TRUMP BROWN SHIRTS COME TO YOUR DOOR! #Resist https://t.co/ujiMErmCk5	36.7782610000000005	-119.417932399999998	California	61	\N
834266845238669318	2147940818	@SenSchumer hope for America Republicans break w/ Trump? Uhh, you don't speak for America.  America spoke November 8th. You lost! Trump 2020	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834266844987011072	823269254564704257	RT @chuckwoolery: I got news for you, if you are a citizen of the United States. Trump is your President. Like it or not. We didn't like Ob…	39.5500506999999999	-105.782067400000003	Colorado, USA	212	\N
834266844966035457	1730405546	Students Get Taught A Major Lesson After Attacking President Trump's Motorcade! https://t.co/bjOK6qYhlU https://t.co/gwCfxYJd5p	32.7157380000000018	-117.1610838	San Diego, CA	150	\N
834266844810797056	166281130	RT @PolitikMasFina: Amash has been a better critic of Trump than McCain. Where's his article? https://t.co/nZUkeuzOrr	33.8608820999999978	-118.152222399999999	Lives in Cowboy Country	557	\N
834266844500484097	125030665	RT @andylassner: Trump and his cronies also inspiring some great headlines https://t.co/MacBN5PxWV	39.9525839000000005	-75.1652215000000012	Philadelphia, PA	233	\N
834266844450213889	810106940869185536	@soledadobrien Well, Trump has paid for crowds it the past, it's not a big leap for him to believe that everyone does it.	41.2033216000000024	-77.1945247000000023	Pennsylvania, USA	107	\N
834266844034850816	783487468964163584	RT @MatthewACherry: This was literally us a month ago during Trump's inauguration speech. https://t.co/PdHP3eVAJ8	40.2346554000000012	-75.0561859999999967	farm station.	558	\N
834266843506438149	237387519	RT @kylegriffin1: Trump and aides: We had no contact with Russian officials.\n\nRussian officials: We had contact with Trump aides.\nhttps://t…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266843368062977	2635340887	DANG, \n\nPursuit of shady oligarch a test of DoJ integrity under Trump https://t.co/CXaioUzTX7 via @msnbc	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834266843149901824	706683740483883009	The left's hypocrisy on Trump's "enemy of the American People" comment https://t.co/iP10ilq3kB via @denverpost	33.2148412000000022	-97.133068300000005	Denton, TX	498	\N
834266842713714688	764567449	RT @thephysicsgirl: If the entire budget is 1600 Skittles, the arts funding is ONE Skittle. https://t.co/wZi5AkDsu1	56.1303660000000022	-106.346771000000004	Canada	257	\N
834266842348797952	33914769	RT @RawStory: ‘Have you no ethics?’: Anne Frank Ctr head rips Kayleigh McEnany for citing Ivanka as proof Trump’s not anti-Semitic https://…	41.2033216000000024	-77.1945247000000023	Pennsylvania	426	\N
834266840998215681	189389598	RT @politico: Trump, who attacked Obama for golfing and personal travel, spends his first month outdoing his predecessor https://t.co/CS4pa…	40.0149856000000028	-105.270545600000005	Boulder, CO	253	\N
834266840293576704	2825411642	RT @laceyandpearl: https://t.co/hFRoAF4gNs\n\nWhat Did MELANIA AND IVANKA TRUMP WEAR to the Inauguration Ball?\n\n#gown #gowns #dress #ballgown…	42.4136427999999981	-70.9915996999999948	Wonderland	559	\N
834266838980816896	291199456	RT @PRESlDENTBANNON: Day 33. Donald Trump still believes he is the president.	40.7127837000000028	-74.0059413000000035	New York	214	\N
834266838385188864	27493883	RT @petermaer: Thanks to @MarlowNYC for reminding the world there are deep footprints on the #Trump twitter trail. https://t.co/4sQbbdAstu	40.7127837000000028	-74.0059413000000035	New York	214	\N
834266837781090305	110332839	Rep. Maxine Waters: Trump advisors with Russia ties are ... https://t.co/T8pRZzn3Af via @msnbc	38.4404290000000017	-122.7140548	Santa Rosa California	560	\N
834266837403660289	27125886	RT @CNNPolitics: GOP Sen. Joni Ernst runs into the anti-Trump resistance in rural Iowa https://t.co/5BzRO6fNx2 https://t.co/UrL1oC0PZ2	39.5500506999999999	-105.782067400000003	Colorado 	331	\N
834266837378412544	882456098	@JSmitherman74 Our youngest daughter had hours cut for the same reason. Point is Trump has tremendous amount of damage to repair.	33.7475202999999979	-116.971968399999994	Hemet, CA	561	\N
834266836589961217	417553124	RT @onekade: "The administration seems to be putting its foot down as far as the [deportation] gas pedal will go"  https://t.co/vWUGrHe9US	62.411363399999999	-149.072971499999994	West Coast	242	\N
834266835969253376	1885149961	RT @Jeffb928: @RichardTBurnett these 2 Rhinos still trying to take Trump down leftover never Trump. We sure don't wonder why nothing ever g…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266835394641920	3325464867	RT @paul_lander: Milo Yiannopoulos Is Leaving Breitbart News\nLook for Trump to appoint him to head up Department of Child Protective Servic…	40.7127837000000028	-74.0059413000000035	New York City	145	\N
834266834887143424	1153197612	RT @VincentLombar13: "Sometimes by losing a battle you find a new way to win the war."\n\n             ~Donald Trump	30.8153755999999994	-95.1122373000000039	Alabama/Texas	562	\N
834266834115317760	831186667100790784	@truthandtruth70 @realDonaldTrump Donald Trump, did you read the  investigation into Flynn or you just listen to what other people tell you?	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834266833234513920	20448269	RT @MattBors: Jones believes Billy Bush is a deep state operative who psyop'd Trump into pussy grabbing remarks. This is who Trump has dire…	45.5230621999999983	-122.676481600000002	Portland, OR	41	\N
834266832525680640	59865242	Coal mining fantasy https://t.co/VuSOAnqXO7\nvs reality https://t.co/AEPL7nFSyK https://t.co/zktLKYIniz	34.1157564000000022	-118.185404199999994	Highland Park, CA	563	\N
834266831938535424	2524046315	RT @PalmerReport: YouTube takes down Roger Stone’s channel after FBI fingers him in Trump-Russia scandal https://t.co/mbrCN3tgEb #TrumpRuss…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266831473016833	798369590975852544	@FoxNews @NBCNews @ABC @CBS @MSNBC and the rest of the MSM. The people considered you the enemy long before Trump said it. Stop pretending!	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266831330357248	802939510652805120	RT @BruceBartlett: John McCain talks a good line, but he never ever follows up with actions. Until he does he deserves no respect. https://…	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834266830961311749	49190798	RT @JoyAnnReid: .@Lawrence going there tonight on the question of Trump's mental health, and whether he has a firm grip on reality. #dutyto…	35.7595730999999972	-79.0192997000000048	North Carolina, USA	384	\N
834266830814531584	33260475	RT @Mikel_Jollett: Let's be very clear: Milo was an editor at Breitbart hired by Trump's closest advisor Steve Bannon.\n\nThis hatred is in t…	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834266829635727364	2322653682	I'm sure Trump will find a way to spin this as a "win": \n"We beat Obama in the first fortnight!" https://t.co/U0K835c4js	45.5230621999999983	-122.676481600000002	Portland, Oregon, USA	564	\N
834266829291925504	436103546	RT @peterwsinger: Sarah Sanders, a Trump spokeswoman, said Trump's visits to Mar-a-Lago make him accessible to "regular Americans" \nhttps:/…	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834266828557910016	424047059	RT @kylegriffin1: "Trump quacks, walks, and talks like an anti-Semite. That makes him an anti-Semite." —Anne Frank Center Exec. Dir. Steven…	43.6532259999999965	-79.3831842999999964	Toronto, Ontario	39	\N
834266828331315200	526633428	RT @ii_haymon: @BIZPACReview This is sick!!! No President should ever be treated the way Trump is being treated right now.	36.7782610000000005	-119.417932399999998	California	61	\N
834266828125904896	1206161593	Trump doesn't "tiptoe" https://t.co/LCN9QeGLc5	29.7604267	-95.3698028000000022	Houston,Texas	565	\N
834266827853352961	229010922	RT @BroderickGreer: Notice that Trump is never in the company of mainstream black intellectuals, activists, or civic leaders https://t.co/u…	40.7127837000000028	-74.0059413000000035	NYC	60	\N
834266827219836929	9063952	Donald Trump’s highly abnormal presidency: a running guide for February – VICE News https://t.co/0d78xgSfcW	47.6062094999999985	-122.332070799999997	Seattle	111	\N
834266825995083777	1222988930	RT @liu226: Do these 10 things, and Trump will be toast, via @mmflint https://t.co/NSpzMppyhr via @HuffPostPol	36.1699411999999967	-115.139829599999999	Las Vegas	566	\N
834266825990950912	824877546936295426	RT @GavinNewsom: RECAP-McConnell's ok with:\n-Attacks on judiciary\n-Hateful Muslim ban\n-Attacks on media\n-Praise for Putin\n...cool.\nhttps://…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266825395417088	21064184	RT @washingtonpost: Anne Frank Center slams Trump: "Do not make us Jews settle for crumbs of condescension" https://t.co/qhbOpBWpFZ	40.7652440999999968	-73.9902902999999981	Heart of Manhattan	567	\N
834266824942383104	297602297	RT @RBReich: We don't need to wait until '18 to begin to tip the House. Special elections are coming up in GA, KS, MT, CA, &amp; SC. https://t.…	39.5500506999999999	-105.782067400000003	Colorado & California	568	\N
834266824585904128	34766309	RT @TransEquality: Trump administration poised to change #transgender student bathroom guidelines https://t.co/xQJMaU8TCJ via @washingtonpo…	35.7795897000000025	-78.6381786999999974	Raleigh, NC	417	\N
834266824099430400	754478404515328000	After DJT quoted nonexistent events, Hannity says this https://t.co/PqzcBEa0xf	44.3148442999999972	-85.602364300000005	Michigan, USA	83	\N
834266823352782848	4777113617	RT @katz: Someone in Williamsburg is projecting a pregnant Trump, and Putin, on the side of a building https://t.co/yFkZ0Q2eY4	51.4815809999999985	-3.17908999999999997	Cardiff, Wales	569	\N
834266823302320129	444408640	RT @kylegriffin1: 33 days.\n\n132 false or misleading claims from Trump.\n\n0 days without a false statement https://t.co/24V21Vw2Mw\nhttps://t.…	37.7749294999999989	-122.419415499999999	San Francisco	37	\N
834266823184912384	148237540	RT @IndivisibleTeam: Your stories are so important.\n\nKeep them coming. Keep fighting.\n\nWe can win. https://t.co/5g4iyTnZS7	46.0869408000000007	-100.630127099999996	Standing with the Constitution	570	\N
834266822190956546	92677101	RT @VillanuevaEdgar: New in @HuffingtonPost: #Philanthropy, You in Danger, Girl!  5 Things We Need to Do NOW in the #Trump Age https://t.co…	25.7616797999999996	-80.1917901999999998	Miami, Florida	571	\N
834266822132260864	17659340	Former PM Mulroney: 'I wasn't singing for Trump' https://t.co/ez85df4CVK https://t.co/bNgzxCWQnf	43.6532259999999965	-79.3831842999999964	Toronto, ON, Canada	572	\N
834266821989646336	764489721644888065	RT @democraticbear: Once again, Rep. Maxine Waters (D) CA has stated the reality of Trump's people:  "Scum."  Most certainly, again, she is…	40.7891419999999982	-73.1349610000000041	long island ny	573	\N
834500581829931008	548943317	Cancel White House Correspondent's Dinner to Protest Trump https://t.co/UrXtiroJHo	34.2746459999999971	-119.229031599999999	Ventura, CA	678	\N
834266821477928960	708724060918710272	@McIlroyrory Comes Back Early From Golf Rehab to Tee It Up With President Trump - Breitbart https://t.co/Dc8elkzfp1 via @BreitbartNews	37.0902400000000014	-95.7128909999999991	United States	44	\N
834266821230489600	732574435102855168	Chuck Schumer: ‘Hope of America’ Is Republicans Break With Trump https://t.co/DQmBhyhJzM	43.7844397000000001	-88.7878678000000008	Wisconsin, USA	91	\N
834267226031144961	818606335336083456	RT @PalmerReport: Donald Trump’s strategy for blocking the 25th Amendment has been in plain sight all along https://t.co/u5uF0r8mjU	39.7684029999999993	-86.1580680000000001	Indianapolis, Indiana	574	\N
834267225129316355	39665865	RT @yottapoint: In just 1 month, Trump has cost taxpayers over 1/10th of Obama's entire 8-year travel expense https://t.co/8szRlrtGIj	54.5259613999999999	-105.255118699999997	North America	575	\N
834267224785481730	1921941900	@Turtle_Paulson @Darren32895836\n in Trump world organizing opposition is/will be a crime. The land of mushrooms!	31.8023831000000001	-97.0916691999999983	West Tx	576	\N
834267224084971520	259115841	@JxhnBinder @melmillerusa #cpac is a joke they will stack it with cucks. Other then Trump	26.1224385999999988	-80.1373174000000006	Ft lauderdale	577	\N
834267223803957249	63007815	RT @Italians4Trump: Rory McIlroy Comes Back Early From Golf Rehab to Tee It Up With President Trump - Breitbart https://t.co/7N2NbC9gAh	43.8338831000000013	-87.8200886999999994	Howards Grove, Wisconsin, USA	578	\N
834267222776360961	829735580	RT @FoxNews: President #Trump has had biggest #Dow gain in a president's 1st 30 days since 1909 https://t.co/9SWXWegxMC	35.7595730999999972	-79.0192997000000048	North Carolina	436	\N
834267222663102465	741095325516075010	RT @drugmember: There are people that willingly put pineapple on their pizza and y'all still tryna tell me Donald Trump is this country's b…	39.8089350999999994	-85.2913558999999992	Straughn Indiana, USA	579	\N
834267222520524800	10133922	The guys @WhyLose offer XM as a preferred #WhyLose #Forex broker. $30 no Deposit Bonus Now - Trump-Watching Likely https://t.co/tpONtZP8Wr	35.937496000000003	14.3754159999999995	Malta	580	\N
834267220494557184	3229912764	RT @2ALAW: Watch: What Happens When muslims Challenge Russians To A Street Style Fight.\n\nRetweet..If This Gave You Great Viewing Pleasure!👊…	36.7782610000000005	-119.417932399999998	California, & Texas 	581	\N
834267220339486720	538717804	President is mentally unstable  #My4WordWarningLabel #CrazyIsMySuperpower #trump	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834267218149928960	2693172618	RT @rasalom666: Bad news for sufferers of Trump Derangement Syndrome! Trump moves to target criminal illegals!! https://t.co/nYmpZ2s02F	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834267217508306944	36633505	Trump works &lt; any POTUS &amp; costs Amer. ppl the most. #entitled #whineylittlebitch #russiagate #investigatetrump https://t.co/wz489xK6T3	31.9685987999999988	-99.9018130999999983	Texas	381	\N
834267217051140096	753057467496558592	RT @immigrant4trump: VIDEO: French Presidential Candidate Marine Le Pen Refuses To Wear Headscarf To Meet Lebanon’s Grand Mufti #Trump http…	25.790654	-80.1300454999999943	Miami Beach, FL	260	\N
834267216912658432	241665167	RT @LifeNewsHQ: Liberals Trash First Lady Melania Trump for Leading Lord’s Prayer at a Rally, Call Her a “Whore” https://t.co/Y2NiBePy0v ht…	34.0522342000000009	-118.243684900000005	LA area	582	\N
834267216745000961	288310866	Trans bathrooms issue not federal... https://t.co/7Oyuc0s5mA	30.5082550999999995	-97.6788959999999946	Round Rock, Texas	583	\N
834267216128389120	17929186	@MuckRock Stock in private prison cos. shot up in wake of Trump election. https://t.co/NirzK6LNJF	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834267215847256064	2199196795	RT @kylegriffin1: Reminder— Trump reportedly paid actors to attend his presidential announcement: https://t.co/zW0qA1Pag4 https://t.co/oXeZ…	21.6684353999999999	-100.576029300000002	Tierra Nueva	584	\N
834267215817908224	2959759857	Sean Spicer attacks Anne Frank Center https://t.co/74RUvrEy1i #Trump's inactions speak louder than belated words. #AntiSemitism #NeverAgain	34.0483215000000001	-118.254849300000004	Los Angeles/New York	585	\N
834267215369211905	758329378203897856	RT @PoliticusSarah: Opinion: Three White Terrorist Arrests In One Week – Where’s Trump Outrage? via @politicususa https://t.co/0gupR4hKmG #…	46.7295530000000028	-94.6858998000000014	Minnesota, USA	262	\N
834267215100833792	1411678987	These are the American people Trump calls enemies of the American people https://t.co/WnflmY682k	42.3338097000000033	-73.3677581999999973	West Stockbridge MA USA	586	\N
834267214220029953	47148844	RT @TimOBrien: And thank YOU, American taxpayers, for helping fund the Trumps' travel so this new venture could launch--while POTUS stays c…	40.7127837000000028	-74.0059413000000035	New York	214	\N
834267213599092736	17696313	RT @soledadobrien: Actually Donald Trump suggested execution for 5 young black men in Central Park jogger case. They were wrongfully convic…	30.1713908000000011	-95.4523173999999983	the nearest Luby's	587	\N
834267213385330688	56682701	RT @nytimes: 3 generals bound by Iraq will guide President Trump on security https://t.co/4lqGJsZvX2 https://t.co/Jc5VN0GZeX	41.7508391000000003	-88.1535351999999932	Naperville	588	\N
834267211397165056	739691269656477696	RT @StockMonsterUSA: KABOOM : Donald Trump Administration Strips Funding For Illegal Aliens, Reallocates Money to Victims of Their Crimes\nh…	39.5500506999999999	-105.782067400000003	Colorado, USA	212	\N
834267210789093376	108063745	RT @kylegriffin1: 33 days.\n\n132 false or misleading claims from Trump.\n\n0 days without a false statement https://t.co/24V21Vw2Mw\nhttps://t.…	43.3255195999999998	-79.7990319000000028	Burlington,ont	589	\N
834267210361163776	227259371	RT @CNNPolitics: President Trump's aides don't want to admit the President is golfing https://t.co/OyVC0KhRdZ https://t.co/GScN3nwAjD	-42.8821377000000012	147.327194899999995	Hobart, Australia	590	\N
834267210054905856	2653978472	RT @Fahrenthold: PGA chief got a "social" call out of the blue from @realDonaldTrump, whose golf courses have sought PGA events. https://t.…	51.5492774000000011	-0.108230199999999999	Not Islington, London 	591	\N
834267209740468224	264265349	RT @joshrogin: Austria approves extraditions to U.S. of Ukrainian billionaire tied to Manafort https://t.co/TFQ3mzgqtl by @ARothWP	45.4215295999999995	-75.6971931000000069	Ottawa, ON	592	\N
834267208259862528	773169389902270469	RT @CResisting: @yashar @rep_stevewomack funny thing is that trump and republicans believe these are all liberals.  They are not and they a…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834267208201039872	724248142485450752	New York Just Filed A Tax Warrant Against Ivanka Trump For Dodging Taxes - https://t.co/V6RQJSmnXB	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
834267207924330496	18269496	Trump’s New Guidance Calls for Vigorous Immigration Enforcement https://t.co/1Obi7DGWqb	31.9685987999999988	-99.9018130999999983	Texas	381	\N
834267207517478913	456124249	RT @thinkprogress: Trump claims he denounces anti-Semitism ‘wherever I get a chance.’ Actually, he doesn’t.\nhttps://t.co/RU1V5ox1Lh https:/…	41.2033216000000024	-77.1945247000000023	Pa	593	\N
834267205613281280	18662449	RT @jonfavs: Remember: \n1) Trump's base may support him until the bitter end.\n2) Trump needed voters outside his base to win, and will in 2…	34.2331373000000028	-102.410749300000006	The Earth	536	\N
834267205474725889	462609615	RT @momztweet: @JooBilly @IndivisibleTeam @ARGOP They're playing a game like Trump. Do the obligatory press conference, put your rabid fans…	41.9340157999999974	-87.661010399999995	Left Coast. USA	594	\N
834267205462167552	21250667	RT @NewYorker: In less than a week—a nanosecond in museum bureaucracy—the @whitneymuseum made a change in resistance to Trump: https://t.co…	47.6062094999999985	-122.332070799999997	SEATTLE	595	\N
834267205265002496	4042851734	Cutting short post-study period: No US dream for Indian youth in Trump era? https://t.co/Jc7j8TaZPj https://t.co/RHv0YqzEs7	23.6345010000000002	-102.552784000000003	Mexico 	596	\N
834267205151899648	342996178	RT @JBurtonXP: Muslims in Sweden just had to NOT RIOT for like one week in order to make Trump look like he was wrong, but they couldn't ev…	40.748440500000001	-73.9856644000000045	The Empire State	597	\N
834267204938002432	2907287903	Straight up read this as Donald Trump, but was reminded that the world is a cruel, harsh place. https://t.co/rdgZL6rLtL	47.4941835999999995	-111.283344900000003	Great Falls, Montana	598	\N
834267204933779457	4231753156	@josh_hammer \nUnironic : This is very much correct\nLess so : GOP could become so diminished that Donald Trump could take it over?	42.4400357000000028	-85.648903500000003	Plainwell, MI	599	\N
834267202865995776	3648946277	RT @ZaRdOz420WPN: petition: Hey, Trump: If You Repeal Obamacare, Replace it with Single-Payer Healthcare! \n#P4SED \nhttps://t.co/63u0b9pRnu	37.0902400000000014	-95.7128909999999991	 United States of America	475	\N
834267202433990657	2235007050	Remember how the Republican's "average guy" was Joe the plumber? Now it's the guy who salutes cardboard cutout Trump every day.	44.9537029000000032	-93.0899577999999934	St Paul, MN	600	\N
834267202278785025	34413749	Pastor storms out of Trump's 'demonic' rally:' My 11-year-old daughter was 'sobbing in fear' https://t.co/0PgvSwMmrc	29.4241218999999994	-98.4936282000000034	san antonio, tx	601	\N
834267202153021440	3315464599	RT @zip90210: U.S. District Attorney to charge Obama with Treason + other top stories https://t.co/fgBE0q3Umv\n#TrumpPresident \n#tuesdaymoti…	33.4959788999999972	-88.3839210999999949	Alabama, USA, Mississippi, USA	602	\N
834267201892909058	103485019	RT @kylegriffin1: CIA officer resigns over Trump.\n\n"I cannot in good faith serve this administration as an intelligence professional." http…	37.0902400000000014	-95.7128909999999991	USA	56	\N
834267200521269248	4053945194	Cutting short post-study period: No US dream for Indian youth in Trump era? https://t.co/6z2HaQNRG3 https://t.co/5jytc75Eaf	23.6345010000000002	-102.552784000000003	México 	603	\N
834267200261222401	4066232723	Cutting short post-study period: No US dream for Indian youth in Trump era? https://t.co/lq1RJjwaBo https://t.co/YAFgMlSsvt	23.6345010000000002	-102.552784000000003	México 	603	\N
834267199665745920	14969093	Opinion | Trump is set to introduce a new 'Muslim ban.' This one is nonsense, too. https://t.co/Yft0ttSymn	34.2331373000000028	-102.410749300000006	Earth	481	\N
834267199133069312	827365484236513280	RT @altNOAA: If Trump was just going to destroy the reputation of the GOP, I'd be fine with it. It's the reputation of the USA that will be…	37.0902400000000014	-95.7128909999999991	southwest usa	604	\N
834267198281613313	479032793	Jimmy Fallon.  Seriously?  Your writers can't come up with anything better than bad Trump jokes?!  #liberalmedia #FakeNewsMedia	35.6528323	-97.4780954000000008	Edmond, OK	605	\N
834267197627211776	74149816	RT @ddiamond: That's from this terrific @nancook profile of Don McGahn, the lawyer who signed off on Trump's executive orders. https://t.co…	56.1303660000000022	-106.346771000000004	Canada	257	\N
834267197618913280	1405493413	RT @soledadobrien: Same poll: 68 percent say Trump should be willing to compromise and find ways to work with Democrats in Congress. https:…	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834267197287510016	4048485974	Cutting short post-study period: No US dream for Indian youth in Trump era? https://t.co/CfgKGZZjJQ https://t.co/dqA9fdJYL7	23.6345010000000002	-102.552784000000003	México 	603	\N
834267197207826432	3065650245	RT @redwhiteblue45: 👍🇺🇸Thank God 4 Trump 🇺🇸👍  #TG4T	32.7157380000000018	-117.1610838	San Diego	606	\N
834267195781812224	271602903	Trump's being sabotaged on all sides, Deep State with vile #NeverTrump's help is getting some hits...BUT THIS IS NO… https://t.co/cE0hBo1iC0	37.0902400000000014	-95.7128909999999991	USA	56	\N
834267194657734656	38561476	Uber driver: "It's 60° in Chicago in February. Donald Trump is president. The Cubs won the World Series. Are we sure this is real life?"	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
834267194284449792	16963034	RT @TeriGRight: We voted #Trump to #StopCommonCore!\n#POTUS PLEASE #KeepYourPromise to America's Children!\n#MAGA #PJNET #TCOT https://t.co/h…	33.6356618000000012	-96.6088804999999979	Sherman, TX	607	\N
834267193550331905	62167206	Trump can't come clean on Russia, because the cover-up is all that keeps him in office https://t.co/tSdGwsXisi	46.1467790000000022	-122.908444500000002	Kelso, Washington	608	\N
834267190954176514	15315979	RT @tonyhschu: Neat scrollytelling piece from @nytimes about immigration! https://t.co/9cFnXJYpsi by @haeyoun and @TroyEricG	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834267189544787968	19730650	Automakers Ask Trump's EPA Boss to Toss Obama Mileage Decision https://t.co/Up61iy987h https://t.co/NCBsUcIl6F	32.3668052000000017	-86.2999688999999961	Montgomery, AL	609	\N
834267189461020673	63007815	RT @Italians4Trump: Irrespective Of Travel Ban, Trump Has Broad Executive Powers On Immigration Enforcement | Zero Hedge https://t.co/AbKGN…	43.8338831000000013	-87.8200886999999994	Howards Grove, Wisconsin, USA	578	\N
834267189074989056	17927511	If there is a single issue emerging to unify our country, it's probably universal health care https://t.co/O45PE0SmF2 #trump #SinglePayer	40.7607793000000029	-111.891047400000005	Salt Lake City	610	\N
834267188894760966	42326387	RT @mic: National Security Council spokesman Edward Price resigns over Trump and Stephen Bannon https://t.co/RZpo36Xthv https://t.co/bmcf5C…	40.6781784000000002	-73.9441578999999933	Brooklyn	611	\N
834267187829415936	792100041733308416	RT @Coulterfan22: Riots in Sweden. Trump right again. He's the savior of the modern world. #maga	40.7282239000000033	-73.7948516000000012	Queens, NY	134	\N
834267187774906369	386028702	RT @mitchellvii: #Setism - "The new political reality wherein previously wimpy PC world leaders suddenly grow a set inspired by Trump's bol…	40.2671940999999975	-86.1349019000000027	Indiana, USA	100	\N
834267186776666112	2244290719	The psychological and philosophical reasons it feels like it's been years since Donald Trump's inauguration https://t.co/sWo0WKGvnE	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834267185631608833	736719148890329088	RT @kylegriffin1: Reminder— Trump reportedly paid actors to attend his presidential announcement: https://t.co/zW0qA1Pag4 https://t.co/oXeZ…	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
834267185270886401	148663	RT @JuddLegum: Trump’s first month travel expenses cost taxpayers just about what Obama spent in a year https://t.co/HYBO2HBiqQ https://t.c…	32.8406945999999991	-83.6324022000000014	Macon, GA	612	\N
834267184931172352	72130758	A Lifelong Republican Ex-Judge Just Called For Trump's Impeachment https://t.co/4cUAq9GVa2	25.7616797999999996	-80.1917901999999998	Miami Florida	613	\N
834267408512741377	808073398756798464	@cveidson \nHis daughter and close confidant is Jewish. Trump is the most Jewish president we've ever had.	37.0902400000000014	-95.7128909999999991	Northeast, USA	614	\N
834267406902112258	75029631	RT @Mikel_Jollett: Let's be very clear: Milo was an editor at Breitbart hired by Trump's closest advisor Steve Bannon.\n\nThis hatred is in t…	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
834267406453215232	796961848289611776	RT @RBReich: The 14th Amendment bars government from depriving any person of life, liberty, or property without due process.\n\nTrump says to…	34.9592083000000002	-116.419388999999995	SOCAL, USA	615	\N
834267405169876996	187007833	so ya think Trump was wrong about Sweden.. lol.. maybe follow some people that actually live there... https://t.co/9wOBqJ9Tgk	41.6509652000000017	-87.538349199999999	arizona/illinois	616	\N
834500708669984771	198817236	New Planets discovered.  Trump puts them on the no-fly list.	56.4906712000000013	-4.20264579999999999	Scotland	51	\N
834267404997779456	27512270	RT @leahmcelrath: Trump conned 46% of voters into believing he's a "populist."\nNow the WH is continuing the con.\n\nBy me for @Shareblue\nhttp…	61.2180555999999996	-149.900277799999998	Anchorage, AK	617	\N
834267404729454592	476398014	RT @Cernovich: It's almost as if Trump stakes out an aggressive first offer as he describes in great detail in his 30+ year old book. https…	36.1626637999999971	-86.7816016000000019	Nashville, TN	618	\N
834267404666441728	126852418	#Poll: 132% of Americans want @KellyannePolls to disappear along with Donald Trump, Steve Bannon, and Sean Spicy. https://t.co/oQ5FYXd54A	37.0902400000000014	-95.7128909999999991	USA	56	\N
834267404205060096	3158451439	RT @michaelharrisdr: This is what #Trump meant when he spoke of #Putin! "Do I not destroy my enemies when I make them my friends"? https://…	-33.8688197000000031	151.209295499999996	Sydney, New South Wales	619	\N
834267403534020608	263157510	RT @mrochabrun: .@DHSgov just confirmed our @propublica story: the US wants to deport migrants to Mexico even if they aren't Mexican https:…	44.9374831000000015	-93.2009998000000053	Twin Cities, MN	620	\N
834267401701175296	46272091	RT @BraddJaffy: Crowd asks Rep. Steve Womack (R-AR) to investigate Trump/Russia. \n\nWait for it... https://t.co/4siV7A0cOR	38.5976262000000006	-80.4549025999999969	West Virginia, USA	393	\N
834267401072021504	2256840859	RT @SallyAlbright: Rachel @Maddow reporting Trump's call with Taiwan's president caused trouble with China. It's unimaginable that it would…	31.5429658000000011	-97.1498878000000019	the cutting edge	621	\N
834267400841330688	138482341	RT @AC360: .@VanJones68 on Trump: "He has an opportunity, rare in that office, to be a special champion against racism" https://t.co/FVWFE1…	33.7489953999999983	-84.3879823999999985	ATL 	622	\N
834267400468123651	19558983	RT @greenhousenyt: HYPOCRISY: Trump has made 132 false or misleading claims in 33 days—4 a day. Yet he calls the press dishonest. SAD! http…	41.3797787999999969	-83.6300825999999944	Bowling green massacre	623	\N
834267399549444096	20477596	RT @TheViewFromLL2: In other words: President Trump has lied under oath, in multiple depositions spanning a decade, about his relationship…	-36.8484596999999994	174.763331499999993	Auckland, NZ	624	\N
834267399146860546	14097197	RT @washingtonpost: "Trump wasn’t a real CEO. No wonder his White House is disorganized." https://t.co/XnXtBfTxWV  via @PostEverything	42.4072107000000003	-71.3824374000000006	Massachusetts	202	\N
834267399129952257	1706302074	Deep state globalists hate that Trump is destroying their empire game. https://t.co/QFnDNsTLmt	37.7652064999999979	-122.241635500000001	Alameda, CA	625	\N
834267398811303936	2682728899	RT @ChangFrick: For my english readers: Donald Trump is correct – I live in an immigrant area in Sweden and it is not working well https://…	56.1303660000000022	-106.346771000000004	Canada & International	626	\N
834267397280432128	18269496	A Swedish Gaffe That Wasn’t https://t.co/1LaOwFQ9dd	31.9685987999999988	-99.9018130999999983	Texas	381	\N
834267397091651584	1890992798	Here’s Who Would Save The Most Money Under Trump’s Propose | https://t.co/J9019lXd78 | #ReasonStrategyExecution https://t.co/V3XOnh8MPg	39.739235800000003	-104.990251000000001	Denver, CO	361	\N
834267397036994562	54773913	RT @smokesangel: Since Ronald Reagan there has not been a good @POTUS until we voted in Trump. Thank You Lord for a Christian President and…	33.3945681000000008	-104.522928100000001	3rd Rock from the Sun	627	\N
834267396823252993	3308686370	RT @SouthLoneStar: Dalai Lama, the leader of Buddhists: "Europe has taken in too many migrants" - agrees with Trump.\n\nRefugees Welcome.	34.0099868000000001	-118.337462299999999	A Southern Gal	628	\N
834267396798107650	293559094	@JoeyShababoo @VP @POTUS it's sad that the idiot trump is so pathetic that you begin to expect something better from the other idiot pence	38.6270025000000032	-90.1994042000000036	Saint Louis	629	\N
834267396676415489	46139343	RT @washingtonpost: "Trump wasn’t a real CEO. No wonder his White House is disorganized." https://t.co/XnXtBfTxWV  via @PostEverything	33.7489953999999983	-84.3879823999999985	Atlanta, GA	289	\N
834267396147802112	724706472857214976	RT @Elizasoul80: Remember how the Republican's "average guy" was Joe the plumber? Now it's the guy who salutes cardboard cutout Trump every…	49.2827290999999974	-123.120737500000004	Near Vancouver	630	\N
834267396135268354	78622104	RT @BMLewis2: Remember when Trump mocked Clinton for being wonky? That was a big clue about his presidency https://t.co/BF9aewueGx	32.0005282999999991	-110.700920600000003	Vail, AZ	631	\N
834267396126957568	22831555	RT @marcushjohnson: What happened to Milo today is what should have happened to Trump after the video came out	42.1857745000000008	-122.695808	Central Oregon 	632	\N
834267395652857856	1101298442	RT @nytimes: 3 generals bound by Iraq will guide President Trump on security https://t.co/4lqGJsZvX2 https://t.co/Jc5VN0GZeX	41.736980299999999	-111.833835899999997	Logan, UT	633	\N
834267394898026496	2584830338	RT @BIZPACReview: Florida teacher gets ‘reassigned’ for making pro-Trump Facebook status praising deportation https://t.co/ZlhbCIaEzU https…	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834267394293895168	1186457310	RT @SkidneyVee: But they never evaluated him in person? Crazy.\n\nIs Donald Trump sane? The evidence suggests he's not https://t.co/SESxOc10X…	45.5230621999999983	-122.676481600000002	Portland, OREGON	634	\N
834267394109366272	74149816	RT @Fahrenthold: PGA chief got a "social" call out of the blue from @realDonaldTrump, whose golf courses have sought PGA events. https://t.…	56.1303660000000022	-106.346771000000004	Canada	257	\N
834267393962733568	341240159	RT @Amy_Siskind: I really feel this in my bones:\nDonald Trump will not make it out of 2017.\nAny Republican who stands by him will not make…	42.3600824999999972	-71.0588800999999961	Boston, MA	149	\N
834267392003956736	1956515965	RT @ScottAdamsSays: Do the over-generalizations cancel out? #Trump https://t.co/SkUHi8fa6J	27.6648274000000001	-81.5157535000000024	US Florida & Belize	635	\N
834267391504875521	234536971	RT @RawStory: ‘Words fall far short of deeds’: Dan Rather rips Trump for denouncing anti-semitism — and keeping Bannon https://t.co/OjxxjMu…	42.4072107000000003	-71.3824374000000006	MA 	636	\N
834267391492108288	18771487	RT @nowhitenonsense: Oregon’s governor is forbidding all state employees from helping Trump’s ICE agents https://t.co/X6OImtY6ck via @USUnc…	45.5230621999999983	-122.676481600000002	Portland, OR	41	\N
834267389839581186	534929951	RT @BruceBartlett: John McCain talks a good line, but he never ever follows up with actions. Until he does he deserves no respect. https://…	49.8879518999999974	-119.496010600000005	Kelowna BC	637	\N
834267389797683200	825121634570760195	https://t.co/RI2lrdSVe7 ITS TIME TO GET RID OF #PresidentBannon	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834267389151809537	818778290525765632	RT @DebFreedomVoice: And the #AltLeft continues to spin Trump needs to get to work &amp; stop tweeting 😂😂😂 https://t.co/t36FyTVVNd	42.606409499999998	-83.1497750999999994	Troy, MICHIGAN	638	\N
834267389046951936	19198839	@CasaMadison @POTUS the post is noting putin &amp; associates $ as may be linked to trump - we'll see what @FBI turns up - that's the point	37.0902400000000014	-95.7128909999999991	United States	44	\N
834267387788664832	217711375	RT @businessinsider: California congresswoman calls Trump's cabinet the 'Kremlin clan' https://t.co/oGYAaErunb https://t.co/RJZIovC2td	-0.0235590000000000001	37.9061930000000018	Kenya	639	\N
834267387599876096	297719462	RT @StockMonsterUSA: Since Full Scale Rioting began in Sweden hours ago It's been Crickets frm Media. https://t.co/8tET3T2qVg #TuesdayMotiv…	-25.2743980000000015	133.775136000000003	    Australia	640	\N
834267884419428352	39702190	RT @soledadobrien: Same poll: 68 percent say Trump should be willing to compromise and find ways to work with Democrats in Congress. https:…	41.3894905000000008	-82.019032100000004	North Ridgeville, Ohio	641	\N
834267883957989376	48799836	RT @activist360: You don't have to be a doctor to conclude that lunatic Trump is mentally 'unable to discharge the powers &amp; duties of his o…	34.0522342000000009	-118.243684900000005	LA	259	\N
834267883224043525	379511613	RT @thehill: GOP rep defends town hall protesters after Trump tweet: "They are our fellow Americans with legitimate concerns" https://t.co/…	34.2331373000000028	-102.410749300000006	Earth	481	\N
834267882670477313	800012172013211648	@FoxNews @POTUS @RefuseFascism Did Trump invade any country, arrest journalists, kill jews? These stupid liberals' claims should go to hell!	44.9537029000000032	-93.0899577999999934	St Paul, MN	600	\N
834267882120962055	2256840859	RT @stephaniebhall: And somehow, in our election postmortems, we're not supposed to talk about sexism. Even though we all remember "Trump t…	31.5429658000000011	-97.1498878000000019	the cutting edge	621	\N
834267879541448704	31312712	RT @womensmarch: We're excited to team up with @womensstrike on March 8th. Please read this op-ed. #WomensStrike #DayWithoutAWoman https://…	43.4113603999999995	-106.2800242	Midwest, USA	66	\N
834267879474343936	794603925810905089	RT @TrumpSWOhio: WikiLeaks: Clinton Bribed 6 Republicans To 'Destroy Trump' https://t.co/jT3RmmvZPa	38.3291954999999973	-121.979503699999995	hell on earth	643	\N
834267879402975233	380664031	RT @TheViewFromLL2: Sater was Trump's top talent when it came to scouting out new Trump Tower locations. It's who Trump relies on to get fo…	53.5443890000000025	-113.490926700000003	Edmonton, Alberta, Canada	644	\N
834267879172345856	100346357	RT @TrinaAltadonna: @BernieSanders Stop spreading Bull Bernie! Fear has always been a source for controlling society. Obama did more to hur…	39.5500506999999999	-105.782067400000003	Colorado, USA	212	\N
834267878673223680	269511432	RT @thehill: Republicans at risk in 2018 steering clear of town halls to avoid anti-Trump protesters https://t.co/cxPQcIazkC https://t.co/S…	39.739235800000003	-104.990251000000001	Denver, CO	361	\N
834267877574311936	2521147680	RT @TEN_GOP: BREAKING: Massive riots happening now in Sweden. Stockholm in flames. Trump was right again!\nhttps://t.co/ZQa9Res2tu https://t…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834267877406625794	776959799871303681	RT @MaxineWaters: Trump cannot assure us no one on his team communicated w/ Russia last year. What does he know? Where are his taxes? #krem…	38.4852928000000034	-78.9514510000000058	Central Virginia	645	\N
834267877322661888	4425444254	RT @GopRachel: Poll: A good majority of Americans oppose sanctuary cities, and support Trump’s immigration efforts https://t.co/4idpgEwRPC…	30.622970200000001	-85.7121530999999948	Vernon, Florida 	646	\N
834267876303450113	76824386	RT @thehill: Anne Frank Center: Trump's anti-Semitism response "too little, too late" https://t.co/GwpUaNl2IN https://t.co/uHmvWfGCu7	40.6642699000000007	-73.7084645000000052	Valley Stream, NY	647	\N
834267875800125440	708713211839643648	Trump will due fyne... he surrounds himself with Ladies to keep him in line!!! Heeheee	36.0345159000000024	-89.3856281000000052	Dyersburg, TN	648	\N
834267871085727744	827285120067317762	RT @JBurtonXP: Swedes EVISCERATE Trump by smugly mocking his anti-immigration comments as fire and bloodshed flare up once again in their c…	32.7120882999999978	-94.1212964999999997	Uncertain,Texas, USA	649	\N
834267871035416578	32879813	RT @kylegriffin1: Trump's 1st month in office includes:\n\nGolf—25 hrs\nForeign relations—21 hrs\nTweeting—13 hrs\nIntel briefings—6 hrs\nhttps:/…	37.0902400000000014	-95.7128909999999991	US	280	\N
834267870301294592	3836322913	RT @RBReich: You might want to send this to anyone you know who voted for Trump. \n(Thx to Rosa Figueroa who posted this responding to one o…	44.927897999999999	-122.983705900000004	Four Corners, OR	650	\N
834267870087442432	55601282	@The_Trump_Train No doubt. Yes.	36.7782610000000005	-119.417932399999998	California	61	\N
834267868762087424	249537404	Most Trump Voters Say The Media Is Their Enemy - The Huffington Post https://t.co/BUK26M6gcD	33.4936391000000029	-117.148364799999996	Temecula, CA	651	\N
834267868707557377	1875605521	RT @ddale8: Photog: "Washington Post." Trump supporter: "Corrupt news media corrupt news media!" "Mind if I take a picture?" "Not at all."…	55.6760968000000034	12.5683371000000008	Copenhagen	652	\N
834267867424124929	754348407091818496	Travel industry next victims of Trump policy. https://t.co/3DCWbtPLPC	29.7604267	-95.3698028000000022	Houston, TX	167	\N
834267866891427841	813771045710729216	RT @ABCPolitics: .@RepCummings: "Do you hear that?...This is the sound of House Republicans conducting no oversight of Pres. Trump." https:…	40.262570199999999	-80.1872797000000048	Canonsburg, PA	653	\N
834267864249008128	18662449	RT @samswey: Learn more about Trump's immigration policy, how it impacts communities &amp; what you can do to resist at: https://t.co/MTKvBAkbHK	34.2331373000000028	-102.410749300000006	The Earth	536	\N
834267863074627584	432032738	Girls be saying "#ilovebeinglatina" but support Trump 😴	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
834267862789402625	2301528260	RT @Mark_Beech: New dates added to @rogerwaters Us &amp; Them @rogerwaterstour see also https://t.co/X2mLQ0BAVR https://t.co/zy1GIH7URf https:/…	35.7595730999999972	-79.0192997000000048	North Carolina	436	\N
834267861883432960	18226362	"If I tattoo trump on my lip AND do this sick spider-leg mascara maybe a frat guy will ask me to semi" https://t.co/frCqeKG6uS	42.4072107000000003	-71.3824374000000006	Massachusetts, USA	64	\N
834267861526867968	38495355	RT @thehill: Trump's new national security adviser pick marks big change on Russia https://t.co/WxHYTc9z3Q https://t.co/sg96vLJIKj	36.1699411999999967	-115.139829599999999	Las Vegas, NV	218	\N
834267860616749058	443605395	RT @tylerrwebster: Daily reminder that Donald Trump is your President 😊 https://t.co/Tx13n1dXix	30.230920900000001	-92.5311776000000066	Trump's America	654	\N
834267859098427394	717259750761635840	First assassination attempt on President Donald Trump (Circa 2016) https://t.co/2r7uF3zSat	43.8041333999999978	-120.554201199999994	Oregon, USA	655	\N
834267858947416065	1411678987	RT @JoyAnnReid: .@Lawrence going there tonight on the question of Trump's mental health, and whether he has a firm grip on reality. #dutyto…	42.3338097000000033	-73.3677581999999973	West Stockbridge MA USA	586	\N
834267858607542272	286163867	RT @TheStranger: Unlike GOP reps, @PramilaJayapal  will hold a town hall meeting for constituents in Seattle during the recess: https://t.c…	46.5180823999999973	-123.826451199999994	Pacific Northwest	656	\N
834267857890353157	828835841258594304	RT @RBReich: You might want to send this to anyone you know who voted for Trump. \n(Thx to Rosa Figueroa who posted this responding to one o…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834498507004338180	2883346446	RT @mattyglesias: um … what kind of investments? https://t.co/c8dUVpZDca https://t.co/3ZqxeZ63Bb	37.0902400000000014	-95.7128909999999991	United States	44	\N
834498506631036929	370875869	RT @kylegriffin1: Trump's 1st month in office includes:\n\nGolf—25 hrs\nForeign relations—21 hrs\nTweeting—13 hrs\nIntel briefings—6 hrs\nhttps:/…	39.0457548999999986	-76.6412712000000056	Maryland USA	657	\N
834498505758478336	798350907159101442	RT @naretevduorp: Another Trump team fail. https://t.co/Qm0KXN6pkP	37.613825300000002	-122.486919400000005	Pacifica, CA	658	\N
834498505716748288	2335844449	RT @tparsi: WOW! The job descriptions of White House staffers and kindergarten teachers are surprisingly similar these days...\n\nhttps://t.c…	54.5259613999999999	15.2551187000000006	Europe	659	\N
834498505641168901	69478952	Donald Trump has misled public on every single one of his 33 days as President https://t.co/zfsqBWv2XD There's a shock. NOT.	42.1925746000000004	-76.0610360999999955	NY/Maine	660	\N
834498505402101760	774765613889626112	RT @AltStateDpt: Constitution restricts emolument from foreign government\n\nTrump endorses One China, gets Chinese trademark\n\nAsk your Rep w…	33.0151205000000019	-96.6130485999999991	Murphy, TX	661	\N
834500596728160256	3018140491	Donald Trump aide Sebastian Gorka accuses BBC of 'fake news'- BBC Newsnight https://t.co/m6chtqfzNp	50.040548600000001	-110.676425800000004	Medicine Hat Ab Canada	662	\N
834500596388425730	714137230239866880	This Top Democrat Calls Trump Administration “A Bunch Of Scumbags” [Video] https://t.co/utcLGF7skg	36.0395247000000012	-114.981721300000004	Henderson, NV	663	\N
834500595910184960	823575801597751296	#Trump 🇺🇸 Malia Swarmed By Paparazzi When They Look Down &amp; See What’s Missing https://t.co/MHbMRAeODw 👈See Here 🇺🇸 https://t.co/W57IiTFtH9	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
834500595822239745	23191482	RT @thehill: Top Dem on hiring freeze affecting military childcare: Trump "should be embarrassed" https://t.co/ohuxneyICH https://t.co/u1Sh…	27.6648274000000001	-81.5157535000000024	Florida	183	\N
834500595146952706	39582911	RT @RBReich: You might want to send this to anyone you know who voted for Trump. \n(Thx to Rosa Figueroa who posted this responding to one o…	26.1224385999999988	-80.1373174000000006	Fort Lauderdale	664	\N
834500594563964933	2341214017	RT @3lectric5heep: #Ohio - Contact your Senators!\n\nLet them know you VOTE, and you expect them to Fully Support President Trump\n\nhttps://t.…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834500594396073984	15383887	RT @Wahlid: Welcome to Trump's America https://t.co/l7wVzR4tlX	34.9592083000000002	-116.419388999999995	Southern California	50	\N
834500594333134848	24150823	Kellyanne Conway reportedly benched from TV by Team Trump https://t.co/l9Y0xT2FA6 https://t.co/nrEDcDaBJQ	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834500594173956096	4106597901	RT @redbluewitham: Latest piece discusses how the Anti Trump movement is dead in its tracks\n\nhttps://t.co/Xipsz7S5Ia\n\n@RynoOnAir \n@scrowder…	40.748440500000001	-73.9856644000000045	The Empire State 	665	\N
834500594148765696	4404515537	@butchparnell Or creating safe zones, which is what Trump wants to do. I am in full support of this.	37.0902400000000014	-95.7128909999999991	USA	56	\N
834500593918103553	1460474131	@Nouriel @MaxBoot @POTUS @realDonaldTrump Failing Donald Trump. Sad!	37.0902400000000014	-95.7128909999999991	United States	44	\N
834500593142030336	31532083	Usually flaks plant stories to drive public opinion or make their boss look good. Trump's flaks do it to keep him h… https://t.co/kubnn1KN2F	38.5815719000000001	-121.494399599999994	Sacramento	666	\N
834500592919785473	827538640737820674	RT @JohnJHarwood: POTUS 2/9: "We're going to be announcing something phenomenal in terms of tax" \nHill Rs now: we don't expect WH plan\nhttp…	39.5500506999999999	-105.782067400000003	Colorado, USA	212	\N
834500592886128641	800535028866220033	Kellyanne Conway reportedly benched from TV by Team Trump https://t.co/MaB4xgnhtd https://t.co/qU17yJwjAY	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
834500592823308288	42641225	@Morning_Joe PRAYERS FOR #TRUMP #AMERICA ALL BAD LIBERALS BURNING CARS AND RIOTING. END ABORTION OPPOSITE OF LIBERA… https://t.co/PUeeCQbU4V	44.9334927000000022	7.54074940000000016	NONE	667	\N
834500592533958658	257415645	So Trump wants to deport people to Mexico even if they are not Mexicans? Good luck with that Donald.	53.9345810000000014	-9.35164559999999945	Mayo	668	\N
834500591741239298	798256855214653440	.@Newsweek @CFR_org @edwardalden I suspect Trump admin's definition of success is different than 1 you're using here (or 1 they're selling)	41.5048158000000029	-73.9695832000000024	Beacon, NY	669	\N
834500591661486082	1415657671	I liked Shep until he started making snarky anti-Trump remarks when reporting the news. Give me the story and let m… https://t.co/m6HaRTRXiq	43.9324854999999985	-103.575192999999999	Hill City, SD	670	\N
834500591661375488	18198208	RT @conradhackett: Republicans trust Trump more than Congress\nDemocrats fear Congress won't stop Trump\n\nhttps://t.co/R35uH54ywU https://t.c…	47.6062094999999985	-122.332070799999997	Seattle, WA	139	\N
834500591644663808	21610870	If only she had stuck 2 her guns. If she had only had the courage of her convictions, Trump would have fired her. https://t.co/hLJJ8v32Eh	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834500591023857664	34663425	When somebody challenges you, fight back. Be brutal, be tough. Donald Trump	46.7295530000000028	-94.6858998000000014	Minnesota, USA	262	\N
834500590902185984	88584153	RT @ZaneSafrit: Via @peterwsinger: Trump spends twice as long tweeting\nas he has in intelligence briefings\nhttps://t.co/TX3UBMyWPZ via @vel…	39.739235800000003	-104.990251000000001	Denver, CO	361	\N
834500590331953154	4322390847	RT @Rockprincess818: The left is circling back to "Trump is Anti-Semitic" which tells me they are conceding to themselves that the Russian…	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834500590277386241	1858468885	RT @TheDemocrats: Trump's "deportation force" is:\n✔️ Extreme\n✔️ Frightening\n✔️ Expensive\n✔️ Detrimental to deeply held American values\nhttp…	46.8181879999999992	8.22751200000000082	Switzerland	671	\N
834500588985524225	261375916	Saul "Peace is a lie..." Alinsky taught Obama the Sith Code.  https://t.co/7a5HAKz2fk	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
834500588922560512	784799572560228352	RT @Politics_PR: Former CIA official says having Trump in the White House is the gravest threat since Civil War https://t.co/Hjy9swVHaq #p2…	33.4269728000000015	-117.611992499999999	San Clemente, CA	672	\N
834500588599701505	23789618	RT @thehill: "Sanders, not Trump, is the real working-class hero" https://t.co/CqNmCIHCK9 https://t.co/P6CBefQpU7	51.2537749999999974	-85.3232138999999989	Ontario, Canada	252	\N
834500588196999169	16331010	Donald Trump's Star Vandal Dodges Jail in Plea Bargain https://t.co/TCDVqVqua6	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834500588138352640	44513456	RT @ddale8: According to Alveda King, this is how President Trump reacted to the slavery exhibit yesterday: https://t.co/UA24mjQCRQ https:/…	33.7489953999999983	-84.3879823999999985	Atlanta, GA	289	\N
834500587517538304	876523207	RT @thehill: Top Dem on hiring freeze affecting military childcare: Trump "should be embarrassed" https://t.co/ohuxneyICH https://t.co/u1Sh…	40.0583237999999966	-74.4056611999999973	new jersey	673	\N
834500587152551937	830491680453300224	Malia Swarmed By Paparazzi When They Look Down &amp; See What’s Missing https://t.co/Pseeyxp4Sk https://t.co/RbAO9P3KIK	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
834500587139903489	2980716533	From Trump the Nationalist, a Trail of Global Trademarks https://t.co/YIbAl1WfKm https://t.co/TjuKT6mQJc	37.0902400000000014	-95.7128909999999991	United States	44	\N
834500585575632898	38079965	RT @JordanUhl: The Anti-Defamation League received a bomb threat today.\n\nWe CANNOT accept Trump's tacit endorsement through SILENCE any lon…	28.4769457999999993	-80.7886656999999957	Port St John, FL 	674	\N
834500583772004352	1063922101	RT @FoxNews: .@johnrobertsFox: "The Trump Administration wants it known that it does not believe that [transgender issues] should be a fede…	54.7877148999999974	-6.49231449999999999	Northern Ireland	675	\N
834500583440601088	2399121283	RT @kylegriffin1: Trump's 1st month in office includes:\n\nGolf—25 hrs\nForeign relations—21 hrs\nTweeting—13 hrs\nIntel briefings—6 hrs\nhttps:/…	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834500583411167232	823334185775591426	#Trump 🇺🇸 Malia Swarmed By Paparazzi When They Look Down &amp; See What’s Missing https://t.co/bNXjf0LFcW 👈See Here 🇺🇸 https://t.co/sAR4IxQ7oA	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
834500582664572930	797243715320500226	Ready To Be Taxed For Being White? Here’s Racist Democrats’ DISGUSTING Plan To MAKE YOU PAY https://t.co/Ux2yXqZtPH https://t.co/pDrs2yoWeo	35.0077519000000024	-97.0928770000000014	Oklahoma, USA	676	\N
834500581989326848	53276941	RT @bannerite: No money for day care for military families but all kinds of money for Trump family trips! #thatsNotRight https://t.co/ug8xI…	35.0853335999999985	-106.605553400000005	Albuquerque	677	\N
834500581762936834	422340727	RT @JoyAnnReid: Trump's win is allowing Republicans to implement every extreme idea they've ever had, on healthcare, reproduction, taxes. m…	42.5161310000000014	-83.2625577000000021	Beverly Hills Mi	679	\N
834500581637095425	3107842713	Trump to rescind transgender bathroom rules from Obama era #trans https://t.co/9et6PKIGq3	53.1423672000000025	-7.69205360000000038	Ireland	42	\N
834500581360283648	224261544	RT @RollingStone: How America’s oldest Muslim community is coping with President Trump https://t.co/KiviF1Rjv5 https://t.co/cLR0ndHbi9	-14.235004	-51.9252800000000008	brasil	680	\N
834500581226082304	826116190410043393	Richmond City Council unanimously approves of a Trump impeachment resolution.\n\nhttps://t.co/tuPCQA86IA	37.0902400000000014	-95.7128909999999991	United States	44	\N
834500580454330368	3107909896	Trump to rescind transgender bathroom rules from Obama era  https://t.co/NkqmQsQMrT	53.1423672000000025	-7.69205360000000038	Ireland	42	\N
834500580408188931	165537786	RT @molleindustria: Make Trump Tweets Eight Again - plugin that displays POTUS tweets as a child's scribble\n\nhttps://t.co/OuHz5p7llB\n\nhttps…	40.7127837000000028	-74.0059413000000035	New York City, NY	681	\N
834500580135559173	2892983181	RT @VP: Businesses are already reacting to @POTUS Trump's "Buy American, Hire American" vision with optimism and investment in our country.	37.0902400000000014	-95.7128909999999991	 USA	682	\N
834500579871309828	160820530	For Democrats, concern is that Democratic leaders in Congress won't do enough to oppose Trump… https://t.co/w2YHoYu7pm	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834500579724558340	2379859314	RT @thehill: "Sanders, not Trump, is the real working-class hero" https://t.co/CqNmCIHCK9 https://t.co/P6CBefQpU7	38.9208177000000006	-76.9907766999999978	dc's only home depot	683	\N
834500579120517120	294897270	"Reflects the key role libraries play in the lives of new Americans...more than half visiting..at least once a week" https://t.co/F4ChdhIR7x	43.6532259999999965	-79.3831842999999964	Toronto	148	\N
834500578034188288	2273554058	@RandPaul this just feel good? Rand Paul Has Become Trump’s Most Loyal Toady https://t.co/7CrRS9J7h7	42.3600824999999972	-71.0588800999999961	Boston, MA	149	\N
834500577849532416	21771686	RT @EWErickson: So the Trump Admin says local school districts should decide bathroom policy instead of one size fits all nat'l policy.  Cu…	47.7510740999999967	-120.740138599999995	Washington State	333	\N
834500577673486343	754720071394660353	@pattymo The Trump we saw was the best they could do? Jesus, imagine what kind of an insane tantrum machine this toddler man actually is!	42.5195399999999992	-70.8967154999999991	Salem, MA	684	\N
834500575731523585	4749696918	Liberals LOSE IT Over What Trump Is About To Do!: https://t.co/7un1z3izTp via @YouTube	37.0902400000000014	-95.7128909999999991	United States	44	\N
834500575693660160	106625425	When will you and Trump be replaced with something that actually works? GOP has had years to come up with a plan. M… https://t.co/vFKHBT6Fo3	34.0928091999999978	-118.328661400000001	Hollywood	685	\N
834500575584587777	830491680453300224	Muslim Teacher Calls For Dead Infidels, Gets Nasty Surprise In Texas Class https://t.co/JdecwYIsHg https://t.co/EwlEJbdpON	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
834500575450451968	792790628	RT @kylegriffin1: Spicer: "Bit of professional protester" at town halls.\n\nReminder—DJT reportedly paid actors for presidential anncmt https…	34.2331373000000028	-102.410749300000006	EARTH	369	\N
834500575362502658	2940035856	Will Trump Create Jobs? Growth And Economy Will Improve Under The Presid.. Related Articles: https://t.co/5rwQhGg2W8	38.9071922999999984	-77.0368706999999944	Washington DC	686	\N
834500574972301312	823575801597751296	#Trump 🇺🇸 Muslim Teacher Calls For Dead Infidels, Gets Nasty Surprise In Texas Class https://t.co/FP5HVtPNM7 👈See H… https://t.co/18Vj3muWWp	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
834500573856673793	137129421	National @QuinnipiacPoll shows @realDonaldTrump popularity 'sinking like a rock' https://t.co/ykePX9ekMX	39.9525839000000005	-75.1652215000000012	Philadelphia, PA	233	\N
834500573269364738	823334185775591426	#Trump 🇺🇸 Muslim Teacher Calls For Dead Infidels, Gets Nasty Surprise In Texas Class https://t.co/ODyFmZiF1u 👈See H… https://t.co/skjr567lWy	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
834500573068132353	50322571	RT @kylegriffin1: Trump's 1st month in office includes:\n\nGolf—25 hrs\nForeign relations—21 hrs\nTweeting—13 hrs\nIntel briefings—6 hrs\nhttps:/…	41.6617833999999974	-70.7923674000000034	On the go	687	\N
834500571331653632	2399121283	RT @GavinNewsom: Our focus is on forcing families to live in fear. It should be on paths to citizenship and comprehensive reform. https://t…	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834500571172188162	1125455396	Vile Leftists Greet VP Pence in St. Louis: “Suck My Girl D*ck” (Video) https://t.co/PMeM6yOHpc 👈 🇺🇸 #Trump https://t.co/f6TApI2bpV	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
834500570958426117	275389379	Trump is 'eliminating arts funding programs'. It will save him 0.0625% of the federal budget https://t.co/6l0zkXmkeq	42.2917069000000012	-85.5872286000000031	kalamazoo	688	\N
834500570920558592	788522236860887041	Ivanka Trump listens to arguments at Supreme Court https://t.co/fNHaLQSmpD https://t.co/PTtmkyTmnF	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
834500570769547264	797243715320500226	BREAKING: Young FOX News Host DEAD, Here’s What We Know Right Now https://t.co/tObJbiHXL8 https://t.co/wyfHfeSD6S	35.0077519000000024	-97.0928770000000014	Oklahoma, USA	676	\N
834500570635460614	3107842713	Mexico fumes over Trump immigration rules as US talks loom #tr https://t.co/GDI61l44KE	53.1423672000000025	-7.69205360000000038	Ireland	42	\N
834500569913913344	146455788	RT @Cyndee00663219: please call your senators.... demand a investigation into trump's and GOP's Russian involvement (2022243121) #Trumpruss…	44.0811690000000027	-103.225855999999993	Roamin Around	689	\N
834500569842720771	24791596	RT @JamilahLemieux: "And then he asks his wife to face the people who have hurt him so much." @DavidDTSS on Michelle O. a gift\nhttps://t.co…	30.8477871999999991	-83.2895670000000052	Valdosta State University	690	\N
834500569830076416	394231278	RT @Don_Vito_08: BREAKING: Majority Want Fewer Refugees, Support @POTUS Trump’s Migration Cuts #AmericaFirst #MAGA https://t.co/sM2IHp3csQ…	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834500569565954048	241608523	President Trump's deportation plans strikes fear in #Asian American community. #AAPI https://t.co/yk4eYmBZDn	37.7749294999999989	-122.419415499999999	San Francisco	37	\N
834500568836096002	325932977	RT @mattyglesias: um … what kind of investments? https://t.co/c8dUVpZDca https://t.co/3ZqxeZ63Bb	40.0583237999999966	-74.4056611999999973	New Jersey, USA	68	\N
834500568706068480	149802946	RT @DanaSchwartzzz: How to predict Donald Trump's response every single time: https://t.co/qSvSuqzDjp	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834500567632326656	3529881557	RT @comermd: 🤡Liberals have a unique ability to suspend all basic knowledge just to bash Trump. Via @MarkDice\n#TuesdayMotivation\nhttps://t.…	30.1588129000000009	-85.6602058	Panama City Fl	691	\N
834500730195148802	621419621	RT @observer: Gillibrand Says Cuomo Would ‘Be a Great Candidate’ for Dems to Run Against Trump in 2020 https://t.co/3Z0Lp22OUQ	40.7127837000000028	-74.0059413000000035	NY & N.J #RESIST 	692	\N
834500730169982976	62338337	RT @mitchellvii: Trump's best play to rid America of illegals is to remove the attractive hazard. Make it impossible for employers to hire…	-23.5505199000000012	-46.6333094000000017	São Paulo	693	\N
834500730031575041	886026313	RT @BraddJaffy: Crowd asks Rep. Steve Womack (R-AR) to investigate Trump/Russia. \n\nWait for it... https://t.co/4siV7A0cOR	46.7295530000000028	-94.6858998000000014	Minnesota	388	\N
834500728852971520	806222129649721344	RT @AltStateDpt: RT- Trump voters should replace blind defense with critical thought.\n\nIf they do, they'll see Scott Pruitt as the embodime…	42.1536301000000009	-72.5466485999999975	Western Mass	694	\N
834500726986403840	826953137776766976	RT @TMZ: Donald Trump's Star Vandal Dodges Jail in Plea Bargain https://t.co/TCDVqVqua6	39.9525167999999979	-75.1630284000000017	$in City 	695	\N
834500726885851137	393076781	RT @JuddLegum: 1. Trump campaign staff would pitch positive stories to InfoWars, print them out and show them to Trump https://t.co/OgdTULI…	40.7127837000000028	-74.0059413000000035	New York City	145	\N
834500726864887808	144649235	RT @JessicaValenti: you guys we're fucked if we find aliens while Trump is president https://t.co/mF1jQOvBtB	29.9510657999999985	-90.0715323000000012	New Orleans	696	\N
834500726000869376	758961792856887297	RT @RealJack: Still the most telling meme of the Election...\n\nLiberals claim Trump will destroy America... as they go out and destroy Ameri…	56.1303660000000022	-106.346771000000004	Canada 	697	\N
834500725442957312	378485799	Plot twist: Ivanka Trump first woman president	36.7782610000000005	-119.417932399999998	California	61	\N
834500724998467584	34014681	@sahilkapur @AP can't wait to lose to trump again in 2020	42.3314269999999979	-83.0457538	Detroit, MI	698	\N
834500724675510272	264199679	RT @Pamela_Moore13: Whatever the liberals say, MAJORITY support Trump! Fact! https://t.co/j04dSQsT0K	44.4669941000000009	-73.1709603999999985	South	699	\N
834500724490895360	494387394	RT @Nouriel: Deportation force: Trump's new immigration rules are based on lies https://t.co/wYThamK7pi	40.7830603000000025	-73.9712487999999979	Manhattan, NY	133	\N
834500724318928896	1897322246	RT @FoxNews: Trump to revoke Obama-era transgender bathroom guidance for schools, source says  https://t.co/HZcRf8VsZx https://t.co/VNU0hzT…	47.3774633000000023	9.54691329999999994	Altstaetten	700	\N
834500723043885063	3340073541	RT @BigRadMachine: I think Trump's new National Security Advisor crushed it in that Super Bowl commercial #McMaster https://t.co/q8X7bmrG9g	39.1031181999999973	-84.5120196000000021	Cincinnati, OH	701	\N
834500722645413890	703068920484331520	@JackPosobiec Oh boy.... guess there must be a bunch of Trump supporters in Sweden harassing Jews?	40.4172871000000029	-82.9071229999999986	Northeast Ohio	702	\N
834500722397937664	43246407	RT @thehill: "Sanders, not Trump, is the real working-class hero" https://t.co/CqNmCIHCK9 https://t.co/P6CBefQpU7	42.3600824999999972	-71.0588800999999961	Boston & Cooperstown,NY	703	\N
834500721605214209	63013144	Trump, Who Has Declared Bankruptcy 6 Times, Promises To Clean Up The Nation's Finances via @politicususa https://t.co/WO0cwBXUQY	41.2033216000000024	-77.1945247000000023	Pennsylvania, USA	107	\N
834500721043087360	760134904680030208	@mattyglesias too light on Ivanka Trump holdings?	34.1477848999999978	-118.144515499999997	Pasadena, CA	704	\N
834500719386451971	2746355332	RT @JoeNBC: "Her absence from the airwaves has already lowered the level of controversy for the Trump White House." https://t.co/Wpo8cdM53P	41.2033216000000024	-77.1945247000000023	Pennsylvania, USA	107	\N
834500718799249412	624134597	Pastor walks out on Trump’s ‘demonic’ Florida rally: ‘My 11-year-old daughter was sobbing in fear’ https://t.co/CFFQvDxkAt	41.0814446999999987	-81.5190053000000034	akron	705	\N
834500718346186752	2302272152	RT @jeffreylondon: @funder @Khanoisseur How Khrapunov laundered stolen mineral assets from KAZ thru ARIF and TRUMP, https://t.co/XClFoJuJ8r…	37.3979296999999988	14.6587820999999998	Sicily, Italy	706	\N
834500717872300032	376504227	RT @Pamela_Moore13: Mexican-American explains why he supports Trump Securing the Border 🇺🇸 https://t.co/awbsSYObK4	37.0902400000000014	-95.7128909999999991	United States	44	\N
834500717352202240	2197392172	RT @DaShanneStokes: For those who don't know, a credible media survey wouldn't ask leading questions, unlike Trump's. #resist #TheResistanc…	35.9606384000000006	-83.9207391999999999	Knoxville, TN	707	\N
834500716936978434	2682435204	RT @MRodOfficial: White House Stalls Obama Administration Rule on Retirement Advisers https://t.co/0SdjJEZtKa Welcome to America inc feel s…	39.0742079999999987	21.824311999999999	Greece	708	\N
834500716811210753	736250687839866885	Stay focused on the Trump/Russian ties, crimes and corruption. Pressure Congress for independent investigation. Stay focused.	35.7595730999999972	-79.0192997000000048	North Carolina, USA	384	\N
834500716538519553	789546382956781568	Trump's First Solo Press Conference as President: A Closer Look https://t.co/GRoxDJeIyu	37.0902400000000014	-95.7128909999999991	United States	44	\N
834500716521623553	70412072	Trump wants to save the blcks and jews so he's building conservatories and zoos to house them.	40.0992293999999987	-83.1140771000000029	Dublin, OH, USA	709	\N
834500716249112579	14186393	RT @QuinnipiacPoll: Trump Slumps As American Voters Disapprove 55% – 38% Poll Finds; Voters Trust Media, Courts More Than President  https:…	25.790654	-80.1300454999999943	Miami Beach, Florida	710	\N
834500716001587200	713204456419004416	RT @JBurtonXP: Muslims in Sweden just had to NOT RIOT for like one week in order to make Trump look like he was wrong, but they couldn't ev…	37.0902400000000014	-95.7128909999999991	USA	56	\N
834500715695452162	342050953	RT @JuddLegum: 1. Trump campaign staff would pitch positive stories to InfoWars, print them out and show them to Trump https://t.co/OgdTULI…	65.471371199999993	-17.0280279000000014	Northeast	711	\N
834500715229872128	459612537	RT @FoxBusiness: Trump seeks jobs advice from some firms that offshore U.S. work  https://t.co/IAigewOi6A	40.7127837000000028	-74.0059413000000035	New York City	145	\N
834500715204722690	1563908942	RT @donaldbroom: Trump's UN Ambassador Nikki Haley Shows The United Nations Why America Is Not To be F*cked With https://t.co/yALm7yjT47 vi…	37.4315733999999978	-78.6568941999999964	Virginia	276	\N
834500715120848897	3477455725	RT @newsmax: Paxton: Trump's Immigration Plans, Wall 'Huge Benefit' for Texas https://t.co/Hy0EIZI1Ce	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834500714747613184	731477602800668673	RT @IndyUSA: Town hall fury: If the Republicans think this is bad wait until Trump voters turn on them too https://t.co/dHDfLNnce9 https://…	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834500714525253634	30376473	RT @TomthunkitsMind: BOMBSHELL: Trump Campaign Aides Had Repeated Contacts With Russian Intelligence For 1 Year Before Election. https://t.…	41.7199779999999976	-87.7479527999999931	Oak Lawn, IL	712	\N
834500714185490432	26798863	@RichardRubinDC they've been too tied up with Trump's audit.	39.9611755000000031	-82.9987942000000061	Columbus, OH	57	\N
834500713845751810	21261932	RT @kylegriffin1: Trump's 1st month in office includes:\n\nGolf—25 hrs\nForeign relations—21 hrs\nTweeting—13 hrs\nIntel briefings—6 hrs\nhttps:/…	43.6532259999999965	-79.3831842999999964	Toronto, Canada	713	\N
834500712159657986	806524210470383616	RT @mattyglesias: um … what kind of investments? https://t.co/c8dUVpZDca https://t.co/3ZqxeZ63Bb	43.7844397000000001	-88.7878678000000008	Wisconsin, USA	91	\N
834500711962509313	763744416163041280	The evidence ahead of a key right-wing conference suggests that it’s the right that’s moving, writes ed_kilgore https://t.co/u8cDv3g31i	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834500711685648384	146455788	RT @pithypacky: "They're quite obviously playing Trump. They consider him a stupid, unstrategic politician."\n\n#TrumpRussia #Putin \n\n https:…	44.0811690000000027	-103.225855999999993	Roamin Around	689	\N
834500709827633152	199317006	"We’re doing a lot of interviews tomorrow — generals, dictators, we have everything,” Trump told the crowd,... https://t.co/tKlMRLix8g	35.8456212999999977	-86.390270000000001	Murfreesboro, TN	714	\N
834500708967837697	61236989	RT @RichardTBurnett: Chuck the Schmuck Schumer is the one that Trumpsters will destroy in the next 4 years! He will be sent to a padded cel…	37.0902400000000014	-95.7128909999999991	America	203	\N
834500708325957632	1538008483	CIA analyst quits, blames President Trump @CNNPolitics https://t.co/0NrdXF2qBf	34.0479403000000005	-118.222820200000001	Los Angeles * Las Vegas 	715	\N
834500707692654592	880929493	RT @JuddLegum: 1. Guys, there is a A LOT more to the story of Trump's new trademark https://t.co/NjauHV3tf7	49.166589799999997	-123.133568999999994	Richmond B.C.	716	\N
834500707461914624	21230204	RT @JuddLegum: To review, since Trump became prez we:\n\n1. Spent $10M on his golf trips to Mar-a-lago\n\n2. Cut military child care\n\nhttps://t…	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
834500707453693953	1639717104	@_jaslynnnn teanna_trump	29.6185669000000011	-95.5377215000000035	Missouri City, TX	717	\N
834500707403210752	739691269656477696	RT @ThePatriot143: BREAKING : NRA Targets Anti-Trump Forces With Powerful New Video – TruthFeed https://t.co/PYtKLQqDJ2 Democracy Dies in D…	39.5500506999999999	-105.782067400000003	Colorado, USA	212	\N
834500707143262209	787951696840368129	@MarcusKieffer1 @FoxNews  Well then, you can pee on yourself, Trump wont care and Im sure the state will let you :)	43.7844397000000001	-88.7878678000000008	Wisconsin, USA	91	\N
834500706568642565	24707450	Places like Haiti could suffer from "America 1st"-What Trump Means for the World’s Poorest People https://t.co/jw1bROxXc0 via @newyorker	40.7127837000000028	-74.0059413000000035	New York	214	\N
834500706463682560	613934233	RT @TheViewFromLL2: Through a mysterious "mutual friend," Sater is hooked up with a guy that can give him this kompromat, with instructions…	47.4954046000000005	-101.3767438	Wyoming via North Dakota	718	\N
834500705574649859	772921250586828801	RT @foxandfriends: .@michellemalkin calls out journalists who say Trump may incite violence: Where are they when liberals call for violence…	35.0077519000000024	-97.0928770000000014	Oklahoma, USA	676	\N
834500705465618433	1482396266	RT @washingtonpost: At a town hall in Trump country, an America that’s pleading to be heard https://t.co/qnNqiGhrcU	38.2109329999999972	-85.751583999999994	Safe Place	719	\N
834500705230675973	16049743	RT @TimOBrien: Trump deportation plan could cost the economy $5 trillion over 10 years. Yes, $5 trillion.  https://t.co/5QxJus1f1x	41.8781135999999989	-87.6297981999999962	Chicago, IL 	720	\N
834500705155215361	16310953	I wouldn't pass these background checks, either. Also, no one is appointing me to white house jobs. https://t.co/XuH0VPdWwt	41.1432450000000003	-81.8552195999999981	Medina, OH	721	\N
834500704626675717	55285564	"Palestinians are stateless, Israelis are war weary, Saudi hates Iran, Trump is president, an opportunity for peace!" #Platitudes #Fraud	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834500703867568128	4699219632	RT @OhNoSheTwitnt: What's the over under on Trump's morning Twitter tirade being about Anne Frank? "She was no hero. I like heroes who didn…	33.9137084999999985	-98.4933872999999949	Wichita Falls, TX	722	\N
834500702965637120	884695994	RT @Bvweir: #Russia \nVladimir Putin’s big mistake, and why his Donald Trump – Russia conspiracy is unraveling https://t.co/XdWPFBocI2 via @…	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834500889347919872	774058706132725760	@TParkPrincess @maddow   Trump said "what happened in Sweden yesterday".  A singing competition.  No violence on hi… https://t.co/AQ6KOAOWmu	37.0902400000000014	-95.7128909999999991	United States	44	\N
834500889071251456	30962796	RT @BrendanNyhan: Hard to believe this is real: the POTUS (who won't read long briefing books) can't be left alone with a TV. https://t.co/…	33.7748275000000007	-84.2963122999999968	Decatur, GA	723	\N
834500888941064192	764555973587406848	RT @VP: Businesses are already reacting to @POTUS Trump's "Buy American, Hire American" vision with optimism and investment in our country.	32.7157380000000018	-117.1610838	San Diego, CA	150	\N
834500887347277824	130326816	RT @benjaminja: 5 year old or Trump? \n\n"Leaving him alone for several hours can prove damaging, bc he consumes too much television” https:/…	37.8043637000000032	-122.271113700000001	Oakland, California	724	\N
834500887259336704	961217294	RT @washingtonpost: "Poll: Donald Trump is losing his war with the media" https://t.co/4IslDQV36Y	40.7351018000000025	-73.6879081999999954	new hyde park ny	725	\N
834500886986649606	20002807	RT @TerriGreenUSA: There's a great scene in Chariots of Fire, when Eric Liddell's father talks about compromise and the authority of God. W…	31.9685987999999988	-99.9018130999999983	texas	425	\N
834500886755934208	144907880	In the reverse.  https://t.co/BfbMrzQIG9	30.2671530000000004	-97.743060799999995	Austin, TX	106	\N
834500886214832128	2349507882	It's a TRUMP EGG! https://t.co/KI4hffEwrn	29.7408977999999991	-95.5827333999999951	WEST SIDE	726	\N
834500886202249216	797243715320500226	IT’S NO TINFOIL HAT CONSPIRACY THEORY! SCIENTISTS DISCOVER HOW TO ERASE MEMORIES #o4a #news https://t.co/SEJFAgU24o https://t.co/ZVAcy4G0FX	35.0077519000000024	-97.0928770000000014	Oklahoma, USA	676	\N
834500885699055616	594990097	Swedish Journalists: TRUMP was Right About Sweden (VIDEO) https://t.co/6lqdjhWzht	37.4315733999999978	-78.6568941999999964	Virginia, USA	263	\N
834500885455593472	405853228	RT @TMZ: Donald Trump's Star Vandal Dodges Jail in Plea Bargain https://t.co/TCDVqVqua6	34.2746459999999971	-119.229031599999999	Ventura, California 	727	\N
834500884277125123	906942590	Kellyanne Conway reportedly benched from TV by Team Trump https://t.co/dhIODKzjBj	36.1699411999999967	-115.139829599999999	Las Vegas, Nevada	728	\N
834500883920601088	723561666919710720	RT @washingtonpost: "Poll: Donald Trump is losing his war with the media" https://t.co/4IslDQV36Y	46.7295530000000028	-94.6858998000000014	Minnesota, USA	262	\N
834500883799011328	730433203207548932	RT @DineshDSouza: An idiot savant expresses his frustration that Trump won't listen to either the liberal garbage or the neocon garbage htt…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834500882888814592	474950375	RT @ForeignAffairs: Trump's ardent support for the Dakota Access pipeline reinforces concerns about possible conflicts of interest. https:/…	52.0704977999999983	4.30069989999999969	Den Haag	729	\N
834500882670686208	2204095723	RT @ananavarro: President. Donald. Trump. https://t.co/pnPAydkkVS	41.0489674000000022	-73.5032676000000009	Terry in CT	730	\N
834500882595139584	80793585	RT @ChangFrick: For my english readers: Donald Trump is correct – I live in an immigrant area in Sweden and it is not working well https://…	34.9592083000000002	-116.419388999999995	SoCal	250	\N
834500882528038913	17756037	Trump Aide Throws Up ‘White Power’ In Official Photo – Unbelievable Image Here https://t.co/gKvXw8uuqe via @Bipartisan Report	37.0902400000000014	-95.7128909999999991	America	203	\N
834500882494545922	75193022	Kellyanne Conway reportedly benched from TV by Team Trump https://t.co/kTax8zWCN7	21.1250077000000012	-101.685960499999993	León, Guanajuato; México	731	\N
834500882100219904	258110028	RT @Mikel_Jollett: Let's be very clear: Milo was an editor at Breitbart hired by Trump's closest advisor Steve Bannon.\n\nThis hatred is in t…	43.8041333999999978	-120.554201199999994	Oregon, USA	655	\N
834500881093505024	24226326	RT @ThePatriot143: BREAKING : NRA Targets Anti-Trump Forces With Powerful New Video – TruthFeed https://t.co/PYtKLQqDJ2 Democracy Dies in D…	31.9685987999999988	-99.9018130999999983	Texas	381	\N
834500881030733825	422740850	This is REAL feminism. This is a REAL woman you twats. #resist #RT #RealNews #Persist  Every country needs a Trump… https://t.co/UBmB4onR45	40.1692940000000007	-74.0228029999999961	North of the Wall	732	\N
834500880896397312	35993642	@POTUS @Rosie  Trump makes the world a darker place. I vote health, love,caring,&amp;NO MORE TRUMP carnage! https://t.co/jITwwGOXsA via @nbcnews	47.6062094999999985	-122.332070799999997	Seattle	111	\N
834500880279945217	20665221	RT @pattymo: This is an article about a 70 year-old man who is also the President of the United States https://t.co/EwZSNbvyRd https://t.co…	-33.9248685000000023	18.4240552999999991	Cape Town, South Africa	733	\N
834500879495487488	3933992962	Trump has a problem: Americans increasingly think he's incompetent https://t.co/0hdNcmjwAc https://t.co/BCgd7MOv05	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834500879235440640	43590098	@Native__Wit @Chica63 @BritFunTravel @TheEllenShow It's possible they did not give her foddor for her fire. They had class, Trump doesn't.	38.4318550999999999	-120.571871900000005	Pioneer, CA	734	\N
834500879168344064	16018805	RT @usatodayDC: Political apps are all the rage in the Trump era https://t.co/eeH9KMAxr5 via @jswartz	37.7749294999999989	-122.419415499999999	San Francisco	37	\N
834500879046676480	797996709850779648	WATCH NANCY PELOSI PRAISE FAILED NATION OF MEXICO AS ‘HEIGHTENED CIVILIZATION’ *VIDEO* #o4a #Trump… https://t.co/MNQ3swsUwK	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
834500878795104257	797983375038513152	WATCH NANCY PELOSI PRAISE FAILED NATION OF MEXICO AS ‘HEIGHTENED CIVILIZATION’ *VIDEO* #o4a #Trump… https://t.co/9BhcYLT9t3	40.7127837000000028	-74.0059413000000035	Nueva York, USA	81	\N
834500878413418496	744358368316297216	RT @thehill: Poll: Trump approval hits new low https://t.co/AYXgrwooc2 https://t.co/7zRM5PXD2C	42.3265152000000029	-122.875594899999996	Medford, OR	735	\N
834500878186995715	16714347	More than 3,000 scientists have already expressed interest in running for office to oppose Trump: https://t.co/zaC2zInwgm	40.6781784000000002	-73.9441578999999933	brooklyn	736	\N
834500877654310912	759218015019859973	RT @RBReich: You're having an impact!  The people are rising.\nhttps://t.co/ApbtI9EGwv	39.0457548999999986	-76.6412712000000056	Maryland, USA	234	\N
834500877306126336	797260424731361280	WATCH NANCY PELOSI PRAISE FAILED NATION OF MEXICO AS ‘HEIGHTENED CIVILIZATION’ *VIDEO* #o4a #Trump… https://t.co/d0ctyDPj0F	25.8195423999999996	-80.3553301999999974	Doral, FL	737	\N
834500876517638145	24452840	Trump to Bernanke: "so how do we confiscate the gold, 1933 style?"	46.7295530000000028	-94.6858998000000014	MN	368	\N
834500876261679104	797252185109254144	WATCH NANCY PELOSI PRAISE FAILED NATION OF MEXICO AS ‘HEIGHTENED CIVILIZATION’ *VIDEO* #o4a #Trump… https://t.co/dBLaL7VYA6	40.0656291000000024	-79.8917138999999992	California, PA	738	\N
834500876211519488	3115991508	RT @washingtonpost: "Poll: Donald Trump is losing his war with the media" https://t.co/4IslDQV36Y	37.0902400000000014	-95.7128909999999991	United States	44	\N
834500875993247744	18971381	RT @TimKarr: Trump's chief digital officer escorted out of the White House after failing FBI background check https://t.co/U4GIgayjay #Shit…	34.0479403000000005	-118.222820200000001	Los Angeles/Las Vegas	739	\N
834500875406176256	106274105	RT @ObsoleteDogma: Trump might speed up what seemed like a 15 or 20 year trend: the Sun Belt's move from Republican to Democrat https://t.c…	27.763383000000001	-82.5436722000000032	Tampa Bay, FL 	740	\N
834500875343106049	4227468554	RT @MaxineWaters: It's just the tip of the iceberg. It doesn't end w/ Flynn. Only thorough investigations will unveil the truth about Trump…	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
834500874995060736	768681209945817088	WATCH NANCY PELOSI PRAISE FAILED NATION OF MEXICO AS ‘HEIGHTENED CIVILIZATION’ *VIDEO* #o4a #Trump… https://t.co/yHTMYw441M	32.3182314000000019	-86.9022980000000018	Alabama, USA	741	\N
834500874785345536	797990317911867396	WATCH NANCY PELOSI PRAISE FAILED NATION OF MEXICO AS ‘HEIGHTENED CIVILIZATION’ *VIDEO* #o4a #Trump… https://t.co/BpdVDqZzVm	29.9510657999999985	-90.0715323000000012	New Orleans, LA	742	\N
834500874768572416	766499969696169984	WATCH NANCY PELOSI PRAISE FAILED NATION OF MEXICO AS ‘HEIGHTENED CIVILIZATION’ *VIDEO* #o4a #Trump… https://t.co/KZxXAOQx2R	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834500874613436418	422083723	RT @pattymo: This is an article about a 70 year-old man who is also the President of the United States https://t.co/EwZSNbvyRd https://t.co…	40.0583237999999966	-74.4056611999999973	New Jersey, USA	68	\N
834500874563055617	557240142	#10: I believe that the Trump admin doesn't do their due diligence fact-checking before giving briefings and interviews. #mediasurvey	64.2008412999999933	-149.493673300000012	Alaska, USA	743	\N
834500874298880005	171198826	RT @USARedOrchestra: NASA has told Trump that 2 of the planets discovered aren't suitable for hotels or golf courses, so they've been added…	43.7844397000000001	-88.7878678000000008	Wisconsin, USA	91	\N
834500874063974400	310509245	RT @fawfulfan: Reminder: Trump wants to eliminate the budget for #AmeriCorps and #PBS while he blows billions jetting himself to Mar-a-Lago…	32.776664199999999	-96.7969879000000049	Dallas, TX	267	\N
834500874059784194	3340073541	RT @BigRadMachine: How long after WW3 starts do you think Trump supporters will blame Obama and Hillary?	39.1031181999999973	-84.5120196000000021	Cincinnati, OH	701	\N
834500874013700096	51366890	RT @activist360: Rachel Maddow: After her Kremlin paid lunch w/ Putin &amp; Flynn, why is Jill Stein silent abt the Trump-Russia scandal? https…	47.6062094999999985	-122.332070799999997	Near Seattle, WA, USA	744	\N
834500873900453889	17920055	THR: Mexico vows to resist Donald Trump's immigration plans https://t.co/cmOBPp8Rhd (WT)	34.0928091999999978	-118.328661400000001	Hollywood, CA USA	745	\N
834500873720037376	52836557	RT @pattymo: This is an article about a 70 year-old man who is also the President of the United States https://t.co/EwZSNbvyRd https://t.co…	44.9777529999999999	-93.2650107999999989	Minneapolis	746	\N
834500873141248006	793946417769357312	It costs taxpayers $500,000 a day to protect Trump Tower. That's $182,500,000 per year.	32.1656221000000002	-82.9000750999999951	Georgia	747	\N
834500872746831872	87971880	RT @vesaldi: OK so the Trump admin is coming for trans kids now. When are the protests scheduled? I'm ready to fight.	33.4355977000000024	-112.349602099999998	avondale, az	748	\N
834500872461619200	2437339435	RT @resnikoff: Trump Staffer Grateful To Work With So Many People He Could Turn Over To FBI In Exchange For Immunity https://t.co/hKhwfLalh…	47.8458036000000035	-122.297512400000002	Anywhere but here	749	\N
834500872344211456	767567215638052864	WATCH NANCY PELOSI PRAISE FAILED NATION OF MEXICO AS ‘HEIGHTENED CIVILIZATION’ *VIDEO* #o4a #Trump… https://t.co/8u9gbgb4Vm	40.7127837000000028	-74.0059413000000035	Nueva York, USA	81	\N
834500871790530560	162249930	WATCH NANCY PELOSI PRAISE FAILED NATION OF MEXICO AS ‘HEIGHTENED CIVILIZATION’ *VIDEO* #o4a #Trump… https://t.co/fLME5x4ugy	25.7616797999999996	-80.1917901999999998	Miami, FL	141	\N
834500871656337408	24597757	RT @RBReich: You're having an impact!  The people are rising.\nhttps://t.co/ApbtI9EGwv	56.1303660000000022	-106.346771000000004	Canada	257	\N
834500871195066372	827270492360826880	The news coverage of the Trump administration and his family is out of proportion. There are other important issues. https://t.co/5BQttrKtv0	40.2671940999999975	-86.1349019000000027	Indiana, USA	100	\N
834500871043981312	797243715320500226	WATCH NANCY PELOSI PRAISE FAILED NATION OF MEXICO AS ‘HEIGHTENED CIVILIZATION’ *VIDEO* #o4a #Trump… https://t.co/EnYL1S6QmT	35.0077519000000024	-97.0928770000000014	Oklahoma, USA	676	\N
834500870939095040	797979946400575488	WATCH NANCY PELOSI PRAISE FAILED NATION OF MEXICO AS ‘HEIGHTENED CIVILIZATION’ *VIDEO* #o4a #Trump… https://t.co/HpwxItRY7N	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834500870913921024	548943317	Vanity Fair, Resist Trump: Turn Your Oscar's Party into a Fundraiser! https://t.co/ypD52IWD2y	34.2746459999999971	-119.229031599999999	Ventura, CA	678	\N
834500870167420928	767961725102657536	WATCH NANCY PELOSI PRAISE FAILED NATION OF MEXICO AS ‘HEIGHTENED CIVILIZATION’ *VIDEO* #o4a #Trump… https://t.co/qK7R1uRAxz	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834500870037524480	306199816	Silicon Valley Leaders Slam Trump Refugee Order https://t.co/5deUqWXRD1 #Gadgets ?	30.6953657	-88.0398911999999996	Mobile, AL	750	\N
834500869538381824	417765463	Trump Was Absolutely Right About Sweden: Where's the Fake News Alt-Left ...\n\nhttps://t.co/0RDOnNyYdM https://t.co/n3Z9CSdINy	36.1699411999999967	-115.139829599999999	Las Vegas, NV	218	\N
834500869446004737	741459435311104001	Everyone for got about Executive order 9066 issued by Franklin Roosevelt (D) during word war II! Allow #TRUMP to do his job!	38.8026096999999979	-116.419388999999995	Nevada, USA	510	\N
834500869160726530	634898785	RT @ananavarro: President. Donald. Trump. https://t.co/pnPAydkkVS	33.8703596000000005	-117.924296600000005	fullerton	751	\N
834500868993142786	260598382	RT @HRC: Now is the time for every single person to stand up for transgender kids under attack by the Trump Administration. #ProtectTransKi…	44.3148442999999972	-85.602364300000005	West Michigan	752	\N
834500868569444352	27787448	RT @CraigKarmin: Trump travel ban will spark a big drop in foriegn travel to the U.S., a big blow to many local economies  https://t.co/srw…	36.1626637999999971	-86.7816016000000019	Nashville, TN	618	\N
834500868527382528	200213106	Trump has a problem: Americans increasingly think he's incompetent https://t.co/M8KUM6Y2tD https://t.co/vMSlPyEWXP	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
834500868078702594	73653483	RT @DineshDSouza: The left called him a senile Bozo when he ran against Obama--now that he's criticizing Trump, they portray him as an inco…	27.6648274000000001	-81.5157535000000024	Florida	183	\N
834500867839631361	192935540	RT @JordanUhl: so, trump's former campaign staffers confirmed what we long suspected: when trump gets cranky, he throws hissy fits on twitt…	40.7432759000000004	-73.9196323999999976	Sunnyside, NY	753	\N
834500867508359168	130097118	Donald Trump: https://t.co/e2tGiorvk3 via @YouTube	52.1326329999999984	5.29126600000000025	Netherland	754	\N
834500867147460608	65466158	RT @kylegriffin1: Stephen Miller on Trump's new immigration EO: "Mostly minor, technical differences. Fundamentally...going to have the sam…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834501024073338880	21540135	RT @dabeard: As taxpayers paid $10m for 3 #Trump weekends in Florida, a Trump hiring freeze ended pre-K, daycare for US military families i…	40.4406248000000019	-79.9958864000000034	Pittsburgh, PA	99	\N
834501023452504064	784930455787364352	RT @JuddLegum: To review, since Trump became prez we:\n\n1. Spent $10M on his golf trips to Mar-a-lago\n\n2. Cut military child care\n\nhttps://t…	33.7489953999999983	-84.3879823999999985	Atlanta, GA	289	\N
834501023272050688	25823163	RT @kylegriffin1: Majority of voters approve of blocking Trump's travel ban, more disapprove of the EO's main provisions —@QuinnipiacPoll h…	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834501022710009856	706105772048908288	RT @Pamela_Moore13: Mexican-American explains why he supports Trump Securing the Border 🇺🇸 https://t.co/awbsSYObK4	43.8169837000000015	-79.532156999999998	worldwide	755	\N
834501022575890432	353471233	@chrislhayes this is the benefit of having someone with no convictions or understanding lead a dept. Trump wins.	28.0222434999999983	-81.7328566999999993	Winter Haven, Florida	756	\N
834501022315847680	31537047	Ivanka Trump and daughter pay the Supreme Court a visit https://t.co/w1PDDX7WSW via @HuffPostPol	42.7325349999999986	-84.5555346999999955	Lansing, MI	757	\N
834501021909008388	830000732682153984	@ElizLanders @PressSec @VP guess trump just couldn't get the words out. Thanks for clearing that up @vp	39.739235800000003	-104.990251000000001	Denver, co	758	\N
834501021745319936	74614792	RT @vulture: George Clooney wants you to remember that Donald Trump and Steve Bannon are hypocritical "Hollywood elitists" https://t.co/Tzb…	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834501021422469120	2859269159	RT @AlfGarnettTil: For those of you clowns under the misapprehension that Donnie Trump's an evil bastard.\nTHIS is what a genuinely evil git…	40.7127837000000028	-74.0059413000000035	NYC	60	\N
834501020982075392	3064883199	RT @JimCrackton: I hope WaPo leads the way in stopping propaganda and anti-Trump advocacy. It's time to return journalism. #DemocracyDiesIn…	34.2331373000000028	-102.410749300000006	Earth	481	\N
834501018813681669	60684098	Vladimir Putin’s big mistake, and why his Donald Trump – Russia conspiracy is unraveling https://t.co/ahey7FrepG via @PalmerReport	37.0902400000000014	-95.7128909999999991	USA	56	\N
834501018612285444	38582056	RT @pattymo: This is an article about a 70 year-old man who is also the President of the United States https://t.co/EwZSNbvyRd https://t.co…	42.3709299000000001	-71.1828320999999988	Watertown, MA	759	\N
834501016292880384	2587113794	I added a video to a @YouTube playlist https://t.co/jENiSbIsTP Abby Martin Rips Apart Trump’s Anti-Muslim Travel Ban	56.1303660000000022	-106.346771000000004	Canada	257	\N
834501016254967809	19113885	RT @DavidCornDC: The real story: Trump can be easily manipulated by staffers. Very sad! And frightening! https://t.co/m93BvyOwKa	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
834501016192163840	25448411	RT @rolandsmartin: PREACH! @Trevornoah Says @RealDonaldTrump Doesn’t Have the ‘Balls’ to Go on an Unfriendly Show... https://t.co/1nz0JDb71p	41.885031699999999	-87.7845025000000021	OAK PARK, IL	760	\N
834501015399325697	73309758	RT @pattymo: This is an article about a 70 year-old man who is also the President of the United States https://t.co/EwZSNbvyRd https://t.co…	49.2827290999999974	-123.120737500000004	Vancouver, BC	310	\N
834501015147835392	16827326	Every president has a catch phrase that defines his term in office. For Trump, I nominate “Vagina is expensive."	46.7295530000000028	-94.6858998000000014	Minnesota	388	\N
834501014808051712	1360674169	RT @ringoffireradio: Trump Literally Hasn’t Gone A Day As President Without Lying To The American Public: https://t.co/hmKWzCDUQY via @YouT…	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834501014417920000	821788470943227904	The foiled bomb plot in Kansas that didn't make Trump's terror list - OMG white terrorists! No way!  https://t.co/pnShFikBqs	37.0902400000000014	-95.7128909999999991	United States	44	\N
834501014166331398	1613447581	How the #media should rewrite live coverage rules to fight #Trump's administration’s #lies. #fakenews… https://t.co/y4JgXSH1L5	40.7127837000000028	-74.0059413000000035	New York City	145	\N
834501014162198528	478602651	RT @AltStateDpt: Trump Russia story is increasingly sordid &amp; building. It will be interesting to see who breaks first.\n\n#KeepResisting http…	41.8299578999999966	-72.609245400000006	nomadic	761	\N
834501014149591040	755575819	#JoeLiccar cartoon about #newsgathering in the #Trump Era. Download available at https://t.co/JMfNhUKOjv… https://t.co/Lx0ydqBXeT	30.2671530000000004	-97.743060799999995	Austin, Texas	78	\N
834501013608493056	829740186842103809	RT @PoliticusSarah: Trump, Who Has Declared Bankruptcy 6 Times, Promises To Clean Up The Nation's Finances via @politicususa https://t.co/W…	28.3861159000000001	-80.7419983999999999	Cocoa Florida 	762	\N
834501012916428802	868856461	RT @washingtonpost: Can Trump help Democrats take back the House? Here’s a big thing to watch. https://t.co/LHmFGHa6mI	31.9685987999999988	-99.9018130999999983	Texas	381	\N
834501012912234497	778688518818177024	RT @loopynature: DONALD TRUMP IS NOT MY PRESIDENT!\n\nDONALD TRUMP IS NOT MY PRESIDENT!\n\nDONALD TRUMP IS NOT MY PRESIDENT!\n\nDONALD TRUMP IS N…	29.7604267	-95.3698028000000022	Houston, TX	167	\N
834501012639604737	775374224034783232	RT @Great_Wall2018: FAKE NEWS: Ignorant reporter thinks Trump said “White people made America great” https://t.co/LS62pm9Pzc https://t.co/f…	44.3148442999999972	-85.602364300000005	Michigan, USA	83	\N
834501012543119361	93945977	RT @kylegriffin1: Miller's language here is destined to be used in lawsuits against Trump's new immigration ban. https://t.co/pdkPu5PZ1t	40.7127837000000028	-74.0059413000000035	ny	763	\N
834501012178153472	805455868997287937	RT @aravosis: Flashback: Dec 7, 2015. But it’s not about religion. https://t.co/yKmI1SElcf https://t.co/n27kFDpMMt	34.0611808000000025	-118.290878300000003	CA, previously VT & OR	764	\N
834540631984857088	2612942360	Media more trustworthy than Trump, poll finds https://t.co/B42ifXDWq1	34.1395596999999995	-118.3870991	Studio City, CA	813	\N
834501012010496000	593741888	RT @TimKarr: Trump's chief digital officer escorted out of the White House after failing FBI background check https://t.co/U4GIgayjay #Shit…	51.5073508999999987	-0.127758299999999991	London, UK	87	\N
834501010848641026	179734226	@TMKSESPN Next time U guys do some type of Bet Peter if he loses should have to wear a Trump T-shirt &amp; MAGA hat all day including @ HOT	40.7127837000000028	-74.0059413000000035	New York	214	\N
834501010756337665	825347924750061570	RT @TheDemocrats: Trump's "deportation force" is:\n✔️ Extreme\n✔️ Frightening\n✔️ Expensive\n✔️ Detrimental to deeply held American values\nhttp…	37.0902400000000014	-95.7128909999999991	USA 	210	\N
834501010676658176	1235918263	Left-Wing Front Groups Make Anti-Trump Money Untraceable https://t.co/3lNCh2j9PJ	37.0902400000000014	-95.7128909999999991	USA	56	\N
834501009972019200	3239230500	RT @kylegriffin1: Trump's 1st month in office includes:\n\nGolf—25 hrs\nForeign relations—21 hrs\nTweeting—13 hrs\nIntel briefings—6 hrs\nhttps:/…	34.2576066000000026	-88.7033859000000007	Tupelo, MS	765	\N
834501009636483075	50641019	RT @pattymo: This is an article about a 70 year-old man who is also the President of the United States https://t.co/EwZSNbvyRd https://t.co…	40.4172871000000029	-82.9071229999999986	Ohio	766	\N
834501009619742723	784547606194257921	@MaxineWaters Fucking scumbag Waters doesn't have the balls 2 say those things face 2 face w/Trump team. U know what would happen!	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834501008952733697	757337340268257280	RT @onlxn: Sources: Ivanka &amp; Jared Behind Some Good Thing Trump Administration Did, You Fill That Part In, You're The Dumb Reporter, I'm Iv…	34.0483473999999973	-117.261152699999997	Loma Linda,  Ca	767	\N
834501008747163648	2946745916	RT @RBReich: You might want to send this to anyone you know who voted for Trump. \n(Thx to Rosa Figueroa who posted this responding to one o…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834501008646627328	710536181616758784	"People of faith are pledging to protect and defend undocumented immigrants under attack." https://t.co/3IYQ30m1nH via @sojourners	35.7595730999999972	-79.0192997000000048	NC	352	\N
834501007749029890	4830928745	RT @AnneRiceAuthor: Cuts to childcare for military families overseas? Trump's cuts did this? https://t.co/eVd1UjvIDi	44.3148442999999972	-85.602364300000005	Michigan, USA	83	\N
834501007090540563	3292725757	RT @donaldbroom: MSNBC Reporter Accidentally Leaked The Media's Secret Anti-Trump Agenda On Live TV https://t.co/vsXssuTyRu via @yesimright1	33.7589187999999965	-84.3640828999999997	Everywhere.	768	\N
834501007015079936	354650675	@OngLengImm @FoxBusiness Donald Trump's vacation expenses at his own resort in one month were more than Barack Obama's entire first year.	40.7127837000000028	-74.0059413000000035	nyc	363	\N
834501006725484544	1631341752	RT @ClimateReality: In “Fahrenheit 451,” they burned books. Today, they take down science websites. But they can’t change reality https://t…	37.8043637000000032	-122.271113700000001	Oakland, CA	38	\N
834501006432096256	48599448	RT @MarciaBunney: 33 questions about Donald Trump and Russia https://t.co/kkg3SM3bCa	40.7127837000000028	-74.0059413000000035	New York City	145	\N
834501006398541825	265755224	RT @TimKarr: Trump's chief digital officer escorted out of the White House after failing FBI background check https://t.co/U4GIgayjay #Shit…	43.0730517000000006	-89.4012302000000005	Madison	769	\N
834501006385881088	2475393662	RT @nytimes: Trump says that his campaign had no contact with Russia. Russian officials contradict him. https://t.co/AgIz9fAlvm	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
834501006180311040	426650276	RT @stockguy61: IMPEACH Trump SOON!! https://t.co/8nMsTAxSgf	37.0902400000000014	-95.7128909999999991	United States	44	\N
834501006167781376	1157872273	RT @pbpost: NEW: @TheEllenShow rips security at Trump’s Mar-a-Lago in new commercial\nhttps://t.co/HTwi8mt2iP @potus @realdonaldtrump @white…	26.7153424000000008	-80.0533745999999979	West Palm Beach, FL	770	\N
834501005823791104	15891995	RT @ObsoleteDogma: Trump might speed up what seemed like a 15 or 20 year trend: the Sun Belt's move from Republican to Democrat https://t.c…	37.6163116999999971	-122.3901106	California Global	771	\N
834501004452306944	3210417094	"It's up to the #states to decide" is a cop-out. Protect #Trans rights! | #Trump to lift trans #bathroom guidelines https://t.co/kk5kahPyxF	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
834501003475091457	14607035	RT @conradhackett: Republicans trust Trump more than Congress\nDemocrats fear Congress won't stop Trump\n\nhttps://t.co/R35uH54ywU https://t.c…	40.5852602000000005	-105.084423000000001	Fort Collins, CO	772	\N
834501003105927169	2513357536	RT @nytimes: President Trump appears on the verge of reversing protections for transgender students, officials said https://t.co/CouRzVKuVN…	37.8393331999999987	-84.2700178999999991	Kentucky, USA	88	\N
834501002678108162	69580586	Trump is President!!!!!!  #TellASadStoryIn3Words	38.9071922999999984	-77.0368706999999944	washington, dc 	773	\N
834501001876869120	792529889991725057	Enda Kenny to address his future after Trump meeting https://t.co/PQ6j4CUCo4 https://t.co/TXkDk5gEvG	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
834501000362881025	831610422629392386	RT @washingtonpost: "Poll: Donald Trump is losing his war with the media" https://t.co/4IslDQV36Y	42.6220234999999974	-73.8326232000000005	Delmar, NY	774	\N
834500999196729344	749497339639762945	WAHOOOOO!! I made a comment yesterday that, why couldn't Trump reverse what Obama did and look today, he said HE IS… https://t.co/oWviApEq4f	37.0902400000000014	-95.7128909999999991	United States	44	\N
834500998630629377	785256748869443585	RT @benjaminja: 5 year old or Trump? \n\n"Leaving him alone for several hours can prove damaging, bc he consumes too much television” https:/…	25.7616797999999996	-80.1917901999999998	Miami, FL	141	\N
834500998185971712	85935544	RT @jason_koebler: More than 3,000 scientists have already expressed interest in running for office to oppose Trump: https://t.co/zaC2zInwgm	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
834500997426864130	284757897	RT @ResistanceTees: Glad they asked if Trump was going to be watching the Oscars, but nobody asks about Russia. Guess we're over that whole…	42.4072107000000003	-71.3824374000000006	MA	775	\N
834500996667678720	768140059497365504	RT @kylegriffin1: Miller's language here is destined to be used in lawsuits against Trump's new immigration ban. https://t.co/pdkPu5PZ1t	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
834500996407582720	840658771	Listening to TRUMP--TIES W/RUSSIAN MOB&amp;MYSTERY RUSSIAN BILLION... by RoughRiderz-RADIO https://t.co/kpErt8DceD	37.9735346000000007	-122.531087400000004	San Rafael, CA	463	\N
834500996344795136	720940290635341825	RT @pattymo: This is an article about a 70 year-old man who is also the President of the United States https://t.co/EwZSNbvyRd https://t.co…	37.4315733999999978	-78.6568941999999964	Virginia, USA	263	\N
834500996172771328	26468518	RT @thegarance: Trump White House ousted its new chief digital officer after he failed the background check https://t.co/ej0dD4uf3H https:/…	51.5073508999999987	-0.127758299999999991	London	420	\N
834500995358920704	38514131	RT @paulwaldman1: This story is amazing. Trump aides plant stories in conservative media so they can show him and manage his moods: https:/…	46.5180823999999973	-123.826451199999994	Pacific Northwest	656	\N
834540516255682563	478774015	RT @washingtonpost: GOP senator says she’s open to demanding Trump’s tax returns as part of Russia probe https://t.co/1b4COKdVAs	38.6270025000000032	-90.1994042000000036	St. Louis, MO	777	\N
834540515366490113	633245763	RT @politico: Trump's Russia problem dogs Republicans at town halls https://t.co/pq7TeK6uiV https://t.co/FfgelhCt0t	41.8239890999999986	-71.4128343000000001	Providence, RI	778	\N
834540935811850241	827717615816736769	RT @MartinaSark6: How's the GOP's suicide pact with Trump playing in Iowa? Not well https://t.co/wB2Xyjidoe	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
834540515206901761	578421655	RT @DylanByers: New @CNN: Media more trustworthy than Trump, poll finds https://t.co/D07ej3wfqe h/t @ThePlumLineGS https://t.co/0w55t6HW8g	-25.2743980000000015	133.775136000000003	Australia	779	\N
834540514666020864	3248732129	RT @MorinToon: Give me your rich, your corrupt, your self-absorbed and greedy yearning to suffocate the middle class #morintoon #Trump #Imm…	40.9126389999999986	-111.892747999999997	My own little world 	780	\N
834540514384961537	746830315952480256	RT @thehill: Poll: Two-thirds of Americans fear Trump will involve US in another major war https://t.co/cP2ro8TAXF https://t.co/0ZJVE8tIdh	37.0902400000000014	-95.7128909999999991	United States	44	\N
834540514242342912	4872282796	@peterdaou @CNN Does trump  ever work??	42.408430199999998	-71.0119947999999965	Revere, MA	781	\N
834540514120724480	733438971859107840	RT @TPInsidr: Rev. Graham is Thankful First Lady Melania Trump is Sharing Her Christian Faith https://t.co/VzXT3RTvzH	37.0902400000000014	-95.7128909999999991	United States 	782	\N
834540513231564800	829364270748094465	RT @OSheaToday: How to turn Trump’s Twitter account against him in 10 seconds or less https://t.co/tNB2btn9xJ via @Recode	25.7616797999999996	-80.1917901999999998	Miami, FL	141	\N
834540513046908929	750371862220115969	RT @NewssTrump: TAKE OUR POLL: WOULD YOU SUPPORT JUDGE JEANINE AS TRUMP’S SUPREME COURT PICK? https://t.co/CiGZwmiOyS https://t.co/l8hzHdbr…	39.5500506999999999	-105.782067400000003	Colorado, USA	212	\N
834540512891711488	3061715160	RT @PalmerReport: I told you the Trump Russia intel leaks would go silent this week – and it’s a sign of progress https://t.co/6dvMTrc8WG #…	46.5180823999999973	-123.826451199999994	Pacific Northwest	656	\N
834540511750975489	4926134953	RT @JuddLegum: To review, since Trump became prez we:\n\n1. Spent $10M on his golf trips to Mar-a-lago\n\n2. Cut military child care\n\nhttps://t…	45.621631800000003	-94.2069364999999976	Sartell, MN	783	\N
834540511620784128	2460749166	RT @AutumnE46: Yeah, tough shit!!: Trump voters are still feeling sad and attacked, and we really don't give a damn https://t.co/5y9mLi1e1Z	-33.8688197000000031	151.209295499999996	Sydney NSW Australia	784	\N
834540510895300608	242374336	The Trump family's lavish lifestyle is costing taxpayers a fortune https://t.co/D1nxLW46jt https://t.co/UC40X3R3QL	40.7127837000000028	-74.0059413000000035	New York	214	\N
834540510739984384	798211286010130432	VA Whistleblower Sends Urgent Letter to President Trump https://t.co/2mdNUa3A9H https://t.co/myQrhxaqYl	40.7127837000000028	-74.0059413000000035	Nueva York, USA	81	\N
834540510433914880	82461587	RT @Forbes: Trump's 3 trips to Mar-a-Lago have cost taxpayers about $10 million https://t.co/7boMQz7nYF https://t.co/vDeQ6Z6Vz3	43.8508552999999992	-79.0203731999999945	Ajax, Ontario, Canada	785	\N
834540510106693632	2290504362	RT @DineshDSouza: CAUGHT RED HANDED: The @nytimes can't say "Trump is deporting illegals" so they have to lie &amp; say "Trump is deporting imm…	33.8543346000000014	-112.125137199999998	Anthem, Arizona	786	\N
834540509842530304	2253787674	RT @VP: Businesses are already reacting to @POTUS Trump's "Buy American, Hire American" vision with optimism and investment in our country.	40.326740700000002	-78.9219697999999994	Johnstown, PA	787	\N
834540509641125889	169394930	RT @PostRoz: .@SenatorCollins says she's open to issuing subpoena for Trump's tax returns as part of Russia probe https://t.co/17MpMJgAJ7 v…	43.5991801999999993	-79.6623565000000013	Proudly Canadian	788	\N
834540509372624896	31343064	RT @HRC: Now is the time for every single person to stand up for transgender kids under attack by the Trump Administration. #ProtectTransKi…	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834540508462604289	265413212	@mattyglesias isn't it also the opposite of want Trump wants for trade?	40.4167022000000031	-86.8752869000000061	Lafayette, IN	789	\N
834540508215144448	2615111313	RT @danny_dire_: some kids on my block made an anti-trump protest with toy dinosaurs and i'm dying https://t.co/fZKhe6fgqu	34.2331373000000028	-102.410749300000006	Earth	481	\N
834540507846025217	15182214	RT @MrJamesonNeat: $30 million a month is being spent for Melania to live in NYC but Military child care programs are suspended due to Trum…	42.0405852000000024	-87.7825621000000069	Morton Grove, Illinois	790	\N
834540507560816640	403859962	Sadly for US, Azerbaijan autocrat's behavior doesn't feel as unfamiliar as it would have before Trump regime. https://t.co/iNYQwyzjY6 #	42.3600824999999972	-71.0588800999999961	Boston, MA	149	\N
834540507489394688	798906576098603008	@GC_bikini @VP Sadly I could see this as Trump's next executive order. Dystopian society here we come. 😥	47.6062094999999985	-122.332070799999997	Seattle, WA	139	\N
834540507141386241	2904587352	@Rosie It didn't work when Obama tried, or when Clinton tried...but that IS how we got Trump so thanks :)	30.1765913999999995	-85.8054879000000028	 Panama City Beach, Florida	791	\N
834540507099455488	16746076	The Trump family's lavish lifestyle is costing taxpayers a fortune https://t.co/QOkrk6nPUY https://t.co/pEeTu7m9hK	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834540505983774721	927089431	RT @mikeh8518: @Impeach_D_Trump I have heard thatTrump has a financial interest in this pipeline, certainly an attorney could find some imp…	43.1938516000000021	-71.5723952999999966	New Hampshire, USA	792	\N
834540505958473728	593871970	Alveda King defends Trump against bogus ‘racist’ label, says it’s a result of ‘fake news’ https://t.co/VothpFAreB https://t.co/LF1TyVURtv	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834540505744687104	68226471	I know he's doing what trump won't and all but seeing him on a bullhorn all I can hear is "there's nothing to see h… https://t.co/qzdr3RKIC3	40.2671940999999975	-86.1349019000000027	Indiana, USA	100	\N
834540505388064768	37969344	RT @AIIAmericanGirI: Poll: Majority Want Fewer Refugees, Support Donald Trump's Migration Cuts @BreitbartNews\nhttps://t.co/13QVsVLfQg	45.5897694000000016	-122.595094200000005	PDX	793	\N
834540505371381761	110361695	RT @MrJamesonNeat: $30 million a month is being spent for Melania to live in NYC but Military child care programs are suspended due to Trum…	51.6286109999999994	-0.748229000000000033	High Wycombe, England	794	\N
834540505040052229	1969133372	RT @GrahamPenrose2: #Trump is deToqueville Reborn, Being #Sisyphus - They Made Desolation They Called It Peace: The Wheel &amp; The Line https:…	-38.4160970000000006	-63.6166720000000012	Argentina	795	\N
834540504951963648	367768348	RT @BostonGlobe: A month into Trump's presidency, GOP lawmakers are facing angry foes at town hall meetings https://t.co/FdCvnUAqBo https:/…	31.9685987999999988	-99.9018130999999983	Texas	381	\N
834540504507416577	28101276	RT @infolibnews: SICK: NBC News Uses Kids As Pawns to Attack Trump https://t.co/ldmNvG2IHI	51.1656910000000025	10.4515259999999994	Germany	796	\N
834540504490528770	346015198	RT @RawStory: 'LEAVE HIM': Twitter reacts to video that seems to show Melania Trump flinching at her husband's touch https://t.co/qH06ZCMug…	44.3528980999999973	-121.177812900000006	Terrebonne, OR	797	\N
834540504272494594	14313371	RT @Newsweek: Eichenwald: The reasons why Trump should be very troubled by the Flynn-Russia affair https://t.co/Cf89zsBEqe https://t.co/XWp…	39.0457548999999986	-76.6412712000000056	Maryland, USA	234	\N
834540503945338880	3679704142	RT @ezlusztig: The MOMENT it emerges Trump's campaign colluded w/Russians to undermine Clinton, we demand A NEW ELECTION. Not President Pen…	35.7595730999999972	-79.0192997000000048	NC, USA	798	\N
834540503421042689	823005565274226689	RT @dabeard: As taxpayers paid $10m for 3 #Trump weekends in Florida, a Trump hiring freeze ended pre-K, daycare for US military families i…	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834540502498365441	2244306842	The Trump family's lavish lifestyle is costing taxpayers a fortune https://t.co/qEx8oNmq1C https://t.co/yWix1vbeA9	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834540502229860352	27888312	RT @dabeard: As taxpayers paid $10m for 3 #Trump weekends in Florida, a Trump hiring freeze ended pre-K, daycare for US military families i…	39.0119019999999992	-98.4842464999999976	Kansas	799	\N
834540501814620161	250117654	RT @ananavarro: President. Donald. Trump. https://t.co/pnPAydkkVS	50.629249999999999	3.0572560000000002	Lille, France	800	\N
834540501806243840	1398464959	GOP are looking for nukes in marijuana bales. I expect they are only finding Trump's stash. Lol	37.0902400000000014	-95.7128909999999991	USA	56	\N
834540501399330816	603798545	Trump Vows to Cut Waste in First https://t.co/okyNLNmnqy https://t.co/OlaFEs95Dj	28.5383354999999987	-81.3792365000000046	Orlando, FL	130	\N
834540500975763458	2815042585	RT @nytimes: One NYT reader's reaction to the Trump administration's new deportation rules https://t.co/CXDkmliN1V https://t.co/4JUhfonN0U	29.4241218999999994	-98.4936282000000034	San Antonio TX	801	\N
834540498966679552	1955132936	Trump: The Budget We Are Inheriting 'Is a Mess' - Breitbart https://t.co/1DPeIWS3Mn \n\nOBAMA AND DEMS LEFT THIS COUNTRY IN A MESS	38.9586307000000005	-77.3570028000000036	Reston, Virginia	287	\N
834540498882699264	831354483749879809	Trump gets under Keith Ellison’s skin by delivering a backhanded compliment before DNC chair election… https://t.co/UuX6P9Y4Rz	40.7127837000000028	-74.0059413000000035	Nueva York, USA	81	\N
834540498614259712	827364353724731392	Fabulous, now we have a place for Trump and his family!  Woop woop #resist https://t.co/Cej9zQkjN3	35.5950581000000028	-82.5514869000000004	Asheville, NC	802	\N
834540498543075328	760797750	RT @TVietor08: Particularly disgusting of the Trump campaign to brag about using Gold Star Mothers as a political prop. https://t.co/VKVCgi…	39.0457548999999986	-76.6412712000000056	Maryland	803	\N
834540498354372609	34808055	RT @paulapoundstone: After saying for months that NATO is obsolete, now Trump says he is a fan of NATO. He talks out of both sides of his a…	43.1610299999999967	-77.6109218999999939	Rochester, NY	804	\N
834540497846693890	788143446989025280	RT @kylegriffin1: This is a story about keeping a 70-year old man's Twitter habit under control https://t.co/1iq5uf7U3F https://t.co/kUQtfe…	37.552205899999997	-122.329959799999997	Alameda, CA and Sonora, CA	805	\N
834540497750331394	20562637	The Trump family's lavish lifestyle is costing taxpayers a fortune https://t.co/vgmEvkgCcA https://t.co/WGlN8bAS51	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834540497540636672	303827284	RT @BruceBourgoine: No mistake about it @Governor_LePage is asking Trump to steal a gift made to both the people of Maine &amp; people of Unite…	53.5409298000000007	-2.11136590000000002	Oldham Lancs UK	806	\N
834540497527939073	1345567362	RT @alfranken: It doesn't end with Flynn. Call for an investigation into the Trump Admin's connection with Russia. https://t.co/fyKwhA9eZ9	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834540497167343617	3592477283	RT @nycjaneyvee: Trump 2016: "People are angry and America is a hellhole!"\nTrump 2017: "Angry people must be paid protesters!". \nPick one,…	40.725158399999998	-74.0049309999999991	here	807	\N
834540496672419840	14992576	RT @AynRandPaulRyan: Trump HATES this video. We need to plaster it everywhere, every day, until the impeachment. #TheResistance #NoFascistU…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834540496655699970	223989188	@3lectric5heep @laurape00486139 SWEDISH JOURNALISTS CONFIRM That Trump Is Dead On About Sweden [Video] https://t.co/QDpAcHpzcX @CBCPolitics	56.1303660000000022	-106.346771000000004	Canada	257	\N
834540496605310978	15885801	RT @HuffPostPol: White House petition demanding Trump release tax returns gets over 1 million signatures https://t.co/KQFQxW4oT5 https://t.…	52.2053370000000001	0.121816999999999995	Cambridge	808	\N
834540495904743424	328844693	RT @kylegriffin1: Trump's 1st month in office includes:\n\nGolf—25 hrs\nForeign relations—21 hrs\nTweeting—13 hrs\nIntel briefings—6 hrs\nhttps:/…	49.2827290999999974	-123.120737500000004	Vancouver, BC	310	\N
834540495267323904	2872795917	RT @mitchellvii: Trump's best play to rid America of illegals is to remove the attractive hazard. Make it impossible for employers to hire…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834540494612934656	710555839573024768	RT @LilMikitten: President Donald Trump #TellASadStoryIn3Words	51.1829547999999974	3.09386420000000006	Eric	809	\N
834540494558490624	532634600	RT @ScottPresler: "Democracy Dies In Darkness" is precisely why Americans don't trust the media.\n\nPresident Trump is keeping all of his pro…	31.9685987999999988	-99.9018130999999983	Texas	381	\N
834540494373793793	819238743521497090	@TLTESQ37 does he realize it's costing tax payers  $1.5mil dollars a day for security at Trump Towers for Melania?… https://t.co/zpOl7p17by	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834540493912543232	243963524	RT @kylegriffin1: This is a story about keeping a 70-year old man's Twitter habit under control https://t.co/1iq5uf7U3F https://t.co/kUQtfe…	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
834540493824466946	38857156	RT @kimberlypatch: Me reads this: What is happening in our country?\nMy 10yr old daughter: Trump is happening to this country. #NoDAPL #Rais…	40.4172871000000029	-82.9071229999999986	Ohio	766	\N
834540493732245505	326570183	The more Democrats attack Trump the more he loves it, makes him only stronger and them weaker and hated by voters.	37.0902400000000014	-95.7128909999999991	United States of America	534	\N
834540493132414976	4837060487	RT @thehill: Pence selecting members for task force to investigate Trump's claim of widespread voter fraud https://t.co/dov3d1AVbl https://…	43.7844397000000001	-88.7878678000000008	Wisconsin, USA	91	\N
834540492897525760	2263320834	RT @kylegriffin1: .@HRC on Trump rolling back transgender student protections: "What could possibly motivate a blind and cruel attack on yo…	39.0457548999999986	-76.6412712000000056	Maryland, USA	234	\N
834540492725460992	131963992	RT @ananavarro: President. Donald. Trump. https://t.co/pnPAydkkVS	21.306944399999999	-157.858333299999998	Honolulu	810	\N
834540492654313473	820831780244692993	RT @washingtonpost: GOP senator says she’s open to demanding Trump’s tax returns as part of Russia probe https://t.co/1b4COKdVAs	35.8456212999999977	-86.390270000000001	Murfreesboro tn	811	\N
834540492440354816	922974936	RT @jbarro: It is amazing the extent to which Trump's top staffers have it out for each other. https://t.co/vTHiCVh57M	40.7127837000000028	-74.0059413000000035	 NY & NJ 	812	\N
834540492230520833	805111091810471936	Robert Reich Implies Trump Incited Sweden’s Migrant Riots  Robert Reich, a professor at UC...… https://t.co/eni76lhocZ	37.0902400000000014	-95.7128909999999991	USA	56	\N
834540491807064064	77326391	Hundreds Rally for Trump Impeachment in Atlanta https://t.co/0uMS4kJ4Dm	33.7489953999999983	-84.3879823999999985	Atlanta	182	\N
834540490884263936	158823516	RT @SumSheek: Mashable says it's thriving by embracing quality journalism — and avoiding the same old Trump stories https://t.co/PVlw8Nopoi	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
834540490523545600	1028532780	RT @caitlinzemma: DeVos has reportedly been shut out of the DACA conversation, in addition to losing on transgender directive: https://t.co…	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834540490158645248	808038524	RT @FoxNews: .@oreillyfactor: It is not a stretch for any fair-minded person to believe that the national media leans heavily left, despise…	38.6270025000000032	-90.1994042000000036	St. Louis	247	\N
834540489965727748	3830376237	RT @CNNPolitics: How President Trump could change the fabric of the US without changing its laws https://t.co/g3HO8l9w7M https://t.co/B4fsA…	25.7616797999999996	-80.1917901999999998	Miami, FL	141	\N
834540489789603840	20655334	Did he explain this to #Trump who was very concerned about the #Dollar https://t.co/fwKHONsHfZ	40.7127837000000028	-74.0059413000000035	New York	214	\N
834540631678521344	345161742	RT @TheWeek: President Trump has no idea how the trade deficit works, says @jeffspross: https://t.co/hsWc30IzBN https://t.co/4KJXgVOQcq	34.693737800000001	135.502165100000013	Osaka	814	\N
834540631351492608	1887921582	@matthewjdowd I don't take a lot out of Trump approval polls now.  After a jobs report.  After a GDP report.  Then it really matters.	42.6651965000000004	-82.9286428000000058	Macomb Twp	815	\N
834540630986481665	766499969696169984	Protester Gives the Cops the Bird and Immediately Gets Shot and Taken Down https://t.co/eBdCubnOmU https://t.co/iL8mjbGDTi	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834540630621577216	16080536	RT @dabeard: As taxpayers paid $10m for 3 #Trump weekends in Florida, a Trump hiring freeze ended pre-K, daycare for US military families i…	-37.7870011999999988	175.279253000000011	Hamilton, New Zealand	816	\N
834540630433026048	1342700142	@dburbach\n"If Trump destroys the world before we can colonize this I'm gonna be MAD"\n(paraphrasing @ShanaMlawski 's joke- can't find tweet 🙃	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
834540630370054144	21718571	"Donald Trump has been playing footsie with the radical Whites of the United States" -Mark Potok @RUWithSonali	39.739235800000003	-104.990251000000001	Denver, Colorado	817	\N
834540629178871808	798485769308532736	@nichugme @ABC probably because trump claims the source as legitimate.	40.4172871000000029	-82.9071229999999986	Ohio, USA	469	\N
834540628780265472	17031234	RT @politico: Trump's Russia problem dogs Republicans at town halls https://t.co/pq7TeK6uiV https://t.co/FfgelhCt0t	34.0522342000000009	-118.243684900000005	Los Angeles, California	818	\N
834540628700647424	797252185109254144	Judge blocks California law limiting publication of actors' ages https://t.co/5E28b1h9Rt https://t.co/nU8FCapPYP	40.0656291000000024	-79.8917138999999992	California, PA	738	\N
834540627933093892	767567215638052864	Protester Gives the Cops the Bird and Immediately Gets Shot and Taken Down https://t.co/JrQ8T7tdO0 https://t.co/Qg2qOqyvCk	40.7127837000000028	-74.0059413000000035	Nueva York, USA	81	\N
834540627366969344	148628139	RT @TrumpUSAforever: 🇺🇸#mediasurvey🇺🇸 Do you believe the #MSM has reported unfairly on the Trump movement? VOTE AND RETWEET!!	39.9525839000000005	-75.1652215000000012	Philly	819	\N
834540626876194818	781709113713684480	RT @businessinsider: The Trump family's lavish lifestyle is costing taxpayers a fortune https://t.co/vgmEvkgCcA https://t.co/WGlN8bAS51	-1.32271019999999995	36.9260693000000018	Nairobi. Winnipeg	820	\N
834540626595168256	1210646653	RT @OhNoSheTwitnt: #TBT (Throwback Trump) https://t.co/5lswn9mZz4	40.7127837000000028	-74.0059413000000035	NYC	60	\N
834540626175733761	2267775933	RT @JoyAnnReid: .@PressSes saying ppl don't have enough sense to know they're losing the healthcare they have and would prefer an unnamed T…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834540625194266625	1258489765	RT @businessinsider: Former Trump trade adviser: Border-adjustment tax could go a long way toward improving NAFTA https://t.co/PxyK1iNQXt h…	23.6345010000000002	-102.552784000000003	Mexico	428	\N
834540624758132740	747808244475830273	RT @varepall: Trump: The Budget We Are Inheriting 'Is a Mess' - Breitbart https://t.co/1DPeIWS3Mn \n\nOBAMA AND DEMS LEFT THIS COUNTRY IN A M…	43.628014499999999	-94.9143238999999994	Minnesota/Wisconsin	821	\N
834540623780839426	21097079	@SashPointO @matthewjdowd Like @WahcaMia said, how can anyone believe pathological liar/not #freepress? Trump has immunity/press can b sued.	32.776664199999999	-96.7969879000000049	Dallas, TX	267	\N
834540623717859332	17156932	Donald Trump is losing his war with the media https://t.co/otELEzINGd	29.9584426000000015	-90.0644106999999963	French Quarter, New Orleans	822	\N
834540623713689600	14313371	RT @abbydphillip: The all-out war between Trump adviser Sebastian Gorka and his critics in the nat sec world is b-a-n-a-n-a-s https://t.co/…	39.0457548999999986	-76.6412712000000056	Maryland, USA	234	\N
834540623277420544	489991894	Mexico's foreign secretary rejects Trump deportation policy https://t.co/x7ji2us7lH https://t.co/gDtOFYxrBE	6.42375000000000007	-66.589730000000003	Venezuela	823	\N
834540622749040641	451857367	RT @Earnest_One: Someone tell this Nincompoop that he is not King, Supreme Leader, or Caesar. He is our Employee.  Clearly, Trump can't do…	40.7127837000000028	-74.0059413000000035	Ny	824	\N
834540622287605764	108020041	RT @kerryeleveld: As Team Trump vetoes not-loyal-enough staff picks, hundreds of administration jobs remain unfilled via @hunterDK https://…	39.1607284999999976	-86.5460669999999936	J.David Stevens 	825	\N
834540622015057925	301634807	RT @Drjohnhorgan: So, one day, Mia Bloom, Clint Watts &amp; Seb Gorka went to the Defense Intelligence Agency. Then this happened: https://t.co…	38.9071922999999984	-77.0368706999999944	Washington DC	686	\N
834540621956268032	761585164656971776	RT @ImNotRobFrei: #IfIWonThePowerball I would build a museum and call it the Hall Of Shame. it would be an ode to Trump's most shameful twe…	47.6062094999999985	-122.332070799999997	Seattle, WA	139	\N
834540621700354049	14292092	RT @thinkprogress: Trump’s first month travel expenses cost taxpayers just less than what Obama spent in a year https://t.co/bb2oD8p2Os htt…	44.7916669999999968	-72.5827780000000047	Gorgeous Green Mtns of Vermont	826	\N
834540620727349249	797095725901447168	RT @RachelStoltz: Trump didn't put illegal immigrants "at risk" of getting deported. Coming here illegally did. https://t.co/tzsrsR3NbS	37.0902400000000014	-95.7128909999999991	United States	44	\N
834540619867488256	581461273	@deray Did Trump pass a background check.	33.0185038999999989	-80.1756481000000036	Summerville, SC	827	\N
834540619557195776	10819222	@trishlawish @VicenteFoxQue If Fox would have been half as tough on cartels as he is on Trump, maybe his country wouldn't be in shambles.	32.7764748999999966	-79.9310511999999989	Charleston, SC	828	\N
834540619330703361	19344401	Trump expected to revoke Obama transgender bathroom directive https://t.co/DzJqd3eAzb	27.4989278000000006	-82.5748193999999955	Bradenton, Florida	829	\N
834540619074793472	3234962824	RT @brontyman: There is a second sacred wall at the CIA. Trump disrespects that one every day. - The Washington Post https://t.co/BHHEkPxAhJ	44.3148442999999972	-85.602364300000005	Michigan, USA	83	\N
834540618554732544	106517855	Maxine Waters: Trump admin  bunch of scumbags. They’re all organized around making money\n\nGASP\n\nImagine an economy organized around making $	37.9873515999999967	-84.5209080999999998	Brigadoon	830	\N
834540618315612166	2790778640	RT @LOLGOP: Kind of like how Trump and Pence have been calling out antisemitism but Bannon still works for them. https://t.co/d0oTwDheP9	42.5770022999999966	-78.2528190000000023	Bliss 	831	\N
834540617703108608	1183316539	RT @mmpadellan: There's a reason for trump's #contradictrumps on his taxes. He's HIDING his #TrumpRussia #Russiagate smoking guns. #wednesd…	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834540617669758976	41508711	RT @MassAGO: Trump, reconsider this wrongheaded policy. Pursue comprehensive immigration reform rather than spreading fear &amp; eroding the pu…	42.3736158000000032	-71.1097335000000044	Cambridge, MA	832	\N
834540617019461632	789623538340601856	RT @ScottPresler: My being an American means I care for ALL of my American brothers &amp; sisters. 🇺🇸\n\nEven Trump supports Caitlyn Jenner. \n\n#w…	33.4483771000000019	-112.074037300000001	Phoenix, AZ	833	\N
834540616709242880	3496411936	Mexico ‘will not accept’ Trump’s new immigration ban | New York Post https://t.co/tT4Jbc7bHC	39.8915021999999979	-75.0376707000000067	Haddonfield, NJ	834	\N
834540615958413313	35313560	Meet the 23 Republicans blocking Congress from seeing Trump's tax returns. Is your rep on the list? https://t.co/gxtliIeikZ	32.3546679000000026	-89.3985282999999953	Mississippi	835	\N
834540615912325126	97941504	RT @dissonance_pod: Someone woke up Sméagol to ask what he thought. And so he could choke down some strained carrots. https://t.co/FwN8jrBD…	40.4406248000000019	-79.9958864000000034	Pittsburgh, PA	99	\N
834540614725144581	767567215638052864	URGENT: 74-Year-Old Vet Prosecuted by Obama for Displaying American Flag https://t.co/qe5sE9l3L6 https://t.co/l06O1sdMh5	40.7127837000000028	-74.0059413000000035	Nueva York, USA	81	\N
834540614624608256	58246576	RT @LouDobbs: Trump admin working with Mexico - Tillerson, Kelly talk border, law-enforcement &amp; trade with Peña Nieto. @EdRollins joins #Do…	34.8526176000000021	-82.3940103999999991	Greenville, South Carolina	836	\N
834540614314254337	760507702833471488	RT @os4185: Lt. Col. Tony Shaffer: Obama Laid Tripwires&amp;#8221; in Intel Community to Sabotage Trump https://t.co/KLWSQzuGUK	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834540614100201472	797252185109254144	Protester Gives the Cops the Bird and Immediately Gets Shot and Taken Down https://t.co/HAkUH8llym https://t.co/pZl7GN4Cfs	40.0656291000000024	-79.8917138999999992	California, PA	738	\N
834540614096191488	19571797	O'Reilly: Trump Must Use Discipline, Facts To Win Culture War https://t.co/3sURMgMAFM	37.0902400000000014	-95.7128909999999991	America	203	\N
834540613949353984	4785624496	RT @Pamela_Moore13: .@RandPaul: "I would actually say Trump has done more in the last four weeks than we've done in the last six years." ht…	41.5800945000000013	-71.4774290999999948	Rhode Island, USA	837	\N
834540613492232192	119044017	RT @JoyAnnReid: Trump's win is allowing Republicans to implement every extreme idea they've ever had, on healthcare, reproduction, taxes. m…	30.2671530000000004	-97.743060799999995	Austin, TX	106	\N
834540613253074945	1618641848	RT @ChristieC733: .@KarlRove please don't give President Trump advice. \n\nMcCain  ✖️\nRomney ✖️\nJ Bush    ✖️\n\nThree strikes you're out! \n\n#dr…	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834540613123006464	4852429895	RT @CNNPolitics: Mexico slams the Trump administration's immigration plan ahead of Secretary of State Rex Tillerson's visit https://t.co/4Z…	47.7510740999999967	-120.740138599999995	Washington, USA	82	\N
834540613056004099	4120430787	RT @grillguy54: @ABCPolitics Trump did say he wanted to keep manufacturing in USA. So we are manufacturing protests locally!	43.8169837000000015	-79.532156999999998	Worldwide	838	\N
834540612355497989	119161370	Kris Kobach was the architect behind the most stringent #immigration laws in the country; illegal aliens beware https://t.co/ef9bGWmdwF	37.0902400000000014	-95.7128909999999991	USA	56	\N
834540611772354561	766499969696169984	URGENT: 74-Year-Old Vet Prosecuted by Obama for Displaying American Flag https://t.co/8IDeQoUmb3 https://t.co/5MUy6hsVKf	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834540611634016257	797243715320500226	Protester Gives the Cops the Bird and Immediately Gets Shot and Taken Down https://t.co/8TjpELLw9F https://t.co/vUhruHLOGe	35.0077519000000024	-97.0928770000000014	Oklahoma, USA	676	\N
834540611529236480	812810833831096320	RT @rolandscahill: @EthanTL2002 @realDonaldTrump here you go: https://t.co/ATmXaxqmFv	26.0112014000000009	-80.1494900999999942	Hollywood, FL	839	\N
834540611499761665	315411392	RT @relombardo3: 2▪22▪17\nNative People Are Being Forced Off Their Treaty Land Today By Trump's Administration.\nGov Has Power To Take Our La…	37.0902400000000014	-95.7128909999999991	USA	56	\N
834540611277565953	159930435	RT @VP: Businesses are already reacting to @POTUS Trump's "Buy American, Hire American" vision with optimism and investment in our country.	44.9537029000000032	-93.0899577999999934	St. Paul, MN	840	\N
834540611034157056	16557300	RT @businessinsider: Trump has a problem: Americans increasingly think he's incompetent https://t.co/PfCWJc2CO7 https://t.co/4qbpSvew5V	37.7749294999999989	-122.419415499999999	San Francisco	37	\N
834540610451292160	40255795	Trump's Mar-a-Lago trips cost taxpayers about $10M so far https://t.co/f1FtMlOE45	42.3600824999999972	-71.0588800999999961	Boston, MA	149	\N
834540610191138816	743089596297150466	RT @RealJack: Liberals are losing their mind over President Trump's deportations. Real reason they're upset is because they're losing all t…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834540610035949568	41163204	RT @MattMcNeilShow: #Trump is a kind of a dumb dog, self obsessed with his ball.  The @GOP in Congress are cats on the hunt for specific mi…	41.4925374000000033	-99.9018130999999983	Nebraska, USA	841	\N
834540609591324672	1061623501	RT @EricHolthaus: A brave EPA employee securely contacted me with a heartfelt message for all Americans.\nHere is what they wrote:\nhttps://t…	37.8687660000000008	-122.256557999999998	berkeley/oakland	842	\N
834540609352454144	55381358	RT @gatewaypundit: Trump Rally: DOW Reaches its 27th New High Since Trump Won Election https://t.co/TZUxBpJGN0	40.0583237999999966	-74.4056611999999973	NJ	324	\N
834540609218154497	305568174	RT @BraddJaffy: Crowd asks Rep. Steve Womack (R-AR) to investigate Trump/Russia. \n\nWait for it... https://t.co/4siV7A0cOR	40.7127837000000028	-74.0059413000000035	New York	214	\N
834540609109061632	810070414248513536	RT @DineshDSouza: The left called him a senile Bozo when he ran against Obama--now that he's criticizing Trump, they portray him as an inco…	47.5983889000000033	-122.329908599999996	Seattle / Vancouver	843	\N
834540608488357888	1542502494	Trump signs resolution to permit dumping mining waste into waterways https://t.co/8Z3lETAFT2	32.3512600999999975	-95.3010624000000064	Tyler, TX	844	\N
834540608005894144	2777267753	RT @ericgeller: Senate Intelligence Committee announces confirmation hearing for Trump's DNI nominee, former Sen. Dan Coats. https://t.co/m…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834540771646795776	820296815983505408	RT @politico: So far, Trump has nominated fewer than three dozen of the 550 most important Senate-confirmed jobs https://t.co/KDSdnXVNOJ ht…	41.2211309999999997	-74.453669000000005	Heaven Hills	845	\N
834540771625799681	18261145	@MesyJesi maybe this will work better | When the Enemy of Your Enemy Is — Your Enemy https://t.co/XLdz0M40gU via @NRO	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834540771428544512	1070346631	RT @mitchellvii: What has Trump done as POTUS that is anti-Semitic?  What has he done that is racist?  Actual evidence means NOTHING to the…	15.1793840000000007	39.7823339999999988	T w i t t er 	846	\N
834540771307053056	823217930720526336	RT @JohnTrumpFanKJV: 202-224-2235\nLet's call John McCain and let him know that it is Wrong to criticize President Trump on Foreign Soil.	39.739235800000003	-104.990251000000001	Denver. , U.S.A.	847	\N
834540770594004993	701408955986223104	We Trump ppl.are followers of OUR LORD JESUS. You better be REAL CAREFUL who you refer to as a Cult. Your on the LE… https://t.co/e1mwOgtSxR	37.0902400000000014	-95.7128909999999991	USA	56	\N
834540770249936897	33435305	Sign Sen. @Jeffmerkley's petition to AG Sessions: Appoint a special prosecutor to investigate Trump: https://t.co/aG4xZRDx6N @MoveOn	33.8491816000000014	-118.388407799999996	Redondo Beach, CA	848	\N
834540769868406784	32419544	RT @bocavista2016: NO MATTER\n\nHow much you appease them\n\nSometimes people will NEVER be your friends\n\nhttps://t.co/3xRH5Jrj12\n#Trump #MAGA…	41.6032207000000014	-73.0877490000000023	Connecticut, USA	365	\N
834540768614158340	755442744789655552	RT @thinkprogress: Trump’s first month travel expenses cost taxpayers just less than what Obama spent in a year https://t.co/bb2oD8p2Os htt…	47.7510740999999967	-120.740138599999995	Washington, USA	82	\N
834540768538669058	31217076	RT @thehill: "Deportation force: Trump's new immigration rules are based on lies" https://t.co/5fyjIaxtcV https://t.co/BlMC9GsSh8	34.9592083000000002	-116.419388999999995	Inland Empire	849	\N
834540768337334273	22312991	Dear @FUNimation \nPlease take #theSagaofTanyatheEvil and make Tanya Trump or at least put one of his hats on her.\nThanks	56.1303660000000022	-106.346771000000004	Canada	257	\N
834540767771230209	18342195	RT @DylanByers: New @CNN: Media more trustworthy than Trump, poll finds https://t.co/D07ej3wfqe h/t @ThePlumLineGS https://t.co/0w55t6HW8g	40.6781784000000002	-73.9441578999999933	Brooklyn	611	\N
834540767712571392	220277203	GOP senator says she’s open to demanding Trump’s tax returns as part of... https://t.co/0NyF9ndFBA by #washingtonpost via @c0nvey	43.9695147999999989	-99.9018130999999983	Sud America	850	\N
834540767465000960	15369994	Here we go again! https://t.co/1ZMaoWil8j	34.0522342000000009	-118.243684900000005	Los Angeles, California	818	\N
834540767439884288	16267008	RT @politico: So far, Trump has nominated fewer than three dozen of the 550 most important Senate-confirmed jobs https://t.co/KDSdnXVNOJ ht…	29.5571824999999997	-95.8085623000000055	Rosenberg, TX	851	\N
834540767322443777	1728147644	As taxpayers paid $10m for 3 #Trump weekends in Florida, a Trump hiring freeze ended pre-K... by #justfacetious https://t.co/4BAZleDvpo	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
834540767112732675	48473625	RT @DylanByers: New @CNN: Media more trustworthy than Trump, poll finds https://t.co/D07ej3wfqe h/t @ThePlumLineGS https://t.co/0w55t6HW8g	42.8105356000000015	-83.0790865000000025	Metro Detroit	852	\N
834540766777143296	5391432	RT @MrJamesonNeat: $30 million a month is being spent for Melania to live in NYC but Military child care programs are suspended due to Trum…	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834540766693306368	350647665	"Trump's sheer pace of action will up everyone's game!" -@KellyannePolls on #Congress @CPAC	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834540766462611458	389486216	RT @RealAlexJones: Anti-Trump Groups Use Tax Loophole to Hide Finances - https://t.co/4ReqHHj6Pl	53.1355091000000002	-57.6604364000000018	NEW FOUND LAND, CANADA	853	\N
834540766219399168	18350235	RT @DavidWright_CNN: Just in: Trump admin official tells @SaraMurray new executive order on travel restrictions has been delayed to early t…	40.7353179999999995	-73.988472999999999	Independent Nation of New York	854	\N
834540765716029440	23960942	Amazing how many of Trump's cabinet picks have blatant conflicts of interest in their positions. Do they have the i… https://t.co/V4BO4p5OK7	56.1303660000000022	-106.346771000000004	 CANADA	855	\N
834540765422432256	814120619029725184	RT @ChristieC733: .@KarlRove please don't give President Trump advice. \n\nMcCain  ✖️\nRomney ✖️\nJ Bush    ✖️\n\nThree strikes you're out! \n\n#dr…	40.8256561000000033	-73.6981858000000045	Port Washington, NY	856	\N
834540765258801152	2869798043	Trump has a problem: Americans increasingly think he's incompetent (via @BIAUS) https://t.co/3x62R9vtKg	56.1303660000000022	-106.346771000000004	canada	857	\N
834540765137117184	15985291	RT @DylanByers: New @CNN: Media more trustworthy than Trump, poll finds https://t.co/D07ej3wfqe h/t @ThePlumLineGS https://t.co/0w55t6HW8g	45.5230621999999983	-122.676481600000002	Portland, OR	41	\N
834540765074309120	435295193	@POTUS_Don45 #dumbshit 4 insulting one of #USA best partners! #fuckingwall #ImmigrantsWelcome They work hard!\n\nhttps://t.co/yy9z5XCwch	27.9505750000000006	-82.4571775999999943	Tampa, FL	101	\N
834540764818399233	292679653	Treasury secretary says a strong dollar is a 'good thing,' contradicting what Trump has said at - Business Insider https://t.co/9ZzMd9FzMl	33.745851100000003	-117.826166000000001	Tustin, CA	261	\N
834540764575186944	831323881705177089	What's happening to Trump's popularity? Parsing the polls with Nate Silver - Boing Boing https://t.co/vvjWaEHJFH	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834540764524744704	73998366	Trump has now declared Sweden a Nation non Grata. https://t.co/GgZF5UdgIa	34.0522342000000009	-118.243684900000005	Los Angeles, California	818	\N
834540764218671105	836653135	RT @JBurtonXP: Muslims in Sweden just had to NOT RIOT for like one week in order to make Trump look like he was wrong, but they couldn't ev…	29.9321498000000012	-90.3664693999999997	Luling, LA	858	\N
834540763509698561	797462043729096704	RT @solusnan1: NYPD won't round up immigrants under Trump's deportation orders - NY Daily News https://t.co/Q1YJ3BgFBr	45.5230621999999983	-122.676481600000002	Portland, OR	41	\N
834540762788401153	92556599	RT @melgillman: Apparently too many people "sabotaged" Trump's media survey by...taking it. So he scrapped the results/started over. https:…	30.6711373999999992	-81.4639368999999931	Villa Villekulla	859	\N
834540762394091520	336923967	RT @Lawrence: Why Rupert Murdoch fired the man who called Trump a 'political sociopath' https://t.co/IWWMf0blWd via @msnbc	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834540762033451009	11999982	RT @kylegriffin1: Trump's 1st month in office includes:\n\nGolf—25 hrs\nForeign relations—21 hrs\nTweeting—13 hrs\nIntel briefings—6 hrs\nhttps:/…	41.3082739999999973	-72.927883499999993	New Haven, CT	215	\N
834540761857277957	3234962824	RT @NewYorker: “America First” is not a slogan that offers hope to countries languishing at the bottom of world poverty tables: https://t.c…	44.3148442999999972	-85.602364300000005	Michigan, USA	83	\N
834540761093922816	14161139	RT @jaredshoemaker: Trump "is shallow and his followers are shallow, he shall do what he can to make our society shallower." https://t.co/f…	28.5383354999999987	-81.3792365000000046	Orlando, FL	130	\N
834540761064435712	2933015707	Fuck u #MortonCountySheriff  u scrum terrorist fuk u trump dumb ass shit head n #NDGOV fuk u more send ur products bck not buying	46.3829037	-120.731180100000003	white swan, WA 	860	\N
834540760347336704	822159113719312385	RT @colinjones: "Leaving him alone for several hours can prove damaging, because he consumes too much television" https://t.co/1h8pSPyfd7 h…	42.5792027000000033	-84.4435845	Mason, MI	861	\N
834540760326348800	4132549666	How I did on Twitter this week: 202 New moth species named after President-elect Donald Trump's Inauguration and moose deaths	56.1303660000000022	-106.346771000000004	Canada	257	\N
834540759688867841	3485382014	Trump Campaign Staff Reveals Tricks To Keeping The POTUS Off Twitter (DETAILS) https://t.co/Z8KDNBIhiW via @Bipartisan Report	44.9777529999999999	-93.2650107999999989	Minneapolis, MN	102	\N
834540759311192064	27471898	Eichenwald: The reasons why Trump should be very troubled by the Flynn-Russia affair https://t.co/TgZdImFSfs	37.3382081999999969	-121.886328599999999	San Jose, CA	43	\N
834540757721632768	2385687918	Trump Is Playing Role of Father to Destructive, Deceptive Media • #News • https://t.co/Yw8NzXnIWT... ►	37.0902400000000014	-95.7128909999999991	U.S.A.	231	\N
834540756660584448	161203655	Papaw complaining while in the hospital\n\n"These doctors...Trump will get em straightened out." https://t.co/dOo4wmYGGV	36.3134397000000035	-82.3534726999999975	Johnson City, TN	862	\N
834540756014657537	21663432	Ha! Can U even imagine D J Trump enjoyin somthin as joyfully simple, as "Man &amp; his Dog"? NOoo, Ther will b no Canin… https://t.co/yJbDxpJFz2	30.1588129000000009	-85.6602058	Panama City, FL	863	\N
834540755691642881	16387036	RT @markknoller: "We must do a lot more with less,” says Pres Trump of government spending, "and look for every last dollar of savings.” ht…	35.2010500000000022	-91.8318333999999936	Arkansas	328	\N
834540755355996160	351700595	Stop lying for Trump, he does not care about the people of this country. He only thinks about spending million of t… https://t.co/DaJTT04J7Z	35.3732921000000005	-119.018712500000007	Bakersfield, CA	864	\N
834540754827612160	43322527	RT @kylegriffin1: This is a story about keeping a 70-year old man's Twitter habit under control https://t.co/1iq5uf7U3F https://t.co/kUQtfe…	48.2081743000000031	16.3738188999999998	Vienna, Austria	865	\N
834540754802507776	1899218054	RT @CitizenSlant: Anne Frank Center Head to Trump Surrogate Kayleigh McEnany: ‘Have you no ethics?’ https://t.co/TXn2a7fSbQ https://t.co/SD…	53.7654396000000006	-2.68211850000000007	chester/preston	866	\N
834540754735280128	18690958	RT @Fahrenthold: PGA chief got a "social" call out of the blue from @realDonaldTrump, whose golf courses have sought PGA events. https://t.…	28.4057916000000006	-81.5865869999999944	Aotearoa	867	\N
834540754676637697	269798459	RT @Lawsonbulk: The New Quinnipiac Poll Is Out. It Says 'President Donald Trump's Popularity Is Sinking Like a Rock' https://t.co/LoTVCLGs4p	37.4315733999999978	-78.6568941999999964	Virginia, USA	263	\N
834540754236227586	3867815182	RT @Pamela_Moore13: .@RandPaul: "I would actually say Trump has done more in the last four weeks than we've done in the last six years." ht…	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
834540753749688320	48011439	George Clooney: President Trump and Steve Bannon Are ‘Hollywood Elitists’ https://t.co/1mZWYhrfAZ via @YahooMovies #StopPresidentBannon	40.8758910000000029	-81.4023356000000007	North Canton, OH	868	\N
834540753460330496	15597241	RT @pharris830: City of Las Cruces just said NO to Trump’s wall: State legislators trying to do the same thing!  https://t.co/uIr3lorbSn vi…	46.5883706999999987	-112.024505399999995	Helena, Montana	869	\N
834540753078538240	810277341280669696	RT @SykesCharlie: .@Kasparov63 was arrested and beaten for opposing Putin. Now he's speaking about Trump. He joins me live on #IndivisibleR…	37.8271784000000011	-122.291307799999998	SF Bay Area	166	\N
834540752797569028	853185504	RT @FoxNewsInsider: .@JudgeNap: How @realDonaldTrump's New Immigration Order Could Be 'Bulletproof' @TeamCavuto @POTUS https://t.co/vbv5wnm…	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834540752252264449	8057892	RT @nycjaneyvee: Trump 2016: "People are angry and America is a hellhole!"\nTrump 2017: "Angry people must be paid protesters!". \nPick one,…	45.5230621999999983	-122.676481600000002	Portland, OR	41	\N
834540751652544512	567210744	#trumprussia #resistance Sign this petition and help us meet our goal!  https://t.co/zLp6nh8vcA via @credomobile	41.6032207000000014	-73.0877490000000023	Connecticut, USA	365	\N
834540751186980864	21951034	RT @Lawrence: .@Trevornoah is right: 'I don't think Trump has the balls to go on a show’ that doesn't like him. https://t.co/3Mm7v5XWwN via…	40.9253763999999975	-73.0473283999999978	Port Jeffeson Station, NY	870	\N
834540750700417024	832239649296936960	RT @CharlesMBlow: “'President Trump’s popularity is sinking like a rock,' Tim Malloy, the asst dir of the poll, said in a statement announc…	44.3148442999999972	-85.602364300000005	Michigan, USA	83	\N
834540750691987457	1286821	RT @leahmcelrath: Anyone have expertise in "white power" hate group signs?\n\nIs this accurate?\n\nhttps://t.co/OjHC7TVD6R	39.739235800000003	-104.990251000000001	Denver, Colorado, USA	871	\N
834540749643513856	28201964	Hitlers playbook? \n\nMore insanity on the left. https://t.co/1Cj2I6zdR8	27.6648274000000001	-81.5157535000000024	Florida	183	\N
834540749492412417	976628899	RT @luke_j_obrien: Read this entire article. All of it. Simply incredible this man is taken seriously at all, let alone on the NSC. https:/…	47.5514926000000031	-101.002011899999999	North Dakota, USA	872	\N
834540749265977346	703380295244976128	RT @ALECexposed: Tune in! CMD's @thelisagraves will be on @democracynow tomorrow at 8 ET 7CT to talk about CMD's lawsuit for #pruittemails…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834540748993347584	1171213596	RT @TomthunkitsMind: Trump family’s elaborate lifestyle is a ‘logistical nightmare’ — at taxpayer expense over $10 Million a week. https://…	40.6781784000000002	-73.9441578999999933	Brooklyn, NY, USA	873	\N
834540748947066880	947070450	RT @BraddJaffy: Crowd asks Rep. Steve Womack (R-AR) to investigate Trump/Russia. \n\nWait for it... https://t.co/4siV7A0cOR	62.411363399999999	-149.072971499999994	Westcoast	874	\N
834540748565471232	1928656327	RT @latimes: Trump's preparing to roll back Obama's protections for transgender students. Students in CA have these rights https://t.co/uYZ…	34.9592083000000002	-116.419388999999995	SoCal, USA	875	\N
834540747949010947	4826141870	RT @TheTweetwit: Paying for Donald Trump's expenses in his first month as President is equal to what Obama averaged on a yearly basis. Unbe…	35.0077519000000024	-97.0928770000000014	Oklahoma, USA	676	\N
834540747189809152	208233956	RT @BI_Video: The Trump family's lavish lifestyle is costing taxpayers a fortune https://t.co/qEx8oNmq1C https://t.co/yWix1vbeA9	44.784550000000003	1.98447700000000005	Terre	876	\N
834540747131121665	112532974	RT @Greg_Palast: Palast pulls down the pants on #Trump's claims of millions of illegal voters &amp; exposes the real scam behind it all https:/…	43.6532259999999965	-79.3831842999999964	Toronto	148	\N
834540745805668353	906729811	RT @byHeatherLong: Wow. Telling stats from @QuinnipiacPoll today: Repubs trust Trump to tell the truth; Dems trust the media  (h/t @DylanBy…	42.3370413000000028	-71.2092214000000041	Newton, Massachusetts	877	\N
834540745654730752	586707638	RT @FreeBeacon: .@netanyahu Says Trump’s Recent Denunciation of Anti-Semitism Is ‘Strong’ https://t.co/YOKck8CzJo https://t.co/dziIUYObh5	37.0902400000000014	-95.7128909999999991	USA 	210	\N
834540745226739712	2959119889	RT @SheriffClarke: Like I said. President Trump using the Mohammed Ali Rope-A-Dope strategy on the media. They'll punch themselves out. htt…	38.8375215000000011	-120.895824200000007	Northern California, USA	878	\N
834540744937443329	709203675332386816	@Impeach_D_Trump Prayers for all....	28.5383354999999987	-81.3792365000000046	Orlando, FL	130	\N
834540744744529920	2470250408	Maxine Waters: Trump's Administration, Associates Are 'a Bunch of Scumbags' ... https://t.co/Ws9JNDzAGI	38.4495688000000015	-78.8689155	Harrisonburg, VA	879	\N
834540744245288960	131816912	Trump to rescind transgender bathroom rules from Obama era https://t.co/YlwwUnycD9	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
834540743331106816	299381035	RT @liberalincincy: @BoomMan1976 @FightNowAmerica @petefrt I think some of the simpler ppl that voted Trump have never had experience with…	39.3209800999999999	-111.093731099999999	Utah, USA	880	\N
834540742974509056	325357449	RT @digby56: I get not trusting media. But trusting Trump to tell the truth means 78% of GOP are too daft to be allowed to operate heavy ma…	29.4241218999999994	-98.4936282000000034	San Antonio, TX	433	\N
834540940580773889	789863089785233413	RT @TheViewFromLL2: Felix Sater is someone that President Donald Trump is confident he doesn't know.	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834540938395529216	15273001	RT @FAIRImmigration: Donald Trump's Comprehensive Border Reforms Kill Obama's Pro-Migration Policies https://t.co/PPBknSLxsJ via @Breitbart…	36.6002378000000022	-121.894676099999998	Monterey, Ca.    #Monterey	881	\N
834540938362048512	768204297351884800	RT @realjunsonchan: Fake News heads will be exploding for a long, great, 8 Trump years. Nice. #maga #americafirst #drsebastiangorka https:/…	40.4172871000000029	-82.9071229999999986	Ohio, USA	469	\N
834540937774845953	2596733485	RT @thinkprogress: Trump’s first month travel expenses cost taxpayers just less than what Obama spent in a year https://t.co/bb2oD8p2Os htt…	35.5174913000000032	-86.580447300000003	Tennessee, USA	330	\N
834540937573457920	19903736	RT @ajeppsson: 92 percent of Swedes h little to no confidence in Trump,a higher number than in any other nation https://t.co/EkMxxogq4X # v…	55.6049810000000022	13.0038219999999995	Malmo	882	\N
834540937044959232	3938814591	Farm groups and food processors fear worker shortages under Trump’s immigrant crackdown  https://t.co/7NuonSvDzL via @WSJ	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834540936730394624	14118768	RT @MaddowBlog: Programming Note! MSNBC special on Trump's first month tomorrow!\n10pm ET, right after TRMS. https://t.co/Mdq385dGJ1	44.8546856000000034	-93.4707860000000039	Eden Prairie, MN	883	\N
834540936411627520	16439736	@realDonaldTrump Trump's attempt to be a dictator over Americans has finally pissed people off. We will have no more of your bully tactics!	35.2270869000000033	-80.8431266999999991	Charlotte, NC	325	\N
834540936315203586	27489303	Trump news . . . . . https://t.co/1NCTzgJ9W2	30.6332617999999997	-97.6779841999999974	Georgetown, TX	884	\N
834540935434424320	70530774	Tell Disney to stand against President Trump’s anti-family policies - Sign the Petition! https://t.co/5oaQwN9VWo via @Change	39.2903847999999982	-76.6121892999999972	Baltimore, MD	885	\N
834540935224532993	816352196698644481	@johncardillo @MaxineWaters @FBI she is a racist scumbag has she called our folks under Trump	33.4483771000000019	-112.074037300000001	Phoenix, AZ	833	\N
834540934922633216	807237994348482562	RT @olgaNYC1211: Russian state media RT anchor scheduled to be a panelist at CPAC 🤦🏼‍♀️\nSeriously...\n\n#trumprussia #TrumpLeaks \n\nhttps://t.…	38.9108324999999979	-75.5276699000000065	Delaware	886	\N
834540934868062208	216830541	RT @maga_zine_usa: #Trump looted his Casinos just like he's looting the #US Treasury\n#stribpol #abc #cbs #nbc #msnbc #cnn #maddow #p2 https…	49.2827290999999974	-123.120737500000004	vancouver 	887	\N
834540934624899073	4885703096	RT @guypbenson: New Politico poll reflects sharply improved "right track" numbers &amp; decent Trump approval rating. Contrast with media/Left…	30.4213090000000008	-87.2169149000000061	Pensacola, FL	888	\N
834540934528430080	824184183052529666	RT @topspin7777: A month into his 1st term, Trump launches his 2020 presidential campaign in Florida in front of a small group of supporter…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834540934293549056	420266672	RT @3lectric5heep: BRAVE SWEDISH JOURNALISTS CONFIRM That Trump Is Dead On About Sweden [Video] https://t.co/aF18Ojm9gh @3lectric5heep	40.4172871000000029	-82.9071229999999986	Ohio, USA	469	\N
834540933555314692	20002807	RT @JudicialWatch: Right now, our borders are being used as gateways for drug cartels, terrorists, and human smugglers.\n\nhttps://t.co/rtGCw…	31.9685987999999988	-99.9018130999999983	texas	425	\N
834540933118963713	402888514	RT @kelleycalkins: "The commander of the shallow state does not have much use for reading. Or briefings. Or experts" https://t.co/CoBbtMq43…	38.9071922999999984	-77.0368706999999944	Washington, DC & New York City	889	\N
834540932930293760	827205296661606402	Give the New Travel Limits a New Name https://t.co/Zvdg4EHNk4 https://t.co/aYbMANewOh	41.0534302000000011	-73.5387340999999992	Stamford, CT	890	\N
834540932913524737	371938055	RT @w_fightback: Donald Trump is losing his war with the media https://t.co/D98dJ7qBi1	36.7782610000000005	-119.417932399999998	california usa	891	\N
834540932347338752	1861885849	RT @KGBKomrad: #FIFY Trump is Poised to Restore Protections on All Students' Rights.\n\nWhere does this crap end??? https://t.co/rL1IeC0mry	41.352999699999998	-83.1584428999999972	Terra	892	\N
834540932074786816	14642871	RT @melgillman: Apparently too many people "sabotaged" Trump's media survey by...taking it. So he scrapped the results/started over. https:…	38.2009054999999975	-84.8732834999999994	Frankfort, KY	893	\N
834540931520925696	45001481	@luke_j_obrien @bi_politics If Genghis Khan were alive to &amp;he said nice things ab Trump,Trump still let him wipe out 1/3 of the population.	37.7749294999999989	-122.419415499999999	San Francisco, Ca.	894	\N
834540931218960384	36553809	Ivanka Trump Condemns Jewish Community Center Threats https://t.co/FEjKhPIm4O #tennis #news	42.3600824999999972	-71.0588800999999961	Boston, MA USA	895	\N
834540930686414849	750212981510836224	RT @ananavarro: President. Donald. Trump. https://t.co/pnPAydkkVS	51.4072144000000009	5.54453019999999963	Erebor	896	\N
834540929826639872	428458467	RT @politico: So far, Trump has nominated fewer than three dozen of the 550 most important Senate-confirmed jobs https://t.co/KDSdnXVNOJ ht…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834540929163812864	25487241	RT @Newsweek: Eichenwald: The reasons why Trump should be very troubled by the Flynn-Russia affair https://t.co/Cf89zsBEqe https://t.co/XWp…	54.3150367000000003	-130.32081869999999	prince rupert british columbia	897	\N
834540927880400896	800429745208848384	RT @NYMag: Secretary of Education Betsy DeVos is reportedly hesitant to rescind Obama’s guidelines https://t.co/QNtb60l3qD	42.3370413000000028	-71.2092214000000041	Newton, MA	898	\N
834540926026477569	814242776623841281	Risk to Rally https://t.co/CwAL8Cky8u via the @FoxNews Android app\n Thanks to President Trump😊	41.7784371999999991	-73.7477856999999943	Dutchess County, NY	899	\N
834540926022348803	4686112616	RT @ChristieC733: #ChrisWallace you lost all credibility with me using an early photo of Trump's Inauguration crowd #s pushing a boldface l…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834540925904879620	1895272381	RT @FreeBeacon: Muslim Activist Who Called Israel’s Leader a ‘Waste of a Human Being,’ Labels Trump Admin Officials Anti-Semites https://t.…	33.473497799999997	-82.0105147999999957	Augusta, Georgia	900	\N
834540925380472832	16505825	Former Aides Explain How They Shielded Trump From Twitter Destruction https://t.co/sEbtOBKzjM	46.7295530000000028	-94.6858998000000014	Minnesota	388	\N
834540925313482752	210818207	RT @USARedOrchestra: Felix Sater funneled Russian money to Trump when US banks stopped loaning him, &amp; his business card said he was a Senio…	41.8781135999999989	-87.6297981999999962	Chicago, Il	901	\N
834540923803594752	196218058	I added a video to a @YouTube playlist https://t.co/I9JG1Qe7zs A Heated Confrontation With Trump Supporter In NYC	40.7127837000000028	-74.0059413000000035	NYC	60	\N
834540923740635137	20964739	RT @shacker56: @TurnKyBlue @goprapebuster @jasoninthehouse @TheWeek sad He wld rather destroy country than investigate their corruption or…	31.9685987999999988	-99.9018130999999983	Texas	381	\N
834540923577040897	51937284	Trump Campaign Staff Reveals Tricks To Keeping The POTUS Off Twitter (DETAILS) https://t.co/xbKv78NIh5 via @Bipartisan Report	37.0870821000000035	-76.4730121999999994	newport news	902	\N
834540923002437632	845649349	RT @conradhackett: Trump has solid Republican support (84%). What is unusual is how little support he has among Democrats (8%) https://t.co…	52.3700210000000013	5.77675420000000006	Internet. Europe, BeNeLux	903	\N
834540922998292481	2448017617	Top 10 Holdover Obama Bureaucrats President Trump Can Fire or Remove Today - Breitbart https://t.co/4M34XfOWUa via @BreitbartNews	37.0842270999999997	-94.5132810000000063	Joplin MO USA	904	\N
834540922771746816	221358452	She is now worthless to Trump. Time to check the job openings at QVC https://t.co/FvRNQ5j4zS	37.0902400000000014	-95.7128909999999991	United States	44	\N
834540922687856640	10259572	RT @katiefehren: Elon Musk says he told Trump administration if they want to get rid of subsidies for energy, should get rid for both fossi…	33.7489953999999983	-84.3879823999999985	Atlanta, Georgia	905	\N
834540922465611783	277845186	RT @activist360: Rachel Maddow: After her Kremlin paid lunch w/ Putin &amp; Flynn, why is Jill Stein silent abt the Trump-Russia scandal? https…	43.0764386999999971	-89.3762756999999937	Way up north Wisconsin 	906	\N
834540922310377473	4826141870	RT @TheTweetwit: Donald Trump said today that he'd have a replacement plan for ObamaCare by mid-March. Let's not forget what he said, "Be B…	35.0077519000000024	-97.0928770000000014	Oklahoma, USA	676	\N
834540921341423616	28971460	RT @businessinsider: The Trump family's lavish lifestyle is costing taxpayers a fortune https://t.co/vgmEvkgCcA https://t.co/WGlN8bAS51	34.9918587000000016	-90.0022957999999988	Southaven	907	\N
834540920980791296	17446493	I added a video to a @YouTube playlist https://t.co/Cv4jMdDKpF Jack Ma on Donald Trump, "I like him. US should spend money on America,	30.3321837999999993	-81.655651000000006	Jacksonville, Florida	908	\N
834540918808145921	787840575903072257	@timkaine @Pontifex @GOLD_CUP45 @Bohicamf1 No Catholic would ever support abortion you loser. #ProLife… https://t.co/AmznypWT3L	41.2033216000000024	-77.1945247000000023	SW Pennsylvania	909	\N
834540917918883840	105007589	RT @Politikath: I Ignored Trump News for a Week. Here’s What I Learned. https://t.co/SfshEEDNNZ	40.691613199999999	-112.0010501	West Valley, Utah	910	\N
834540916744531968	789131756997840896	Trump Effect https://t.co/eN9GPaaxXO via @YouTube	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834540916572434433	14585825	RT @BraddJaffy: Crowd asks Rep. Steve Womack (R-AR) to investigate Trump/Russia. \n\nWait for it... https://t.co/4siV7A0cOR	40.7127837000000028	-74.0059413000000035	NYC	60	\N
834540916471914497	37048835	RT @digiphile: @maddow Please ask the @WhiteHouse when it will disclose new visitor logs. @Obama-era data is at the @USNatArchives. https:/…	42.7238362000000009	-76.9297353999999984	fingering the lakes	911	\N
834540916320894978	4013224959	RT @dabeard: As taxpayers paid $10m for 3 #Trump weekends in Florida, a Trump hiring freeze ended pre-K, daycare for US military families i…	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834540915373006848	14136886	Money Flows Down Ballot as Donald Trump Is Abandoned by Big Donors (Even Himself) https://t.co/UaZxG6E4pY	32.9618763000000001	-96.9960925000000032	Coppell, TX 75019	912	\N
834540914865537025	3239739028	RT @GartrellLinda: WH Fingers John McCain As Media Leak;Believes He Eavesdropped on Trump’s Classified Phone\nIF It'S PROVEN- HE'S TOAST\nhtt…	28.0582984999999994	-81.8661441999999937	Central Florida	913	\N
834540914454429697	4437815832	RT @IMPL0RABLE: Trump vs press: Washington Post's new intense tagline: "Democracy Dies in Darkness" on @washingtonpost home page: https://t…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834540914261504000	59225887	RT @cjwerleman: BOOM: Russia's deputy foreign minister says his government had been in regular contact with the Trump campaign https://t.co…	40.7127837000000028	-74.0059413000000035	New York	214	\N
834540913842073600	15285457	@Impeach_D_Trump @OTOOLEFAN Because when he's on TV, there's a little "R" next to his name.	38.9351125000000025	-74.9060053000000039	Cape May NJ	914	\N
834540913036648448	4625980813	RT @2ALAW: Riot In Rinkeby Stockholm, Sweden\n\nHey #ChelseaClinton I think we caught the Bowling Green Massacre perpetrators red handed😉\n\n#C…	38.5815719000000001	-121.494399599999994	Sacramento, CA	383	\N
834540912806084608	389848388	RT @AORecovery: Join us in urging President Trump to break down barriers to addiction recovery.  Add your voice: #LetsTrumpAddiction https:…	37.0902400000000014	-95.7128909999999991	USA	56	\N
834540912235667459	65069465	RT @sidhubaba: This is a line-perfect story, start to finish https://t.co/Sfe2vqR3u8 bravo, @PamEngel12	41.8781135999999989	-87.6297981999999962	chicago, il	915	\N
834540911807885313	310495374	RT @PoliticsWolf: This chart lists the 25 congressional districts that experienced the biggest swing toward Donald Trump in 2016 https://t.…	44.9537029000000032	-93.0899577999999934	St Paul, MN	600	\N
834540910935470087	1408591765	RT @BostonGlobe: Trump Today: President Trump spent nearly 20 percent of his first 31 days in office on the golf course https://t.co/2EqOfN…	45.4654219000000026	9.18592429999999993	Milano, Lombardia	916	\N
834540910503276544	244693950	RT @nycjaneyvee: Trump 2016: "People are angry and America is a hellhole!"\nTrump 2017: "Angry people must be paid protesters!". \nPick one,…	47.6062094999999985	-122.332070799999997	Seattle,WA	917	\N
834540910096556036	223989188	@3lectric5heep @laurape00486139 SWEDISH JOURNALISTS CONFIRM That Trump Is Dead On About Sweden [Video] https://t.co/QDpAcHpzcX @MSNBC @ABC	56.1303660000000022	-106.346771000000004	Canada	257	\N
834540908238495744	796670186	Does Trump Herald the End of the West? https://t.co/xsjmnUev0D	33.7489953999999983	-84.3879823999999985	Atlanta, GA	289	\N
834540908183969792	271183127	RT @BraddJaffy: Crowd asks Rep. Steve Womack (R-AR) to investigate Trump/Russia. \n\nWait for it... https://t.co/4siV7A0cOR	43.0730517000000006	-89.4012302000000005	Madison, WI	74	\N
834541140217036800	1467292483	Immigrant Crackdown Worries Food and Restaurant Industries https://t.co/JTZKu20jAh	40.7127837000000028	-74.0059413000000035	New York, NY 	918	\N
834541139520663553	1849686307	RT @thehill: Poll: Trump approval hits new low https://t.co/SwIFWBn0uM https://t.co/jM8754mdm8	36.1699411999999967	-115.139829599999999	Las Vegas, NV	218	\N
834541137922781185	796985661958029312	RT @politico: Trump's Russia problem dogs Republicans at town halls https://t.co/pq7TeK6uiV https://t.co/FfgelhCt0t	27.1975480000000012	-80.2528257000000025	Stuart, FL	919	\N
834541137130094592	1385633960	RT @dabeard: As taxpayers paid $10m for 3 #Trump weekends in Florida, a Trump hiring freeze ended pre-K, daycare for US military families i…	39.9611755000000031	-82.9987942000000061	Columbus, OH	57	\N
834541136761016320	112532974	RT @conradhackett: Approval from the other party\nReagan 39%\nBush 46%\nClinton 30%\nBush 30%\nObama 37%\n\nTrump 8% https://t.co/cWhE1qNrjb	43.6532259999999965	-79.3831842999999964	Toronto	148	\N
834541136752496640	2723822198	RT @JohnJHarwood: Congressional Republicans now expect Trump will not propose his own health-care plan or tax plan. my @CNBC column https:/…	23.6978100000000005	120.960515000000001	Taiwan	920	\N
834541135980855296	814440339687641089	@realDonaldTrump this is the funniest thing I have read all day https://t.co/EVMMORuSEB	27.8005828000000008	-97.3963810000000052	Corpus Christi, TX	921	\N
834541135867547648	61124569	RT @ananavarro: President. Donald. Trump. https://t.co/pnPAydkkVS	37.0902400000000014	-95.7128909999999991	USA	56	\N
834541135024549888	830170123709325313	RT @katetaylornyt: Some internal tension at Success Academy over Eva Moskowitz’s support for Betsy DeVos and failure to denounce Trump’s im…	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834541132696653825	202385245	Just like Obama? Only difference is, Trump owns where he is going... https://t.co/VjY7leCyzX	37.5407245999999972	-77.4360480999999936	Richmond, VA	922	\N
834541131635490817	17156932	Donald Trump is losing his war with the media https://t.co/70KwQShnO3	29.9584426000000015	-90.0644106999999963	French Quarter, New Orleans	822	\N
834541131236913153	3224894161	RT @HeyTammyBruce: My latest: Trump-Reagan parallels: Both were mocked &amp; ridiculed, but relentless assault has unexpected consequences http…	47.3223221000000009	-122.312622200000007	Federal Way, WA	923	\N
834541131148976128	30722110	I can't believe another woman would gay shame an entire organization because her career didn't workout. Gotta be Trump fault. 😂	37.4075646000000006	-122.120541700000004	The SEA	924	\N
834541130586914816	1971099698	RT @CitizenSlant: Anne Frank Center Head to Trump Surrogate Kayleigh McEnany: ‘Have you no ethics?’ https://t.co/TXn2a7fSbQ https://t.co/SD…	38.1156878999999975	13.3612670999999992	Palermo	925	\N
834541130159095808	3422134108	RT @680NEWS: Video: Canadian tourism in the Trump era, plus @richard680news &amp; @CityAvery ask -- does pineapple belong on pizza? https://t.c…	43.6532259999999965	-79.3831842999999964	Toronto	148	\N
834541129571958784	124801008	@VP Trump hires foreign workers at Mar-a-Lago! What a great example!	30.0799404999999993	-95.4171601000000038	Spring, TX	926	\N
834541129223790592	2393288396	How Trump's campaign staffers tried to keep him off Twitter via @POLITICO for iOS https://t.co/UhKkpNSzmy https://t.co/TfYzYOOUzc	41.8781135999999989	-87.6297981999999962	Chicago	94	\N
834541128871452673	260412833	I keep laughing whenever someone tells me that Trump has excellent "managerial skills" https://t.co/CaOTTsg2A2	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
834541128711966720	213159189	RT @BraddJaffy: Crowd asks Rep. Steve Womack (R-AR) to investigate Trump/Russia. \n\nWait for it... https://t.co/4siV7A0cOR	36.7782610000000005	-119.417932399999998	California	61	\N
834541128007426048	781995667073880065	RT @luke_j_obrien: Read this entire article. All of it. Simply incredible this man is taken seriously at all, let alone on the NSC. https:/…	39.6951729999999969	-104.832262900000003	Planet Aurora	927	\N
834541126946320384	18433550	RT @luke_j_obrien: Read this entire article. All of it. Simply incredible this man is taken seriously at all, let alone on the NSC. https:/…	51.5073508999999987	-0.127758299999999991	London	420	\N
834541126665244672	171653863	Pence, in visit here, condemns anti-Jewish vandalism, defends Trump's response https://t.co/19rP1PDA77 via @stltoday	38.576701700000001	-92.1735163999999969	Jefferson City, MO	928	\N
834541126166142976	946365445	RT @TimKarr: Trump's chief digital officer escorted out of the White House after failing FBI background check https://t.co/U4GIgayjay #Shit…	37.0902400000000014	-95.7128909999999991	USA	56	\N
834541125947908097	793858	Trump-Russia: Senate Intel Committee goes after Michael Flynn and Donald Trump’s tax returns https://t.co/FZ30sMqJv8 via @PalmerReport	39.3279619999999994	-120.183253300000004	Truckee, CA	929	\N
834541125809561602	80455838	RT @nedprice: I resigned from @CIA last week. I wrote about why in the @washingtonpost:  https://t.co/HXJhRCkw3O	49.7560167999999976	-123.937411600000004	west coast BC Canada	930	\N
834541125771870209	138925333	RT @jenniferword: I support you guys! I just ordered recurring shipments of your awesome coffee &amp; nascent iodine X-2 Shield &amp; "Trump is my…	39.5630521000000002	-95.1216356000000047	Atchison, KS	931	\N
834541124626812928	783106359411609600	@skywriter35 @Justice0999 @politico Trump has already done more than 0b0z0 in 8 years, this is just the beginning.	31.9685987999999988	-99.9018130999999983	Texas	381	\N
834541124463259648	759576436680241153	The irony is, Trump did accomplish one thing — bringing the rest of the world together to oppose him.	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
834541124115009536	161418504	@IMPL0RABLE @NoraFarr bandaids.I hope Pence actually cares about what's going on,but he's not much of an improvement over Trump.	47.3223221000000009	-122.312622200000007	Federal Way, WA	923	\N
834541124035371009	2899488712	Trump Expected to Reverse Obama's Transgender Bathroom Guidelines in Schools https://t.co/fUe2nhglId via @Newsmax	33.4255104000000003	-111.940005400000004	Tempe, AZ	932	\N
834541123800547329	341854868	Or maybe I should get out and run for congress I mean shit if Donald Trump can make it in politics then why can't I	32.0835407000000004	-81.0998342000000036	Savannah, GA	933	\N
834541123758587904	1837293084	@Cigarvolante @Dirty_Water @10903 @cspanwj Mostly because of our proximity to AC and NYC, both scenes of Trump disasters through the years.	40.1303821999999997	-75.5149128000000047	Phoenixville, PA	934	\N
834541123053953025	34521009	RT @PowerPost: .@SenatorCollins says she's open to demanding #Trump's tax returns as part of #Russia probe https://t.co/n9g5MoID1N via @kar…	40.6331248999999985	-89.3985282999999953	Illinois, USA	360	\N
834541122764599301	816970914285912065	RT @womensmarch: We're excited to team up with @womensstrike on March 8th. Please read this op-ed. #WomensStrike #DayWithoutAWoman https://…	26.1224385999999988	-80.1373174000000006	Fort Lauderdale, FL	935	\N
834541122525478912	393190233	RT @Don_Vito_08: BREAKING: Majority Want Fewer Refugees, Support @POTUS Trump’s Migration Cuts #AmericaFirst #MAGA https://t.co/sM2IHp3csQ…	34.0489280999999977	-111.093731099999999	 AZ	936	\N
834541122269609984	3857661635	RT @NewDeal1964: Always nice to see! #TheResistance #ImpeachTrump #noGop #NoTrump https://t.co/0R7AFo81aJ via @politicalwire	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541122051469312	525695332	RT @RealJack: Still the most telling meme of the Election...\n\nLiberals claim Trump will destroy America... as they go out and destroy Ameri…	50.0548556000000033	-119.414788299999998	Lake Country, British Columbia	937	\N
834541122009563136	3032085306	RT @HRC: Now is the time for every single person to stand up for transgender kids under attack by the Trump Administration. #ProtectTransKi…	39.0997265000000027	-94.5785666999999961	KCMO	938	\N
834541121518829569	788111764508377089	RT @PostRoz: .@SenatorCollins says she's open to issuing subpoena for Trump's tax returns as part of Russia probe https://t.co/17MpMJgAJ7 v…	36.1626637999999971	-86.7816016000000019	Nashville, TN	618	\N
834541121426571264	856933050	RT @Naumovich: Black Trump Supporter "Black Community has been destroyed by RACIST ILLEGAL IMMIGRATION" - YouTube https://t.co/64pHcJwxZY h…	39.0457548999999986	-76.6412712000000056	Maryland, USA	234	\N
834541120487096320	343682317	RT @CNNPolitics: Mexico slams the Trump administration's immigration plan ahead of Secretary of State Rex Tillerson's visit https://t.co/4Z…	38.9071922999999984	-77.0368706999999944	washington, dc	939	\N
834541120407400448	3165497013	RT @MONEY: This chart will show you how Trump's plan will affect your taxes depending on your income https://t.co/lHbl8OZCKA https://t.co/b…	34.1140497000000025	-83.9811014	Global	940	\N
834541120080064514	58415745	Sebastian Gorka is widely disdained within national security field https://t.co/oO21PVx9VE	47.6062094999999985	-122.332070799999997	Seattle, WA	139	\N
834541119874748416	4093283477	RT @pattymo: This is an article about a 70 year-old man who is also the President of the United States https://t.co/EwZSNbvyRd https://t.co…	37.0902400000000014	-95.7128909999999991	U.S.	941	\N
834541119253803009	32625855	Sign Sen. @Jeffmerkley's petition to AG Sessions: Appoint a special prosecutor to investigate Trump: https://t.co/kx17Ph2js9 @MoveOn	34.0522342000000009	-118.243684900000005	Los Angeles	115	\N
834541119052582915	18008972	RT @NBCNews: Tell President Trump about you ... and your expectations. Just tweet @NBCNews using the hashtag #DearMrPresident https://t.co/…	41.8781135999999989	-87.6297981999999962	Chicago, IL	199	\N
834541118444417027	89985438	RT @joannamcneal: Listening to NPR and there are people calling themselves "Trump Democrats." WHAT is this?! What could they possibly see i…	35.5174913000000032	-86.580447300000003	Tennessee	390	\N
834541118314442754	17138703	as a time traveller nothing disappoints me more than seeing a No Hoverboards sign on the subway &amp; then learning they have wheels. also Trump	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
834541117853011970	604698119	RT @DavidCornDC: The real story: Trump can be easily manipulated by staffers. Very sad! And frightening! https://t.co/m93BvyOwKa	35.789285999999997	-78.6374519999999961	Peace 	942	\N
834541117399986176	703644811023118337	RT @RealAlexJones: ‘Refuse Fascism’ Organizer Says Trump is Hitler &amp; Wants to Incinerate the World - https://t.co/DBUdKRfTIV	34.0489280999999977	-111.093731099999999	Arizona, USA	943	\N
834541116175347712	45685606	RT @activist360: Rachel Maddow: After her Kremlin paid lunch w/ Putin &amp; Flynn, why is Jill Stein silent abt the Trump-Russia scandal? https…	40.4172871000000029	-82.9071229999999986	Ohio, USA	469	\N
834541115738984448	40541688	RT @lucia_fasano: New comedic piece by me! Please read and share! https://t.co/cRZQ6RDnnA	33.4483771000000019	-112.074037300000001	PHOENIX, AZ	944	\N
834541114933780480	512741248	Freeze forcing Ft Knox to suspend some on base childcare programs too. "I will do great things for our military." -… https://t.co/1dB7gV0bXS	37.7030645999999976	-85.8649407999999994	Elizabethtown, KY	945	\N
834541114891829250	29082715	What's Really Happening in Sweden that President Trump Cited, and the Politically Correct Don't Want to Admit | BCN https://t.co/XelCbgQrOU	40.8693272000000007	-74.6634640000000047	Roxbury, NJ	946	\N
834541114627592193	799769459158319105	Sign Sen. @Jeffmerkley's petition to AG Sessions: Appoint a special prosecutor to investigate Trump: https://t.co/QzMCk54ZnA @MoveOn	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834541114581331968	798867897346965504	RT @melgillman: Apparently too many people "sabotaged" Trump's media survey by...taking it. So he scrapped the results/started over. https:…	45.6318397000000004	-122.671606299999993	Vancouver, WA	947	\N
834541114266836992	757593129901928448	RT @CentristChat: Trump cabinet urges 45 to go to the Holocaust Museum. They had to remind him it wasn't "to get new ideas."	37.7749294999999989	-122.419415499999999	San Francisco, CA	24	\N
834541113901981696	733246533156655104	No, former President Obama isn't planning a coup against President Trump - ABC News https://t.co/Ozd5hKKDoE	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541113738457091	32194167	I liked a @YouTube video https://t.co/GoLkdvAVXN Academy Awards, Trump Visits Museum of African American History - Monologue	33.8573280000000025	-84.0199108000000052	Snellville, GA	948	\N
834541252943179776	844324099	RT @BraddJaffy: Jeff Sessions wants to revoke protections for transgender students. Betsy DeVos doesn't.\n\nTrump sided with Sessions. https:…	44.3148442999999972	-85.602364300000005	Michigan, USA	83	\N
834541252423122945	800778471848873987	RT @bocavista2016: NAZI GERMANY SURVIVOR\n\n#Trump isn't Hitler\n\nThose silencing FREE SPEECH are Hitler\n\nhttps://t.co/1xKej9FRl4\nhttps://t.co…	33.7489953999999983	-84.3879823999999985	Atlanta, GA	289	\N
834541252221640704	1183316539	RT @justinjm1: Michael Cohen now denies "even knowing what the plan is" that he told NYT he had delivered to Flynn https://t.co/mHrKG2lDxd	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834541252200824836	2848802507	RT @oliverdarcy: Trump nat/sec aide @SebGorka called @MichaelSSmithII last night, nearly screaming at him over his critical tweets https://…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541251735207936	329196439	@realAngeloGomez @AndreasOpinions @LisaBornfree247 @lolalolita0 omg! Ur back! The little twerp trump kiss ass! Go w… https://t.co/GC08Ucx14k	25.7616797999999996	-80.1917901999999998	Miami, Florida	571	\N
834541250564853760	100073936	@BPie7 @cxcope @realDonaldTrump I am so damn proud to be a Democrat never prouder than when Trump became the clown in the White House fat 🐷	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541250552459266	281754653	RT @DylanByers: Poll suggests Trump's aggressive efforts to discredit media have had a profound effect on Republican voters at large https:…	38.9071922999999984	-77.0368706999999944	Washington, D.C.	286	\N
834541250409795585	319954656	RT @mmpadellan: DUTY TO WARN: 26K mental professionals signed petition 2 declare trump mentally ill, to be REMOVED under 25th Amendment. #w…	40.4172871000000029	-82.9071229999999986	Ohio, USA	469	\N
834541249944121344	2651777845	RT @RonPaul: More Troops: Why Trump's ISIS Strategy Will Fail\nhttps://t.co/LgF6T3iTe6	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541249533091841	1323092520	@Rare NEW!\n EDITORIAL \n "THE TRUMP INAUGURATION, THE \n WOMAN’S MARCH, AND “GAS LIGHTING”\n February 7th, 2017 \n Seahorn Epublishing Presents:	47.6587802000000025	-117.426046600000006	Spokane, WA	952	\N
834541249365417984	52885287	RT @DineshDSouza: Trump needs a task force to visit Obama holdovers throughout the govt, notify them they're fired &amp; escort them out of the…	30.441305100000001	-91.4520542000000063	Rosedale, Louisiana	953	\N
834541249017286656	15829381	There is so much that is appalling here, I don't even know where to begin https://t.co/4LyvShevaN	41.6032207000000014	-73.0877490000000023	Connecticut, USA	365	\N
834541248941731840	808808239953346561	@VP god bless our Pres and Vice pres and their families Jesus was a carpenter. We are all about Jesus and Trump	35.5174913000000032	-86.580447300000003	Tennessee, USA	330	\N
834541247683559424	22873947	RT @AltStateDpt: Trump Russia story is increasingly sordid &amp; building. It will be interesting to see who breaks first.\n\n#KeepResisting http…	35.1543631999999988	-90.0606637000000063	*At The Farm or Traveling* 	954	\N
834541247616348160	3276212370	RT @TrumpUntamed: Trump Administration Strips Funding For Illegal Aliens, Reallocates Money to Victims of Their Crimes https://t.co/5IKj018…	36.1699411999999967	-115.139829599999999	Las Vegas, NV	218	\N
834541246500581376	996402692	Russian mafia figure Felix Sater now appears to be blackmailing Donald Trump on Putin’s behalf https://t.co/ZiWCSD0sXp via @PalmerReport	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541245787676673	87321455	Give a #Trump a fish and he'll eat for a day. Teach a #Trump to fish and he'll forget how it was done and pretend he still knows how to...	45.4830737999999997	-74.2821990000000056	rigaud, quebec	955	\N
834541245775089664	342271777	@KaivanShroff I wonder if irrefutable evidence came out that Trump was a traitor, would they still be this dumb?	37.0902400000000014	-95.7128909999999991	USA	56	\N
834541245565399041	21370988	Trump's Homeland Security deportation memos are wrong on every policy point imaginable https://t.co/5PaTSn1iuU AND DEPORT THIS AHOLE	34.0194542999999996	-118.491191200000003	Santa Monica. Ca.	956	\N
834541244869140480	205971568	RT @AlexPappas: This NYT piece on Trump's expected guidance on transgender bathrooms should be case study on real liberal media bias https:…	38.9554606000000021	-74.8510538000000025	Near the beach, New Jersey	957	\N
834541244390993921	832640838408695810	That one Clinton voter that keeps talking about Trump and Russia on a 50 minute train ride...🤦🏻‍♀️	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834541244269355008	14674094	RT @FPMediaDept: .@djrothkopf: "Trump and his supporters are threatened by what they don’t understand, and that's almost everything" https:…	32.8107723999999976	-96.8234606000000042	Lucas, Texas (north of Dallas)	958	\N
834541243019440130	135216045	RT @cjwerleman: BOOM: Russia's deputy foreign minister says his government had been in regular contact with the Trump campaign https://t.co…	39.0457548999999986	-76.6412712000000056	Maryland USA  	959	\N
834541242545418240	87732946	RT @BraddJaffy: Crowd asks Rep. Steve Womack (R-AR) to investigate Trump/Russia. \n\nWait for it... https://t.co/4siV7A0cOR	38.6315389000000025	-112.121412300000003	ÜT: 33.96803,-118.42298	960	\N
834541242163814401	3380966237	RT @politico: So far, Trump has nominated fewer than three dozen of the 550 most important Senate-confirmed jobs https://t.co/KDSdnXVNOJ ht…	-30.7501847999999995	151.448498999999998	Hiraeth 	961	\N
834541241362583552	2167131644	RT @WPJohnWagner: GOP senator says she’s open to demanding Trump’s tax returns as part of Russia probe, via @karoun https://t.co/uVNutuJoI1	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541240033091585	820030531832344577	@BraddJaffy Who in hell could pay people for almost 5 weeks to rally or protest even minimum wage Trump needs to get a grip. This is real.	40.4406248000000019	-79.9958864000000034	Pittsburgh	962	\N
834541239907278853	451147925	@thehill can you say President Pence? The trick is to look less crazy than Trump.	33.7489953999999983	-84.3879823999999985	Atlanta, GA	289	\N
834541239492046849	2536246700	Right because we should waste more money? Meanwhile the ONLY TWO voters found to have committed fraud were voting f… https://t.co/2b8EgrbwXa	40.7127837000000028	-74.0059413000000035	New York	214	\N
834541239341023232	452258139	I liked a @YouTube video https://t.co/E7PyNlQLlL Trump Attacks the Press, Gets Mocked by Sweden: A Closer Look	53.1423672000000025	-7.69205360000000038	Ireland 	963	\N
834541238414045184	308925854	'Trump's rise was enabled by deep social maladies ... a deep and advanced stage of rot'. https://t.co/OVdTiGnCZn	-25.2743980000000015	133.775136000000003	Australia	779	\N
834541237508112384	2764402421	RT @robynanne: The Devil whispered into President Trump's ear "You're not strong enough to withstand the storm " @potus whispered back, "I…	39.0119019999999992	-98.4842464999999976	Kansas, USA	964	\N
834541237441007618	15273001	RT @FAIRImmigration: Watch How All Top Democrats Took Exactly the Same Positions On Immigration As Donald Trump: https://t.co/wV8TFvCqNm vi…	36.6002378000000022	-121.894676099999998	Monterey, Ca.    #Monterey	881	\N
834541237134905344	3325910979	RT @_Carja: Op-Ed: Is this even legal? Expect a bruising battle over Trump's new deportation orders https://t.co/Y8IcbcZ37J	41.5800945000000013	-71.4774290999999948	Rhode Island	965	\N
834541237059321856	14720265	RT @byHeatherLong: Wow. Telling stats from @QuinnipiacPoll today: Repubs trust Trump to tell the truth; Dems trust the media  (h/t @DylanBy…	42.0307811999999998	-93.6319131000000056	Ames, IA	217	\N
834541236711280641	1976135388	RT @CitizenSlant: Anne Frank Center Head to Trump Surrogate Kayleigh McEnany: ‘Have you no ethics?’ https://t.co/TXn2a7fSbQ https://t.co/SD…	52.5204889999999978	-1.46538199999999996	nuneaton	966	\N
834541236564348928	3465276494	RT @PostRoz: .@SenatorCollins says she's open to issuing subpoena for Trump's tax returns as part of Russia probe https://t.co/17MpMJgAJ7 v…	47.7510740999999967	-120.740138599999995	Washington, USA	82	\N
834541236476325888	792620006	RT @sparksjls: Here's a fun article about an elderly man who is also America's president. https://t.co/8wfKgQf8Oz https://t.co/g2Ms3MfdTG	40.7127837000000028	-74.0059413000000035	New York City	145	\N
834541236434436097	16384055	RT @LOLGOP: Kind of like how Trump and Pence have been calling out antisemitism but Bannon still works for them. https://t.co/d0oTwDheP9	27.8617346999999995	-81.6911558999999983	Polk County, FL	967	\N
834541235952025600	816176155698937856	@VibeMagazine @MaxineWaters you lost the election get over it find another job America elected Donald Trump live with it😊😊😏😅🇺🇸🇺🇸🚂😅😂	40.2671940999999975	-86.1349019000000027	Indiana USA	968	\N
834541235843059717	21878767	Trump is on our side? https://t.co/PaSdCTwB4W	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834541235838783488	130023526	RT @BraddJaffy: Crowd asks Rep. Steve Womack (R-AR) to investigate Trump/Russia. \n\nWait for it... https://t.co/4siV7A0cOR	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834541234626641920	809586511331074048	RT @USARedOrchestra: Felix Sater funneled Russian money to Trump when US banks stopped loaning him, &amp; his business card said he was a Senio…	43.7844397000000001	-88.7878678000000008	Wisconsin, USA	91	\N
834541234337226753	24040951	Things You Didn’t Know About Barron Trump’s Billionaire Kid Lifestyle\n*CLICK To READ https://t.co/LAwZNHxShb	36.1626637999999971	-86.7816016000000019	Nashville, TN	618	\N
834541233221619713	129050151	RT @TimOBrien: Trump deportation plan could cost the economy $5 trillion over 10 years. Yes, $5 trillion.  https://t.co/5QxJus1f1x	43.6532259999999965	-79.3831842999999964	Toronto	148	\N
834541232378494977	623444777	Trump, Clinton &amp; other Wall St/Gov't criminals get to avoid taxes &amp; rig economy against us, yet no jail for them? https://t.co/GOFlihS9vj	44.5588028000000023	-72.5778415000000052	Vermont, USA	969	\N
834541231908732928	577616442	RT @CNNPolitics: Mexico slams the Trump administration's immigration plan ahead of Secretary of State Rex Tillerson's visit https://t.co/4Z…	35.7595730999999972	-79.0192997000000048	North Carolina	436	\N
834541231636086786	780916317192847360	@RosauraCabrera9 @vrbteach @harrisongolden Or having your birth certificate called into question, something initiated by Trump. Karmax100	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541231166349312	3219283843	Trump Family History: Donald, Fred, and the Ku Klux Klan  https://t.co/59P9B6dGzF via @HuffPostPol	40.4406248000000019	-79.9958864000000034	Pittsburgh, PA	99	\N
834541230700765185	281003459	RT @AnaMardoll: Now we have a rumored Executive Order that would hurt trans people. https://t.co/EIjc40oUHO	53.1423672000000025	-7.69205360000000038	Ireland	42	\N
834541228494557184	3420540252	@POTUS @realDonaldTrump destroying proof of ovomit orders Whistleblower Sends Urgent Letter to President Trump https://t.co/AL7bvzrtLU	36.1699411999999967	-115.139829599999999	Las Vegas, NV	218	\N
834541227773198336	857124588	RT @KarenLehner: @thehill @PressSec Trump rally included paid and "professional" ass-kissers. You placed a Craig's list ad to get people to…	47.6062094999999985	-122.332070799999997	Seattle, WA	139	\N
834541227756384257	751283435382067202	RT @olgaNYC1211: Russian state media RT anchor scheduled to be a panelist at CPAC 🤦🏼‍♀️\nSeriously...\n\n#trumprussia #TrumpLeaks \n\nhttps://t.…	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
834541227202715648	2848802507	RT @oliverdarcy: —@MichaelSSmithII told @PamEngel12 that @SebGorka threatened to bring his tweets to attention of the WH legal team https:/…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541227030740992	225733872	RT @gabriellahope_: I covered candidate Trump for 16 months. Not once did his comms team try to "place a story" in WEX for positive coverag…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541226908999680	32283017	US military will retain core strategy against Isis as Trump mulls escalation https://t.co/0G7MI6eYn2	34.9592083000000002	-116.419388999999995	Southern California	50	\N
834541226825244672	1004702144	RT @infowars: ‘Refuse Fascism’ Organizer Says Trump is Hitler &amp; Wants to Incinerate the World - https://t.co/MpzsU19TGG	37.8393331999999987	-84.2700178999999991	Kentucky, USA	88	\N
834541226237964288	51498309	RT @AltStateDpt: Trump's migrant restrictions could cost Americans $5 trillion over 10 years.\n\nThat amount could pay off 25% of our nationa…	34.0522342000000009	-118.243684900000005	LA	259	\N
834541226070274048	2479558671	RT @mkaee: Two historians weigh in on how to make sense of Donald Trump https://t.co/Za2rAJ9LVf	34.9592083000000002	-116.419388999999995	Southern California	50	\N
834541225034260480	377451388	RT @ComfortablySmug: Under Obama, we lost planets (RIP Pluto).\n\nIn Trump's first month, we've found SEVEN\n\nhttps://t.co/ue38vCiimx	37.4315733999999978	-78.6568941999999964	Virginia	276	\N
834541224690331648	723317313408274433	@jennajameson for the wrong reasons. Just remember, trump doesn't like the Jews. Yet he is your boy... I love it.	42.1014831000000029	-72.5898109999999974	Springfield, MA	970	\N
834541224107315205	775987687	RT @BraddJaffy: Jeff Sessions wants to revoke protections for transgender students. Betsy DeVos doesn't.\n\nTrump sided with Sessions. https:…	43.4510700000000014	-88.6976527000000061	Minnesota, WI	971	\N
834541223402541056	2931901110	Trump Must Show His Taxes! Corruption, Collusion. Complicit! The truth will reveal itself! @FBI @NewYorkFBI… https://t.co/EQQn40CdUt	36.6002378000000022	-121.894676099999998	Monterey, CA	972	\N
834541223243194368	2178280099	@collie_418 She also repeatedly apologized and acknowledged mistakes. I have never seen Trump apologize ever.	40.6868914000000004	-111.8754907	Millcreek, UT	973	\N
834541222932967424	1301656158	RT @GALEOorg: The time has come for Georgia's leadership to speak up against #MassDeportations.  #gapol https://t.co/ztd8hZpXZt	33.9244531000000009	-84.8413055999999983	Dallas, GA. U.S.A.	974	\N
834541222521950209	110459289	RT @politico: So far, Trump has nominated fewer than three dozen of the 550 most important Senate-confirmed jobs https://t.co/KDSdnXVNOJ ht…	34.2331373000000028	-102.410749300000006	Earth	481	\N
834541222207352833	976459728	RT @caitlinzemma: Potential @usedgov hires might be thwarted if they have conflicting views with Trump's policy positions: https://t.co/lDE…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834541222085672961	832400109535162368	RT @DunnBAD: Senior U.S. intel official predicts #Trump will go to prison for #Russian #treason\n#KremlinGate #russiagate \n https://t.co/nPj…	38.9071922999999984	-77.0368706999999944	Washington, DC	54	\N
834541369595146240	718154722	RT @dabeard: As taxpayers paid $10m for 3 #Trump weekends in Florida, a Trump hiring freeze ended pre-K, daycare for US military families i…	40.0707887000000014	-75.4268251000000021	Southeastern United States	975	\N
834541368328359936	151677792	RT @StopTrump2020: Trump in his own words - talking about his relationship with Russia and proving he is a LIAR https://t.co/b6LNhC6Tbo	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834541368005517314	4645471333	RT @Latinos4Trump16: ⚡️ “Ivanka Trump took her daughter to the Supreme Court today”\n\nhttps://t.co/Hc7V0uFhH1	30.9842976999999991	-91.9623327000000046	Louisiana 	976	\N
834541367640612865	119161370	Zeke Miller of Time states #Trump removes MLK bust from #WhiteHouse - example of idiot reporting… https://t.co/7SJnlFuzfa	37.0902400000000014	-95.7128909999999991	USA	56	\N
834541367439269890	84526257	RT @activist360: Trump is so horrendous that after only 1 month on the job, historians already say he has 'worst president ever' in the bag…	37.0902400000000014	-95.7128909999999991	USA	56	\N
834541366801727488	2335960920	President Trump approval rating falls to 38 percent: Poll - https://t.co/XUBkIeWGbd https://t.co/np7278MYTR	37.386051700000003	-122.083851100000004	Mountain View, CA	977	\N
834541366298476544	64947549	RT @OISEUofT: Will Trump’s election see more US scholars head to Canada? #OISEUofT Dean Glen Jones discusses in new op-ed  https://t.co/ccZ…	47.5615096000000008	-52.7125768000000008	St. John's, NL	978	\N
834541366000640004	813789030496272384	#TellASadStoryIn3Words President Donald Trump	32.1656221000000002	-82.9000750999999951	Georgia, USA	304	\N
834541365874851842	277762635	RT @2020fight: Daily reminder that it costs $.5 million a day to have Melania &amp; Barron Trump stay in New York.\nCurrent total post-inaugurat…	40.0581205000000011	-82.4012642	Newark OH	979	\N
834541365447053314	33048690	RT @Pamela_Moore13: .@RandPaul: "I would actually say Trump has done more in the last four weeks than we've done in the last six years." ht…	28.3180687999999989	-80.6659841999999969	Merritt Island, Fl	980	\N
834541364591337472	283027361	RT @CREWcrew: Inside President #Trump’s potential conflicts of interest (more here: https://t.co/3CKGf1WTJT) https://t.co/GKc9UW00kJ	52.3702157000000028	4.89516789999999968	Amsterdam	981	\N
834541364129980418	717553584490037250	Where is Kellyanne Conway? Trump adviser reportedly banned from TV: https://t.co/rKlYL8YSgL via @AOL	40.6084304999999972	-75.4901832999999982	Allentown, PA	490	\N
834541361806266368	614086713	RT @GrahamPenrose2: #Trump is deToqueville Reborn, Being #Sisyphus - They Made Desolation They Called It Peace: The Wheel &amp; The Line https:…	49.0952155000000019	-123.026475899999994	The Delta	982	\N
834541359839191043	28585906	RT @AnnCoulter: Trump right about Sweden after all! Riot breaks out in Stockholm suburb the Pres was ridiculed for referring to ... https:/…	50.6132407999999998	-4.38821749999999966	Tiny Town - New England	983	\N
834541359520444421	822877755444523008	RT @DavidYankovich: #CongressCanRequest Trump's taxes.\n\n@BillPascrell is leading this charge.\n\nRT if you believe Trump's taxes should be re…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541359205752832	2931672930	RT @HRC: Now is the time for every single person to stand up for transgender kids under attack by the Trump Administration. #ProtectTransKi…	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541358996131842	3065391393	RT @sahilkapur: An intriguing glimpse into the pressures Dems face. Their base's main fear is they won't do enough to oppose Trump. https:/…	42.7369792000000004	-84.4838653999999991	East Lansing, MI	984	\N
834541358291550208	243963524	RT @kylegriffin1: Oof—majorities of ppl think Trump:\n1. Is dishonest\n2. Has bad leadership skills\n3. Doesn't care abt average Americans\n4.…	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
834541357603704833	781749925	The Intel Community and the Slow Death of Trump's Presidency | The Resis... https://t.co/fL5Yy6faah via @YouTube	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834541357247102981	2788902852	RT @StopTrump2020: Trump in his own words - talking about his relationship with Russia and proving he is a LIAR https://t.co/b6LNhC6Tbo	37.0902400000000014	-95.7128909999999991	United States	44	\N
834541357167374337	484341564	RT @HRC: Now is the time for every single person to stand up for transgender kids under attack by the Trump Administration. #ProtectTransKi…	33.8958492000000007	-118.220071200000007	Compton, CA	985	\N
834541357096173569	17408645	RT @Amy_Siskind: Stay on this story:  Trump and his treason.  #PutinPuppet https://t.co/92QfQZwPFF	40.0583237999999966	-74.4056611999999973	The Garden State	986	\N
834541356756242432	49262835	RT @MikeOwensArt: #Trump Attacks "So-Called Angry" Americans Worried About Losing Their Health Insurance https://t.co/NO7l2lGHsX https://t.…	43.8041333999999978	-120.554201199999994	Oregon	477	\N
834541356114706432	2318516194	RT @MiamiHerald: Trump expected to revoke Obama transgender bathroom directive https://t.co/LSZiF54uDn https://t.co/7HlER4e3Lq	27.6648274000000001	-81.5157535000000024	Florida, USA	89	\N
834541355577724928	107281820	RT @DylanByers: Poll suggests Trump's aggressive efforts to discredit media have had a profound effect on Republican voters at large https:…	36.7782610000000005	-119.417932399999998	California	61	\N
834541354583748608	24626122	RT @immigrant4trump: Trump Hollywood Star Vandal Ordered To Pay $4,400 Fine, 3 Years of Probation, 20 Days of Road Maintenance Work #Maga h…	37.4315733999999978	-78.6568941999999964	Virginia, USA	263	\N
834541354516619265	879154249	RT @Pamela_Moore13: .@RandPaul: "I would actually say Trump has done more in the last four weeks than we've done in the last six years." ht…	40.2671940999999975	-86.1349019000000027	Indiana	987	\N
834541353807798272	24783838	RT @washingtonpost: GOP senator says she’s open to demanding Trump’s tax returns as part of Russia probe https://t.co/1b4COKdVAs	40.6084304999999972	-75.4901832999999982	Allentown, PA	490	\N
834541353455468545	2991043915	"Reporter" @AprilDRyan joins the ranks of the #FakeNews media with her lie about Trump. https://t.co/ZFybhTWFG9	37.0902400000000014	-95.7128909999999991	USA	56	\N
834541352973131777	306047638	RT @melgillman: Apparently too many people "sabotaged" Trump's media survey by...taking it. So he scrapped the results/started over. https:…	40.4614663999999991	-89.4008965999999958	Kentuckiana	988	\N
834541352918667269	314045611	RT @washingtonpost: "Poll: Donald Trump is losing his war with the media" https://t.co/4IslDQV36Y	37.4315733999999978	-78.6568941999999964	Virginia, USA	263	\N
834541352117530624	753994880	RT @politico: So far, Trump has nominated fewer than three dozen of the 550 most important Senate-confirmed jobs https://t.co/KDSdnXVNOJ ht…	40.7127837000000028	-74.0059413000000035	New York, NY	73	\N
834541352067223554	613796064	RT @RealNaturalNews: Eugenicist Bill Gates outraged over Trump’s Planned Parenthood cuts https://t.co/eMoWkjIDn7  #abortion #prolife #nwo h…	46.7295530000000028	-94.6858998000000014	Minnesota	388	\N
834541351651905538	757596295137755136	RT @digby56: I get not trusting media. But trusting Trump to tell the truth means 78% of GOP are too daft to be allowed to operate heavy ma…	49.8152729999999977	6.12958300000000023	luxembourg	989	\N
834541351433809921	36766620	RT @jamiedupree: Pentagon says child care cuts at two Army bases due to hiring freeze may have been unnecessary https://t.co/8Fr1DWfRUM	32.4609763999999998	-84.9877094	Columbus Ga	990	\N
834541350926290949	102807848	I only wish they'd let me donate in someone's honor. But it'd be hard to choose between DeVos, Trump, &amp; that partic… https://t.co/0bCHoqxycb	40.6781784000000002	-73.9441578999999933	Brooklyn, NY	239	\N
834541350666326017	1516602132	RT @Coco_Wms: Muslims repaired losses, whereas Trump &amp; GOP wouldn't. Trump's tepid response to growing anti-Semitic acts wasn't convincing.…	29.7604267	-95.3698028000000022	houston tx	991	\N
834541349802242048	903090192	Quinnipiac poll: Trump approval hits new low https://t.co/TzuRkZA0WV	27.6648274000000001	-81.5157535000000024	South Florida	992	\N
834541349512818688	812155433959964672	RT @NewssTrump: Black Lives Matter Declares WAR On White America and Death To President Trump; Are They Hate Group? https://t.co/3JJpDuKSRl…	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834541348896198656	823621879910973442	RT @alfranken: It doesn't end with Flynn. Call for an investigation into the Trump Admin's connection with Russia. https://t.co/fyKwhA9eZ9	36.7782610000000005	-119.417932399999998	California, USA	71	\N
834541348208275456	831601271429689344	@USAFCENT @KazmierskiR @usairforce @CENTCOM @DeptofDefense Folks this is what a Trump win looks like.Thanks Trump for making us safe #MAGA	37.9642528999999982	-91.8318333999999936	Missouri	993	\N
834541347839283200	2965284615	Trump's Russia problem dogs Republicans at town halls https://t.co/oq5ujv2dzu by #Ronraj777 via @c0nvey https://t.co/gao3oEq5p5	29.1383164999999984	-80.995610499999998	Port Orange, FL	994	\N
834541347516346373	377746000	RT @dabeard: As taxpayers paid $10m for 3 #Trump weekends in Florida, a Trump hiring freeze ended pre-K, daycare for US military families i…	40.6789836000000022	-74.3314677000000046	NJ // MO	995	\N
834541347407171585	14638113	RT @igorvolsky: Trump’s crackdown on undocumented immigrants will cost the economy as much as $5 trillion over 10yrs https://t.co/CrpzNkrg6…	34.0522342000000009	-118.243684900000005	Los Angeles, CA	176	\N
834541347260530693	797252185109254144	Met Director Fears Elimination Of NEA Marks 'New Assault' On Art https://t.co/oEWKugRPmL https://t.co/KJ7RcTMWHU	40.0656291000000024	-79.8917138999999992	California, PA	738	\N
834541347050713088	54773913	RT @RealAlexJones: ‘Refuse Fascism’ Organizer Says Trump is Hitler &amp; Wants to Incinerate the World - https://t.co/DBUdKRfTIV	33.3945681000000008	-104.522928100000001	3rd Rock from the Sun	627	\N
834541346819944448	767567215638052864	Met Director Fears Elimination Of NEA Marks 'New Assault' On Art https://t.co/g6JzdhNSe0 https://t.co/fTbKX9thER	40.7127837000000028	-74.0059413000000035	Nueva York, USA	81	\N
834541346765549570	558293436	RT @GabrielDanRadu: Most Alt Right is 100% Anti Semitic and Racist. Trump said he is "the least". That means he is only around 90% Anti Sem…	44.3148442999999972	-85.602364300000005	Michigan	124	\N
834541346681544704	97815317	The best take-down of racist/xenophobic Trump advisor Stephen Miller you'll read and a high school student no less:\nhttps://t.co/DWBq6IZGj7	40.7127837000000028	-74.0059413000000035	New York, USA	84	\N
834541346564227072	1166669730	Troubling-to say the least\nTrump's national security aide, is widely disdained within his own field https://t.co/fkh62b79P7 via @bi_politics	39.2903847999999982	-76.6121892999999972	Baltimore	996	\N
834541346429874176	766499969696169984	Met Director Fears Elimination Of NEA Marks 'New Assault' On Art https://t.co/JjmW0IfPFJ https://t.co/nNU7Cs8ESt	31.9685987999999988	-99.9018130999999983	Texas, USA	225	\N
834541345440145408	19590168	RT @CNNPolitics: Mexico slams the Trump administration's immigration plan ahead of Secretary of State Rex Tillerson's visit https://t.co/4Z…	40.6603544000000028	-82.5521946000000071	Somewhere in Ohio	997	\N
834541345226240003	728981660566433792	Spicer said our relationship with Mexico is "phenomenal". Yes, enthusiastic support for Trump in Mexico City is har… https://t.co/lhq2DN1pVt	43.9653889000000007	-70.8226540999999941	New England, USA	998	\N
834541344932638720	88307326	RT @shannoncoulter: .@BedBathBeyond I spotted this photo on Facebook today. Does it concern you that people have strong associations betwee…	40.4406248000000019	-79.9958864000000034	Pittsburgh PA	999	\N
834541344890589184	797243715320500226	Met Director Fears Elimination Of NEA Marks 'New Assault' On Art https://t.co/4mmbRtL3Xv https://t.co/ww0o6W9fNx	35.0077519000000024	-97.0928770000000014	Oklahoma, USA	676	\N
834541344806809601	1975191656	RT @GrahamPenrose2: #Trump is deToqueville Reborn, Being #Sisyphus - They Made Desolation They Called It Peace: The Wheel &amp; The Line https:…	35.7118769	139.796697099999989	Asakusa, Tokyo	1000	\N
834541343087140870	44512287	This can't be real.  It has to be staged right?  My heavens. https://t.co/NoUpIPZ2rf	42.3714252999999985	-83.4702132000000034	Plymouth, MI	1001	\N
834541342671912961	709203675332386816	RT @IMPL0RABLE: #TheResistance #TrumpLies\n\n#Trump In the last 100 days has made 133 FALSE/FAKE claims, they've been documented here: https:…	28.5383354999999987	-81.3792365000000046	Orlando, FL	130	\N
834541342218997760	898510778	RT @StockMonsterUSA: 🚨Democracy Dies In Darkness🚨Doug Schoen says as a Jew &amp; a Democrat he's Disgusted and Outraged with His Party !#wednes…	35.7595730999999972	-79.0192997000000048	NC	352	\N
834541341669523457	62128121	Trump hits new record low in poll, seen as weak and 'not honest' https://t.co/aYn79xoLGY	29.7604267	-95.3698028000000022	Houston,TX	1002	\N
834541341602365440	33048690	RT @MichaelDelauzon: CIA Agent: Trump has just figured out that there is in fact a massive DC pedophilia ring. And he is pissed off. Only h…	28.3180687999999989	-80.6659841999999969	Merritt Island, Fl	980	\N
834541340511846402	25605222	Could Trump’s Attacks On Judges Give The Religious Right Their Biggest Payoff? | Right Wing Watch https://t.co/S8qnQasK8N	42.5847424999999973	-87.8211854000000045	Kenosha, Wi	1003	\N
834541339492618240	604698119	RT @ChrisMegerian: I'm pretty sure he called it a "shutdown of Muslims" at the very beginning https://t.co/ZxJVsLeaFR https://t.co/bZsHjduj…	35.789285999999997	-78.6374519999999961	Peace 	942	\N
834541339370991618	314909425	RT @politico: Trump's Russia problem dogs Republicans at town halls https://t.co/pq7TeK6uiV https://t.co/FfgelhCt0t	40.6781784000000002	-73.9441578999999933	Brooklyn	611	\N
834541338976780288	848251890	will trump's tweets doom the majority of his cabinet and spokespeople? it's hard to have credibility when your bos… https://t.co/pchHRt6F5F	34.420830500000001	-119.698190100000005	Santa Barbara, CA	35	\N
834541338821423104	1066746841	Trump’s Pick For EU Ambassador Sides With Turkey On Imam’s Extradition [VIDEO] https://t.co/mKmS6Rr8Ey 🇺🇸… https://t.co/npSCjgpCyi	37.0902400000000014	-95.7128909999999991	Estados Unidos	140	\N
\.


--
-- Name: tweets_tweet_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('tweets_tweet_id_seq', 1, false);


--
-- Name: cachedgeocodes_pkey; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY cachedgeocodes
    ADD CONSTRAINT cachedgeocodes_pkey PRIMARY KEY (city_id);


--
-- Name: tweets_pkey; Type: CONSTRAINT; Schema: public; Owner: user
--

ALTER TABLE ONLY tweets
    ADD CONSTRAINT tweets_pkey PRIMARY KEY (tweet_id);


--
-- Name: public; Type: ACL; Schema: -; Owner: postgres
--

REVOKE ALL ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM postgres;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO PUBLIC;


--
-- PostgreSQL database dump complete
--

