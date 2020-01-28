if select(2, UnitClass('player')) ~= 'HUNTER' then
	DisableAddOn('GoodHunting')
	return
end

-- copy heavily accessed global functions into local scope for performance
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellCharges = _G.GetSpellCharges
local GetTime = _G.GetTime
local UnitCastingInfo = _G.UnitCastingInfo
local UnitAura = _G.UnitAura
-- end copy global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
   return string.lower(str:sub(1, start:len())) == start:lower()
end
-- end useful functions

GoodHunting = {}
local Opt -- use this as a local table reference to GoodHunting

SLASH_GoodHunting1, SLASH_GoodHunting2 = '/gh', '/good'
BINDING_HEADER_GOODHUNTING = 'Good Hunting'

local function InitOpts()
	local function SetDefaults(t, ref)
		local k, v
		for k, v in next, ref do
			if t[k] == nil then
				local pchar
				if type(v) == 'boolean' then
					pchar = v and 'true' or 'false'
				elseif type(v) == 'table' then
					pchar = 'table'
				else
					pchar = v
				end
				t[k] = v
			elseif type(t[k]) == 'table' then
				SetDefaults(t[k], v)
			end
		end
	end
	SetDefaults(GoodHunting, { -- defaults
		locked = false,
		snap = false,
		scale = {
			main = 1,
			previous = 0.7,
			cooldown = 0.7,
			interrupt = 0.4,
			extra = 0.4,
			glow = 1,
		},
		glow = {
			main = true,
			cooldown = true,
			interrupt = false,
			extra = true,
			blizzard = false,
			color = { r = 1, g = 1, b = 1 },
		},
		hide = {
			beastmastery = false,
			marksmanship = false,
			survival = false,
		},
		alpha = 1,
		frequency = 0.2,
		previous = true,
		always_on = false,
		cooldown = true,
		spell_swipe = true,
		dimmer = true,
		miss_effect = true,
		boss_only = false,
		interrupt = true,
		aoe = false,
		auto_aoe = false,
		auto_aoe_ttl = 10,
		pot = false,
		trinket = true,
		mend_threshold = 65,
	})
end

-- UI related functions container
local UI = {
	anchor = {},
	glows = {},
}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0
}

-- specialization constants
local SPEC = {
	NONE = 0,
	BEASTMASTERY = 1,
	MARKSMANSHIP = 2,
	SURVIVAL = 3,
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	spec = 0,
	target_mode = 0,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	focus = 0,
	focus_regen = 0,
	focus_max = 100,
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false,
	estimated_range = 30,
}

-- Azerite trait API access
local Azerite = {}

local ghPanel = CreateFrame('Frame', 'ghPanel', UIParent)
ghPanel:SetPoint('CENTER', 0, -169)
ghPanel:SetFrameStrata('BACKGROUND')
ghPanel:SetSize(64, 64)
ghPanel:SetMovable(true)
ghPanel:Hide()
ghPanel.icon = ghPanel:CreateTexture(nil, 'BACKGROUND')
ghPanel.icon:SetAllPoints(ghPanel)
ghPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
ghPanel.border = ghPanel:CreateTexture(nil, 'ARTWORK')
ghPanel.border:SetAllPoints(ghPanel)
ghPanel.border:SetTexture('Interface\\AddOns\\GoodHunting\\border.blp')
ghPanel.border:Hide()
ghPanel.dimmer = ghPanel:CreateTexture(nil, 'BORDER')
ghPanel.dimmer:SetAllPoints(ghPanel)
ghPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
ghPanel.dimmer:Hide()
ghPanel.swipe = CreateFrame('Cooldown', nil, ghPanel, 'CooldownFrameTemplate')
ghPanel.swipe:SetAllPoints(ghPanel)
ghPanel.text = CreateFrame('Frame', nil, ghPanel)
ghPanel.text:SetAllPoints(ghPanel)
ghPanel.text.tl = ghPanel.text:CreateFontString(nil, 'OVERLAY')
ghPanel.text.tl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
ghPanel.text.tl:SetPoint('TOPLEFT', ghPanel, 'TOPLEFT', 2.5, -3)
ghPanel.text.tl:SetJustifyH('LEFT')
ghPanel.text.tr = ghPanel.text:CreateFontString(nil, 'OVERLAY')
ghPanel.text.tr:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
ghPanel.text.tr:SetPoint('TOPRIGHT', ghPanel, 'TOPRIGHT', -2.5, -3)
ghPanel.text.tr:SetJustifyH('RIGHT')
ghPanel.text.bl = ghPanel.text:CreateFontString(nil, 'OVERLAY')
ghPanel.text.bl:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
ghPanel.text.bl:SetPoint('BOTTOMLEFT', ghPanel, 'BOTTOMLEFT', 2.5, 3)
ghPanel.text.bl:SetJustifyH('LEFT')
ghPanel.text.br = ghPanel.text:CreateFontString(nil, 'OVERLAY')
ghPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
ghPanel.text.br:SetPoint('BOTTOMRIGHT', ghPanel, 'BOTTOMRIGHT', -2.5, 3)
ghPanel.text.br:SetJustifyH('RIGHT')
ghPanel.text.center = ghPanel.text:CreateFontString(nil, 'OVERLAY')
ghPanel.text.center:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
ghPanel.text.center:SetAllPoints(ghPanel.text)
ghPanel.text.center:SetJustifyH('CENTER')
ghPanel.text.center:SetJustifyV('CENTER')
ghPanel.button = CreateFrame('Button', 'ghPanelButton', ghPanel)
ghPanel.button:SetAllPoints(ghPanel)
ghPanel.button:RegisterForClicks('LeftButtonDown', 'RightButtonDown', 'MiddleButtonDown')
local ghPreviousPanel = CreateFrame('Frame', 'ghPreviousPanel', UIParent)
ghPreviousPanel:SetFrameStrata('BACKGROUND')
ghPreviousPanel:SetSize(64, 64)
ghPreviousPanel:Hide()
ghPreviousPanel:RegisterForDrag('LeftButton')
ghPreviousPanel:SetScript('OnDragStart', ghPreviousPanel.StartMoving)
ghPreviousPanel:SetScript('OnDragStop', ghPreviousPanel.StopMovingOrSizing)
ghPreviousPanel:SetMovable(true)
ghPreviousPanel.icon = ghPreviousPanel:CreateTexture(nil, 'BACKGROUND')
ghPreviousPanel.icon:SetAllPoints(ghPreviousPanel)
ghPreviousPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
ghPreviousPanel.border = ghPreviousPanel:CreateTexture(nil, 'ARTWORK')
ghPreviousPanel.border:SetAllPoints(ghPreviousPanel)
ghPreviousPanel.border:SetTexture('Interface\\AddOns\\GoodHunting\\border.blp')
local ghCooldownPanel = CreateFrame('Frame', 'ghCooldownPanel', UIParent)
ghCooldownPanel:SetSize(64, 64)
ghCooldownPanel:SetFrameStrata('BACKGROUND')
ghCooldownPanel:Hide()
ghCooldownPanel:RegisterForDrag('LeftButton')
ghCooldownPanel:SetScript('OnDragStart', ghCooldownPanel.StartMoving)
ghCooldownPanel:SetScript('OnDragStop', ghCooldownPanel.StopMovingOrSizing)
ghCooldownPanel:SetMovable(true)
ghCooldownPanel.icon = ghCooldownPanel:CreateTexture(nil, 'BACKGROUND')
ghCooldownPanel.icon:SetAllPoints(ghCooldownPanel)
ghCooldownPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
ghCooldownPanel.border = ghCooldownPanel:CreateTexture(nil, 'ARTWORK')
ghCooldownPanel.border:SetAllPoints(ghCooldownPanel)
ghCooldownPanel.border:SetTexture('Interface\\AddOns\\GoodHunting\\border.blp')
ghCooldownPanel.cd = CreateFrame('Cooldown', nil, ghCooldownPanel, 'CooldownFrameTemplate')
ghCooldownPanel.cd:SetAllPoints(ghCooldownPanel)
local ghInterruptPanel = CreateFrame('Frame', 'ghInterruptPanel', UIParent)
ghInterruptPanel:SetFrameStrata('BACKGROUND')
ghInterruptPanel:SetSize(64, 64)
ghInterruptPanel:Hide()
ghInterruptPanel:RegisterForDrag('LeftButton')
ghInterruptPanel:SetScript('OnDragStart', ghInterruptPanel.StartMoving)
ghInterruptPanel:SetScript('OnDragStop', ghInterruptPanel.StopMovingOrSizing)
ghInterruptPanel:SetMovable(true)
ghInterruptPanel.icon = ghInterruptPanel:CreateTexture(nil, 'BACKGROUND')
ghInterruptPanel.icon:SetAllPoints(ghInterruptPanel)
ghInterruptPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
ghInterruptPanel.border = ghInterruptPanel:CreateTexture(nil, 'ARTWORK')
ghInterruptPanel.border:SetAllPoints(ghInterruptPanel)
ghInterruptPanel.border:SetTexture('Interface\\AddOns\\GoodHunting\\border.blp')
ghInterruptPanel.cast = CreateFrame('Cooldown', nil, ghInterruptPanel, 'CooldownFrameTemplate')
ghInterruptPanel.cast:SetAllPoints(ghInterruptPanel)
local ghExtraPanel = CreateFrame('Frame', 'ghExtraPanel', UIParent)
ghExtraPanel:SetFrameStrata('BACKGROUND')
ghExtraPanel:SetSize(64, 64)
ghExtraPanel:Hide()
ghExtraPanel:RegisterForDrag('LeftButton')
ghExtraPanel:SetScript('OnDragStart', ghExtraPanel.StartMoving)
ghExtraPanel:SetScript('OnDragStop', ghExtraPanel.StopMovingOrSizing)
ghExtraPanel:SetMovable(true)
ghExtraPanel.icon = ghExtraPanel:CreateTexture(nil, 'BACKGROUND')
ghExtraPanel.icon:SetAllPoints(ghExtraPanel)
ghExtraPanel.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
ghExtraPanel.border = ghExtraPanel:CreateTexture(nil, 'ARTWORK')
ghExtraPanel.border:SetAllPoints(ghExtraPanel)
ghExtraPanel.border:SetTexture('Interface\\AddOns\\GoodHunting\\border.blp')
-- Beast Mastery Pet Frenzy stacks and duration remaining on extra icon
ghExtraPanel.frenzy = CreateFrame('Cooldown', nil, ghExtraPanel, 'CooldownFrameTemplate')
ghExtraPanel.frenzy:SetAllPoints(ghExtraPanel)
ghExtraPanel.frenzy.stack = ghExtraPanel.frenzy:CreateFontString(nil, 'OVERLAY')
ghExtraPanel.frenzy.stack:SetFont('Fonts\\FRIZQT__.TTF', 18, 'OUTLINE')
ghExtraPanel.frenzy.stack:SetTextColor(1, 1, 1, 1)
ghExtraPanel.frenzy.stack:SetAllPoints(ghExtraPanel.frenzy)
ghExtraPanel.frenzy.stack:SetJustifyH('CENTER')
ghExtraPanel.frenzy.stack:SetJustifyV('CENTER')

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.BEASTMASTERY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
	[SPEC.MARKSMANSHIP] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
	[SPEC.SURVIVAL] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'}
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes[self.spec])
	self.enemies = self.target_modes[self.spec][self.target_mode][1]
	ghPanel.text.br:SetText(self.target_modes[self.spec][self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes[self.spec] and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes[self.spec] or mode)
end

-- Target Mode Keybinding Wrappers
function GoodHunting_SetTargetMode(mode)
	Player:SetTargetMode(mode)
end

function GoodHunting_ToggleTargetMode()
	Player:ToggleTargetMode()
end

function GoodHunting_ToggleTargetModeReverse()
	Player:ToggleTargetModeReverse()
end

-- End AoE

-- Start Auto AoE

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local unitId = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	if unitId and self.ignored_units[tonumber(unitId)] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function autoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function autoAoe:Clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		Player:SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #Player.target_modes[Player.spec], 1, -1 do
		if count >= Player.target_modes[Player.spec][i][1] then
			Player:SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:Purge()
	local update, guid, t
	for guid, t in next, self.targets do
		if Player.time - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	-- remove expired blacklisted enemies
	for guid, t in next, self.blacklist do
		if Player.time > t then
			self.blacklist[guid] = nil
		end
	end
	if update then
		self:Update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellId = spellId,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_pet = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		focus_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 40,
		velocity = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, self)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:Match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function Ability:Usable()
	if not self.known then
		return false
	end
	if self:Cost() > Player.focus then
		return false
	end
	if self.requires_pet and not Player.pet_active then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready()
