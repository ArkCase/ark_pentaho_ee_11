"""Rules shared by the patch-list generators (get-karaf-patches, get-jar-patches).

Nothing here is specific to one report, image, project or library: which bundles
belong together and the version they move to are worked out from the data alone.
Both generators import this module from their own directory.
"""

import json
import re
from collections import defaultdict

# Severity names as Trivy spells them, plus the short forms the user asked for.
SEV_RANK = {'CRITICAL': 5, 'HIGH': 4, 'MEDIUM': 3, 'LOW': 2, 'UNKNOWN': 1}
SEV_ALIAS = {'CRIT': 'CRITICAL', 'CRITICAL': 'CRITICAL', 'HIGH': 'HIGH',
             'MED': 'MEDIUM', 'MEDIUM': 'MEDIUM', 'LOW': 'LOW',
             'UNK': 'UNKNOWN', 'UNKNOWN': 'UNKNOWN'}
DEFAULT_LEVELS = 'HIGH,CRIT'            # what the applier patches unless told otherwise
JUMP_RANK = {'patch': 1, 'minor': 2, 'major': 3}

# Two groupIds belong to one project when they are equal or share at least this
# many leading segments (com.fasterxml.jackson.core / com.fasterxml.jackson.jaxrs).
# Two segments is only an organisation (org.apache, org.springframework), which
# hosts many independently released projects, so it does not count.
MIN_SHARED_SEGMENTS = 3


def sev_name(s):
    return SEV_ALIAS.get((s or '').strip().upper(), 'UNKNOWN')


def max_sev(names):
    names = [n for n in names if n]
    return max(names, key=lambda s: SEV_RANK.get(s, 0)) if names else None


def related(g1, g2):
    if g1 == g2:
        return True
    n = 0
    for x, y in zip(g1.split('.'), g2.split('.')):
        if x != y:
            break
        n += 1
    return n >= MIN_SHARED_SEGMENTS


def common_group(groups):
    """Longest dotted groupId prefix shared by all the given groupIds."""
    parts = [g.split('.') for g in groups]
    out = []
    for segs in zip(*parts):
        if len(set(segs)) != 1:
            break
        out.append(segs[0])
    return '.'.join(out) or '(mixed)'


def vtuple(s):
    return tuple(int(p) for p in re.findall(r'\d+', s)) or (0,)


def vstr(t):
    return '.'.join(str(x) for x in t)


def jump_kind(cur, tgt):
    a, b = vtuple(cur), vtuple(tgt)
    if a[0] != b[0]:
        return 'major'
    if len(a) < 2 or len(b) < 2 or a[1] != b[1]:
        return 'minor'
    return 'patch'


def gav(k):
    return '%s:%s:%s' % k


def tidy(e):
    return {k: v for k, v in e.items() if v not in (None, [], '')}


# ---------------------------------------------------------------- the report
PURL_RE = re.compile(r'pkg:maven/([^/]+)/([^@?#]+)@([^?#]+)(?:\?([^#]*))?')


def purl_qualifiers(q):
    return dict(kv.split('=', 1) for kv in (q or '').split('&') if '=' in kv)


def read_report(path):
    """(report, entries). Every Maven entry of the report as (key, path, vuln, quals):
    key is (groupId, artifactId, version) from the PURL; vuln is the Vulnerabilities
    record, or None for a Packages record; quals are the PURL qualifiers (classifier,
    type, ...). Coordinates come only from here."""
    report = json.load(open(path))
    entries = []
    for res in report.get('Results') or report.get('results') or []:
        for v in (res.get('Vulnerabilities') or res.get('vulnerabilities') or []):
            m = PURL_RE.match((v.get('PkgIdentifier') or {}).get('PURL') or v.get('Purl') or '')
            if m:
                entries.append(((m.group(1), m.group(2), v.get('InstalledVersion') or m.group(3)),
                                v.get('PkgPath') or v.get('FilePath') or '', v, purl_qualifiers(m.group(4))))
        for pk in (res.get('Packages') or []):
            m = PURL_RE.match((pk.get('Identifier') or {}).get('PURL') or '')
            if m and pk.get('FilePath'):
                entries.append(((m.group(1), m.group(2), pk.get('Version') or m.group(3)), pk['FilePath'], None,
                                purl_qualifiers(m.group(4))))
    return report, entries


