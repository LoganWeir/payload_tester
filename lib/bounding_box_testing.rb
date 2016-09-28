require 'rgeo/geo_json'
require 'rgeo'
require 'pry'


def average(array)
	average = array.inject \
			{ |sum, el| sum + el }.to_f / array.length.to_f
end

# Converts polygons from strings into RGeo
def convert_poly_rgeo(array, factory)
	rgeo_polys = []
	for polygon in array
			rgeo_poly = factory.parse_wkt(polygon)
			rgeo_polys << rgeo_poly
	end
	rgeo_polys
end


# Takes in RGEO Polygons, Chops to fit BBox, Converts to JOSN, Returns Length
def polychop_lentest(array, bounding_box)
	chopped_json_polys = []
	for polygon in array
		if polygon.intersects?(bounding_box)
			poly_chop = bounding_box.intersection(polygon)
			json_poly = RGeo::GeoJSON.encode(poly_chop)
			chopped_json_polys << json_poly
		end
	end
	return (chopped_json_polys.to_json.length.to_f/1024)/1024
end



# Gets the average JSON length of all boxes
def average_box_length(array)
	all_box_lengths = []
	for box in array
		all_box_lengths << polychop_lentest(box['polygons'], box['bbox'])
	end
	average(all_box_lengths)
end



# ALL TOGETHER NOW
def box_simplifier(ratio, min_hole_size, size_fill_limits = {}, boxes, factory)
	simpler_boxes = []
	for box in boxes
		simpler_box_hash = {}
		simpler_box_hash['bbox'] = box['bbox']
		simpler_box_hash['polygons'] = []
		for polygon in box['polygons']
			hole_filtered = hole_filtering(min_hole_size, polygon, factory)
			simple_poly = polygon_simplifier(hole_filtered, ratio)
			if size_fill_testing(simple_poly, size_fill_limits) == false
				next
			else
				simpler_box_hash['polygons'] << simple_poly
			end
		end
		simpler_boxes << simpler_box_hash
	end
	simpler_boxes
end



# DELETING HOLES
def hole_filtering(minimum_hole_size, polygon, factory)
	# If holes
	if polygon.num_interior_rings > 0
		new_inner_array = []
		# For each hole
		for inner_ring in polygon.interior_rings do
			# Test size
			if factory.polygon(inner_ring).area > minimum_hole_size
				# If big enough, add to array
				new_inner_array << inner_ring
			end
		end
		if new_inner_array.length > 0
			# If any made it, build new polygon
			new_polygon = factory.polygon(polygon.exterior_ring, 
				new_inner_array)
		else
			# Else, new polygon with no holes
			new_polygon = factory.polygon(polygon.exterior_ring)				
		end
		return new_polygon
	else
		return polygon
	end
end



# SIMPLIFICATION
def polygon_simplifier(polygon, ratio)
	max_points = polygon.exterior_ring.num_points * ratio
	simplfication = 0
	while polygon.exterior_ring.num_points > max_points	
		simplfication += 1
		new_simple_projection = polygon.simplify(simplfication)
		# Over-simplification can delete polygons
		if new_simple_projection == nil
			break
		# Polygons can simply end up empty?
		elsif new_simple_projection.is_empty?
			break 
		# Over-simplification can turn the projection into a multi-polygon
		elsif new_simple_projection.geometry_type.type_name == "MultiPolygon"
			break 					
		else
			polygon = new_simple_projection
		end				
	end
	polygon
end


# SIZE AND FILL LIMITS
def size_fill_testing(polygon, size_fill_limits = {})
	fit = 0
	polygon_fill = polygon.area/polygon.envelope.area
	polygon_area = polygon.area
	for fill, size in size_fill_limits
		if polygon_fill > fill.to_f &&  polygon_area > size
			fit += 1
		end
	end
	if fit == 0
		return false
	else
		return true
	end
end








# TEST OUTPUT STRUCTURE
# zoom_level
# 	payload
# 		average_length
# 		max_length
# 	ratios (hash)
# 		fill : (minimum area/average bbox area)

