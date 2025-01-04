local ADDON = 'GoodHunting'
local ADDON_PATH = 'Interface\\AddOns\\' .. ADDON .. '\\'

BINDING_CATEGORY_GOODHUNTING = ADDON
BINDING_NAME_GOODHUNTING_TARGETMORE = "Toggle Targets +"
BINDING_NAME_GOODHUNTING_TARGETLESS = "Toggle Targets -"
BINDING_NAME_GOODHUNTING_TARGET1 = "Set Targets to 1"
BINDING_NAME_GOODHUNTING_TARGET2 = "Set Targets to 2"
BINDING_NAME_GOODHUNTING_TARGET3 = "Set Targets to 3"
BINDING_NAME_GOODHUNTING_TARGET4 = "Set Targets to 4"
BINDING_NAME_GOODHUNTING_TARGET5 = "Set Targets to 5+"

local function log(...)
	print(ADDON, '-', ...)
end

if select(2, UnitClass('player')) ~= 'HUNTER' then
	log('[|cFFFF0000Error|r]', 'Not loading because you are not the correct class! Consider disabling', ADDON, 'for this character.')
	return
end

-- reference heavily accessed global functions from local scope for performance
local min = math.min
local max = math.max
local floor = math.floor
local GetPowerRegenForPowerType = _G.GetPowerRegenForPowerType
local GetSpellCharges = C_Spell.GetSpellCharges
local GetSpellCooldown = C_Spell.GetSpellCooldown
local GetSpellInfo = C_Spell.GetSpellInfo
local GetItemCount = C_Item.GetItemCount
local GetItemCooldown = C_Item.GetItemCooldown
local GetInventoryItemCooldown = _G.GetInventoryItemCooldown
local GetItemInfo = C_Item.GetItemInfo
local GetTime = _G.GetTime
local GetUnitSpeed = _G.GetUnitSpeed
local IsSpellUsable = C_Spell.IsSpellUsable
local IsItemUsable = C_Item.IsUsableItem
local UnitAttackSpeed = _G.UnitAttackSpeed
local UnitAura = C_UnitAuras.GetAuraDataByIndex
local UnitCastingInfo = _G.UnitCastingInfo
local UnitChannelInfo = _G.UnitChannelInfo
local UnitDetailedThreatSituation = _G.UnitDetailedThreatSituation
local UnitHealth = _G.UnitHealth
local UnitHealthMax = _G.UnitHealthMax
local UnitPower = _G.UnitPower
local UnitPowerMax = _G.UnitPowerMax
local UnitSpellHaste = _G.UnitSpellHaste
-- end reference global functions

-- useful functions
local function between(n, min, max)
	return n >= min and n <= max
end

local function clamp(n, min, max)
	return (n < min and min) or (n > max and max) or n
end

local function startsWith(str, start) -- case insensitive check to see if a string matches the start of another string
	if type(str) ~= 'string' then
		return false
	end
	return string.lower(str:sub(1, start:len())) == start:lower()
end

local function ToUID(guid)
	local uid = guid:match('^%w+-%d+-%d+-%d+-%d+-(%d+)')
	return uid and tonumber(uid)
end
-- end useful functions

GoodHunting = {}
local Opt -- use this as a local table reference to GoodHunting

SLASH_GoodHunting1, SLASH_GoodHunting2 = '/gh', '/good'

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
			animation = false,
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
		heal = 60,
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
local Events = {}

-- player ability template
local Ability = {}
Ability.__index = Ability

-- classified player abilities
local Abilities = {
	all = {},
	bySpellId = {},
	velocity = {},
	autoAoe = {},
	tracked = {},
}

-- summoned pet template
local SummonedPet = {}
SummonedPet.__index = SummonedPet

-- classified summoned pets
local SummonedPets = {
	all = {},
	known = {},
	byUnitId = {},
}

-- methods for target tracking / aoe modes
local AutoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {},
}

-- methods for tracking ticking debuffs on targets
local TrackedAuras = {}

-- timers for updating combat/display/hp info
local Timer = {
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

-- action priority list container
local APL = {
	[SPEC.NONE] = {},
	[SPEC.BEASTMASTERY] = {},
	[SPEC.MARKSMANSHIP] = {},
	[SPEC.SURVIVAL] = {},
}

-- current player information
local Player = {
	time = 0,
	time_diff = 0,
	ctime = 0,
	combat_start = 0,
	level = 1,
	spec = 0,
	group_size = 1,
	target_mode = 0,
	gcd = 1.5,
	gcd_remains = 0,
	execute_remains = 0,
	haste_factor = 1,
	moving = false,
	movement_speed = 100,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	focus = {
		current = 0,
		regen = 0,
		max = 100,
		deficit = 100,
	},
	cast = {
		start = 0,
		ends = 0,
		remains = 0,
	},
	channel = {
		chained = false,
		start = 0,
		ends = 0,
		remains = 0,
		tick_count = 0,
		tick_interval = 0,
		ticks = 0,
		ticks_remain = 0,
		ticks_extra = 0,
		interruptible = false,
		early_chainable = false,
	},
	threat = {
		status = 0,
		pct = 0,
		lead = 0,
	},
	swing = {
		mh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		oh = {
			last = 0,
			speed = 0,
			remains = 0,
		},
		last_taken = 0,
	},
	set_bonus = {
		t33 = 0, -- Lightless Scavenger's Necessities
	},
	previous_gcd = {},-- list of previous GCD abilities
	item_use_blacklist = { -- list of item IDs with on-use effects we should mark unusable
		[190958] = true, -- Soleah's Secret Technique
		[193757] = true, -- Ruby Whelp Shell
		[202612] = true, -- Screaming Black Dragonscale
		[203729] = true, -- Ominous Chromatic Essence
	},
	main_freecast = false,
	major_cd_remains = 0,
}

-- current pet information
local Pet = {
	active = false,
	alive = false,
	stuck = false,
	health = {
		current = 0,
		max = 100,
		pct = 100,
	},
	focus = {
		current = 0,
		max = 100,
	},
}

-- current target information
local Target = {
	boss = false,
	dummy = false,
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

-- target dummy unit IDs (count these units as bosses)
Target.Dummies = {
	[189617] = true,
	[189632] = true,
	[194643] = true,
	[194644] = true,
	[194648] = true,
	[194649] = true,
	[197833] = true,
	[198594] = true,
	[219250] = true,
	[225983] = true,
	[225984] = true,
	[225985] = true,
	[225976] = true,
	[225977] = true,
	[225978] = true,
	[225982] = true,
}

-- Start AoE

Player.target_modes = {
	[SPEC.NONE] = {
		{1, ''}
	},
	[SPEC.BEASTMASTERY] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.MARKSMANSHIP] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
	},
	[SPEC.SURVIVAL] = {
		{1, ''},
		{2, '2'},
		{3, '3'},
		{4, '4'},
		{5, '5+'},
		{7, '7+'},
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

function AutoAoe:Add(guid, update)
	if self.blacklist[guid] then
		return
	end
	local uid = ToUID(guid)
	if uid and self.ignored_units[uid] then
		self.blacklist[guid] = Player.time + 10
		return
	end
	local new = not self.targets[guid]
	self.targets[guid] = Player.time
	if update and new then
		self:Update()
	end
end

function AutoAoe:Remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:Update()
	end
end

function AutoAoe:Clear()
	for _, ability in next, Abilities.autoAoe do
		ability.auto_aoe.start_time = nil
		for guid in next, ability.auto_aoe.targets do
			ability.auto_aoe.targets[guid] = nil
		end
	end
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
	self:Update()
end

function AutoAoe:Update()
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

function AutoAoe:Purge()
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
		rank = 0,
		focus_cost = 0,
		focus_gain = 0,
		cooldown_duration = 0,
		buff_duration = 0,
		tick_interval = 0,
		summon_count = 0,
		max_range = 40,
		velocity = 0,
		last_gained = 0,
		last_used = 0,
		aura_target = buff and 'player' or 'target',
		aura_filter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or ''),
		pet_spell = player == 'pet',
	}
	if ability.pet_spell then
		ability.aura_target = buff and 'pet' or 'target'
	end
	setmetatable(ability, self)
	Abilities.all[#Abilities.all + 1] = ability
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
	if (self.requires_pet or self.pet_spell) and not Pet.active then
		return false
	end
	if not pool and self:Cost() > (self.pet_spell and Pet.focus.current or Player.focus.current) then
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
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			if aura.expirationTime == 0 then
				return 600 -- infinite duration
			end
			return max(0, aura.expirationTime - Player.ctime - (self.off_gcd and 0 or Player.execute_remains))
		end
	end
	return 0
end

function Ability:React()
	return self:Remains()
end

function Ability:Expiring(seconds)
	local remains = self:Remains()
	return remains > 0 and remains < (seconds or Player.gcd)
end

function Ability:Refreshable()
	if self.buff_duration > 0 then
		return self:Remains() < self:Duration() * 0.3
	end
	return self:Down()
end

function Ability:Up(...)
	return self:Remains(...) > 0
end

function Ability:Down(...)
	return self:Remains(...) <= 0
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
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				count = count + 1
			end
		end
	end
	return count
end

function Ability:TravelTime()
	return Target.estimated_range / self.velocity + (self.travel_delay or 0)
end

function Ability:Ticking()
	local count, ticking = 0, {}
	if self.aura_targets then
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > (self.off_gcd and 0 or Player.execute_remains) then
				ticking[guid] = true
			end
		end
	end
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity + (self.travel_delay or 0) then
				ticking[cast.dstGUID] = true
			end
		end
	end
	for _ in next, ticking do
		count = count + 1
	end
	return count
end

function Ability:HighestRemains()
	local highest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				highest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not highest or remains > highest) then
				highest = remains
			end
		end
	end
	return highest or 0
end

function Ability:LowestRemains()
	local lowest
	if self.traveling then
		for _, cast in next, self.traveling do
			if Player.time - cast.start < self.max_range / self.velocity then
				lowest = self:Duration()
			end
		end
	end
	if self.aura_targets then
		local remains
		for _, aura in next, self.aura_targets do
			remains = max(0, aura.expires - Player.time - Player.execute_remains)
			if remains > 0 and (not lowest or remains < lowest) then
				lowest = remains
			end
		end
	end
	return lowest or 0
end