def coordinate(g, a, v, classifier=None, typ=None):
    """Maven coordinate in mvn-get's spec order, groupId:artifactId:version[:type[:classifier]];
    the type is only written when it is not jar or a classifier follows it."""
    out = '%s:%s:%s' % (g, a, v)
    if classifier:
        return '%s:%s:%s' % (out, typ or 'jar', classifier)
    return '%s:%s' % (out, typ) if typ and typ != 'jar' else out


def add_vuln(vulns, k, v):
    """Merge one Vulnerabilities record into vulns[(g, a, v)]: per CVE, the union of
    its fixed versions and its highest severity."""
    c = vulns.setdefault(k, {'cves': {}})['cves'].setdefault(
        v.get('VulnerabilityID'), {'fixes': set(), 'severity': 'UNKNOWN'})
    c['fixes'].update(x.strip() for x in (v.get('FixedVersion') or '').split(',') if x.strip())
    c['severity'] = max_sev([c['severity'], sev_name(v.get('Severity'))])


def sev_of(vulns, k):
    return max_sev(c['severity'] for c in vulns[k]['cves'].values())


# ---------------------------------------------------------------- targets
def pick_target(line_mm, cve_fix_sets):
    """The major.minor to land on is the installed one when every CVE has a fix
    there (patch move); otherwise the lowest same-major minor at which every CVE
    is fixed (minor move). Within that major.minor the LATEST fix offered for any
    member is taken. None: some CVE has no fix on this major."""
    need = []
    for fs in cve_fix_sets:
        same = sorted((f for f in fs if vtuple(f)[0] == line_mm[0] and vtuple(f)[:2] >= line_mm), key=vtuple)
        if not same:
            return None
        need.append(same[0])
    mm = max(vtuple(f)[:2] for f in need)
    return max((f for fs in cve_fix_sets for f in fs if vtuple(f)[:2] == mm), key=vtuple)


def pick_any(line_mm, cve_fix_sets):
    """pick_target on the installed major, else on the lowest higher major where
    every CVE is fixed (a major move)."""
    t = pick_target(line_mm, cve_fix_sets)
    if t:
        return t
    for major in sorted({vtuple(f)[0] for fs in cve_fix_sets for f in fs if vtuple(f)[0] > line_mm[0]}):
        t = pick_target((major, 0), cve_fix_sets)
        if t:
            return t
    return None


