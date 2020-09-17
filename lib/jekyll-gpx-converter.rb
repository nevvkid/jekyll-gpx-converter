require 'jekyll'

root = File.expand_path("jekyll-gpx-converter", File.dirname(__FILE__))
require "#{root}/version"

require File.expand_path("jekyll/converters/gpx", File.dirname(__FILE__))
require File.expand_path("jekyll/geojson_filter", File.dirname(__FILE__))

module Jekyll
  module GpxConverter
  end
end
