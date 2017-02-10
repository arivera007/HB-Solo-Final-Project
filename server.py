"""Creating Google Map with tweeter information."""

from jinja2 import StrictUndefined
from flask import Flask, render_template     # , jsonify
from flask_debugtoolbar import DebugToolbarExtension

# from model import connect_to_db, db
import Model

app = Flask(__name__)
app.secret_key = "queonda"
app.jinja_env.undefined = StrictUndefined

#---------------------------------------------------------------------#


@app.route('/')
def index():
    """Show homepage."""

    return render_template("home.html")


@app.route('/map')
def map():
    """Show map with tweets."""

    return render_template("map.html")

#---------------------------------------------------------------------#


if __name__ == "__main__":
    app.debug = True
    Model.connect_to_db(app)
    DebugToolbarExtension(app)

    app.run(port=5000, host="0.0.0.0")
    app.run(port=5000, host="0.0.0.0")
