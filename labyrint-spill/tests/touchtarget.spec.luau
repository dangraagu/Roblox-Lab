-- Rene tester for TouchTarget. Kjør: luau tests/touchtarget.spec.luau
-- Bakgrunnen: runde 1 flyttet HUD-en ut av veien for mobil-kontrollene og fikk den til å
-- passe — men UIScale-en som fikk den til å passe krympet samtidig hver knapp, så
-- rekord-knappen landet på 29x29 skjerm-piksler. Disse testene låser gulvet som hindrer det.
local T = require("../src/shared/TouchTarget")
local R = require("../src/shared/Responsive")

local passed, failed = 0, 0
local function eq(a, b, msg)
	if a == b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "want", tostring(b))
	end
end
local function atLeast(a, b, msg)
	if a >= b then passed += 1 else
		failed += 1; print("FAIL:", msg, "-> got", tostring(a), "must be >=", tostring(b))
	end
end

-- De samme viewportene hudcheck måler i.
local PHONE = R.layout(800, 360, true)
local SMALL_PHONE = R.layout(640, 300, true)
local PHONE_TALL = R.layout(414, 800, true)
local TABLET = R.layout(1024, 768, true)
local LAPTOP = R.layout(1366, 768, false)
local DESKTOP = R.layout(1920, 1080, false)

local TOUCH = { PHONE, SMALL_PHONE, PHONE_TALL, TABLET }
local MOUSE = { LAPTOP, DESKTOP }

-- ── desktop rører seg ikke ──────────────────────────────────────────────────
-- Uten mobil-kontroller på skjermen skal begge funksjonene gi tilbake nøyaktig
-- design-tallet. Dette er hele regresjonsvakta: 1920x1080 har scale 1 og controlPad 0.
for _, l in MOUSE do
	eq(T.grow(48, l), 48, "grow rører ikke et vindu uten mobil-kontroller")
	eq(T.tap(48, l), 48, "tap rører ikke et vindu uten mobil-kontroller")
	eq(T.tap(29, l), 29, "tap løfter ikke engang en for liten knapp uten mobil-kontroller")
	eq(T.grow(17, l), 17, "tekst-taket står stille uten mobil-kontroller")
end

-- ── gulvet: 44 skjerm-piksler på berøring ───────────────────────────────────
for _, l in TOUCH do
	atLeast(T.tap(48, l) * l.scale, T.MIN_TAP, "en 48px-knapp lander over 44 skjerm-piksler")
	atLeast(T.tap(40, l) * l.scale, T.MIN_TAP, "en 40px-knapp løftes opp til gulvet")
	atLeast(T.tap(29, l) * l.scale, T.MIN_TAP, "selv en bitteliten knapp løftes opp til gulvet")
	atLeast(T.tap(160, l) * l.scale, 160, "en bred knapp beholder sin fysiske bredde")
end

-- Det konkrete tilfellet fra rapporten: rekord-knappen på 800x360.
atLeast(T.tap(48, PHONE) * PHONE.scale, 44, "RekordKnapp er ikke lenger 29x29")

-- ── grow beholder fysisk størrelse, uten gulv ───────────────────────────────
-- Tekst-tak MÅ kunne være små: et gulv her ville blåst en 17px-etikett opp til 44.
for _, l in TOUCH do
	atLeast(T.grow(17, l) * l.scale, 17, "grow beholder tekst-takets fysiske størrelse")
	local capped = T.grow(17, l) * l.scale
	if capped < T.MIN_TAP then passed += 1 else
		failed += 1; print("FAIL: grow skal IKKE ha noe 44px-gulv (fikk", tostring(capped), ")")
	end
end

-- ── tap er aldri mindre enn grow ────────────────────────────────────────────
for _, l in TOUCH do
	atLeast(T.tap(66, l), T.grow(66, l), "tap er aldri mindre enn grow")
	atLeast(T.tap(12, l), T.grow(12, l), "tap er aldri mindre enn grow, heller ikke i det små")
end

-- ── monotone og degenererte verdier ─────────────────────────────────────────
atLeast(T.grow(100, PHONE), T.grow(50, PHONE), "grow er monoton i design-størrelsen")
atLeast(T.tap(100, PHONE), T.tap(50, PHONE), "tap er monoton i design-størrelsen")
-- ViewportSize er (0,0) et bilde eller to ved oppstart; da må vi ikke dele på noe rart.
local ZERO = R.layout(0, 0, true)
atLeast(T.tap(48, ZERO), 48, "0x0 viewport gir fortsatt et brukbart tall")
eq(T.grow(48, nil), 48, "manglende layout gir design-tallet tilbake")
eq(T.tap(48, nil), 48, "manglende layout gir design-tallet tilbake for tap også")

print(string.format("%d passed, %d failed", passed, failed))
if failed > 0 then error("touchtarget.spec: " .. failed .. " failed", 0) end
