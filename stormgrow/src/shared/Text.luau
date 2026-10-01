--!strict
-- Text.luau — number and clock formats for toasts and the HUD. Pure, no requires.

local Text = {}

-- "12,345" (coins are whole: a fraction is floored)
function Text.int(n: number): string
	local neg = n < 0
	local s = tostring(math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if string.sub(out, 1, 1) == "," then out = string.sub(out, 2) end
	return (if neg then "-" else "") .. out
end

local function trim(x: number): string
	local s = string.format("%.1f", x)
	s = string.gsub(s, "%.0$", "")
	return s
end

-- "950", "1.2K", "35K", "1.5M", "2.5B"
function Text.short(n: number): string
	local a = math.abs(n)
	if a < 1000 then return Text.int(n) end
	if a < 1e6 then return trim(n / 1e3) .. "K" end
	if a < 1e9 then return trim(n / 1e6) .. "M" end
	return trim(n / 1e9) .. "B"
end

-- "m:ss", rounded UP so a label never reads 0:00 while time is left; never negative
function Text.clock(seconds: number): string
	local s = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", s // 60, s % 60)
end

return Text
