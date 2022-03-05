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
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitRangedDamage = _G.UnitRangedDamage
local UnitAura = _G.UnitAura
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

GoodHuntingConfig = {}
local Opt -- use this as a local table reference to GoodHuntingConfig

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
	SetDefaults(GoodHuntingConfig, { -- defaults
		locked = false,
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
		shot_timer = true,
		shot_speed = true,
		steady_macro = true,
		mend_threshold = 65,
		viper_low = 15,
		viper_high = 50,
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
	health = 0
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	target_mode = 0,
	cast_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	gcd = 1.5,
	gcd_remains = 0,
	health = 0,
	health_max = 0,
	mana = {
		base = 0,
		current = 0,
		max = 0,
		regen = 0,
		tick_mana = 0,
		tick_interval = 2,
		next_tick = 0,
		per_tick = 0,
		time_until_tick = 0,
		fsr_break = 0,
	},
	group_size = 1,
	moving = false,
	movement_speed = 100,
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		last_taken = 0,
	},
	pet = {
		guid = 0,
		active = false,
		alive = false,
		stuck = false,
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
	},
}

-- current target information
local Target = {
	boss = false,
	guid = 0,
	health_array = {},
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
ghPanel.button = CreateFrame('Button', nil, ghPanel)
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
local ghScanTooltip = CreateFrame('GameTooltip', 'ghScanTooltip', nil, 'GameTooltipTemplate')
ghScanTooltip:SetOwner(UIParent, 'ANCHOR_NONE')

-- Start AoE

Player.target_modes = {
	{1, ''},
	{2, '2'},
	{3, '3'},
	{4, '4'},
	{5, '5+'},
}

function Player:SetTargetMode(mode)
	if mode == self.target_mode then
		return
	end
	self.target_mode = min(mode, #self.target_modes)
	self.enemies = self.target_modes[self.target_mode][1]
	ghPanel.text.br:SetText(self.target_modes[self.target_mode][2])
end

function Player:ToggleTargetMode()
	local mode = self.target_mode + 1
	self:SetTargetMode(mode > #self.target_modes and 1 or mode)
end

function Player:ToggleTargetModeReverse()
	local mode = self.target_mode - 1
	self:SetTargetMode(mode < 1 and #self.target_modes or mode)
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
	for i = #Player.target_modes, 1, -1 do
		if count >= Player.target_modes[i][1] then
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
	all = {}
}

function Ability:Add(spellId, buff, player)
	local ability = {
		spellIds = type(spellId) == 'table' and spellId or { spellId },
		spellId = 0,
		name = false,
		rank = 0,
		icon = false,
		requires_charge = false,
		requires_react = false,
		requires_pet = false,
		triggers_combat = false,
		triggers_gcd = true,
		hasted_duration = false,
		hasted_cooldown = false,
		hasted_ticks = false,
		known = false,
		mana_cost = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		max_range = 35,
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
		if spell == self.spellId then
			return true
		end
		for _, id in next, self.spellIds do
			if spell == id then
				return true
			end
		end
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

function Ability:Usable(seconds)
	if not self.known then
		return false
	end
	if self:ManaCost() > Player.mana.current then
		return false
	end
	if self.requires_charge and self:Charges() == 0 then
		return false
	end
	if self.requires_react and not IsUsableSpell(self.spellId) then
		return false
	end
	if self.requires_pet and not Player.pet.active then
		return false
	end
	return self:Ready(seconds)
end

function Ability:Remains(mine)
	if self:Casting() or self:Traveling() > 0 then
		return self:Duration()
	end
	local _, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter .. (mine and '|PLAYER' or ''))
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

function Ability:ManaCost()
	return self.mana_cost
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

function Ability:CastFailed(dstGUID)
	return
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if self.traveling and self.next_castGUID then
		self.traveling[self.next_castGUID] = {
			guid = self.next_castGUID,
			start = self.last_used,
			dstGUID = dstGUID,
		}
		self.next_castGUID = nil
	end
	if Opt.previous and ghPanel:IsVisible() then
		ghPreviousPanel.ability = self
		ghPreviousPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
		ghPreviousPanel.icon:SetTexture(self.icon)
		ghPreviousPanel:Show()
	end
	if self.aura_targets and self.requires_react then
		self:RemoveAura(self.auraTarget == 'player' and Player.guid or dstGUID)
	end
end

function Ability:CastLanded(dstGUID, event)
	if not self.traveling then
		return
	end
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

-- Start DoT Tracking

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
	return self:ApplyAura(guid)
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT Tracking

-- Hunter Abilities
---- General

---- Beast Mastery
local AspectOfTheCheetah = Ability:Add({5118}, true, true)
AspectOfTheCheetah.mana_cost = 40
local AspectOfTheHawk = Ability:Add({13165, 14318, 14319, 14320, 14321, 14322, 25296, 27044}, true, true)
AspectOfTheHawk.mana_costs = {20, 35, 50, 70, 90, 110, 120, 140}
local AspectOfThePack = Ability:Add({13159}, true, true)
AspectOfThePack.mana_cost = 100
local AspectOfTheViper = Ability:Add({34074}, true, true)
AspectOfTheViper.mana_cost = 40
local CallPet = Ability:Add({883}, false, true)
local FeedPet = Ability:Add({6991}, true, true)
FeedPet.requires_pet = true
FeedPet.buff = Ability:Add({1539}, true, true)
FeedPet.buff.buff_duration = 20
FeedPet.buff.tick_interval = 2
FeedPet.buff.auraTarget = 'pet'
local KillCommand = Ability:Add({34026}, true, true)
KillCommand.mana_costs = {75}
KillCommand.buff_duration = 5 -- use 5 second imaginary buff triggered by crits
KillCommand.cooldown_duration = 5
KillCommand.triggers_gcd = false
KillCommand.requires_react = true
KillCommand.requires_pet = true
local MendPet = Ability:Add({136, 3111, 3661, 3662, 13542, 13543, 13544, 27046}, true, true)
MendPet.mana_costs = {40, 70, 100, 130, 165, 200, 250, 300}
MendPet.buff_duration = 15
MendPet.tick_interval = 3
MendPet.auraTarget = 'pet'
MendPet.requires_pet = true
local RevivePet = Ability:Add({982}, false, true)
RevivePet.mana_cost_pct = 80
------ Talents

------ Procs

---- Marksmanship
local AimedShot = Ability:Add({19434, 20900, 20901, 20902, 20903, 20904, 27065}, false, true)
AimedShot.mana_costs = {75, 115, 160, 210, 260, 310, 370}
AimedShot.cooldown_duration = 6
AimedShot.triggers_combat = true
AimedShot:SetVelocity(35)
local ArcaneShot = Ability:Add({3044, 14281, 14282, 14283, 14284, 14285, 14286, 14287, 27019}, false, true)
ArcaneShot.mana_costs = {25, 35, 50, 80, 105, 135, 160, 190, 230}
ArcaneShot.cooldown_duration = 6
ArcaneShot:SetVelocity(35)
local AutoShot = Ability:Add({75}, false, true)
AutoShot.next = 0
AutoShot.speed = 0
AutoShot.base_speed = 0
local HuntersMark = Ability:Add({1130, 14323, 14324, 14325})
HuntersMark.mana_costs = {15, 30, 45, 60}
HuntersMark.buff_duration = 120
HuntersMark:TrackAuras()
local MultiShot = Ability:Add({2643, 14288, 14289, 14290, 25294, 27021}, false, true)
MultiShot.mana_costs = {100, 140, 175, 210, 230, 275}
MultiShot.cooldown_duration = 10
MultiShot:SetVelocity(35)
MultiShot:AutoAoe()
local RapidFire = Ability:Add({3045}, true, true)
RapidFire.mana_cost = 100
RapidFire.buff_duration = 15
RapidFire.cooldown_duration = 300
RapidFire.triggers_gcd = false
local SerpentSting = Ability:Add({1978, 13549, 13550, 13551, 13552, 13553, 13554, 13555, 25295, 27016}, false, true)
SerpentSting.mana_costs = {15, 30, 50, 80, 115, 150, 190, 230, 250, 275}
SerpentSting.buff_duration = 15
SerpentSting.tick_interval = 3
SerpentSting:SetVelocity(35)
SerpentSting:TrackAuras()
local SteadyShot = Ability:Add({34120}, false, true)
SteadyShot.mana_costs = {110}
SteadyShot.triggers_combat = true
SteadyShot:SetVelocity(35)
------ Talents
local RapidKilling = Ability:Add({34948, 34949}, true, true)
RapidKilling.buff = Ability:Add({35098, 35099}, true, true)
RapidKilling.buff.buff_duration = 20
------ Procs

---- Survival
local ExplosiveTrap = Ability:Add({13813, 14316, 14317, 27025}, false, true)
ExplosiveTrap.mana_costs = {275, 395, 520, 650}
ExplosiveTrap.cooldown_duration = 30
ExplosiveTrap.dot = Ability:Add({13812, 14314, 14315, 27026}, false, true)
ExplosiveTrap.dot.buff_duration = 20
ExplosiveTrap.dot.tick_interval = 2
local FeignDeath = Ability:Add({5384}, true, true)
FeignDeath.mana_cost = 80
FeignDeath.cooldown_duration = 30
FeignDeath.buff_duration = 360
FeignDeath.triggers_gcd = false
local ImmolationTrap = Ability:Add({13795, 14302, 14303, 14304, 14305, 27023}, false, true)
ImmolationTrap.mana_costs = {50, 90, 135, 190, 245, 305}
ImmolationTrap.cooldown_duration = 30
ImmolationTrap.dot = Ability:Add({13797, 14298, 14299, 14300, 14301, 27024}, false, true)
ImmolationTrap.dot.buff_duration = 15
ImmolationTrap.dot.tick_interval = 3
local RaptorStrike = Ability:Add({2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266, 27014}, false, true)
RaptorStrike.mana_costs = {15, 25, 35, 45, 55, 70, 85, 100, 120}
RaptorStrike.cooldown_duration = 6
RaptorStrike.swing_queue = true
local MongooseBite = Ability:Add({1495, 14269, 14270, 14271, 36916}, true, true)
MongooseBite.mana_costs = {30, 40, 50, 65, 80}
MongooseBite.buff_duration = 5 -- use 5 second imaginary buff triggered by dodge
MongooseBite.cooldown_duration = 5
MongooseBite.requires_react = true
------ Talents

------ Procs

-- Racials

-- Class Buffs/Debuffs
local Bloodlust = Ability:Add({2825, 32183}, true)
Bloodlust.buff_duration = 40
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

-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Player API

function Player:HealthPct()
	return self.health / self.health_max * 100
end

function Player:ManaPct()
	return self.mana.current / self.mana.max * 100
end

function Player:ManaTick(timerTrigger)
	local time = GetTime()
	local mana = UnitPower('player', 0)
	if (
		(not timerTrigger and mana > self.mana.tick_mana) or
		(timerTrigger and mana >= self.mana.max)
	) then
		self.mana.tick_interval = (time - self.mana.fsr_break) > 5 and 2 or 5
		self.mana.next_tick = time + self.mana.tick_interval
		if mana >= self.mana.max then
			C_Timer.After(self.mana.tick_interval, function() Player:ManaTick(true) end)
		end
	end
	self.mana.tick_mana = mana
end

function Player:UnderMeleeAttack()
	return (self.time - self.swing.last_taken) < 3
end

function Player:UnderAttack()
	return self.threat.status >= 3 or self:UnderMeleeAttack()
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.ability_casting and self.ability_casting.triggers_combat then
		return 0.1
	end
	return 0
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

function Player:UpdateAbilities()
	local int = UnitStat('player', 4)
	self.mana.max = UnitPowerMax('player', 0)
	self.mana.base = self.mana.max - (min(20, int) + 15 * (int - min(20, int)))

	-- Update spell ranks first
	for _, ability in next, abilities.all do
		ability.known = false
		ability.spellId = ability.spellIds[1]
		ability.rank = 1
		for i, spellId in next, ability.spellIds do
			if IsPlayerSpell(spellId) then
				ability.known = true
				ability.spellId = spellId -- update spellId to current rank
				ability.rank = i
				if ability.mana_costs then
					ability.mana_cost = ability.mana_costs[i] -- update mana_cost to current rank
				end
				if ability.mana_cost_pct then
					ability.mana_cost = floor(self.mana.base * (ability.mana_cost_pct / 100))
				end
			end
		end
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
	end

	if FeedPet.known then
		FeedPet.buff.known = true
	end
	if ExplosiveTrap.known then
		ExplosiveTrap.dot.known = true
		ExplosiveTrap.dot.rank = ExplosiveTrap.rank
		ExplosiveTrap.dot.spellId = ExplosiveTrap.dot.spellIds[ExplosiveTrap.dot.rank]
	end
	if ImmolationTrap.known then
		ImmolationTrap.dot.known = true
		ImmolationTrap.dot.rank = ImmolationTrap.rank
		ImmolationTrap.dot.spellId = ImmolationTrap.dot.spellIds[ImmolationTrap.dot.rank]
	end
	if RapidKilling.known then
		RapidKilling.buff.known = true
		RapidKilling.buff.rank = RapidKilling.rank
		RapidKilling.buff.spellId = RapidKilling.buff.spellIds[RapidKilling.buff.rank]
	end

	abilities.bySpellId = {}
	abilities.velocity = {}
	abilities.autoAoe = {}
	abilities.trackAuras = {}
	for _, ability in next, abilities.all do
		if ability.known then
			for i, spellId in next, ability.spellIds do
				abilities.bySpellId[spellId] = ability
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
	self.pet.health = self.pet.alive and UnitHealth('pet') or 0
	self.pet.health_max = self.pet.alive and UnitHealthMax('pet') or 0
	self.pet.happiness = self.pet.alive and GetPetHappiness() or 2
end

function Player:Update()
	local _, start, duration, remains, spellId, speed, max_speed
	self.ctime = GetTime()
	self.time = self.ctime - self.time_diff
	self.main =  nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_seconds = nil
	start, duration = GetSpellCooldown(47524)
	self.gcd_remains = start > 0 and duration - (self.ctime - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	self.ability_casting = abilities.bySpellId[spellId]
	self.cast_remains = remains and (remains / 1000 - self.ctime) or 0
	self.execute_remains = max(self.cast_remains, self.gcd_remains)
	self.health = UnitHealth('player')
	self.health_max = UnitHealthMax('player')
	self.mana.current = UnitPower('player', 0)
	self.mana.regen = GetPowerRegenForPowerType(0)
	self.mana.per_tick = floor(self.mana.regen * self.mana.tick_interval)
	self.mana.time_until_tick = max(0, self.mana.next_tick - self.ctime)
	if self.ability_casting then
		self.mana.current = self.mana.current - self.ability_casting:ManaCost()
	end
	if self.execute_remains > self.mana.time_until_tick then
		self.mana.current = self.mana.current + self.mana.per_tick
	end
	self.mana.current = max(0, min(self.mana.max, self.mana.current))
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	self:UpdateThreat()
	self:UpdatePet()
	AutoShot.speed = UnitRangedDamage('player')

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
	end
	ghPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	self.level = UnitLevel('player')
	_, self.instance = IsInInstance()
	self:SetTargetMode(1)
	events:GROUP_ROSTER_UPDATE()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
	self:Update()
end

-- End Player API

-- Start Target API

function Target:UpdateHealth(reset)
	timer.health = 0
	self.health = UnitHealth('target')
	self.health_max = UnitHealthMax('target')
	if self.health <= 0 then
		self.health = Player.health_max
		self.health_max = self.health
	end
	if reset then
		for i = 1, 25 do
			self.health_array[i] = self.health
		end
	else
		table.remove(self.health_array, 1)
		self.health_array[25] = self.health
	end
	self.timeToDieMax = self.health / Player.health_max * 10
	self.healthPercentage = self.health_max > 0 and (self.health / self.health_max * 100) or 100
	self.healthLostPerSec = (self.health_array[1] - self.health) / 5
	self.timeToDie = self.healthLostPerSec > 0 and min(self.timeToDieMax, self.health / self.healthLostPerSec) or self.timeToDieMax
end

function Target:Update()
	UI:Disappear()
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.npcid = nil
		self.boss = false
		self.stunnable = true
		self.classification = 'normal'
		self.creature_type = 'Humanoid'
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
		self.npcid = tonumber(guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)') or 0)
		self:UpdateHealth(true)
	end
	self.boss = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.creature_type = UnitCreatureType('target')
	self.player = UnitIsPlayer('target')
	self.level = UnitLevel('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		if self.level == -1 or (Player.instance == 'party' and self.level >= Player.level + 2) then
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

function Target:Stunned()
	if Intimidation:Up() then
		return true
	end
	return false
end

-- End Target API

-- Start Ability Modifications

function AutoShot:Reset()
	self.casting = false
	self.speed = UnitRangedDamage('player')
	self.next = Player.time + self.speed
	if Opt.shot_timer then
		ghPanel.text.tl:SetTextColor(1, 1, 1, 1)
	end
end

function AutoShot:CastStart()
	self.casting = true
	self.speed = UnitRangedDamage('player')
	self.next = Player.time + self.speed
	if Opt.shot_timer then
		ghPanel.text.tl:SetTextColor(1, 0.75, 0, 1)
	end
end

function AutoShot:CastSuccess()
	self.casting = false
	self.last_used = Player.time
	if Opt.shot_timer then
		ghPanel.text.tl:SetTextColor(1, 1, 1, 1)
	end
end

function AutoShot:CastFailed()
	self.casting = false
	self.next = Player.time
	if Opt.shot_timer then
		ghPanel.text.tl:SetTextColor(1, 1, 1, 1)
	end
end

function AutoShot:Remains()
	if AimedShot:Casting() then
		return self.speed
	end
	return max(0, self.next - Player.time - Player.execute_remains)
end

function AimedShot:CastStart(...)
	Ability.CastStart(self, ...)
	AutoShot:Reset()
end

function AimedShot:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	AutoShot:Reset()
end

function FeignDeath:CastSuccess(...)
	Ability.CastSuccess(self, ...)
	AutoShot:CastFailed()
end

function RapidFire:CooldownDuration()
	local duration = Ability.CooldownDuration(self)
	if RapidKilling.known then
		duration = duration - (60 * RapidKilling.rank)
	end
	return max(0, duration)
end

function SerpentSting:Usable()
	if Target.creature_type == 'Mechanical' then
		return false
	end
	return Ability.Usable(self)
end

function CallPet:Usable()
	if Player.pet.active then
		return false
	end
	if Player.pet.guid and UnitIsDead('pet') then
		return false
	end
	return Ability.Usable(self)
end

function FeedPet:Usable()
	if Player.pet.happiness >= 3 then
		return false
	end
	return Ability.Usable(self)
end

function MendPet:Usable()
	if not Player.pet.alive then
		return false
	end
	if Opt.mend_threshold == 0 or (Player.pet.health / Player.pet.health_max * 100) >= Opt.mend_threshold then
		return false
	end
	return Ability.Usable(self)
end

function RevivePet:Usable()
	if not Player.pet.guid or Player.pet.alive then
		return false
	end
	if self:Casting() then
		return false
	end
	return Ability.Usable(self)
end

function SteadyShot:FirstAfterShot()
	return (AutoShot.casting or (Player.time - AutoShot.last_used) < 1 or AimedShot:Casting()) and not self:Casting()
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

-- Begin Action Priority Lists

local APL = {}

APL.main = function(self)
	if RevivePet:Usable() then
		UseExtra(RevivePet)
	elseif CallPet:Usable() then
		UseExtra(CallPet)
	elseif MendPet:Usable() and MendPet:Down() then
		UseExtra(MendPet)
	elseif FeedPet:Usable() and FeedPet.buff:Down() and Player:TimeInCombat() == 0 then
		UseExtra(FeedPet)
	end
	if Player:TimeInCombat() == 0 then
		if Target.hostile then
			if AspectOfTheViper:Usable() and AspectOfTheViper:Down() and Player:ManaPct() < Opt.viper_low then
				return AspectOfTheViper
			end
			if AspectOfTheHawk:Usable() and AspectOfTheHawk:Down() and (not AspectOfTheViper.known or Player:ManaPct() >= Opt.viper_high or AspectOfTheViper:Down()) then
				return AspectOfTheHawk
			end
		else
			if AspectOfTheViper:Usable() and AspectOfTheViper:Down() and Player:ManaPct() < Opt.viper_high then
				return AspectOfTheViper
			end
			if Player.moving and not (IsMounted() or IsSwimming() or UnitOnTaxi('player')) then
				if AspectOfThePack:Usable() and AspectOfTheCheetah:Down() and AspectOfThePack:Down() and Player.group_size > 1 then
					return AspectOfThePack
				end
				if AspectOfTheCheetah:Usable() and AspectOfTheCheetah:Down() and AspectOfThePack:Down() then
					return AspectOfTheCheetah
				end
			end
		end
		if HuntersMark:Usable() and HuntersMark:Down() then
			return HuntersMark
		end
		if AimedShot:Usable() then
			return AimedShot
		end
	else
		if Player.threat.status >= 3 and FeignDeath:Usable() then
			UseExtra(FeignDeath)
		end
		if AspectOfTheHawk:Usable() and AspectOfTheHawk:Down() and (not AspectOfTheViper.known or Player:ManaPct() >= Opt.viper_high or AspectOfTheViper:Down()) then
			UseExtra(AspectOfTheHawk)
		end
		if AspectOfTheViper:Usable() and AspectOfTheViper:Down() and Player:ManaPct() < Opt.viper_low and Target.timeToDie > 15 then
			UseExtra(AspectOfTheViper)
		end
		if KillCommand:Usable() then
			UseCooldown(KillCommand)
		end
		if Player.threat.status >= 3 and Player:UnderMeleeAttack() then
			if RaptorStrike:Usable() then
				UseCooldown(RaptorStrike)
			end
			if MongooseBite:Usable() then
				return MongooseBite
			end
		end
		if ExplosiveTrap:Usable() and Player:UnderMeleeAttack() and Player.enemies > 1 then
			UseCooldown(ExplosiveTrap)
		end
		if ImmolationTrap:Usable() and Player:UnderMeleeAttack() and Player.enemies == 1 and Target.timeToDie > (ImmolationTrap.dot:TickTime() * 3) then
			UseCooldown(ImmolationTrap)
		end
		if HuntersMark:Usable() and HuntersMark:Down() and HuntersMark:Ticking() == 0 then
			UseCooldown(HuntersMark)
		end
	end
	if RapidFire:Usable() and ((not Target.boss and Target.timeToDie > 15) or (Target.boss and Player:TimeInCombat() > 5 and (Bloodlust:Remains() > 10 or Target.healthPercentage < 20 or Target.timeToDie < 20 or Target.timeToDie > RapidFire:CooldownDuration() + 20))) then
		UseCooldown(RapidFire)
	end
	local no_clip = not SteadyShot.known or (AutoShot:Remains() + AutoShot.speed - Player.gcd) > SteadyShot:CastTime()
	local use_multi = Player:ManaPct() > min(Target.timeToDie, 10 + (Target.healthPercentage / 2))
	local use_as = not SteadyShot.known or (Player:ManaPct() > min(Target.timeToDie, 10 + (Target.healthPercentage / 1.5)) and AspectOfTheViper:Down())
	local use_ss = not SteadyShot.known or (Player:ManaPct() > 90 and AutoShot:Remains() > Player.gcd)
	if ArcaneShot:Usable() and Player.enemies == 1 and Target.timeToDie < 2 then
		return ArcaneShot
	end
	--print('no_clip', no_clip, AutoShot:Remains() + AutoShot.speed - Player.gcd, SteadyShot:CastTime(), 'use_multi', use_multi, AutoShot:Remains(), SteadyShot:CastTime() + 0.5)
	if MultiShot:Usable() and use_multi and no_clip and (AutoShot:Remains() < (SteadyShot:CastTime() + 0.5) or Target.timeToDie < 2) then
		return MultiShot
	end
	if ExplosiveTrap:Usable() and Player.enemies >= 3 then
		UseCooldown(ExplosiveTrap)
	end
	if SteadyShot:Usable() and ((Opt.steady_macro and not Player.moving and AutoShot:Remains() == 0) or (SteadyShot:FirstAfterShot() and SteadyShot:CastTime() < (AutoShot:Remains() + 0.5))) then
		return SteadyShot
	end
	if MultiShot:Usable() and use_multi and no_clip then
		return MultiShot
	end
	if SteadyShot:Usable() and SteadyShot:CastTime() < AutoShot:Remains() then
		return SteadyShot
	end
	if ArcaneShot:Usable() and (Player.moving or (use_as and no_clip)) then
		return ArcaneShot
	end
	if SerpentSting:Usable() and SerpentSting:Down() and Target.timeToDie > (SerpentSting:TickTime() * 5) and (Player.moving or use_ss) then
		return SerpentSting
	end
end

APL.Interrupt = function(self)

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
		GenerateGlow(_G['StanceButton' .. i])
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

function UI:UpdateShotTimers()
	local text_tl, text_tr

	if Opt.shot_timer then
		local now = GetTime()
		local shot = AutoShot.next - (now - Player.time_diff)
		local _, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
		if spellId then
			remains = (remains / 1000) - now
			if abilities.bySpellId[spellId] == AimedShot then
				shot = remains + AutoShot.speed
			elseif remains > shot then
				if shot > 0 then
					ghPanel.text.tl:SetTextColor(1, 0, 0, 1)
				end
				shot = remains
			end
		end
		if shot > 0 then
			text_tl = format('%.1f', shot)
		end
	end
	if Opt.shot_speed then
		text_tr = format('%.1f', AutoShot.speed)
	end

	ghPanel.text.tl:SetText(text_tl)
	ghPanel.text.tr:SetText(text_tr)
end

function UI:UpdateDisplay()
	timer.display = 0
	local dim, dim_cd, text_center

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsUsableSpell(Player.main.spellId)) or
		           (Player.main.itemId and IsUsableItem(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsUsableSpell(Player.cd.spellId)) or
		           (Player.cd.itemId and IsUsableItem(Player.cd.itemId)))
	end
	if Player.cd and Player.cd.queue_time then
		if not ghCooldownPanel.swingQueueOverlayOn then
			ghCooldownPanel.swingQueueOverlayOn = true
			ghCooldownPanel.border:SetTexture(ADDON_PATH .. 'swingqueue.blp')
		end
	elseif ghCooldownPanel.swingQueueOverlayOn then
		ghCooldownPanel.swingQueueOverlayOn = false
		ghCooldownPanel.border:SetTexture(ADDON_PATH .. 'border.blp')
	end

	ghPanel.dimmer:SetShown(dim)
	ghPanel.text.center:SetText(text_center)
	ghCooldownPanel.dimmer:SetShown(dim_cd)
	--ghPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))

	self:UpdateShotTimers()
end

function UI:UpdateCombat()
	timer.combat = 0

	Player:Update()

	Player.main = APL.main()
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
		local _, _, _, start, ends = UnitCastingInfo('target')
		if not start then
			_, _, _, start, ends = UnitChannelInfo('target')
		end
		if start then
			Player.interrupt = APL.Interrupt()
			ghInterruptPanel.swipe:SetCooldown(start / 1000, (ends - start) / 1000)
		end
		if Player.interrupt then
			ghInterruptPanel.icon:SetTexture(Player.interrupt.icon)
		end
		ghInterruptPanel.icon:SetShown(Player.interrupt)
		ghInterruptPanel.border:SetShown(Player.interrupt)
		ghInterruptPanel:SetShown(start)
	end
	ghPanel.icon:SetShown(Player.main)
	ghPanel.border:SetShown(Player.main)
	ghCooldownPanel:SetShown(Player.cd)
	ghExtraPanel:SetShown(Player.extra)

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
		Opt = GoodHuntingConfig
		if not Opt.frequency then
			print('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_GoodHunting1 .. '|r for a list of commands.')
		end
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		UI:SnapAllPanels()
	end
end

CombatEvent.TRIGGER = function(timeStamp, event, _, srcGUID, _, _, _, dstGUID, _, _, _, ...)
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time
	local e = event
	if (
	   e == 'UNIT_DESTROYED' or
	   e == 'UNIT_DISSIPATES' or
	   e == 'SPELL_INSTAKILL' or
	   e == 'PARTY_KILL')
	then
		e = 'UNIT_DIED'
	elseif (
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
	if Player.pet.stuck and srcGUID == Player.pet.guid then
		Player.pet.stuck = false
		return
	end
	if not (dstGUID == Player.guid or dstGUID == Player.pet.guid) then
		return
	end
	if dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
	end
	if Opt.auto_aoe then
		autoAoe:Add(srcGUID, true)
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if Player.pet.stuck and srcGUID == Player.pet.guid then
		Player.pet.stuck = false
		return
	end
	if not (dstGUID == Player.guid or dstGUID == Player.pet.guid) then
		return
	end
	if dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
	end
	if Opt.auto_aoe then
		autoAoe:Add(srcGUID, true)
	end
end

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, _, _, resisted, blocked, absorbed, critical)
	if srcGUID == Player.pet.guid then
		if Player.pet.stuck and (event == 'SPELL_CAST_SUCCESS' or event == 'SPELL_DAMAGE') then
			Player.pet.stuck = false
		elseif not Player.pet.stuck and event == 'SPELL_CAST_FAILED' and missType == 'No path available' then
			Player.pet.stuck = true
		end
	end

	if srcGUID ~= Player.guid then
		return
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
		ability:CastFailed(dstGUID)
		if ability.requires_pet and missType == 'No path available' then
			Player.pet.stuck = true
		end
		return
	end

	if dstGUID == Player.guid then
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
	if event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_DAMAGE' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event)
		if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and ghPanel:IsVisible() and ability == ghPreviousPanel.ability then
			ghPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
		end
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

function events:PLAYER_REGEN_DISABLED()
	Player.combat_start = GetTime() - Player.time_diff
end

function events:PLAYER_REGEN_ENABLED()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Player.pet.stuck = false
	Target.estimated_range = 30
	Player.previous_gcd = {}
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
	equipType = GetInventoryItemLink('player', 18)
	if equipType then
		local speed
		ghScanTooltip:SetHyperlink(equipType)
		for i = 2, 4 do
			speed = _G['ghScanTooltipTextRight' .. i]:GetText()
			if speed and speed:find(WEAPON_SPEED) then
				speed = speed:match('[%d.]+')
				if speed then
					AutoShot.base_speed = tonumber(speed)
					break
				end
			end
		end
		ghScanTooltip:ClearLines()
	end
	Player:UpdateAbilities()
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, start, duration, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(47524)
		end
		ghPanel.swipe:SetCooldown(start, duration)
	end
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

function events:UNIT_SPELLCAST_SENT(srcName, dstName, castGUID, spellId)
	if srcName ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.swing_queue then
		ability.queue_time = GetTime()
	end
end

function events:UNIT_SPELLCAST_FAILED(srcName, castGUID, spellId)
	if srcName ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.swing_queue then
		ability.queue_time = nil
	end
end
events.UNIT_SPELLCAST_FAILED_QUIET = events.UNIT_SPELLCAST_FAILED

function events:UNIT_SPELLCAST_SUCCEEDED(srcName, castGUID, spellId)
	if srcName ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
	if ability.swing_queue then
		ability.queue_time = nil
	end
	if ability.mana_cost > 0 then
		Player.mana.fsr_break = GetTime()
	end
	if ability == FeignDeath then
		ability:CastSuccess() -- Feign Death doesn't have a CLEU trigger, so this is a workaround
	end
end

function events:UNIT_POWER_FREQUENT(srcName, powerType)
	if srcName ~= 'player' then
		return
	elseif powerType == 'MANA' then
		Player:ManaTick()
	end
end

function events:MIRROR_TIMER_STOP(timer)
	if timer == 'FEIGNDEATH' then
		AutoShot:Reset()
	end
end

function events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function events:GROUP_ROSTER_UPDATE()
	Player.group_size = max(1, min(40, GetNumGroupMembers()))
end

function events:PLAYER_ENTERING_WORLD()
	Player:Init()
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
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UI:UpdateScale()
			end
			return Status('Extra cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UI:UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
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
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Glowing ability buttons (extra cooldown icon)', Opt.glow.extra)
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
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
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
	if startsWith(msg[1], 'sh') then
		if msg[2] then
			Opt.shot_timer = msg[2] == 'on'
		end
		return Status('Show time remaining until next Auto Shot (top-left)', Opt.shot_timer)
	end
	if startsWith(msg[1], 'sp') then
		if msg[2] then
			Opt.shot_speed = msg[2] == 'on'
		end
		return Status('Show Auto Shot speed (top-right)', Opt.shot_speed)
	end
	if startsWith(msg[1], 'st') then
		if msg[2] then
			Opt.steady_macro = msg[2] == 'on'
		end
		return Status('Using a Steady Shot macro that starts Auto Shot', Opt.steady_macro)
	end
	if startsWith(msg[1], 'me') then
		if msg[2] then
			Opt.mend_threshold = tonumber(msg[2]) or 65
		end
		return Status('Recommend Mend Pet when pet\'s health is below', Opt.mend_threshold .. '%')
	end
	if startsWith(msg[1], 'vi') then
		if msg[2] == 'off' then
			Opt.viper_low = 0
			Opt.viper_high = 0
		elseif msg[2] and msg[3] then
			Opt.viper_low = tonumber(msg[2]) or 15
			Opt.viper_high = tonumber(msg[3]) or 50
		end
		if Opt.viper_low + Opt.viper_high == 0 then
			Status('Recommend Aspect of the Viper', false)
		else
			Status('Recommend Aspect of the Viper when mana is below', Opt.viper_low .. '%')
			Status('Turn off Aspect of the Viper when mana is above', Opt.viper_high .. '%')
		end
		return
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
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'shot |cFF00C000on|r/|cFFC00000off|r - show time remaining until next Auto Shot (top-left)',
		'speed |cFF00C000on|r/|cFFC00000off|r - show Auto Shot speed (top-right)',
		'steady |cFF00C000on|r/|cFFC00000off|r  - enable this if using a Steady Shot macro that starts Auto Shot',
		'mend |cFFFFD000[percent]|r  - health percentage to recommend Mend Pet at (default is 65%, 0 to disable)',
		'viper |cFFFFD000[low] [high]|r  - mana percentage to recommend Aspect of the Viper at (default is 15% to 50%)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_GoodHunting1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