function Ability:TickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:CooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:Cooldown()
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	return max(0, cooldown.duration - (Player.ctime - cooldown.startTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:CooldownExpected()
	if self.last_used == 0 then
		return self:Cooldown()
	end
	if self.cooldown_duration > 0 and self:Casting() then
		return self:CooldownDuration()
	end
	local cooldown = GetSpellCooldown(self.spellId)
	if cooldown.startTime == 0 then
		return 0
	end
	local remains = cooldown.duration - (Player.ctime - cooldown.startTime)
	local reduction = (Player.time - self.last_used) / (self:CooldownDuration() - remains)
	return max(0, (remains * reduction) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Stack()
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0
		elseif self:Match(aura.spellId) then
			return (aura.expirationTime == 0 or aura.expirationTime - Player.ctime > (self.off_gcd and 0 or Player.execute_remains)) and aura.applications or 0
		end
	end
	return 0
end

function Ability:MaxStack()
	return self.max_stack
end

function Ability:Capped(deficit)
	return self:Stack() >= (self:MaxStack() - (deficit or 0))
end

function Ability:Cost()
	return self.focus_cost
end

function Ability:Gain()
	return self.focus_gain
end

function Ability:Free()
	return self.focus_cost > 0 and self:Cost() == 0
end

function Ability:ChargesFractional()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return charges - 1
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return charges
	end
	return charges + ((max(0, Player.ctime - info.cooldownStartTime + (self.off_gcd and 0 or Player.execute_remains))) / info.cooldownDuration)
end

function Ability:Charges()
	return floor(self:ChargesFractional())
end

function Ability:MaxCharges()
	local info = GetSpellCharges(self.spellId)
	return info and info.maxCharges or 0
end

function Ability:FullRechargeTime()
	local info = GetSpellCharges(self.spellId)
	if not info then
		return 0
	end
	local charges = info.currentCharges
	if self:Casting() then
		if charges >= info.maxCharges then
			return info.cooldownDuration
		end
		charges = charges - 1
	end
	if charges >= info.maxCharges then
		return 0
	end
	return (info.maxCharges - charges - 1) * info.cooldownDuration + (info.cooldownDuration - (Player.ctime - info.cooldownStartTime) - (self.off_gcd and 0 or Player.execute_remains))
end

function Ability:Duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:Casting()
	return Player.cast.ability == self
end

function Ability:Channeling()
	return Player.channel.ability == self
end

function Ability:CastTime()
	local info = GetSpellInfo(self.spellId)
	return info and info.castTime / 1000 or 0
end

function Ability:CastRegen()
	return Player.focus.regen * self:CastTime() - self:Cost() + self:Gain()
end

function Ability:WillCapFocus(reduction)
	return (Player.focus.current + self:CastRegen()) >= (Player.focus.max - (reduction or 5))
end

function Ability:WontCapFocus(...)
	return not self:WillCapFocus(...)
end

function Ability:Previous(n)
	local i = n or 1
	if Player.cast.ability then
		if i == 1 then
			return Player.cast.ability == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:UsedWithin(seconds)
	return self.last_used >= (Player.time - seconds)
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
		self.auto_aoe.target_count = 0
		if self.auto_aoe.remove then
			for guid in next, AutoAoe.targets do
				AutoAoe.targets[guid] = nil
			end
		end
		for guid in next, self.auto_aoe.targets do
			AutoAoe:Add(guid)
			self.auto_aoe.targets[guid] = nil
			self.auto_aoe.target_count = self.auto_aoe.target_count + 1
		end
		AutoAoe:Update()
	end
end

function Ability:Targets()
	if self.auto_aoe and self:Up() then
		return self.auto_aoe.target_count
	end
	return 0
end

function Ability:CastFailed(dstGUID, missType)
	if (self.requires_pet or self.pet_spell) and missType == 'No path available' then
		Pet.stuck = true
	end
end

function Ability:CastSuccess(dstGUID)
	self.last_used = Player.time
	if self.ignore_cast then
		return
	end
	if self.requires_pet or self.pet_spell then
		Pet.stuck = false
		if self.pet_spell then
			return
		end
	end
	Player.last_ability = self
	if self.triggers_gcd then
		Player.previous_gcd[10] = nil
		table.insert(Player.previous_gcd, 1, self)
	end
	if Opt.auto_aoe and self.auto_aoe and self.auto_aoe.trigger == 'SPELL_CAST_SUCCESS' then
		AutoAoe:Add(dstGUID, true)
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
	if self.traveling then
		local oldest
		for guid, cast in next, self.traveling do
			if Player.time - cast.start >= self.max_range / self.velocity + (self.travel_delay or 0) + 0.2 then
				self.traveling[guid] = nil -- spell traveled 0.2s past max range, delete it, this should never happen
			elseif cast.dstGUID == dstGUID and (not oldest or cast.start < oldest.start) then
				oldest = cast
			end
		end
		if oldest then
			Target.estimated_range = floor(clamp(self.velocity * max(0, Player.time - oldest.start - (self.travel_delay or 0)), 0, self.max_range))
			self.traveling[oldest.guid] = nil
		end
	end
	if self.range_est_start then
		Target.estimated_range = floor(clamp(self.velocity * (Player.time - self.range_est_start - (self.travel_delay or 0)), 5, self.max_range))
		self.range_est_start = nil
	elseif self.max_range < Target.estimated_range then
		Target.estimated_range = self.max_range
	end
	if Opt.auto_aoe and self.auto_aoe then
		if event == 'SPELL_MISSED' and (missType == 'EVADE' or (missType == 'IMMUNE' and not self.ignore_immune)) then
			AutoAoe:Remove(dstGUID)
		elseif event == self.auto_aoe.trigger or (self.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and event == 'SPELL_AURA_REFRESH') then
			self:RecordTargetHit(dstGUID)
		end
	end
	if Opt.previous and Opt.miss_effect and event == 'SPELL_MISSED' and ghPreviousPanel.ability == self then
		ghPreviousPanel.border:SetTexture(ADDON_PATH .. 'misseffect.blp')
	end
end

-- Start DoT tracking

function TrackedAuras:Purge()
	for _, ability in next, Abilities.tracked do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:RemoveAura(guid)
			end
		end
	end
end

function TrackedAuras:Remove(guid)
	for _, ability in next, Abilities.tracked do
		ability:RemoveAura(guid)
	end
end

function Ability:Track()
	self.aura_targets = {}
end

function Ability:ApplyAura(guid)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid] or {}
	aura.expires = Player.time + self:Duration()
	self.aura_targets[guid] = aura
	return aura
end

function Ability:RefreshAura(guid, extend)
	if AutoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		return self:ApplyAura(guid)
	end
	local duration = self:Duration()
	aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	return aura
end

function Ability:RefreshAuraAll(extend)
	local duration = self:Duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = max(aura.expires, Player.time + min(duration * (self.no_pandemic and 1.0 or 1.3), (aura.expires - Player.time) + (extend or duration)))
	end
end

function Ability:RemoveAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- End DoT tracking

--[[
Note: To get talent_node value for a talent, hover over talent and use macro:
/dump GetMouseFoci()[1]:GetNodeID()
]]

-- Hunter Abilities
---- Class
------ Baseline
local ArcaneShot = Ability:Add(185358, false, true)
ArcaneShot.focus_cost = 40
ArcaneShot:SetVelocity(70)
local AspectOfTheCheetah = Ability:Add(186257, true, true, 186258)
AspectOfTheCheetah.buff_duration = 3
AspectOfTheCheetah.cooldown_duration = 180
AspectOfTheCheetah.triggers_gcd = false
local AspectOfTheTurtle = Ability:Add(186265, true, true)
AspectOfTheTurtle.buff_duration = 8
AspectOfTheTurtle.cooldown_duration = 180
AspectOfTheTurtle.triggers_gcd = false
local CallPet1 = Ability:Add(883, false, true)
local Disengage = Ability:Add(781, false, true)
Disengage.cooldown_duration = 20
Disengage.triggers_gcd = false
local DismissPet = Ability:Add(2641, false, true)
local Exhilaration = Ability:Add(109304, true, true, 128594)
Exhilaration.cooldown_duration = 120
local FeignDeath = Ability:Add(5384, true, true)
FeignDeath.buff_duration = 360
FeignDeath.cooldown_duration = 30
FeignDeath.triggers_gcd = false
local Flare = Ability:Add(1543, false, true)
Flare.cooldown_duration = 20
local FreezingTrap = Ability:Add(187650, false, true, 3355)
FreezingTrap.cooldown_duration = 25
FreezingTrap.buff_duration = 60
local HuntersMark = Ability:Add(257284)
local MendPet = Ability:Add(136, true, true)
MendPet.cooldown_duration = 10
MendPet.buff_duration = 10
MendPet.requires_pet = true
MendPet.aura_target = 'pet'
local RevivePet = Ability:Add(982, false, true)
RevivePet.focus_cost = 35
local SerpentSting = Ability:Add(259491, false, true)
SerpentSting.buff_duration = 12
SerpentSting.tick_interval = 3
SerpentSting.hasted_ticks = true
SerpentSting:SetVelocity(60)
SerpentSting:AutoAoe(false, 'apply')
SerpentSting:Track()
local SteadyShot = Ability:Add(56641, false, true)
SteadyShot:SetVelocity(75)
local WingClip = Ability:Add(195645, false, true)
WingClip.buff_duration = 15
WingClip.focus_cost = 20
------ Talents
local AlphaPredator = Ability:Add(269737, false, true)
local Barrage = Ability:Add(120360, false, true, 120361)
Barrage.buff_duration = 3
Barrage.cooldown_duration = 20
Barrage.focus_cost = 60
Barrage:AutoAoe()
local BindingShot = Ability:Add(109248, false, true, 117405)
BindingShot.buff_duration = 10
BindingShot.cooldown_duration = 45
local BurstingShot = Ability:Add(186387, false, true)
BurstingShot.buff_duration = 6
BurstingShot.cooldown_duration = 30
BurstingShot.focus_cost = 10
local Camouflage = Ability:Add(199483, true, true)
Camouflage.buff_duration = 60
Camouflage.cooldown_duration = 60
local ConcussiveShot = Ability:Add(5116, false, true)
ConcussiveShot.buff_duration = 6
ConcussiveShot.cooldown_duration = 5
ConcussiveShot:SetVelocity(50)
local CounterShot = Ability:Add(147362, false, true)
CounterShot.buff_duration = 3
CounterShot.cooldown_duration = 24
CounterShot.triggers_gcd = false
local Deathblow = Ability:Add(343248, true, true, 378770)
Deathblow.buff_duration = 12
Deathblow.max_stack = 1
local ExplosiveShot = Ability:Add(212431, false, true)
ExplosiveShot.buff_duration = 3
ExplosiveShot.cooldown_duration = 30
ExplosiveShot.focus_cost = 20
ExplosiveShot:SetVelocity(75)
ExplosiveShot.explosion = Ability:Add(212680, false, true)
ExplosiveShot.explosion:AutoAoe()
local HighExplosiveTrap = Ability:Add(236776, false, true, 236777)
HighExplosiveTrap.cooldown_duration = 40
local ImplosiveTrap = Ability:Add(462031, false, true, 236777)
HighExplosiveTrap.cooldown_duration = 60
local Intimidation = Ability:Add(19577, false, true, 24394)
Intimidation.cooldown_duration = 60
Intimidation.buff_duration = 5
Intimidation.requires_pet = true
local KillShot = Ability:Add({320976, 53351}, false, true)
KillShot.cooldown_duration = 10
KillShot.focus_cost = 10
KillShot:SetVelocity(80)
local Misdirection = Ability:Add(34477, true, true)
Misdirection.buff_duration = 30
Misdirection.cooldown_duration = 30
local ScareBeast = Ability:Add(1513)
ScareBeast.buff_duration = 20
ScareBeast.focus_cost = 25
local ScatterShot = Ability:Add(213691, false, true)
ScatterShot.buff_duration = 4
ScatterShot.cooldown_duration = 30
ScatterShot:SetVelocity(60)
local SurvivalOfTheFittest = Ability:Add(264735, true, true)
SurvivalOfTheFittest.buff_duration = 6
SurvivalOfTheFittest.cooldown_duration = 180
SurvivalOfTheFittest.triggers_gcd = false
local TarTrap = Ability:Add(187698, false, true, 135299)
TarTrap.cooldown_duration = 30
TarTrap.buff_duration = 30
TarTrap.ignore_immune = true
local TranquilizingShot = Ability:Add(19801, false, true)
TranquilizingShot.cooldown_duration = 10
TranquilizingShot:SetVelocity(50)
------ Procs

---- Beast Mastery
------ Baseline

------ Talents
local AMurderOfCrows = Ability:Add(459760, true, true, 459759)
AMurderOfCrows.buff_duration = 15
local BarbedShot = Ability:Add(217200, false, true)
BarbedShot.cooldown_duration = 12
BarbedShot.buff_duration = 8
BarbedShot.tick_interval = 2
BarbedShot.hasted_cooldown = true
BarbedShot.requires_charge = true
BarbedShot:SetVelocity(50)
BarbedShot.buff = Ability:Add(246152, true, true)
BarbedShot.buff.buff_duration = 8
local BeastCleave = Ability:Add(115939, true, true)
BeastCleave.buff_duration = 4
BeastCleave.pet = Ability:Add(118455, false, true, 118459)
BeastCleave.pet:AutoAoe()
local BestialWrath = Ability:Add(19574, true, true)
BestialWrath.cooldown_duration = 90
BestialWrath.buff_duration = 15
BestialWrath.pet = Ability:Add(186254, true, true)
BestialWrath.pet.aura_target = 'pet'
BestialWrath.pet.buff_duration = 15
local CobraShot = Ability:Add(193455, false, true)
CobraShot.focus_cost = 35
CobraShot:SetVelocity(45)
local HuntersPrey = Ability:Add(378210, true, true, 378215)
HuntersPrey.buff_duration = 15
local KillCleave = Ability:Add(378207, false, true)
local KillCommandBM = Ability:Add(34026, false, true, 83381)
KillCommandBM.focus_cost = 30
KillCommandBM.cooldown_duration = 7.5
KillCommandBM.hasted_cooldown = true
KillCommandBM.requires_pet = true
KillCommandBM.max_range = 50
local KillerCobra = Ability:Add(199532, true, true)
local KillerInstinct = Ability:Add(273887, false, true)
local MultiShotBM = Ability:Add(2643, false, true)
MultiShotBM.focus_cost = 40
MultiShotBM:SetVelocity(50)
MultiShotBM:AutoAoe(true)
local PetFrenzy = Ability:Add(272790, true, true)
PetFrenzy.aura_target = 'pet'
PetFrenzy.buff_duration = 12
PetFrenzy.max_stack = 3
local ScentOfBlood = Ability:Add(193532, true, true)
local Stomp = Ability:Add(199530, false, true, 201754)
Stomp:AutoAoe()
local WildCall = Ability:Add(185789, true, true, 185791)
WildCall.buff_duration = 4
------ Procs

---- Marksmanship
------ Baseline

------ Talents
local HydrasBite = Ability:Add(260241, false, true)
local MasterMarksman = Ability:Add(260309, false, true, 269576)
MasterMarksman.buff_duration = 6
MasterMarksman.tick_interval = 2
------ Procs

---- Survival
------ Baseline
local AspectOfTheEagle = Ability:Add(186289, true, true)
AspectOfTheEagle.buff_duration = 15
AspectOfTheEagle.cooldown_duration = 90
------ Talents
local Bloodseeker = Ability:Add(260248, false, true, 259277)
Bloodseeker.buff_duration = 8
Bloodseeker.tick_interval = 2
Bloodseeker.hasted_ticks = true
Bloodseeker.no_pandemic = true
Bloodseeker:Track()
Bloodseeker.buff = Ability:Add(260249, true, true)
local Bombardier = Ability:Add(389880, true, true, 459859)
Bombardier.buff_duration = 60
Bombardier.max_stack = 1
local Butchery = Ability:Add(212436, false, true)
Butchery.focus_cost = 30
Butchery.cooldown_duration = 15
Butchery.hasted_cooldown = true
Butchery.requires_charge = true
Butchery:AutoAoe(true)
local ContagiousReagents = Ability:Add(459741, false, true)
local CoordinatedAssault = Ability:Add(360952, true, true)
CoordinatedAssault.cooldown_duration = 120
CoordinatedAssault.buff_duration = 20
CoordinatedAssault.requires_pet = true
CoordinatedAssault.empower = Ability:Add(361738, true, true)
CoordinatedAssault.empower.buff_duration = 3
local DeadlyDuo = Ability:Add(378962, true, true)
local FlankersAdvantage = Ability:Add(459964, false, true)
local FlankingStrike = Ability:Add(269751, false, true, 269752)
FlankingStrike.cooldown_duration = 30
FlankingStrike.requires_pet = true
FlankingStrike.max_range = 10
FlankingStrike.focus_cost = 15
local FuryOfTheEagle = Ability:Add(203415, true, true, 203413)
FuryOfTheEagle.buff_duration = 3
FuryOfTheEagle.cooldown_duration = 45
FuryOfTheEagle.tick_interval = 0.5
FuryOfTheEagle.hasted_duration = true
FuryOfTheEagle.hasted_ticks = true
FuryOfTheEagle:AutoAoe()
local GrenadeJuggler = Ability:Add(459843, true, true, 470488)
GrenadeJuggler.buff_duration = 8
GrenadeJuggler.max_stack = 1
local GuerrillaTactics = Ability:Add(264332, false, true)
local Harpoon = Ability:Add(190925, false, true, 190927)
Harpoon.cooldown_duration = 30
Harpoon.buff_duration = 3
Harpoon.triggers_gcd = false
Harpoon.max_range = 30
local KillCommand = Ability:Add(259489, false, true)
KillCommand.cooldown_duration = 6
KillCommand.focus_gain = 15
KillCommand.hasted_cooldown = true
KillCommand.requires_charge = true
KillCommand.requires_pet = true
KillCommand.max_range = 50
KillCommand:AutoAoe(false, 'cast')
local MercilessBlow = Ability:Add(459868, false, true, 459870)
MercilessBlow.buff_duration = 8
MercilessBlow.tick_interval = 1
MercilessBlow.hasted_ticks = true
local MongooseBite = Ability:Add(259387, false, true)
MongooseBite.focus_cost = 30
MongooseBite.max_range = 5
local MongooseFury = Ability:Add(259388, true, true)
MongooseFury.buff_duration = 14
local Muzzle = Ability:Add(187707, false, true) -- Replaces Counter-Shot
Muzzle.cooldown_duration = 15
Muzzle.max_range = 5
Muzzle.triggers_gcd = false
local OutlandVenom = Ability:Add(459939, false, true, 459941)
OutlandVenom.max_stack = 8
local Ranger = Ability:Add(385695, false, true)
local RaptorStrike = Ability:Add(186270, false, true)
RaptorStrike.focus_cost = 30
RaptorStrike.max_range = 5
local RelentlessPrimalFerocity = Ability:Add(459922, true, true)
local RuthlessMarauder = Ability:Add(470068, true, true, 470070)
RuthlessMarauder.buff_duration = 10
local SicEm = Ability:Add(459920, true, true, 461409)
SicEm.max_stack = 1
local Spearhead = Ability:Add(360966, false, true, 378957)
Spearhead.buff_duration = 10
Spearhead.cooldown_duration = 90
Spearhead.tick_interval = 1
Spearhead.hasted_ticks = true
local SymbioticAdrenaline = Ability:Add(459875, false, true)
local TermsOfEngagement = Ability:Add(265895, true, true, 265898)
TermsOfEngagement.buff_duration = 10
local TipOfTheSpear = Ability:Add(260285, true, true, 260286)
TipOfTheSpear.buff_duration = 10
TipOfTheSpear.max_stack = 3
local VipersVenom = Ability:Add(268501, false, true)
local WildfireBomb = Ability:Add(259495, false, true, 265157)
WildfireBomb.cooldown_duration = 18
WildfireBomb.focus_cost = 10
WildfireBomb.hasted_cooldown = true
WildfireBomb.requires_charge = true
WildfireBomb:SetVelocity(35)
WildfireBomb:AutoAoe()
WildfireBomb.dot = Ability:Add(269747, false, true)
WildfireBomb.dot.buff_duration = 6
WildfireBomb.dot.tick_interval = 1
WildfireBomb.dot.no_pandemic = true
local WildfireInfusion = Ability:Add(460198, false, true)
------ Procs

-- Hero talents
---- Dark Ranger

---- Pack Leader
local BeastOfOpportunity = Ability:Add(445700, true, true, 450143)
BeastOfOpportunity.buff_duration = 6
local CoveringFire = Ability:Add(445715, false, true)
local CullTheHerd = Ability:Add(445717, false, true, 449233)
CullTheHerd.buff_duration = 6
CullTheHerd.tick_interval = 2
local FrenziedTear = Ability:Add(445696, true, true, 447262)
FrenziedTear.buff_duration = 20
local FuriousAssault = Ability:Add(445699, true, true, 448814)
FuriousAssault.buff_duration = 12
FuriousAssault.max_stack = 1
local HowlOfThePack = Ability:Add(445707, true, true, 462515)
local PackAssault = Ability:Add(445721, false, true)
local PackCoordination = Ability:Add(445505, true, true, 445695)
PackCoordination.buff_duration = 20
local ScatteredPrey = Ability:Add(445768, true, true, 461866)
ScatteredPrey.buff_duration = 20
local ViciousHunt = Ability:Add(445404, true, true, 431917)
ViciousHunt.buff_duration = 20
ViciousHunt.max_stack = 1
local WildAttacks = Ability:Add(445708, true, true)
---- Sentinel
local LunarStorm = Ability:Add(450385, true, true, 450978)
LunarStorm.buff_duration = 8
LunarStorm.cooldown_duration = 15
LunarStorm:Track()
LunarStorm.damage = Ability:Add(450883, false, true)
LunarStorm.damage.tick_interval = 0.4
LunarStorm.damage:AutoAoe()
LunarStorm.debuff = Ability:Add(450884, false, true)
LunarStorm.debuff.buff_duration = 8
LunarStorm.debuff.no_pandemic = true
LunarStorm.debuff:Track()
local Sentinel = Ability:Add(450369, false, true, 450387)
Sentinel.buff_duration = 1200
Sentinel.max_stack = 10
Sentinel.no_pandemic = true
Sentinel.damage = Ability:Add(450412, false, true)
local SymphonicArsenal = Ability:Add(450383, false, true, 451194)
-- Aliases
local RaptorBite = RaptorStrike
-- Tier set bonuses

-- PvP talents

-- Racials

-- Trinket effects
local SeethingRage = Ability:Add(408835, true, true)
SeethingRage.buff_duration = 10
-- Pet abilities
Pet.Bite = Ability:Add(17253, false, 'pet')
Pet.Bite.cooldown_duration = 3
Pet.Bite.focus_cost = 25
Pet.Claw = Ability:Add(16827, false, 'pet')
Pet.Claw.cooldown_duration = 3
Pet.Claw.focus_cost = 25
Pet.FlankingStrike = Ability:Add(259516, false, 'pet')
Pet.FlankingStrike.focus_gain = 30
Pet.Growl = Ability:Add(2649, false, 'pet')
Pet.Growl.cooldown_duration = 8
Pet.Smack = Ability:Add(49966, false, 'pet')
Pet.Smack.cooldown_duration = 3
Pet.Smack.focus_cost = 25
-- End Abilities

-- Start Summoned Pets

function SummonedPets:Purge()
	for _, pet in next, self.known do
		for guid, unit in next, pet.active_units do
			if unit.expires <= Player.time then
				pet.active_units[guid] = nil
			end
		end
	end
end

function SummonedPets:Update()
	wipe(self.known)
	wipe(self.byUnitId)
	for _, pet in next, self.all do
		pet.known = pet.summon_spell and pet.summon_spell.known
		if pet.known then
			self.known[#SummonedPets.known + 1] = pet
			self.byUnitId[pet.unitId] = pet
		end
	end
end

function SummonedPets:Count()
	local count = 0
	for _, pet in next, self.known do
		count = count + pet:Count()
	end
	return count
end

function SummonedPets:Clear()
	for _, pet in next, self.known do
		pet:Clear()
	end
end

function SummonedPet:Add(unitId, duration, summonSpell)
	local pet = {
		unitId = unitId,
		duration = duration,
		active_units = {},
		summon_spell = summonSpell,
		known = false,
	}
	setmetatable(pet, self)
	SummonedPets.all[#SummonedPets.all + 1] = pet
	return pet
end

function SummonedPet:Remains(initial)
	if self.summon_spell and self.summon_spell.summon_count > 0 and self.summon_spell:Casting() then
		return self:Duration()
	end
	local expires_max = 0
	for guid, unit in next, self.active_units do
		if (not initial or unit.initial) and unit.expires > expires_max then
			expires_max = unit.expires
		end
	end
	return max(0, expires_max - Player.time - Player.execute_remains)
end

function SummonedPet:Up(...)
	return self:Remains(...) > 0
end

function SummonedPet:Down(...)
	return self:Remains(...) <= 0
end

function SummonedPet:Count()
	local count = 0
	if self.summon_spell and self.summon_spell:Casting() then
		count = count + self.summon_spell.summon_count
	end
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time > Player.execute_remains then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:Duration()
	return self.duration
end

function SummonedPet:Expiring(seconds)
	local count = 0
	for guid, unit in next, self.active_units do
		if unit.expires - Player.time <= (seconds or Player.execute_remains) then
			count = count + 1
		end
	end
	return count
end

function SummonedPet:AddUnit(guid)
	local unit = {
		guid = guid,
		spawn = Player.time,
		expires = Player.time + self:Duration(),
	}
	self.active_units[guid] = unit
	--log(format('%.3f SUMMONED PET ADDED %s EXPIRES %.3f', unit.spawn, guid, unit.expires))
	return unit
end

function SummonedPet:RemoveUnit(guid)
	if self.active_units[guid] then
		--log(format('%.3f SUMMONED PET REMOVED %s AFTER %.3fs EXPECTED %.3fs', Player.time, guid, Player.time - self.active_units[guid], self.active_units[guid].expires))
		self.active_units[guid] = nil
	end
end

function SummonedPet:ExtendAll(seconds)
	for guid, unit in next, self.active_units do
		if unit.expires > Player.time then
			unit.expires = unit.expires + seconds
		end
	end
end

function SummonedPet:Clear()
	for guid in next, self.active_units do
		self.active_units[guid] = nil
	end
end

-- Summoned Pets
Pet.SentinelOwl = SummonedPet:Add(233188, LunarStorm.cooldown_duration, LunarStorm)
-- End Summoned Pets

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
		off_gcd = true,
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
	local start, duration
	if self.equip_slot then
		start, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		start, duration = GetItemCooldown(self.itemId)
	end
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - (self.off_gcd and 0 or Player.execute_remains))
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
local Healthstone = InventoryItem:Add(5512)
Healthstone.max_charges = 3
-- Equipment
local Trinket1 = InventoryItem:Add(0)
local Trinket2 = InventoryItem:Add(0)
-- End Inventory Items

-- Start Abilities Functions

function Abilities:Update()
	wipe(self.bySpellId)
	wipe(self.velocity)
	wipe(self.autoAoe)
	wipe(self.tracked)
	for _, ability in next, self.all do
		if ability.known then
			self.bySpellId[ability.spellId] = ability
			if ability.spellId2 then
				self.bySpellId[ability.spellId2] = ability
			end
			if ability.velocity > 0 then
				self.velocity[#self.velocity + 1] = ability
			end
			if ability.auto_aoe then
				self.autoAoe[#self.autoAoe + 1] = ability
			end
			if ability.aura_targets then
				self.tracked[#self.tracked + 1] = ability
			end
		end
	end
end

-- End Abilities Functions

-- Start Player Functions

function Player:FocusTimeToMax(focus)
	local deficit = (focus or self.focus.max) - self.focus.current
	if deficit <= 0 then
		return 0
	end
	return deficit / self.focus.regen
end

function Player:ResetSwing(mainHand, offHand, missed)
	local mh, oh = UnitAttackSpeed('player')
	if mainHand then
		self.swing.mh.speed = (mh or 0)
		self.swing.mh.last = self.time
	end
	if offHand then
		self.swing.oh.speed = (oh or 0)
		self.swing.oh.last = self.time
	end
end

function Player:TimeInCombat()
	if self.combat_start > 0 then
		return self.time - self.combat_start
	end
	if self.cast.ability and self.cast.ability.triggers_combat then
		return 0.1
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
	local aura
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HELPFUL')
		if not aura then
			return false
		elseif (
			aura.spellId == 2825 or   -- Bloodlust (Horde Shaman)
			aura.spellId == 32182 or  -- Heroism (Alliance Shaman)
			aura.spellId == 80353 or  -- Time Warp (Mage)
			aura.spellId == 90355 or  -- Ancient Hysteria (Hunter Pet - Core Hound)
			aura.spellId == 160452 or -- Netherwinds (Hunter Pet - Nether Ray)
			aura.spellId == 264667 or -- Primal Rage (Hunter Pet - Ferocity)
			aura.spellId == 381301 or -- Feral Hide Drums (Leatherworking)
			aura.spellId == 390386    -- Fury of the Aspects (Evoker)
		) then
			return true
		end
	end
end

function Player:Exhausted()
	local aura
	for i = 1, 40 do
		aura = UnitAura('player', i, 'HARMFUL')
		if not aura then
			return false
		elseif (
			aura.spellId == 57724 or -- Sated (Alliance Shaman)
			aura.spellId == 57723 or -- Exhaustion (Horde Shaman)
			aura.spellId == 80354 or -- Temporal Displacement (Mage)
			aura.spellId == 264689 or-- Fatigued (Hunter)
			aura.spellId == 390435   -- Exhaustion (Evoker)
		) then
			return true
		end
	end
end

function Player:Equipped(itemID, slot)
	for i = (slot or 1), (slot or 19) do
		if GetInventoryItemID('player', i) == itemID then
			return true, i
		end
	end
	return false
end

function Player:BonusIdEquipped(bonusId, slot)
	local link, item
	for i = (slot or 1), (slot or 19) do
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

function Player:UpdateKnown()
	local info, node
	local configId = C_ClassTalents.GetActiveConfigID()
	for _, ability in next, Abilities.all do
		if not ability.pet_spell then
			ability.known = false
			ability.rank = 0
			for _, spellId in next, ability.spellIds do
				info = GetSpellInfo(spellId)
				if info then
					ability.spellId, ability.name, ability.icon = info.spellID, info.name, info.originalIconID
				end
				if IsPlayerSpell(spellId) or (ability.learn_spellId and IsPlayerSpell(ability.learn_spellId)) then
					ability.known = true
					break
				end
			end
			if ability.bonus_id then -- used for checking enchants and crafted effects
				ability.known = self:BonusIdEquipped(ability.bonus_id)
			end
			if ability.talent_node and configId then
				node = C_Traits.GetNodeInfo(configId, ability.talent_node)
				if node then
					ability.rank = node.activeRank
					ability.known = ability.rank > 0
				end
			end
			if C_LevelLink.IsSpellLocked(ability.spellId) or (ability.check_usable and not IsSpellUsable(ability.spellId)) then
				ability.known = false -- spell is locked, do not mark as known
			end
		end
	end

	RaptorBite = MongooseBite.known and MongooseBite or RaptorStrike
	SerpentSting.known = RaptorBite.known
	Bloodseeker.buff.known = Bloodseeker.known
	ExplosiveShot.explosion.known = ExplosiveShot.known
	if MongooseBite.known then
		MongooseFury.known = true
		RaptorStrike.known = false
	end
	LunarStorm.damage.known = LunarStorm.known
	LunarStorm.debuff.known = LunarStorm.known
	WildfireBomb.dot.known = WildfireBomb.known
	Sentinel.damage.known = Sentinel.known

	Abilities:Update()
	SummonedPets:Update()

	if APL[self.spec].precombat_variables then
		APL[self.spec]:precombat_variables()
	end
end

function Player:UpdateChannelInfo()
	local channel = self.channel
	local _, _, _, start, ends, _, _, spellId = UnitChannelInfo('player')
	if not spellId then
		channel.ability = nil
		channel.chained = false
		channel.start = 0
		channel.ends = 0
		channel.tick_count = 0
		channel.tick_interval = 0
		channel.ticks = 0
		channel.ticks_remain = 0
		channel.ticks_extra = 0
		channel.interrupt_if = nil
		channel.interruptible = false
		channel.early_chain_if = nil
		channel.early_chainable = false
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if ability then
		if ability == channel.ability then
			channel.chained = true
		end
		channel.interrupt_if = ability.interrupt_if
	else
		channel.interrupt_if = nil
	end
	channel.ability = ability
	channel.ticks = 0
	channel.start = start / 1000
	channel.ends = ends / 1000
	if ability and ability.tick_interval then
		channel.tick_interval = ability:TickTime()
	else
		channel.tick_interval = channel.ends - channel.start
	end
	channel.tick_count = (channel.ends - channel.start) / channel.tick_interval
	if channel.chained then
		channel.ticks_extra = channel.tick_count - floor(channel.tick_count)
	else
		channel.ticks_extra = 0
	end
	channel.ticks_remain = channel.tick_count
end

function Player:UpdateThreat()
	local _, status, pct
	_, status, pct = UnitDetailedThreatSituation('player', 'target')
	self.threat.status = status or 0
	self.threat.pct = pct or 0
	self.threat.lead = 0
	if self.threat.status >= 3 and DETAILS_PLUGIN_TINY_THREAT then
		local threat_table = DETAILS_PLUGIN_TINY_THREAT.player_list_indexes
		if threat_table and threat_table[1] and threat_table[2] and threat_table[1][1] == self.name then
			self.threat.lead = max(0, threat_table[1][6] - threat_table[2][6])
		end
	end
end

function Player:Update()
	local _, cooldown, start, ends, spellId, speed, max_speed, speed_mh, speed_oh
	self.main = nil
	self.cd = nil
	self.interrupt = nil
	self.extra = nil
	self.wait_time = nil
	self.pool_focus = nil
	self:UpdateTime()
	self.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	self.gcd = 1.5 * self.haste_factor
	cooldown = GetSpellCooldown(61304)
	self.gcd_remains = cooldown.startTime > 0 and cooldown.duration - (self.ctime - cooldown.startTime) or 0
	_, _, _, start, ends, _, _, _, spellId = UnitCastingInfo('player')
	if spellId then
		self.cast.ability = Abilities.bySpellId[spellId]
		self.cast.start = start / 1000
		self.cast.ends = ends / 1000
		self.cast.remains = self.cast.ends - self.ctime
	else
		self.cast.ability = nil
		self.cast.start = 0
		self.cast.ends = 0
		self.cast.remains = 0
	end
	self.execute_remains = max(self.cast.remains, self.gcd_remains)
	if self.channel.tick_count > 1 then
		self.channel.ticks = ((self.ctime - self.channel.start) / self.channel.tick_interval) - self.channel.ticks_extra
		self.channel.ticks_remain = (self.channel.ends - self.ctime) / self.channel.tick_interval
	end
	self.focus.regen = GetPowerRegenForPowerType(2)
	self.focus.current = UnitPower('player', 2) + (self.focus.regen * self.execute_remains)
	if self.cast.ability and self.cast.ability.focus_cost then
		self.focus.current = self.focus.current - self.cast.ability:Cost()
	end
	self.focus.current = clamp(self.focus.current, 0, self.focus.max)
	self.focus.deficit = self.focus.max - self.focus.current
	speed, max_speed = GetUnitSpeed('player')
	self.moving = speed ~= 0
	self.movement_speed = max_speed / 7 * 100
	speed_mh, speed_oh = UnitAttackSpeed('player')
	self.swing.mh.speed = speed_mh or 0
	self.swing.oh.speed = speed_oh or 0
	self.swing.mh.remains = max(0, self.swing.mh.last + self.swing.mh.speed - self.time)
	self.swing.oh.remains = max(0, self.swing.oh.last + self.swing.oh.speed - self.time)
	self:UpdateThreat()

	Pet:Update()

	SummonedPets:Purge()
	TrackedAuras:Purge()
	if Opt.auto_aoe then
		for _, ability in next, Abilities.autoAoe do
			ability:UpdateTargetsHit()
		end
		AutoAoe:Purge()
	end

	self.major_cd_remains = (
		(BestialWrath.known and BestialWrath:Remains()) or
		(CoordinatedAssault.known and CoordinatedAssault:Remains())
	) or 0

	self.main = APL[self.spec]:Main()

	if self.channel.interrupt_if then
		self.channel.interruptible = self.channel.ability ~= self.main and self.channel.interrupt_if()
	end
	if self.channel.early_chain_if then
		self.channel.early_chainable = self.channel.ability == self.main and self.channel.early_chain_if()
	end
end

function Player:Init()
	local _
	if #UI.glows == 0 then
		UI:DisableOverlayGlows()
		UI:CreateOverlayGlows()
		UI:HookResourceFrame()
	end
	ghPreviousPanel.ability = nil
	self.guid = UnitGUID('player')
	self.name = UnitName('player')
	_, self.instance = IsInInstance()
	Events:GROUP_ROSTER_UPDATE()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

-- End Player Functions

-- Start Pet Functions

function Pet:UpdateKnown()
	local info
	for _, ability in next, Abilities.all do
		if ability.pet_spell then
			ability.known = false
			ability.rank = 0
			for _, spellId in next, ability.spellIds do
				info = GetSpellInfo(spellId)
				ability.spellId, ability.name, ability.icon = info.spellID, info.name, info.originalIconID
				if IsSpellKnown(spellId, true) then
					ability.known = true
					break
				end
			end
		end
	end

	self.basic_attack = (
		(self.Bite.known and self.Bite) or
		(self.Claw.known and self.Claw) or
		(self.Smack.known and self.Smack)
	)
	self.FlankingStrike.known = FlankingStrike.known

	Abilities:Update()
end

function Pet:Update()
	self.guid = UnitGUID('pet')
	self.alive = self.guid and not UnitIsDead('pet')
	self.active = (self.alive and not self.stuck or IsFlying()) and true
	self.focus.regen = GetPowerRegenForPowerType(2)
	self.focus.max = self.active and UnitPowerMax('pet', 2) or 100
	self.focus.current = UnitPower('pet', 2) + (self.focus.regen * Player.execute_remains)
end

-- End Pet Functions

-- Start Target Functions

function Target:UpdateHealth(reset)
	Timer.health = 0
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
	self.timeToDieMax = self.health.current / Player.health.max * 15
	self.health.pct = self.health.max > 0 and (self.health.current / self.health.max * 100) or 100
	self.health.loss_per_sec = (self.health.history[1] - self.health.current) / 5
	self.timeToDie = (
		(self.dummy and 600) or
		(self.health.loss_per_sec > 0 and min(self.timeToDieMax, self.health.current / self.health.loss_per_sec)) or
		self.timeToDieMax
	)
end

function Target:Update()
	if UI:ShouldHide() then
		return UI:Disappear()
	end
	local guid = UnitGUID('target')
	if not guid then
		self.guid = nil
		self.uid = nil
		self.boss = false
		self.dummy = false
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
		return UI:Disappear()
	end
	if guid ~= self.guid then
		self.guid = guid
		self.uid = ToUID(guid) or 0
		self:UpdateHealth(true)
	end
	self.boss = false
	self.dummy = false
	self.stunnable = true
	self.classification = UnitClassification('target')
	self.player = UnitIsPlayer('target')
	self.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	self.level = UnitLevel('target')
	if self.level == -1 then
		self.level = Player.level + 3
	end
	if not self.player and self.classification ~= 'minus' and self.classification ~= 'normal' then
		self.boss = self.level >= (Player.level + 3)
		self.stunnable = self.level < (Player.level + 2)
	end
	if self.Dummies[self.uid] then
		self.boss = true
		self.dummy = true
	end
	if self.hostile or Opt.always_on then
		UI:UpdateCombat()
		ghPanel:Show()
		return true
	end
	UI:Disappear()
end

function Target:TimeToPct(pct)
	if self.health.pct <= pct then
		return 0
	end
	if self.health.loss_per_sec <= 0 then
		return self.timeToDieMax
	end
	return min(self.timeToDieMax, (self.health.current - (self.health.max * (pct / 100))) / self.health.loss_per_sec)
end

function Target:Stunned()
	return Intimidation:Up()
end

-- End Target Functions

-- Start Ability Modifications

function Harpoon:CastLanded(dstGUID, event)
	Ability.CastLanded(self, dstGUID, event)
	Target.estimated_range = 5
end

function KillShot:Usable(...)
	if not Ability.Usable(self, ...) then
		return false
	end
	if Target.health.pct < 20 then
		return true
	end
	if Deathblow.known and Deathblow:Up() then
		return true
	end
	return false
end

function RaptorStrike:Cost()
	if FuriousAssault.known and FuriousAssault:Up() then
		return 0
	end
	return Ability.Cost(self)
end
MongooseBite.Cost = RaptorStrike.Cost

function CallPet1:Usable(...)
	if Pet.active then
		return false
	end
	return Ability.Usable(self, ...)
end

function MendPet:Usable(...)
	if Opt.mend_threshold <= 0 then
		return false
	end
	if Pet.health.pct >= Opt.mend_threshold then
		return false
	end
	return Ability.Usable(self, ...)
end

function RevivePet:Usable(...)
	if Pet.alive then
		return false
	end
	return Ability.Usable(self, ...)
end

function PetFrenzy:StartDurationStack()
	local aura
	for i = 1, 40 do
		aura = UnitAura(self.aura_target, i, self.aura_filter)
		if not aura then
			return 0, 0, 0
		elseif self:Match(aura.spellId) then
			return aura.expirationTime - aura.duration, aura.duration, aura.applications
		end
	end
	return 0, 0, 0
end

function CoordinatedAssault:CooldownDuration()
	local duration = Ability.CooldownDuration(self)
	if SymbioticAdrenaline.known then
		duration = duration - 60
	end
	return max(0, duration)
end

function LunarStorm:Remains()
	local aura = self.aura_targets[Player.guid]
	return aura and max(0, aura.expires - Player.time - Player.execute_remains) or 0
end

function LunarStorm:Cooldown()
	local remains = Pet.SentinelOwl:Remains()
	if remains == 0 and (Player.time - WildfireBomb.last_used) < 2 then
		return self:CooldownDuration()
	end
	return remains
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

local function Pool(ability, extra)
	Player.pool_focus = ability:Cost() + (extra or 0)
	return ability
end

-- Begin Action Priority Lists

APL[SPEC.NONE].Main = function(self)
end

APL[SPEC.BEASTMASTERY].Main = function(self)
	if Player.health.pct < Opt.heal and Exhilaration:Usable() then
		UseExtra(Exhilaration)
	elseif CallPet1:Usable() then
		UseExtra(CallPet1)
	elseif RevivePet:Usable() then
		UseExtra(RevivePet)
	elseif MendPet:Usable() then
		UseExtra(MendPet)
	end
end

APL[SPEC.MARKSMANSHIP].Main = function(self)
	if Player.health.pct < Opt.heal and Exhilaration:Usable() then
		UseExtra(Exhilaration)
	elseif CallPet1:Usable() then
		UseExtra(CallPet1)
	elseif RevivePet:Usable() then
		UseExtra(RevivePet)
	elseif MendPet:Usable() then
		UseExtra(MendPet)
	end
end

APL[SPEC.SURVIVAL].Main = function(self)
	if Player.health.pct < Opt.heal and Exhilaration:Usable() then
		UseExtra(Exhilaration)
	elseif CallPet1:Usable() then
		UseExtra(CallPet1)
	elseif RevivePet:Usable() then
		UseExtra(RevivePet)
	elseif MendPet:Usable() then
		UseExtra(MendPet)
	end
	if Player:TimeInCombat() == 0 then
--[[
actions.precombat=summon_pet
actions.precombat+=/use_item,name=imperfect_ascendancy_serum
actions.precombat+=/snapshot_stats
]]
		if HuntersMark:Usable() and HuntersMark:Down() and Target:TimeToPct(80) > 10 then
			UseCooldown(HuntersMark)
		elseif Harpoon:Usable() then
			UseCooldown(Harpoon)
		end
	end
--[[
actions=auto_attack
actions+=/call_action_list,name=cds
actions+=/call_action_list,name=plst,if=active_enemies<3&talent.vicious_hunt
actions+=/call_action_list,name=plcleave,if=active_enemies>2&talent.vicious_hunt
actions+=/call_action_list,name=sentst,if=active_enemies<3&!talent.vicious_hunt
actions+=/call_action_list,name=sentcleave,if=active_enemies>2&!talent.vicious_hunt
actions+=/arcane_torrent
actions+=/bag_of_tricks
actions+=/lights_judgment
]]
	self.use_cds = Target.boss or Target.player or Target.timeToDie > (Opt.cd_ttd - min(6, Player.enemies - 1)) or (CoordinatedAssault.known and CoordinatedAssault:Up()) or (Spearhead.known and Spearhead:Up())
	if self.use_cds then
		self:cds()
	end
	local apl
	if ViciousHunt.known then
		if Player.enemies < 3 then
			apl = self:plst()
		else
			apl = self:plcleave()
		end
	else
		if Player.enemies < 3 then
			apl = self:sentst()
		else
			apl = self:sentcleave()
		end
	end
	return apl
end

APL[SPEC.SURVIVAL].cds = function(self)
--[[
actions.cds=blood_fury,if=buff.coordinated_assault.up|!talent.coordinated_assault&cooldown.spearhead.remains|!talent.spearhead&!talent.coordinated_assault
actions.cds+=/invoke_external_buff,name=power_infusion,if=buff.coordinated_assault.up|!talent.coordinated_assault&cooldown.spearhead.remains|!talent.spearhead&!talent.coordinated_assault
actions.cds+=/harpoon,if=prev.kill_command
actions.cds+=/ancestral_call,if=buff.coordinated_assault.up|!talent.coordinated_assault&cooldown.spearhead.remains|!talent.spearhead&!talent.coordinated_assault
actions.cds+=/fireblood,if=buff.coordinated_assault.up|!talent.coordinated_assault&cooldown.spearhead.remains|!talent.spearhead&!talent.coordinated_assault
actions.cds+=/berserking,if=buff.coordinated_assault.up|!talent.coordinated_assault&cooldown.spearhead.remains|!talent.spearhead&!talent.coordinated_assault|time_to_die<13
actions.cds+=/muzzle
actions.cds+=/potion,if=target.time_to_die<25|buff.coordinated_assault.up|!talent.coordinated_assault&cooldown.spearhead.remains|!talent.spearhead&!talent.coordinated_assault
actions.cds+=/use_item,name=imperfect_ascendancy_serum,use_off_gcd=1,if=gcd.remains>gcd.max-0.1
actions.cds+=/use_item,name=mad_queens_mandate,if=(time_to_die<10|time_to_die>120)&(trinket.skardyns_grace.cooldown.remains|!equipped.skardyns_grace)|time_to_die<10
actions.cds+=/use_items,if=cooldown.coordinated_assault.remains|cooldown.spearhead.remains
actions.cds+=/aspect_of_the_eagle,if=target.distance>=6
]]
	if HuntersMark:Usable() and HuntersMark:Down() and Target:TimeToPct(80) > 15 then
		return UseCooldown(HuntersMark)
	end
	if Opt.trinket then
		if Trinket1:Usable() then
			return UseCooldown(Trinket1)
		elseif Trinket2:Usable() then
			return UseCooldown(Trinket2)
		end
	end
end

APL[SPEC.SURVIVAL].plst = function(self)
--[[
actions.plst=raptor_bite,target_if=max:dot.serpent_sting.remains,if=buff.howl_of_the_pack.up&pet.main.buff.pack_coordination.up&buff.howl_of_the_pack.remains<gcd
actions.plst+=/kill_command,target_if=min:bloodseeker.remains,if=(buff.relentless_primal_ferocity.up&buff.tip_of_the_spear.stack<1)
actions.plst+=/butchery,if=buff.scattered_prey.up&buff.scattered_prey.remains<gcd
actions.plst+=/spearhead,if=cooldown.coordinated_assault.remains
actions.plst+=/raptor_bite,target_if=min:dot.serpent_sting.remains,if=!dot.serpent_sting.ticking&target.time_to_die>12&(!talent.contagious_reagents|active_dot.serpent_sting=0)
actions.plst+=/raptor_bite,target_if=max:dot.serpent_sting.remains,if=talent.contagious_reagents&active_dot.serpent_sting<active_enemies&dot.serpent_sting.remains
actions.plst+=/butchery
actions.plst+=/flanking_strike,if=buff.tip_of_the_spear.stack=2|buff.tip_of_the_spear.stack=1
actions.plst+=/kill_shot,if=buff.tip_of_the_spear.stack>0
actions.plst+=/wildfire_bomb,if=buff.tip_of_the_spear.stack>0&cooldown.wildfire_bomb.charges_fractional>1.4|cooldown.wildfire_bomb.charges_fractional>1.9|cooldown.coordinated_assault.remains<2*gcd&talent.bombardier
actions.plst+=/explosive_shot
actions.plst+=/coordinated_assault,if=!talent.bombardier|talent.bombardier&cooldown.wildfire_bomb.charges_fractional<1
actions.plst+=/fury_of_the_eagle,if=buff.tip_of_the_spear.stack>0&(!raid_event.adds.exists|raid_event.adds.exists&raid_event.adds.in>40)
actions.plst+=/raptor_bite,if=buff.furious_assault.up
actions.plst+=/kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max&(!buff.relentless_primal_ferocity.up|(buff.relentless_primal_ferocity.up&buff.tip_of_the_spear.stack<1|focus<30))
actions.plst+=/wildfire_bomb,if=buff.tip_of_the_spear.stack>0&(!raid_event.adds.exists|raid_event.adds.exists&raid_event.adds.in>15)
actions.plst+=/raptor_bite,target_if=min:dot.serpent_sting.remains,if=!talent.contagious_reagents
actions.plst+=/raptor_bite,target_if=max:dot.serpent_sting.remains
]]

end

APL[SPEC.SURVIVAL].plcleave = function(self)
--[[
actions.plcleave=spearhead,if=cooldown.coordinated_assault.remains
actions.plcleave+=/kill_command,target_if=min:bloodseeker.remains,if=buff.relentless_primal_ferocity.up&buff.tip_of_the_spear.stack<1
actions.plcleave+=/wildfire_bomb,if=buff.tip_of_the_spear.stack>0&cooldown.wildfire_bomb.charges_fractional>1.7|cooldown.wildfire_bomb.charges_fractional>1.9|cooldown.coordinated_assault.remains<2*gcd|talent.butchery&cooldown.butchery.remains<gcd
actions.plcleave+=/flanking_strike,if=buff.tip_of_the_spear.stack=2|buff.tip_of_the_spear.stack=1
actions.plcleave+=/butchery
actions.plcleave+=/explosive_shot
actions.plcleave+=/coordinated_assault,if=!talent.bombardier|talent.bombardier&cooldown.wildfire_bomb.charges_fractional<1
actions.plcleave+=/fury_of_the_eagle,if=buff.tip_of_the_spear.stack>0
actions.plcleave+=/kill_shot,if=buff.deathblow.remains
actions.plcleave+=/kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max
actions.plcleave+=/wildfire_bomb,if=buff.tip_of_the_spear.stack>0
actions.plcleave+=/kill_shot
actions.plcleave+=/kill_command,target_if=min:bloodseeker.remains
actions.plcleave+=/raptor_bite
]]

end

APL[SPEC.SURVIVAL].sentst = function(self)
--[[
actions.sentst=wildfire_bomb,if=!cooldown.lunar_storm.remains
actions.sentst+=/kill_command,target_if=min:bloodseeker.remains,if=(buff.relentless_primal_ferocity.up&buff.tip_of_the_spear.stack<1)
actions.sentst+=/spearhead,if=cooldown.coordinated_assault.remains
actions.sentst+=/raptor_bite,target_if=min:dot.serpent_sting.remains,if=!dot.serpent_sting.ticking&target.time_to_die>12&(!talent.contagious_reagents|active_dot.serpent_sting=0)
actions.sentst+=/raptor_bite,target_if=max:dot.serpent_sting.remains,if=talent.contagious_reagents&active_dot.serpent_sting<active_enemies&dot.serpent_sting.remains
actions.sentst+=/flanking_strike,if=buff.tip_of_the_spear.stack=2|buff.tip_of_the_spear.stack=1
actions.sentst+=/wildfire_bomb,if=(cooldown.lunar_storm.remains>full_recharge_time-gcd)&(buff.tip_of_the_spear.stack>0&cooldown.wildfire_bomb.charges_fractional>1.7|cooldown.wildfire_bomb.charges_fractional>1.9)|(talent.bombardier&cooldown.coordinated_assault.remains<2*gcd)
actions.sentst+=/butchery
actions.sentst+=/coordinated_assault,if=!talent.bombardier|talent.bombardier&cooldown.wildfire_bomb.charges_fractional<1
actions.sentst+=/explosive_shot
actions.sentst+=/fury_of_the_eagle,if=buff.tip_of_the_spear.stack>0
actions.sentst+=/kill_shot
actions.sentst+=/kill_command,target_if=min:bloodseeker.remains,if=buff.tip_of_the_spear.stack<1&cooldown.flanking_strike.remains<gcd
actions.sentst+=/kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max&(!buff.relentless_primal_ferocity.up|(buff.relentless_primal_ferocity.up&(buff.tip_of_the_spear.stack<2|focus<30)))
actions.sentst+=/wildfire_bomb,if=buff.tip_of_the_spear.stack>0&cooldown.lunar_storm.remains>full_recharge_time&(!raid_event.adds.exists|raid_event.adds.exists&raid_event.adds.in>15)
actions.sentst+=/raptor_bite,target_if=min:dot.serpent_sting.remains,if=!talent.contagious_reagents
actions.sentst+=/raptor_bite,target_if=max:dot.serpent_sting.remains
]]
	if LunarStorm.known and WildfireBomb:Usable() and LunarStorm:Ready() then
		return WildfireBomb
	end
	if RelentlessPrimalFerocity.known and KillCommand:Usable() and RelentlessPrimalFerocity:Up() and TipOfTheSpear:Down() then
		return KillCommand
	end
	if self.use_cds and Spearhead:Usable() and CoordinatedAssault:Up() and (Target.boss or Target.timeToDie > 6) then
		UseCooldown(Spearhead)
	end
	if RaptorBite:Usable() and (
		(SerpentSting:Down() and Target.timeToDie > 12 and (not ContagiousReagents.known or SerpentSting:Ticking() == 0)) or
		(ContagiousReagents.known and SerpentSting:Up() and SerpentSting:Ticking() < Player.enemies)
	) then
		return RaptorBite
	end
	if self.use_cds and FlankingStrike:Usable() and (not TipOfTheSpear.known or between(TipOfTheSpear:Stack(), 1, 2)) then
		UseCooldown(FlankingStrike)
	end
	if WildfireBomb:Usable() and (not LunarStorm.known or LunarStorm:Cooldown() > (WildfireBomb:FullRechargeTime() - Player.gcd)) and (
		WildfireBomb:ChargesFractional() > 1.9 or
		(TipOfTheSpear.known and TipOfTheSpear:Up() and WildfireBomb:ChargesFractional() > 1.7) or
		(self.use_cds and Bombardier.known and CoordinatedAssault:Ready(Player.gcd * 2))
	) then
		return WildfireBomb
	end
	if Butchery:Usable() then
		return Butchery
	end
	if self.use_cds and CoordinatedAssault:Usable() and (not Bombardier.known or WildfireBomb:ChargesFractional() < 1) then
		UseCooldown(CoordinatedAssault)
	end
	if ExplosiveShot:Usable() and (Player.enemies > 1 or Target.timeToDie > ExplosiveShot:Duration()) then
		return ExplosiveShot
	end
	if self.use_cds and FuryOfTheEagle:Usable() and (not TipOfTheSpear.known or TipOfTheSpear:Up()) then
		UseCooldown(FuryOfTheEagle)
	end
	if KillShot:Usable() then
		return KillShot
	end
	if KillCommand:Usable() and (
		(FlankingStrike.known and TipOfTheSpear:Down() and FlankingStrike:Ready(Player.gcd)) or
		(KillCommand:WontCapFocus() and (not RelentlessPrimalFerocity.known or RelentlessPrimalFerocity:Down() or (TipOfTheSpear.known and TipOfTheSpear:Stack() < 2) or Player.focus.current < 30))
	) then
		return KillCommand
	end
	if WildfireBomb:Usable() and (not TipOfTheSpear.known or TipOfTheSpear:Up()) and (not LunarStorm.known or LunarStorm:Cooldown() > WildfireBomb:FullRechargeTime()) then
		return WildfireBomb
	end
	if RaptorBite:Usable() then
		return RaptorBite
	end
end

APL[SPEC.SURVIVAL].sentcleave = function(self)
--[[
actions.sentcleave=wildfire_bomb,if=!cooldown.lunar_storm.remains
actions.sentcleave+=/kill_command,target_if=min:bloodseeker.remains,if=buff.relentless_primal_ferocity.up&buff.tip_of_the_spear.stack<1
actions.sentcleave+=/wildfire_bomb,if=buff.tip_of_the_spear.stack>0&cooldown.wildfire_bomb.charges_fractional>1.7|cooldown.wildfire_bomb.charges_fractional>1.9|(talent.bombardier&cooldown.coordinated_assault.remains<2*gcd)|talent.butchery&cooldown.butchery.remains<gcd
actions.sentcleave+=/butchery
actions.sentcleave+=/explosive_shot
actions.sentcleave+=/coordinated_assault,if=!talent.bombardier|talent.bombardier&cooldown.wildfire_bomb.charges_fractional<1
actions.sentcleave+=/fury_of_the_eagle,if=buff.tip_of_the_spear.stack>0
actions.sentcleave+=/flanking_strike,if=(buff.tip_of_the_spear.stack=2|buff.tip_of_the_spear.stack=1)
actions.sentcleave+=/kill_shot,if=buff.deathblow.remains&talent.sic_em
actions.sentcleave+=/kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max
actions.sentcleave+=/wildfire_bomb,if=buff.tip_of_the_spear.stack>0
actions.sentcleave+=/kill_command,target_if=min:bloodseeker.remains
actions.sentcleave+=/raptor_bite,target_if=min:dot.serpent_sting.remains,if=!talent.contagious_reagents
actions.sentcleave+=/raptor_bite,target_if=max:dot.serpent_sting.remains
]]
	if LunarStorm.known and WildfireBomb:Usable() and LunarStorm:Ready() then
		return WildfireBomb
	end
	if RelentlessPrimalFerocity.known and KillCommand:Usable() and RelentlessPrimalFerocity:Up() and TipOfTheSpear:Down() then
		return KillCommand
	end
	if WildfireBomb:Usable() and (
		WildfireBomb:ChargesFractional() > 1.9 or
		(TipOfTheSpear.known and TipOfTheSpear:Up() and WildfireBomb:ChargesFractional() > 1.7) or
		(self.use_cds and Bombardier.known and CoordinatedAssault:Ready(Player.gcd * 2)) or
		(Butchery.known and Butchery:Ready(Player.gcd))
	) then
		return WildfireBomb
	end
	if Butchery:Usable() then
		return Butchery
	end
	if ExplosiveShot:Usable() and (Player.enemies > 1 or Target.timeToDie > ExplosiveShot:Duration()) then
		return ExplosiveShot
	end
	if self.use_cds then
		if CoordinatedAssault:Usable() and (not Bombardier.known or WildfireBomb:ChargesFractional() < 1) then
			UseCooldown(CoordinatedAssault)
		end
		if FuryOfTheEagle:Usable() and (not TipOfTheSpear.known or TipOfTheSpear:Up()) then
			UseCooldown(FuryOfTheEagle)
		end
		if FlankingStrike:Usable() and (not TipOfTheSpear.known or between(TipOfTheSpear:Stack(), 1, 2)) then
			UseCooldown(FlankingStrike)
		end
	end
	if SicEm.known and KillShot:Usable() and Deathblow:Up() then
		return KillShot
	end
	if TipOfTheSpear.known and KillCommand:Usable() and KillCommand:WontCapFocus() and TipOfTheSpear:Stack() < TipOfTheSpear:MaxStack() then
		return KillCommand
	end
	if WildfireBomb:Usable() and WildfireBomb.dot:Down() and (not TipOfTheSpear.known or TipOfTheSpear:Up()) then
		return WildfireBomb
	end
	if KillCommand:Usable() and (TipOfTheSpear:Stack() < TipOfTheSpear:MaxStack() or (Target.timeToDie > 4 and Bloodseeker:Down())) then
		return KillCommand
	end
	if WildfireBomb:Usable() and (not TipOfTheSpear.known or TipOfTheSpear:Up()) then
		return WildfireBomb
	end
	if KillShot:Usable() then
		return KillShot
	end
	if RaptorBite:Usable() and (
		(not TipOfTheSpear.known or not between(TipOfTheSpear:Stack(), 1, 2)) or
		(ContagiousReagents.known and SerpentSting:Up())
	) then
		return RaptorBite
	end
	if KillCommand:Usable() then
		return KillCommand
	end
	if RaptorBite:Usable() and Player.focus.current > 60 then
		return RaptorBite
	end
end

APL.Interrupt = function(self)
	if CounterShot:Usable() then
		return CounterShot
	end
	if Muzzle:Usable() then
		return Muzzle
	end
	if Intimidation:Usable() then
		return Intimidation
	end
	if ScatterShot:Usable() then
		return ScatterShot
	end
end

-- End Action Priority Lists

-- Start UI Functions

function UI.DenyOverlayGlow(actionButton)
	if Opt.glow.blizzard then
		return
	end
	local alert = actionButton.SpellActivationAlert
	if not alert then
		return
	end
	if alert.ProcStartAnim:IsPlaying() then
		alert.ProcStartAnim:Stop()
	end
	alert:Hide()
end
hooksecurefunc('ActionButton_ShowOverlayGlow', UI.DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

function UI:UpdateGlowColorAndScale()
	local w, h, glow
	local r, g, b = Opt.glow.color.r, Opt.glow.color.g, Opt.glow.color.b
	for i = 1, #self.glows do
		glow = self.glows[i]
		w, h = glow.button:GetSize()
		glow:SetSize(w * 1.4, h * 1.4)
		glow:SetPoint('TOPLEFT', glow.button, 'TOPLEFT', -w * 0.2 * Opt.scale.glow, h * 0.2 * Opt.scale.glow)
		glow:SetPoint('BOTTOMRIGHT', glow.button, 'BOTTOMRIGHT', w * 0.2 * Opt.scale.glow, -h * 0.2 * Opt.scale.glow)
		glow.ProcStartFlipbook:SetVertexColor(r, g, b)
		glow.ProcLoopFlipbook:SetVertexColor(r, g, b)
	end
end

function UI:DisableOverlayGlows()
	if LibStub and LibStub.GetLibrary and not Opt.glow.blizzard then
		local lib = LibStub:GetLibrary('LibButtonGlow-1.0', true)
		if lib then
			lib.ShowOverlayGlow = function(self)
				return
			end
		end
	end
end

function UI:CreateOverlayGlows()
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.ProcStartAnim:Play() -- will bug out if ProcLoop plays first
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
	self:UpdateGlowColorAndScale()
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
				glow:Show()
				if Opt.glow.animation then
					glow.ProcStartAnim:Play()
				else
					glow.ProcLoop:Play()
				end
			end
		elseif glow:IsVisible() then
			if glow.ProcStartAnim:IsPlaying() then
				glow.ProcStartAnim:Stop()
			end
			if glow.ProcLoop:IsPlaying() then
				glow.ProcLoop:Stop()
			end
			glow:Hide()
		end
	end
end

function UI:UpdateDraggable()
	local draggable = not (Opt.locked or Opt.snap or Opt.aoe)
	ghPanel:SetMovable(not Opt.snap)
	ghPreviousPanel:SetMovable(not Opt.snap)
	ghCooldownPanel:SetMovable(not Opt.snap)
	ghInterruptPanel:SetMovable(not Opt.snap)
	ghExtraPanel:SetMovable(not Opt.snap)
	if not Opt.snap then
		ghPanel:SetUserPlaced(true)
		ghPreviousPanel:SetUserPlaced(true)
		ghCooldownPanel:SetUserPlaced(true)
		ghInterruptPanel:SetUserPlaced(true)
		ghExtraPanel:SetUserPlaced(true)
	end
	ghPanel:EnableMouse(draggable or Opt.aoe)
	ghPanel.button:SetShown(Opt.aoe)
	ghPreviousPanel:EnableMouse(draggable)
	ghCooldownPanel:EnableMouse(draggable)
	ghInterruptPanel:EnableMouse(draggable)
	ghExtraPanel:EnableMouse(draggable)
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
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.MARKSMANSHIP] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
		[SPEC.SURVIVAL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 36 },
			['below'] = { 'TOP', 'BOTTOM', 0, -9 },
		},
	},
	kui = { -- Kui Nameplates
		[SPEC.BEASTMASTERY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, 7 },
		},
		[SPEC.MARKSMANSHIP] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, 7 },
		},
		[SPEC.SURVIVAL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 24 },
			['below'] = { 'TOP', 'BOTTOM', 0, 7 },
		},
	},
}

