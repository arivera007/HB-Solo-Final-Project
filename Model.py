from flask_sqlalchemy import SQLAlchemy

# Here's where we create the idea of our database. We're getting this through
# the Flask-SQLAlchemy library. On db, we can find the `session`
# object, where we do most of our interactions (like committing, etc.)
db = SQLAlchemy()

from flask import Flask

app = Flask(__name__)


class Tweet(db.Model):

    """ Tweets for an specific term"""

    # or should I just make it for anytime anywhere??

    __tablename__ = "tweets"

    tweet_id = db.Column(db.BIGINT, primary_key=True)
    user_id = db.Column(db.BIGINT, nullable=True)
    text = db.Column(db.String(150), nullable=False)
    lat = db.Column(db.Float)
    lon = db.Column(db.Float)
    author_location = db.Column(db.String(50))  # What is the max in twitter ??
    city_id = db.Column(db.Integer, nullable=True)
    sentiment = db.Column(db.Integer, nullable=True)

    def __repr__(self):
        """ Returns infor about the tweet """

        return "< TweetID: %s, Text: %s, City: %s >" % (self.tweet_id, self.text, self.city)


class Geocode(db.Model):
    """ Tweets for an specific term"""

    __tablename__ = "cachedgeocodes"

    city_id = db.Column(db.Integer, primary_key=True)
    city = db.Column(db.String(50), nullable=False)
    state = db.Column(db.String(50), nullable=False)
    lat = db.Column(db.Float, nullable=False)
    lon = db.Column(db.Float, nullable=False)

    def __repr__(self):
        """ Returns infor about the tweet """

        return "< TweetID: %s, Text: %s, City: %s >" % (self.tweet_id, self.text, self.city)


##############################################################################
# Helper functions

def init_app():
    # So that we can use Flask-SQLAlchemy, we'll make a Flask app.
    from flask import Flask
    app = Flask(__name__)

    connect_to_db(app)
    print "Connected to DB......"


def connect_to_db(app):
    """Connect the database to our Flask app."""

    # Configure to use our database.
    app.config['SQLALCHEMY_DATABASE_URI'] = 'postgres:///tweets'
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