end

function Ability:Remains()
	if self:Casting() or self:Traveling() then
		return self:Duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up()
	return self:Remains() > 0
end

function Ability:Down()
	return not self:Up()
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:Traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:Up() and 1 or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:Stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:Cost()
	return self.focus_cost
end

function Ability:Charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:MaxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.ability_casting == self
end

function Ability:Channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:CastTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:CastRegen()
	return Player.focus_regen * self:CastTime() - self:Cost()
end

function Ability:WontCapFocus(reduction)
	return (Player.focus + self:CastRegen()) < (Player.focus_max - (reduction or 5))
end

function Ability:Previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:AzeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {}
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	else
		self.auto_aoe.trigger = 'SPELL_DAMAGE'
	end
end

function Ability:RecordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:UpdateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:Clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:Update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:RemoveAura(guid)
	end
end

function Ability:TrackAuras()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:Duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:RefreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:ApplyAura(guid)
		return
	end
	local duration = self:Duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:RefreshAuraAll()
	local guid, aura, remains
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Hunter Abilities
---- Multiple Specializations
local CallPet = Ability:Add(883, false, true)
local CounterShot = Ability:Add(147362, false, true)
CounterShot.cooldown_duration = 24
CounterShot.triggers_gcd = false
local MendPet = Ability:Add(136, true, true)
MendPet.cooldown_duration = 10
MendPet.buff_duration = 10
MendPet.requires_pet = true
MendPet.auraTarget = 'pet'
local RevivePet = Ability:Add(982, false, true)
RevivePet.focus_cost = 10
------ Procs

------ Talents
local AMurderOfCrows = Ability:Add(131894, false, true, 131900)
AMurderOfCrows.cooldown_duration = 60
AMurderOfCrows.buff_duration = 15
AMurderOfCrows.focus_cost = 30
AMurderOfCrows.tick_interval = 1
AMurderOfCrows.hasted_ticks = true
---- Beast Mastery
local AspectOfTheWild = Ability:Add(193530, true, true)
AspectOfTheWild.cooldown_duration = 120
AspectOfTheWild.buff_duration = 20
local BarbedShot = Ability:Add(217200, false, true)
BarbedShot.cooldown_duration = 12
BarbedShot.buff_duration = 8
BarbedShot.tick_interval = 2
BarbedShot.hasted_cooldown = true
BarbedShot.requires_charge = true
BarbedShot:SetVelocity(50)
BarbedShot.buff = Ability:Add(246152, true, true)
BarbedShot.buff.buff_duration = 8
local BeastCleave = Ability:Add(268877, true, true)
BeastCleave.buff_duration = 4
BeastCleave.pet = Ability:Add(118455, false, true, 118459)
BeastCleave.pet:AutoAoe()
local BestialWrath = Ability:Add(19574, true, true)
BestialWrath.cooldown_duration = 90
BestialWrath.buff_duration = 15
BestialWrath.pet = Ability:Add(186254, true, true)
BestialWrath.pet.auraTarget = 'pet'
BestialWrath.pet.buff_duration = 15
local CobraShot = Ability:Add(193455, false, true)
CobraShot.focus_cost = 35
CobraShot:SetVelocity(45)
local KillCommandBM = Ability:Add(34026, false, true, 83381)
KillCommandBM.focus_cost = 30
KillCommandBM.cooldown_duration = 7.5
KillCommandBM.hasted_cooldown = true
KillCommandBM.requires_pet = true
local MultiShotBM = Ability:Add(2643, false, true)
MultiShotBM.focus_cost = 40
MultiShotBM:SetVelocity(50)
MultiShotBM:AutoAoe(true)
local PetFrenzy = Ability:Add(272790, true, true)
PetFrenzy.auraTarget = 'pet'
PetFrenzy.buff_duration = 8
------ Talents
local Barrage = Ability:Add(120360, false, true, 120361)
Barrage.cooldown_duration = 20
Barrage.focus_cost = 60
Barrage:AutoAoe(true)
local ChimaeraShot = Ability:Add(53209, false, true)
ChimaeraShot.cooldown_duration = 15
ChimaeraShot.hasted_cooldown = true
ChimaeraShot:SetVelocity(40)
local DireBeast = Ability:Add(120679, true, true, 281036)
DireBeast.cooldown_duration = 20
DireBeast.buff_duration = 8
local KillerInstinct = Ability:Add(273887, false, true)
local OneWithThePack = Ability:Add(199528, false, true)
local Stampede = Ability:Add(201430, false, true, 201594)
Stampede.cooldown_duration = 180
Stampede.buff_duration = 12
Stampede:AutoAoe()
local SpittingCobra = Ability:Add(194407, true, true)
SpittingCobra.cooldown_duration = 90
SpittingCobra.buff_duration = 20
local Stomp = Ability:Add(199530, false, true, 201754)
Stomp:AutoAoe(true)
------ Procs

---- Marksmanship

------ Talents

------ Procs

---- Survival
local Carve = Ability:Add(187708, false, true)
Carve.focus_cost = 35
Carve:AutoAoe(true)
local CoordinatedAssault = Ability:Add(266779, true, true)
CoordinatedAssault.cooldown_duration = 120
CoordinatedAssault.buff_duration = 20
CoordinatedAssault.requires_pet = true
local Harpoon = Ability:Add(190925, false, true, 190927)
Harpoon.cooldown_duration = 20
Harpoon.buff_duration = 3
Harpoon.triggers_gcd = false
Harpoon:SetVelocity(70)
local Intimidation = Ability:Add(19577, false, true)
Intimidation.cooldown_duration = 60
Intimidation.buff_duration = 5
Intimidation.requires_pet = true
local KillCommand = Ability:Add(259489, false, true)
KillCommand.focus_cost = -15
KillCommand.cooldown_duration = 6
KillCommand.hasted_cooldown = true
KillCommand.requires_charge = true
KillCommand.requires_pet = true
local Muzzle = Ability:Add(187707, false, true)
Muzzle.cooldown_duration = 15
Muzzle.triggers_gcd = false
local RaptorStrike = Ability:Add(186270, false, true)
RaptorStrike.focus_cost = 30
local SerpentSting = Ability:Add(259491, false, true)
SerpentSting.focus_cost = 20
SerpentSting.buff_duration = 12
SerpentSting.tick_interval = 3
SerpentSting.hasted_ticks = true
SerpentSting.hasted_duration = true
SerpentSting:SetVelocity(60)
SerpentSting:TrackAuras()
local WildfireBomb = Ability:Add(259495, false, true, 269747)
WildfireBomb.cooldown_duration = 18
WildfireBomb.buff_duration = 6
WildfireBomb.tick_interval = 1
WildfireBomb.hasted_cooldown = true
WildfireBomb.requires_charge = true
WildfireBomb:SetVelocity(35)
WildfireBomb:AutoAoe(true)
------ Talents
local AlphaPredator = Ability:Add(269737, false, true)
local BirdsOfPrey = Ability:Add(260331, false, true)
local Bloodseeker = Ability:Add(260248, false, true, 259277)
Bloodseeker.buff_duration = 8
Bloodseeker.tick_interval = 2
Bloodseeker.hasted_ticks = true
Bloodseeker:TrackAuras()
local Butchery = Ability:Add(212436, false, true)
Butchery.focus_cost = 30
Butchery.cooldown_duration = 9
Butchery.hasted_cooldown = true
Butchery.requires_charge = true
Butchery:AutoAoe(true)
local Chakrams = Ability:Add(259391, false, true, 259398)
Chakrams.focus_cost = 30
Chakrams.cooldown_duration = 20
Chakrams:SetVelocity(30)
local FlankingStrike = Ability:Add(269751, false, true)
FlankingStrike.focus_cost = -30
FlankingStrike.cooldown_duration = 40
FlankingStrike.requires_pet = true
local GuerrillaTactics = Ability:Add(264332, false, true)
local HydrasBite = Ability:Add(260241, false, true)
local InternalBleeding = Ability:Add(270343, false, true) -- Shrapnel Bomb DoT applied by Raptor Strike/Mongoose Bite/Carve
local MongooseBite = Ability:Add(259387, false, true)
MongooseBite.focus_cost = 30
local MongooseFury = Ability:Add(259388, true, true)
MongooseFury.buff_duration = 14
local PheromoneBomb = Ability:Add(270323, false, true, 270332) -- Provided by Wildfire Infusion, replaces Wildfire Bomb
PheromoneBomb.cooldown_duration = 18
PheromoneBomb.buff_duration = 6
PheromoneBomb.tick_interval = 1
PheromoneBomb.hasted_cooldown = true
PheromoneBomb.requires_charge = true
PheromoneBomb:SetVelocity(35)
PheromoneBomb:AutoAoe(true)
local Predator = Ability:Add(260249, true, true) -- Bloodseeker buff
local ShrapnelBomb = Ability:Add(270335, false, true, 270339) -- Provided by Wildfire Infusion, replaces Wildfire Bomb
ShrapnelBomb.cooldown_duration = 18
ShrapnelBomb.buff_duration = 6
ShrapnelBomb.tick_interval = 1
ShrapnelBomb.hasted_cooldown = true
ShrapnelBomb.requires_charge = true
ShrapnelBomb:SetVelocity(35)
ShrapnelBomb:AutoAoe()
ShrapnelBomb:TrackAuras(true)
local SteelTrap = Ability:Add(162488, false, true, 162487)
SteelTrap.cooldown_duration = 30
SteelTrap.buff_duration = 20
SteelTrap.tick_interval = 2
SteelTrap.hasted_ticks = true
local TermsOfEngagement = Ability:Add(265895, true, true, 265898)
TermsOfEngagement.buff_duration = 10
local TipOfTheSpear = Ability:Add(260285, true, true, 260286)
TipOfTheSpear.buff_duration = 10
local VipersVenom = Ability:Add(268501, true, true, 268552)
VipersVenom.buff_duration = 8
local VolatileBomb = Ability:Add(271045, false, true, 271049) -- Provided by Wildfire Infusion, replaces Wildfire Bomb
VolatileBomb.cooldown_duration = 18
VolatileBomb.buff_duration = 6
VolatileBomb.tick_interval = 1
VolatileBomb.hasted_cooldown = true
VolatileBomb.requires_charge = true
VolatileBomb:SetVelocity(35)
VolatileBomb:AutoAoe(true)
local WildfireInfusion = Ability:Add(271014, false, true)
------ Procs

