export const meta = {
  name: 'roblox-game-radar',
  description: 'Scan platforms for trending Roblox game demand (7d), rank solo-buildable opportunities, produce game concepts with perfect SEO descriptions',
  phases: [
    { title: 'Research', detail: 'one scout per platform: Roblox charts, Reddit, Google, TikTok, YouTube, solo-buildability' },
    { title: 'Synthesize', detail: 'aggregate + rank opportunities by demand x buildability x differentiation' },
    { title: 'Concepts', detail: 'game brief + perfect paste-ready Roblox description per top opportunity' },
  ],
}

const RESEARCH_SCHEMA = { type: 'object', additionalProperties: false, properties: {
  platform: { type: 'string' },
  trendingGames: { type: 'array', items: { type: 'object', additionalProperties: false, properties: {
    name: { type: 'string' }, genre: { type: 'string' }, whyTrending: { type: 'string' }, signal: { type: 'string' },
  }, required: ['name', 'genre', 'whyTrending'] } },
  demandSignals: { type: 'array', items: { type: 'string' } },
  risingKeywords: { type: 'array', items: { type: 'string' } },
  underserved: { type: 'array', items: { type: 'string' } },
  sources: { type: 'array', items: { type: 'string' } },
}, required: ['platform', 'trendingGames', 'demandSignals', 'underserved'] }

const SYNTH_SCHEMA = { type: 'object', additionalProperties: false, properties: {
  summary: { type: 'string' },
  opportunities: { type: 'array', items: { type: 'object', additionalProperties: false, properties: {
    genre: { type: 'string' }, concept: { type: 'string' },
    demand: { type: 'integer' }, buildability: { type: 'integer' }, differentiation: { type: 'integer' }, score: { type: 'number' },
    rationale: { type: 'string' }, targetKeywords: { type: 'array', items: { type: 'string' } },
  }, required: ['genre', 'concept', 'demand', 'buildability', 'differentiation', 'rationale'] } },
}, required: ['summary', 'opportunities'] }

const CONCEPT_SCHEMA = { type: 'object', additionalProperties: false, properties: {
  title: { type: 'string' },
  hook: { type: 'string' },
  coreLoop: { type: 'string' },
  whyItTrends: { type: 'string' },
  targetAudience: { type: 'string' },
  soloBuildScope: { type: 'string' },
  robloxDescription: { type: 'string' },
  thumbnailIdea: { type: 'string' },
  genreTag: { type: 'string' },
}, required: ['title', 'hook', 'coreLoop', 'whyItTrends', 'robloxDescription'] }

const A = (typeof args === 'object' && args) ? args : {}
const TODAY = A.today || '2026-09-04'
const PORTFOLIO = A.portfolio || 'a 500-level procedural maze obby with DataStore saves'
const EXCLUDE = Array.isArray(A.exclude) ? A.exclude : []
const EXCLUDE_LINE = EXCLUDE.length ? ` The developer has ALREADY shipped these lanes — do NOT re-propose them, find DIFFERENT opportunities: ${EXCLUDE.join('; ')}.` : ''
const COMMON = `You are helping a SOLO developer decide what Roblox game to build next for a growing portfolio (they already shipped ${PORTFOLIO}). Today is ${TODAY}; focus on the LAST 7 DAYS.${EXCLUDE_LINE} Use real web research: FIRST call ToolSearch with query "select:WebSearch,WebFetch" to load the tools, then run several WebSearch queries and WebFetch the most promising result URLs. Be concrete, current, and cite source URLs. Your final output IS the structured data (not a message).`

const ANGLES = [
  { key: 'roblox-charts', prompt: `${COMMON}\n\nPLATFORM: Roblox itself. Find the hottest + fastest-RISING Roblox experiences and GENRES right now (search Roblox charts, "top trending Roblox games this week 2026", "Roblox front page games September 2026"). Identify which genres are surging (obby, tycoon, simulator, brainrot, horror, roleplay, PvP/fighting, tower defense, UGC-limited, story, "escape", clicker, etc.) and what makes the front-runners work. platform="roblox".` },
  { key: 'reddit', prompt: `${COMMON}\n\nPLATFORM: Reddit. Search r/roblox, r/RobloxGameDev, r/robloxgamedev, r/gaming for the past week: what do players ASK FOR, complain is missing, or say "I wish there was a game that...". Surface unmet demand + frustrations, not just what exists. platform="reddit".` },
  { key: 'google', prompt: `${COMMON}\n\nPLATFORM: Google search / Trends. Find RISING Roblox-related search queries the past 7 days (e.g. "roblox <X> game", spiking game names/genres). Which search terms are climbing? platform="google".` },
  { key: 'tiktok', prompt: `${COMMON}\n\nPLATFORM: TikTok. Find which Roblox games / hashtags are going VIRAL right now — viral clips drive massive Roblox traffic. What formats/games are blowing up this week? platform="tiktok".` },
  { key: 'youtube', prompt: `${COMMON}\n\nPLATFORM: YouTube. Find trending Roblox game videos the past week — which games are big creators covering, and what's getting the most views/uploads? Creator attention pipes players in. platform="youtube".` },
  { key: 'buildability', prompt: `${COMMON}\n\nANGLE: solo-buildability. From the trending Roblox genres of the past week, judge which are REALISTICALLY shippable by ONE developer as an MVP in days-to-weeks (NOT a big-team MMO/UGC-economy). Favor genres that reuse our strengths: procedural generation, DataStore progression/saves, single-server logic, simple UI. Rank genres by solo-buildability + MVP speed, and flag the best "high demand AND fast to build" sweet spots. platform="buildability".` },
]

