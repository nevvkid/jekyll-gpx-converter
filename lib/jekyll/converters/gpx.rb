module Jekyll
	module Converters
		class Gpx < Converter
			safe false
			priority :low
			
			DEFAULT_CONFIGURATION = {
				gpx_ext: "gpx",
				collection_name: "rides",
				layout_name: "gpx"
			}
			
			def initialize(config = {})
				@config = Jekyll::Utils.deep_merge_hashes(DEFAULT_CONFIGURATION, config)
				@setup_done = false
				
				# Set layout like this, because gpx files don't have front matter.
				Jekyll::Hooks.register :site, :pre_render do |site|
					site.collections[@config[:collection_name]].docs.each do |doc|
						doc.data["layout"] = @config[:layout_name]
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
				
				features = xml.css("trk").map do |trk|
					translate_gpx_trk_to_geojson_feature(trk)
				end
				
				# Return either geojson Feature or FeatureCollection, depending
				# on how many trk elements the gpx file has.
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
			
			def translate_gpx_trk_to_geojson_feature(trk)
				coordinates = trk.css("trkpt").map do |point|
					lat = point.attributes["lat"]&.value&.to_f
					lon = point.attributes["lon"]&.value&.to_f
					[lon, lat]
				end
				
				{
					type: "Feature",
					properties: {
						distance: linestring_length(coordinates)
					},
					geometry: {
						type: "LineString",
						coordinates: coordinates
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