-- Azerite Traits
local BlurOfTalons = Ability:Add(277653, true, true, 277969)
BlurOfTalons.buff_duration = 6
local DanceOfDeath = Ability:Add(274441, true, true, 274443)
DanceOfDeath.buff_duration = 8
local LatentPoison = Ability:Add(273283, true, true, 273284)
LatentPoison.buff_duration = 10
local PrimalInstincts = Ability:Add(279806, true, true, 279810)
PrimalInstincts.buff_duration = 20
local RapidReload = Ability:Add(278530, true, true)
local VenomousFangs = Ability:Add(274590, false, true)
local WildernessSurvival = Ability:Add(278532, false, true)
-- Heart of Azeroth
---- Major Essences
local ConcentratedFlame = Ability:Add(295373, true, true, 295378)
ConcentratedFlame.buff_duration = 180
ConcentratedFlame.cooldown_duration = 30
ConcentratedFlame.requires_charge = true
ConcentratedFlame.essence_id = 12
ConcentratedFlame.essence_major = true
ConcentratedFlame:SetVelocity(40)
ConcentratedFlame.dot = Ability:Add(295368, false, true)
ConcentratedFlame.dot.buff_duration = 6
ConcentratedFlame.dot.tick_interval = 2
ConcentratedFlame.dot.essence_id = 12
ConcentratedFlame.dot.essence_major = true
local GuardianOfAzeroth = Ability:Add(295840, false, true)
GuardianOfAzeroth.cooldown_duration = 180
GuardianOfAzeroth.essence_id = 14
GuardianOfAzeroth.essence_major = true
local FocusedAzeriteBeam = Ability:Add(295258, false, true)
FocusedAzeriteBeam.cooldown_duration = 90
FocusedAzeriteBeam.essence_id = 5
FocusedAzeriteBeam.essence_major = true
local MemoryOfLucidDreams = Ability:Add(298357, true, true)
MemoryOfLucidDreams.buff_duration = 15
MemoryOfLucidDreams.cooldown_duration = 120
MemoryOfLucidDreams.essence_id = 27
MemoryOfLucidDreams.essence_major = true
local PurifyingBlast = Ability:Add(295337, false, true, 295338)
PurifyingBlast.cooldown_duration = 60
PurifyingBlast.essence_id = 6
PurifyingBlast.essence_major = true
PurifyingBlast:AutoAoe(true)
local RippleInSpace = Ability:Add(302731, true, true)
RippleInSpace.buff_duration = 2
RippleInSpace.cooldown_duration = 60
RippleInSpace.essence_id = 15
RippleInSpace.essence_major = true
local TheUnboundForce = Ability:Add(298452, false, true)
TheUnboundForce.cooldown_duration = 45
TheUnboundForce.essence_id = 28
TheUnboundForce.essence_major = true
local VisionOfPerfection = Ability:Add(299370, true, true, 303345)
VisionOfPerfection.buff_duration = 10
VisionOfPerfection.essence_id = 22
VisionOfPerfection.essence_major = true
local WorldveinResonance = Ability:Add(295186, true, true)
WorldveinResonance.cooldown_duration = 60
WorldveinResonance.essence_id = 4
WorldveinResonance.essence_major = true
---- Minor Essences
local AncientFlame = Ability:Add(295367, false, true)
AncientFlame.buff_duration = 10
AncientFlame.essence_id = 12
local CondensedLifeForce = Ability:Add(295367, false, true)
CondensedLifeForce.essence_id = 14
local FocusedEnergy = Ability:Add(295248, true, true)
FocusedEnergy.buff_duration = 4
FocusedEnergy.essence_id = 5
local Lifeblood = Ability:Add(295137, true, true)
Lifeblood.essence_id = 4
local LucidDreams = Ability:Add(298343, true, true)
LucidDreams.buff_duration = 8
LucidDreams.essence_id = 27
local PurificationProtocol = Ability:Add(295305, false, true)
PurificationProtocol.essence_id = 6
PurificationProtocol:AutoAoe()
local RealityShift = Ability:Add(302952, true, true)
RealityShift.buff_duration = 20
RealityShift.cooldown_duration = 30
RealityShift.essence_id = 15
local RecklessForce = Ability:Add(302932, true, true)
RecklessForce.buff_duration = 3
RecklessForce.essence_id = 28
local StriveForPerfection = Ability:Add(299369, true, true)
StriveForPerfection.essence_id = 22
-- Racials
local ArcaneTorrent = Ability:Add(80483, true, false) -- Blood Elf
ArcaneTorrent.focus_cost = -15
-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems, Trinket = {}, {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem:Add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, self)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:Charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:Cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:Ready(seconds)
	return self:Cooldown() <= (seconds or 0)
end

function InventoryItem:Equipped()
	return self.equip_slot and true
end

function InventoryItem:Usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:Equipped() and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

-- Inventory Items
local GreaterFlaskOfTheCurrents = InventoryItem:Add(168651)
GreaterFlaskOfTheCurrents.buff = Ability:Add(298836, true, true)
local SuperiorBattlePotionOfAgility = InventoryItem:Add(168489)
SuperiorBattlePotionOfAgility.buff = Ability:Add(298146, true, true)
SuperiorBattlePotionOfAgility.buff.triggers_gcd = false
local PotionOfUnbridledFury = InventoryItem:Add(169299)
PotionOfUnbridledFury.buff = Ability:Add(300714, true, true)
PotionOfUnbridledFury.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:Init()
	self.locations = {}
	self.traits = {}
	self.essences = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:Update()
	local _, loc, slot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for pid in next, self.essences do
		self.essences[pid] = nil
	end
	if UnitEffectiveLevel('player') < 110 then
		print('disabling azerite, player is effectively level', UnitEffectiveLevel('player'))
		return -- disable all Azerite/Essences for players scaled under 110
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			for _, slot in next, C_AzeriteEmpoweredItem.GetAllTierInfo(loc) do
				if slot.azeritePowerIDs then
					for _, pid in next, slot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								--print('Azerite found:', pinfo.azeritePowerID, GetSpellInfo(pinfo.spellID))
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
	for _, loc in next, C_AzeriteEssence.GetMilestones() or {} do
		if loc.slot then
			pid = C_AzeriteEssence.GetMilestoneEssence(loc.ID)
			if pid then
				pinfo = C_AzeriteEssence.GetEssenceInfo(pid)
				self.essences[pid] = {
					id = pid,
					rank = pinfo.rank,
					major = loc.slot == 0,
				}
			end
		end
	end
end

-- End Azerite Trait API

-- Start Player API

function Player:Health()
	return self.health
end

function Player:HealthMax()
	return self.health_max
end

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:Focus()
	return self.focus
end

function Player:FocusDeficit()
	return self.focus_max - self.focus
end

function Player:FocusRegen()
	return self.focus_regen
end

function Player:FocusMax()
	return self.focus_max
end