function UI.OnResourceFrameHide()
	if Opt.snap then
		ghPanel:ClearAllPoints()
	end
end

function UI.OnResourceFrameShow()
	if Opt.snap and UI.anchor.points then
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
	self:UpdateGlows()
end

function UI:Reset()
	ghPanel:ClearAllPoints()
	ghPanel:SetPoint('CENTER', 0, -169)
	self:SnapAllPanels()
end

function UI:UpdateDisplay()
	Timer.display = 0
	local border, dim, dim_cd, text_cd, text_center, text_tr
	local channel = Player.channel

	if Opt.dimmer then
		dim = not ((not Player.main) or
		           (Player.main.spellId and IsSpellUsable(Player.main.spellId)) or
		           (Player.main.itemId and IsItemUsable(Player.main.itemId)))
		dim_cd = not ((not Player.cd) or
		           (Player.cd.spellId and IsSpellUsable(Player.cd.spellId)) or
		           (Player.cd.itemId and IsItemUsable(Player.cd.itemId)))
	end
	if Player.main then
		if Player.main.requires_react then
			local react = Player.main:React()
			if react > 0 then
				text_center = format('%.1f', react)
			end
		end
		if Player.main_freecast then
			border = 'freecast'
		end
	end
	if Player.cd then
		if Player.cd.requires_react then
			local react = Player.cd:React()
			if react > 0 then
				text_cd = format('%.1f', react)
			end
		end
	end
	if Player.pool_focus then
		local deficit = Player.pool_focus - UnitPower('player', 2)
		if deficit > 0 then
			text_center = format('POOL %d', deficit)
			dim = Opt.dimmer
		end
	end
	if Player.wait_time then
		local deficit = Player.wait_time - GetTime()
		if deficit > 0 then
			text_center = format('WAIT\n%.1fs', deficit)
			dim = Opt.dimmer
		end
	end
	if channel.ability and not channel.ability.ignore_channel and channel.tick_count > 0 then
		dim = Opt.dimmer
		if channel.tick_count > 1 then
			local ctime = GetTime()
			channel.ticks = ((ctime - channel.start) / channel.tick_interval) - channel.ticks_extra
			channel.ticks_remain = (channel.ends - ctime) / channel.tick_interval
			text_center = format('TICKS\n%.1f', max(0, channel.ticks))
			if channel.ability == Player.main then
				if channel.ticks_remain < 1 or channel.early_chainable then
					dim = false
					text_center = '|cFF00FF00CHAIN'
				end
			elseif channel.interruptible then
				dim = false
			end
		end
	end
	if Player.major_cd_remains > 0 then
		text_tr = format('%.1fs', Player.major_cd_remains)
	end
	if border ~= ghPanel.border.overlay then
		ghPanel.border.overlay = border
		ghPanel.border:SetTexture(ADDON_PATH .. (border or 'border') .. '.blp')
	end

	ghPanel.dimmer:SetShown(dim)
	ghPanel.text.center:SetText(text_center)
	ghPanel.text.tr:SetText(text_tr)
	--ghPanel.text.bl:SetText(format('%.1fs', Target.timeToDie))
	ghCooldownPanel.text:SetText(text_cd)
	ghCooldownPanel.dimmer:SetShown(dim_cd)
