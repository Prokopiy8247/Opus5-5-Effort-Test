extends RefCounted
## Graphics presets for Settings "quality" (0 low, 1 medium, 2 high, 3 ultra). Applies the static parts
## (shadow atlas / splits / filter, SSAO, SSIL, SDFGI, volumetric fog grid) and returns the caps the
## environment controller respects every frame.

const SHADOW_ATLAS: Array[int] = [2048, 4096, 4096, 8192]
const SHADOW_DISTANCE: Array[float] = [240.0, 320.0, 400.0, 450.0]
const SOFT_FILTER: Array[int] = [
	RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
	RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH,
]


static func apply(env: Environment, lights: Array[DirectionalLight3D], q: int) -> Dictionary:
	q = clampi(q, 0, 3)
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[q], true)
	RenderingServer.directional_soft_shadow_filter_set_quality(SOFT_FILTER[q])
	for l in lights:
		l.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q == 0 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		l.directional_shadow_max_distance = SHADOW_DISTANCE[q]
		l.directional_shadow_blend_splits = q >= 2
		l.directional_shadow_split_1 = 0.055 if q > 0 else 0.15
		l.directional_shadow_split_2 = 0.16
		l.directional_shadow_split_3 = 0.42
		l.directional_shadow_fade_start = 0.82
		l.shadow_bias = 0.03
		l.shadow_normal_bias = 1.4 if q < 3 else 1.1
	env.ssao_enabled = q >= 1
	if q >= 1:
		var sq: int = [RenderingServer.ENV_SSAO_QUALITY_LOW, RenderingServer.ENV_SSAO_QUALITY_LOW,
			RenderingServer.ENV_SSAO_QUALITY_MEDIUM, RenderingServer.ENV_SSAO_QUALITY_HIGH][q]
		RenderingServer.environment_set_ssao_quality(sq, q < 3, 0.5, 2, 50.0, 300.0)
	env.ssil_enabled = q >= 3
	if q >= 3:
		RenderingServer.environment_set_ssil_quality(RenderingServer.ENV_SSIL_QUALITY_MEDIUM, true, 0.5, 4, 50.0, 300.0)
	env.sdfgi_enabled = false
	if q >= 1:
		RenderingServer.environment_set_volumetric_fog_volume_size([64, 64, 96, 128][q], [48, 48, 64, 96][q])
		RenderingServer.environment_set_volumetric_fog_filter_active(q >= 2)
	RenderingServer.environment_glow_set_use_bicubic_upscale(q >= 2)
	return {
		"quality": q,
		"volumetric": q >= 1,
		"volumetric_always": q >= 2,
		"volumetric_length": [0.0, 90.0, 140.0, 180.0][q],
		"ssr": q >= 2,
		"lights": [8, 12, 16, 16][q],
	}