function Player:FocusTimeToMax()
	local deficit = self.focus_max - self.focus
	if deficit <= 0 then
		return 0
	end
	return deficit / self.focus_regen
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or   -- Bloodlust (Horde Shaman)
			id == 32182 or  -- Heroism (Alliance Shaman)
			id == 80353 or  -- Time Warp (Mage)
			id == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			id == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			id == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			id == 178207 or -- Drums of Fury (Leatherworking)
			id == 146555 or -- Drums of Rage (Leatherworking)
			id == 230935 or -- Drums of the Mountain (Leatherworking)
			id == 256740    -- Drums of the Maelstrom (Leatherworking)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	if slot then
		return GetInventoryItemID('player', slot) == itemID, slot
	end
	local i
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateAbilities()
	self.focus_max = UnitPowerMax('player', 2)

	local _, ability

	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = false
		if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.spellId2 and C_LevelLink.IsSpellLocked(ability.spellId2)) then
			-- spell is locked, do not mark as known
		elseif IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) then
			ability.known = true
		elseif Azerite.traits[ability.spellId] then
			ability.known = true
		elseif ability.essence_id and Azerite.essences[ability.essence_id] then
			if ability.essence_major then
				ability.known = Azerite.essences[ability.essence_id].major
			else
				ability.known = true
			end
		end
	end

	if Butchery.known then
		Carve.known = false
	end
	if MongooseBite.known then
		MongooseFury.known = true
		RaptorStrike.known = false
	end
	if WildfireInfusion.known then
		ShrapnelBomb.known = true
		PheromoneBomb.known = true
		VolatileBomb.known = true
		InternalBleeding.known = true
	end
	if Bloodseeker.known then
		Predator.known = true
	end
	if BarbedShot.known then
		BarbedShot.buff.known = true
		PetFrenzy.known = true
	end
	if BestialWrath.known then
		BestialWrath.pet.known = true
	end
	if MultiShotBM.known then
		BeastCleave.known = true
		BeastCleave.pet.known = true
	end

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			abilities.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				abilities.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				abilities.velocity[#abilities.velocity + 1] = ability
			end
			if ability.auto_aoe then
				abilities.autoAoe[#abilities.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				abilities.trackAuras[#abilities.trackAuras + 1] = ability
			end
		end
	end
end

function Player:UpdatePet()
	self.pet = UnitGUID('pet')
	self.pet_alive = self.pet and not UnitIsDead('pet') and true
	self.pet_active = (self.pet_alive and not self.pet_stuck or IsFlying()) and true
end

-- End Player API

-- Start Target API

function Target:UpdateHealth()
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	table.remove(self.healthArray, 1)
	self.healthArray[25] = self.health
	self.timeToDieMax = self.health / Player.health_max * 15
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.healthArray[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	if UI:ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.player = false
		self.level = UnitLevel('player')
		self.hostile = true
		local i
		for i = 1, 25 do
			self.healthArray[i] = 0
		end
		self:UpdateHealth()
		if Opt.always_on then
			UI:UpdateCombat()
			ghPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			ghPreviousPanel:Hide()
		end
		return
	end
	if guid ~= self.guid then
		self.guid = guid
		local i
		for i = 1, 25 do
			self.healthArray[i] = UnitHealth('target')
		end
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self:UpdateHealth()
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= UnitLevel('player') + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health_max > Player.health_max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		ghPanel:Show()
		return true
	end
end

-- End Target API

-- Start Ability Modifications

function ConcentratedFlame.dot:Remains()
	if ConcentratedFlame:Traveling() then
		return self:Duration()
	end
	return Ability.Remains(self)
end

function SerpentSting:Remains()
	local remains = Ability.Remains(self)
	if VolatileBomb.known and VolatileBomb:Traveling() and remains > 0 then
		return self:Duration()
	end
	return remains
end

function SerpentSting:Cost()
	if VipersVenom:Up() then
		return 0
	end
	return Ability.Cost(self)
end

-- hack to support Wildfire Bomb's changing spells on each cast
function WildfireInfusion:Update()
	local _, _, _, _, _, _, spellId = GetSpellInfo(WildfireBomb.name)
	if self.current then
		if self.current:Match(spellId) then
			return -- not a bomb change
		end
		self.current.next = false
	end
	if ShrapnelBomb:Match(spellId) then
		self.current = ShrapnelBomb
	elseif PheromoneBomb:Match(spellId) then
		self.current = PheromoneBomb
	elseif VolatileBomb:Match(spellId) then
		self.current = VolatileBomb
	else
		self.current = WildfireBomb
	end
	self.current.next = true
	WildfireBomb.icon = self.current.icon
	if Player.main == WildfireBomb then
		Player.main = false -- reset current ability if it was a bomb
	end
end

function CallPet:Usable()
	if Player.pet_active then
		return false
	end
	return Ability.Usable(self)
end

function MendPet:Usable()
	if not Ability.Usable(self) then
		return false
	end
	if Opt.mend_threshold == 0 then
		return false
	end
	if (UnitHealth('pet') / UnitHealthMax('pet') * 100) >= Opt.mend_threshold then
		return false
	end
	return true
end

function RevivePet:Usable()
	if not UnitExists('pet') or (UnitExists('pet') and not UnitIsDead('pet')) then
		return false
	end
	return Ability.Usable(self)
end

function PetFrenzy:StartDurationStack()
	local _, i, id, duration, expires, stack
	for i = 1, 40 do
		_, _, stack, _, duration, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0, 0, 0
		end
		if self:Match(id) then
			return expires - duration, duration, stack
		end
	end
	return 0, 0, 0
end

-- End Ability Modifications

local function UseCooldown(ability, overwrite)
	if Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite) then
		Player.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not Player.extra or overwrite then
		Player.extra = ability
	end
end

local function WaitFor(ability, wait_time)
	Player.wait_time = Player.ctime + wait_time
	return ability
end

-- Begin Action Priority Lists

local APL = {
	[SPEC.NONE] = {
		main = function() end
	},
	[SPEC.BEASTMASTERY] = {},
	[SPEC.MARKSMANSHIP] = {},
	[SPEC.SURVIVAL] = {},
}

APL[SPEC.BEASTMASTERY].main = function(self)
	if CallPet:Usable() then
		UseExtra(CallPet)
	elseif RevivePet:Usable() then
		UseExtra(RevivePet)
	elseif MendPet:Usable() then
		UseExtra(MendPet)
	end
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/summon_pet
actions.precombat+=/potion
actions.precombat+=/worldvein_resonance
actions.precombat+=/guardian_of_azeroth
actions.precombat+=/memory_of_lucid_dreams
# Adjusts the duration and cooldown of Aspect of the Wild and Primal Instincts by the duration of an unhasted GCD when they're used precombat. As AotW has a 1.3s GCD and affects itself this is 1.1s.
actions.precombat+=/aspect_of_the_wild,precast_time=1.1,if=!azerite.primal_instincts.enabled
# Adjusts the duration and cooldown of Bestial Wrath and Haze of Rage by the duration of an unhasted GCD when they're used precombat.
actions.precombat+=/bestial_wrath,precast_time=1.5,if=azerite.primal_instincts.enabled
]]
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheCurrents:Usable() and GreaterFlaskOfTheCurrents.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
			if Target.boss and SuperiorBattlePotionOfAgility:Usable() then
				UseCooldown(SuperiorBattlePotionOfAgility)
			end
		end
		if PrimalInstincts.known then
			if BestialWrath:Usable() then
				UseCooldown(BestialWrath)
			end
		else
			if AspectOfTheWild:Usable() then
				UseCooldown(AspectOfTheWild)
			end
		end
	end
--[[
actions=auto_shot
actions+=/use_items
actions+=/call_action_list,name=cds
actions+=/call_action_list,name=st,if=active_enemies<2
actions+=/call_action_list,name=cleave,if=active_enemies>1
]]
	if Opt.trinket then
		if Trinket1:Usable() then
			UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			UseCooldown(Trinket2)
		end
	end
	self:cds()
	if PetFrenzy:Stack() >= 2 and PetFrenzy:Remains() < (Player.gcd + 0.3) and BarbedShot:Ready(PetFrenzy:Remains()) then
		return WaitFor(BarbedShot, PetFrenzy:Remains() - 0.5)
	end
	if Player.enemies > 1 then
		return self:cleave()
	end
	return self:st()
end

APL[SPEC.BEASTMASTERY].cds = function(self)
--[[
actions.cds=ancestral_call,if=cooldown.bestial_wrath.remains>30
actions.cds+=/fireblood,if=cooldown.bestial_wrath.remains>30
actions.cds+=/berserking,if=buff.aspect_of_the_wild.up&(target.time_to_die>cooldown.berserking.duration+duration|(target.health.pct<35|!talent.killer_instinct.enabled))|target.time_to_die<13
actions.cds+=/blood_fury,if=buff.aspect_of_the_wild.up&(target.time_to_die>cooldown.blood_fury.duration+duration|(target.health.pct<35|!talent.killer_instinct.enabled))|target.time_to_die<16
actions.cds+=/lights_judgment,if=pet.cat.buff.frenzy.up&pet.cat.buff.frenzy.remains>gcd.max|!pet.cat.buff.frenzy.up
actions.cds+=/potion,if=buff.bestial_wrath.up&buff.aspect_of_the_wild.up&(target.health.pct<35|!talent.killer_instinct.enabled)|target.time_to_die<25
actions.cds+=/worldvein_resonance,if=buff.lifeblood.stack<4
actions.cds+=/guardian_of_azeroth
actions.cds+=/ripple_in_space
actions.cds+=/memory_of_lucid_dreams
]]
	if Opt.pot and Target.boss and SuperiorBattlePotionOfAgility:Usable() and (BestialWrath:Up() and AspectOfTheWild:Up() and (Target.healthPercentage < 35 or not KillerInstinct.known) or Target.timeToDie < 25) then
		UseCooldown(SuperiorBattlePotionOfAgility)
	end
end

APL[SPEC.BEASTMASTERY].st = function(self)
--[[
actions.st=barbed_shot,if=pet.cat.buff.frenzy.up&pet.cat.buff.frenzy.remains<=gcd.max|full_recharge_time<gcd.max&cooldown.bestial_wrath.remains|azerite.primal_instincts.enabled&cooldown.aspect_of_the_wild.remains<gcd
actions.st+=/aspect_of_the_wild
actions.st+=/a_murder_of_crows
actions.st+=/stampede,if=buff.aspect_of_the_wild.up&buff.bestial_wrath.up|target.time_to_die<15
actions.st+=/bestial_wrath,if=cooldown.aspect_of_the_wild.remains>20|target.time_to_die<15
actions.st+=/kill_command
actions.st+=/chimaera_shot
actions.st+=/dire_beast
actions.st+=/barbed_shot,if=pet.cat.buff.frenzy.down&(charges_fractional>1.8|buff.bestial_wrath.up)|cooldown.aspect_of_the_wild.remains<pet.cat.buff.frenzy.duration-gcd&azerite.primal_instincts.enabled|azerite.dance_of_death.rank>1&buff.dance_of_death.down&crit_pct_current>40|target.time_to_die<9
actions.st+=/focused_azerite_beam
actions.st+=/purifying_blast
actions.st+=/concentrated_flame
actions.st+=/blood_of_the_enemy
actions.st+=/the_unbound_force,if=buff.reckless_force.up|buff.reckless_force_counter.stack<10
actions.st+=/barrage
actions.st+=/cobra_shot,if=(focus-cost+focus.regen*(cooldown.kill_command.remains-1)>action.kill_command.cost|cooldown.kill_command.remains>1+gcd|buff.memory_of_lucid_dreams.up)&cooldown.kill_command.remains>1
actions.st+=/spitting_cobra
actions.st+=/barbed_shot,if=charges_fractional>1.4
]]
	if BarbedShot:Usable() and ((PetFrenzy:Up() and PetFrenzy:Remains() <= (Player.gcd + 0.3)) or (BarbedShot:FullRechargeTime() < Player.gcd and not BestialWrath:Ready()) or (PrimalInstincts.known and AspectOfTheWild:Ready(Player.gcd))) then
		return BarbedShot
	end
	if AspectOfTheWild:Usable() then
		UseCooldown(AspectOfTheWild)
	end
	if AMurderOfCrows:Usable() then
		UseCooldown(AMurderOfCrows)
	end
	if Stampede:Usable() and (AspectOfTheWild:Up() and BestialWrath:Up() or Target.timeToDie < 15) then
		UseCooldown(Stampede)
	end
	if BestialWrath:Usable() and (AspectOfTheWild:Cooldown() > 20 or Target.timeToDie < 15) then
		UseCooldown(BestialWrath)
	end
	if KillCommandBM:Usable() then
		return KillCommandBM
	end
	if ChimaeraShot:Usable() then
		return ChimaeraShot
	end
	if DireBeast:Usable() then
		return DireBeast
	end
	if BarbedShot:Usable() and ((PetFrenzy:Down() and (BarbedShot:ChargesFractional() > 1.8 or BestialWrath:Up())) or (PrimalInstincts.known and AspectOfTheWild:Ready(PetFrenzy:Duration() - Player.gcd)) or (DanceOfDeath:AzeriteRank() > 1 and DanceOfDeath:Down() and GetCritChance() > 40) or Target.timeToDie < 9) then
		return BarbedShot
	end
	if ConcentratedFlame:Usable() and ConcentratedFlame.dot:Down() then
		return ConcentratedFlame
	end
	if Barrage:Usable() then
		return Barrage
	end
	if CobraShot:Usable() and KillCommandBM:Cooldown() > 1 and (((Player:Focus() - CobraShot:Cost() + Player:FocusRegen() * (KillCommandBM:Cooldown() - 1)) > KillCommandBM:Cost()) or KillCommandBM:Cooldown() > (1 + Player.gcd)) then
		return CobraShot
	end
	if SpittingCobra:Usable() then
		UseCooldown(SpittingCobra)
	end
	if BarbedShot:Usable() and BarbedShot:ChargesFractional() > 1.4 then
		return BarbedShot
	end
end

