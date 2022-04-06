local ADDON = 'GoodHunting'
if select(2, UnitClass('player')) ~= 'HUNTER' then
	DisableAddOn(ADDON)
	return
end
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

-- copy heavily accessed global functions into local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetSpellCharges = _G.GetSpellCharges
local GetSpellCooldown = _G.GetSpellCooldown
local GetSpellInfo = _G.GetSpellInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local UnitAura = _G.UnitAura
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
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
BINDING_HEADER_GOODHUNTING = ADDON

local function InitOpts()
	local function SetDefaults(t, ref)
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
		cd_ttd = 8,
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

-- combat event related functions container
local CombatEvent = {}

-- automatically registered events container
local events = {}

local timer = {
	combat = 0,
	display = 0,
	health = 0,
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
	level = 1,
	spec = 0,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	cast_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	health = {
		current = 0,
		max = 100,
	},
	focus = {
		current = 0,
		regen = 0,
		max = 100,
	},
	pet = {
		active = false,
		alive = false,
		stuck = false,
		health = {
			current = 0,
			max = 100,
		},
	},
	moving = false,
	movement_speed = 100,
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		mh = {
			last = 0,
			next = 0,
			speed = 0,
			remains = 0,
		},
		oh = {
			last = 0,
			next = 0,
			speed = 0,
			remains = 0,
		},
		last_taken = 0,
	},
	set_bonus = {
		t28 = 0,
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health = {
		current = 0,
		loss_per_sec = 0,
		max = 100,
		pct = 100,
		history = {},
	},
	hostile = false,
	estimated_range = 30,
}

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
ghPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
ghPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
ghCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
ghCooldownPanel.dimmer = ghCooldownPanel:CreateTexture(nil, 'BORDER')
ghCooldownPanel.dimmer:SetAllPoints(ghCooldownPanel)
ghCooldownPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
ghCooldownPanel.dimmer:Hide()
ghCooldownPanel.swipe = CreateFrame('Cooldown', nil, ghCooldownPanel, 'CooldownFrameTemplate')
ghCooldownPanel.swipe:SetAllPoints(ghCooldownPanel)
ghCooldownPanel.text = ghCooldownPanel:CreateFontString(nil, 'OVERLAY')
ghCooldownPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
ghCooldownPanel.text:SetAllPoints(ghCooldownPanel)
ghCooldownPanel.text:SetJustifyH('CENTER')
ghCooldownPanel.text:SetJustifyV('CENTER')
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
ghInterruptPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
ghInterruptPanel.swipe = CreateFrame('Cooldown', nil, ghInterruptPanel, 'CooldownFrameTemplate')
ghInterruptPanel.swipe:SetAllPoints(ghInterruptPanel)
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
ghExtraPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
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
		{4, '4+'},
	},
	[SPEC.MARKSMANSHIP] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
	[SPEC.SURVIVAL] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4+'},
	},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(#self.target_modes[self.spec], mode)
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
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:Update()
	local count = 0
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
	local update
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
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	trackAuras = {},
}

function Ability:Add(spellId, buff, player, spellId2)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		spellId2 = spellId2,
		name = false,
		icon = false,
		requires_charge = false,
		requires_react = false,
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
		last_used = 0,
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
	return self:Cooldown() <= (seconds or 0) and (not self.requires_react or self:React() > (seconds or 0))
end

function Ability:Usable(seconds, pool)
	if not self.known then
		return false
	end
	if not pool then
		if self:Cost() > Player.focus.current then
			return false
		end
	end
	if self.requires_pet and not Player.pet.active then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains()
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif self:Match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(0, expires - Player.ctime - Player.execute_remains)
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

function Ability:Up(condition)
	return self:Remains(condition) > 0
end

function Ability:Down(condition)
	return self:Remains(condition) <= 0
end

function Ability:SetVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.traveling = {}
	else
		self.traveling = nil
		self.velocity = 0
	end
end

function Ability:Traveling(all)
	if not self.traveling then
		return 0
	end
	local count = 0
	for _, cast in next, self.traveling do
		if all or cast.dstGUID == Target.guid then
			if Player.time - cast.start < self.max_range / self.velocity then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
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
	local _, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		elseif self:Match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:Cost()
	return self.focus_cost
end

function Ability:ChargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:FullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if self:Casting() then
		if charges >= max_charges then
			return recharge_time
		end
		charges = charges - 1
	end
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
	return Player.focus.regen * self:CastTime() - self:Cost()
end

function Ability:WontCapFocus(reduction)
	return (Player.focus.current + self:CastRegen()) < (Player.focus.max - (reduction or 5))
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

function Ability:AutoAoe(removeUnaffected, trigger)
	self.auto_aoe = {
		remove = removeUnaffected,
		targets = {},
		target_count = 0,
		trigger = 'SPELL_DAMAGE',
	}
	if trigger == 'periodic' then
		self.auto_aoe.trigger = 'SPELL_PERIODIC_DAMAGE'
	elseif trigger == 'apply' then
		self.auto_aoe.trigger = 'SPELL_AURA_APPLIED'
	elseif trigger == 'cast' then
		self.auto_aoe.trigger = 'SPELL_CAST_SUCCESS'
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
		self.auto_aoe.target_count = 0
		for guid in next, self.auto_aoe.targets do
			autoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		autoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastStart(dstGUID)
	return
end

function Ability:CastFailed(dstGUID, missType)
	if self.requires_pet and missType == 'No path available' then
		Player.pet.stuck = true
	end
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.aura_targets and self.requires_react then
		if self.activated then
			self.activated = false
		end
		self:RemoveAura(self.auraTarget == 'player' and Player.guid or dstGUID)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		autoAoe:Add(dstGUID, true)
	end
	if self.requires_pet then
		Player.pet.stuck = false
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous then
		ghPreviousPanel.ability = self
		ghPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		ghPreviousPanel.icon:SetTexture(self.icon)
		ghPreviousPanel:SetShown(ghPanel:IsVisible())
	end
end

function Ability:CastLanded(dstGUID, event, missType)
	if self.swing_queue then
		Player:ResetSwing(true, false, event == 'SPELL_MISSED')
	end
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = min(self.max_range, floor(self.velocity * max(0, Player.time - oldest.start)))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(max(5, min(self.max_range, self.velocity * (Player.time - self.range_est_start))))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and ghPreviousPanel.ability == self then
		ghPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

local trackAuras = {}

function trackAuras:Purge()
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function trackAuras:Remove(guid)
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

-- End DoT tracking

