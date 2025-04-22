module Jekyll
	module Converters
	  class Gpx < Converter
		safe false
		priority :low
		
		DEFAULT_CONFIGURATION = {
		  gpx_ext: "gpx,xml",  # Added xml extension to catch GPX files saved as XML
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
				# Only process documents with GPX/XML extension that contain GPX data
				next unless matches(File.extname(doc.path))
				next unless is_gpx_content?(doc.content)
				
				# Set layout
				doc.data["layout"] = @config[:layout_name]
				
				# Extract date from filename if it matches common date patterns
				filename = File.basename(doc.path)
				
				if filename =~ /^(\d{4})[\s_-](\d{2})[\s_-](\d{2})/
				  # Format: YYYY-MM-DD, YYYY_MM_DD, YYYY MM DD
				  year, month, day = $1, $2, $3
				  doc.data["date"] = Time.new(year.to_i, month.to_i, day.to_i)
				elsif filename =~ /^(\d{2})[\s_-](\d{2})[\s_-](\d{4})/
				  # Format: DD-MM-YYYY, DD_MM_YYYY, DD MM YYYY
				  day, month, year = $1, $2, $3
				  doc.data["date"] = Time.new(year.to_i, month.to_i, day.to_i)
				elsif filename =~ /^(\d{2})[\s_-]([A-Za-z]{3})[\s_-](\d{4})/i
				  # Format: DD-MMM-YYYY, DD_MMM_YYYY, DD MMM YYYY (e.g., 22-Jan-2024)
				  day, month_name, year = $1, $2.downcase, $3
				  month_map = {
					'jan' => 1, 'feb' => 2, 'mar' => 3, 'apr' => 4, 'may' => 5, 'jun' => 6,
					'jul' => 7, 'aug' => 8, 'sep' => 9, 'oct' => 10, 'nov' => 11, 'dec' => 12
				  }
				  if month = month_map[month_name]
					doc.data["date"] = Time.new(year.to_i, month.to_i, day.to_i)
				  end
				end
				
				# Extract title from filename for better display
				if doc.data["title"].nil? || doc.data["title"].empty?
				  base_filename = File.basename(filename, ".*")
				  
				  # Remove date prefix if present
				  clean_filename = base_filename.gsub(/^\d{4}[\s_-]\d{2}[\s_-]\d{2}[\s_-]?/, '')
				  clean_filename = clean_filename.gsub(/^\d{2}[\s_-]\d{2}[\s_-]\d{4}[\s_-]?/, '')
				  clean_filename = clean_filename.gsub(/^\d{2}[\s_-][A-Za-z]{3}[\s_-]\d{4}[\s_-]?/, '')
				  
				  # Try to get a meaningful title from metadata if available
				  begin
					xml = Nokogiri::XML(doc.content)
					metadata_name = xml.at_css("metadata name")&.content || xml.at_css("name")&.content
					doc.data["title"] = metadata_name if metadata_name && !metadata_name.empty?
				  rescue
					# If parsing fails, fallback to filename
					doc.data["title"] = clean_filename
				  end
				  
				  # Fallback to clean filename if no title found
				  doc.data["title"] ||= clean_filename
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
		
		def is_gpx_content?(content)
		  # Quick check to see if content is likely a GPX file
		  content.include?("<gpx") || content.include?("<trk") || content.include?("<wpt")
		end
		
		def convert(content)
		  setup
		  xml = Nokogiri::XML(content)
		  
		  # Handle different GPX namespaces
		  namespaces = xml.namespaces
		  default_ns = namespaces.key?('xmlns') ? 'xmlns:' : ''
		  
		  # Process track elements - handle different possible XPath structures
		  track_features = []
		  
		  # Try different XPath patterns for tracks
		  track_elements = xml.xpath("//trk") 
		  track_elements = xml.xpath("//#{default_ns}trk") if track_elements.empty? && !default_ns.empty?
		  
		  track_features = track_elements.map do |trk|
			translate_gpx_trk_to_geojson_feature(trk)
		  end
		  
		  # Process waypoint elements - handle different possible XPath structures
		  waypoint_elements = xml.xpath("//wpt")
		  waypoint_elements = xml.xpath("//#{default_ns}wpt") if waypoint_elements.empty? && !default_ns.empty?
		  
		  waypoint_features = waypoint_elements.map do |wpt|
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
			
			# Calculate total distance for tracks
			total_distance = 0
			track_features.each do |feature|
			  total_distance += feature[:properties][:distance] if feature[:properties][:distance]
			end
			geojson[:properties][:distance] = total_distance
		  else
			geojson[:properties] ||= {}
			geojson[:properties][:center] = [0, 0]
			geojson[:properties][:distance] = 0
			geojson[:properties][:isEmpty] = true
		  end
		  
		  # Set a zoom level based on track length
		  if all_coordinates.any?
			# Calculate appropriate zoom level based on track length
			total_distance = geojson[:properties][:distance]
			zoom_level = if total_distance > 100000  # > 100km
						  8
						elsif total_distance > 50000  # > 50km
						  9
						elsif total_distance > 20000  # > 20km
						  10
						elsif total_distance > 10000  # > 10km
						  11
						elsif total_distance > 5000   # > 5km
						  12
						else
						  13
						end
			geojson[:properties][:zoom] = zoom_level
		  else
			geojson[:properties][:zoom] = 11 # Default zoom
		  end
		  
		  geojson.to_json
		end
		
		private
		
		def setup
		  return if @setup_done
		  require "nokogiri"
		  require "json"
		  @setup_done = true
		rescue LoadError => e
		  STDERR.puts "You are missing a library required for this plugin. Please run:"
		  STDERR.puts "  $ [sudo] gem install #{e.message.split(' ').last}"
		  raise Jekyll::Errors::FatalException.new("Missing dependency: #{e.message}")
		end
		
		def extname_list
		  @extname_list ||= @config[:gpx_ext].split(",").map { |e| ".#{e}" }
		end
		
		# Handle track points with better error handling
		def translate_gpx_trk_to_geojson_feature(trk)
		  coordinates = []
		  
		  # Try different ways to get track points
		  trackpoints = trk.css("trkpt")
		  trackpoints = trk.css("trkseg trkpt") if trackpoints.empty?
		  
		  coordinates = trackpoints.map do |point|
			lat = point.attributes["lat"]&.value&.to_f
			lon = point.attributes["lon"]&.value&.to_f
			
			# Skip invalid coordinates
			next nil unless lat && lon && !lat.zero? && !lon.zero?
			
			# Check valid ranges
			next nil if lat < -90 || lat > 90 || lon < -180 || lon > 180
			
			[lon, lat]
		  end.compact
		  
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
		
		# Handle waypoints with better error handling
		def translate_gpx_wpt_to_geojson_feature(wpt)
		  lat = wpt.attributes["lat"]&.value&.to_f
		  lon = wpt.attributes["lon"]&.value&.to_f
		  
		  # Return empty feature if coordinates are invalid
		  if !lat || !lon || lat.zero? && lon.zero? || lat < -90 || lat > 90 || lon < -180 || lon > 180
			return {
			  type: "Feature",
			  properties: {
				name: "Invalid Waypoint",
				type: "waypoint"
			  },
			  geometry: {
				type: "Point",
				coordinates: [0, 0]
			  }
			}
		  end
		  
		  name = wpt.at_css("name")&.content || "Waypoint"
		  desc = wpt.at_css("desc")&.content || wpt.at_css("cmt")&.content
		  ele = wpt.at_css("ele")&.content
		  sym = wpt.at_css("sym")&.content
		  
		  properties = {
			name: name,
			type: "waypoint"
		  }
		  
		  # Add additional properties if available
		  properties[:description] = desc if desc
		  properties[:ele] = ele.to_f if ele
		  properties[:sym] = sym if sym
		  
		  {
			type: "Feature",
			properties: properties,
			geometry: {
			  type: "Point",
			  coordinates: [lon, lat]
			}
		  }
		end
		
		# Enhanced distance calculation with improved Haversine formula
		def distance_between_coordinates(a, b)
		  return 0 if a.nil? || b.nil?
		  
		  lon1, lat1 = a[0], a[1]
		  lon2, lat2 = b[0], b[1]
		  
		  # Convert from degrees to radians
		  lon1_rad = lon1 * Math::PI / 180
		  lat1_rad = lat1 * Math::PI / 180
		  lon2_rad = lon2 * Math::PI / 180
		  lat2_rad = lat2 * Math::PI / 180
		  
		  # Haversine formula
		  dlon = lon2_rad - lon1_rad
		  dlat = lat2_rad - lat1_rad
		  a = Math.sin(dlat/2)**2 + Math.cos(lat1_rad) * Math.cos(lat2_rad) * Math.sin(dlon/2)**2
		  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
		  
		  # Earth radius in meters
		  earth_radius = 6371000
		  
		  # Return distance in meters
		  earth_radius * c
		end
		
		def linestring_length(coordinates)
		  length = 0
		  
		  if coordinates.length > 1
			coordinates.each_with_index do |coord, index|
			  next if index.zero?
			  segment_distance = distance_between_coordinates(coordinates[index-1], coord)
			  length += segment_distance if segment_distance
			end
		  end
		  
		  length
		end
		
		def bounding_box(coordinates)
		  return [[0, 0], [0, 0]] if coordinates.empty?
		  
		  valid_coordinates = coordinates.compact.reject { |point| point[0].nil? || point[1].nil? }
		  return [[0, 0], [0, 0]] if valid_coordinates.empty?
		  
		  lngs = valid_coordinates.map { |point| point[0] }
		  lats = valid_coordinates.map { |point| point[1] }
		  
		  left   = lngs.min
		  bottom = lats.min
		  right  = lngs.max
		  top    = lats.max
		  
		  [[left, bottom], [right, top]]
		end
		
		def center(bbox)
		  left, bottom = bbox[0]
		  right, top = bbox[1]
		  
		  # Add safety checks to prevent nil errors
		  if left.nil? || top.nil? || bottom.nil? || right.nil?
			return [0, 0]
		  end
		  
		  lng = (left + right) / 2
		  lat = (bottom + top) / 2
		  
		  # Return coordinates in correct format for center
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
	  
	  GPX_FILE_EXTS = %w(.gpx .xml).freeze # Added .xml extension
	  
	  def is_gpx_file?(path)
		extname = File.extname(path)
		if GPX_FILE_EXTS.include?(extname.downcase)
		  # Quick check of file content to confirm it's actually a GPX file
		  begin
			first_bytes = File.open(path, 'rb') { |f| f.read(500) } # Read first 500 bytes
			return first_bytes.include?("<gpx") || 
				   first_bytes.include?("<trk") || 
				   first_bytes.include?("<wpt")
		  rescue => e
			Jekyll.logger.warn "GPX Converter:", "Error checking file type: #{e.message}"
			return false
		  end
		end
		false
	  end
	end
  end