end

function UI:UpdateCombat()
	Timer.combat = 0

	Player:Update()

	if Player.main then
		ghPanel.icon:SetTexture(Player.main.icon)
		Player.main_freecast = Player.main:Free()
	end
	if Player.cd then
		ghCooldownPanel.icon:SetTexture(Player.cd.icon)
		if Player.cd.spellId then
			local cooldown = GetSpellCooldown(Player.cd.spellId)
			ghCooldownPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
		end
	end
	if Player.extra then
		ghExtraPanel.icon:SetTexture(Player.extra.icon)
	end
	if Opt.interrupt then
		local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
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
	if Opt.frequency - Timer.combat > seconds then
		Timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

-- End UI Functions

-- Start Event Handling

function Events:ADDON_LOADED(name)
	if name == ADDON then
		Opt = GoodHunting
		local firstRun = not Opt.frequency
		InitOpts()
		UI:UpdateDraggable()
		UI:UpdateAlpha()
		UI:UpdateScale()
		if firstRun then
			log('It looks like this is your first time running ' .. ADDON .. ', why don\'t you take some time to familiarize yourself with the commands?')
			log('Type |cFFFFD000' .. SLASH_GoodHunting1 .. '|r for a list of commands.')
			UI:SnapAllPanels()
		end
		if UnitLevel('player') < 10 then
			log('[|cFFFFD000Warning|r]', ADDON, 'is not designed for players under level 10, and almost certainly will not operate properly!')
		end
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
	   e == 'SPELL_CAST_START' or
	   e == 'SPELL_CAST_SUCCESS' or
	   e == 'SPELL_CAST_FAILED' or
	   e == 'SPELL_DAMAGE' or
	   e == 'SPELL_ABSORBED' or
	   e == 'SPELL_ENERGIZE' or
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
	local uid = ToUID(dstGUID)
	if not uid or Target.Dummies[uid] then
		return
	end
	TrackedAuras:Remove(dstGUID)
	if Opt.auto_aoe then
		AutoAoe:Remove(dstGUID)
	end
	local pet = SummonedPets.byUnitId[uid]
	if pet then
		pet:RemoveUnit(dstGUID)
	end