-- Hunter Abilities
---- Multiple Specializations
local CallPet = Ability:Add(883, false, true)
local CounterShot = Ability:Add(147362, false, true)
CounterShot.cooldown_duration = 24
CounterShot.triggers_gcd = false
local FreezingTrap = Ability:Add(187650, false, true, 3355)
FreezingTrap.cooldown_duration = 25
FreezingTrap.buff_duration = 60
local KillShot = Ability:Add({320976, 53351}, false, true)
KillShot.cooldown_duration = 10
KillShot.focus_cost = 10
local MendPet = Ability:Add(136, true, true)
MendPet.cooldown_duration = 10
MendPet.buff_duration = 10
MendPet.requires_pet = true
MendPet.auraTarget = 'pet'
local RevivePet = Ability:Add(982, false, true)
RevivePet.focus_cost = 10
local TarTrap = Ability:Add(187698, false, true, 135299)
TarTrap.cooldown_duration = 30
TarTrap.buff_duration = 30
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
KillCommandBM.max_range = 50
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
Carve.max_range = 5
Carve:AutoAoe(true)
local CoordinatedAssault = Ability:Add(266779, true, true)
CoordinatedAssault.cooldown_duration = 120
CoordinatedAssault.buff_duration = 20
CoordinatedAssault.requires_pet = true
local Harpoon = Ability:Add(190925, false, true, 190927)
Harpoon.cooldown_duration = 20
Harpoon.buff_duration = 3
Harpoon.triggers_gcd = false
Harpoon.max_range = 30
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
KillCommand.max_range = 50
KillCommand:AutoAoe(false, 'cast')
local Muzzle = Ability:Add(187707, false, true)
Muzzle.cooldown_duration = 15
Muzzle.max_range = 5
Muzzle.triggers_gcd = false
local RaptorStrike = Ability:Add(186270, false, true)
RaptorStrike.focus_cost = 30
RaptorStrike.max_range = 5
local SerpentSting = Ability:Add(259491, false, true)
SerpentSting.focus_cost = 20
SerpentSting.buff_duration = 12
SerpentSting.tick_interval = 3
SerpentSting.hasted_ticks = true
SerpentSting:SetVelocity(60)
SerpentSting:AutoAoe(false, 'apply')
SerpentSting:TrackAuras()
local WildfireBomb = Ability:Add(259495, false, true, 269747)
WildfireBomb.cooldown_duration = 18
WildfireBomb.buff_duration = 6
WildfireBomb.tick_interval = 1
WildfireBomb.hasted_cooldown = true
WildfireBomb.requires_charge = true
WildfireBomb:SetVelocity(30)
WildfireBomb:AutoAoe(false, 'apply')
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
FlankingStrike.max_range = 5
local GuerrillaTactics = Ability:Add(264332, false, true)
local HydrasBite = Ability:Add(260241, false, true)
local InternalBleeding = Ability:Add(270343, false, true) -- Shrapnel Bomb DoT applied by Raptor Strike/Mongoose Bite/Carve
local MongooseBite = Ability:Add(259387, false, true)
MongooseBite.focus_cost = 30
MongooseBite.max_range = 5
local MongooseFury = Ability:Add(259388, true, true)
MongooseFury.buff_duration = 14
local PheromoneBomb = Ability:Add(270323, false, true, 270332) -- Provided by Wildfire Infusion, replaces Wildfire Bomb
PheromoneBomb.cooldown_duration = 18
PheromoneBomb.buff_duration = 6
PheromoneBomb.tick_interval = 1
PheromoneBomb.hasted_cooldown = true
PheromoneBomb.requires_charge = true
PheromoneBomb:SetVelocity(30)
PheromoneBomb:AutoAoe(false, 'apply')
local Predator = Ability:Add(260249, true, true) -- Bloodseeker buff
local ShrapnelBomb = Ability:Add(270335, false, true, 270339) -- Provided by Wildfire Infusion, replaces Wildfire Bomb
ShrapnelBomb.cooldown_duration = 18
ShrapnelBomb.buff_duration = 6
ShrapnelBomb.tick_interval = 1
ShrapnelBomb.hasted_cooldown = true
ShrapnelBomb.requires_charge = true
ShrapnelBomb:SetVelocity(30)
ShrapnelBomb:AutoAoe(false, 'apply')
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
VolatileBomb:SetVelocity(30)
VolatileBomb:AutoAoe(false, 'apply')
local WildfireInfusion = Ability:Add(271014, false, true)
------ Procs

-- Covenant abilities
local DeathChakram = Ability:Add(325028, false, true) -- Necrolord
DeathChakram.cooldown_duration = 45
DeathChakram:AutoAoe()
local FlayedShot = Ability:Add(324149, false, true) -- Venthyr
FlayedShot.cooldown_duration = 30
FlayedShot.buff_duration = 18
FlayedShot.tick_interval = 2
local FlayersMark = Ability:Add(324156, true, true) -- triggered by Flayed Shot ticks
FlayersMark.buff_duration = 12
local ResonatingArrow = Ability:Add(308491, false, true, 308498) -- Kyrian
ResonatingArrow.cooldown_duration = 60
ResonatingArrow.buff_duration = 10
ResonatingArrow:AutoAoe(false, 'apply')
local WildSpirits = Ability:Add(328231, false, true) -- Night Fae
WildSpirits.cooldown_duration = 120
local WildMark = Ability:Add(328275, false, true) -- triggered by Wild Spirits
WildMark.buff_duration = 15
WildMark:AutoAoe(false, 'apply')
-- Soulbind conduits

-- Legendary effects
local LatentPoisonInjectors = Ability:Add(336902, false, true, 336903)
LatentPoisonInjectors.buff_duration = 15
LatentPoisonInjectors.bonus_id = 7017
local NesingwarysTrappingApparatus = Ability:Add(336743, true, true, 336744)
NesingwarysTrappingApparatus.buff_duration = 5
NesingwarysTrappingApparatus.bonus_id = 7004
local RylakstalkersConfoundingStrikes = Ability:Add(336901, true, true)
RylakstalkersConfoundingStrikes.bonus_id = 7016
-- Tier effects
local MadBombardier = Ability:Add(364490, true, true, 363805)
MadBombardier.buff_duration = 20
-- Racials

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
		charges = max(self.max_charges, charges)
	end
	return charges
end

function InventoryItem:Count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:Previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(1, count)
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
Trinket.BottledFlayedwingToxin = InventoryItem:Add(178742)
Trinket.BottledFlayedwingToxin.buff = Ability:Add(345545, true, true)
-- End Inventory Items

-- Start Player API

function Player:Health()
	return self.health.current
end

function Player:HealthMax()
	return self.health.max
end

function Player:HealthPct()
	return self.health.current / self.health.max * 100
end

function Player:Focus()
	return self.focus.current
end

function Player:FocusDeficit()
	return self.focus.max - self.focus.current
end

function Player:FocusRegen()
	return self.focus.regen
end

function Player:FocusMax()
	return self.focus.max
end

function Player:FocusTimeToMax()
	local deficit = self.focus.max - self.focus.current
	if deficit <= 0 then
		return 0
	end
	return deficit / self.focus.regen
end

function Player:HasteFactor()
	return self.haste_factor
end

function Player:ResetSwing(mainHand, offHand, missed)
	local mh, oh = UnitAttackSpeed('player')
	if mainHand then
		self.swing.mh.speed = (mh or 0)
		self.swing.mh.last = self.time
		self.swing.mh.next = self.time + self.swing.mh.speed
		if Opt.swing_timer then
			ghPanel.text.tl:SetTextColor(1, missed and 0 or 1, missed and 0 or 1, 1)
		end
	end
	if offHand then
		self.swing.oh.speed = (oh or 0)
		self.swing.oh.last = self.time
		self.swing.oh.next = self.time + self.swing.oh.speed
		if Opt.swing_timer then
			ghPanel.text.tr:SetTextColor(1, missed and 0 or 1, missed and 0 or 1, 1)
		end
	end
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	return 0
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:BloodlustActive()
	local _, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if not id then
			return false
		elseif (
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
	for i = 1, 19 do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId)
	local link, item
	for i = 1, 19 do
		link = GetInventoryItemLink('player', i)
		if link then
			item = link:match('Hitem:%d+:([%d:]+)')
			if item then
				for id in item:gmatch('(%d+)') do
					if tonumber(id) == bonusId then
						return true
					end
				end
			end
		end
	end
	return false
end

function Player:InArenaOrBattleground()
	return self.instance == 'arena' or self.instance == 'pvp'
end

function Player:UpdateTime(timeStamp)
	self.ctime = GetTime()
	if timeStamp then
		self.time_diff = self.ctime - timeStamp
	end
	self.time = self.ctime - self.time_diff
end

function Player:UpdateAbilities()
	self.focus.max = UnitPowerMax('player', 2)

	local node

	for _, ability in next, abilities.all do
		ability.known = false
		for _, spellId in next, ability.spellIds do
			ability.spellId, ability.name, _, ability.icon = spellId, GetSpellInfo(spellId)
			if IsPlayerSpell(spellId) then
				ability.known = true
				break
			end
		end
		if C_LevelLink.IsSpellLocked(ability.spellId) then
			ability.known = false -- spell is locked, do not mark as known
		end
		if ability.bonus_id then -- used for checking Legendary crafted effects
			ability.known = self:BonusIdEquipped(ability.bonus_id)
		end
		if ability.conduit_id then
			node = C_Soulbinds.FindNodeIDActuallyInstalled(C_Soulbinds.GetActiveSoulbindID(), ability.conduit_id)
			if node then
				node = C_Soulbinds.GetNode(node)
				if node and node.state == 3 then
					ability.known = true
				end
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
	if FlayedShot.known then
		FlayersMark.known = true
	end
	if WildSpirits.known then
		WildMark.known = true
	end
	if Player.spec == SPEC.SURVIVAL and Player.set_bonus.t28 >= 2 then
		MadBombardier.known = true
	end

	wipe(abilities.bySpellId)
	wipe(abilities.velocity)
	wipe(abilities.autoAoe)
	wipe(abilities.trackAuras)
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

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == Player.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:UpdatePet()
	self.pet.guid = UnitGUID('pet')
	self.pet.alive = self.pet.guid and not UnitIsDead('pet') and true
	self.pet.active = (self.pet.alive and not self.pet.stuck or IsFlying()) and true
