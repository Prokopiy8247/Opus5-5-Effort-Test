import json, struct, os, sys, math

D = r"W:\YouTube\Opus 5.5 Effort Test\6. Opus 5.5 Forza Ultracode Effort\6.-opus-5.5-forza-ultracode-effort\assets\imported\cars"
IDS = ["kestrel_r4", "aurelia_sedan", "brute_68", "sora_s2", "castellan_gt", "vortex_x",
       "granite_rally", "ridgeback_sx", "hauler_2500", "lark_roadster"]
REQ = ["Body", "Glass", "Interior", "SteeringWheel", "Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR",
       "Caliper_FL", "Caliper_FR", "Caliper_RL", "Caliper_RR", "Lights_Head", "Lights_Tail", "Lights_Brake",
       "Lights_Reverse", "Socket_HeadlightL", "Socket_HeadlightR", "Socket_Exhaust", "Socket_CamHood",
       "Socket_CamCockpit", "Socket_CamBumper"]
BUDGET = {"Body": 30000, "Interior": 10000, "Wheel": 3500, "total": 60000}


def read_glb(p):
    b = open(p, 'rb').read()
    magic, ver, length = struct.unpack_from('<III', b, 0)
    assert magic == 0x46546C67, 'bad magic'
    off = 12
    js = None; binc = None
    while off < length:
        clen, ctype = struct.unpack_from('<II', b, off)
        data = b[off + 8: off + 8 + clen]
        if ctype == 0x4E4F534A:
            js = json.loads(data.decode('utf-8'))
        elif ctype == 0x004E4942:
            binc = data
        off += 8 + clen
    return js, binc, len(b), length


def quat_ident(q):
    return q is None or (abs(q[0]) < 1e-5 and abs(q[1]) < 1e-5 and abs(q[2]) < 1e-5 and abs(abs(q[3]) - 1) < 1e-5)


