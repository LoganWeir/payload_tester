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










