module Jekyll
	module GeojsonFilter
	  def geojson(input)
		if input.is_a? String
		  begin
			JSON.parse(input)
		  rescue => e
			Jekyll.logger.warn "GeojsonFilter:", "Error parsing JSON: #{e.message}"
			{"type" => "Feature", "properties" => {"error" => true, "message" => e.message}, "geometry" => {"type" => "Point", "coordinates" => [0, 0]}}
		  end
		else
		  input
		end
	  end
	  
	  # Extract linestring length; this assumes that it is stored in the properties hash.
	  def linestring_length(input)
		return 0 unless input.is_a?(Hash) && input["properties"]
		input["properties"]["distance"] || 0
	  end
	  
	  def center(input)
		return [0, 0] unless input.is_a?(Hash) && input["properties"]
		input["properties"]["center"] || [0, 0]
	  end
	  
	  def zoom(input)
		return 11 unless input.is_a?(Hash) && input["properties"]
		input["properties"]["zoom"] || 11
	  end
	  
	  def humanize_distance(input)
		return "0 km" if input.nil? || !input.respond_to?(:to_f) || input.to_f == 0
		
		distance = input.to_f
		if distance < 1000
		  "#{distance.round} m"
		elsif distance < 10000
		  "#{(distance / 1000).round(1)} km"
		else
		  "#{(distance / 1000).round} km"
		end
	  end
	  
	  # New method to extract waypoints for separate display
	  def extract_waypoints(input)
		return [] unless input.is_a?(Hash)
		
		if input["type"] == "FeatureCollection" && input["features"]
		  input["features"].select { |f| f["properties"] && f["properties"]["type"] == "waypoint" }
		elsif input["type"] == "Feature" && input["properties"] && input["properties"]["type"] == "waypoint"
		  [input]
		else
		  []
		end
	  end
	  
	  # New method to extract tracks for separate display
	  def extract_tracks(input)
		return [] unless input.is_a?(Hash)
		
		if input["type"] == "FeatureCollection" && input["features"]
		  input["features"].select { |f| f["properties"] && f["properties"]["type"] == "track" }
		elsif input["type"] == "Feature" && input["properties"] && input["properties"]["type"] == "track"
		  [input]
		else
		  []
		end
	  end
	end
  end
  
  # Some extra filters we can use in a layout file.
  Liquid::Template.register_filter(Jekyll::GeojsonFilter)