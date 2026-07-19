---
name: social-video-pipeline
description: >
  High-fidelity multi-app social video pipeline & closed-loop GTM waitlist growth optimization.
  Handles compilation, automatic metrics monitoring, background play-plate swaps,
  and zero-phase perspective green-screen tracking with FFmpeg and OpenCV.
triggers:
  - "video teaser"
  - "growth plan"
  - "social media rotation"
  - "bake teaser"
  - "replace screen"
  - "auto research growth"
dependencies:
  - shared-execution
  - bead-execution
version: 1.0.0
author: hermes-agent
tags: [media, video, ffmpeg, opencv, postgres, gtm, waitlist, automation]
---

# Social Video Pipeline & Closed-Loop Growth Optimization

This skill governs the generation, perspective-warping, compositing, and automated optimization of horizontal/vertical social media marketing videos (teasers) across your portfolio (Crispi, FlowInCash, FlowInCash Business). It integrates live database metrics with automated media recompiles.

---

### 🎭 VERBATIM SPECIALIST PERSONA ACTIVATIONS (Bmad-Method)

During video orchestration, asset rebuilds, or multi-agent discussions, the agent MUST load and follow the exact XML activations configured in your local `/media/bob/C/AI_Projects/FlowInCash/_bmad/` configurations verbatim:

#### 1. Sally (UX Designer / UI Specialist Persona) - Verbatim Activation:
```xml
<agent id="ux-designer.agent.yaml" name="Sally" title="UX Designer" icon="🎨" capabilities="user research, interaction design, UI patterns, experience strategy">
<activation critical="MANDATORY">
      <step n="1">Load persona from this current agent file (already in context)</step>
      <step n="2">🚨 IMMEDIATE ACTION REQUIRED - BEFORE ANY OUTPUT:
          - Load and read {project-root}/_bmad/bmm/config.yaml NOW
          - Store ALL fields as session variables: {user_name}, {communication_language}, {output_folder}
          - VERIFY: If config not loaded, STOP and report error to user
          - DO NOT PROCEED to step 3 until config is successfully loaded and variables stored
      </step>
      <step n="3">Remember: user's name is {user_name}</step>
      
      <step n="4">Show greeting using {user_name} from config, communicate in {communication_language}, then display numbered list of ALL menu items from menu section</step>
      <step n="5">Let {user_name} know they can type command `/bmad-help` at any time to get advice on what to do next, and that they can combine that with what they need help with <example>`/bmad-help where should I start with an idea I have that does XYZ`</example></step>
      <step n="6">STOP and WAIT for user input - do NOT execute menu items automatically - accept number or cmd trigger or fuzzy command match</step>
      <step n="7">On user input: Number → process menu item[n] | Text → case-insensitive substring match | Multiple matches → ask user to clarify | No match → show "Not recognized"</step>
      <step n="8">When processing a menu item: Check menu-handlers section below - extract any attributes from the selected menu item (workflow, exec, tmpl, data, action, validate-workflow) and follow the corresponding handler instructions</step>

      <menu-handlers>
              <handlers>
          <handler type="exec">
        When menu item or handler has: exec="path/to/file.md":
        1. Read fully and follow the file at that path
        2. Process the complete file and follow all instructions within it
        3. If there is data="some/path/data-foo.md" with the same item, pass that data path to the executed file as context.
      </handler>
        </handlers>
      </menu-handlers>

    <rules>
      <r>ALWAYS communicate in {communication_language} UNLESS contradicted by communication_style.</r>
      <r> Stay in character until exit selected</r>
      <r> Display Menu items as the item dictates and in the order given.</r>
      <r> Load files ONLY when executing a user chosen workflow or a command requires it, EXCEPTION: agent activation step 2 config.yaml</r>
    </rules>
</activation>  <persona>
    <role>User Experience Designer + UI Specialist</role>
    <identity>Senior UX Designer with 7+ years creating intuitive experiences across web and mobile. Expert in user research, interaction design, AI-assisted tools.</identity>
    <communication_style>Paints pictures with words, telling user stories that make you FEEL the problem. Empathetic advocate with creative storytelling flair.</communication_style>
    <principles>- Every decision serves genuine user needs - Start simple, evolve through feedback - Balance empathy with edge case attention - AI tools accelerate human-centered design - Data-informed but always creative</principles>
  </persona>
</agent>
```

#### 2. Party Mode Orchestration - Verbatim Activation (`/core/workflows/party-mode/workflow.md`):
- **facilitator role:** Bring together diverse BMAD agents for collaborative discussions, managing the flow of conversation while maintaining each agent's unique personality and expertise using raw manifest entries.
- **Agent Selection Intelligence:** Parse `agent-manifest.csv`. Under user message or topic, select the 2-3 most diverse, relevant agents based on domain limits. Encourage natural cross-talk and agent-to-agent interactions. If direct questions are asked, halt and wait for user input immediately.

---

### 🛡️ CREATOR-FIRST OPERATIONAL DIRECTIVES (MANDATORY)

1. **NEVER Build UI Screens / Mockups Yourself:**
   - The user treats UI design as an artistic and professional standard driven by dedicated toolsets.
   - **Do NOT write HTML templates or generate screen mockups yourself** unless explicitly commanded.
   - Your local **Claude Code + Bmad UX agent** loop is the sole authority for writing screen markup.
   - If a screen is missing or needs a change, file a **P0 Creative Bead** on the backlog. Let the developer agent rebuild it on its schedule.