end

function Player:Update()
	local _, start, duration, remains, spellId, speed, max_speed
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self:UpdateTime()
	start, duration = GetSpellCooldown(61304)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.cast_remains = remains and (remains / 1000 - self.ctime) or 0
	self.execute_remains = max(self.cast_remains, self.gcd_remains)
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	self.health.current = UnitHealth('player')
	self.health.max = UnitHealthMax('player')
	self.focus.regen = GetPowerRegen()
	self.focus.current = UnitPower('player', 2) + (self.focus.regen * self.execute_remains)
	if self.ability_casting then
		self.focus.current = self.focus.current - self.ability_casting:Cost()
	end
	self.focus.current = max(0, min(self.focus.max, self.focus.current))
	self.swing.mh.remains = max(0, self.swing.mh.next - self.time - self.execute_remains)
	self.swing.oh.remains = max(0, self.swing.oh.next - self.time - self.execute_remains)
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()
	self:UpdatePet()

	trackAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		autoAoe:Purge()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	ghPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player API

-- Start Target API

function Target:UpdateHealth(reset)
	timer.health = 0
	self.health.current = UnitHealth('target')
	self.health.max = UnitHealthMax('target')
	if self.health.current <= 0 then
		self.health.current = Player.health.max
		self.health.max = self.health.current
	end
	if reset then
		for i = 1, 25 do
			self.health.history[i] = self.health.current
		end
	else
		table.remove(self.health.history, 1)
		self.health.history[25] = self.health.current
	end
	self.timeToDieMax = self.health.current / Player.health.max * 10
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec) or self.timeToDieMax
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
		self.level = Player.level
		self.hostile = false
		self:UpdateHealth(true)
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
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
			self.boss = true
			self.stunnable = false
		elseif Player.instance == 'raid' or (self.health.max > Player.health.max * 10) then
			self.stunnable = false
		end
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		ghPanel:Show()
		return true
	end
end

function Target:Stunned()
	if Intimidation:Up() then
		return true
	end
	return false
end

-- End Target API

-- Start Ability Modifications

function Harpoon:CastLanded(dstGUID, event)
	Ability.CastLanded(self, dstGUID, event)
	Target.estimated_range = 5
end

function SerpentSting:CastLanded(dstGUID, event)
	Ability.CastLanded(self, dstGUID, event)
	if event == 'SPELL_AURA_APPLIED' and self.aura_targets[dstGUID] then
		self:RefreshAura(dstGUID)
	end
end

function SerpentSting:Remains()
	local remains = Ability.Remains(self)
	if VolatileBomb.known and VolatileBomb:Traveling() > 0 and remains > 0 then
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

function KillShot:Usable()
	if (not FlayersMark.known or FlayersMark:Down()) and Target.health.pct >= 20 then
		return false
	end
	return Ability.Usable(self)
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
	if Player.pet.active then
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
	local _, id, duration, expires, stack
	for i = 1, 40 do
		_, _, stack, _, duration, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0, 0, 0
		elseif self:Match(id) then
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
	Player.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(6, Player.enemies - 1)) or AspectOfTheWild:Up() or (WildSpirits.known and WildMark:Up())
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/summon_pet
actions.precombat+=/potion
actions.precombat+=/aspect_of_the_wild,precast_time=1.1
]]
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheCurrents:Usable() and GreaterFlaskOfTheCurrents.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
			if Target.boss and SuperiorBattlePotionOfAgility:Usable() then
				UseCooldown(SuperiorBattlePotionOfAgility)
			end
		end
		if Player.use_cds and AspectOfTheWild:Usable() then
			UseCooldown(AspectOfTheWild)
		end
	end
--[[
actions=auto_shot
actions+=/use_items
actions+=/call_action_list,name=cds
actions+=/call_action_list,name=st,if=active_enemies<2
actions+=/call_action_list,name=cleave,if=active_enemies>1
]]
	if Player.use_cds then
		self:cds()
	end
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
]]
	if Opt.trinket then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
	if Opt.pot and Target.boss and SuperiorBattlePotionOfAgility:Usable() and (BestialWrath:Up() and AspectOfTheWild:Up() and (Target.health.pct < 35 or not KillerInstinct.known) or Target.timeToDie < 25) then
		return UseCooldown(SuperiorBattlePotionOfAgility)
	end
	if WildSpirits:Usable() and WildMark:Down() then
		return UseCooldown(WildSpirits)
	end
end

APL[SPEC.BEASTMASTERY].st = function(self)
--[[
actions.st=barbed_shot,if=pet.cat.buff.frenzy.up&pet.cat.buff.frenzy.remains<=gcd.max|full_recharge_time<gcd.max&cooldown.bestial_wrath.remains
actions.st+=/aspect_of_the_wild
actions.st+=/a_murder_of_crows
actions.st+=/stampede,if=buff.aspect_of_the_wild.up&buff.bestial_wrath.up|target.time_to_die<15
actions.st+=/bestial_wrath,if=cooldown.aspect_of_the_wild.remains>20|target.time_to_die<15
actions.st+=/kill_command
actions.st+=/chimaera_shot
actions.st+=/dire_beast
actions.st+=/barbed_shot,if=pet.cat.buff.frenzy.down&(charges_fractional>1.8|buff.bestial_wrath.up)|target.time_to_die<9
actions.st+=/the_unbound_force,if=buff.reckless_force.up|buff.reckless_force_counter.stack<10
actions.st+=/barrage
actions.st+=/cobra_shot,if=(focus-cost+focus.regen*(cooldown.kill_command.remains-1)>action.kill_command.cost|cooldown.kill_command.remains>1+gcd)&cooldown.kill_command.remains>1
actions.st+=/spitting_cobra
actions.st+=/barbed_shot,if=charges_fractional>1.4
]]
	if BarbedShot:Usable() and ((PetFrenzy:Up() and PetFrenzy:Remains() <= (Player.gcd + 0.3)) or (BarbedShot:FullRechargeTime() < Player.gcd and not BestialWrath:Ready())) then
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
	if BarbedShot:Usable() and ((PetFrenzy:Down() and (BarbedShot:ChargesFractional() > 1.8 or BestialWrath:Up())) or Target.timeToDie < 9) then
		return BarbedShot
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
actions.cleave+=/kill_command
actions.cleave+=/dire_beast
actions.cleave+=/barbed_shot,target_if=min:dot.barbed_shot.remains,if=pet.cat.buff.frenzy.down&(charges_fractional>1.8|buff.bestial_wrath.up)|charges_fractional>1.4|target.time_to_die<9
actions.cleave+=/the_unbound_force,if=buff.reckless_force.up|buff.reckless_force_counter.stack<10
actions.cleave+=/cobra_shot,if=cooldown.kill_command.remains>focus.time_to_max
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
	if KillCommandBM:Usable() then
		return KillCommandBM
	end
	if DireBeast:Usable() then
		return DireBeast
	end
	if BarbedShot:Usable() and ((PetFrenzy:Down() and (BarbedShot:ChargesFractional() > 1.8 or BestialWrath:Up())) or BarbedShot:ChargesFractional() > 1.4 or Target.timeToDie < 9) then
		return BarbedShot
	end
	if CobraShot:Usable() and KillCommandBM:Cooldown() > Player:FocusTimeToMax() then
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
		if Trinket.BottledFlayedwingToxin.can_use and Trinket.BottledFlayedwingToxin.buff:Remains() < 300 and Trinket.BottledFlayedwingToxin:Usable() then
			UseCooldown(Trinket.BottledFlayedwingToxin)
		end
		if Opt.pot and not Player:InArenaOrBattleground() then
			if GreaterFlaskOfTheCurrents:Usable() and GreaterFlaskOfTheCurrents.buff:Remains() < 300 then
				UseCooldown(GreaterFlaskOfTheCurrents)
			end
			if Target.boss and PotionOfUnbridledFury:Usable() then
				UseCooldown(PotionOfUnbridledFury)
			end
		end
		if Harpoon:Usable() then
			UseCooldown(Harpoon)
		end
	end
	if Trinket.BottledFlayedwingToxin.can_use and Trinket.BottledFlayedwingToxin.buff:Down() and Trinket.BottledFlayedwingToxin:Usable() then
		UseCooldown(Trinket.BottledFlayedwingToxin)
	end
