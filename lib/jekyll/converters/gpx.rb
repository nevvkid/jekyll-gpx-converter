module Jekyll
	module Converters
		class Gpx < Converter
			safe false
			priority :low
			
			DEFAULT_CONFIGURATION = {
				gpx_ext: "gpx",
				layout_name: "gpx"
			}
			
			def initialize(config = {})
				@config = Jekyll::Utils.deep_merge_hashes(DEFAULT_CONFIGURATION, config)
				@setup_done = false
				
				# Set layout and extract date from filename for all collections containing GPX files
				Jekyll::Hooks.register :site, :pre_render do |site|
					# Process all collections
					site.collections.each do |name, collection|
						collection.docs.each do |doc|
							# Only process documents with GPX extension
							next unless File.extname(doc.path).downcase == ".gpx"
							
							# Set layout
							doc.data["layout"] = @config[:layout_name]
							
							# Extract date from filename if it matches the pattern YYYY_MM_DD or similar
							filename = File.basename(doc.path)
							if filename =~ /^(\d{4})[\s_-](\d{2})[\s_-](\d{2})/
								year, month, day = $1, $2, $3
								doc.data["date"] = Time.new(year.to_i, month.to_i, day.to_i)
							end
						end
					end
				end
			end
			
			def matches(ext)
				extname_list.include? ext.downcase
			end
			
			def output_ext(ext)
				".html"
			end
			
			def convert(content)
				setup
				xml = Nokogiri::XML(content)
				
				# Process track elements
				track_features = xml.css("trk").map do |trk|
					translate_gpx_trk_to_geojson_feature(trk)
				end
				
				# Process waypoint elements (new)
				waypoint_features = xml.css("wpt").map do |wpt|
					translate_gpx_wpt_to_geojson_feature(wpt)
				end
				
				# Combine both types of features
				features = track_features + waypoint_features
				
				# If no features found, create an empty GeoJSON object with default values
				if features.empty?
					return {
						type: "Feature",
						properties: {
							center: [0, 0],
							zoom: 11,
							distance: 0,
							isEmpty: true
						},
						geometry: {
							type: "LineString",
							coordinates: []
						}
					}.to_json
				end
				
				# Return either geojson Feature or FeatureCollection, depending
				# on how many elements the gpx file has.
				geojson = begin
					if features.size == 1
						features.first
					else
						{
							type: "FeatureCollection",
							features: features
						}
					end
				end
				
				# Collect all coordinates from all features
				all_coordinates = []
				features.each do |feature|
					if feature[:geometry][:type] == "LineString"
						all_coordinates += feature[:geometry][:coordinates]
					elsif feature[:geometry][:type] == "Point"
						all_coordinates << feature[:geometry][:coordinates]
					end
				end
				
				# Only calculate bounding box and center if we have coordinates
				if all_coordinates.any?
					bbox = bounding_box(all_coordinates)
					geojson[:properties] ||= {}
					geojson[:properties][:center] = center(bbox)
				else
					geojson[:properties] ||= {}
					geojson[:properties][:center] = [0, 0]
					geojson[:properties][:isEmpty] = true
				end
				
				# Zoom value is hardcoded for now
				geojson[:properties][:zoom] = 11
				
				geojson.to_json
			end
			
			private
			
			def setup
				return if @setup_done
				require "nokogiri"
				@setup_done = true
			rescue LoadError
				STDERR.puts "You are missing a library required for this plugin. Please run:"
				STDERR.puts "  $ [sudo] gem install Nokogiri"
				raise Errors::FatalException.new("Missing dependency: Nokogiri")
			end
			
			def extname_list
				@extname_list ||= @config[:gpx_ext].split(",").map { |e| ".#{e}" }
			end
			
			# Handle track points
			def translate_gpx_trk_to_geojson_feature(trk)
				coordinates = trk.css("trkpt").map do |point|
					lat = point.attributes["lat"]&.value&.to_f
					lon = point.attributes["lon"]&.value&.to_f
					[lon, lat]
				end
				
				name = trk.at_css("name")&.content || "Unnamed Track"
				
				{
					type: "Feature",
					properties: {
						name: name,
						type: "track",
						distance: linestring_length(coordinates)
					},
					geometry: {
						type: "LineString",
						coordinates: coordinates
					}
				}
			end
			
			# New method to handle waypoints
			def translate_gpx_wpt_to_geojson_feature(wpt)
				lat = wpt.attributes["lat"]&.value&.to_f
				lon = wpt.attributes["lon"]&.value&.to_f
				
				name = wpt.at_css("name")&.content || "Waypoint"
				desc = wpt.at_css("desc")&.content
				
				properties = {
					name: name,
					type: "waypoint"
				}
				
				# Add description if available
				properties[:description] = desc if desc
				
				{
					type: "Feature",
					properties: properties,
					geometry: {
						type: "Point",
						coordinates: [lon, lat]
					}
				}
			end
			
			# Distance calculation needs to take into account that the earth is a sphere.
			def distance_between_coordinates(a, b)
				rad_conversion = Math::PI / 180
				
				delta_lon = (b.first - a.first) * rad_conversion
				lat_a = a.last * rad_conversion
				lat_b = b.last * rad_conversion
				
				x = delta_lon * Math.cos((lat_a + lat_b) / 2)
				y = (lat_b - lat_a)
				d = Math.sqrt(x**2 + y**2)
				
				earth_radius = 6371000
				d * earth_radius
			end
			
			def linestring_length(coordinates)
				length = 0
				
				if coordinates.length > 1
					coordinates.each_with_index do |coord, index|
						next if index.zero?
						length += distance_between_coordinates(coordinates[index], coordinates[index-1])
					end
				end
				
				length
			end
			
			def bounding_box(coordinates)
				return [[0, 0], [0, 0]] if coordinates.empty?
				
				lngs = coordinates.map { |point| point[0] }
				lats = coordinates.map { |point| point[1] }
				
				left   = lngs.min
				bottom = lats.min
				right  = lngs.max
				top    = lats.max
				
				[[left, top], [bottom, right]]
			end
			
			def center(bbox)
				left, top, bottom, right = bbox.flatten
				
				# Add safety checks to prevent nil errors
				if left.nil? || top.nil? || bottom.nil? || right.nil?
					return [0, 0]
				end
				
				lat = (bottom + top) / 2
				lng = (left + right) / 2
				
				# jekyll-leaflet takes center coordinates in this order - first lat, then lng - in contrast to geojson format, which takes lng first.
				[lat, lng]
			end
		end
	end
	
	class Collection
		# Monkey patched version of the read method: treat gpx files as documents even if they don't have front matter.
		def read
			filtered_entries.each do |file_path|
				full_path = collection_dir(file_path)
				next if File.directory?(full_path)

				if is_gpx_file?(full_path) or Utils.has_yaml_header?(full_path)
					read_document(full_path)
				else
					read_static_file(file_path, full_path)
				end
			end
			sort_docs!
		end
		
		GPX_FILE_EXTS = %w(.gpx).freeze
		
		def is_gpx_file?(path)
			extname = File.extname(path)
			GPX_FILE_EXTS.include?(extname.downcase)
		end
	end
end