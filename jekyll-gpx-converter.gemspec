# frozen_string_literal: true

require_relative "lib/jekyll-gpx-converter/version"

Gem::Specification.new do |spec|
  spec.name          = "jekyll-gpx-converter"
  spec.version       = Jekyll::GpxConverter::VERSION
  spec.authors       = ["Mika Haulo"]
  spec.email         = ["mika@hey.com"]
  spec.summary       = "Gpx converter for Jekyll."
  spec.homepage      = "https://github.com/mhaulo/jekyll-gpx-converter"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*.rb", "LICENSE", "README.md", "Gemfile", "Gemfile.lock", "Rakefile"]
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "nokogiri", "~> 1"
  spec.add_runtime_dependency "jekyll", ">= 3.0"

  spec.add_development_dependency "bundler", "~> 2"
  spec.add_development_dependency "rake", "~> 12"
  spec.add_development_dependency "rspec", "~> 3.0"
end
