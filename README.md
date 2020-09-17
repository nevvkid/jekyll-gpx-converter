# Jekyll Gpx Converter

Convert gpx files into viewable web pages with a map. For Jekyll 3.0 and up.

## Installation

This gem is designed to be used with jekyll-leaflet.

Add these lines to your application's Gemfile:

```ruby
gem 'jekyll-gpx-converter'
gem 'jekyll-leaflet'
```

And then execute:

    $ bundle

Or install the gems manually:

    $ gem install jekyll-gpx-converter
    $ gem install jekyll-leaflet

Lastly, add it as well as jekyll-leaflet to your `_config.yml` file:

    plugins:
    - jekyll-gpx-converter
    - jekyll-leaflet

## Usage

Create a collection named "rides" in your theme and enable output for it. See [Jekyll documentation](https://jekyllrb.com/docs/collections/) for details on how to do this.

Drop some gpx files into `_rides` directory. Do *not* add front matter to them. Jekyll will render them as collection documents.

You probably need to add an index page somewhere in your theme. To iterate the collection, you can do something like this:

```html
{% for ride in site.rides %}
  <a href="{{ ride.url | prepend: site.baseurl }}">
    <div>
      <time datetime="{{ ride.date }}">{{ ride.date | date: "%B %d, %Y" }}</time>
      <h2>{{ ride.title }}</h2>
    </div>
  </a>
{% endfor %}
```

To show gpx content in a theme, create a layout named "gpx". Example:

```html
<div class="post">
  <h1>{{ page.title }}</h1>

  {{ content | geojson_linestring_length | humanize_distance }}

  {% leaflet_map  {"providerBasemap": "OpenStreetMap.Mapnik"} %}
    {% leaflet_geojson {{ content }} %}
  {% endleaflet_map %}
</div>

```


## Implementation details

This gem consists of three parts:

* the converter itself
* a GeoJSON filter
* a monkey patch to Jekyll

### The converter

This is the main feature of this gem that allows dropping in gpx files. It converts gpx file format into GeoJSON; something that the Leaflet map library can understand.

### The GeoJSON filter

Two filter methods are added for convenience:

* `geojson_linestring_length` extracts length information from a GeoJSON object or string. It assumes that the length is present in properties hash.
* `humanize_distance` returns a human-friendly format of the distance. Currently it's hard coded to output the distance in kilometers.

### The monkey patch

The idea behind this gem is to allow dropping in gpx files without making any (manual) modifications to them. This requires some monkey patching because of how Jekyll itself is designed to work.

Jekyll treats files differently based on whether they have a thing called *front matter* or not. Normally content files should have front matter; that tell Jekyll important things such as which layout to use. Files with front matter will be processed, files without it will be copied as they are.

Now, here's the problem: we don't want to add front matter manually to gpx files. But we still want them to processed by Jekyll. To achieve this, we need to add a small exception to Jekyll's internal processing rules by overwriting the `read` method in `Jekyll::Collection`.

Another thing that needs to be done is to programmatically add the front matter. This is because we need to tell Jekyll which layout to use. This is done by registering a pre_render site hook.

Couldn't we just add the front matter and not monkey patch at all? No – we need the monkey patch because otherwise Jekyll would treat gpx files as static files and the pre_render hook would't reach them.


## Contributing

1. Fork it ( https://github.com/jekyll/jekyll-gpx-converter/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request
