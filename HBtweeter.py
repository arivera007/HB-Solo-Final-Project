import os
import tweepy
import Model
from sqlalchemy import exc


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
    """ Read Tweets and add them to data base """


    global RECORDS_SKIPPED, DUPLICATED_RECORDS  # ?? How  to manage this non globally?

    near_tweets = api.search(q='trump', lang='en', count=100,
                             geocode="37.7749300,-122.4194200,1km")
    tweets_read = len(near_tweets)
    for tweet in near_tweets:
        city_id = None
        if tweet.coordinates is None:
            # if tweet.author.location:
            #     print tweet.author.location
            #     lon, lat, city_id = googleMapApiOrCached(tweet.author.location)
            lon, lat = (37.7749300, -122.4194200)
            city_id = 1
            # else:
                # RECORDS_SKIPPED += 1    # Add different variable ???????

        else:
            lon = tweet.coordinates['coordinates'][1]
            lat = tweet.coordinates['coordinates'][0]

        tweet_data = Model.Tweet(tweet_id=tweet.id,
                                 user_id=tweet.author.id,
                                 text=tweet.text,
                                 author_location=tweet.author.location,
                                 city_id=city_id, lat=lat, lon=lon)
        try:
            Model.db.session.add(tweet_data)
            Model.db.session.commit()
        except exc.IntegrityError:
            DUPLICATED_RECORDS += 1
            Model.db.session.rollback()
        except exc.SQLAlchemyError as e:        # How do I get the description
            RECORDS_SKIPPED += 1

    print "Records duplicated: %s, Record Skkiped %s, out of %s." % (
        str(DUPLICATED_RECORDS), str(RECORDS_SKIPPED), str(tweets_read))


def googleMapApiOrCached(location):
    my_location = [x.strip() for x in location.split(',')]
    city = my_location[0]   # What if there are more than 1 spaces in between words
    state = my_location[1]
    geocode = Model.Geocode.query.filter(Model.Geocode.city.like(city),
                                         Model.Geocode.state.like(state)).first()
    if geocode:
        city_id = geocode.city_id
        lon = geocode.lon
        lat = geocode.lat
    else:
        # go to googlemapapi ang get lat lon   # TODO
        # and update caching table
        # and get city_id
        city_id = 2
        lon = 122.4116
        lat = 37.7887

    return lon, lat, city_id

#-------------------------------------------------------------------#

if __name__ == '__main__':
    Model.connect_to_db(Model.app)
    Model.db.create_all()

    get_tweets()
