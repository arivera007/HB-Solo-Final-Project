import os
import tweepy
import Model
from sqlalchemy import exc


RECORDS_SKIPPED = 0      # Best way to put this variable, global for now ??
DUPLICATED_RECORDS = 0

Model.db.app = Model.app  # why do I need this ?
# from server import app


##########################################################
# Works with Plan twitter, but not with Tweepy
# api = tweepy.API(
#     consumer_key=os.environ["TWITTER_CONSUMER_KEY"],
#     consumer_secret=os.environ["TWITTER_CONSUMER_SECRET"],
#     access_token_key=os.environ["TWITTER_ACCESS_TOKEN_KEY"],
#     access_token_secret=os.environ["TWITTER_ACCESS_TOKEN_SECRET"])

##########################################################

## Connect to Twitter through 3rd party lib Tweepy
auth = tweepy.OAuthHandler(os.environ["TWITTER_CONSUMER_KEY"],
                           os.environ["TWITTER_CONSUMER_SECRET"])
auth.set_access_token(os.environ["TWITTER_ACCESS_TOKEN_KEY"],
                      os.environ["TWITTER_ACCESS_TOKEN_SECRET"])
api = tweepy.API(auth)


def get_tweets():
    """ Read Tweets and add them to data base """

# #############  Helpers    ################
# ## dumpling to a file
# with open('sample_tweets.tx', 'a+') as f:
#     f.write(str(public_tweets))
############################################
# ## Creating tweets by hand
#     class user:
#         id = 1
#
#     class TWEET_TEST:
#         coordinates = {'coordinates': (37.7749300, -122.4194200)}
#         id = 2
#         author = user()
#         text = "This is a test"
#         city_id = 1
#     test3 = TWEET_TEST()
#     test3.id = 3
#     near_tweets = [TWEET_TEST(), test3]

    near_tweets = api.search(q='trump', lang='en',
                             geocode="37.7749300,-122.4194200,1km")
    tweets_read = len(near_tweets)
    for tweet in near_tweets:
        # Model.insertTweet(tweet.id, tweet.author.id, tweet.text,
        #                   tweet.author.location, tweet.coordinates)
        city_id = None
        if tweet.coordinates is None:
            # lon, lat = googleMapApiOrCached(city)
            lon, lat = (37.7749300, -122.4194200)
            city_id = 1
            # RECORDSSKIPPED += 1
        else:
            lon = tweet.coordinates['coordinates'][1]
            lat = tweet.coordinates['coordinates'][0]

        tweet_data = Model.Tweet(tweet_id=tweet.id, user_id=tweet.author.id,
                                 text=tweet.text, city_id=city_id,
                                 lat=lat, lon=lon)
        global RECORDS_SKIPPED, DUPLICATED_RECORDS  # ?? How  to manage this non globally?
        try:
            Model.db.session.add(tweet_data)
            Model.db.session.commit()
        except exc.IntegrityError:
            DUPLICATED_RECORDS += 1
            Model.db.session.rollback()
        except exc.SQLAlchemyError as e:        # How do I get the description
            RECORDS_SKIPPED += 1
            print "Record Skkiped %s, out of %s." % (str(RECORDS_SKIPPED), str(tweets_read))

        print "Records duplicated: %s, Record Skkiped %s, out of %s." % (
            str(DUPLICATED_RECORDS), str(RECORDS_SKIPPED), str(tweets_read))


#-------------------------------------------------------------------#

if __name__ == '__main__':
    Model.connect_to_db(Model.app)
    Model.db.create_all()

    get_tweets()
