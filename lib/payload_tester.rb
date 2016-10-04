#!/usr/bin/env ruby

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)

require 'json'
require 'trollop'
require 'rgeo/geo_json'
require 'rgeo'
# For pretty printing, if needed
require 'pry'

require 'bounding_box_testing'



# Set options outside of ARGV
opts = Trollop::options do
  opt :output_name, "Output Name", default: nil, 
  	short: 'o', type: String
end


# Only produce output file if asked for
if opts[:output_name].nil?
	output = nil
else
	path_file = 'output/' + opts[:output_name]
	output = open(path_file, 'w')
end


zoom_bboxes_intersections = JSON.parse(File.read(ARGV[0]))

seed_parameters = JSON.parse(File.read('seed_parameters.json'))

zoom_parameters = seed_parameters['zoom_parameters']

# Setup RGeo factory for handling geographic data
# Uses projection for calculations
# Converts area/distance calculations to meters (75% sure)
factory = RGeo::Geographic.simple_mercator_factory(:srid => 4326)



# Preparing Hash for Testing
testing_hash = {}
for zoom_level, zoom_value in zoom_bboxes_intersections
	testing_hash[zoom_level] = {}
	testing_hash[zoom_level]['settings'] = zoom_parameters[zoom_level]
	testing_hash[zoom_level]['average_box_area'] = zoom_value['average_area']
	testing_hash[zoom_level]['boxes'] = []
	for box in zoom_value['boxes']
		box_hash = {}
		box_hash['bbox'] = factory.parse_wkt(box['rgeo_box'])
		box_hash['polygons'] = convert_poly_rgeo(box['intersections'], factory)
		testing_hash[zoom_level]['boxes'] << box_hash
	end
end


# Output
size_parameters = {}


# Testing
for zoom_level, zoom_contents in testing_hash

	size_parameters[zoom_level] = {}

	target_boxes = zoom_contents['boxes']

	bbox_area = zoom_contents['average_box_area']


	# Gather parameters from settings


	# PULLED FROM FILE
	min_hole_size = zoom_contents['settings']["minimum_hole_size"]
	simplify_ratio = zoom_contents['settings']["simplification"] 
	# size_fill_ratio = zoom_contents['settings']["size_fill_limits"]

	# Setting Limits
	min_hole_size_limit = min_hole_size * 10

	

	# DONE AS RATIO, RATIO IS SET BY TESTING ON ZOOM 8
	size_fill_ratio = {}
	size_fill_ratio["0.5"] = bbox_area * (50 * (10 ** -7))
	size_fill_ratio["0.25"] = bbox_area * (10 * (10 ** -6))
	size_fill_ratio["0"] = bbox_area * (20 * (10 ** -6))



	size_fill_limits = {}
	size_fill_limits["0.5"] = size_fill_ratio["0.5"] * 10
	size_fill_limits["0.25"] = size_fill_ratio["0.25"] * 10
	size_fill_limits["0"] = size_fill_ratio["0"] * 10







	# # DONE MANUALLY
	# size_fill_ratio = {}
	# size_fill_ratio[0.5] = 0
	# size_fill_ratio[0.25] = 0
	# size_fill_ratio[0] = 0

	# # Setting Limits
	# min_hole_size_limit = 10000

	# size_fill_limits = {}
	# size_fill_limits[0.5] = 10000
	# size_fill_limits[0.25] = 10000
	# size_fill_limits[0] = 100000





	# Filter Holes, Filter Small Polygons, Simplify Polygon in Each Box
	first_simplification = box_simplifier(simplify_ratio,
		min_hole_size, size_fill_ratio, target_boxes, factory)

	current_payload_average = average_box_length(first_simplification)
	average_point_length = average_polygon_point_count(first_simplification)

	puts ">>>>>>>>>>"
	puts "Zoom Level #{zoom_level} initial size: #{current_payload_average}"

	puts "Average BBox-Chopped Polygon Point Length: #{average_point_length}"

	attempts = 0

	while current_payload_average > 1

		attempts += 1

		puts "=========="
		puts "Attempt ##{attempts}"

		if min_hole_size > min_hole_size_limit
			puts "Minimum Hole Size Reached"
			break
		else
			min_hole_size = min_hole_size * 1.1
		end


		for fill, size_limit in size_fill_ratio

			if size_limit > size_fill_limits[fill]
				puts "Max Size/Fill Reached: #{fill}: #{size_limit}"
				break
			else
				size_fill_ratio[fill] = size_limit * 1.1
			end

		end

		# if simplify_ratio < 0.1
		# 	puts "Simplification Limit Hit"
		# 	# break
		# else
		# 	simplify_ratio -= 0.05
		# end

		if attempts == 20
			puts "TOO MANY ATTEMPTS!!!"
			break
		end


		puts "=========="
		puts "Minimum Hole Size: #{min_hole_size}"
		puts "Simplification: #{simplify_ratio}"
		puts "Size/Fill Limits: #{size_fill_ratio}"
		puts "=========="

		simplified_boxes = box_simplifier(simplify_ratio, min_hole_size, 
			size_fill_ratio, target_boxes, factory)

		current_payload_average = average_box_length(simplified_boxes)

		puts "Payload = #{current_payload_average}"
		puts "=========="
		puts "\a"

	end

	puts "Zoom Level #{zoom_level} final size: #{current_payload_average}"
	puts "<<<<<<<<<<"

	size_parameters[zoom_level]['Simplification'] = simplify_ratio
	size_parameters[zoom_level]['Minimum Hole Size'] = min_hole_size
	size_parameters[zoom_level]['Fill Size Limits'] = size_fill_ratio
	size_parameters[zoom_level]['Final Payload'] = current_payload_average
end


pp(size_parameters)

output.write(size_parameters.to_json) unless output.nil?

output.close unless output.nil?

puts "\a"
puts "\a"
puts "\a"