--[[
actions=auto_attack
# Delay facing your doubt until you have put Resonating Arrow down, or if the cooldown is too long to delay facing your Doubt. If none of these conditions are able to met within the 10 seconds leeway, the sim faces your Doubt automatically.
actions+=/newfound_resolve,if=soulbind.newfound_resolve&(buff.resonating_arrow.up|cooldown.resonating_arrow.remains>10|target.time_to_die<16)
actions+=/call_action_list,name=trinkets,if=covenant.kyrian&cooldown.coordinated_assault.remains&cooldown.resonating_arrow.remains|!covenant.kyrian&cooldown.coordinated_assault.remains
actions+=/call_action_list,name=cds
actions+=/call_action_list,name=bop,if=active_enemies<3&talent.birds_of_prey.enabled
actions+=/call_action_list,name=st,if=active_enemies<3&!talent.birds_of_prey.enabled
actions+=/call_action_list,name=cleave,if=active_enemies>2
actions+=/arcane_torrent
]]
	Player.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(6, Player.enemies - 1)) or CoordinatedAssault:Up() or (WildSpirits.known and WildMark:Up())
	if Player.use_cds then
		if Opt.trinket then
			self:trinkets()
		end
		self:cds()
	end
	if Player.enemies < 3 then
		if BirdsOfPrey.known then
			return self:bop()
		end
		return self:st()
	end
	return self:cleave()
end

APL[SPEC.SURVIVAL].cds = function(self)
--[[
actions.cds=harpoon,if=talent.terms_of_engagement.enabled&focus<focus.max
actions.cds+=/blood_fury,if=buff.coordinated_assault.up
actions.cds+=/ancestral_call,if=buff.coordinated_assault.up
actions.cds+=/fireblood,if=buff.coordinated_assault.up
actions.cds+=/lights_judgment
actions.cds+=/bag_of_tricks,if=cooldown.kill_command.full_recharge_time>gcd
actions.cds+=/berserking,if=buff.coordinated_assault.up|time_to_die<13
actions.cds+=/muzzle
actions.cds+=/potion,if=target.time_to_die<25|buff.coordinated_assault.up
actions.cds+=/fleshcraft,cancel_if=channeling&!soulbind.pustule_eruption,if=(focus<70|cooldown.coordinated_assault.remains<gcd)&(soulbind.pustule_eruption|soulbind.volatile_solvent)
actions.cds+=/tar_trap,if=focus+cast_regen<focus.max&runeforge.soulforge_embers.equipped&tar_trap.remains<gcd&cooldown.flare.remains<gcd&(active_enemies>1|active_enemies=1&time_to_die>5*gcd)
actions.cds+=/flare,if=focus+cast_regen<focus.max&tar_trap.up&runeforge.soulforge_embers.equipped&time_to_die>4*gcd
actions.cds+=/kill_shot,if=active_enemies=1&target.time_to_die<focus%(variable.mb_rs_cost-cast_regen)*gcd
actions.cds+=/mongoose_bite,if=active_enemies=1&target.time_to_die<focus%(variable.mb_rs_cost-cast_regen)*gcd
actions.cds+=/raptor_strike,if=active_enemies=1&target.time_to_die<focus%(variable.mb_rs_cost-cast_regen)*gcd
actions.cds+=/aspect_of_the_eagle,if=target.distance>=6
]]
	if Opt.pot and Target.boss and not Player:InArenaOrBattleground() and PotionOfUnbridledFury:Usable() and ((CoordinatedAssault:Up() and Player:BloodlustActive()) or Target.timeToDie < 61) then
		return UseCooldown(PotionOfUnbridledFury)
	end
	if WildSpirits:Usable() and WildMark:Down() then
		return UseCooldown(WildSpirits)
	end
end

APL[SPEC.SURVIVAL].trinkets = function(self)
--[[
actions.trinkets=variable,name=sync_up,value=buff.resonating_arrow.up|buff.coordinated_assault.up
actions.trinkets+=/variable,name=strong_sync_up,value=covenant.kyrian&buff.resonating_arrow.up&buff.coordinated_assault.up|!covenant.kyrian&buff.coordinated_assault.up
actions.trinkets+=/variable,name=strong_sync_remains,op=setif,condition=covenant.kyrian,value=cooldown.resonating_arrow.remains<?cooldown.coordinated_assault.remains_guess,value_else=cooldown.coordinated_assault.remains_guess,if=buff.coordinated_assault.down
actions.trinkets+=/variable,name=strong_sync_remains,op=setif,condition=covenant.kyrian,value=cooldown.resonating_arrow.remains,value_else=cooldown.coordinated_assault.remains_guess,if=buff.coordinated_assault.up
actions.trinkets+=/variable,name=sync_remains,op=setif,condition=covenant.kyrian,value=cooldown.resonating_arrow.remains>?cooldown.coordinated_assault.remains_guess,value_else=cooldown.coordinated_assault.remains_guess
actions.trinkets+=/use_items,slots=trinket1,if=((trinket.1.has_use_buff|covenant.kyrian&trinket.1.has_cooldown)&(variable.strong_sync_up&(!covenant.kyrian&!trinket.2.has_use_buff|covenant.kyrian&!trinket.2.has_cooldown|trinket.2.cooldown.remains|trinket.1.has_use_buff&(!trinket.2.has_use_buff|trinket.1.cooldown.duration>=trinket.2.cooldown.duration)|trinket.1.has_cooldown&!trinket.2.has_use_buff&trinket.1.cooldown.duration>=trinket.2.cooldown.duration)|!variable.strong_sync_up&(!trinket.2.has_use_buff&(trinket.1.cooldown.duration-5<variable.sync_remains|variable.sync_remains>trinket.1.cooldown.duration%2)|trinket.2.has_use_buff&(trinket.1.has_use_buff&trinket.1.cooldown.duration>=trinket.2.cooldown.duration&(trinket.1.cooldown.duration-5<variable.sync_remains|variable.sync_remains>trinket.1.cooldown.duration%2)|(!trinket.1.has_use_buff|trinket.2.cooldown.duration>=trinket.1.cooldown.duration)&(trinket.2.cooldown.ready&trinket.2.cooldown.duration-5>variable.sync_remains&variable.sync_remains<trinket.2.cooldown.duration%2|!trinket.2.cooldown.ready&(trinket.2.cooldown.remains-5<variable.strong_sync_remains&variable.strong_sync_remains>20&(trinket.1.cooldown.duration-5<variable.sync_remains|trinket.2.cooldown.remains-5<variable.sync_remains&trinket.2.cooldown.duration-10+variable.sync_remains<variable.strong_sync_remains|variable.sync_remains>trinket.1.cooldown.duration%2|variable.sync_up)|trinket.2.cooldown.remains-5>variable.strong_sync_remains&(trinket.1.cooldown.duration-5<variable.strong_sync_remains|trinket.1.cooldown.duration<fight_remains&variable.strong_sync_remains+trinket.1.cooldown.duration>fight_remains|!trinket.1.has_use_buff&(variable.sync_remains>trinket.1.cooldown.duration%2|variable.sync_up))))))|target.time_to_die<variable.sync_remains)|!trinket.1.has_use_buff&!covenant.kyrian&(trinket.2.has_use_buff&((!variable.sync_up|trinket.2.cooldown.remains>5)&(variable.sync_remains>20|trinket.2.cooldown.remains-5>variable.sync_remains))|!trinket.2.has_use_buff&(!trinket.2.has_cooldown|trinket.2.cooldown.remains|trinket.2.cooldown.duration>=trinket.1.cooldown.duration)))&(!trinket.1.is.cache_of_acquired_treasures|active_enemies<2&buff.acquired_wand.up|active_enemies>1&!buff.acquired_wand.up)
actions.trinkets+=/use_items,slots=trinket2,if=((trinket.2.has_use_buff|covenant.kyrian&trinket.2.has_cooldown)&(variable.strong_sync_up&(!covenant.kyrian&!trinket.1.has_use_buff|covenant.kyrian&!trinket.1.has_cooldown|trinket.1.cooldown.remains|trinket.2.has_use_buff&(!trinket.1.has_use_buff|trinket.2.cooldown.duration>=trinket.1.cooldown.duration)|trinket.2.has_cooldown&!trinket.1.has_use_buff&trinket.2.cooldown.duration>=trinket.1.cooldown.duration)|!variable.strong_sync_up&(!trinket.1.has_use_buff&(trinket.2.cooldown.duration-5<variable.sync_remains|variable.sync_remains>trinket.2.cooldown.duration%2)|trinket.1.has_use_buff&(trinket.2.has_use_buff&trinket.2.cooldown.duration>=trinket.1.cooldown.duration&(trinket.2.cooldown.duration-5<variable.sync_remains|variable.sync_remains>trinket.2.cooldown.duration%2)|(!trinket.2.has_use_buff|trinket.1.cooldown.duration>=trinket.2.cooldown.duration)&(trinket.1.cooldown.ready&trinket.1.cooldown.duration-5>variable.sync_remains&variable.sync_remains<trinket.1.cooldown.duration%2|!trinket.1.cooldown.ready&(trinket.1.cooldown.remains-5<variable.strong_sync_remains&variable.strong_sync_remains>20&(trinket.2.cooldown.duration-5<variable.sync_remains|trinket.1.cooldown.remains-5<variable.sync_remains&trinket.1.cooldown.duration-10+variable.sync_remains<variable.strong_sync_remains|variable.sync_remains>trinket.2.cooldown.duration%2|variable.sync_up)|trinket.1.cooldown.remains-5>variable.strong_sync_remains&(trinket.2.cooldown.duration-5<variable.strong_sync_remains|trinket.2.cooldown.duration<fight_remains&variable.strong_sync_remains+trinket.2.cooldown.duration>fight_remains|!trinket.2.has_use_buff&(variable.sync_remains>trinket.2.cooldown.duration%2|variable.sync_up))))))|target.time_to_die<variable.sync_remains)|!trinket.2.has_use_buff&!covenant.kyrian&(trinket.1.has_use_buff&((!variable.sync_up|trinket.1.cooldown.remains>5)&(variable.sync_remains>20|trinket.1.cooldown.remains-5>variable.sync_remains))|!trinket.1.has_use_buff&(!trinket.1.has_cooldown|trinket.1.cooldown.remains|trinket.1.cooldown.duration>=trinket.2.cooldown.duration)))&(!trinket.2.is.cache_of_acquired_treasures|active_enemies<2&buff.acquired_wand.up|active_enemies>1&!buff.acquired_wand.up)
actions.trinkets+=/use_item,name=jotungeirr_destinys_call
]]
	if Trinket1:Usable() then
		return UseCooldown(Trinket1)
	elseif Trinket2:Usable() then
		return UseCooldown(Trinket2)
	end
