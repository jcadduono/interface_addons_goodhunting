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

local function InitializeOpts()
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

-- specialization constants
local SPEC = {
	NONE = 0,
	BEASTMASTERY = 1,
	MARKSMANSHIP = 2,
	SURVIVAL = 3,
}

local events, glows = {}, {}

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
	spec = 0,
	gcd = 1.5,
	health = 0,
	health_max = 0,
	focus = 0,
	focus_regen = 0,
	focus_max = 100,
	previous_gcd = {},-- list of previous GCD abilities
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
ghPanel.text.br = ghPanel.text:CreateFontString(nil, 'OVERLAY')
ghPanel.text.br:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
ghPanel.text.br:SetPoint('BOTTOMRIGHT', ghPanel, 'BOTTOMRIGHT', -1.5, 3)
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

-- Start Auto AoE

local targetModes = {
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

local function SetTargetMode(mode)
	if mode == targetMode then
		return
	end
	targetMode = min(mode, #targetModes[Player.spec])
	Player.enemies = targetModes[Player.spec][targetMode][1]
	ghPanel.text.br:SetText(targetModes[Player.spec][targetMode][2])
end
GoodHunting_SetTargetMode = SetTargetMode

local function ToggleTargetMode()
	local mode = targetMode + 1
	SetTargetMode(mode > #targetModes[Player.spec] and 1 or mode)
end
GoodHunting_ToggleTargetMode = ToggleTargetMode

local function ToggleTargetModeReverse()
	local mode = targetMode - 1
	SetTargetMode(mode < 1 and #targetModes[Player.spec] or mode)
end
GoodHunting_ToggleTargetModeReverse = ToggleTargetModeReverse

local autoAoe = {
	targets = {},
	blacklist = {},
	ignored_units = {
		[120651] = true, -- Explosives (Mythic+ affix)
	},
}

function autoAoe:add(guid, update)
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
		self:update()
	end
end

function autoAoe:remove(guid)
	-- blacklist enemies for 2 seconds when they die to prevent out of order events from re-adding them
	self.blacklist[guid] = Player.time + 2
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:clear()
	local guid
	for guid in next, self.targets do
		self.targets[guid] = nil
	end
end

function autoAoe:update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		SetTargetMode(1)
		return
	end
	Player.enemies = count
	for i = #targetModes[Player.spec], 1, -1 do
		if count >= targetModes[Player.spec][i][1] then
			SetTargetMode(i)
			Player.enemies = count
			return
		end
	end
end

function autoAoe:purge()
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
		self:update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability = {}
Ability.__index = Ability
local abilities = {
	all = {}
}

function Ability.add(spellId, buff, player, spellId2)
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
	setmetatable(ability, Ability)
	abilities.all[#abilities.all + 1] = ability
	return ability
end

function Ability:match(spell)
	if type(spell) == 'number' then
		return spell == self.spellId or (self.spellId2 and spell == self.spellId2)
	elseif type(spell) == 'string' then
		return spell:lower() == self.name:lower()
	elseif type(spell) == 'table' then
		return spell == self
	end
	return false
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable()
	if not self.known then
		return false
	end
	if self:cost() > Player.focus then
		return false
	end
	if self.requires_pet and not Player.pet_active then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	return self:ready()
end

function Ability:remains()
	if self:casting() or self:traveling() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - Player.ctime - Player.execute_remains, 0)
		end
	end
	return 0
end

function Ability:refreshable()
	if self.buff_duration > 0 then
		return self:remains() < self:duration() * 0.3
	end
	return self:down()
end

function Ability:up()
	return self:remains() > 0
end

function Ability:down()
	return not self:up()
end

function Ability:setVelocity(velocity)
	if velocity > 0 then
		self.velocity = velocity
		self.travel_start = {}
	else
		self.travel_start = nil
		self.velocity = 0
	end
end

function Ability:traveling()
	if self.travel_start and self.travel_start[Target.guid] then
		if Player.time - self.travel_start[Target.guid] < self.max_range / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:travelTime()
	return Target.estimated_range / self.velocity
end

function Ability:ticking()
	if self.aura_targets then
		local count, guid, aura = 0
		for guid, aura in next, self.aura_targets do
			if aura.expires - Player.time > Player.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:up() and 1 or 0
end

function Ability:tickTime()
	return self.hasted_ticks and (Player.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (Player.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	if self.cooldown_duration > 0 and self:casting() then
		return self.cooldown_duration
	end
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (Player.ctime - start) - Player.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if self:match(id) then
			return (expires == 0 or expires - Player.ctime > Player.execute_remains) and count or 0
		end
	end
	return 0
end

function Ability:cost()
	return self.focus_cost
end

function Ability:charges()
	return (GetSpellCharges(self.spellId)) or 0
end

function Ability:chargesFractional()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return charges
	end
	return charges + ((max(0, Player.ctime - recharge_start + Player.execute_remains)) / recharge_time)
end

function Ability:fullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (Player.ctime - recharge_start) - Player.execute_remains)
end

function Ability:maxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:duration()
	return self.hasted_duration and (Player.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:casting()
	return Player.ability_casting == self
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and Player.gcd or 0
	end
	return castTime / 1000
end

function Ability:castRegen()
	return Player.focus_regen * self:castTime() - self:cost()
end

function Ability:wontCapFocus(reduction)
	return (Player.focus + self:castRegen()) < (Player.focus_max - (reduction or 5))
end

function Ability:previous(n)
	local i = n or 1
	if Player.ability_casting then
		if i == 1 then
			return Player.ability_casting == self
		end
		i = i - 1
	end
	return Player.previous_gcd[i] == self
end

function Ability:azeriteRank()
	return Azerite.traits[self.spellId] or 0
end

function Ability:autoAoe(removeUnaffected, trigger)
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

function Ability:recordTargetHit(guid)
	self.auto_aoe.targets[guid] = Player.time
	if not self.auto_aoe.start_time then
		self.auto_aoe.start_time = self.auto_aoe.targets[guid]
	end
end

function Ability:updateTargetsHit()
	if self.auto_aoe.start_time and Player.time - self.auto_aoe.start_time >= 0.3 then
		self.auto_aoe.start_time = nil
		if self.auto_aoe.remove then
			autoAoe:clear()
		end
		local guid
		for guid in next, self.auto_aoe.targets do
			autoAoe:add(guid)
			self.auto_aoe.targets[guid] = nil
		end
		autoAoe:update()
	end
end

-- start DoT tracking

local trackAuras = {}

function trackAuras:purge()
	local _, ability, guid, expires
	for _, ability in next, abilities.trackAuras do
		for guid, aura in next, ability.aura_targets do
			if aura.expires <= Player.time then
				ability:removeAura(guid)
			end
		end
	end
end

function trackAuras:remove(guid)
	local _, ability
	for _, ability in next, abilities.trackAuras do
		ability:removeAura(guid)
	end
end

function Ability:trackAuras()
	self.aura_targets = {}
end

function Ability:applyAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = {
		expires = Player.time + self:duration()
	}
	self.aura_targets[guid] = aura
end

function Ability:refreshAura(guid)
	if autoAoe.blacklist[guid] then
		return
	end
	local aura = self.aura_targets[guid]
	if not aura then
		self:applyAura(guid)
		return
	end
	local duration = self:duration()
	aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
end

function Ability:refreshAuraAll()
	local guid, aura, remains
	local duration = self:duration()
	for guid, aura in next, self.aura_targets do
		aura.expires = Player.time + min(duration * 1.3, (aura.expires - Player.time) + duration)
	end
end

function Ability:removeAura(guid)
	if self.aura_targets[guid] then
		self.aura_targets[guid] = nil
	end
end

-- end DoT tracking

-- Hunter Abilities
---- Multiple Specializations
local CallPet = Ability.add(883, false, true)
local CounterShot = Ability.add(147362, false, true)
CounterShot.cooldown_duration = 24
CounterShot.triggers_gcd = false
local MendPet = Ability.add(136, true, true)
MendPet.cooldown_duration = 10
MendPet.buff_duration = 10
MendPet.requires_pet = true
MendPet.auraTarget = 'pet'
local RevivePet = Ability.add(982, false, true)
RevivePet.focus_cost = 10
------ Procs

------ Talents
local AMurderOfCrows = Ability.add(131894, false, true, 131900)
AMurderOfCrows.cooldown_duration = 60
AMurderOfCrows.buff_duration = 15
AMurderOfCrows.focus_cost = 30
AMurderOfCrows.tick_interval = 1
AMurderOfCrows.hasted_ticks = true
---- Beast Mastery
local AspectOfTheWild = Ability.add(193530, true, true)
AspectOfTheWild.cooldown_duration = 120
AspectOfTheWild.buff_duration = 20
local BarbedShot = Ability.add(217200, false, true)
BarbedShot.cooldown_duration = 12
BarbedShot.buff_duration = 8
BarbedShot.tick_interval = 2
BarbedShot.hasted_cooldown = true
BarbedShot.requires_charge = true
BarbedShot:setVelocity(50)
BarbedShot.buff = Ability.add(246152, true, true)
BarbedShot.buff.buff_duration = 8
local BeastCleave = Ability.add(268877, true, true)
BeastCleave.buff_duration = 4
BeastCleave.pet = Ability.add(118455, false, true, 118459)
BeastCleave.pet:autoAoe()
local BestialWrath = Ability.add(19574, true, true)
BestialWrath.cooldown_duration = 90
BestialWrath.buff_duration = 15
BestialWrath.pet = Ability.add(186254, true, true)
BestialWrath.pet.auraTarget = 'pet'
BestialWrath.pet.buff_duration = 15
local CobraShot = Ability.add(193455, false, true)
CobraShot.focus_cost = 35
CobraShot:setVelocity(45)
local KillCommandBM = Ability.add(34026, false, true, 83381)
KillCommandBM.focus_cost = 30
KillCommandBM.cooldown_duration = 7.5
KillCommandBM.hasted_cooldown = true
KillCommandBM.requires_pet = true
local MultiShotBM = Ability.add(2643, false, true)
MultiShotBM.focus_cost = 40
MultiShotBM:setVelocity(50)
MultiShotBM:autoAoe(true)
local PetFrenzy = Ability.add(272790, true, true)
PetFrenzy.auraTarget = 'pet'
PetFrenzy.buff_duration = 8
------ Talents
local Barrage = Ability.add(120360, false, true, 120361)
Barrage.cooldown_duration = 20
Barrage.focus_cost = 60
Barrage:autoAoe(true)
local ChimaeraShot = Ability.add(53209, false, true)
ChimaeraShot.cooldown_duration = 15
ChimaeraShot.hasted_cooldown = true
ChimaeraShot:setVelocity(40)
local DireBeast = Ability.add(120679, true, true, 281036)
DireBeast.cooldown_duration = 20
DireBeast.buff_duration = 8
local KillerInstinct = Ability.add(273887, false, true)
local OneWithThePack = Ability.add(199528, false, true)
local Stampede = Ability.add(201430, false, true, 201594)
Stampede.cooldown_duration = 180
Stampede.buff_duration = 12
Stampede:autoAoe()
local SpittingCobra = Ability.add(194407, true, true)
SpittingCobra.cooldown_duration = 90
SpittingCobra.buff_duration = 20
local Stomp = Ability.add(199530, false, true, 201754)
Stomp:autoAoe(true)
------ Procs

---- Marksmanship

------ Talents

------ Procs

---- Survival
local Carve = Ability.add(187708, false, true)
Carve.focus_cost = 35
Carve:autoAoe(true)
local CoordinatedAssault = Ability.add(266779, true, true)
CoordinatedAssault.cooldown_duration = 120
CoordinatedAssault.buff_duration = 20
CoordinatedAssault.requires_pet = true
local Harpoon = Ability.add(190925, false, true, 190927)
Harpoon.cooldown_duration = 20
Harpoon.buff_duration = 3
Harpoon.triggers_gcd = false
Harpoon:setVelocity(70)
local Intimidation = Ability.add(19577, false, true)
Intimidation.cooldown_duration = 60
Intimidation.buff_duration = 5
Intimidation.requires_pet = true
local KillCommand = Ability.add(259489, false, true)
KillCommand.focus_cost = -15
KillCommand.cooldown_duration = 6
KillCommand.hasted_cooldown = true
KillCommand.requires_charge = true
KillCommand.requires_pet = true
local Muzzle = Ability.add(187707, false, true)
Muzzle.cooldown_duration = 15
Muzzle.triggers_gcd = false
local RaptorStrike = Ability.add(186270, false, true)
RaptorStrike.focus_cost = 30
local SerpentSting = Ability.add(259491, false, true)
SerpentSting.focus_cost = 20
SerpentSting.buff_duration = 12
SerpentSting.tick_interval = 3
SerpentSting.hasted_ticks = true
SerpentSting.hasted_duration = true
SerpentSting:setVelocity(60)
SerpentSting:trackAuras()
local WildfireBomb = Ability.add(259495, false, true, 269747)
WildfireBomb.cooldown_duration = 18
WildfireBomb.buff_duration = 6
WildfireBomb.tick_interval = 1
WildfireBomb.hasted_cooldown = true
WildfireBomb.requires_charge = true
WildfireBomb:setVelocity(35)
WildfireBomb:autoAoe(true)
------ Talents
local AlphaPredator = Ability.add(269737, false, true)
local BirdsOfPrey = Ability.add(260331, false, true)
local Bloodseeker = Ability.add(260248, false, true, 259277)
Bloodseeker.buff_duration = 8
Bloodseeker.tick_interval = 2
Bloodseeker.hasted_ticks = true
Bloodseeker:trackAuras()
local Butchery = Ability.add(212436, false, true)
Butchery.focus_cost = 30
Butchery.cooldown_duration = 9
Butchery.hasted_cooldown = true
Butchery.requires_charge = true
Butchery:autoAoe(true)
local Chakrams = Ability.add(259391, false, true, 259398)
Chakrams.focus_cost = 30
Chakrams.cooldown_duration = 20
Chakrams:setVelocity(30)
local FlankingStrike = Ability.add(269751, false, true)
FlankingStrike.focus_cost = -30
FlankingStrike.cooldown_duration = 40
FlankingStrike.requires_pet = true
local GuerrillaTactics = Ability.add(264332, false, true)
local HydrasBite = Ability.add(260241, false, true)
local InternalBleeding = Ability.add(270343, false, true) -- Shrapnel Bomb DoT applied by Raptor Strike/Mongoose Bite/Carve
local MongooseBite = Ability.add(259387, false, true)
MongooseBite.focus_cost = 30
local MongooseFury = Ability.add(259388, true, true)
MongooseFury.buff_duration = 14
local PheromoneBomb = Ability.add(270323, false, true, 270332) -- Provided by Wildfire Infusion, replaces Wildfire Bomb
PheromoneBomb.cooldown_duration = 18
PheromoneBomb.buff_duration = 6
PheromoneBomb.tick_interval = 1
PheromoneBomb.hasted_cooldown = true
PheromoneBomb.requires_charge = true
PheromoneBomb:setVelocity(35)
PheromoneBomb:autoAoe(true)
local Predator = Ability.add(260249, true, true) -- Bloodseeker buff
local ShrapnelBomb = Ability.add(270335, false, true, 270339) -- Provided by Wildfire Infusion, replaces Wildfire Bomb
ShrapnelBomb.cooldown_duration = 18
ShrapnelBomb.buff_duration = 6
ShrapnelBomb.tick_interval = 1
ShrapnelBomb.hasted_cooldown = true
ShrapnelBomb.requires_charge = true
ShrapnelBomb:setVelocity(35)
ShrapnelBomb:autoAoe()
ShrapnelBomb:trackAuras(true)
local SteelTrap = Ability.add(162488, false, true, 162487)
SteelTrap.cooldown_duration = 30
SteelTrap.buff_duration = 20
SteelTrap.tick_interval = 2
SteelTrap.hasted_ticks = true
local TermsOfEngagement = Ability.add(265895, true, true, 265898)
TermsOfEngagement.buff_duration = 10
local TipOfTheSpear = Ability.add(260285, true, true, 260286)
TipOfTheSpear.buff_duration = 10
local VipersVenom = Ability.add(268501, true, true, 268552)
VipersVenom.buff_duration = 8
local VolatileBomb = Ability.add(271045, false, true, 271049) -- Provided by Wildfire Infusion, replaces Wildfire Bomb
VolatileBomb.cooldown_duration = 18
VolatileBomb.buff_duration = 6
VolatileBomb.tick_interval = 1
VolatileBomb.hasted_cooldown = true
VolatileBomb.requires_charge = true
VolatileBomb:setVelocity(35)
VolatileBomb:autoAoe(true)
local WildfireInfusion = Ability.add(271014, false, true)
------ Procs

-- Azerite Traits
local BlurOfTalons = Ability.add(277653, true, true, 277969)
BlurOfTalons.buff_duration = 6
local DanceOfDeath = Ability.add(274441, true, true, 274443)
DanceOfDeath.buff_duration = 8
local LatentPoison = Ability.add(273283, true, true, 273284)
LatentPoison.buff_duration = 10
local PrimalInstincts = Ability.add(279806, true, true, 279810)
PrimalInstincts.buff_duration = 20
local RapidReload = Ability.add(278530, true, true)
local VenomousFangs = Ability.add(274590, false, true)
local WildernessSurvival = Ability.add(278532, false, true)
-- Racials
local ArcaneTorrent = Ability.add(80483, true, false) -- Blood Elf
ArcaneTorrent.focus_cost = -15
-- Trinket Effects

-- End Abilities

-- Start Inventory Items

local InventoryItem, inventoryItems = {}, {}
InventoryItem.__index = InventoryItem

function InventoryItem.add(itemId)
	local name, _, _, _, _, _, _, _, _, icon = GetItemInfo(itemId)
	local item = {
		itemId = itemId,
		name = name,
		icon = icon,
		can_use = false,
	}
	setmetatable(item, InventoryItem)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or Player.previous_gcd[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or Player.previous_gcd[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration
	if self.equip_slot then
		startTime, duration = GetInventoryItemCooldown('player', self.equip_slot)
	else
		startTime, duration = GetItemCooldown(self.itemId)
	end
	return startTime == 0 and 0 or duration - (Player.ctime - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:equipped()
	return self.equip_slot and true
end

function InventoryItem:usable(seconds)
	if not self.can_use then
		return false
	end
	if not self:equipped() and self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

-- Inventory Items
local FlaskOfTheCurrents = InventoryItem.add(152638)
FlaskOfTheCurrents.buff = Ability.add(251836, true, true)
local BattlePotionOfAgility = InventoryItem.add(163223)
BattlePotionOfAgility.buff = Ability.add(279152, true, true)
BattlePotionOfAgility.buff.triggers_gcd = false
-- Equipment
local Trinket1 = InventoryItem.add(0)
local Trinket2 = InventoryItem.add(0)
-- End Inventory Items

-- Start Azerite Trait API

Azerite.equip_slots = { 1, 3, 5 } -- Head, Shoulder, Chest

function Azerite:initialize()
	self.locations = {}
	self.traits = {}
	local i
	for i = 1, #self.equip_slots do
		self.locations[i] = ItemLocation:CreateFromEquipmentSlot(self.equip_slots[i])
	end
end

function Azerite:update()
	local _, loc, tinfo, tslot, pid, pinfo
	for pid in next, self.traits do
		self.traits[pid] = nil
	end
	for _, loc in next, self.locations do
		if GetInventoryItemID('player', loc:GetEquipmentSlot()) and C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(loc) then
			tinfo = C_AzeriteEmpoweredItem.GetAllTierInfo(loc)
			for _, tslot in next, tinfo do
				if tslot.azeritePowerIDs then
					for _, pid in next, tslot.azeritePowerIDs do
						if C_AzeriteEmpoweredItem.IsPowerSelected(loc, pid) then
							self.traits[pid] = 1 + (self.traits[pid] or 0)
							pinfo = C_AzeriteEmpoweredItem.GetPowerInfo(pid)
							if pinfo and pinfo.spellID then
								self.traits[pinfo.spellID] = self.traits[pid]
							end
						end
					end
				end
			end
		end
	end
end

-- End Azerite Trait API

-- Start Helpful Functions

local function Health()
	return Player.health
end

local function HealthMax()
	return Player.health_max
end

local function HealthPct()
	return Player.health / Player.health_max * 100
end

local function Focus()
	return Player.focus
end

local function FocusDeficit()
	return Player.focus_max - Player.focus
end

local function FocusRegen()
	return Player.focus_regen
end

local function FocusMax()
	return Player.focus_max
end

local function FocusTimeToMax()
	local deficit = Player.focus_max - Player.focus
	if deficit <= 0 then
		return 0
	end
	return deficit / Player.focus_regen
end

local function TimeInCombat()
	if Player.combat_start > 0 then
		return Player.time - Player.combat_start
	end
	return 0
end

local function BloodlustActive()
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

local function InArenaOrBattleground()
	return Player.instance == 'arena' or Player.instance == 'pvp'
end

-- End Helpful Functions

-- Start Ability Modifications

function SerpentSting:remains()
	if VolatileBomb.known and VolatileBomb:traveling() and Ability.up(self) then
		return self:duration()
	end
	return Ability.remains(self)
end

function SerpentSting:cost()
	if VipersVenom:up() then
		return 0
	end
	return Ability.cost(self)
end

-- hack to support Wildfire Bomb's changing spells on each cast
function WildfireInfusion:update()
	local _, _, _, _, _, _, spellId = GetSpellInfo(WildfireBomb.name)
	if self.current then
		if self.current:match(spellId) then
			return -- not a bomb change
		end
		self.current.next = false
	end
	if ShrapnelBomb:match(spellId) then
		self.current = ShrapnelBomb
	elseif PheromoneBomb:match(spellId) then
		self.current = PheromoneBomb
	elseif VolatileBomb:match(spellId) then
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

function CallPet:usable()
	if Player.pet_active then
		return false
	end
	return Ability.usable(self)
end

function MendPet:usable()
	if not Ability.usable(self) then
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

function RevivePet:usable()
	if not UnitExists('pet') or (UnitExists('pet') and not UnitIsDead('pet')) then
		return false
	end
	return Ability.usable(self)
end

function PetFrenzy:start_duration_stack()
	local _, i, id, duration, expires, stack
	for i = 1, 40 do
		_, _, stack, _, duration, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0, 0, 0
		end
		if self:match(id) then
			return expires - duration, duration, stack
		end
	end
	return 0, 0, 0
end

-- End Ability Modifications

local function UseCooldown(ability, overwrite, always)
	if always or (Opt.cooldown and (not Opt.boss_only or Target.boss) and (not Player.cd or overwrite)) then
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
	[SPEC.SURVIVAL] = {}
}

APL[SPEC.BEASTMASTERY].main = function(self)
	if CallPet:usable() then
		UseExtra(CallPet)
	elseif RevivePet:usable() then
		UseExtra(RevivePet)
	elseif MendPet:usable() then
		UseExtra(MendPet)
	end
	if TimeInCombat() == 0 then
--[[
actions.precombat=flask
actions.precombat+=/summon_pet
actions.precombat+=/potion
# Adjusts the duration and cooldown of Aspect of the Wild and Primal Instincts by the duration of an unhasted GCD when they're used precombat. As AotW has a 1.3s GCD and affects itself this is 1.1s.
actions.precombat+=/aspect_of_the_wild,precast_time=1.1,if=!azerite.primal_instincts.enabled
# Adjusts the duration and cooldown of Bestial Wrath and Haze of Rage by the duration of an unhasted GCD when they're used precombat.
actions.precombat+=/bestial_wrath,precast_time=1.5,if=azerite.primal_instincts.enabled
]]
		if Opt.pot and not InArenaOrBattleground() then
			if FlaskOfTheCurrents:usable() and FlaskOfTheCurrents.buff:remains() < 300 then
				UseCooldown(FlaskOfTheUndertow)
			end
			if BattlePotionOfAgility:usable() then
				UseCooldown(BattlePotionOfAgility)
			end
		end
		if PrimalInstincts.known then
			if BestialWrath:usable() then
				UseCooldown(BestialWrath)
			end
		else
			if AspectOfTheWild:usable() then
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
	self:cds()
	if PetFrenzy:stack() >= 2 and PetFrenzy:remains() < (Player.gcd + 0.3) and BarbedShot:ready(PetFrenzy:remains()) then
		return WaitFor(BarbedShot, PetFrenzy:remains() - 0.5)
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
	if Opt.pot and BattlePotionOfAgility:usable() and (BestialWrath:up() and AspectOfTheWild:up() and (Target.healthPercentage < 35 or not KillerInstinct.known) or Target.timeToDie < 25) then
		UseCooldown(BattlePotionOfAgility)
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
actions.st+=/barrage
actions.st+=/cobra_shot,if=(focus-cost+focus.regen*(cooldown.kill_command.remains-1)>action.kill_command.cost|cooldown.kill_command.remains>1+gcd)&cooldown.kill_command.remains>1
actions.st+=/spitting_cobra
actions.st+=/barbed_shot,if=charges_fractional>1.4
]]
	if BarbedShot:usable() and ((PetFrenzy:up() and PetFrenzy:remains() <= (Player.gcd + 0.3)) or (BarbedShot:fullRechargeTime() < Player.gcd and not BestialWrath:ready()) or (PrimalInstincts.known and AspectOfTheWild:ready(Player.gcd))) then
		return BarbedShot
	end
	if AspectOfTheWild:usable() then
		UseCooldown(AspectOfTheWild)
	end
	if AMurderOfCrows:usable() then
		UseCooldown(AMurderOfCrows)
	end
	if Stampede:usable() and (AspectOfTheWild:up() and BestialWrath:up() or Target.timeToDie < 15) then
		UseCooldown(Stampede)
	end
	if BestialWrath:usable() and (AspectOfTheWild:cooldown() > 20 or Target.timeToDie < 15) then
		UseCooldown(BestialWrath)
	end
	if KillCommandBM:usable() then
		return KillCommandBM
	end
	if ChimaeraShot:usable() then
		return ChimaeraShot
	end
	if DireBeast:usable() then
		return DireBeast
	end
	if BarbedShot:usable() and ((PetFrenzy:down() and (BarbedShot:chargesFractional() > 1.8 or BestialWrath:up())) or (PrimalInstincts.known and AspectOfTheWild:ready(PetFrenzy:duration() - Player.gcd)) or (DanceOfDeath:azeriteRank() > 1 and DanceOfDeath:down() and GetCritChance() > 40) or Target.timeToDie < 9) then
		return BarbedShot
	end
	if Barrage:usable() then
		return Barrage
	end
	if CobraShot:usable() and KillCommandBM:cooldown() > 1 and (((Focus() - CobraShot:cost() + FocusRegen() * (KillCommandBM:cooldown() - 1)) > KillCommandBM:cost()) or KillCommandBM:cooldown() > (1 + Player.gcd)) then
		return CobraShot
	end
	if SpittingCobra:usable() then
		UseCooldown(SpittingCobra)
	end
	if BarbedShot:usable() and BarbedShot:chargesFractional() > 1.4 then
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
actions.cleave+=/multishot,if=azerite.rapid_reload.enabled&active_enemies>2
actions.cleave+=/cobra_shot,if=cooldown.kill_command.remains>focus.time_to_max&(active_enemies<3|!azerite.rapid_reload.enabled)
actions.cleave+=/spitting_cobra
]]
	if BarbedShot:usable() and PetFrenzy:up() and PetFrenzy:remains() <= (Player.gcd + 0.3) then
		return BarbedShot
	end
	if MultiShotBM:usable() and (Player.gcd - BeastCleave:remains()) > 0.25 then
		return MultiShotBM
	end
	if BarbedShot:usable() and BarbedShot:fullRechargeTime() < Player.gcd and not BestialWrath:ready() then
		return BarbedShot
	end
	if AspectOfTheWild:usable() then
		UseCooldown(AspectOfTheWild)
	end
	if Stampede:usable() and (AspectOfTheWild:up() and BestialWrath:up() or Target.timeToDie < 15) then
		UseCooldown(Stampede)
	end
	if BestialWrath:usable() and (AspectOfTheWild:cooldown() > 20 or OneWithThePack.known or Target.timeToDie < 15) then
		UseCooldown(BestialWrath)
	end
	if ChimaeraShot:usable() then
		return ChimaeraShot
	end
	if AMurderOfCrows:usable() then
		UseCooldown(AMurderOfCrows)
	end
	if Barrage:usable() then
		return Barrage
	end
	if KillCommandBM:usable() and (Player.enemies < 4 or not RapidReload.known) then
		return KillCommandBM
	end
	if DireBeast:usable() then
		return DireBeast
	end
	if BarbedShot:usable() and ((PetFrenzy:down() and (BarbedShot:chargesFractional() > 1.8 or BestialWrath:up())) or (PrimalInstincts.known and AspectOfTheWild:ready(PetFrenzy:duration() - Player.gcd)) or BarbedShot:chargesFractional() > 1.4 or Target.timeToDie < 9) then
		return BarbedShot
	end
	if RapidReload.known and MultiShotBM:usable() and Player.enemies > 2 then
		return MultiShotBM
	end
	if CobraShot:usable() and KillCommandBM:cooldown() > FocusTimeToMax() and (Player.enemies < 3 or not RapidReload.known) then
		return CobraShot
	end
	if SpittingCobra:usable() then
		UseCooldown(SpittingCobra)
	end
end

APL[SPEC.MARKSMANSHIP].main = function(self)
	if CallPet:usable() then
		UseExtra(CallPet)
	elseif RevivePet:usable() then
		UseExtra(RevivePet)
	elseif MendPet:usable() then
		UseExtra(MendPet)
	end
	if TimeInCombat() == 0 then
		if Opt.pot and not InArenaOrBattleground() then
			if FlaskOfTheCurrents:usable() and FlaskOfTheCurrents.buff:remains() < 300 then
				UseCooldown(FlaskOfTheUndertow)
			end
			if BattlePotionOfAgility:usable() then
				UseCooldown(BattlePotionOfAgility)
			end
		end
	end
end

APL[SPEC.SURVIVAL].main = function(self)
	if CallPet:usable() then
		UseExtra(CallPet)
	elseif RevivePet:usable() then
		UseExtra(RevivePet)
	elseif MendPet:usable() then
		UseExtra(MendPet)
	end
	if TimeInCombat() == 0 then
		if Opt.pot and not InArenaOrBattleground() then
			if FlaskOfTheCurrents:usable() and FlaskOfTheCurrents.buff:remains() < 300 then
				UseCooldown(FlaskOfTheUndertow)
			end
			if BattlePotionOfAgility:usable() then
				UseCooldown(BattlePotionOfAgility)
			end
		end
		if Harpoon:usable() then
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
	Player.ss_refresh = SerpentSting:refreshable() and (((Target.timeToDie - SerpentSting:remains()) > (SerpentSting:tickTime() * 2)) or (VipersVenom.known and VipersVenom:up()))
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
	if ArcaneTorrent:usable() and Focus() < 30 then
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
	if Opt.pot and not InArenaOrBattleground() and BattlePotionOfAgility:usable() and CoordinatedAssault:up() and BloodlustActive() then
		UseCooldown(BattlePotionOfAgility)
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
	if AMurderOfCrows:usable() then
		UseCooldown(AMurderOfCrows)
	end
	if CoordinatedAssault:usable() then
		UseCooldown(CoordinatedAssault)
	end
	if AlphaPredator.known then
		if WildfireBomb:usable() and WildfireBomb:fullRechargeTime() < Player.gcd then
			return WildfireBomb
		end
		if MongooseBite.known and MongooseFury:remains() > 0.2 and MongooseFury:stack() == 5 then
			if SerpentSting:usable() and Player.ss_refresh then
				return SerpentSting
			end
			if MongooseBite:usable() then
				return MongooseBite
			end
		end
	end
	if BirdsOfPrey.known and CoordinatedAssault:up() and (CoordinatedAssault:remains() < Player.gcd or BlurOfTalons:up() and BlurOfTalons:remains() < Player.gcd) then
		if MongooseBite:usable() then
			return MongooseBite
		end
		if RaptorStrike:usable() then
			return RaptorStrike
		end
	end
	if KillCommand:usable() and KillCommand:wontCapFocus() and TipOfTheSpear:stack() < 3 then
		return KillCommand
	end
	if Chakrams:usable() then
		return Chakrams
	end
	if SteelTrap:usable() then
		UseCooldown(SteelTrap)
	end
	if WildfireBomb:usable() and WildfireBomb:wontCapFocus() and (WildfireBomb:fullRechargeTime() < Player.gcd or WildfireBomb:refreshable() and MongooseFury:down()) then
		return WildfireBomb
	end
	if TermsOfEngagement.known and Harpoon:usable() then
		UseCooldown(Harpoon)
	end
	if FlankingStrike:usable() and FlankingStrike:wontCapFocus() then
		return FlankingStrike
	end
	if SerpentSting:usable() and ((VipersVenom.known and VipersVenom:up()) or (Player.ss_refresh and (not MongooseBite.known or not VipersVenom.known or LatentPoison.known or VenomousFangs.known))) then
		return SerpentSting
	end
	if MongooseBite:usable() and (MongooseFury:remains() > 0.2 or Focus() > 60) then
		return MongooseBite
	end
	if RaptorStrike:usable() then
		return RaptorStrike
	end
	if WildfireBomb:usable() and WildfireBomb:refreshable() then
		return WildfireBomb
	end
	if SerpentSting:usable() and Player.ss_refresh then
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
	if AMurderOfCrows:usable() then
		UseCooldown(AMurderOfCrows)
	end
	if CoordinatedAssault:usable() then
		UseCooldown(CoordinatedAssault)
	end
	if MongooseBite:usable() and WildernessSurvival.known and VolatileBomb.next and between(SerpentSting:remains(), 2.1 * Player.gcd, 3.5 * Player.gcd) and WildfireBomb:cooldown() > 2.5 * Player.gcd then
		return MongooseBite
	end
	if WildfireBomb:usable() and (WildfireBomb:fullRechargeTime() < Player.gcd or (WildfireBomb:wontCapFocus() and ((VolatileBomb.next and SerpentSting:up() and SerpentSting:refreshable()) or (PheromoneBomb.next and not MongooseFury:up() and WildfireBomb:wontCapFocus(KillCommand:castRegen() * 3))))) then
		return WildfireBomb
	end
	if KillCommand:usable() and KillCommand:wontCapFocus() and TipOfTheSpear:stack() < 3 and (not AlphaPredator.known or MongooseFury:stack() < 5 or Focus() < MongooseBite:cost()) then
		return KillCommand
	end
	if RaptorStrike:usable() and InternalBleeding:stack() < 3 and ShrapnelBomb:up() then
		return RaptorStrike
	end
	if WildfireBomb:usable() and ShrapnelBomb.next and MongooseFury:down() and (KillCommand:cooldown() > Player.gcd or Focus() > 60) and not SerpentSting:refreshable() then
		return WildfireBomb
	end
	if SteelTrap:usable() then
		UseCooldown(SteelTrap)
	end
	if FlankingStrike:usable() and FlankingStrike:wontCapFocus() then
		return FlankingStrike
	end
	if SerpentSting:usable() and ((VipersVenom.known and VipersVenom:up()) or (Player.ss_refresh and (not MongooseBite.known or not VipersVenom.known or VolatileBomb.next and not ShrapnelBomb:up() or LatentPoison.known or VenomousFangs.known or MongooseFury:stack() == 5))) then
		return SerpentSting
	end
	if TermsOfEngagement.known and Harpoon:usable() then
		UseCooldown(Harpoon)
	end
	if MongooseBite:usable() and (MongooseFury:remains() > 0.2 or Focus() > 60 or ShrapnelBomb:up()) then
		return MongooseBite
	end
	if RaptorStrike:usable() then
		return RaptorStrike
	end
	if SerpentSting:usable() and Player.ss_refresh then
		return SerpentSting
	end
	if WildfireBomb:usable() and ((VolatileBomb.next and SerpentSting:up()) or PheromoneBomb.next or (ShrapnelBomb.next and Focus() > 50)) then
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
	if MongooseBite:usable() and MongooseBite:stack() == 5 and between(MongooseFury:remains(), 0.2, Player.gcd) then
		return MongooseBite
	end
	if SerpentSting:usable() and SerpentSting:down() and Player.ss_refresh then
		return SerpentSting
	end
	if WildfireBomb:usable() and (WildfireBomb:fullRechargeTime() < Player.gcd or (WildfireBomb:wontCapFocus() and ((VolatileBomb.next and SerpentSting:up() and SerpentSting:refreshable()) or (PheromoneBomb.next and not MongooseFury:up() and WildfireBomb:wontCapFocus(KillCommand:castRegen() * 3))))) then
		return WildfireBomb
	end
	if CoordinatedAssault:usable() then
		UseCooldown(CoordinatedAssault)
	end
	if MongooseBite:usable() and MongooseBite:stack() == 5 and MongooseFury:remains() > 0.2  then
		return MongooseBite
	end
	if AMurderOfCrows:usable() then
		UseCooldown(AMurderOfCrows)
	end
	if SteelTrap:usable() then
		UseCooldown(SteelTrap)
	end
	if MongooseBite:usable() and MongooseFury:remains() > 0.2 and PheromoneBomb.next then
		return MongooseBite
	end
	if KillCommand:usable() and KillCommand:wontCapFocus() and (MongooseFury:stack() < 5 or Focus() < MongooseBite:cost()) then
		return KillCommand
	end
	if WildfireBomb:usable() and ShrapnelBomb.next and Focus() > 60 and SerpentSting:remains() > 3 * Player.gcd then
		return WildfireBomb
	end
	if SerpentSting:usable() and Player.ss_refresh and not ShrapnelBomb:up() then
		return SerpentSting
	end
	if MongooseBite:usable() and (MongooseFury:remains() > 0.2 or Focus() > 60 or ShrapnelBomb:up()) then
		return MongooseBite
	end
	if SerpentSting:usable() and Player.ss_refresh then
		return SerpentSting
	end
	if WildfireBomb:usable() and ((VolatileBomb.next and SerpentSting:up()) or PheromoneBomb.next or (ShrapnelBomb.next and Focus() > 50)) then
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
	if AMurderOfCrows:usable() then
		UseCooldown(AMurderOfCrows)
	end
	if CoordinatedAssault:usable() then
		UseCooldown(CoordinatedAssault)
	end
	if Carve:usable() and ShrapnelBomb:ticking() > 0 then
		return Carve
	end
	if WildfireBomb:usable() and (not GuerrillaTactics.known or WildfireBomb:fullRechargeTime() < Player.gcd) then
		return WildfireBomb
	end
	if MongooseBite:usable() and LatentPoison:stack() >= 10 then
		return MongooseBite
	end
	if Chakrams:usable() then
		return Chakrams
	end
	if KillCommand:usable() and KillCommand:wontCapFocus() then
		return KillCommand
	end
	if Butchery:usable() and (Butchery:fullRechargeTime() < Player.gcd or not WildfireInfusion.known or (ShrapnelBomb:ticking() > 0 and InternalBleeding:stack() < 3)) then
		return Butchery
	end
	if GuerrillaTactics.known and Carve:usable() then
		return Carve
	end
	if FlankingStrike:usable() and FlankingStrike:wontCapFocus() then
		return FlankingStrike
	end
	if WildfireBomb:usable() and (WildfireInfusion.known or WildfireBomb:refreshable()) then
		return WildfireBomb
	end
	if VipersVenom.known and VipersVenom:up() and SerpentSting:usable() then
		return SerpentSting
	end
	if Carve:usable() and WildfireBomb:cooldown() > (carve_cdr / 2) then
		return Carve
	end
	if SteelTrap:usable() then
		UseCooldown(SteelTrap)
	end
	if TermsOfEngagement.known and Harpoon:usable() then
		UseCooldown(Harpoon)
	end
	if SerpentSting:usable() and Player.ss_refresh and (not TipOfTheSpear.known or TipOfTheSpear:stack() < 3) then
		return SerpentSting
	end
	if MongooseBite:usable() then
		return MongooseBite
	end
	if RaptorStrike:usable() then
		return RaptorStrike
	end
end

APL.Interrupt = function(self)
	if CounterShot:usable() then
		return CounterShot
	end
	if Muzzle:usable() then
		return Muzzle
	end
	if Intimidation:usable() and Target.stunnable then
		return Intimidation
	end
end

-- End Action Priority Lists

local function UpdateInterrupt()
	local _, _, _, start, ends, _, _, notInterruptible = UnitCastingInfo('target')
	if not start then
		_, _, _, start, ends, _, notInterruptible = UnitChannelInfo('target')
	end
	if not start or notInterruptible then
		Player.interrupt = nil
		ghInterruptPanel:Hide()
		return
	end
	Player.interrupt = APL.Interrupt()
	if Player.interrupt then
		ghInterruptPanel.icon:SetTexture(Player.interrupt.icon)
	end
	ghInterruptPanel.icon:SetShown(Player.interrupt)
	ghInterruptPanel.border:SetShown(Player.interrupt)
	ghInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
	ghInterruptPanel:Show()
end

local function DenyOverlayGlow(actionButton)
	if not Opt.glow.blizzard then
		actionButton.overlay:Hide()
	end
end

hooksecurefunc('ActionButton_ShowOverlayGlow', DenyOverlayGlow) -- Disable Blizzard's built-in action button glowing

local function UpdateGlowColorAndScale()
	local w, h, glow, i
	local r = Opt.glow.color.r
	local g = Opt.glow.color.g
	local b = Opt.glow.color.b
	for i = 1, #glows do
		glow = glows[i]
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

local function CreateOverlayGlows()
	local b, i
	local GenerateGlow = function(button)
		if button then
			local glow = CreateFrame('Frame', nil, button, 'ActionBarButtonSpellActivationAlert')
			glow:Hide()
			glow.button = button
			glows[#glows + 1] = glow
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
	UpdateGlowColorAndScale()
end

local function UpdateGlows()
	local glow, icon, i
	for i = 1, #glows do
		glow = glows[i]
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

function events:ACTIONBAR_SLOT_CHANGED()
	UpdateGlows()
end

local function ShouldHide()
	return (Player.spec == SPEC.NONE or
		   (Player.spec == SPEC.BEASTMASTERY and Opt.hide.beastmastery) or
		   (Player.spec == SPEC.MARKSMANSHIP and Opt.hide.marksmanship) or
		   (Player.spec == SPEC.SURVIVAL and Opt.hide.survival))
end

local function Disappear()
	ghPanel:Hide()
	ghPanel.icon:Hide()
	ghPanel.border:Hide()
	ghCooldownPanel:Hide()
	ghInterruptPanel:Hide()
	ghExtraPanel:Hide()
	Player.main, Player.last_main = nil
	Player.cd, Player.last_cd = nil
	Player.interrupt = nil
	Player.extra, Player.last_extra = nil
	UpdateGlows()
end

local function Equipped(itemID, slot)
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

local function UpdateDraggable()
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

local function UpdateScale()
	ghPanel:SetSize(64 * Opt.scale.main, 64 * Opt.scale.main)
	ghPreviousPanel:SetSize(64 * Opt.scale.previous, 64 * Opt.scale.previous)
	ghCooldownPanel:SetSize(64 * Opt.scale.cooldown, 64 * Opt.scale.cooldown)
	ghInterruptPanel:SetSize(64 * Opt.scale.interrupt, 64 * Opt.scale.interrupt)
	ghExtraPanel:SetSize(64 * Opt.scale.extra, 64 * Opt.scale.extra)
end

local function UpdateAlpha()
	ghPanel:SetAlpha(Opt.alpha)
	ghPreviousPanel:SetAlpha(Opt.alpha)
	ghCooldownPanel:SetAlpha(Opt.alpha)
	ghInterruptPanel:SetAlpha(Opt.alpha)
	ghExtraPanel:SetAlpha(Opt.alpha)
end

local function SnapAllPanels()
	ghPreviousPanel:ClearAllPoints()
	ghPreviousPanel:SetPoint('TOPRIGHT', ghPanel, 'BOTTOMLEFT', -3, 40)
	ghCooldownPanel:ClearAllPoints()
	ghCooldownPanel:SetPoint('TOPLEFT', ghPanel, 'BOTTOMRIGHT', 3, 40)
	ghInterruptPanel:ClearAllPoints()
	ghInterruptPanel:SetPoint('BOTTOMLEFT', ghPanel, 'TOPRIGHT', 3, -21)
	ghExtraPanel:ClearAllPoints()
	ghExtraPanel:SetPoint('BOTTOMRIGHT', ghPanel, 'TOPLEFT', -3, -21)
end

local resourceAnchor = {}

local ResourceFramePoints = {
	['blizzard'] = {
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
		}
	},
	['kui'] = {
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
		}
	},
}

local function OnResourceFrameHide()
	if Opt.snap then
		ghPanel:ClearAllPoints()
	end
end

local function OnResourceFrameShow()
	if Opt.snap then
		ghPanel:ClearAllPoints()
		local p = ResourceFramePoints[resourceAnchor.name][Player.spec][Opt.snap]
		ghPanel:SetPoint(p[1], resourceAnchor.frame, p[2], p[3], p[4])
		SnapAllPanels()
	end
end

local function HookResourceFrame()
	if KuiNameplatesCoreSaved and KuiNameplatesCoreCharacterSaved and
		not KuiNameplatesCoreSaved.profiles[KuiNameplatesCoreCharacterSaved.profile].use_blizzard_personal
	then
		resourceAnchor.name = 'kui'
		resourceAnchor.frame = KuiNameplatesPlayerAnchor
	else
		resourceAnchor.name = 'blizzard'
		resourceAnchor.frame = NamePlateDriverFrame:GetClassNameplateBar()
	end
	if resourceAnchor.frame then
		resourceAnchor.frame:HookScript("OnHide", OnResourceFrameHide)
		resourceAnchor.frame:HookScript("OnShow", OnResourceFrameShow)
	end
end

local function UpdateTargetHealth()
	timer.health = 0
	Target.health = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[15] = Target.health
	Target.timeToDieMax = Target.health / UnitHealthMax('player') * 15
	Target.healthPercentage = Target.healthMax > 0 and (Target.health / Target.healthMax * 100) or 100
	Target.healthLostPerSec = (Target.healthArray[1] - Target.health) / 3
	Target.timeToDie = Target.healthLostPerSec > 0 and min(Target.timeToDieMax, Target.health / Target.healthLostPerSec) or Target.timeToDieMax
end

local function UpdateDisplay()
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
			ghPanel.text.center:SetText(format('WAIT %.1fs', deficit))
			text_center = true
			dim = Opt.dimmer
		end
	end
	ghPanel.dimmer:SetShown(dim)
	ghPanel.text:SetShown(text_center)
end

local function UpdateCombat()
	timer.combat = 0
	local _, start, duration, remains, spellId
	Player.ctime = GetTime()
	Player.time = Player.ctime - Player.time_diff
	Player.last_main = Player.main
	Player.last_cd = Player.cd
	Player.last_extra = Player.extra
	Player.main =  nil
	Player.cd = nil
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
		Player.focus = Player.focus - Player.ability_casting:cost()
	end
	Player.focus = min(max(Player.focus, 0), Player.focus_max)
	Player.pet = UnitGUID('pet')
	Player.pet_alive = Player.pet and not UnitIsDead('pet') and true
	Player.pet_active = (Player.pet_alive and not Player.pet_stuck or IsFlying()) and true

	trackAuras:purge()
	if Opt.auto_aoe then
		local ability
		for _, ability in next, abilities.autoAoe do
			ability:updateTargetsHit()
		end
		autoAoe:purge()
	end

	Player.main = APL[Player.spec]:main()
	if Player.main ~= Player.last_main then
		if Player.main then
			ghPanel.icon:SetTexture(Player.main.icon)
		end
		ghPanel.icon:SetShown(Player.main)
		ghPanel.border:SetShown(Player.main)
	end
	if Player.cd ~= Player.last_cd then
		if Player.cd then
			ghCooldownPanel.icon:SetTexture(Player.cd.icon)
		end
		ghCooldownPanel:SetShown(Player.cd)
	end
	if Player.extra ~= Player.last_extra then
		if Player.extra then
			ghExtraPanel.icon:SetTexture(Player.extra.icon)
		end
		ghExtraPanel:SetShown(Player.extra)
	end
	if Opt.interrupt then
		UpdateInterrupt()
	end

	if Player.spec == SPEC.BEASTMASTERY then
		local start, duration, stack = PetFrenzy:start_duration_stack()
		if start > 0 then
			ghExtraPanel.frenzy.stack:SetText(stack)
			ghExtraPanel.frenzy:SetCooldown(start, duration)
			ghExtraPanel.frenzy:Show()
			if not Player.extra then
				ghExtraPanel.icon:SetTexture(PetFrenzy.icon)
				ghExtraPanel:Show()
			end
		else
			ghExtraPanel.frenzy:Hide()
			if not Player.extra then
				ghExtraPanel:Hide()
			end
		end
	end

	UpdateGlows()
	UpdateDisplay()
end

local function UpdateCombatWithin(seconds)
	if Opt.frequency - timer.combat > seconds then
		timer.combat = max(seconds, Opt.frequency - seconds)
	end
end

function events:SPELL_UPDATE_COOLDOWN()
	if Opt.spell_swipe then
		local start, duration
		local _, _, _, castStart, castEnd = UnitCastingInfo('player')
		if castStart then
			start = castStart / 1000
			duration = (castEnd - castStart) / 1000
		else
			start, duration = GetSpellCooldown(61304)
		end
		ghPanel.swipe:SetCooldown(start, duration)
	end
end

function events:UNIT_SPELLCAST_START(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:UNIT_SPELLCAST_STOP(srcName)
	if Opt.interrupt and srcName == 'target' then
		UpdateCombatWithin(0.05)
	end
end

function events:ADDON_LOADED(name)
	if name == 'GoodHunting' then
		Opt = GoodHunting
		if not Opt.frequency then
			print('It looks like this is your first time running Good Hunting, why don\'t you take some time to familiarize yourself with the commands?')
			print('Type |cFFFFD000' .. SLASH_GoodHunting1 .. '|r for a list of commands.')
		end
		if UnitLevel('player') < 110 then
			print('[|cFFFFD000Warning|r] Good Hunting is not designed for players under level 110, and almost certainly will not operate properly!')
		end
		InitializeOpts()
		Azerite:initialize()
		UpdateDraggable()
		UpdateAlpha()
		UpdateScale()
		SnapAllPanels()
	end
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

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, _, srcGUID, _, _, _, dstGUID, _, _, _, spellId, spellName, _, missType = CombatLogGetCurrentEventInfo()
	Player.time = timeStamp
	Player.ctime = GetTime()
	Player.time_diff = Player.ctime - Player.time

	if eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
		trackAuras:remove(dstGUID)
		if Opt.auto_aoe then
			autoAoe:remove(dstGUID)
		end
	end
	if Opt.auto_aoe and (eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED') then
		if dstGUID == Player.guid or dstGUID == Player.pet then
			autoAoe:add(srcGUID, true)
		elseif (srcGUID == Player.guid or srcGUID == Player.pet) and not (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:add(dstGUID, true)
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

	UpdateCombatWithin(0.05)
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
			ability:applyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REFRESH' then
			ability:refreshAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' then
			ability:removeAura(dstGUID)
		end
		if ability == Outbreak then
			VirulentPlague:refreshAuraAll()
		end
	end
	if Opt.auto_aoe then
		if eventType == 'SPELL_MISSED' and (missType == 'EVADE' or missType == 'IMMUNE') then
			autoAoe:remove(dstGUID)
		elseif ability.auto_aoe and (eventType == ability.auto_aoe.trigger or ability.auto_aoe.trigger == 'SPELL_AURA_APPLIED' and eventType == 'SPELL_AURA_REFRESH') then
			ability:recordTargetHit(dstGUID)
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

local function UpdateTargetInfo()
	Disappear()
	if ShouldHide() then
		return
	end
	local guid = UnitGUID('target')
	if not guid then
		Target.guid = nil
		Target.boss = false
		Target.stunnable = true
		Target.classification = 'normal'
		Target.player = false
		Target.level = UnitLevel('player')
		Target.healthMax = 0
		Target.hostile = true
		local i
		for i = 1, 15 do
			Target.healthArray[i] = 0
		end
		if Opt.always_on then
			UpdateTargetHealth()
			UpdateCombat()
			ghPanel:Show()
			return true
		end
		if Opt.previous and Player.combat_start == 0 then
			ghPreviousPanel:Hide()
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = guid
		local i
		for i = 1, 15 do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.boss = false
	Target.stunnable = true
	Target.classification = UnitClassification('target')
	Target.player = UnitIsPlayer('target')
	Target.level = UnitLevel('target')
	Target.healthMax = UnitHealthMax('target')
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if not Target.player and Target.classification ~= 'minus' and Target.classification ~= 'normal' then
		if Target.level == -1 or (Player.instance == 'party' and Target.level >= UnitLevel('player') + 2) then
			Target.boss = true
			Target.stunnable = false
		elseif Player.instance == 'raid' or (Target.healthMax > Player.health_max * 10) then
			Target.stunnable = false
		end
	end
	if Target.hostile or Opt.always_on then
		UpdateTargetHealth()
		UpdateCombat()
		ghPanel:Show()
		return true
	end
end

function events:PLAYER_TARGET_CHANGED()
	UpdateTargetInfo()
end

function events:UNIT_FACTION(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
	end
end

function events:UNIT_FLAGS(unitID)
	if unitID == 'target' then
		UpdateTargetInfo()
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
		autoAoe:clear()
		autoAoe:update()
	end
end

local function UpdateAbilityData()
	Player.focus_max = UnitPowerMax('player', 2)
	local _, ability
	for _, ability in next, abilities.all do
		ability.name, _, ability.icon = GetSpellInfo(ability.spellId)
		ability.known = (IsPlayerSpell(ability.spellId) or (ability.spellId2 and IsPlayerSpell(ability.spellId2)) or Azerite.traits[ability.spellId]) and true or false
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

function events:SPELL_UPDATE_ICON()
	if WildfireInfusion.known then
		WildfireInfusion:update()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()
	Azerite:update()
	UpdateAbilityData()
	Trinket1.itemId = GetInventoryItemID('player', 13) or 0
	Trinket2.itemId = GetInventoryItemID('player', 14) or 0
	local _, i, equipType, hasCooldown
	for i = 1, #inventoryItems do
		inventoryItems[i].name, _, _, _, _, _, _, _, equipType, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId or 0)
		inventoryItems[i].can_use = inventoryItems[i].name and true or false
		if equipType and equipType ~= '' then
			hasCooldown = 0
			_, inventoryItems[i].equip_slot = Equipped(inventoryItems[i].itemId)
			if inventoryItems[i].equip_slot then
				_, _, hasCooldown = GetInventoryItemCooldown('player', inventoryItems[i].equip_slot)
			end
			inventoryItems[i].can_use = hasCooldown == 1
		end
	end
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName ~= 'player' then
		return
	end
	Player.spec = GetSpecialization() or 0
	ghPreviousPanel.ability = nil
	SetTargetMode(1)
	UpdateTargetInfo()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_REGEN_ENABLED()
end

function events:PLAYER_PVP_TALENT_UPDATE()
	UpdateAbilityData()
end

function events:PLAYER_ENTERING_WORLD()
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	local _
	_, Player.instance = IsInInstance()
	Player.guid = UnitGUID('player')
	events:PLAYER_SPECIALIZATION_CHANGED('player')
end

ghPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			ToggleTargetMode()
		elseif button == 'RightButton' then
			ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			SetTargetMode(1)
		end
	end
end)

ghPanel:SetScript('OnUpdate', function(self, elapsed)
	timer.combat = timer.combat + elapsed
	timer.display = timer.display + elapsed
	timer.health = timer.health + elapsed
	if timer.combat >= Opt.frequency then
		UpdateCombat()
	end
	if timer.display >= 0.05 then
		UpdateDisplay()
	end
	if timer.health >= 0.2 then
		UpdateTargetHealth()
	end
end)

ghPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	ghPanel:RegisterEvent(event)
end

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
			UpdateDraggable()
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
			OnResourceFrameShow()
		end
		return Status('Snap to Blizzard combat resources frame', Opt.snap)
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				UpdateScale()
			end
			return Status('Previous ability icon scale', Opt.scale.previous, 'times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				UpdateScale()
			end
			return Status('Main ability icon scale', Opt.scale.main, 'times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				UpdateScale()
			end
			return Status('Cooldown ability icon scale', Opt.scale.cooldown, 'times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				UpdateScale()
			end
			return Status('Interrupt ability icon scale', Opt.scale.interrupt, 'times')
		end
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				UpdateScale()
			end
			return Status('Extra/Pet cooldown ability icon scale', Opt.scale.extra, 'times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return Status('Action button glow scale', Opt.scale.glow, 'times')
		end
		return Status('Default icon scale options', '|cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000pet 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
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
				UpdateGlows()
			end
			return Status('Glowing ability buttons (main icon)', Opt.glow.main)
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Glowing ability buttons (cooldown icon)', Opt.glow.cooldown)
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Glowing ability buttons (interrupt icon)', Opt.glow.interrupt)
		end
		if startsWith(msg[2], 'ex') or startsWith(msg[2], 'pet') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Glowing ability buttons (extra/pet cooldown icon)', Opt.glow.extra)
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return Status('Blizzard default proc glow', Opt.glow.blizzard)
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return Status('Glow color', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return Status('Possible glow options', '|cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000pet|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return Status('Previous ability icon', Opt.previous)
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			UpdateTargetInfo()
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
		return Status('Dim main ability icon when you don\'t have enough mana to use it', Opt.dimmer)
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
			SetTargetMode(1)
			UpdateDraggable()
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
		SnapAllPanels()
		return Status('Position has been reset to', 'default')
	end
	print('Good Hunting (version: |cFFFFD000' .. GetAddOnMetadata('GoodHunting', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Good Hunting UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Good Hunting UI to the Blizzard combat resources frame',
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
		'pot |cFF00C000on|r/|cFFC00000off|r - show Battle potions in cooldown UI',
		'trinket |cFF00C000on|r/|cFFC00000off|r - show on-use trinkets in cooldown UI',
		'mend |cFFFFD000[percent]|r  - health percentage to recommend Mend Pet at (default is 65%, 0 to disable)',
		'|cFFFFD000reset|r - reset the location of the Good Hunting UI to default',
	} do
		print('  ' .. SLASH_GoodHunting1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Talk to me on Battle.net:',
		'|c' .. BATTLENET_FONT_COLOR:GenerateHexColor() .. '|HBNadd:Spy#1955|h[Spy#1955]|h|r')
end
