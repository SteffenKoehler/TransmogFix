-- TransmogFix: with server-side transmog (e.g. Rising Gods) the 3.3.5a client takes the
-- look item for things it reads from the visible gear. This fixes what shows up wrong:
-- set piece counts and set bonuses in item tooltips, and the icons of the equipment slots
-- in the character window. Transmogged slots get a hint in their tooltip.
local addonName = ...

local DEFAULTS = {
	setBonus = true,
	slotHints = true,
}

local L = {
	TRANSMOGRIFIED = "Transmogrified",
	SET_BONUS = "Fix set bonuses",
	SET_BONUS_DESC = "Counts set pieces in item tooltips from the gear you really wear. The client counts the look item, so a transmogged set piece and its set bonuses show as missing.",
	SLOT_HINTS = "Real icons and transmog hint",
	SLOT_HINTS_DESC = "Character window slots show the icon of the item you really wear, their tooltip names the transmog look (icon).",
}
if GetLocale() == "deDE" then
	L.TRANSMOGRIFIED = "Transmogrifiziert"
	L.SET_BONUS = "Set-Boni korrigieren"
	L.SET_BONUS_DESC = "Zählt Set-Teile in Item-Tooltips anhand der wirklich getragenen Ausrüstung. Der Client zählt das Aussehen, dadurch fehlen ein transmogrifiziertes Set-Teil und seine Set-Boni."
	L.SLOT_HINTS = "Echte Icons und Transmog-Hinweis"
	L.SLOT_HINTS_DESC = "Die Plätze im Charakterfenster zeigen das Icon des wirklich getragenen Items, ihr Tooltip nennt das Transmog-Aussehen (Icon)."
end

local db = DEFAULTS -- replaced by the saved variables on ADDON_LOADED

-------------------------------------------------------------------------------------
-- Set bonuses: recount from the equipped items by name and correct header, piece lines
-- and bonus lines. Only ever raises the count, so without transmog nothing changes.
-------------------------------------------------------------------------------------
local SET_TOOLTIPS = {"GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ShoppingTooltip3"}
local SET_PIECE_ON = {1, 1, 0.6}
local SET_BONUS_ON = {0.1, 1, 0.1}

-- Turns a format string like "%1$s (%2$d/%3$d)" into a Lua pattern plus the argument
-- index of each capture
local function FormatToPattern(fmt)
	local order, n = {}, 0
	local pattern = fmt:gsub("%%(%d*)%$?([sd])", function(pos, kind)
		n = n + 1
		order[n] = tonumber(pos) or n
		return kind == "s" and "\001" or "\002"
	end)
	pattern = pattern:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
	pattern = pattern:gsub("\001", "(.+)"):gsub("\002", "(%%d+)")
	return "^" .. pattern .. "$", order
end

local setNamePattern, setNameOrder = FormatToPattern(ITEM_SET_NAME)
local setBonusGrayPattern, setBonusGrayOrder = FormatToPattern(ITEM_SET_BONUS_GRAY)

local function Captures(order, ...)
	local args = {}
	for i = 1, #order do
		args[order[i]] = select(i, ...)
	end
	return args
end

local function EquippedNames()
	local names = {}
	for slot = 1, 19 do
		local link = GetInventoryItemLink("player", slot)
		local name = link and link:match("|h%[(.-)%]|h")
		if name then
			names[name] = true
		end
	end
	return names
end