end

APL[SPEC.SURVIVAL].nta = function(self)
--[[
actions.nta=steel_trap
actions.nta+=/freezing_trap,if=!buff.wild_spirits.remains|buff.wild_spirits.remains&cooldown.kill_command.remains
actions.nta+=/tar_trap,if=!buff.wild_spirits.remains|buff.wild_spirits.remains&cooldown.kill_command.remains
]]
	if SteelTrap:Usable() then
		UseCooldown(SteelTrap)
	end
	if FreezingTrap:Usable() and (not WildSpirits.known or WildMark:Down() or not KillCommand:Ready()) then
		UseCooldown(FreezingTrap)
	end
	if TarTrap:Usable() and (not WildSpirits.known or WildMark:Down() or not KillCommand:Ready()) then
		UseCooldown(TarTrap)
	end
end

APL[SPEC.SURVIVAL].bop = function(self)
--[[
actions.bop=serpent_sting,target_if=min:remains,if=buff.vipers_venom.remains&(buff.vipers_venom.remains<gcd|refreshable)
actions.bop+=/kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max&buff.nesingwarys_trapping_apparatus.up|focus+cast_regen<focus.max+10&buff.nesingwarys_trapping_apparatus.up&buff.nesingwarys_trapping_apparatus.remains<gcd
actions.bop+=/kill_shot
actions.bop+=/wildfire_bomb,if=focus+cast_regen<focus.max&full_recharge_time<gcd|buff.mad_bombardier.up
actions.bop+=/flanking_strike,if=focus+cast_regen<focus.max
actions.bop+=/flayed_shot
actions.bop+=/call_action_list,name=nta,if=runeforge.nessingwarys_trapping_apparatus.equipped&focus<variable.mb_rs_cost
actions.bop+=/death_chakram,if=focus+cast_regen<focus.max
actions.bop+=/raptor_strike,target_if=max:debuff.latent_poison_injection.stack,if=buff.coordinated_assault.up&buff.coordinated_assault.remains<1.5*gcd
actions.bop+=/mongoose_bite,target_if=max:debuff.latent_poison_injection.stack,if=buff.coordinated_assault.up&buff.coordinated_assault.remains<1.5*gcd
actions.bop+=/a_murder_of_crows
actions.bop+=/raptor_strike,target_if=max:debuff.latent_poison_injection.stack,if=buff.tip_of_the_spear.stack=3
actions.bop+=/mongoose_bite,target_if=max:debuff.latent_poison_injection.stack,if=talent.alpha_predator.enabled&(buff.mongoose_fury.up&buff.mongoose_fury.remains<focus%(variable.mb_rs_cost-cast_regen)*gcd)
actions.bop+=/wildfire_bomb,if=focus+cast_regen<focus.max&!ticking&(full_recharge_time<gcd|!dot.wildfire_bomb.ticking&buff.mongoose_fury.remains>full_recharge_time-1*gcd|!dot.wildfire_bomb.ticking&!buff.mongoose_fury.remains)|time_to_die<18&!dot.wildfire_bomb.ticking
# If you don't have Nessingwary's Trapping Apparatus, simply cast Kill Command if you won't overcap on Focus from doing so. If you do have Nessingwary's Trapping Apparatus you should cast Kill Command if your focus is below the cost of Mongoose Bite or Raptor Strike
actions.bop+=/kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max&(!runeforge.nessingwarys_trapping_apparatus|focus<variable.mb_rs_cost)
# With Nessingwary's Trapping Apparatus only Kill Command if your traps are on cooldown, otherwise stop using Kill Command if your current focus amount is enough to sustain the amount of time left for any of your traps to come off cooldown
actions.bop+=/kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max&runeforge.nessingwarys_trapping_apparatus&cooldown.freezing_trap.remains>(focus%(variable.mb_rs_cost-cast_regen)*gcd)&cooldown.tar_trap.remains>(focus%(variable.mb_rs_cost-cast_regen)*gcd)&(!talent.steel_trap|talent.steel_trap&cooldown.steel_trap.remains>(focus%(variable.mb_rs_cost-cast_regen)*gcd))
actions.bop+=/steel_trap,if=focus+cast_regen<focus.max
actions.bop+=/serpent_sting,target_if=min:remains,if=dot.serpent_sting.refreshable&!buff.coordinated_assault.up|talent.alpha_predator&refreshable&!buff.mongoose_fury.up
actions.bop+=/resonating_arrow
actions.bop+=/wild_spirits
actions.bop+=/coordinated_assault,if=!buff.coordinated_assault.up
actions.bop+=/mongoose_bite,if=buff.mongoose_fury.up|focus+action.kill_command.cast_regen>focus.max|buff.coordinated_assault.up
actions.bop+=/raptor_strike,target_if=max:debuff.latent_poison_injection.stack
actions.bop+=/wildfire_bomb,if=dot.wildfire_bomb.refreshable
actions.bop+=/serpent_sting,target_if=min:remains,if=buff.vipers_venom.up
]]

end