APL[SPEC.BEASTMASTERY].cleave = function(self)
--[[
actions.cleave=barbed_shot,target_if=min:dot.barbed_shot.remains,if=pet.cat.buff.frenzy.up&pet.cat.buff.frenzy.remains<=gcd.max
actions.cleave+=/multishot,if=gcd.max-pet.cat.buff.beast_cleave.remains>0.25
actions.cleave+=/barbed_shot,target_if=min:dot.barbed_shot.remains,if=full_recharge_time<gcd.max&cooldown.bestial_wrath.remains
actions.cleave+=/aspect_of_the_wild
actions.cleave+=/stampede,if=buff.aspect_of_the_wild.up&buff.bestial_wrath.up|target.time_to_die<15
actions.cleave+=/bestial_wrath,if=cooldown.aspect_of_the_wild.remains_guess>20|talent.one_with_the_pack.enabled|target.time_to_die<15
actions.cleave+=/chimaera_shot
actions.cleave+=/a_murder_of_crows
actions.cleave+=/barrage
actions.cleave+=/kill_command,if=active_enemies<4|!azerite.rapid_reload.enabled
actions.cleave+=/dire_beast
actions.cleave+=/barbed_shot,target_if=min:dot.barbed_shot.remains,if=pet.cat.buff.frenzy.down&(charges_fractional>1.8|buff.bestial_wrath.up)|cooldown.aspect_of_the_wild.remains<pet.cat.buff.frenzy.duration-gcd&azerite.primal_instincts.enabled|charges_fractional>1.4|target.time_to_die<9
actions.cleave+=/focused_azerite_beam
actions.cleave+=/purifying_blast
actions.cleave+=/concentrated_flame
actions.cleave+=/blood_of_the_enemy
actions.cleave+=/the_unbound_force,if=buff.reckless_force.up|buff.reckless_force_counter.stack<10
actions.cleave+=/multishot,if=azerite.rapid_reload.enabled&active_enemies>2
actions.cleave+=/cobra_shot,if=cooldown.kill_command.remains>focus.time_to_max&(active_enemies<3|!azerite.rapid_reload.enabled)
actions.cleave+=/spitting_cobra
]]
	if BarbedShot:Usable() and PetFrenzy:Up() and PetFrenzy:Remains() <= (Player.gcd + 0.3) then
		return BarbedShot
	end
	if MultiShotBM:Usable() and (Player.gcd - BeastCleave:Remains()) > 0.25 then
		return MultiShotBM
	end
	if BarbedShot:Usable() and BarbedShot:FullRechargeTime() < Player.gcd and not BestialWrath:Ready() then
		return BarbedShot
	end
	if AspectOfTheWild:Usable() then
		UseCooldown(AspectOfTheWild)
	end
	if Stampede:Usable() and (AspectOfTheWild:Up() and BestialWrath:Up() or Target.timeToDie < 15) then
		UseCooldown(Stampede)
	end
	if BestialWrath:Usable() and (AspectOfTheWild:Cooldown() > 20 or OneWithThePack.known or Target.timeToDie < 15) then
		UseCooldown(BestialWrath)
	end
	if ChimaeraShot:Usable() then
		return ChimaeraShot
	end
	if AMurderOfCrows:Usable() then
		UseCooldown(AMurderOfCrows)
	end
	if Barrage:Usable() then
		return Barrage
	end
	if KillCommandBM:Usable() and (Player.enemies < 4 or not RapidReload.known) then
		return KillCommandBM
	end
	if DireBeast:Usable() then
		return DireBeast
	end
	if BarbedShot:Usable() and ((PetFrenzy:Down() and (BarbedShot:ChargesFractional() > 1.8 or BestialWrath:Up())) or (PrimalInstincts.known and AspectOfTheWild:Ready(PetFrenzy:Duration() - Player.gcd)) or BarbedShot:ChargesFractional() > 1.4 or Target.timeToDie < 9) then
		return BarbedShot
	end
	if ConcentratedFlame:Usable() and ConcentratedFlame.dot:Down() then
		return ConcentratedFlame
	end
	if RapidReload.known and MultiShotBM:Usable() and Player.enemies > 2 then
		return MultiShotBM
	end
	if CobraShot:Usable() and KillCommandBM:Cooldown() > Player:FocusTimeToMax() and (Player.enemies < 3 or not RapidReload.known) then
		return CobraShot
	end
	if SpittingCobra:Usable() then
		UseCooldown(SpittingCobra)
	end
end

APL[SPEC.MARKSMANSHIP].main = function(self)
	if CallPet:Usable() then
		UseExtra(CallPet)
	elseif RevivePet:Usable() then
		UseExtra(RevivePet)
	elseif MendPet:Usable() then
		UseExtra(MendPet)
	end
	if Player:TimeInCombat() == 0 then
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheCurrents:Usable() and GreaterFlaskOfTheCurrents.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
			if Target.boss and SuperiorBattlePotionOfAgility:Usable() then
				UseCooldown(SuperiorBattlePotionOfAgility)
			end
		end
	end
end

APL[SPEC.SURVIVAL].main = function(self)
	if CallPet:Usable() then
		UseExtra(CallPet)
	elseif RevivePet:Usable() then
		UseExtra(RevivePet)
	elseif MendPet:Usable() then
		UseExtra(MendPet)
	end
	if Player:TimeInCombat() == 0 then
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheCurrents:Usable() and GreaterFlaskOfTheCurrents.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
			if Target.boss and SuperiorBattlePotionOfAgility:Usable() then
				UseCooldown(SuperiorBattlePotionOfAgility)
			end
		end
		if Harpoon:Usable() then
			UseCooldown(Harpoon)
		end
	end
--[[
actions+=/call_action_list,name=cds
actions+=/run_action_list,name=mb_ap_wfi_st,if=active_enemies<2&talent.wildfire_infusion.enabled&talent.alpha_predator.enabled&talent.mongoose_bite.enabled
actions+=/run_action_list,name=wfi_st,if=active_enemies<2&talent.wildfire_infusion.enabled
actions+=/run_action_list,name=st,if=active_enemies<2
actions+=/run_action_list,name=cleave
actions+=/arcane_torrent
]]
	Player.ss_refresh = SerpentSting:Refreshable() and (((Target.timeToDie - SerpentSting:Remains()) > (SerpentSting:TickTime() * 2)) or (VipersVenom.known and VipersVenom:Up()))
	local apl
	apl = self:cds()
	if Player.enemies < 2 then
		if WildfireInfusion.known then
			if AlphaPredator.known and MongooseBite.known then
				apl = self:mb_ap_wfi_st()
			else
				apl = self:wfi_st()
			end
		else
			apl = self:st()
		end
	else
		apl = self:cleave()
	end
	if ArcaneTorrent:Usable() and Player:Focus() < 30 then
		UseCooldown(ArcaneTorrent)
	end
	return apl
end

APL[SPEC.SURVIVAL].cds = function(self)
--[[
actions.cds=blood_fury,if=cooldown.coordinated_assault.remains>30
actions.cds+=/ancestral_call,if=cooldown.coordinated_assault.remains>30
actions.cds+=/fireblood,if=cooldown.coordinated_assault.remains>30
actions.cds+=/lights_judgment
actions.cds+=/berserking,if=cooldown.coordinated_assault.remains>60|time_to_die<11
actions.cds+=/potion,if=buff.coordinated_assault.up&(buff.berserking.up|buff.blood_fury.up|!race.troll&!race.orc)|time_to_die<26
actions.cds+=/aspect_of_the_eagle,if=target.distance>=6
]]
	if Opt.pot and Target.boss and not Player:InArenaOrBattleground() and SuperiorBattlePotionOfAgility:Usable() and CoordinatedAssault:Up() and Player:BloodlustActive() then
		UseCooldown(SuperiorBattlePotionOfAgility)
	end
end

APL[SPEC.SURVIVAL].st = function(self)
--[[
actions.st=a_murder_of_crows
# To simulate usage for Mongoose Bite or Raptor Strike during Aspect of the Eagle, copy each occurrence of the action and append _eagle to the action name.
actions.st+=/mongoose_bite,if=talent.birds_of_prey.enabled&buff.coordinated_assault.up&(buff.coordinated_assault.remains<gcd|buff.blur_of_talons.up&buff.blur_of_talons.remains<gcd)
actions.st+=/raptor_strike,if=talent.birds_of_prey.enabled&buff.coordinated_assault.up&(buff.coordinated_assault.remains<gcd|buff.blur_of_talons.up&buff.blur_of_talons.remains<gcd)
actions.st+=/serpent_sting,if=buff.vipers_venom.react&buff.vipers_venom.remains<gcd
actions.st+=/kill_command,if=focus+cast_regen<focus.max&(!talent.alpha_predator.enabled|full_recharge_time<gcd)
actions.st+=/wildfire_bomb,if=focus+cast_regen<focus.max&(full_recharge_time<gcd|!dot.wildfire_bomb.ticking&(buff.mongoose_fury.down|full_recharge_time<4.5*gcd))
actions.st+=/serpent_sting,if=buff.vipers_venom.react&dot.serpent_sting.remains<4*gcd|!talent.vipers_venom.enabled&!dot.serpent_sting.ticking&!buff.coordinated_assault.up
actions.st+=/serpent_sting,if=refreshable&(azerite.latent_poison.rank>2|azerite.latent_poison.enabled&azerite.venomous_fangs.enabled|(azerite.latent_poison.enabled|azerite.venomous_fangs.enabled)&(!azerite.blur_of_talons.enabled|!talent.birds_of_prey.enabled|!buff.coordinated_assault.up))
actions.st+=/steel_trap
actions.st+=/harpoon,if=talent.terms_of_engagement.enabled
actions.st+=/coordinated_assault
actions.st+=/chakrams
actions.st+=/flanking_strike,if=focus+cast_regen<focus.max
actions.st+=/kill_command,if=focus+cast_regen<focus.max&(buff.mongoose_fury.stack<4|focus<action.mongoose_bite.cost)
actions.st+=/mongoose_bite,if=buff.mongoose_fury.up|focus>60
actions.st+=/raptor_strike
actions.st+=/serpent_sting,if=dot.serpent_sting.refreshable&!buff.coordinated_assault.up
actions.st+=/wildfire_bomb,if=dot.wildfire_bomb.refreshable
]]
	if AMurderOfCrows:Usable() then
		UseCooldown(AMurderOfCrows)
	end
	if CoordinatedAssault:Usable() then
		UseCooldown(CoordinatedAssault)
	end
	if AlphaPredator.known then
		if WildfireBomb:Usable() and WildfireBomb:FullRechargeTime() < Player.gcd then
			return WildfireBomb
		end
		if MongooseBite.known and MongooseFury:Remains() > 0.2 and MongooseFury:Stack() == 5 then
			if SerpentSting:Usable() and Player.ss_refresh then
				return SerpentSting
			end
			if MongooseBite:Usable() then
				return MongooseBite
			end
		end
	end
	if BirdsOfPrey.known and CoordinatedAssault:Up() and (CoordinatedAssault:Remains() < Player.gcd or BlurOfTalons:Up() and BlurOfTalons:Remains() < Player.gcd) then
		if MongooseBite:Usable() then
			return MongooseBite
		end
		if RaptorStrike:Usable() then
			return RaptorStrike
		end
	end
	if KillCommand:Usable() and KillCommand:WontCapFocus() and TipOfTheSpear:Stack() < 3 then
		return KillCommand
	end
	if Chakrams:Usable() then
		return Chakrams
	end
	if SteelTrap:Usable() then
		UseCooldown(SteelTrap)
	end
	if WildfireBomb:Usable() and WildfireBomb:WontCapFocus() and (WildfireBomb:FullRechargeTime() < Player.gcd or WildfireBomb:Refreshable() and MongooseFury:Down()) then
		return WildfireBomb
	end
	if TermsOfEngagement.known and Harpoon:Usable() then
		UseCooldown(Harpoon)
	end
	if FlankingStrike:Usable() and FlankingStrike:WontCapFocus() then
		return FlankingStrike
	end
	if SerpentSting:Usable() and ((VipersVenom.known and VipersVenom:Up()) or (Player.ss_refresh and (not MongooseBite.known or not VipersVenom.known or LatentPoison.known or VenomousFangs.known))) then
		return SerpentSting
	end
	if MongooseBite:Usable() and (MongooseFury:Remains() > 0.2 or Player:Focus() > 60) then
		return MongooseBite
	end
	if RaptorStrike:Usable() then
		return RaptorStrike
	end
	if WildfireBomb:Usable() and WildfireBomb:Refreshable() then
		return WildfireBomb
	end
	if SerpentSting:Usable() and Player.ss_refresh then
		return SerpentSting
	end
