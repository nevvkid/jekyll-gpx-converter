module Jekyll
	module GeojsonFilter
		def geojson(input)
			if input.is_a? String
				JSON.parse input
			else
				input
			end
		end
		
		# Extract linestring lenght; this assumes that it is stored in the properties hash.
		def linestring_length(input)
			input["properties"]["distance"]
		end
		
		def center(input)
			input["properties"]["center"]
		end
		
		def zoom(input)
			input["properties"]["zoom"]
		end
		
		def humanize_distance(input)
			"#{(input.to_f / 1000).round} km"
		end
	end
end

# Some extra filters we can use in a layout file.
Liquid::Template.register_filter(Jekyll::GeojsonFilter)