local function FixSetTooltip(tooltip)
	if not db.setBonus then return end
	-- inspected players: the client counts their gear, not ours
	local owner = tooltip:GetOwner()
	local ownerName = owner and owner:GetName()
	if ownerName and ownerName:find("^Inspect") then return end

	local prefix = tooltip:GetName() .. "TextLeft"
	local numLines = tooltip:NumLines()
	for i = 2, numLines do
		local header = _G[prefix .. i]
		local text = header and header:GetText()
		local args = text and Captures(setNameOrder, text:match(setNamePattern))
		local setName, shown, total = args and args[1], args and tonumber(args[2]), args and tonumber(args[3])
		if setName and shown and total then
			local equipped = EquippedNames()
			local pieces, count = {}, 0
			local j = i + 1
			while j <= numLines do
				local line = _G[prefix .. j]
				local name = line:GetText()
				name = name and name:match("^%s*(.-)%s*$")
				if not name or name == "" then break end
				if equipped[name] then
					count = count + 1
					pieces[#pieces + 1] = line
				end
				j = j + 1
			end
			if count > shown then
				header:SetText(format(ITEM_SET_NAME, setName, count, total))
				for _, line in ipairs(pieces) do
					line:SetTextColor(unpack(SET_PIECE_ON))
				end
				for k = i + 1, numLines do
					local line = _G[prefix .. k]
					local bonus = line:GetText()
					local b = bonus and Captures(setBonusGrayOrder, bonus:match(setBonusGrayPattern))
					local need = b and tonumber(b[1])
					if need and b[2] and need <= count then
						line:SetText(format(ITEM_SET_BONUS, b[2]))
						line:SetTextColor(unpack(SET_BONUS_ON))
					end
				end
				tooltip:Show()
			end
			return
		end
	end
end

for _, name in ipairs(SET_TOOLTIPS) do
	local tooltip = _G[name]
	if tooltip then
		tooltip:HookScript("OnTooltipSetItem", FixSetTooltip)
	end
end

-------------------------------------------------------------------------------------
-- Slot icons and hint: the client gives an equipment slot the icon of the look item, the
-- item link stays the real one. Different icons = transmogged slot.
-------------------------------------------------------------------------------------
local TRANSMOG_COLOR = {1, 0.5, 1}
local SLOTS = {
	"Head", "Neck", "Shoulder", "Shirt", "Chest", "Waist", "Legs", "Feet", "Wrist", "Hands",
	"Finger0", "Finger1", "Trinket0", "Trinket1", "Back", "MainHand", "SecondaryHand", "Ranged", "Tabard",
}

-- Real icon and look icon of a player slot, or nil when the slot isn't transmogged
local function TransmogIcons(slot)
	local link = GetInventoryItemLink("player", slot)
	local look = link and GetInventoryItemTexture("player", slot)
	local real = link and select(10, GetItemInfo(link))
	if look and real and look:lower():gsub("/", "\\") ~= real:lower():gsub("/", "\\") then
		return real, look
	end
end

hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
	if not db.slotHints then return end
	local real = TransmogIcons(button:GetID())
	if real then
		SetItemButtonTexture(button, real)
	end
end)

hooksecurefunc(GameTooltip, "SetInventoryItem", function(tooltip, unit, slot)
	if not (db.slotHints and unit and slot and UnitIsUnit(unit, "player")) then return end
	local _, look = TransmogIcons(slot)
	if look then
		tooltip:AddLine(format("|T%s:16|t %s", look, L.TRANSMOGRIFIED), unpack(TRANSMOG_COLOR))
		tooltip:Show()
	end
end)

local function UpdateSlots()
	if not (PaperDollFrame and PaperDollFrame:IsShown()) then return end
	for _, name in ipairs(SLOTS) do
		local button = _G["Character" .. name .. "Slot"]
		if button then
			PaperDollItemSlotButton_Update(button)
		end
	end
end

-------------------------------------------------------------------------------------
-- Options: Interface > AddOns > TransmogFix, /transmogfix
-------------------------------------------------------------------------------------
local panel = CreateFrame("Frame")
panel.name = "TransmogFix"

local function CreateCheck(key, label, desc, y)
	local check = CreateFrame("CheckButton", "TransmogFixCheck_" .. key, panel, "InterfaceOptionsCheckButtonTemplate")
	check:SetPoint("TOPLEFT", 16, y)
	_G[check:GetName() .. "Text"]:SetText(label)
	check.tooltipText = label
	check.tooltipRequirement = desc
	check:SetScript("OnClick", function(self)
		db[key] = self:GetChecked() and true or false
		UpdateSlots()
	end)
	check.key = key
	return check
end

local function CreatePanel()
	local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 16, -16)
	title:SetText("TransmogFix " .. (GetAddOnMetadata(addonName, "Version") or ""))
	local notes = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	notes:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
	notes:SetText(GetAddOnMetadata(addonName, "Notes"))

	local checks = {
		CreateCheck("setBonus", L.SET_BONUS, L.SET_BONUS_DESC, -70),
		CreateCheck("slotHints", L.SLOT_HINTS, L.SLOT_HINTS_DESC, -100),
	}
	panel.refresh = function()
		for _, check in ipairs(checks) do
			check:SetChecked(db[check.key])
		end
	end
	InterfaceOptions_AddCategory(panel)
end

SLASH_TRANSMOGFIX1 = "/transmogfix"
SlashCmdList.TRANSMOGFIX = function()
	-- the first call only opens the AddOns tab when the list was never shown
	InterfaceOptionsFrame_OpenToCategory(panel)
	InterfaceOptionsFrame_OpenToCategory(panel)
end

panel:RegisterEvent("ADDON_LOADED")
panel:SetScript("OnEvent", function(self, event, name)
	if name ~= addonName then return end
	self:UnregisterEvent("ADDON_LOADED")
	TransmogFixDB = TransmogFixDB or {}
	for key, value in pairs(DEFAULTS) do
		if TransmogFixDB[key] == nil then
			TransmogFixDB[key] = value
		end
	end
	db = TransmogFixDB
	CreatePanel()
end)
