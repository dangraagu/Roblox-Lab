// Browser-side helpers for scheduling one Short in YouTube Studio. Used by the daily upload task
// (docs/marketing/youtube-daily-upload.md). Each block below is pasted as ONE javascript_tool call.
// Everything that takes longer than a few seconds is started unawaited and polled, because the
// automation tab is often a hidden tab whose timers are throttled (45 s CDP timeout otherwise).

// ---- BLOCK TAG (after navigate to .../videos/upload?d=ud) ----------------------------------------
// The file input lives in a shadow root; label it so `find` returns a ref for file_upload.
await new Promise(r => setTimeout(r, 3000));
(function () {
  function walk(root, out) {
    for (const el of root.querySelectorAll('*')) {
      if (el.tagName === 'INPUT' && el.type === 'file') out.push(el);
      if (el.shadowRoot) walk(el.shadowRoot, out);
    }
    return out;
  }
  const ins = walk(document, []);
  ins.forEach((e, i) => e.setAttribute('aria-label', 'claude-file-input-' + i));
  return [ins.length, (document.body.innerText.match(/Daglig opplastingsgrense[^\n]*/) || ['no cap banner'])[0]];
})();

// ---- BLOCK FILL (after file_upload; set window.__job first in the same call) ----------------------
// window.__job = {title: "...", description: "..."};
window.__cs = 'filling';
(async () => {
  const J = window.__job, sl = ms => new Promise(r => setTimeout(r, ms));
  await sl(7000);
  const d = document.querySelector('ytcp-uploads-dialog');
  if (/Daglig opplastingsgrense/.test(d.innerText)) { window.__cs = 'CAP'; return; }
  const tb = [...d.querySelectorAll('#textbox')];
  [J.title, J.description].forEach((v, i) => {
    tb[i].focus(); tb[i].innerText = v;
    tb[i].dispatchEvent(new InputEvent('input', {bubbles: true, composed: true})); tb[i].blur();
  });
  await sl(1000);
  d.querySelector('tp-yt-paper-radio-button[name=VIDEO_MADE_FOR_KIDS_NOT_MFK]').click();
  await sl(800);
  const mfk = d.querySelector('tp-yt-paper-radio-button[name=VIDEO_MADE_FOR_KIDS_NOT_MFK]').getAttribute('aria-checked');
  const lens = tb.map(t => t.innerText.length);
  for (let i = 0; i < 3; i++) { d.querySelector('#next-button').click(); await sl(2000); }
  d.querySelector('#second-container-expand-button').click(); await sl(1000);
  d.querySelector('ytcp-datetime-picker #datepicker-trigger').click(); await sl(1000);
  const di = [...document.querySelectorAll('ytcp-date-picker input, tp-yt-paper-dialog input')]
    .filter(i => /\d+\. \w+\.? \d{4}/.test(i.value)).pop();
  di.focus(); di.select();
  window.__cs = 'filled:' + JSON.stringify([mfk, lens]);
})().catch(e => { window.__cs = 'err:' + e; });
'started';

// ---- BLOCK POLL FILL --------------------------------------------------------------------------------
for (let i = 0; i < 40 && window.__cs === 'filling'; i++) await new Promise(r => setTimeout(r, 1000));
window.__cs;

// then, with the computer tool: key ctrl+a, type the date exactly as YouTube writes it
// ("19. sep. 2026", "3. okt. 2026"), key Return.

// ---- BLOCK FINISH (window.__job.date / .time must be set; time on the 15-minute grid) -------------
window.__cf = 'finishing';
(async () => {
  const J = window.__job, sl = ms => new Promise(r => setTimeout(r, ms));
  await sl(800);
  const d = document.querySelector('ytcp-uploads-dialog');
  const p = d.querySelector('ytcp-datetime-picker');
  const inp = p.querySelector('tp-yt-paper-input#textbox input');
  inp.click(); await sl(900);   // the time field is a dropdown; typing into it does nothing
  const item = [...document.querySelectorAll('tp-yt-paper-item')].find(e => e.innerText.trim() === J.time);
  if (item) item.click();
  await sl(900);
  const shownDate = p.innerText.trim().replace(/\s+/g, ' ');
  if (!shownDate.startsWith(J.date) || inp.value !== J.time) {
    window.__cf = JSON.stringify(['MISMATCH', shownDate.slice(0, 16), inp.value]); return;
  }
  d.querySelector('#done-button').click();
  await sl(6000);
  window.__cf = JSON.stringify(['SUBMITTED', J.date, J.time]);
})().catch(e => { window.__cf = 'err:' + e; });
'started';

// ---- BLOCK POLL FINISH ------------------------------------------------------------------------------
for (let i = 0; i < 40 && window.__cf === 'finishing'; i++) await new Promise(r => setTimeout(r, 1000));
window.__cf;

// ---- BLOCK VERIFY (on .../videos/short, after all uploads of the run) -------------------------------
// SUBMITTED is not proof: on 2026-09-17 an upload past the cap reported success and never appeared.
await new Promise(r => setTimeout(r, 6000));
[...document.querySelectorAll('ytcp-video-row')].map(r => {
  const t = r.innerText.split('\n').filter(Boolean);
  const a = r.querySelector('a[href*="/video/"]');
  return (a ? a.href.split('/video/')[1].split('/')[0] : '?') + ' | ' + t[1] + ' | ' + t.slice(3, 6).join(' / ');
});