APL[SPEC.SURVIVAL].st = function(self)
--[[
actions.st=death_chakram,if=focus+cast_regen<focus.max&(!raid_event.adds.exists|!raid_event.adds.up&raid_event.adds.duration+raid_event.adds.in<5)|raid_event.adds.up&raid_event.adds.remains>40
actions.st+=/serpent_sting,target_if=min:remains,if=!dot.serpent_sting.ticking&target.time_to_die>7|buff.vipers_venom.up&buff.vipers_venom.remains<gcd
actions.st+=/flayed_shot
actions.st+=/resonating_arrow,if=!raid_event.adds.exists|!raid_event.adds.up&(raid_event.adds.duration+raid_event.adds.in<20|raid_event.adds.count=1)|raid_event.adds.up&raid_event.adds.remains>40|time_to_die<10
actions.st+=/wild_spirits,if=!raid_event.adds.exists|!raid_event.adds.up&raid_event.adds.duration+raid_event.adds.in<20|raid_event.adds.up&raid_event.adds.remains>20|time_to_die<20
actions.st+=/coordinated_assault,if=!raid_event.adds.exists|covenant.night_fae&cooldown.wild_spirits.remains|!covenant.night_fae&(!raid_event.adds.up&raid_event.adds.duration+raid_event.adds.in<30|raid_event.adds.up&raid_event.adds.remains>20|!raid_event.adds.up)|time_to_die<30
actions.st+=/kill_shot
actions.st+=/flanking_strike,if=focus+cast_regen<focus.max
actions.st+=/a_murder_of_crows
actions.st+=/wildfire_bomb,if=full_recharge_time<2*gcd&set_bonus.tier28_2pc|buff.mad_bombardier.up|!set_bonus.tier28_2pc&(full_recharge_time<gcd|focus+cast_regen<focus.max&(next_wi_bomb.volatile&dot.serpent_sting.ticking&dot.serpent_sting.refreshable|next_wi_bomb.pheromone&!buff.mongoose_fury.up&focus+cast_regen<focus.max-action.kill_command.cast_regen*3)|time_to_die<10)
actions.st+=/kill_command,target_if=min:bloodseeker.remains,if=set_bonus.tier28_2pc&dot.pheromone_bomb.ticking&!buff.mad_bombardier.up&(focus+cast_regen<focus.max|buff.tip_of_the_spear.stack<3)
actions.st+=/carve,if=active_enemies>1&!runeforge.rylakstalkers_confounding_strikes.equipped
actions.st+=/butchery,if=active_enemies>1&!runeforge.rylakstalkers_confounding_strikes.equipped&cooldown.wildfire_bomb.full_recharge_time>spell_targets&(charges_fractional>2.5|dot.shrapnel_bomb.ticking)
actions.st+=/steel_trap,if=focus+cast_regen<focus.max
actions.st+=/mongoose_bite,target_if=max:debuff.latent_poison_injection.stack,if=talent.alpha_predator.enabled&(buff.mongoose_fury.up&buff.mongoose_fury.remains<focus%(variable.mb_rs_cost-cast_regen)*gcd&!buff.wild_spirits.remains|buff.mongoose_fury.remains&next_wi_bomb.pheromone)
actions.st+=/kill_command,target_if=min:bloodseeker.remains,if=full_recharge_time<gcd&focus+cast_regen<focus.max
actions.st+=/raptor_strike,target_if=max:debuff.latent_poison_injection.stack,if=buff.tip_of_the_spear.stack=3|dot.shrapnel_bomb.ticking
actions.st+=/mongoose_bite,if=dot.shrapnel_bomb.ticking
actions.st+=/wildfire_bomb,if=next_wi_bomb.volatile&dot.serpent_sting.refreshable&dot.serpent_sting.remains>travel_time&charges_fractional>1.5
actions.st+=/serpent_sting,target_if=min:remains,if=refreshable&target.time_to_die>7|buff.vipers_venom.up
actions.st+=/wildfire_bomb,if=next_wi_bomb.shrapnel&focus>variable.mb_rs_cost*2&dot.serpent_sting.remains>5*gcd&!set_bonus.tier28_2pc
actions.st+=/chakrams
actions.st+=/kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max
actions.st+=/wildfire_bomb,if=runeforge.rylakstalkers_confounding_strikes.equipped
actions.st+=/mongoose_bite,target_if=max:debuff.latent_poison_injection.stack,if=buff.mongoose_fury.up|focus+action.kill_command.cast_regen>focus.max-15|dot.shrapnel_bomb.ticking|buff.wild_spirits.remains
actions.st+=/raptor_strike,target_if=max:debuff.latent_poison_injection.stack
actions.st+=/wildfire_bomb,if=(next_wi_bomb.volatile&dot.serpent_sting.ticking|next_wi_bomb.pheromone|next_wi_bomb.shrapnel&focus>50)&!set_bonus.tier28_2pc
]]
	if DeathChakram:Usable() and DeathCharkram:WontCapFocus() then
		UseCooldown(DeathChakram)
	end
	if SerpentSting:Usable() and ((SerpentSting:Down() and Target.timeToDie > 7) or (VipersVenom:Up() and VipersVenom:Remains() < Player.gcd)) then
		return SerpentSting
	end
	if FlayedShot:Usable() then
		return FlayedShot
	end
	if ResonatingArrow:Usable() then
		UseCooldown(ResonatingArrow)
	end
	if WildSpirits:Usable() and WildMark:Down() and (CoordinatedAssault:Up() or CoordinatedAssault:Ready() or not CoordinatedAssault:Ready(20)) then
		UseCooldown(WildSpirits)
	end
	if CoordinatedAssault:Usable() and (not WildSpirits.known or WildSpirits:Ready() or WildMark:Up() or (Target.boss and Target.timeToDie < 30)) then
		UseCooldown(CoordinatedAssault)
	end
	if KillShot:Usable() then
		return KillShot
	end
	if FlankingStrike:Usable() and FlankingStrike:WontCapFocus() then
		return FlankingStrike
	end
	if AMurderOfCrows:Usable() then
		UseCooldown(AMurderOfCrows)
	end
	if WildfireBomb:Usable() then
		if MadBombardier.known then
			if WildfireBomb:FullRechargeTime() < (Player.gcd * 2) or MadBombardier:Up() then
				return WildfireBomb
			end
		elseif WildfireBomb:FullRechargeTime() < Player.gcd or Target.timeToDie < 10 or (WildfireBomb:WontCapFocus() and ((VolatileBomb.next and SerpentSting:Remains() > WildfireBomb:TravelTime() and SerpentSting:Refreshable()) or (PheromoneBomb.next and MongooseFury:Down() and (Player:Focus() + WildfireBomb:CastRegen()) < (Player:FocusMax() - KillCommand:CastRegen() * 3)))) then
			return WildfireBomb
		end
	end
	if MadBombardier.known and KillCommand:Usable() and PheromoneBomb:Up() and MadBombardier:Down() and (KillCommand:WontCapFocus() or TipOfTheSpear:Stack() < 3) then
		return KillCommand
	end
	if Player.enemies > 1 and not RylakstalkersConfoundingStrikes.known then
		if Carve:Usable() then
			return Carve
		end
		if Butchery:Usable() and WildfireBomb:FullRechargeTime() > Player.enemies and (Butchery:ChargesFractional() > 2.5 or (WildfireInfusion.known and ShrapnelBomb:Up())) then
			return Butchery
		end
	end
	if SteelTrap:Usable() and SteelTrap:WontCapFocus() then
		UseCooldown(SteelTrap)
	end
	if AlphaPredator.known and MongooseBite:Usable() and MongooseFury:Up() and (PheromoneBomb.next or (MongooseFury:Remains() < (Player:Focus() / (MongooseBite:Cost() - MongooseBite:CastRegen()) * Player.gcd) and WildMark:Down())) then
		return MongooseBite
	end
	if KillCommand:Usable() and KillCommand:WontCapFocus() and KillCommand:FullRechargeTime() < Player.gcd then
		return KillCommand
	end
	if RaptorStrike:Usable() and ((TipOfTheSpear.known and TipOfTheSpear:Stack() >= 3) or (WildfireInfusion.known and ShrapnelBomb:Up())) then
		return RaptorStrike
	end
	if WildfireInfusion.known and MongooseBite:Usable() and ShrapnelBomb:Up() then
		return MongooseBite
	end
	if WildfireInfusion.known and WildfireBomb:Usable() and VolatileBomb.next and SerpentSting:Refreshable() and SerpentSting:Remains() > WildfireBomb:TravelTime() and WildfireBomb:ChargesFractional() > 1.5 then
		return WildfireBomb
	end
	if SerpentSting:Usable() and ((SerpentSting:Refreshable() and Target.timeToDie > 7) or (VipersVenom.known and VipersVenom:Up())) then
		return SerpentSting
	end
	if WildfireInfusion.known and not MadBombardier.known and WildfireBomb:Usable() and ShrapnelBomb.next and Player:Focus() > (RaptorStrike:Cost() * 2) and SerpentSting:Remains() > (5 * Player.gcd) then
		return WildfireBomb
	end
	if Chakrams:Usable() then
		return Chakrams
	end
	if KillCommand:Usable() and KillCommand:WontCapFocus() then
		return KillCommand
	end
	if RylakstalkersConfoundingStrikes.known and WildfireBomb:Usable() then
		return WildfireBomb
	end
	if MongooseBite:Usable() and (MongooseFury:Up() or (Player:Focus() + KillCommand:CastRegen()) > (Player:FocusMax() - 15) or ShrapnelBomb:Up() or WildMark:Up()) then
		return MongooseBite
	end
	if RaptorStrike:Usable() then
		return RaptorStrike
	end
	if WildfireInfusion.known and not MadBombardier.known and WildfireBomb:Usable() and (PheromoneBomb.next or (ShrapnelBomb.next and Player:Focus() > 50) or (VolatileBomb.next and SerpentSting:Remains() > WildfireBomb:TravelTime())) then
		return WildfireBomb
	end
