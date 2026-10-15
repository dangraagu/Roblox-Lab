-- Rene tester for Responsive. Kjør: luau tests/responsive.spec.luau
-- Bakgrunnen: en spiller rapporterte at HUD-en dekker HELE telefonskjermen. Alle panelene
-- var i faste piksler (250x470 venstre, 200x300 høyre) — på ~800x400 er det over halve
-- bredden og mer enn full høyde. Disse testene låser reglene som hindrer det.
local R = require("../src/shared/Responsive")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function truthy(c, msg) if c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function falsy(c, msg) if not c then passed += 1 else failed += 1; print("FAIL:", msg) end end
local function le(a, b, msg)
	if a <= b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "must be <=", tostring(b))
	end
end

-- Reelle viewport-størrelser. Roblox rapporterer ViewportSize i piksler; telefonene er
-- i landskap fordi Roblox tvinger landskap på de fleste spill.
local PHONE = { 800, 360 }      -- iPhone-klasse i landskap
local PHONE_TALL = { 414, 800 } -- portrett (Roblox tillater det)
local SMALL_PHONE = { 640, 300 }
local TABLET = { 1024, 768 }
local LAPTOP = { 1366, 768 }
local DESKTOP = { 1920, 1080 }

-- ── mode ────────────────────────────────────────────────────────────────────
eq(R.layout(PHONE[1], PHONE[2]).mode, "phone", "800x360 er telefon")
eq(R.layout(SMALL_PHONE[1], SMALL_PHONE[2]).mode, "phone", "640x300 er telefon")
eq(R.layout(PHONE_TALL[1], PHONE_TALL[2]).mode, "phone", "portrett-telefon er telefon")
eq(R.layout(TABLET[1], TABLET[2]).mode, "tablet", "1024x768 er nettbrett")
eq(R.layout(LAPTOP[1], LAPTOP[2]).mode, "desktop", "1366x768 er desktop")
eq(R.layout(DESKTOP[1], DESKTOP[2]).mode, "desktop", "1920x1080 er desktop")

-- ── compact ─────────────────────────────────────────────────────────────────
truthy(R.layout(PHONE[1], PHONE[2]).compact, "telefon skjuler sidepaneler bak en knapp")
falsy(R.layout(TABLET[1], TABLET[2]).compact, "nettbrett viser panelene")
falsy(R.layout(DESKTOP[1], DESKTOP[2]).compact, "desktop viser panelene")

-- ── scale ───────────────────────────────────────────────────────────────────
eq(R.layout(DESKTOP[1], DESKTOP[2]).scale, 1, "desktop skalerer ikke ned")
truthy(R.layout(PHONE[1], PHONE[2]).scale < 1, "telefon skalerer ned")
truthy(R.layout(PHONE[1], PHONE[2]).scale >= R.MIN_SCALE, "telefon skalerer ikke under lesbarhetsgulvet")
eq(R.layout(4000, 3000).scale, 1, "skalerer ALDRI opp over 1 (tekst blir uleselig stor ellers)")
-- monoton: større skjerm gir aldri mindre skala
truthy(R.layout(1024, 768).scale >= R.layout(800, 360).scale, "skala er monoton i skjermstørrelse")
truthy(R.layout(1920, 1080).scale >= R.layout(1024, 768).scale, "skala er monoton oppover også")
-- degenerte verdier må ikke gi 0 eller nan (ViewportSize er 0,0 ett bilde ved oppstart)
truthy(R.layout(0, 0).scale >= R.MIN_SCALE, "0x0 viewport gir fortsatt lovlig skala")
eq(R.layout(0, 0).mode, "phone", "0x0 antas som verste tilfelle = telefon")

-- ── plass til Roblox sine touch-kontroller ──────────────────────────────────
-- Tommelstikka nede til venstre og hopp-knappen nede til høyre eier de sonene.
-- Alt vi legger der er umulig å trykke på.
truthy(R.layout(PHONE[1], PHONE[2]).controlPad > 0, "telefon reserverer plass nederst")
eq(R.layout(DESKTOP[1], DESKTOP[2]).controlPad, 0, "desktop reserverer ingenting")
truthy(R.layout(PHONE[1], PHONE[2]).controlPad < PHONE[2] / 2, "reservasjonen spiser ikke halve skjermen")

