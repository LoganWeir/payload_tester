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
			geo_type = poly_chop.geometry_type.type_name
			if geo_type == "Polygon"
				json_poly = RGeo::GeoJSON.encode(poly_chop)
				chopped_json_polys << json_poly
			elsif geo_type == "MultiPolygon"
				for single_poly in poly_chop
					json_poly = RGeo::GeoJSON.encode(single_poly)
					chopped_json_polys << json_poly
				end
			end
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









# GETTING THE AVERAHE POINT LENGTH OF BBOX CHOPPED POLYGON
# Takes in RGEO Polygons, Chops to fit BBox, Converts to JOSN, Returns Length
def polychop_point_test(array, bounding_box)
	point_lengths = []
	for polygon in array
		if polygon.intersects?(bounding_box)
			poly_chop = bounding_box.intersection(polygon)
			geo_type = poly_chop.geometry_type.type_name
			if geo_type == "Polygon"	
				point_lengths << total_point_count(poly_chop)
			elsif geo_type == "MultiPolygon"
				for single_poly in poly_chop
					point_lengths << total_point_count(single_poly)
				end
			end
		end
	end
	return [average(point_lengths), point_lengths.max]
end



# Gets the average JSON length of all boxes
def average_polygon_point_count(array)
	all_polygon_lengths = []
	max_polygon_length = []
	for box in array
		testing = polychop_point_test(box['polygons'], box['bbox'])
		all_polygon_lengths << testing[0]
		max_polygon_length << testing[1]

	end
	[average(all_polygon_lengths),  average(max_polygon_length)]
end



def total_point_count(polygon)
	total_count = 0
	total_count += polygon.exterior_ring.num_points
	if polygon.num_interior_rings > 0
		for inner_ring in polygon.interior_rings do 
			total_count += inner_ring.num_points
		end
	end
	total_count
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