end

APL[SPEC.SURVIVAL].cleave = function(self)
--[[
actions.cleave=serpent_sting,target_if=min:remains,if=talent.hydras_bite.enabled&buff.vipers_venom.remains&buff.vipers_venom.remains<gcd
actions.cleave+=/wild_spirits,if=!raid_event.adds.exists|raid_event.adds.remains>=10|active_enemies>=raid_event.adds.count*2
actions.cleave+=/resonating_arrow,if=!raid_event.adds.exists|raid_event.adds.remains>=8|active_enemies>=raid_event.adds.count*2
actions.cleave+=/coordinated_assault,if=!raid_event.adds.exists|raid_event.adds.remains>=10|active_enemies>=raid_event.adds.count*2
actions.cleave+=/wildfire_bomb,if=full_recharge_time<gcd
actions.cleave+=/death_chakram,if=(!raid_event.adds.exists|raid_event.adds.remains>5|active_enemies>=raid_event.adds.count*2)|focus+cast_regen<focus.max&!runeforge.bag_of_munitions.equipped
actions.cleave+=/call_action_list,name=nta,if=runeforge.nessingwarys_trapping_apparatus.equipped&focus<variable.mb_rs_cost
actions.cleave+=/chakrams
actions.cleave+=/butchery,if=dot.shrapnel_bomb.ticking&(dot.internal_bleeding.stack<2|dot.shrapnel_bomb.remains<gcd)
actions.cleave+=/carve,if=dot.shrapnel_bomb.ticking&!set_bonus.tier28_2pc
actions.cleave+=/butchery,if=charges_fractional>2.5&cooldown.wildfire_bomb.full_recharge_time>spell_targets%2
actions.cleave+=/flanking_strike,if=focus+cast_regen<focus.max
actions.cleave+=/carve,if=cooldown.wildfire_bomb.full_recharge_time>spell_targets%2
actions.cleave+=/wildfire_bomb,if=buff.mad_bombardier.up
actions.cleave+=/kill_command,target_if=dot.pheromone_bomb.ticking&set_bonus.tier28_2pc
actions.cleave+=/kill_shot,if=buff.flayers_mark.up
actions.cleave+=/flayed_shot,target_if=max:target.health.pct
actions.cleave+=/serpent_sting,target_if=min:remains,if=refreshable&!ticking&next_wi_bomb.volatile&target.time_to_die>15&focus+cast_regen>35&active_enemies<=4
actions.cleave+=/kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max&full_recharge_time<gcd&(runeforge.nessingwarys_trapping_apparatus.equipped&cooldown.freezing_trap.remains&cooldown.tar_trap.remains|!runeforge.nessingwarys_trapping_apparatus.equipped)
actions.cleave+=/wildfire_bomb,if=!dot.wildfire_bomb.ticking&!set_bonus.tier28_2pc|charges_fractional>1.3
actions.cleave+=/butchery,if=(!next_wi_bomb.shrapnel|!talent.wildfire_infusion.enabled)&cooldown.wildfire_bomb.full_recharge_time>spell_targets%2
actions.cleave+=/a_murder_of_crows
actions.cleave+=/steel_trap,if=focus+cast_regen<focus.max
actions.cleave+=/serpent_sting,target_if=min:remains,if=refreshable&talent.hydras_bite.enabled&target.time_to_die>8
actions.cleave+=/carve
actions.cleave+=/kill_command,target_if=focus+cast_regen<focus.max&(runeforge.nessingwarys_trapping_apparatus.equipped&cooldown.freezing_trap.remains&cooldown.tar_trap.remains|!runeforge.nessingwarys_trapping_apparatus.equipped)
actions.cleave+=/kill_shot
actions.cleave+=/serpent_sting,target_if=min:remains,if=refreshable&target.time_to_die>8
actions.cleave+=/mongoose_bite,target_if=max:debuff.latent_poison_injection.stack
actions.cleave+=/raptor_strike,target_if=max:debuff.latent_poison_injection.stack
]]
	if HydrasBite.known and SerpentSting:Usable() and VipersVenom:Up() and VipersVenom:Remains() < Player.gcd then
		return SerpentSting
	end
	if WildSpirits:Usable() and WildMark:Down() and (CoordinatedAssault:Up() or CoordinatedAssault:Ready() or not CoordinatedAssault:Ready(20)) then
		UseCooldown(WildSpirits)
	end
	if ResonatingArrow:Usable() then
		UseCooldown(ResonatingArrow)
	end
	if CoordinatedAssault:Usable() and (not WildSpirits.known or WildSpirits:Ready() or WildMark:Up()) then
		UseCooldown(CoordinatedAssault)
	end
	if WildfireBomb:Usable() and WildfireBomb:FullRechargeTime() < Player.gcd then
		return WildfireBomb
	end
	if DeathChakram:Usable() then
		UseCooldown(DeathChakram)
	end
	if Chakrams:Usable() then
		return Chakrams
	end
	if Butchery:Usable() and ShrapnelBomb:Up() and (InternalBleeding:Stack() < 2 or ShrapnelBomb:Remains() < Player.gcd) then
		return Butchery
	end
	if Carve:Usable() and ShrapnelBomb:Up() and not MadBombardier.known then
		return Carve
	end
	if Butchery:Usable() and Butchery:ChargesFractional() > 2.5 and WildfireBomb:FullRechargeTime() > (Player.enemies / 2) then
		return Butchery
	end
	if FlankingStrike:Usable() and FlankingStrike:WontCapFocus() then
		return FlankingStrike
	end
	if Carve:Usable() and WildfireBomb:FullRechargeTime() > (Player.enemies / 2) then
		return Carve
	end
	if MadBombardier.known then
		if WildfireBomb:Usable() and MadBombardier:Up() then
			return WildfireBomb
		end
		if KillCommand:Usable() and PheromoneBomb:Up() then
			return KillCommand
		end
	end
	if FlayedShot.known then
		if KillShot:Usable() and FlayersMark:Up() then
			return KillShot
		end
		if FlayedShot:Usable() then
			return FlayedShot
		end
	end
	if SerpentSting:Usable() and SerpentSting:Refreshable() and VolatileBomb.next and Target.timeToDie > 15 and (Player:Focus() + SerpentSting:CastRegen()) > 35 and Player.enemies <= 4 then
		return SerpentSting
	end
	if KillCommand:Usable() and KillCommand:WontCapFocus() and KillCommand:FullRechargeTime() < Player.gcd and (not NesingwarysTrappingApparatus.known or not (FreezingTrap:Ready() or TarTrap:Ready())) then
		return KillCommand
	end
	if WildfireBomb:Usable() and (WildfireBomb:ChargesFractional() > 1.3 or (not MadBombardier.known and WildfireBomb:Down())) then
		return WildfireBomb
	end
	if Butchery:Usable() and (not WildfireInfusion.known or not ShrapnelBomb.next) and WildfireBomb:FullRechargeTime() > (Player.enemies / 2) then
		return Butchery
	end
	if AMurderOfCrows:Usable() then
		UseCooldown(AMurderOfCrows)
	end
	if SteelTrap:Usable() and SteelTrap:WontCapFocus() then
		UseCooldown(SteelTrap)
	end
	if HydrasBite.known and SerpentSting:Usable() and SerpentSting:Refreshable() and Target.timeToDie > 8 then
		return SerpentSting
	end
	if Carve:Usable() then
		return Carve
	end
	if KillCommand:Usable() and KillCommand:WontCapFocus() and (not NesingwarysTrappingApparatus.known or not (FreezingTrap:Ready() or TarTrap:Ready())) then
		return KillCommand
	end
	if KillShot:Usable() then
		return KillShot
	end
	if SerpentSting:Usable() and SerpentSting:Refreshable() and Target.timeToDie > 8 then
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
	local w, h, glow
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
	local glow, icon
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
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.MARKSMANSHIP] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
		},
		[SPEC.SURVIVAL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 }
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
		self.anchor.frame = NamePlateDriverFrame:GetClassNameplateManaBar()
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
	local dim, dim_cd, text_center, text_cd

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.wait_time then
		local deficit = Player.wait_time - GetTime()
		if deficit > 0 then
			text_center = format('WAIT %.1fs', deficit)
			dim = Opt.dimmer
		end
	end
	if Player.main and Player.main.requires_react then
		local react = Player.main:React()
		if react > 0 then
			text_center = format('%.1f', react)
		end
	end
	if Player.cd and Player.cd.requires_react then
		local react = Player.cd:React()
		if react > 0 then
			text_cd = format('%.1f', react)
		end
	end

	ghPanel.dimmer:SetShown(dim)
	ghPanel.text.center:SetText(text_center)
	--ghPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	ghCooldownPanel.text:SetText(text_cd)
	ghCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	timer.combat = 0
	
	Player:Update()

	Player.main = APL[Player.spec]:main()
	if Player.main then
		ghPanel.icon:SetTexture(Player.main.icon)
	end
	if Player.cd then
		ghCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local start, duration = GetSpellCooldown(Player.cd.spellId)
			ghCooldownPanel.swipe:SetCooldown(start, duration)
		end
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
			ghInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			ghInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		ghInterruptPanel.icon:SetShown(Player.interrupt)
		ghInterruptPanel.border:SetShown(Player.interrupt)
		ghInterruptPanel:SetShown(start and not notInterruptible)
	end
	if Opt.previous and ghPreviousPanel.ability then
		if (Player.time - ghPreviousPanel.ability.last_used) > 10 then
			ghPreviousPanel.ability = nil
			ghPreviousPanel:Hide()
		end
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
	if name == ADDON then
		Opt = GoodHunting
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_GoodHunting1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 10 then
			print('[|cFFFFD000Warning|r] ' .. ADDON .. ' is not designed for players under level 10, and almost certainly will not operate properly!')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player:UpdateTime(timeStamp)
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
	   e == 'RANGE_DAMAGE' or
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_AURA_REMOVED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_PERIODIC_DAMAGE' or
	   e == 'SPELL_MISSED' or
	   e == 'SPELL_AURA_APPLIED' or
	   e == 'SPELL_AURA_REFRESH' or
	   e == 'SPELL_AURA_REMOVED')
	then
		e = 'SPELL'
	end
	if CombatEvent[e] then
		return CombatEvent[e](event, srcGUID, dstGUID, ...)
	end
