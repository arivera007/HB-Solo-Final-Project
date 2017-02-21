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
        country = [x["long_name"] for x in jsonresponse['results'][0]["address_components"] if x["types"][0] == "country"]
        # Maybe add if country = USA here, but I think this should be handled by an calling object.
        plpy.notice(len(country)) 
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
\.


--
-- Name: cachedgeocodes_city_id_seq; Type: SEQUENCE SET; Schema: public; Owner: user
--

SELECT pg_catalog.setval('cachedgeocodes_city_id_seq', 303, true);


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
829819402635849729	17113333	RT @lenagroeger: Why am I not surprised. \n\nhttps://t.co/XC3tGWpZVn https://t.co/nAhQNfgw2I	-122.419420000000002	37.7749299999999977		1	\N
829819401595543552	2210067337	RT @SenSanders: Today’s news that Trump denounced an historic U.S.-Russia arms treaty in a call with Putin is extremely troubling. https://…	-122.419420000000002	37.7749299999999977		1	\N
829819400588926976	1537715586	RT @sdonnan: This gets right to the point... https://t.co/V0nhdtJBe5	-122.419420000000002	37.7749299999999977		1	\N
829819400379367425	187351126	RT @2ALAW: Islam Chants Death To America\n\nGeneral Mattis..Hold My Beer🍺\n\n#Trump 🇺🇸 https://t.co/jz8bz6auPA	-122.419420000000002	37.7749299999999977		1	\N
829820746524454912	213892275	RT @bi_politics: One of the largest middlemen in pharma shared a video showing why it should remain secretive https://t.co/Um9XsGVswZ https…	-122.419420000000002	37.7749299999999977		1	\N
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
829858453216751616	798654799382122496	RT @LuxuriousAdven: Appeals court deals yet another blow to Donald Trump's travel ban targeting Muslims https://t.co/X03Fuu5LZs via @HuffPo…	-122.419420000000002	37.7749299999999977		1	\N
829858453027893248	796451054883717120	RT @JoyAnnReid: .@CNN is reporting that at least one of the appeals court judges hearing Trump's travel ban case has needed extra security…	-122.419420000000002	37.7749299999999977		1	\N
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

