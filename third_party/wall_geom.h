#pragma once
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

// Deliberately tiny C boundary: Odin owns authored walls and all GPU mesh data.
// Coordinates are converted to 1/1000 world-unit integers inside the wrapper.
typedef struct { double ax, ay, bx, by, width; } ChicagoWallSegment;
typedef struct { double ax, ay, bx, by, width; } ChicagoWallDoor;
typedef struct { double x, y; } ChicagoWallPoint;
typedef struct { uint32_t first, count; int32_t is_hole; } ChicagoWallContour;
typedef struct {
  ChicagoWallPoint* points; uint32_t point_count;
  ChicagoWallContour* contours; uint32_t contour_count;
} ChicagoWallGeometry;

int chicago_wall_union(const ChicagoWallSegment* walls, uint32_t wall_count,
  const ChicagoWallDoor* doors, uint32_t door_count, ChicagoWallGeometry* out);
void chicago_wall_geometry_free(ChicagoWallGeometry* geometry);
#ifdef __cplusplus
}
#endif
