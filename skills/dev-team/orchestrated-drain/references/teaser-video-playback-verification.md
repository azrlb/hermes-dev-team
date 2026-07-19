# Teaser / Landing-Page Video Playback Verification (browser QA)

Recurring drain task class: beads asking to "click each teaser card in a real
browser to confirm in-card playback" (e.g. Crispi `sw9q`, FlowInCash `ajp`/`vuw`).
These are legitimate, fully-autonomous browser-automation QA tasks — a daytime
drain can complete the browser-check portion even when the bead also has an
optional creative follow-up (audio re-VO, re-render) that needs Bob.

## The core gotcha — a11y ref click ≠ playback

The `browser_navigate`/`browser_snapshot` accessibility tree lists affordances
like `button "Play Dinner Decided video" [ref=e10]`, but these are often NOT real
`<button>` elements. On Crispi the play affordance is a `<div role="button"
class="teaser-card__video-wrapper" onclick=...>` wrapping a hidden `<video>`,
a poster `<img>`, and a play-icon `<span>`.

Clicking the a11y ref (`browser_click @e10`) may NOT start playback (it left every
`<video>` at `readyState 0`, `paused:true`, `0x0`). What worked: dispatch a real
DOM click on the actual wrapper element and then POLL the video element's runtime
properties. Do not trust "click succeeded" — verify the pixels loaded.

## Verification recipe (browser_console)

1. Enumerate videos and their play wrappers:
```js
[...document.querySelectorAll('video')].map(v => {
  const w = v.closest('[role=button]');   // the clickable wrapper
  return { src:(v.currentSrc||v.src).split('/').pop(), wrapCls:w&&w.className };
})
```
2. Trigger the wrapper's own click (more reliable than the a11y ref):
```js
document.querySelectorAll('.teaser-card__video-wrapper')[i].click();
```
3. Poll AFTER a delay (video is lazy: `preload="none"`, loads on click). Wrap in
a Promise+setTimeout (~3.5s) because `browser_console` evaluates synchronously:
```js
new Promise(res => setTimeout(() => {
  const v = [...document.querySelectorAll('video')][i];
  res(JSON.stringify({
    display:getComputedStyle(v).display, paused:v.paused,
    ct:+v.currentTime.toFixed(2), dur:v.duration, rs:v.readyState,
    w:v.videoWidth, h:v.videoHeight, err:v.error?v.error.code:null }));
}, 3500))
```

## PASS criteria (in-card playback confirmed)

- `paused:false` AND `currentTime` advancing (>0 and increasing)
- `readyState >= 2` (ideally 4 = HAVE_ENOUGH_DATA)
- valid `videoWidth`/`videoHeight` (e.g. 1080x1920 portrait)
- `error === null`
- poster→video swap: `getComputedStyle(v).display === 'block'` on the active card
  (videos start `display:none` showing the poster)

## Notes / edge cases

- Clicking multiple cards in the same JS tick can leave several videos playing in
  background (the "single-active-video / pause-others" logic may not fire on
  programmatic same-tick clicks). This is cosmetic and does NOT affect real
  single-click UX — note it but don't fail the check.
- `browser_vision` may 401 ("User not found") if the vision backend key is
  unconfigured — fall back to DOM inspection via `browser_console`, which is
  more precise for playback state anyway.
- Recording the result: use `bd comment <bead-id> "..."` with the concrete
  evidence (filenames, durations, dimensions, readyState). If the bead is
  `Owner:`-tagged to a human and has a remaining creative/human sub-task, leave
  it OPEN and just record the verification — don't auto-close.
- `bd comment` re-stages `.beads/issues.jsonl`; commit only that file (targeted),
  and if local `main` is level with `origin/main`, `git push` without a pull so
  any unstaged human WIP (e.g. a signed attestation doc) stays untouched.