end

APL[SPEC.SURVIVAL].wfi_st = function(self)
--[[
actions.wfi_st=a_murder_of_crows
actions.wfi_st+=/coordinated_assault
# To simulate usage for Mongoose Bite or Raptor Strike during Aspect of the Eagle, copy each occurrence of the action and append _eagle to the action name.
actions.wfi_st+=/mongoose_bite,if=azerite.wilderness_survival.enabled&next_wi_bomb.volatile&dot.serpent_sting.remains>2.1*gcd&dot.serpent_sting.remains<3.5*gcd&cooldown.wildfire_bomb.remains>2.5*gcd
actions.wfi_st+=/wildfire_bomb,if=full_recharge_time<gcd|(focus+cast_regen<focus.max)&(next_wi_bomb.volatile&dot.serpent_sting.ticking&dot.serpent_sting.refreshable|next_wi_bomb.pheromone&!buff.mongoose_fury.up&focus+cast_regen<focus.max-action.kill_command.cast_regen*3)
actions.wfi_st+=/kill_command,if=focus+cast_regen<focus.max&buff.tip_of_the_spear.stack<3&(!talent.alpha_predator.enabled|buff.mongoose_fury.stack<5|focus<action.mongoose_bite.cost)
actions.wfi_st+=/raptor_strike,if=dot.internal_bleeding.stack<3&dot.shrapnel_bomb.ticking&!talent.mongoose_bite.enabled
actions.wfi_st+=/wildfire_bomb,if=next_wi_bomb.shrapnel&buff.mongoose_fury.down&(cooldown.kill_command.remains>gcd|focus>60)&!dot.serpent_sting.refreshable
actions.wfi_st+=/steel_trap
actions.wfi_st+=/flanking_strike,if=focus+cast_regen<focus.max
actions.wfi_st+=/serpent_sting,if=buff.vipers_venom.react|refreshable&(!talent.mongoose_bite.enabled|!talent.vipers_venom.enabled|next_wi_bomb.volatile&!dot.shrapnel_bomb.ticking|azerite.latent_poison.enabled|azerite.venomous_fangs.enabled|buff.mongoose_fury.stack=5)
actions.wfi_st+=/harpoon,if=talent.terms_of_engagement.enabled
actions.wfi_st+=/mongoose_bite,if=buff.mongoose_fury.up|focus>60|dot.shrapnel_bomb.ticking
actions.wfi_st+=/raptor_strike
actions.wfi_st+=/serpent_sting,if=refreshable
actions.wfi_st+=/wildfire_bomb,if=next_wi_bomb.volatile&dot.serpent_sting.ticking|next_wi_bomb.pheromone|next_wi_bomb.shrapnel&focus>50
]]
	if AMurderOfCrows:Usable() then
		UseCooldown(AMurderOfCrows)
	end
	if CoordinatedAssault:Usable() then
		UseCooldown(CoordinatedAssault)
	end
	if MongooseBite:Usable() and WildernessSurvival.known and VolatileBomb.next and between(SerpentSting:Remains(), 2.1 * Player.gcd, 3.5 * Player.gcd) and WildfireBomb:Cooldown() > 2.5 * Player.gcd then
		return MongooseBite
	end
	if WildfireBomb:Usable() and (WildfireBomb:FullRechargeTime() < Player.gcd or (WildfireBomb:WontCapFocus() and ((VolatileBomb.next and SerpentSting:Up() and SerpentSting:Refreshable()) or (PheromoneBomb.next and not MongooseFury:Up() and WildfireBomb:WontCapFocus(KillCommand:CastRegen() * 3))))) then
		return WildfireBomb
	end
	if KillCommand:Usable() and KillCommand:WontCapFocus() and TipOfTheSpear:Stack() < 3 and (not AlphaPredator.known or MongooseFury:Stack() < 5 or Player:Focus() < MongooseBite:Cost()) then
		return KillCommand
	end
	if RaptorStrike:Usable() and InternalBleeding:Stack() < 3 and ShrapnelBomb:Up() then
		return RaptorStrike
	end
	if WildfireBomb:Usable() and ShrapnelBomb.next and MongooseFury:Down() and (KillCommand:Cooldown() > Player.gcd or Player:Focus() > 60) and not SerpentSting:Refreshable() then
		return WildfireBomb
	end
	if SteelTrap:Usable() then
		UseCooldown(SteelTrap)
	end
	if FlankingStrike:Usable() and FlankingStrike:WontCapFocus() then
		return FlankingStrike
	end
	if SerpentSting:Usable() and ((VipersVenom.known and VipersVenom:Up()) or (Player.ss_refresh and (not MongooseBite.known or not VipersVenom.known or VolatileBomb.next and not ShrapnelBomb:Up() or LatentPoison.known or VenomousFangs.known or MongooseFury:Stack() == 5))) then
		return SerpentSting
	end
	if TermsOfEngagement.known and Harpoon:Usable() then
		UseCooldown(Harpoon)
	end
	if MongooseBite:Usable() and (MongooseFury:Remains() > 0.2 or Player:Focus() > 60 or ShrapnelBomb:Up()) then
		return MongooseBite
	end
	if RaptorStrike:Usable() then
		return RaptorStrike
	end
	if SerpentSting:Usable() and Player.ss_refresh then
		return SerpentSting
	end
	if WildfireBomb:Usable() and ((VolatileBomb.next and SerpentSting:Up()) or PheromoneBomb.next or (ShrapnelBomb.next and Player:Focus() > 50)) then
		return WildfireBomb
	end
end

APL[SPEC.SURVIVAL].mb_ap_wfi_st = function(self)
--[[
actions.mb_ap_wfi_st=mongoose_bite,if=buff.mongoose_fury.stack=5&buff.mongoose_fury.remains<gcd
actions.mb_ap_wfi_st+=/serpent_sting,if=!dot.serpent_sting.ticking
actions.mb_ap_wfi_st+=/wildfire_bomb,if=full_recharge_time<gcd|(focus+cast_regen<focus.max)&(next_wi_bomb.volatile&dot.serpent_sting.ticking&dot.serpent_sting.refreshable|next_wi_bomb.pheromone&!buff.mongoose_fury.up&focus+cast_regen<focus.max-action.kill_command.cast_regen*3)
actions.mb_ap_wfi_st+=/coordinated_assault
actions.mb_ap_wfi_st+=/mongoose_bite,if=buff.mongoose_fury.stack=5
actions.mb_ap_wfi_st+=/a_murder_of_crows
actions.mb_ap_wfi_st+=/steel_trap
# To simulate usage for Mongoose Bite or Raptor Strike during Aspect of the Eagle, copy each occurrence of the action and append _eagle to the action name.
actions.mb_ap_wfi_st+=/mongoose_bite,if=buff.mongoose_fury.remains&next_wi_bomb.pheromone
actions.mb_ap_wfi_st+=/kill_command,if=focus+cast_regen<focus.max&(buff.mongoose_fury.stack<5|focus<action.mongoose_bite.cost)
actions.mb_ap_wfi_st+=/wildfire_bomb,if=next_wi_bomb.shrapnel&focus>60&dot.serpent_sting.remains>3*gcd
actions.mb_ap_wfi_st+=/serpent_sting,if=refreshable&!dot.shrapnel_bomb.ticking
actions.mb_ap_wfi_st+=/mongoose_bite,if=buff.mongoose_fury.up|focus>60|dot.shrapnel_bomb.ticking
actions.mb_ap_wfi_st+=/serpent_sting,if=refreshable
actions.mb_ap_wfi_st+=/wildfire_bomb,if=next_wi_bomb.volatile&dot.serpent_sting.ticking|next_wi_bomb.pheromone|next_wi_bomb.shrapnel&focus>50
]]
	if MongooseBite:Usable() and MongooseBite:Stack() == 5 and between(MongooseFury:Remains(), 0.2, Player.gcd) then
		return MongooseBite
	end
	if SerpentSting:Usable() and SerpentSting:Down() and Player.ss_refresh then
		return SerpentSting
	end
	if WildfireBomb:Usable() and (WildfireBomb:FullRechargeTime() < Player.gcd or (WildfireBomb:WontCapFocus() and ((VolatileBomb.next and SerpentSting:Up() and SerpentSting:Refreshable()) or (PheromoneBomb.next and not MongooseFury:Up() and WildfireBomb:WontCapFocus(KillCommand:CastRegen() * 3))))) then
		return WildfireBomb
	end
	if CoordinatedAssault:Usable() then
		UseCooldown(CoordinatedAssault)
	end
	if MongooseBite:Usable() and MongooseBite:Stack() == 5 and MongooseFury:Remains() > 0.2  then
		return MongooseBite
	end
	if AMurderOfCrows:Usable() then
		UseCooldown(AMurderOfCrows)
	end
	if SteelTrap:Usable() then
		UseCooldown(SteelTrap)
	end
	if MongooseBite:Usable() and MongooseFury:Remains() > 0.2 and PheromoneBomb.next then
		return MongooseBite
	end
	if KillCommand:Usable() and KillCommand:WontCapFocus() and (MongooseFury:Stack() < 5 or Player:Focus() < MongooseBite:Cost()) then
		return KillCommand
	end
	if WildfireBomb:Usable() and ShrapnelBomb.next and Player:Focus() > 60 and SerpentSting:Remains() > 3 * Player.gcd then
		return WildfireBomb
	end
	if SerpentSting:Usable() and Player.ss_refresh and not ShrapnelBomb:Up() then
		return SerpentSting
	end
	if MongooseBite:Usable() and (MongooseFury:Remains() > 0.2 or Player:Focus() > 60 or ShrapnelBomb:Up()) then
		return MongooseBite
	end
	if SerpentSting:Usable() and Player.ss_refresh then
		return SerpentSting
	end
	if WildfireBomb:Usable() and ((VolatileBomb.next and SerpentSting:Up()) or PheromoneBomb.next or (ShrapnelBomb.next and Player:Focus() > 50)) then
		return WildfireBomb
	end
end