# ---------------------------------------------------------------- grouping
def plan(nodes, vulns, unpatchable):
    """Work out the groups. nodes: every (g, a, v) in scope (vulnerable or not);
    vulns: the vulnerable ones with their CVEs; unpatchable: a set the findings no
    group can address are added to. Returns (groups, already): each group is
    {'name', 'target', 'members', 'gjump', 'severity', 'split_of'} - split_of names
    the group it was split from, or None - and already lists (key, target) for
    vulnerable bundles already at or above their target."""
    nodes = sorted(nodes)

    # ---- releases: bundles that belong together, found from the data alone ----
    #   - same version and related groupIds (equal, or MIN_SHARED_SEGMENTS shared):
    #     released together, e.g. every artifact of one project release
    #   - same groupId:artifactId on the same major: another copy of the same artifact,
    #     which must move with it ("patched in one place, patched everywhere")
    parent = {k: k for k in nodes}

    def find(k):
        while parent[k] != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    def union(x, y):
        rx, ry = find(x), find(y)
        if rx != ry:
            parent[max(rx, ry)] = min(rx, ry)

    by_version, by_artifact = defaultdict(list), defaultdict(list)
    for k in nodes:
        by_version[k[2]].append(k)
        by_artifact[(k[0], k[1], vtuple(k[2])[0])].append(k)
    for ks in by_version.values():
        for i, x in enumerate(ks):
            for y in ks[i + 1:]:
                if related(x[0], y[0]):
                    union(x, y)
    for ks in by_artifact.values():
        for y in ks[1:]:
            union(ks[0], y)
    #   - families: a release whose members span two or more related groupIds (a
    #     project publishing under several sub-groupIds with one version, like
    #     a.b.c.core + a.b.c.module) marks those groupIds as one family. Any other
    #     bundle in one of those exact groupIds on the same major moves with it
    #     ("all jars of a family in lockstep"). A release under a single groupId marks
    #     nothing: one groupId often hosts independently versioned projects.
    for v, ks in by_version.items():
        clusters = []
        for k in ks:
            for c in clusters:
                if any(related(k[0], m[0]) for m in c):
                    c.append(k)
                    break
            else:
                clusters.append([k])
        for c in clusters:
            gids = {k[0] for k in c}
            if len(gids) < 2:
                continue
            for x in nodes:
                if x[0] in gids and vtuple(x[2])[0] == vtuple(v)[0]:
                    union(c[0], x)
    releases = defaultdict(list)
    for k in nodes:
        releases[find(k)].append(k)

    # ---- one target per release: every CVE of every vulnerable member is fixed ----
    already, units = [], []        # units: {'target', 'members': [(g, a, v)]}
    for _, ks in sorted(releases.items()):
        vuln = [k for k in ks if k in vulns]
        if not vuln:
            continue
        lines_ = defaultdict(list)
        for k in vuln:
            if any(c['fixes'] for c in vulns[k]['cves'].values()):
                lines_[vtuple(k[2])[:2]].append(k)
            else:
                unpatchable.add('%s - no fixed version reported' % gav(k))
        targets = []
        for mm, arts in sorted(lines_.items()):
            t = pick_any(mm, [c['fixes'] for k in arts for c in vulns[k]['cves'].values() if c['fixes']])
            if t:
                targets.append(t)
            else:
                for k in arts:
                    unpatchable.add('%s - no single major line fixes every CVE' % gav(k))
        if not targets:
            continue
        target = max(targets, key=vtuple)
        members = []
        for k in ks:
            if vtuple(k[2]) < vtuple(target):
                members.append(k)
            elif k in vulns:
                already.append((k, target))
        if any(k in vulns for k in members):
            units.append({'target': target, 'members': members})

    # ---- releases of related groupIds that land on the same target are one group ----
    up = list(range(len(units)))

    def ufind(i):
        while up[i] != i:
            up[i] = up[up[i]]
            i = up[i]
        return i
    for i, x in enumerate(units):
        for j in range(i + 1, len(units)):
            y = units[j]
            if x['target'] == y['target'] and any(related(a[0], b[0]) for a in x['members'] for b in y['members']):
                up[max(ufind(i), ufind(j))] = min(ufind(i), ufind(j))
    merged = defaultdict(list)
    for i, u in enumerate(units):
        merged[ufind(i)].extend(u['members'])
    units = [{'target': units[i]['target'], 'members': sorted(set(ms))} for i, ms in sorted(merged.items())]

    # ---- split off members with no CVE whose jump is larger than the vulnerable ones' ----
    final = []                     # {'target', 'members', 'parent', 'mm'}
    for u in units:
        vj = max((jump_kind(k[2], u['target']) for k in u['members'] if k in vulns), key=lambda j: JUMP_RANK[j])
        keep, split = [], defaultdict(list)
        for k in u['members']:
            if k not in vulns and JUMP_RANK[jump_kind(k[2], u['target'])] > JUMP_RANK[vj]:
                split[vtuple(k[2])[:2]].append(k)
            else:
                keep.append(k)
        main_i = len(final)
        final.append(dict(u, members=keep, parent=None, mm=None))
        for mm, ms in sorted(split.items()):
            final.append(dict(u, members=ms, parent=main_i, mm=mm))

    # ---- names: the members' shared groupId (last segment), or the artifactId ----
    names, used = [], set()
    for u in final:
        if u['mm'] is not None:
            base = '%s-%s' % (names[u['parent']], '.'.join(str(x) for x in u['mm']))
        else:
            arts = sorted({k[1] for k in u['members']})
            cg = common_group(k[0] for k in u['members'])
            base = arts[0] if len(arts) == 1 or cg == '(mixed)' else cg.split('.')[-1]
        name = base if base not in used else '%s-%s' % (base, u['target'])
        used.add(name)
        names.append(name)

    groups = []
    for i, u in enumerate(final):
        par = final[u['parent']] if u['mm'] is not None else None
        groups.append({
            'name': names[i], 'target': u['target'], 'members': u['members'],
            'gjump': max((jump_kind(k[2], u['target']) for k in u['members']), key=lambda j: JUMP_RANK[j]),
            # a split-off group addresses no CVE itself: it carries its parent's severity
            'severity': max_sev(sev_of(vulns, k) for k in (par['members'] if par else u['members']) if k in vulns),
            'split_of': names[u['parent']] if par else None,
        })
    return groups, already


