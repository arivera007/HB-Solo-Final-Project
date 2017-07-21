# Tweet America
Maps sentiment of the tweets in USA.
Hackbright Final Project. 100% my code.

## Contents
* [Technologies](#technologies)
* [Features](#features)
* [Upcoming](#upcoming)
* [Database Model](#database-model)

## <a name="technologies"></a>Technologies
<b>Backend:</b> Python, Flask, PostgreSQL, SQLAlchemy<br/>
<b>Frontend:</b> JavaScript, jQuery, AJAX, Jinja2, Bootstrap, HTML5, CSS3<br/>
<b>APIs:</b> Twitter RestAPI, Google Natural Language, Google Maps, Google Charts<br/>

## <a name="features"></a>Features
#### Summary
  Tweet America is a mostly backend project. It is an app that shows Tweets with their location and Sentiment. Currently only covers the US. I wrote the server using Python and Flask, and SQLALchemy to talk to the DB. 

#### Pride
   My biggest challenge was the calculation of the geolocation of the tweets. To solve this I built a <a href="https://github.com/arivera007/HB-Solo-Final-Project/blob/master/static/db_setup.sql">Store Procedure</a> in the database written in Python, that calls the API of Google Maps Geocode. Also, within this <a href="https://github.com/arivera007/HB-Solo-Final-Project/blob/master/static/db_setup.sql">Store Procedure</a>, I implemented a cache that continually saves the results from Google Maps to minimize the number of future calls.

#### Flow
  We start by inputting the Search Term that we want to learn about. With this term, using an AJAX call I send the request. My server in turn goes and hit Twitter’s Search API  to get the most recent tweets located in the US. 
Each tweet then goes to Google’s Natural Language API to get its prediction about the feeling or sentiment about the content of the tweet. If the tweet contains feel good words it gets tag as positive.  After that each tweet is saved in a Postgres SQL database. 
Finally the server replies back with all the processed tweets and the  information gets displayed in a map with their corresponding location and sentiment.

#### Visualization
  I divided the results in three different views for better perception of the data. Using Jinja, BootStrap, JavaScript, and Google Maps API, this map shows more clearly the density of tweets in each location. This second map, shows the location of the tweet and its sentiment. Red is negative, Blues is positive and Yellow is Neutral. 
This last section, made with Google Charts, is a view of the leaning of the sentiment as a whole regardless of the location.
   
## <a name="upcoming"></a>Upcoming
Currently, I am working on the addition of a Twitter Streaming API requests to get dynamic views of the data.


## <a name="database-model"></a>Database Model
![alt text](screenshots/database.png "database model")
<img src="maps.png"/>

