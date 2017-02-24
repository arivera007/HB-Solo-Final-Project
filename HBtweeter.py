import os
import tweepy
import Model
from sqlalchemy import exc
import pdb


RECORDS_SKIPPED = 0      # Best way to put this variable, global for now ??
DUPLICATED_RECORDS = 0

Model.db.app = Model.app  # why do I need this ?
# from server import app    # and not this.


## Connect to Twitter through 3rd party lib Tweepy
auth = tweepy.OAuthHandler(os.environ["TWITTER_CONSUMER_KEY"],
                           os.environ["TWITTER_CONSUMER_SECRET"])
auth.set_access_token(os.environ["TWITTER_ACCESS_TOKEN_KEY"],
                      os.environ["TWITTER_ACCESS_TOKEN_SECRET"])
api = tweepy.API(auth)

# near_tweets = api.search(q='trump', lang='en', count=1,
                         # geocode="37.7749300,-122.4194200,1km")


def get_tweets():
    """ Read Tweets and add them to database """

    get_search_tweets('Trump', 450)


def get_search_tweets(search_term, tweet_count):
    """ Read Tweets from based on a SEARCH term and add them to database. """

    # ?? Move them to non global space and log them somewhere.
    global RECORDS_SKIPPED, DUPLICATED_RECORDS

    # Calling twitter at center of US with a radisu wide enough to cover the whole country.
    near_tweets = api.search(q=search_term, lang='en', count=tweet_count,
                             geocode="39.8,-95.583068847656,2500km")

    # Starting counters
    DUPLICATED_RECORDS = 0
    RECORDS_SKIPPED = 0
    RECORDS_COMMITED = 0
    tweets_read = len(near_tweets)
    tweet_with_location = True

    # Constructing Tweets
    for tweet in near_tweets:
        city_id = None
        if tweet.coordinates is None:
            if tweet.author.location:
                print tweet.author.location
                city_id, lat, lon = getGeoCode(tweet.author.location)
                if city_id == 0:
                    tweet_with_location = False

            else:
                tweet_with_location = False
        else:   # Best case scenario, when the tweet came with geo info.
            lon = tweet.coordinates['coordinates'][1]
            lat = tweet.coordinates['coordinates'][0]

        if tweet_with_location:
            tweet_data = Model.Tweet(tweet_id=tweet.id,
                                     user_id=tweet.author.id,
                                     text=tweet.text,
                                     author_location=tweet.author.location,
                                     city_id=city_id, lat=lat, lon=lon)
            try:
                Model.db.session.add(tweet_data)
                Model.db.session.commit()
                RECORDS_COMMITED += 1
            except exc.IntegrityError:
                DUPLICATED_RECORDS += 1
                Model.db.session.rollback()
            except exc.SQLAlchemyError as e:        # How do I get the description
                RECORDS_SKIPPED += 1

            print city_id, lat, lon
        else:
            RECORDS_SKIPPED += 1

        tweet_with_location = True          # Resetting this flag for the next tweet.

    print "Records duplicated: %s, Record Skipped %s, Records Committed: %s,    Out of %s." % (
        str(DUPLICATED_RECORDS), str(RECORDS_SKIPPED), str(RECORDS_COMMITED), str(tweets_read))
    return tweets_read


def getGeoCode(location):
    """ Gets the geocode from a location. """
    # recds = Model.db.session.execute("getgeocode @locations:location",params={'location':'San Francisco, CA'})
    f = Model.db.text('select getgeocode(:locations)')
    recds = Model.db.session.execute(f, {'locations': location}).fetchone()
    recd = recds['getgeocode']  # Why does it return text ?
    geocode = recd[1:-1].split(',')
    try:
        city_id = int(geocode[0])
        lat = float(geocode[1])
        lon = float(geocode[2])
    except:   # Interested in TypeError, bur really anytype or error will cause dismissal of tweet.
        city_id = lat = lon = 0

    return city_id, lat, lon


#-------------------------------------------------------------------#

if __name__ == '__main__':
    Model.connect_to_db(Model.app)

    get_tweets()