phase('Research')
log('Scouting 6 angles for trending Roblox game demand (past 7 days)...')
const research = (await parallel(ANGLES.map(a => () =>
  agent(a.prompt, { label: `research:${a.key}`, phase: 'Research', schema: RESEARCH_SCHEMA })
))).filter(Boolean)
log(`Research done: ${research.length}/6 scouts returned.`)

phase('Synthesize')
const synth = await agent(
  `You are a Roblox product strategist for a SOLO developer building a portfolio (they already ship procedural-generation + DataStore + single-server obbys). Below is detailed JSON research from ${research.length} real platform scouts. CRITICAL: return REAL, SUBSTANTIVE analysis grounded in that research — every field specific and evidence-based. Do NOT return placeholder / stub / one-letter / "test" values; a stub is a failed response. Produce EXACTLY 6 opportunities.\n\nSynthesize what players WANT on Roblox right now (name the convergent signals across scouts). Then rank 6 opportunities for a solo dev, each scoring 1-10 on demand (how many players want it), buildability (how fast ONE dev ships a good MVP — reward reuse of procedural-gen/DataStore/single-server, penalize PvP-netcode/AI/audio-heavy), and differentiation (can we stand out AND avoid the saturated+litigated brainrot-clone space). Compute score = demand*0.4 + buildability*0.35 + differentiation*0.25 and sort by it. For each opportunity give: genre, a crisp one-line concept (original theme, not a 1:1 clone), the three integer scores + score, a rationale citing specific research signals, and 5-8 target SEO keywords players actually type.${EXCLUDE.length ? ` HARD CONSTRAINT: the developer has ALREADY shipped these lanes — do NOT re-propose them, every opportunity must be a DIFFERENT genre/loop: ${EXCLUDE.join('; ')}.` : ''} Surface FRESH solo sweet spots the research supports — e.g. procedural roguelite escape-horror (Doors-style), tower defense, tycoon/idle-tycoon, original-theme steal+idle-income (no brainrot assets), round-based physics/survival, story/escape-room, simulator-with-a-twist — grounded in the actual signals. RESEARCH JSON:\n${JSON.stringify(research)}`,
  { label: 'synthesize', phase: 'Synthesize', schema: SYNTH_SCHEMA }
)

phase('Concepts')
const top = (synth.opportunities || []).slice().sort((a, b) => (b.score || 0) - (a.score || 0)).slice(0, 4)
log(`Turning top ${top.length} opportunities into game briefs + descriptions...`)
const concepts = (await parallel(top.map((o, i) => () =>
  agent(
    `You are a Roblox game designer + app-store-optimization copywriter. Turn this opportunity into a concrete, SOLO-buildable game concept.\n\nOPPORTUNITY:\n${JSON.stringify(o)}\n\nProduce: a catchy + searchable title; a one-line hook; the core gameplay loop; why it will trend (tie to the demand signals); target audience; solo build scope (the MVP one dev ships fast, reusing procedural-gen/DataStore/single-server strengths); a PERFECT ready-to-paste Roblox experience description (SEO-optimized: front-load the searchable keywords players type, use emoji, a punchy hook, clear feature bullets, and a "LIKE + FAVORITE" call to action, like a top Roblox game page, MAX ~900 characters); a thumbnail idea; and the best Roblox genre/subgenre tag. The description must be paste-ready.`,
    { label: `concept:${o.genre || i}`, phase: 'Concepts', schema: CONCEPT_SCHEMA }
  )
))).filter(Boolean)

return { summary: synth.summary, opportunities: synth.opportunities, concepts, scoutsReturned: research.length }
