from flask_sqlalchemy import SQL_Alchemy





# Here's where we create the idea of our database. We're getting this through
# the Flask-SQLAlchemy library. On db, we can find the `session`
# object, where we do most of our interactions (like committing, etc.)

db = SQLAlchemy()

class Tweet(db.Model):
    """ Tweets for an specific term"""
    # or should I just make it for anytime anywhere?

    __tablename__ = "tweets"

    tweet_id = db.Column(db.Integer, primary_key=True)
    user_id = db.Column(db.Integer, nullable=True)
    text = db.Column(db.String(150), nullable=False)
    city = db.Column(db.String(50), nullable=True)
    state = db.Column(db.String(50), nullable=True)
    coordinates = db.Column(db.String(50), nullable=True)
    sentiment = db.Column(db.Integer, nullable=True)


    def __repr__(self):
        """ Returns infor about the tweet """

        return "< TweetID: %s, Text: %s, City: %s >" % (self.tweet_id, self.text, self.city)


# *** Different class? *****

def insertTweet(tweet_id, user_id, text, city, coordinates):
    """ Inserts tweets in DB """

    tweet_data = Tweet(tweet_id=tweet_id, user_id=user_id, text=text, city=city, coordinates=coordinates)
    db.session.add(tweet_data)
    db.session.commit()



    ##############################################################################
# Helper functions

def init_app():
    # So that we can use Flask-SQLAlchemy, we'll make a Flask app.
    from flask import Flask
    app = Flask(__name__)

    connect_to_db(app)
    print "Connected to DB."


def connect_to_db(app):
    """Connect the database to our Flask app."""

    # Configure to use our database.
    app.config['SQLALCHEMY_DATABASE_URI'] = 'postgres:///cars'
    app.config['SQLALCHEMY_ECHO'] = False
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
    db.app = app
    db.init_app(app)


if __name__ == "__main__":
    # As a convenience, if we run this module interactively, it will leave
    # you in a state of being able to work with the database directly.

    # So that we can use Flask-SQLAlchemy, we'll make a Flask app.
    from flask import Flask

    app = Flask(__name__)

    connect_to_db(app)
    print "Connected to DB."