end

CombatEvent.SWING_DAMAGE = function(event, srcGUID, dstGUID, amount, overkill, spellSchool, resisted, blocked, absorbed, critical, glancing, crushing, offHand)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand)
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	elseif srcGUID == Pet.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Pet.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SWING_MISSED = function(event, srcGUID, dstGUID, missType, offHand, amountMissed)
	if srcGUID == Player.guid then
		Player:ResetSwing(not offHand, offHand, true)
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Player.guid then
		Player.swing.last_taken = Player.time
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	elseif srcGUID == Pet.guid then
		if Opt.auto_aoe and not (missType == 'EVADE' or missType == 'IMMUNE') then
			AutoAoe:Add(dstGUID, true)
		end
	elseif dstGUID == Pet.guid then
		if Opt.auto_aoe then
			AutoAoe:Add(srcGUID, true)
		end
	end
end

CombatEvent.SPELL_SUMMON = function(event, srcGUID, dstGUID)
	if srcGUID ~= Player.guid then
		return
	end
	local uid = ToUID(dstGUID)
	if not uid then
		return
	end
	local pet = SummonedPets.byUnitId[uid]
	if pet then
		pet:AddUnit(dstGUID)
	end
end

--local UnknownSpell = {}

CombatEvent.SPELL = function(event, srcGUID, dstGUID, spellId, spellName, spellSchool, missType, overCap, powerType)
	if srcGUID == Pet.guid then
		if Pet.stuck and (event == 'SPELL_CAST_SUCCESS' or event == 'SPELL_DAMAGE' or event == 'SWING_DAMAGE') then
			Pet.stuck = false
		elseif not Pet.stuck and event == 'SPELL_CAST_FAILED' and missType == 'No path available' then
			Pet.stuck = true
		end
	elseif srcGUID ~= Player.guid then
		local uid = ToUID(srcGUID)
		if uid then
			local pet = SummonedPets.byUnitId[uid]
			if pet then
				local unit = pet.active_units[srcGUID]
				if unit then
					if event == 'SPELL_CAST_SUCCESS' and pet.CastSuccess then
						pet:CastSuccess(unit, spellId, dstGUID)
					elseif event == 'SPELL_CAST_START' and pet.CastStart then
						pet:CastStart(unit, spellId, dstGUID)
					elseif event == 'SPELL_CAST_FAILED' and pet.CastFailed then
						pet:CastFailed(unit, spellId, dstGUID, missType)
					elseif (event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH') and pet.CastLanded then
						pet:CastLanded(unit, spellId, dstGUID, event, missType)
					end
					--log(format('%.3f PET %d EVENT %s SPELL %s ID %d', Player.time, pet.unitId, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0))
				end
			end
		end
		return
	end

	local ability = spellId and Abilities.bySpellId[spellId]
	if not ability then
--[[
		if not UnknownSpell[event] then
			UnknownSpell[event] = {}
		end
		if not UnknownSpell[event][spellId] then
			UnknownSpell[event][spellId] = true
			log(format('%.3f EVENT %s TRACK CHECK FOR UNKNOWN %s ID %d FROM %s ON %s', Player.time, event, type(spellName) == 'string' and spellName or 'Unknown', spellId or 0, srcGUID, dstGUID))
		end
]]
		return
	end

	UI:UpdateCombatWithin(0.05)
	if event == 'SPELL_CAST_SUCCESS' then
		return ability:CastSuccess(dstGUID)
	elseif event == 'SPELL_CAST_START' then
		return ability.CastStart and ability:CastStart(dstGUID)
	elseif event == 'SPELL_CAST_FAILED'  then
		return ability.CastFailed and ability:CastFailed(dstGUID, missType)
	elseif event == 'SPELL_ENERGIZE' then
		return ability.Energize and ability:Energize(missType, overCap, powerType)
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
	if dstGUID == Player.guid or dstGUID == Pet.guid then
		if event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
			ability.last_gained = Player.time
		end
		return -- ignore buffs beyond here
	end
	if event == 'SPELL_DAMAGE' or event == 'SPELL_ABSORBED' or event == 'SPELL_MISSED' or event == 'SPELL_AURA_APPLIED' or event == 'SPELL_AURA_REFRESH' then
		ability:CastLanded(dstGUID, event, missType)
	end
end

function Events:COMBAT_LOG_EVENT_UNFILTERED()
	CombatEvent.TRIGGER(CombatLogGetCurrentEventInfo())
end

function Events:PLAYER_TARGET_CHANGED()
	Target:Update()
end

function Events:UNIT_FACTION(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_FLAGS(unitId)
	if unitId == 'target' then
		Target:Update()
	end
end

function Events:UNIT_HEALTH(unitId)
	if unitId == 'player' then
		Player.health.current = UnitHealth(unitId)
		Player.health.max = UnitHealthMax(unitId)
		Player.health.pct = Player.health.current / Player.health.max * 100
	elseif unitId == 'pet' then
		Pet.health.current = UnitHealth(unitId)
		Pet.health.max = UnitHealthMax(unitId)
		Pet.health.pct = Pet.health.current / Pet.health.max * 100
	end
end

function Events:UNIT_MAXPOWER(unitId)
	if unitId == 'player' then
		Player.level = UnitLevel(unitId)
		Player.focus.max = UnitPowerMax(unitId, 2)
	elseif unitId == 'pet' then
		Pet.focus.max = UnitPowerMax(unitId, 2)
	end
end

function Events:UNIT_SPELLCAST_START(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end

function Events:UNIT_SPELLCAST_STOP(unitId, castGUID, spellId)
	if Opt.interrupt and unitId == 'target' then
		UI:UpdateCombatWithin(0.05)
	end
end
Events.UNIT_SPELLCAST_FAILED = Events.UNIT_SPELLCAST_STOP
Events.UNIT_SPELLCAST_INTERRUPTED = Events.UNIT_SPELLCAST_STOP

function Events:UNIT_SPELLCAST_SENT(unitId, destName, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability == FeignDeath then
		FeignDeath:CastSuccess(Player.guid)
	end
end

function Events:UNIT_SPELLCAST_SUCCEEDED(unitId, castGUID, spellId)
	if unitId ~= 'player' or not spellId or castGUID:sub(6, 6) ~= '3' then
		return
	end
	local ability = Abilities.bySpellId[spellId]
	if not ability then
		return
	end
	if ability.traveling then
		ability.next_castGUID = castGUID
	end
end

function Events:UNIT_SPELLCAST_CHANNEL_UPDATE(unitId, castGUID, spellId)
	if unitId == 'player' then
		Player:UpdateChannelInfo()
	end
end
Events.UNIT_SPELLCAST_CHANNEL_START = Events.UNIT_SPELLCAST_CHANNEL_UPDATE
Events.UNIT_SPELLCAST_CHANNEL_STOP = Events.UNIT_SPELLCAST_CHANNEL_UPDATE

function Events:UNIT_PET(unitId)
	if unitId ~= 'player' then
		return
	end
	Pet:UpdateKnown()
	Pet:Update()
end

function Events:PLAYER_REGEN_DISABLED()
	Player:UpdateTime()
	Player.combat_start = Player.time
end

function Events:PLAYER_REGEN_ENABLED()
	Player:UpdateTime()
	Player.combat_start = 0
	Player.swing.last_taken = 0
	Pet.stuck = false
	Target.estimated_range = 30
	wipe(Player.previous_gcd)
	if Player.last_ability then
		Player.last_ability = nil
		ghPreviousPanel:Hide()
	end
	for _, ability in next, Abilities.velocity do
		for guid in next, ability.traveling do
			ability.traveling[guid] = nil
		end
	end
	if Opt.auto_aoe then
		AutoAoe:Clear()
	end
	if APL[Player.spec].precombat_variables then
		APL[Player.spec]:precombat_variables()
	end
end

function Events:PLAYER_EQUIPMENT_CHANGED()
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

	Player.set_bonus.t33 = (Player:Equipped(212018) and 1 or 0) + (Player:Equipped(212019) and 1 or 0) + (Player:Equipped(212020) and 1 or 0) + (Player:Equipped(212021) and 1 or 0) + (Player:Equipped(212023) and 1 or 0)

	Player:ResetSwing(true, true)
	Player:UpdateKnown()
end

function Events:PLAYER_SPECIALIZATION_CHANGED(unitId)
	if unitId ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	ghPreviousPanel.ability = nil
	Player:SetTargetMode(1)
	Events:PLAYER_EQUIPMENT_CHANGED()
	Events:PLAYER_REGEN_ENABLED()
	Events:UNIT_HEALTH('player')
	Events:UNIT_MAXPOWER('player')
	UI.OnResourceFrameShow()
	Target:Update()
	Player:Update()
end


function Events:TRAIT_CONFIG_UPDATED()
	Events:PLAYER_SPECIALIZATION_CHANGED('player')
end

function Events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local _, cooldown, castStart, castEnd
		_, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			cooldown = {
				startTime = castStart / 1000,
				duration = (castEnd - castStart) / 1000
			}
		else
			cooldown = GetSpellCooldown(61304)
		end
		ghPanel.swipe:SetCooldown(cooldown.startTime, cooldown.duration)
	end
end

function Events:PLAYER_PVP_TALENT_UPDATE()
	Player:UpdateKnown()
end

function Events:ACTIONBAR_SLOT_CHANGED()
	UI:UpdateGlows()
end

function Events:GROUP_ROSTER_UPDATE()
	Player.group_size = clamp(GetNumGroupMembers(), 1, 40)
end

function Events:PLAYER_ENTERING_WORLD()
	Player:Init()
	Target:Update()
	C_Timer.After(5, function() Events:PLAYER_EQUIPMENT_CHANGED() end)
end

function Events:UI_ERROR_MESSAGE(errorId)
	if (
	    errorId == 394 or -- pet is rooted
	    errorId == 396 or -- target out of pet range
	    errorId == 400    -- no pet path to target
	) then
		Pet.stuck = true
	end
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
	Timer.combat = Timer.combat + elapsed
	Timer.display = Timer.display + elapsed
	Timer.health = Timer.health + elapsed
	if Timer.combat >= Opt.frequency then
		UI:UpdateCombat()
	end
	if Timer.display >= 0.05 then
		UI:UpdateDisplay()
	end
	if Timer.health >= 0.2 then
		Target:UpdateHealth()
	end
end)

ghPanel:SetScript('OnEvent', function(self, event, ...) Events[event](self, ...) end)
for event in next, Events do
	ghPanel:RegisterEvent(event)
end

-- End Event Handling

-- Start Slash Commands

-- this fancy hack allows you to click BattleTag links to add them as a friend!
local SetHyperlink = ItemRefTooltip.SetHyperlink
ItemRefTooltip.SetHyperlink = function(self, link)
	local linkType, linkData = link:match('(.-):(.*)')
	if linkType == 'BNadd' then
		BattleTagInviteFrame_Show(linkData)
		return
	end
	SetHyperlink(self, link)
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
	log(desc .. ':', opt_view, ...)
end

SlashCmdList[ADDON] = function(msg, editbox)
	msg = { strsplit(' ', msg:lower()) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UI:UpdateDraggable()
		end
		if Opt.aoe or Opt.snap then
			Status('Warning', 'Panels cannot be moved when aoe or snap are enabled!')
		end
		return Status('Locked', Opt.locked)
	end
	if startsWith(msg[1], 'snap') then
		if msg[2] then
			if msg[2] == 'above' or msg[2] == 'over' then
				Opt.snap = 'above'
				Opt.locked = true
			elseif msg[2] == 'below' or msg[2] == 'under' then
				Opt.snap = 'below'
				Opt.locked = true
			else
				Opt.snap = false
				Opt.locked = false
				UI:Reset()
			end
			UI:UpdateDraggable()
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
			Opt.alpha = clamp(tonumber(msg[2]) or 100, 0, 100) / 100
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
		if startsWith(msg[2], 'anim') then
			if msg[3] then
				Opt.glow.animation = msg[3] == 'on'
				UI:UpdateGlows()
			end
			return Status('Use extended animation (shrinking circle)', Opt.glow.animation)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = clamp(tonumber(msg[3]) or 0, 0, 1)
				Opt.glow.color.g = clamp(tonumber(msg[4]) or 0, 0, 1)
				Opt.glow.color.b = clamp(tonumber(msg[5]) or 0, 0, 1)
				UI:UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, |cFFFFD000animation|r, and |cFFFFD000color')
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
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Beast Mastery specialization', not Opt.hide.beastmastery)
			end
			if startsWith(msg[2], 'm') then
				Opt.hide.marksmanship = not Opt.hide.marksmanship
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Marksmanship specialization', not Opt.hide.marksmanship)
			end
			if startsWith(msg[2], 's') then
				Opt.hide.survival = not Opt.hide.survival
				Events:PLAYER_SPECIALIZATION_CHANGED('player')
				return Status('Survival specialization', not Opt.hide.survival)
			end
		end
		return Status('Possible hidespec options', '|cFFFFD000beastmastery|r/|cFFFFD000marksmanship|r/|cFFFFD000survival|r')
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
	if startsWith(msg[1], 'he') then
		if msg[2] then
			Opt.heal = clamp(tonumber(msg[2]) or 60, 0, 100)
		end
		return Status('Health percentage threshold to recommend self healing spells', Opt.heal .. '%')
	end
	if startsWith(msg[1], 'mend') then
		if msg[2] then
			Opt.mend_threshold = tonumber(msg[2]) or 65
		end
		return Status('Recommend Mend Pet when pet\'s health is below', Opt.mend_threshold .. '%')
	end
	if msg[1] == 'reset' then
		UI:Reset()
		return Status('Position has been reset to', 'default')
	end
	print(ADDON, '(version: |cFFFFD000' .. C_AddOns.GetAddOnMetadata(ADDON, 'Version') .. '|r) - Commands:')
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the ' .. ADDON .. ' UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the ' .. ADDON .. ' UI to the Personal Resource Display',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the ' .. ADDON .. ' UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the ' .. ADDON .. ' UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.2 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r/|cFFFFD000animation|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the ' .. ADDON .. ' UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use ' .. ADDON .. ' for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough resources to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000beastmastery|r/|cFFFFD000marksmanship|r/|cFFFFD000survival|r - toggle disabling ' .. ADDON .. ' for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'ttd |cFFFFD000[seconds]|r  - minimum enemy lifetime to use cooldowns on (default is 8 seconds, ignored on bosses)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show flasks and battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'heal |cFFFFD000[percent]|r - health percentage threshold to recommend self healing spells (default is 60%, 0 to disable)',
		'mend |cFFFFD000[percent]|r  - health percentage to recommend Mend Pet at (default is 65%, 0 to disable)',
		'|cFFFFD000reset|r - reset the location of the ' .. ADDON .. ' UI to default',
	} do
		print('  ' .. SLASH_GoodHunting1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end

-- End Slash Commands
