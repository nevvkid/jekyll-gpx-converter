module Jekyll
	module GeojsonFilter
		# Extract linestring lenght; this assumes that it is stored in the properties hash.
		def geojson_linestring_length(input)
			if input.is_a? String
				geojson = JSON.parse input
				geojson["properties"]["distance"]
			else
				input[:properties][:distance]
			end
		end
		
		def humanize_distance(input)
			"#{(input.to_f / 1000).round} km"
		end
	end
end

# Some extra filters we can use in a layout file.
Liquid::Template.register_filter(Jekyll::GeojsonFilter)