APL[SPEC.SURVIVAL].cleave = function(self)
--[[
actions.cleave=Playeriable,name=carve_cdr,op=setif,value=active_enemies,value_else=5,condition=active_enemies<5
actions.cleave+=/a_murder_of_crows
actions.cleave+=/coordinated_assault
actions.cleave+=/carve,if=dot.shrapnel_bomb.ticking
actions.cleave+=/wildfire_bomb,if=!talent.guerrilla_tactics.enabled|full_recharge_time<gcd
actions.cleave+=/mongoose_bite,target_if=max:debuff.latent_poison.stack,if=debuff.latent_poison.stack=10
actions.cleave+=/chakrams
actions.cleave+=/kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max
actions.cleave+=/butchery,if=full_recharge_time<gcd|!talent.wildfire_infusion.enabled|dot.shrapnel_bomb.ticking&dot.internal_bleeding.stack<3
actions.cleave+=/carve,if=talent.guerrilla_tactics.enabled
actions.cleave+=/flanking_strike,if=focus+cast_regen<focus.max
actions.cleave+=/wildfire_bomb,if=dot.wildfire_bomb.refreshable|talent.wildfire_infusion.enabled
actions.cleave+=/serpent_sting,target_if=min:remains,if=buff.vipers_venom.react
actions.cleave+=/carve,if=cooldown.wildfire_bomb.remains>Playeriable.carve_cdr%2
actions.cleave+=/steel_trap
actions.cleave+=/harpoon,if=talent.terms_of_engagement.enabled
actions.cleave+=/serpent_sting,target_if=min:remains,if=refreshable&buff.tip_of_the_spear.stack<3
# To simulate usage for Mongoose Bite or Raptor Strike during Aspect of the Eagle, copy each occurrence of the action and append _eagle to the action name.
actions.cleave+=/mongoose_bite,target_if=max:debuff.latent_poison.stack
actions.cleave+=/raptor_strike,target_if=max:debuff.latent_poison.stack
]]
	local carve_cdr = min(Player.enemies, 5)
	if AMurderOfCrows:Usable() then
		UseCooldown(AMurderOfCrows)
	end
	if CoordinatedAssault:Usable() then
		UseCooldown(CoordinatedAssault)
	end
	if Carve:Usable() and ShrapnelBomb:Ticking() > 0 then
		return Carve
	end
	if WildfireBomb:Usable() and (not GuerrillaTactics.known or WildfireBomb:FullRechargeTime() < Player.gcd) then
		return WildfireBomb
	end
	if MongooseBite:Usable() and LatentPoison:Stack() >= 10 then
		return MongooseBite
	end
	if Chakrams:Usable() then
		return Chakrams
	end
	if KillCommand:Usable() and KillCommand:WontCapFocus() then
		return KillCommand
	end
	if Butchery:Usable() and (Butchery:FullRechargeTime() < Player.gcd or not WildfireInfusion.known or (ShrapnelBomb:Ticking() > 0 and InternalBleeding:Stack() < 3)) then
		return Butchery
	end
	if GuerrillaTactics.known and Carve:Usable() then
		return Carve
	end
	if FlankingStrike:Usable() and FlankingStrike:WontCapFocus() then
		return FlankingStrike
	end
	if WildfireBomb:Usable() and (WildfireInfusion.known or WildfireBomb:Refreshable()) then
		return WildfireBomb
	end
	if VipersVenom.known and VipersVenom:Up() and SerpentSting:Usable() then
		return SerpentSting
	end
	if Carve:Usable() and WildfireBomb:Cooldown() > (carve_cdr / 2) then
		return Carve
	end
	if SteelTrap:Usable() then
		UseCooldown(SteelTrap)
	end
	if TermsOfEngagement.known and Harpoon:Usable() then
		UseCooldown(Harpoon)
	end
	if SerpentSting:Usable() and Player.ss_refresh and (not TipOfTheSpear.known or TipOfTheSpear:Stack() < 3) then
		return SerpentSting
	end
	if MongooseBite:Usable() then
		return MongooseBite
	end
	if RaptorStrike:Usable() then
		return RaptorStrike
	end
end

APL.Interrupt = function(self)
	if CounterShot:Usable() then
		return CounterShot
	end
	if Muzzle:Usable() then
		return Muzzle
	end
	if Intimidation:Usable() and Target.stunnable then
		return Intimidation
	end
end

-- End Action Priority Lists

-- Start UI API

function UI.DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.spark:SetVertexColor(r, g, b)
		glow.innerGlow:SetVertexColor(r, g, b)
		glow.innerGlowOver:SetVertexColor(r, g, b)
		glow.outerGlow:SetVertexColor(r, g, b)
		glow.outerGlowOver:SetVertexColor(r, g, b)
		glow.ants:SetVertexColor(r, g, b)
	end
end

