// Shared road-verge colours (linear). road.gdshader (dusty edge of the paving, verge skirt) and
// terrain.gdshader (worn ground beside the road) both take their colours from here, so the asphalt edge,
// the skirt and the terrain meet without a seam.
//
// VERGE_TEX_MEAN is the mean linear colour of mix(dirt, gravel, 0.55) from assets/textures/terrain
// (regenerate with the textures: tools/make_terrain_textures.gd). The terrain scales its dirt/gravel
// detail by VERGE_SOIL / VERGE_TEX_MEAN, so its mean verge colour is exactly VERGE_SOIL.

const vec3 VERGE_SOIL = vec3(0.075, 0.058, 0.042);       // packed earth beside the road
const vec3 VERGE_DUST = vec3(0.150, 0.130, 0.100);       // wind-blown sand and dust on the paving edge
const vec3 VERGE_GRIT = vec3(0.230, 0.215, 0.190);       // fine gravel specks
const vec3 VERGE_GRASS = vec3(0.040, 0.100, 0.015);      // grass breaking through at the edge
const vec3 VERGE_TEX_MEAN = vec3(0.0716, 0.0563, 0.0416);