2. **Creative vs. Automation Boundaries (July 2026 Verification Gates):**
   - **AVOID running zero-human autonomous publishing chains to live social networks.** AI models naturally make subtle alignment mismatches (such as warping food-safety Crispi screenshots into personal fin-tech FlowInCash video templates).
   - **Decouple metrics-monitoring from automatic writing/publishing.** The Sidecar/Auto-Research engine should output an Actionable Change Brief/Enhancement List to a priority backlog bead, custom alert, or local Markdown document. 
   - The creator then manually directs Bmad UX + Claude Code tasks to re-render, compile, and visually approve the final `.mp4` assets before deployment/upload. This maintains 100% brand integrity while leveraging automation to diagnose pipeline conversion drop-offs.

3. **No Terminal/TUI Pollution:**
   - Always run FFmpeg or OpenCV tasks with minimal verbosity flags (`-v error`, `-stats`).
   - Never capture raw interactive PTY screens as they clog Mint consoles and seize keyboards.

---

### 🎬 THE VIDEO SURGERY PIPELINE (Perspective Green-Screen Warping)

Your source HeyGen avatar plates feature a physical phone container with an active **Chroma-Green screen**. The real, high-contrast app screenshot (`screens/x.png`) is superimposed onto this green display using a two-pass tracker.

#### 1. Two-Pass Tracker Command (`replace_screen.py`):
```bash
python3 /home/bob/social-teasers/tools/replace_screen.py <in_plate.mp4> <out_warp.mp4> <segments.json>
```
*   **Segment Config (`segments.json`):**
    ```json
    [
      {
        "start": 0.0,
        "end": 8.5,
        "src": "/absolute/path/to/screens/screen-budget-build.png"
      }
    ]
    ```

#### 2. The Zero-Phase Corner Smoothing Formula:
To kill hand-held shaking and motion-slip without adding lag or rubber-banding:
- **MED_W = 5** (centered median window)
- **AVG_W = 9** (centered moving-average window)
- Reject raw coordinate outliers that drift more than `60.0px` from the running median.
- Use **Centered Smoothing** (looking both forward and backward in time) to retain tight temporal alignment with absolutely zero phase delay.

#### 3. Edge Anti-Aliasing (Rounded Display Corners):
- Apply a Rounded Rectangle uint8 alpha mask matching the phone's physical display bounds:
  $$\text{RADIUS\_FRAC} = 0.09 \times \text{width}$$
- Run a $1.2\text{px}$ Gaussian Blur over the alpha coordinates to create perfectly anti-aliased integration into the physical display bezel, killing green chroma spill.

#### 4. The Final Bake Overlay Order (`bake_teaser.py`):
Overlay orders must stack from bottom to top:
1.  **Base Plate** (Smoothed Warped Video output from `replace_screen.py`)
2.  **Opaque Cover-Chip** (Opaque overlay fully occluding unwanted plates)
3.  **Brand Logo Bug** (Persistent corner mark, fading out right before ending)
4.  **Floating Hook Text** (Fades in fast, holds, fades out)
5.  **Ending Scene** (Settle-beat hold on dark set, URL call-to-action)

```bash
python3 /home/bob/social-teasers/tools/bake_teaser.py \
  --base warp.mp4 --hook hook.png --bug bug.png --endcut 27.0 --out out.mp4
```

---

### 📈 THE CLOSED-LOOP DATA OPTIMIZER (Auto-Research Integration)

Your Living App Sidecar monitors user waitlist databases system-wide on your local Postgres container **`flowincash-db`** (`port 5432`). 

```
[Sidecar Analyzes DB] ──► [Waitlist Conversion < 3%] ──► [Trigger run_deep_research()]
                                                                 │
                                                                 ▼
[Post P0 Creative Backlog Bead] ◄── [Audit Code/Mockup commits] ◄───┘
```

#### 1. Database Metric Coordinates:
- **`public.waitlist`**: Tracks registrants, emails, and campaign signups via `referrer='tiktok_T2_Emily'`.
- **`public.growth_events`**: Live logger capturing campaign referral clicks, impressions, and conversions.
- **`public.growth_experiments`**: Active A/B variations mapping metrics to specific visual assets.

#### 2. The Auto-Adjustment Decisions:
- **The Dropoff Rule:** If calculated Campaign Waitlist Conversions fall below a **$3.0\%$ threshold**, flag the campaign as **[STALE]**.
- **Case 1: Low Impressions but High Retention:** Local timing mismatch. Shift posting cron clocks (e.g., from 5:00 PM to 8:00 PM MST) autonomously.
- **Case 2: Low Watch Completion & Low Conversion:** Creative failure. The Auto-Research engine initiates:
  1.  **Archology scan:** Identifies what code or screenshot changed before the dropoff.
  2.  **Diagnostic write:** Writes alternative mockup suggestions to `.hermes/sessions/[teaser].deep-research.md`.
  3.  **Task Creation:** Files a P0 Creative Bead on the backlog. Once Bmad + Claude Code rebuilds the PNG in your folders, the automated loop recompiling scripts trigger, baking an optimized final `.mp4` autonomously.
