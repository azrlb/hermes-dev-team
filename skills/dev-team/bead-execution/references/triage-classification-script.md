# Triage Classification Script

Systematic Python script for classifying all open beads by implementability.
Use this when `bd ready --json` returns a large queue (10+ beads) and manual
inspection of each `bd show` output is too slow.

## The Script

```bash
bd ready --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)

# Adjust these keyword lists per project/ecosystem
cross_kw = ['@flowincash/', 'core package', 'core-', 'tiered light', 'strategy', 'cashflow']
human_kw = ['bob-owned', 'bob sign', 'legal review', 'ux designer', 'ux refresh',
            'app store', 'appsumo', 'playback sign', 'video producer', 'listing copy',
            'submit to', 'designer creates', 'sally reviews', 'screenshots', 'endcard', 'teaser']
infra_kw = ['dns:', 'delete route 53', 'railway']
# Placeholder beads: empty descriptions or wprl (will populate later)
placeholder_kw = ['wprl']
# Release-cycle-gated: explicitly blocked until Bob confirms metrics
gate_kw = ['do not execute until bob', 'post-beta', 'release-cycle-gated']

for b in data:
    p = str(b.get('priority', '?'))
    t = (b.get('title','') + ' ' + b.get('description','')).lower()
    bid = b['id']
    desc = (b.get('description','') or '').strip()
    
    is_epic = 'epic:' in str(b.get('labels',[])).lower() or t.startswith('epic:')
    is_cross = any(kw in t for kw in cross_kw)
    is_human = any(kw in t for kw in human_kw)
    is_infra = any(kw in t for kw in infra_kw)
    is_deferred = 'deferred' in t[:200]
    # Empty description OR contains placeholder keywords
    is_placeholder = (not desc) or desc == '(none)' or any(kw in t for kw in placeholder_kw)
    is_gated = any(kw in t for kw in gate_kw)
    
    reasons = []
    if p == '0': reasons.append('P0')
    if is_epic: reasons.append('epic')
    if is_cross: reasons.append('cross-repo')
    if is_human: reasons.append('human')
    if is_infra: reasons.append('infra')
    if is_deferred: reasons.append('deferred')
    if is_placeholder: reasons.append('placeholder')
    if is_gated: reasons.append('gated')
    
    status = 'IMPL' if not reasons else ','.join(reasons)
    print(f'{bid}  P{p}  {status}')
"
```

## Output Interpretation

| Output | Meaning |
|--------|---------|
| `IMPL` | Candidate for implementation — investigate further |
| `P0` | Skip per drain priority rules |
| `epic` | Epic marker — needs decomposition into child stories |
| `cross-repo` | Requires packages/API from another repo — blocked |
| `human` | Requires human action (video, design, legal, Bob sign-off) |
| `infra` | Infrastructure/ops task — usually Bob-owned |
| `deferred` | Explicitly deferred — do not implement |
| `placeholder` | Empty description or wprl (will-populate-later) — needs triage info first |
| `gated` | Release-cycle-gated or explicitly blocked until Bob confirms metrics |
| `cross-repo,human` | Blocked by BOTH — skip |

## Customizing Keywords

The keyword lists (`cross_kw`, `human_kw`, `infra_kw`, `placeholder_kw`, `gate_kw`) are project-specific.
Before running, adjust them to match your ecosystem:

- **cross_kw**: Package names, repo names, and feature names that live in other repos
- **human_kw**: Signal phrases that indicate non-code work (sign-offs, video, design)
- **infra_kw**: Infrastructure tasks (DNS, deployment, Railway config)
- **placeholder_kw**: Titles/descriptions indicating beads that will be filled in later (e.g., `wprl` = will populate later)
- **gate_kw**: Phrases indicating release-cycle or metrics gating (e.g., `post-beta`, `do not execute until Bob`)

## Bulk Counting

After classification, count implementable vs total:

```bash
bd ready --json 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
cross_kw = ['@flowincash/', 'core package', 'tiered light', 'strategy', 'cashflow']
human_kw = ['bob-owned', 'legal review', 'ux designer', 'app store', 'appsumo',
            'video producer', 'listing copy', 'submit to', 'screenshots']
placeholder_kw = ['wprl']
gate_kw = ['do not execute until bob', 'post-beta', 'release-cycle-gated']
impl = 0
blocked = 0
for b in data:
    t = (b.get('title','') + ' ' + b.get('description','')).lower()
    desc = (b.get('description','') or '').strip()
    is_placeholder = (not desc) or desc == '(none)' or any(kw in t for kw in placeholder_kw)
    is_blocked = (b.get('priority') == 0 or
                  any(kw in t for kw in cross_kw) or
                  any(kw in t for kw in human_kw) or
                  any(kw in t for kw in gate_kw) or
                  is_placeholder or
                  'epic:' in str(b.get('labels',[])).lower())
    if is_blocked: blocked += 1
    else: impl += 1
print(f'Implementable: {impl}, Blocked: {blocked}, Total: {len(data)}')
"
```

If `Implementable` is 0, the drain has hit pool exhaustion.

## Also Check In-Progress Beads

Don't forget beads that are `in_progress` from prior sessions:

```bash
bd list --status in_progress 2>/dev/null
```

These may be stale (code complete but not closed) or genuinely blocked.
Check each with `bd show <id>` and classify the same way.
