#include "wall_geom.h"
#include "clipper2/clipper.h"
#include <cmath>
#include <cstdlib>
#include <vector>
using namespace Clipper2Lib;
namespace {
constexpr double kScale = 1000.0;
Path64 rect(double ax, double ay, double bx, double by, double width) {
  const double dx=bx-ax, dy=by-ay, length=std::hypot(dx,dy);
  if (length < 1e-8) return {};
  const double half=width*.5;
  const double tx=dx/length*half, ty=dy/length*half;
  const double nx=-dy/length*half, ny=dx/length*half;
  auto point=[](double x,double y) { return Point64((int64_t)llround(x*kScale),(int64_t)llround(y*kScale)); };
  // Extend by half the wall width at both ends. Without this tangent extension
  // these were butt caps despite the old comment; separate runs meeting at an
  // exterior corner consequently left a half-width recess in the union outline.
  // Bounded square caps close L and T joins without the spikes of acute miters.
  return {point(ax-tx+nx,ay-ty+ny),point(bx+tx+nx,by+ty+ny),
          point(bx+tx-nx,by+ty-ny),point(ax-tx-nx,ay-ty-ny)};
}
void flatten(const PolyPath64& parent, ChicagoWallGeometry* out, std::vector<ChicagoWallPoint>& pts, std::vector<ChicagoWallContour>& contours) {
  for (size_t i=0;i<parent.Count();++i) {
    const PolyPath64* child=parent.Child(i); const Path64& path=child->Polygon();
    if (path.size() >= 3) {
      ChicagoWallContour c{(uint32_t)pts.size(),(uint32_t)path.size(),child->IsHole()?1:0};
      for (const Point64& p:path) pts.push_back({p.x/kScale,p.y/kScale});
      contours.push_back(c);
    }
    flatten(*child,out,pts,contours);
  }
}
}
extern "C" int chicago_wall_union(const ChicagoWallSegment* walls, uint32_t wall_count, const ChicagoWallDoor* doors, uint32_t door_count, ChicagoWallGeometry* out) {
  if (!out) return 0; *out={}; Paths64 strokes, cuts;
  for(uint32_t i=0;i<wall_count;++i) { Path64 p=rect(walls[i].ax,walls[i].ay,walls[i].bx,walls[i].by,walls[i].width); if(!p.empty()) strokes.push_back(p); }
  for(uint32_t i=0;i<door_count;++i) { Path64 p=rect(doors[i].ax,doors[i].ay,doors[i].bx,doors[i].by,doors[i].width); if(!p.empty()) cuts.push_back(p); }
  PolyTree64 tree; BooleanOp(ClipType::Union,FillRule::NonZero,strokes,{},tree);
  Paths64 unified=PolyTreeToPaths64(tree);
  if(!cuts.empty()) BooleanOp(ClipType::Difference,FillRule::NonZero,unified,cuts,tree); else BooleanOp(ClipType::Union,FillRule::NonZero,unified,{},tree);
  std::vector<ChicagoWallPoint> pts; std::vector<ChicagoWallContour> contours; flatten(tree,out,pts,contours);
  if(pts.empty()) return 1;
  out->points=(ChicagoWallPoint*)std::malloc(sizeof(ChicagoWallPoint)*pts.size()); out->contours=(ChicagoWallContour*)std::malloc(sizeof(ChicagoWallContour)*contours.size());
  if(!out->points || !out->contours) { chicago_wall_geometry_free(out); return 0; }
  std::copy(pts.begin(),pts.end(),out->points); std::copy(contours.begin(),contours.end(),out->contours); out->point_count=(uint32_t)pts.size(); out->contour_count=(uint32_t)contours.size(); return 1;
}
extern "C" void chicago_wall_geometry_free(ChicagoWallGeometry* g) { if(!g) return; std::free(g->points);std::free(g->contours);*g={}; }