end

CombatEvent.UNIT_DIED = function(event, srcGUID, dstGUID)
	trackAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		autoAoe:Remove(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand)
		if Opt.auto_aoe then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, true)
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			autoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType)
	if not (srcGUID == Player.guid or srcGUID == Player.pet.guid) then
		return
	end

	if srcGUID == Player.pet.guid then
		if Player.pet.stuck and (event == 'SPELL_CAST_SUCCESS' or event == 'SPELL_DAMAGE' or event == 'SWING_DAMAGE') then
			Player.pet.stuck = false
		elseif not Player.pet.stuck and event == 'SPELL_CAST_FAILED' and missType == 'No path available' then
			Player.pet.stuck = true
		end
	end

	local ability = spellId and abilities.bySpellId[spellId]
	if not ability then
		--print(format('EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d', event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		ability:CastSuccess(dstGUID)
		return
	elseif event == 'SPELL_CAST_START' then
		ability:CastStart(dstGUID)
		return
	elseif event == 'SPELL_CAST_FAILED' then
		ability:CastFailed(dstGUID, missType)
		return
	end

	if dstGUID == Player.guid or dstGUID == Player.pet.guid then
		return -- ignore buffs beyond here
	end
	if ability.aura_targets then
		if event == 'SPELL_AURA_APPLIED' then
			ability:ApplyAura(dstGUID)
		elseif event == 'SPELL_AURA_REFRESH' then
			ability:RefreshAura(dstGUID)
		elseif event == 'SPELL_AURA_REMOVED' then
			ability:RemoveAura(dstGUID)
		end
	end
	if Opt.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:Remove(dstGUID)
		elseif ability.auto_aoe and (event == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			ability:RecordTargetHit(dstGUID)
		end
	end
	if event == 'RANGE_DAMAGE' or event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
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

function events:UNIT_SPELLCAST_START(unitID, castGUID, spellId)
	if Opt.interrupt and unitID == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(unitID, castGUID, spellId)
	if Opt.interrupt and unitID == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
events.UNIT_SPELLCAST_FAILED = events.UNIT_SPELLCAST_STOP
events.UNIT_SPELLCAST_INTERRUPTED = events.UNIT_SPELLCAST_STOP

function events:UNIT_SPELLCAST_SUCCEEDED(unitID, castGUID, spellId)
	if unitID ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Player.pet.stuck = false
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		ghPreviousPanel:Hide()
	end
	for _, ability in next, abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
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
	local _, equipType, hasCooldown
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

	Player.set_bonus.t28 = (Player:Equipped(188859) and 1 or 0) + (Player:Equipped(188861) and 1 or 0) + (Player:Equipped(188856) and 1 or 0) + (Player:Equipped(188858) and 1 or 0) + (Player:Equipped(188860) and 1 or 0)

	Player:UpdateAbilities()
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	ghPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
	events:SPELL_UPDATE_ICON()
	UI.OnResourceFrameShow()
	Player:Update()
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

function events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateAbilities()
end

function events:SOULBIND_ACTIVATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_NODE_UPDATED()
	Player:UpdateAbilities()
end

function events:SOULBIND_PATH_CHANGED()
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
		Player.pet.stuck = true
	end
end

function events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() events:PLAYER_EQUIPMENT_CHANGED() end)
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
	print(ADDON, '-', desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
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
			Opt.alpha = max(0, min(100, tonumber(msg[2]) or 100)) / 100
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
				Opt.glow.color.r = max(0, min(1, tonumber(msg[3]) or 0))
				Opt.glow.color.g = max(0, min(1, tonumber(msg[4]) or 0))
				Opt.glow.color.b = max(0, min(1, tonumber(msg[5]) or 0))
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
		return Status('Show the ' .. ADDON .. ' UI without a target', Opt.always_on)
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return Status('Use ' .. ADDON .. ' for cooldown management', Opt.cooldown)
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
	if msg[1] == 'ttd' then
		if msg[2] then
			Opt.cd_ttd = tonumber(msg[2]) or 8
		end
		return Status('Minimum enemy lifetime to use cooldowns on (ignored on bosses)', Opt.cd_ttd, 'seconds')
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
	print(ADDON, '(version: |cFFFFD000' .. GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000beastmastery|r/|cFFFFD000marksmanship|r/|cFFFFD000survival|r  - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'mend |cFFFFD000[percent]|r  - health percentage to recommend Mend Pet at (default is 65%, 0 to disable)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_GoodHunting1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