# Tests for Payload Size,
def bbox_test_output(bboxes = {}, zoom_hash = {})
	test_output = {}
	zoom_hash.each do |zoom_level, zoom_params|
		for zoom_level in zoom_params['map_zoom']
			test_output[zoom_level] = {}
			# Getting payloads, average and max
			payload = bbox_payload_testing(bboxes[zoom_level]['boxes'])
			test_output[zoom_level]['payload'] = payload

			if zoom_params["size_fill_limits"] != nil
				test_output[zoom_level]['ratios'] = {}
				bbox_area = bboxes[zoom_level]['average_area']
				for key, value in zoom_params["size_fill_limits"]
					test_output[zoom_level]['ratios'][value] = \
						(key.to_f/bbox_area) * (10 ** 6)
				end
			end
			
		end
	end
	test_output
end


def bbox_payload_testing(boxes = [])
	payload = {}
	all_box_lengths = []
	for box in boxes
		box_length = []
		for polygon in box['intersections']
			json_poly = RGeo::GeoJSON.encode(polygon)
			# puts json_poly['coordinates']
			box_length << json_poly['coordinates']
		end
		mb_length = (box_length.to_json.length.to_f/1024)/1024
		all_box_lengths << mb_length
	end
	payload['average_length'] = average(all_box_lengths)
	payload['max_length'] = all_box_lengths.sort.max
	payload
end


	# for key, value in bbox_intersections
	# 	test_output[key] = {}
	# 	average_length = []
	# 	for box_name, box_values in value
	# 		box_length = []
	# 		for item in box_values['intersections']
	# 			cleaned_poly = RGeo::GeoJSON.encode(item)
	# 			box_length << cleaned_poly["geometries"][0]
	# 		end
	# 		mb_length = (box_length.to_json.length/1024)/1024
	# 		average_length << mb_length
	# 	end

	# 	average = average_length.inject \
	# 		{ |sum, el| sum + el }.to_f / average_length.length

	# 	test_output[key]['average_length'] = average
	# 	test_output[key]['max_length'] = average_length.max
	# end
	# test_output






# # Matches Zoom Levels to Zoom Ranges. Key is Zoom Level, Value is Boxes
# def sort_bboxes(bounding_boxes = {}, matching_hash = {})
# 	sorted_output = {}
# 	for matching_key, matching_value in matching_hash
# 		matches = bounding_boxes.select\
# 			{ |k,v| matching_value['map_zoom'].include? k}
# 		if matches.empty?
# 			next
# 		else
# 			sorted_output[matching_key] = []
# 			for key, value in matches
# 				for box in value
# 					sorted_output[matching_key] << box
# 				end
# 			end
# 		end
# 	end
# 	sorted_output
# end


# OLD BUILDER

	# for key, boxes in sorted_bboxes
	# 	final_bounding_boxes[key] = {}		
	# 	boxes.each.with_index(1) do |box, index|
	# 		final_bounding_boxes[key]["box_" + index.to_s] = {}
	# 		final_bounding_boxes[key]["box_" + index.to_s]['box'] =\
	# 			convert_bbox(box)
	# 		final_bounding_boxes[key]["box_" + index.to_s]['intersections'] = []
	# 	end
	# end
	# final_bounding_boxes







# # Process Input, Delivers Final Product 
# def bounding_box_builder(bounding_boxes = {})
# 	final_bounding_boxes = {}
# 	for key, boxes in bounding_boxes
# 		final_bounding_boxes[key] = {}
# 		final_bounding_boxes[key]['boxes'] = []
# 		all_areas = []
# 		boxes.each.with_index(1) do |box, index|
# 			box_hash = {}
# 			box_hash['intersections'] = []
# 			rgeo_conversion = convert_bbox(box)
# 			box_hash['rgeo_box'] = rgeo_conversion
# 			box_area = rgeo_conversion.area
# 			box_hash['rgeo_box_area'] = box_area
# 			all_areas << box_area
# 			final_bounding_boxes[key]['boxes'] << box_hash
# 		end
# 		final_bounding_boxes[key]['average_area'] = average(all_areas)
# 	end
# 	final_bounding_boxes
# end


# # Converts GSOJSON Box into RGEO BOX
# def convert_bbox(box)
# 	factory = RGeo::Geographic.simple_mercator_factory(:srid => 4326)
# 	ring = []
# 	for item in box
# 		ring << factory.point(item[0], item[1])
# 	end
# 	linear_ring = factory.linear_ring(ring)
# 	polygon = factory.polygon(linear_ring)
# 	polygon
# end