-- Den fysiske hoyden eier baandet, ikke den tegnbare.
-- Roblox tar topplinje-inset fra TOPPEN, mens tommelstikka og hoppknappen sitter paa bunnen av
-- den FYSISKE skjermen. Da mobil-fiksen begynte aa mate den forkortede hoyden inn her, krympet
-- reservasjonen fra 125 til 113 px paa 800x360 uten at baandet ble mindre: 12 px margin tapt i
-- feil retning. Fjerde argument er den fysiske hoyden; utelates den, oppfoerer alt seg som foer.
do
    local physical = 360
    local drawable = physical - 36 -- topplinje-inset

    local full = R.layout(800, physical, true)
    local naive = R.layout(800, drawable, true)
    local fixed = R.layout(800, drawable, true, physical)

    truthy(naive.controlPad < full.controlPad, "uten fysisk hoyde ville reservasjonen krympet")
    eq(fixed.controlPad, full.controlPad, "controlPad kommer fra den fysiske hoyden")

    -- ... men budsjettet skal fortsatt regnes fra det panelet faktisk har aa gaa paa
    eq(fixed.viewportY, drawable, "viewportY er fortsatt den tegnbare hoyden")
    truthy(R.usableHeight(drawable, fixed) < R.usableHeight(physical, full), "budsjettet krymper med inset-en")

    -- utelatt fjerde argument = uendret oppfoersel, saa ingen kallsted maa endres for aa virke
    eq(R.layout(800, physical, true, nil).controlPad, full.controlPad, "utelatt fysisk hoyde faller tilbake paa vy")
    eq(R.layout(800, physical, true, 0).controlPad, full.controlPad, "0 som fysisk hoyde faller tilbake paa vy")

    -- desktop har ingen kontroller aa reservere for, uansett hvilken hoyde som sendes inn
    eq(R.layout(1920, 1080 - 36, false, 1080).controlPad, 0, "desktop reserverer fortsatt ingenting")
end

-- ── usableHeight: det et sidepanel FAKTISK har å gå på ───────────────────────
for _, v in { PHONE, PHONE_TALL, SMALL_PHONE, TABLET, LAPTOP, DESKTOP } do
	local l = R.layout(v[1], v[2])
	local usable = R.usableHeight(v[2], l)
	truthy(usable > 0, "usableHeight er positiv for " .. v[1] .. "x" .. v[2])
	le(usable, v[2], "usableHeight overstiger aldri skjermhøyden for " .. v[1] .. "x" .. v[2])
end

-- Kjernen i bug-rapporten: 470 px panel på en 360 px høy skjerm.
-- Etter fix må det skalerte panelet få plass innenfor usableHeight.
do
	local l = R.layout(PHONE[1], PHONE[2])
	local usable = R.usableHeight(PHONE[2], l)
	local panelPx = R.fitHeight(470, usable, l)
	le(panelPx * l.scale, usable, "det gamle 470 px panelet får plass etter fitHeight+scale")
	truthy(panelPx > 0, "fitHeight gir et brukbart panel, ikke null")
end
do -- på desktop skal fitHeight ikke røre et panel som allerede får plass
	local l = R.layout(DESKTOP[1], DESKTOP[2])
	local usable = R.usableHeight(DESKTOP[2], l)
	eq(R.fitHeight(470, usable, l), 470, "desktop beholder panelhøyden uendret")
end

-- ── sideWidth: bredden på et sidepanel ──────────────────────────────────────
-- To paneler (venstre + høyre) må aldri spise mer enn halve bredden til sammen.
for _, v in { PHONE, SMALL_PHONE, TABLET, LAPTOP, DESKTOP } do
	local l = R.layout(v[1], v[2])
	local w = R.sideWidth(250, v[1], l)
	truthy(w > 0, "sideWidth positiv for " .. v[1])
	le(w * 2 * l.scale, v[1] * 0.5, "to paneler dekker <= 50% av bredden på " .. v[1] .. "x" .. v[2])
end
eq(R.sideWidth(250, DESKTOP[1], R.layout(DESKTOP[1], DESKTOP[2])), 250, "desktop beholder bredden")
-- 250 px er smalt nok til å slippe unna på alt; det er WIDE paneler som avslører om
-- budsjettet faktisk klemmer. Uten denne overlever en dobling av budsjettet testene.
for _, v in { PHONE, SMALL_PHONE, TABLET, LAPTOP, DESKTOP } do
	local l = R.layout(v[1], v[2])
	local w = R.sideWidth(900, v[1], l)
	le(w * 2 * l.scale, v[1] * 0.5, "et bredt panel klemmes til <= 50% på " .. v[1] .. "x" .. v[2])
	truthy(w < 900, "et 900 px panel BLIR klemt på " .. v[1] .. "x" .. v[2])
end

-- ── stabilitet: layout er ren, samme input gir samme output ──────────────────
do
	local a, b = R.layout(PHONE[1], PHONE[2]), R.layout(PHONE[1], PHONE[2])
	eq(a.mode, b.mode, "layout er deterministisk (mode)")
	eq(a.scale, b.scale, "layout er deterministisk (scale)")
	eq(a.compact, b.compact, "layout er deterministisk (compact)")
end

-- ── ingen avhengigheter ──────────────────────────────────────────────────────
-- Modulen kjøres i BÅDE luau-CLI og Roblox. En bar streng-require ville løst seg
-- her og krasjet i Roblox, så modulen skal ikke require noe i det hele tatt.
truthy(type(R.layout) == "function", "layout er eksportert")
truthy(type(R.usableHeight) == "function", "usableHeight er eksportert")
truthy(type(R.fitHeight) == "function", "fitHeight er eksportert")
truthy(type(R.sideWidth) == "function", "sideWidth er eksportert")

print(string.format("responsive: %d passed, %d failed", passed, failed))
if failed > 0 then error("responsive tests failed") end
