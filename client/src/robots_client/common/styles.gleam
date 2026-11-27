//// The page's CSS.

pub const css =
  "
body { margin: 0; background: #101214; color: #c8d0c8; }
.screen { font-family: ui-monospace, 'JetBrains Mono', Menlo, Consolas, monospace;
  font-size: 15px; max-width: 76rem; margin: 0 auto; padding: 1.5rem 1rem; }
pre { margin: 0 0 0.75rem; white-space: pre-wrap; font: inherit; }
.foe { color: #e08a7a; }
.ally { color: #8fd18f; }
.dim { opacity: 0.45; }
.banner { color: #f0d060; min-height: 1.3em; }
.big { font-size: 1.4em; font-weight: bold; }
.news { color: #f0d060; }
.here { color: #8fd18f; margin: 0; }
.table { display: flex; flex-direction: column; gap: 2px; margin-bottom: 0.75rem; }
.map { width: 100%; max-width: 760px; display: block; margin-bottom: 0.5rem; }
.clickable { cursor: pointer; }
.row { display: flex; flex-wrap: wrap; gap: 0 1.5rem; margin-bottom: 0.25rem; }
.row pre { margin: 0; }
.choice { color: #f0d060; }
.robot { display: flex; flex-direction: column; gap: 1px; margin-bottom: 0.5rem; }
.actions { display: flex; gap: 1rem; margin-bottom: 0.75rem; }
.garage { border-top: 1px solid #2a302a; padding-top: 0.75rem;
  display: grid; grid-template-columns: minmax(0, 1fr) 21rem; gap: 1.5rem; }
.preview { position: sticky; top: 1rem; align-self: start; }
@media (max-width: 900px) { .garage { grid-template-columns: 1fr; } }
.cards { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 0.75rem; }
.cardbox { width: 9.5rem; border: 2px solid; border-radius: 7px;
  padding: 5px 7px; font-size: 12px; display: flex; flex-direction: column; gap: 3px;
  box-sizing: border-box; }
.noted { display: flex; flex-direction: column; gap: 2px; width: 9.5rem; }
.cardnote { font-size: 11px; padding: 0 2px; line-height: 1.25; height: 2.5em; overflow: hidden;
  display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; }
.aims { display: flex; align-items: center; gap: 6px; height: 1.1rem; padding: 0 2px; font-size: 10px; opacity: 0.85; }
.aimdots { display: flex; gap: 4px; }
.aimbot { width: 12px; height: 9px; border-radius: 2px; background: #4a4a4a; margin-right: 3px; }
.aimbot.enemy { background: #e06a5a; }
.aimbot.own { background: #6ad06a; }
.aimdot { width: 8px; height: 8px; border-radius: 50%; background: #4a4a4a; }
.aimdot.enemy { background: #e06a5a; }
.aimdot.own { background: #6ad06a; }
.aimdot.both { background: linear-gradient(90deg, #e06a5a 50%, #6ad06a 50%); }
.aimdot.random { background: transparent; box-sizing: border-box; border: 2px solid #e06a5a; }
.aimdot.own.random { border-color: #6ad06a; }
.aimdot.both.random { border-color: #e06a5a #6ad06a #6ad06a #e06a5a; }
.aimlabel { white-space: nowrap; overflow: hidden; text-overflow: ellipsis; color: #c0c0c0; }
.cardnote.good { color: #8fd18f; }
.cardnote.bad { color: #e08a7a; }
.cardbox.clickable:hover { filter: brightness(1.35); }
.cardhead { display: flex; justify-content: space-between; font-size: 10px; letter-spacing: 0.05em; opacity: 0.85;
  height: 1.3em; white-space: nowrap; overflow: hidden; }
.cardcost { font-weight: bold; color: #f0d060; }
/* Every line has a fixed height (two-line ones clamped), so cards don't
   change size with their text. */
.clamp2 { display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.cardname { font-weight: bold; font-size: 13px; line-height: 1.2; height: 2.4em; }
.cardvalue { font-size: 20px; font-weight: bold; line-height: 1.2; height: 1.2em; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.cardtarget { font-size: 11px; line-height: 1.25; height: 2.5em; }
.cardtags { font-size: 10px; opacity: 0.7; white-space: pre-wrap; line-height: 1.25; height: 2.5em; overflow: hidden;
  display: flex; flex-direction: column; justify-content: flex-end; }
.cardbox.attack { border-color: #e06a5a; background: #2a1614; color: #f2c2ba; }
.cardbox.defence { border-color: #5a9ae0; background: #141e2a; color: #bcd4f2; }
.cardbox.buff { border-color: #6ad06a; background: #142a16; color: #c2f0c2; }
.charge { position: relative; height: 0.9rem; margin-top: 0.3rem; border: 1px solid currentColor; border-radius: 3px; overflow: hidden; }
.chargefill { height: 100%; background: rgba(240, 208, 96, 0.35); }
.chargefill.ready { background: rgba(240, 208, 96, 0.8); }
.chargelabel { position: absolute; inset: 0; text-align: center; font-size: 10px; line-height: 0.9rem; color: #fff; }
.cardbox.special { border-color: #9a9a9a; background: #1e1e1e; color: #d0d0d0; }
.card { font: inherit; color: inherit; background: none; border: none;
  text-align: left; padding: 2px 4px; cursor: pointer; white-space: pre-wrap; }
.card:hover { background: #1f2a1f; }
.picked { background: #2a3a2a; }
.tabs { display: flex; gap: 0.25rem; margin-bottom: 0.75rem;
  border-bottom: 1px solid #2a302a; }
.tab { padding: 0.3rem 1rem; border: 1px solid #2a302a; border-bottom: none;
  border-radius: 6px 6px 0 0; opacity: 0.6; }
table.list { border-collapse: collapse; width: 100%; margin-bottom: 0.75rem; }
table.list th { text-align: left; font-weight: normal; opacity: 0.6; padding: 2px 8px;
  border-bottom: 1px solid #2a302a; }
table.list td { padding: 3px 8px; vertical-align: top; white-space: pre-line; }
table.list th:last-child, table.list td:last-child { text-align: right; white-space: nowrap; }
table.list tr.clickable:hover { background: #1f2a1f; }
table.list tr.group td { opacity: 0.45; padding-top: 0.5rem; text-align: left; }
.tab.active { opacity: 1; background: #2a3a2a; color: #f0d060; }
"