function UI:CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			self.glows[#self.glows + 1] = glow
		end
	end
	for i = 1, 12 do
		GenerateGlow(_G['ActionButton' .. i])
		GenerateGlow(_G['MultiBarLeftButton' .. i])
		GenerateGlow(_G['MultiBarRightButton' .. i])
		GenerateGlow(_G['MultiBarBottomLeftButton' .. i])
		GenerateGlow(_G['MultiBarBottomRightButton' .. i])
	end
	for i = 1, 10 do
		GenerateGlow(_G['PetActionButton' .. i])
	end
	if Bartender4 then
		for i = 1, 120 do
			GenerateGlow(_G['BT4Button' .. i])
		end
	end
	if Dominos then
		for i = 1, 60 do
			GenerateGlow(_G['DominosActionButton' .. i])
		end
	end
	if ElvUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['ElvUI_Bar' .. b .. 'Button' .. i])
			end
		end
	end
	if LUI then
		for b = 1, 6 do
			for i = 1, 12 do
				GenerateGlow(_G['LUIBarBottom' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarLeft' .. b .. 'Button' .. i])
				GenerateGlow(_G['LUIBarRight' .. b .. 'Button' .. i])
			end
		end
	end
	UI:UpdateGlowColorAndScale()
end

function UI:UpdateGlows()
	local glow, icon, i
	for i = 1, #self.glows do
		glow = self.glows[i]
		icon = glow.button.icon:GetTexture()
		if icon and glow.button.icon:IsVisible() and (
			(Opt.glow.main and Player.main and icon == Player.main.icon) or
			(Opt.glow.cooldown and Player.cd and icon == Player.cd.icon) or
			(Opt.glow.interrupt and Player.interrupt and icon == Player.interrupt.icon) or
			(Opt.glow.extra and Player.extra and icon == Player.extra.icon)
			) then
			if not glow:IsVisible() then
				glow.animIn:Play()
			end
		elseif glow:IsVisible() then
			glow.animIn:Stop()
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	ghPanel:EnableMouse(Opt.aoe or not Opt.locked)
	ghPanel.button:SetShown(Opt.aoe)
	if Opt.locked then
		ghPanel:SetScript('OnDragStart', nil)
		ghPanel:SetScript('OnDragStop', nil)
		ghPanel:RegisterForDrag(nil)
		ghPreviousPanel:EnableMouse(false)
		ghCooldownPanel:EnableMouse(false)
		ghInterruptPanel:EnableMouse(false)
		ghExtraPanel:EnableMouse(false)
	else
		if not Opt.aoe then
			ghPanel:SetScript('OnDragStart', ghPanel.StartMoving)
			ghPanel:SetScript('OnDragStop', ghPanel.StopMovingOrSizing)
			ghPanel:RegisterForDrag('LeftButton')
		end
		ghPreviousPanel:EnableMouse(true)
		ghCooldownPanel:EnableMouse(true)
		ghInterruptPanel:EnableMouse(true)
		ghExtraPanel:EnableMouse(true)
	end
end

function UI:UpdateAlpha()
	ghPanel:SetAlpha(Opt.alpha)
	ghPreviousPanel:SetAlpha(Opt.alpha)
	ghCooldownPanel:SetAlpha(Opt.alpha)
	ghInterruptPanel:SetAlpha(Opt.alpha)
	ghExtraPanel:SetAlpha(Opt.alpha)
end

function UI:UpdateScale()
	ghPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	ghPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	ghCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	ghInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	ghExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

function UI:SnapAllPanels()
	ghPreviousPanel:ClearAllPoints()
	ghPreviousPanel:SetPoint('TOPRIGHT', ghPanel, 'BOTTOMLEFT', -3, 40)
	ghCooldownPanel:ClearAllPoints()
	ghCooldownPanel:SetPoint('TOPLEFT', ghPanel, 'BOTTOMRIGHT', 3, 40)
	ghInterruptPanel:ClearAllPoints()
	ghInterruptPanel:SetPoint('BOTTOMLEFT', ghPanel, 'TOPRIGHT', 3, -21)
	ghExtraPanel:ClearAllPoints()
	ghExtraPanel:SetPoint('BOTTOMRIGHT', ghPanel, 'TOPLEFT', -3, -21)
end

UI.anchor_points = {
	blizzard = { -- Blizzard Personal Resource Display (Default)
		[SPEC.BEASTMASTERY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.MARKSMANSHIP] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
		[SPEC.SURVIVAL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 42 },
			['below'] = { 'TOP', 'BOTTOM', 0, -18 }
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.BEASTMASTERY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
		[SPEC.MARKSMANSHIP] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
		[SPEC.SURVIVAL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 28 },
			['below'] = { 'TOP', 'BOTTOM', 0, 4 }
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		ghPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap then
		local p = UI.anchor.points[Player.spec][Opt.snap]
		ghPanel:ClearAllPoints()
		ghPanel:SetPoint(p[1], UI.anchor.frame, p[2], p[3], p[4])
		UI:SnapAllPanels()
	end
end

function UI:HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		self.anchor.points = self.anchor_points.kui
		self.anchor.frame = KuiNameplatesPlayerAnchor
	else
		self.anchor.points = self.anchor_points.blizzard
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
	end
	if self.anchor.frame then
		self.anchor.frame:HookScript('OnHide', self.OnResourceFrameHide)
		self.anchor.frame:HookScript('OnShow', self.OnResourceFrameShow)
	end
end

function UI:ShouldHide()
	return (Player.spec == SPEC.NONE or
		   (Player.spec == SPEC.BEASTMASTERY and Opt.hide.beastmastery) or
		   (Player.spec == SPEC.MARKSMANSHIP and Opt.hide.marksmanship) or
		   (Player.spec == SPEC.SURVIVAL and Opt.hide.survival))
end

function UI:Disappear()
	ghPanel:Hide()
	ghPanel.icon:Hide()
	ghPanel.border:Hide()
	ghCooldownPanel:Hide()
	ghInterruptPanel:Hide()
	ghExtraPanel:Hide()
	Player.main = nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	UI:UpdateGlows()
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim, text_center
	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
	end
	if Player.wait_time then
		local deficit = Player.wait_time - GetTime()
		if deficit > 0 then
			text_center = format('WAIT %.1fs', deficit)
			dim = Opt.dimmer
		end
	end
	ghPanel.dimmer:SetShown(dim)
	ghPanel.text.center:SetText(text_center)
	--ghPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
end

function UI:UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.main =  nil
	Player.cd = nil
	Player.interrupt = nil
	Player.extra = nil
	Player.wait_time = nil
	start, duration = GetSpellCooldown(61304)
	Player.gcd_remains = start > 0 and duration - (Player.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	Player.ability_casting = abilities.bySpellId[spellId]
	Player.execute_remains = max(remains and (remains / 1000 - Player.ctime) or 0, Player.gcd_remains)
	Player.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	Player.gcd = 1.5 * Player.haste_factor
	Player.health = UnitHealth('player')
	Player.health_max = UnitHealthMax('player')
	Player.focus_regen = GetPowerRegen()
	Player.focus = UnitPower('player', 2) + (Player.focus_regen * Player.execute_remains)
	if Player.ability_casting then
		Player.focus = Player.focus - Player.ability_casting:Cost()
	end
	Player.focus = min(max(Player.focus, 0), Player.focus_max)
	Player.moving = GetUnitSpeed('player') ~= 0
	Player:UpdatePet()

	trackAuras:Purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main then
		ghPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		ghCooldownPanel.icon:SetTexture(Player.cd.icon)
	end
	if Player.extra then
		ghExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local ends, notInterruptible
		_, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
		end
		if start and not notInterruptible then
			Player.interrupt = APL.Interrupt()
			ghInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			ghInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		ghInterruptPanel.icon:SetShown(Player.interrupt)
		ghInterruptPanel.border:SetShown(Player.interrupt)
		ghInterruptPanel:SetShown(start and not notInterruptible)
	end
	ghPanel.icon:SetShown(Player.main)
	ghPanel.border:SetShown(Player.main)
	ghCooldownPanel:SetShown(Player.cd)
	ghExtraPanel:SetShown(Player.extra)

	if Player.spec == SPEC.BEASTMASTERY then
		local start, duration, stack = PetFrenzy:StartDurationStack()
		if start > 0 then
			ghExtraPanel.frenzy.stack:SetText(stack)
			ghExtraPanel.frenzy:SetCooldown(start, duration)
			if not Player.extra then
				ghExtraPanel.icon:SetTexture(PetFrenzy.icon)
				ghExtraPanel:SetShown(true)
			end
		end
		ghExtraPanel.frenzy:SetShown(start > 0)
	end

	self:UpdateDisplay()
	self:UpdateGlows()
end

function UI:UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI API

-- Start Event Handling

function events:ADDON_LOADED(name)
	if name == 'GoodHunting' then
		Opt = GoodHunting
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. name .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_GoodHunting1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] ' .. name .. ' is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitOpts()
		Azerite:Init()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:Remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:Remove(dstGUID)
		end
	end
	if Opt.auto_aoe and (eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED') then
		if dstGUID == Player.guid or dstGUID == Player.pet then
			autoAoe:Add(srcGUID, true)
		elseif (srcGUID == Player.guid or srcGUID == Player.pet) and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Add(dstGUID, true)
		end
	end

	if (srcGUID ~= Player.guid and srcGUID ~= Player.pet) then
		return
	end

	if srcGUID == Player.pet then
		if Player.pet_stuck and (eventType == 'SPELL_CAST_SUCCESS' or eventType == 'SPELL_DAMAGE' or eventType == 'SWING_DAMAGE') then
			Player.pet_stuck = false
		elseif not Player.pet_stuck and eventType == 'SPELL_CAST_FAILED' and missType == 'No path available' then
			Player.pet_stuck = true
		end
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', eventType, spellName, spellId))
		return
	end

	if not (
	   eventType == 'SPELL_CAST_START' or
	   eventType == 'SPELL_CAST_SUCCESS' or
	   eventType == 'SPELL_CAST_FAILED' or
	   eventType == 'SPELL_AURA_REMOVED' or
	   eventType == 'SPELL_DAMAGE' or
	   eventType == 'SPELL_PERIODIC_DAMAGE' or
	   eventType == 'SPELL_MISSED' or
	   eventType == 'SPELL_AURA_APPLIED' or
	   eventType == 'SPELL_AURA_REFRESH' or
	   eventType == 'SPELL_AURA_REMOVED')
	then
		return
	end

	UI:UpdateCombatWithin(0.05)
	if eventType == 'SPELL_CAST_SUCCESS' then
		if srcGUID == Player.guid or ability.player_triggered then
			Player.last_ability = ability
			if ability.triggers_gcd then
				Player.previous_gcd[10] = nil
				table.insert(Player.previous_gcd, 1, ability)
			end
			if ability.travel_start then
				ability.travel_start[dstGUID] = Player.time
			end
			if Opt.previous and ghPanel:IsVisible() then
				ghPreviousPanel.ability = ability
				ghPreviousPanel.border:SetTexture('Interface\\AddOns\\GoodHunting\\border.blp')
				ghPreviousPanel.icon:SetTexture(ability.icon)
				ghPreviousPanel:Show()
			end
		end
		if Player.pet_stuck and ability.requires_pet then
			Player.pet_stuck = false
		end
		return
	end
	if eventType == 'SPELL_CAST_FAILED' then
		if ability.requires_pet and missType == 'No path available' then
			Player.pet_stuck = true
		end
		return
	end
	if dstGUID == Player.guid or dstGUID == Player.pet then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if ability.travel_start and ability.travel_start[dstGUID] then
			ability.travel_start[dstGUID] = nil
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and ghPanel:IsVisible() and ability == ghPreviousPanel.ability then
			ghPreviousPanel.border:SetTexture('Interface\\AddOns\\GoodHunting\\misseffect.blp')
		end
	end
end

function events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		Target:Update()
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.pet_stuck = false
	Target.estimated_range = 30
	Player.previous_gcd = {}
	if Player.last_ability then
		Player.last_ability = nil
		ghPreviousPanel:Hide()
	end
	local _, ability, guid
	for _, ability in next, abilities.velocity do
		for guid in next, ability.travel_start do
			ability.travel_start[guid] = nil
		end
	end
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability.auto_aoe.start_time = nil
			for guid in next, ability.auto_aoe.targets do
				ability.auto_aoe.targets[guid] = nil
			end
		end
		autoAoe:Clear()
		autoAoe:Update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	local _, i, equipType, hasCooldown
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	for _, i in next, Trinket do -- use custom APL lines for these trinkets
		if Trinket1.itemId == i.itemId then
			Trinket1.itemId = 0
		end
		if Trinket2.itemId == i.itemId then
			Trinket2.itemId = 0
		end
	end
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Player:Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
		if Player.item_use_blacklist[inventoryItems[i].itemId] then
			inventoryItems[i].can_use = false
		end
	end
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	ghPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Target:Update()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		ghPanel.swipe:SetCooldown(start, duration)
	end
end

function events:SPELL_UPDATE_ICON()
	if WildfireInfusion.known then
		WildfireInfusion:Update()
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:AZERITE_ESSENCE_UPDATE()
	Azerite:Update()
	Player:UpdateAbilities()
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:UI_ERROR_MESSAGE(errorId)
	if (
	    errorId == 394 or -- pet is rooted
	    errorId == 396 or -- target out of pet range
	    errorId == 400    -- no pet path to target
	) then
		Player.pet_stuck = true
	end
end

function events:PLAYER_ENTERING_WORLD()
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

ghPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			Player:ToggleTargetMode()
		elseif button == 'RightButton' then
			Player:ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			Player:SetTargetMode(1)
		end
	end
end)

ghPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

ghPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	ghPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local ChatFrame_OnHyperlinkShow_Original = ChatFrame_OnHyperlinkShow
function ChatFrame_OnHyperlinkShow(chatFrame, link, ...)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		return BattleTagInviteFrame_Show(linkData)
	end
	return ChatFrame_OnHyperlinkShow_Original(chatFrame, link, ...)
end

local function Status(desc, opt, ...)
	local opt_view
	if type(opt) == 'string' then
		if opt:sub(1, 2) == '|c' then
			opt_view = opt
		else
			opt_view = '|cFFFFD000' .. opt .. '|r'
		end
	elseif type(opt) == 'number' then
		opt_view = '|cFFFFD000' .. opt .. '|r'
	else
		opt_view = opt and '|cFF00C000On|r' or '|cFFC00000Off|r'
	end
	print('Good Hunting -', desc .. ':', opt_view, ...)
end

function SlashCmdList.GoodHunting(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
			else
				Opt.snap = false
				ghPanel:ClearAllPoints()
			end
			UI.OnResourceFrameShow()
		end
		return Status('Snap to the Personal Resource Display frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UI:UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UI:UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra/Pet cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000pet 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UI:UpdateAlpha()
		end
		return Status('Icon transparency', Opt.alpha * 100 .. '%')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.2
		end
		return Status('Calculation frequency (max time to wait between each update): Every', Opt.frequency, 'seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra/pet cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000pet|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			Target:Update()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			Target:Update()
		end
		return Status('Show the Good Hunting UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use Good Hunting for cooldown management', Opt.cooldown)
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
		end
		return Status('Spell casting swipe animation', Opt.spell_swipe)
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
		end
		return Status('Dim main ability icon when you don\'t have enough resources to use it', Opt.dimmer)
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return Status('Red border around previous ability when it fails to hit', Opt.miss_effect)
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			Player:SetTargetMode(1)
			UI:UpdateDraggable()
		end
		return Status('Allow clicking main ability icon to toggle amount of targets (disables moving)', Opt.aoe)
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return Status('Only use cooldowns on bosses', Opt.boss_only)
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'b') then
				Opt.hide.beastmastery = not Opt.hide.beastmastery
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Beast Mastery specialization', not Opt.hide.beastmastery)
			end
			if startsWith(msg[2], 'm') then
				Opt.hide.marksmanship = not Opt.hide.marksmanship
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Marksmanship specialization', not Opt.hide.marksmanship)
			end
			if startsWith(msg[2], 's') then
				Opt.hide.survival = not Opt.hide.survival
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Survival specialization', not Opt.hide.survival)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000beastmastery|r/|cFFFFD000marksmanship|r/|cFFFFD000survival|r ')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return Status('Show an icon for interruptable spells', Opt.interrupt)
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return Status('Automatically change target mode on AoE spells', Opt.auto_aoe)
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return Status('Length of time target exists in auto AoE after being hit', Opt.auto_aoe_ttl, 'seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return Status('Show flasks and battle potions in cooldown UI', Opt.pot)
	end
	if startsWith(msg[1], 'tri') then
		if msg[2] then
			Opt.trinket = msg[2] == 'on'
		end
		return Status('Show on-use trinkets in cooldown UI', Opt.trinket)
	end
	if startsWith(msg[1], 'mend') then
		if msg[2] then
			Opt.mend_threshold = tonumber(msg[2]) or 65
		end
		return Status('Recommend Mend Pet when pet\'s health is below', Opt.mend_threshold .. '%')
	end
	if msg[1] == 'reset' then
		ghPanel:ClearAllPoints()
		ghPanel:SetPoint('CENTER', 0, -169)
		UI:SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print('Good Hunting (version: |cFFFFD000' .. GetAddOnMetadata('GoodHunting', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Good Hunting UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Good Hunting UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Good Hunting UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Good Hunting UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Good Hunting UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Good Hunting for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000beastmastery|r/|cFFFFD000marksmanship|r/|cFFFFD000survival|r  - toggle disabling Good Hunting for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'mend |cFFFFD000[percent]|r  - health percentage to recommend Mend Pet at (default is 65%, 0 to disable)',
		'|cFFFFD000reset|r - reset the location of the Good Hunting UI to default',
	} do
		print('  ' .. SLASH_GoodHunting1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