def base_notes(g):
    """Why a group is disabled by default, as far as the shared rules can tell."""
    notes = []
    if g['split_of']:
        notes.append('members of %s with no CVE of their own, on an older line' % g['split_of'])
    if g['gjump'] != 'patch':
        olds = sorted({k[2] for k in g['members']}, key=vtuple)
        notes.append('%s version jump (%s -> %s)' % (g['gjump'], ', '.join(olds), g['target']))
    return notes


def stuck_copies(g, elsewhere):
    """Related copies the group's method cannot reach (repackaged, renamed, nested):
    same version and related groupId as a member, or another copy of a member's
    groupId:artifactId. They stay on their version."""
    vers, gas = {k[2] for k in g['members']}, {k[:2] for k in g['members']}
    return sorted(p.rsplit('/', 1)[-1] for k, ps in elsewhere.items()
                  if (k[2] in vers and any(related(k[0], m[0]) for m in g['members'])) or k[:2] in gas
                  for p in ps)


# ---------------------------------------------------------------- YAML output
# A plain scalar is written unquoted unless YAML would read it as something else
# (a number, bool, null) or its characters need quoting. Versions are always quoted
# so that 1.10 stays "1.10" for any YAML reader, not the float 1.1.
UNSAFE_PLAIN = re.compile(r'^[\s\-?:,\[\]{}#&*!|>\'"%@`]|: | #|\s$|^$')
NOT_A_STRING = re.compile(r'^(~|null|Null|NULL|true|True|TRUE|false|False|FALSE|y|Y|yes|Yes|YES|'
                          r'n|N|no|No|NO|on|On|ON|off|Off|OFF|'
                          r'[-+]?(\.[0-9]+|[0-9][0-9_]*(\.[0-9_]*)?)([eE][-+]?[0-9]+)?|'
                          r'0x[0-9a-fA-F]+|0o[0-7]+|[-+]?\.(inf|Inf|INF)|\.(nan|NaN|NAN))$')
VERSION_KEYS = ('current', 'target', 'candidates')


def scalar(v, quote=False):
    if v is None:
        return 'null'
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, list):
        return '[]'                          # only empty containers get here
    if isinstance(v, dict):
        return '{}'
    s = str(v)
    if quote or '\n' in s or UNSAFE_PLAIN.search(s) or NOT_A_STRING.match(s):
        return json.dumps(s)                 # a JSON string is a valid YAML double-quoted scalar
    return s


PLAIN_KEY = re.compile(r'^[A-Za-z_][^\s"\'#]*$')


def key(k):
    """A mapping key: plain when it is safe (coordinates like g:a:v included - a colon
    not followed by a space does not end a key), double-quoted otherwise."""
    k = str(k)
    if PLAIN_KEY.match(k) and not k.endswith(':') and not NOT_A_STRING.match(k):
        return k
    return json.dumps(k)


def dump_node(v, ind, quote=False):
    pad = ' ' * ind
    out = []
    if isinstance(v, dict):
        for k, x in v.items():
            q = k in VERSION_KEYS
            if isinstance(x, (dict, list)) and x:
                out.append('%s%s:' % (pad, key(k)))
                out += dump_node(x, ind + 2, q)
            else:
                out.append('%s%s: %s' % (pad, key(k), scalar(x, q)))
    else:
        for x in v:
            if isinstance(x, dict) and x:
                sub = dump_node(x, ind + 2, quote)
                sub[0] = pad + '- ' + sub[0].lstrip()
                out += sub
            elif isinstance(x, list) and x:
                out.append(pad + '-')
                out += dump_node(x, ind + 2, quote)
            else:
                out.append('%s- %s' % (pad, scalar(x, quote)))
    return out


def yaml_dump(doc, top_comment):
    out = ['# ' + l if l else '#' for l in top_comment.split('\n')]
    for key, val in doc.items():
        out.append('')
        if isinstance(val, list) and val:
            out.append('%s:' % key)
            for i, item in enumerate(val):
                if i:
                    out.append('')           # one blank line between blocks
                out += dump_node([item], 2)
        elif isinstance(val, dict) and val and key == 'groups':
            out.append('%s:' % key)
            for i, (k, x) in enumerate(val.items()):
                if i:
                    out.append('')
                out += dump_node({k: x}, 2)
        else:
            out += dump_node({key: val}, 0)
    return '\n'.join(out) + '\n'
