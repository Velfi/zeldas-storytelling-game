package main

Chicago_Wall_Segment :: struct {ax,ay,bx,by,width:f64}
Chicago_Wall_Door :: struct {ax,ay,bx,by,width:f64}
Chicago_Wall_Point :: struct {x,y:f64}
Chicago_Wall_Contour :: struct {first,count:u32,is_hole:i32}
Chicago_Wall_Geometry :: struct {points:^Chicago_Wall_Point,point_count:u32,contours:^Chicago_Wall_Contour,contour_count:u32}

when ODIN_OS == .Windows {
	foreign import wall_geom "../third_party/wall_geom.lib"
} else {
	foreign import wall_geom "../third_party/libwall_geom.a"
}
@(default_calling_convention="c")
foreign wall_geom {
	chicago_wall_union :: proc(walls:^Chicago_Wall_Segment,wall_count:u32,doors:^Chicago_Wall_Door,door_count:u32,out:^Chicago_Wall_Geometry)->i32 ---
	chicago_wall_geometry_free :: proc(geometry:^Chicago_Wall_Geometry) ---
}
