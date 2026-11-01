"""Regex GDScript extractor for graphify (it has no .gd support). Appends to .graphify_ast.json.

Run from the project root with graphify's interpreter, right after /graphify's code extraction (Part A), while
graphify-out/.graphify_ast.json and .graphify_detect.json exist. It also removes images and audio from the detect
file, so the run spends nothing on textures and voice clips.

EXTRACTED: definitions, extends, preload/load, Class.func(), alias.func(), bare same-file func(), connect(handler).
INFERRED (0.75): obj.func() with an untyped receiver, only when exactly one file defines that name and it is not a
Godot built-in-looking name. Those are the guesses; everything else is literal in the source.
"""
import json, re
from collections import defaultdict
from pathlib import Path

ROOT = Path('.').resolve()
AST = Path('graphify-out/.graphify_ast.json')
DETECT = Path('graphify-out/.graphify_detect.json')

FUNC = re.compile(r'^(\t*)(?:static\s+)?func\s+([A-Za-z_]\w*)\s*\(')
CLASS_NAME = re.compile(r'^class_name\s+([A-Za-z_]\w*)')
EXTENDS = re.compile(r'^extends\s+([A-Za-z_]\w*|"[^"]+")')
INNER = re.compile(r'^(\t*)class\s+([A-Za-z_]\w*)')
ALIAS = re.compile(r'^(?:const|var)\s+([A-Za-z_]\w*)\s*(?::=|=)\s*(?:preload|load)\("res://([^"]+\.gd)"\)')
LOAD = re.compile(r'(?:preload|load)\("res://([^"]+\.gd)"\)')
DOTCALL = re.compile(r'\b([A-Za-z_]\w*)\.([A-Za-z_]\w*)\s*\(')
BARECALL = re.compile(r'(?<![\w.])([A-Za-z_]\w*)\s*\(')
CONNECT = re.compile(r'\.connect\(\s*([A-Za-z_]\w*)')
CLASSREF = re.compile(r'\b([A-Z][A-Za-z0-9_]*)\b\.')
STRING = re.compile(r'"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'')

# names a receiver may share with Godot's API: never treated as a unique project method
BUILTINS = set('''
add_child remove_child get_node queue_free free duplicate get set has size clear append push_back pop_back pop_front
erase find keys values is_empty normalized length distance_to dot cross lerp rotated connect disconnect emit call call_deferred
play stop start update process ready init reset begin end open close load save clear_all new create show hide
get_parent get_tree get_children look_at to_string instantiate resize sort shuffle min max abs floor ceil round
'''.split())


def stem(rel):
    return re.sub(r'[^a-z0-9_]', '_', rel[:-3].lower().replace('/', '_'))


def nid(*parts):
    return re.sub(r'[^a-z0-9_]', '_', '_'.join(parts).lower())


def clean(line):
    return STRING.sub('""', line).split('#', 1)[0]


files = {}
for p in sorted(ROOT.rglob('*.gd')):
    rel = p.relative_to(ROOT).as_posix()
    if rel.split('/')[0] in ('.godot', 'graphify-out', 'docs_backup', '.claude'):
        continue
    files[rel] = p.read_text(encoding='utf-8', errors='replace').splitlines()

nodes, edges, seen_nodes, seen_edges = [], [], set(), set()


def node(i, label, rel, line):
    if i not in seen_nodes:
        seen_nodes.add(i)
        nodes.append({'id': i, 'label': label, 'file_type': 'code', 'source_file': rel,
                      'source_location': f'L{line}', '_origin': 'ast'})


def edge(s, t, rel_name, rel, line, conf='EXTRACTED', score=1.0):
    if s == t or (s, t, rel_name) in seen_edges:
        return
    seen_edges.add((s, t, rel_name))
    edges.append({'source': s, 'target': t, 'relation': rel_name, 'confidence': conf, 'confidence_score': score,
                  'source_file': rel, 'source_location': f'L{line}', 'weight': 1.0, '_origin': 'ast'})


# first pass: definitions
class_file, file_funcs, funcs_by_name = {}, defaultdict(dict), defaultdict(set)
for rel, lines in files.items():
    fid = stem(rel)
    node(fid, Path(rel).name, rel, 1)
    for n, raw in enumerate(lines, 1):
        if m := CLASS_NAME.match(raw):
            class_file[m[1]] = rel
        elif m := INNER.match(raw):
            cid = nid(fid, m[2])
            node(cid, m[2], rel, n)
            edge(fid, cid, 'contains', rel, n)
        elif m := FUNC.match(raw):
            i = nid(fid, m[2])
            node(i, m[2] + '()', rel, n)
            edge(fid, i, 'contains', rel, n)
            file_funcs[rel][m[2]] = i
            funcs_by_name[m[2]].add(rel)

# second pass: references
for rel, lines in files.items():
    fid = stem(rel)
    aliases = {}
    current = fid
    for n, raw in enumerate(lines, 1):
        if m := ALIAS.match(raw):
            aliases[m[1]] = m[2]
        if m := FUNC.match(raw):
            current = file_funcs[rel][m[2]]
        elif raw and not raw[0].isspace():
            current = fid  # a top-level var/const belongs to the file
        for target in LOAD.findall(raw):
            if target in files:
                edge(fid, stem(target), 'imports', rel, n)
        line = clean(raw)
        if m := EXTENDS.match(raw):
            base = m[1].strip('"')
            base = base[6:] if base.startswith('res://') else class_file.get(base)
            if base in files:
                edge(fid, stem(base), 'inherits', rel, n)
        if FUNC.match(raw):
            continue
        dotted = set()
        for recv, name in DOTCALL.findall(line):
            dotted.add(name)
            target = class_file.get(recv) or aliases.get(recv)
            if target in files:
                if name in file_funcs[target]:
                    edge(current, file_funcs[target][name], 'calls', rel, n)
            elif recv != 'self' and name not in BUILTINS and len(funcs_by_name[name]) == 1:
                other = next(iter(funcs_by_name[name]))
                if other != rel:
                    edge(current, file_funcs[other][name], 'calls', rel, n, 'INFERRED', 0.75)
            elif recv == 'self' and name in file_funcs[rel]:
                edge(current, file_funcs[rel][name], 'calls', rel, n)
        for name in BARECALL.findall(line):
            if name in file_funcs[rel]:
                edge(current, file_funcs[rel][name], 'calls', rel, n)
        for name in CONNECT.findall(line):
            if name in file_funcs[rel]:
                edge(current, file_funcs[rel][name], 'references', rel, n)
        for cls in CLASSREF.findall(line):  # Game.SOME_CONST and the like
            if cls in class_file and class_file[cls] != rel:
                edge(fid, stem(class_file[cls]), 'references', rel, n)

ast = json.loads(AST.read_text(encoding='utf-8'))
ast['nodes'] += nodes
ast['edges'] += edges
AST.write_text(json.dumps(ast, indent=2, ensure_ascii=False), encoding='utf-8')

d = json.loads(DETECT.read_text(encoding='utf-8'))
d['files']['code'] += [str(ROOT / r) for r in files]
d['files']['image'] = []
d['files']['video'] = []
d['total_files'] = sum(len(v) for v in d['files'].values())
d['total_words'] = d.get('total_words', 0) + sum(len(' '.join(l).split()) for l in files.values())
DETECT.write_text(json.dumps(d, ensure_ascii=False), encoding='utf-8')

conf = defaultdict(int)
for e in edges:
    conf[e['relation'], e['confidence']] += 1
print(f'{len(files)} .gd files, {len(class_file)} class_names, {len(nodes)} nodes, {len(edges)} edges')
print(dict(conf))
