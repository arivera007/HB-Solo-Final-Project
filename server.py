"""Creating Google Map with tweeter information."""

from jinja2 import StrictUndefined
from flask import Flask, render_template, request     # , jsonify
from flask_debugtoolbar import DebugToolbarExtension

# from model import connect_to_db, db
import Model
import HBtweeter

app = Flask(__name__)
app.secret_key = "queonda"
app.jinja_env.undefined = StrictUndefined

#---------------------------------------------------------------------#


@app.route('/')
def index():
    """Show homepage."""

    return render_template("home.html")


@app.route('/calculate-tweets')
def calculate_tweets():
    """Hits Twitter to get location and sentiment."""
    term = request.args.get("term")
    qty = request.args.get("qty")
    HBtweeter.get_search_tweets(term, qty)
    return sentiment_map()


@app.route('/map')
def map():
    """Show map with tweets' amount."""

    geo_tweets = read_db()

    return render_template("map.html", geo_tweets=geo_tweets)


@app.route('/sentiment-map')
def sentiment_map():
    """Show map with tweets' sentiment."""

    geo_tweets = read_db_sentiment()

    return render_template("sentiment_map.html", geo_tweets=geo_tweets)


@app.route('/sentiment-plot')
def sentiment_plot():
    """Show map with tweets' sentiment."""
    # Should this data manipulation be on the client ??
    geo_tweets = read_db_sentiment()
    data_counts = {}
    for x in geo_tweets:   # ????? Check if magnitud is > 20 include it in 20.
        key = str(x[2])+','+str(x[3])
        data_counts[key] = data_counts.get(key, 0) + 1
    plot_data = [['ID', 'Sentiment', 'Magnitude', 'Nothing', 'Count']]
    for key, value in data_counts.iteritems():
        keys = key.split(',')
        sentiment = int(keys[0])
        magnitud = int(keys[1])
        color = 'Neutral'
        if sentiment > 0:
            color = 'Positive'
        elif sentiment < 0:
            color = 'Negative'
        plot_data.append([key, sentiment, magnitud, color, value])

    return render_template("sentiment_plot.html", plot_data=plot_data)


def read_db():
    """ Read the tweet data to load to maps from DB. """

    # geo_tup = Model.db.session.query(Model.Tweet.lat, Model.Tweet.lon).all()
    geo_tup = Model.db.session.query(Model.Tweet.lat, Model.Tweet.lon).filter(Model.Tweet.city_id > 1).all()

    # Translating to list because JavaScript does not understand tuples.
    return [[x[0], x[1]] for x in geo_tup]


def read_db_sentiment():
    """ Read the tweet data to load to maps from DB. """

    # geo_tup = Model.db.session.query(Model.Tweet.lat, Model.Tweet.lon).all()
    geo_tup = Model.db.session.query(Model.Tweet.lat, Model.Tweet.lon, Model.Tweet.sentiment, Model.Tweet.magnitude).filter(Model.Tweet.sentiment.isnot(None)).all()

    # Translating to list because JavaScript does not understand tuples.
    return [[x[0], x[1], x[2], x[3]] for x in geo_tup]

#---------------------------------------------------------------------#


if __name__ == "__main__":
    app.debug = True
    Model.connect_to_db(app)
    DebugToolbarExtension(app)

    app.run(port=5000, host="0.0.0.0")
