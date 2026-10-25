export const meta = {
  name: 'sunward-review',
  description: 'Find real bugs/perf problems per subsystem, adversarially verify each finding',
  phases: [
    { title: 'Find', detail: 'one reviewer per area' },
    { title: 'Verify', detail: 'two skeptics per finding' },
  ],
}

const P = 'W:\\YouTube\\Opus 5.5 Effort Test\\6. Opus 5.5 Forza Ultracode Effort\\6.-opus-5.5-forza-ultracode-effort'
const GD = 'W:\\Godot_v4.7.2-stable_win64.exe\\Godot_v4.7.2-stable_win64_console.exe'

const COMMON = `You are reviewing "Sunward Roads", an original Godot 4.7.2 GDScript open-world racing game at ${P}. Read docs/SYSTEM_CONTRACTS.md first for the architecture. Your job: find REAL defects in your assigned area - crashes/script errors, wrong behaviour vs the documented contract, state bugs (e.g. overlay counters, paused state, signals connected twice, freed-object access), resource/node leaks (nodes or RIDs not freed, WorkerThreadPool tasks never waited), thread-safety violations (scene tree or RenderingServer/PhysicsServer calls from worker threads, unsynchronised shared data), per-frame performance problems (O(n^2) work in _process, allocations every frame, full rebuilds), gameplay-breaking edge cases (car switch / teleport / respawn / photo mode / pause interactions). Do NOT report style nits, naming, missing comments or speculative "could be cleaner" items. Every finding needs a concrete failure scenario (inputs/state -> wrong result) and the exact file:line. You may run the game briefly to confirm (wrap in timeout; e.g. \`timeout 150 "${GD}" --path . --resolution 1280x720 -- --qa=shots --targets="Sunward Festival" --views=0 --shot-dir=res://qa_output/review\` or \`--qa=drive --road=ring --minutes=1\`) - read the log for SCRIPT ERROR lines. Never edit project files, never run the editor or --import, never use Blender tools.`

const FINDINGS = { type: 'object', properties: { findings: { type: 'array', items: { type: 'object', properties: {
  file: { type: 'string' }, line: { type: 'integer' }, title: { type: 'string' }, scenario: { type: 'string' },
  severity: { type: 'string', enum: ['high', 'medium', 'low'] }, fix: { type: 'string' } },
  required: ['file', 'line', 'title', 'scenario', 'severity', 'fix'] } } }, required: ['findings'] }
const VERDICT = { type: 'object', properties: { real: { type: 'boolean' }, reason: { type: 'string' } }, required: ['real', 'reason'] }

const AREAS = [
  { key: 'vehicle', files: 'scripts/vehicle/*.gd (car_controller, car_factory, car_visuals, car_input, car_rewind, tuning, car_effects), scripts/camera/camera_rig.gd, scripts/main/main.gd' },
  { key: 'world', files: 'scripts/world/terrain_streamer.gd, road_builder.gd, world.gd, world_data.gd, road_network.gd (runtime only; the offline generator world_gen.gd is out of scope except where runtime code depends on it)' },
  { key: 'ui', files: 'scripts/ui/*.gd (HUD, minimap, world map, GPS, console, garage, debug, pause, photo mode) and scripts/core/*.gd' },
  { key: 'traffic_activities', files: 'scripts/traffic/*.gd and scripts/activities/*.gd' },
  { key: 'env_audio_fx_dressing', files: 'scripts/env/*.gd, scripts/audio/*.gd, scripts/fx/*.gd, scripts/world/dressing*.gd, settlements.gd, prop_library.gd' },
]

const results = await pipeline(AREAS,
  a => agent(`${COMMON}\n\nYOUR AREA: ${a.files}. Report at most 8 findings, most severe first, only ones you are confident are real.`, { label: `find:${a.key}`, phase: 'Find', schema: FINDINGS }),
  (r, a) => parallel((r && r.findings ? r.findings : []).map(f => () =>
    parallel([0, 1].map(k => () => agent(`${COMMON}\n\nAdversarially verify this reported defect. Read the code yourself and try to REFUTE it (wrong reading of the code, impossible state, already handled elsewhere, not actually harmful). Default to real=false if the scenario cannot actually happen.\nFILE: ${f.file}:${f.line}\nTITLE: ${f.title}\nSCENARIO: ${f.scenario}\nPROPOSED FIX: ${f.fix}`, { label: `verify:${a.key}:${k}`, phase: 'Verify', schema: VERDICT })))
      .then(vs => ({ ...f, area: a.key, votes: vs.filter(Boolean).map(v => v.real), reasons: vs.filter(Boolean).map(v => v.reason) }))
  ))
)
const all = results.filter(Boolean).flat().filter(Boolean)
const confirmed = all.filter(f => f.votes.filter(Boolean).length >= 2)
const disputed = all.filter(f => f.votes.filter(Boolean).length === 1)
return { confirmed, disputed, rejected: all.length - confirmed.length - disputed.length }
