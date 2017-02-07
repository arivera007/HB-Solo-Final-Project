import tweepy
import Model
# import json
# from pprint import pprint

consumer_key = 'FRbcmdDq9HzXEtRpMJz3w'
consumer_secret = 'L72oDTKHbUMbVqFNnRFWQSnTAXkYZVmpqQzZZvksy3g'
access_token = '17634766-PeFRd14ux5vAIOeufnKgOmDF0zqMA5iLJesxuk4zQ'
access_token_secret = 'YLiDJ0dfSv1zAszWoPCTT5ja458O8bhFwLlyIkKUpw'

auth = tweepy.OAuthHandler(consumer_key, consumer_secret)
auth.set_access_token(access_token, access_token_secret)

api = tweepy.API(auth)


# Helpers
# with open('sample_tweets.tx', 'a+') as f:
#     f.write(str(public_tweets))


near_tweets = api.search(q='trump', lang='en', geocode="37.7749300,-122.4194200,1km")
for tweet in near_tweets:
    Model.insertTweet(tweet.id, tweet.author.id, tweet.text, tweet.author.location, tweet.coordinates)