for cid in IDS:
    out = []
    gp = os.path.join(D, cid + '.glb'); jp = os.path.join(D, cid + '.json')
    print('=' * 20, cid)
    if not os.path.exists(gp): print('  MISSING GLB'); continue
    if not os.path.exists(jp): print('  MISSING JSON'); continue
    g, binc, flen, hlen = read_glb(gp)
    J = json.load(open(jp, encoding='utf-8'))
    print('  glb bytes', flen, 'header len', hlen, 'json bytes', os.path.getsize(jp))
    print('  extensionsUsed', g.get('extensionsUsed'), 'cameras', len(g.get('cameras', [])),
          'animations', len(g.get('animations', [])), 'lights', g.get('extensions', {}).get('KHR_lights_punctual'))
    nodes = g['nodes']
    names = [n.get('name') for n in nodes]
    missing = [r for r in REQ if r not in names]
    extra = [n for n in names if n not in REQ and n not in (cid, 'Socket_Exhaust2')]
    print('  nodes', len(nodes), 'missing', missing, 'extra', extra)
    scene = g['scenes'][g.get('scene', 0)]
    roots = [nodes[i].get('name') for i in scene['nodes']]
    print('  scene roots', roots)
    root = [n for n in nodes if n.get('name') == cid]
    if root:
        r = root[0]
        print('  root T', r.get('translation'), 'R', r.get('rotation'), 'S', r.get('scale'), 'children', len(r.get('children', [])))
    # tris per mesh node
    acc = g['accessors']
    tris = {}
    wheel_bottom = {}
    for n in nodes:
        if 'mesh' not in n: continue
        m = g['meshes'][n['mesh']]
        t = 0
        ymin = 1e9
        for p in m['primitives']:
            mode = p.get('mode', 4)
            if 'indices' in p:
                c = acc[p['indices']]['count']
            else:
                c = acc[p['attributes']['POSITION']]['count']
            if mode == 4: t += c // 3
            pa = acc[p['attributes']['POSITION']]
            ymin = min(ymin, pa['min'][1])
            for need in ('NORMAL', 'TEXCOORD_0'):
                if need not in p['attributes']:
                    print('   !! mesh', n['name'], 'primitive missing', need)
        tris[n['name']] = t
        if n['name'].startswith('Wheel_'):
            T = n.get('translation', [0, 0, 0])
            wheel_bottom[n['name']] = (T, ymin + T[1], n.get('rotation'), n.get('scale'))
    tot = sum(tris.values())
    print('  glb tris', {k: v for k, v in tris.items() if k in ('Body', 'Interior', 'Glass', 'SteeringWheel', 'Wheel_FL')}, 'total', tot)
    jt = J.get('tris', {})
    print('  json tris total', jt.get('total'), 'Body', jt.get('Body'), 'Interior', jt.get('Interior'))
    flags = []
    if tris.get('Body', 0) > BUDGET['Body']: flags.append('Body over budget %d' % tris['Body'])
    if tris.get('Interior', 0) > BUDGET['Interior']: flags.append('Interior over budget %d' % tris['Interior'])
    for w in ('Wheel_FL', 'Wheel_FR', 'Wheel_RL', 'Wheel_RR'):
        if tris.get(w, 0) > BUDGET['Wheel']: flags.append('%s over budget %d' % (w, tris[w]))
    if tot > BUDGET['total']: flags.append('total over budget %d' % tot)
    for k, v in jt.items():
        if k != 'total' and k in tris and tris[k] != v: flags.append('json tris mismatch %s %s vs glb %s' % (k, v, tris[k]))
    if jt.get('total') != tot: flags.append('json total %s != glb %s' % (jt.get('total'), tot))
    for w, (T, yb, R, S) in sorted(wheel_bottom.items()):
        print('   ', w, 'T', [round(x, 4) for x in T], 'tyre bottom y', round(yb, 4), 'rot', R, 'scale', S)
        if abs(yb) > 0.003: flags.append('%s tyre bottom y=%.4f' % (w, yb))
        if not quat_ident(R): flags.append('%s has rotation %s' % (w, R))
        if S and any(abs(s - 1) > 1e-5 for s in S): flags.append('%s has scale %s' % (w, S))
        jw = J['wheels'].get(w.split('_')[1])
        if jw and any(abs(a - b) > 0.002 for a, b in zip(jw, T)): flags.append('%s json %s != glb %s' % (w, jw, T))
    # symmetry
    W = J['wheels']
    if abs(W['FL'][0] + W['FR'][0]) > 1e-3 or abs(W['RL'][0] + W['RR'][0]) > 1e-3: flags.append('wheel X asymmetric')
    if abs(W['FL'][2] - W['FR'][2]) > 1e-3 or abs(W['RL'][2] - W['RR'][2]) > 1e-3: flags.append('wheel Z asymmetric')
    if not (W['FL'][2] < 0 and W['RL'][2] > 0): flags.append('forward not -z (FL z=%s RL z=%s)' % (W['FL'][2], W['RL'][2]))
    if not (W['FL'][0] < 0 and W['FR'][0] > 0): flags.append('left/right swapped')
    wb = W['RL'][2] - W['FL'][2]
    if abs(wb - J['wheelbase']) > 0.01: flags.append('wheelbase json %.3f vs wheels %.3f' % (J['wheelbase'], wb))
    if abs((W['FR'][0] - W['FL'][0]) - J['track_front']) > 0.01: flags.append('track_front mismatch')
    if abs((W['RR'][0] - W['RL'][0]) - J['track_rear']) > 0.01: flags.append('track_rear mismatch')
    if abs(W['FL'][1] - J['wheel_radius_front']) > 0.003: flags.append('front wheel centre y != radius')
    if abs(W['RL'][1] - J['wheel_radius_rear']) > 0.003: flags.append('rear wheel centre y != radius')
    # midpoint origin
    if abs(W['FL'][2] + W['RL'][2]) > 0.01: flags.append('origin not mid-axle (FLz %s RLz %s)' % (W['FL'][2], W['RL'][2]))
    # keys
    for k in ["id", "name", "length", "width", "height", "wheelbase", "track_front", "track_rear", "wheel_radius_front",
              "wheel_radius_rear", "wheel_width_front", "wheel_width_rear", "wheels", "sockets", "body_aabb", "tris", "materials"]:
        if k not in J: flags.append('json missing key ' + k)
    for s in ('Socket_CamCockpit', 'Socket_CamHood', 'Socket_CamBumper', 'Socket_HeadlightL', 'Socket_HeadlightR', 'Socket_Exhaust'):
        if s not in J.get('sockets', {}): flags.append('json missing socket ' + s)
    # sockets vs glb nodes
    for s, v in J.get('sockets', {}).items():
        nn = [n for n in nodes if n.get('name') == s]
        if nn:
            T = nn[0].get('translation', [0, 0, 0])
            if any(abs(a - b) > 0.002 for a, b in zip(v, T)): flags.append('socket %s json %s != glb %s' % (s, v, T))
    hl = J['sockets'].get('Socket_HeadlightL'); hr = J['sockets'].get('Socket_HeadlightR')
    if hl and hr and not (hl[0] < 0 < hr[0]): flags.append('headlight L/R sides wrong')
    if hl and hl[2] > 0: flags.append('headlights at rear?')
    ex = J['sockets'].get('Socket_Exhaust')
    # materials
    mats = g.get('materials', [])
    glass = [m for m in mats if m['name'].startswith('Glass')]
    for m in glass:
        print('  glass mat', m['name'], m.get('alphaMode'), m.get('pbrMetallicRoughness', {}).get('baseColorFactor'), 'doubleSided', m.get('doubleSided'))
        if m.get('alphaMode') != 'BLEND': flags.append('Glass alphaMode %s' % m.get('alphaMode'))
    emis = {m['name']: (m.get('emissiveFactor'), m.get('extensions', {}).get('KHR_materials_emissive_strength')) for m in mats if 'Lens' in m['name']}
    print('  lens emissive', emis)
    print('  materials', sorted(m['name'] for m in mats))
    print('  body_aabb', J['body_aabb'], 'L/W/H', J['length'], J['width'], J['height'], 'WB', J['wheelbase'], 'tracks', J['track_front'], J['track_rear'], 'radius', J['wheel_radius_front'], J['wheel_radius_rear'], 'width', J['wheel_width_front'], J['wheel_width_rear'])
    print('  sockets', J['sockets'])
    print('  images', len(g.get('images', [])), 'textures', len(g.get('textures', [])))
    print('  FLAGS:', flags if flags else 'none')
