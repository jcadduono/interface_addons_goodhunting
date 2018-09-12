if select(2, UnitClass('player')) ~= 'HUNTER' then
	DisableAddOn('GoodHunting')
	return
end

-- useful functions
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

local function InitializeVariables()
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
			color = { r = 1, g = 1, b = 1 }
		},
		hide = {
			beastmastery = false,
			marksmanship = false,
			survival = false
		},
		alpha = 1,
		frequency = 0.05,
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
		mend_threshold = 65
	})
end

-- specialization constants
local SPEC = {
	NONE = 0,
	BEASTMASTERY = 1,
	MARKSMANSHIP = 2,
	SURVIVAL = 3
}

local events, glows = {}, {}

local abilityTimer, currentSpec, targetMode, combatStartTime = 0, 0, 0, 0

-- current target information
local Target = {
	boss = false,
	guid = 0,
	healthArray = {},
	hostile = false
}

-- list of previous GCD abilities
local PreviousGCD = {}

-- items equipped with special effects
local ItemEquipped = {

}

local var = {
	gcd = 1.5
}

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
	}
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
ghPanel.border:SetTexture('Interface\\AddOns\\GoodHunting\\border.blp')
ghPanel.border:Hide()
ghPanel.text = ghPanel:CreateFontString(nil, 'OVERLAY')
ghPanel.text:SetFont('Fonts\\FRIZQT__.TTF', 14, 'OUTLINE')
ghPanel.text:SetTextColor(1, 1, 1, 1)
ghPanel.text:SetAllPoints(ghPanel)
ghPanel.text:SetJustifyH('CENTER')
ghPanel.text:SetJustifyV('CENTER')
ghPanel.swipe = CreateFrame('Cooldown', nil, ghPanel, 'CooldownFrameTemplate')
ghPanel.swipe:SetAllPoints(ghPanel)
ghPanel.dimmer = ghPanel:CreateTexture(nil, 'BORDER')
ghPanel.dimmer:SetAllPoints(ghPanel)
ghPanel.dimmer:SetColorTexture(0, 0, 0, 0.6)
ghPanel.dimmer:Hide()
ghPanel.targets = ghPanel:CreateFontString(nil, 'OVERLAY')
ghPanel.targets:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
ghPanel.targets:SetPoint('BOTTOMRIGHT', ghPanel, 'BOTTOMRIGHT', -1.5, 3)
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

-- Start Auto AoE

local autoAoe = {
	abilities = {},
	targets = {}
}

function autoAoe:update()
	local count, i = 0
	for i in next, self.targets do
		count = count + 1
	end
	if count <= 1 then
		GoodHunting_SetTargetMode(1)
		return
	end
	for i = #targetModes[currentSpec], 1, -1 do
		if count >= targetModes[currentSpec][i][1] then
			GoodHunting_SetTargetMode(i)
			return
		end
	end
end

function autoAoe:add(guid)
	local new = not self.targets[guid]
	self.targets[guid] = GetTime()
	if new then
		self:update()
	end
end

function autoAoe:remove(guid)
	if self.targets[guid] then
		self.targets[guid] = nil
		self:update()
	end
end

function autoAoe:purge()
	local update, guid, t
	local now = GetTime()
	for guid, t in next, self.targets do
		if now - t > Opt.auto_aoe_ttl then
			self.targets[guid] = nil
			update = true
		end
	end
	if update then
		self:update()
	end
end

-- End Auto AoE

-- Start Abilities

local Ability, abilities, abilityBySpellId = {}, {}, {}
Ability.__index = Ability

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
		velocity = 0,
		auraTarget = buff and 'player' or 'target',
		auraFilter = (buff and 'HELPFUL' or 'HARMFUL') .. (player and '|PLAYER' or '')
	}
	setmetatable(ability, Ability)
	abilities[#abilities + 1] = ability
	abilityBySpellId[spellId] = ability
	if spellId2 then
		abilityBySpellId[spellId2] = ability
	end
	return ability
end

function Ability:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function Ability:usable(seconds)
	if not self.known then
		return false
	end
	if self:cost() > var.focus then
		return false
	end
	if self.requires_pet and not var.pet_exists then
		return false
	end
	if self.requires_charge and self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

function Ability:remains()
	if self:traveling() then
		return self:duration()
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			if expires == 0 then
				return 600 -- infinite duration
			end
			return max(expires - var.time - var.execute_remains, 0)
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
	if self:traveling() then
		return true
	end
	local _, i, id, expires
	for i = 1, 40 do
		_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return false
		end
		if id == self.spellId or id == self.spellId2 then
			return expires == 0 or expires - var.time > var.execute_remains
		end
	end
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
		if var.time - self.travel_start[Target.guid] < 40 / self.velocity then
			return true
		end
		self.travel_start[Target.guid] = nil
	end
end

function Ability:ticking()
	if self.aura_targets then
		local count, guid, expires = 0
		for guid, expires in next, self.aura_targets do
			if expires - var.time > var.execute_remains then
				count = count + 1
			end
		end
		return count
	end
	return self:up() and 1 or 0
end

function Ability:cooldownDuration()
	return self.hasted_cooldown and (var.haste_factor * self.cooldown_duration) or self.cooldown_duration
end

function Ability:cooldown()
	local start, duration = GetSpellCooldown(self.spellId)
	if start == 0 then
		return 0
	end
	return max(0, duration - (var.time - start) - var.execute_remains)
end

function Ability:stack()
	local _, i, id, expires, count
	for i = 1, 40 do
		_, _, count, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
		if not id then
			return 0
		end
		if id == self.spellId or id == self.spellId2 then
			return (expires == 0 or expires - var.time > var.execute_remains) and count or 0
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
	return charges + ((max(0, var.time - recharge_start + var.execute_remains)) / recharge_time)
end

function Ability:fullRechargeTime()
	local charges, max_charges, recharge_start, recharge_time = GetSpellCharges(self.spellId)
	if charges >= max_charges then
		return 0
	end
	return (max_charges - charges - 1) * recharge_time + (recharge_time - (var.time - recharge_start) - var.execute_remains)
end

function Ability:maxCharges()
	local _, max_charges = GetSpellCharges(self.spellId)
	return max_charges or 0
end

function Ability:duration()
	return self.hasted_duration and (var.haste_factor * self.buff_duration) or self.buff_duration
end

function Ability:channeling()
	return UnitChannelInfo('player') == self.name
end

function Ability:castTime()
	local _, _, _, castTime = GetSpellInfo(self.spellId)
	if castTime == 0 then
		return self.triggers_gcd and var.gcd or 0
	end
	return castTime / 1000
end

function Ability:castRegen()
	return var.focus_regen * self:castTime() - self:cost()
end

function Ability:tickTime()
	return self.hasted_ticks and (var.haste_factor * self.tick_interval) or self.tick_interval
end

function Ability:previous()
	if self:channeling() then
		return true
	end
	return PreviousGCD[1] == self or var.last_ability == self
end

function Ability:setAutoAoe(enabled)
	if enabled and not self.auto_aoe then
		self.auto_aoe = true
		self.first_hit_time = nil
		self.targets_hit = {}
		autoAoe.abilities[#autoAoe.abilities + 1] = self
	end
	if not enabled and self.auto_aoe then
		self.auto_aoe = nil
		self.first_hit_time = nil
		self.targets_hit = nil
		local i
		for i = 1, #autoAoe.abilities do
			if autoAoe.abilities[i] == self then
				autoAoe.abilities[i] = nil
				break
			end
		end
	end
end

function Ability:recordTargetHit(guid)
	local t = GetTime()
	self.targets_hit[guid] = t
	if not self.first_hit_time then
		self.first_hit_time = t
	end
end

function Ability:updateTargetsHit()
	if self.first_hit_time and GetTime() - self.first_hit_time >= 0.3 then
		self.first_hit_time = nil
		local guid, t
		for guid in next, autoAoe.targets do
			if not self.targets_hit[guid] then
				autoAoe.targets[guid] = nil
			end
		end
		for guid, t in next, self.targets_hit do
			autoAoe.targets[guid] = t
			self.targets_hit[guid] = nil
		end
		autoAoe:update()
	end
end

-- start DoT tracking

local trackAuras = {
	abilities = {}
}

function trackAuras:purge()
	local now = GetTime()
	local _, ability, guid, expires
	for _, ability in next, self.abilities do
		for guid, expires in next, ability.aura_targets do
			if expires <= now then
				ability:removeAura(guid)
			end
		end
	end
end

function Ability:trackAuras()
	self.aura_targets = {}
	trackAuras.abilities[self.spellId] = self
	if self.spellId2 then
		trackAuras.abilities[self.spellId2] = self
	end
end

function Ability:applyAura(guid)
	if self.aura_targets and UnitGUID(self.auraTarget) == guid then -- for now, we can only track if the enemy is targeted
		local _, i, id, expires
		for i = 1, 40 do
			_, _, _, _, _, expires, _, _, _, id = UnitAura(self.auraTarget, i, self.auraFilter)
			if not id then
				return
			end
			if id == self.spellId or id == self.spellId2 then
				self.aura_targets[guid] = expires
				return
			end
		end
	end
end

function Ability:removeAura(guid)
	if self.aura_targets then
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

---- Beast Mastery

------ Talents

------ Procs

---- Marksmanship

------ Talents

------ Procs

---- Survival
local Carve = Ability.add(187708, false, true)
Carve.focus_cost = 35
Carve:setAutoAoe(true)
local CoordinatedAssault = Ability.add(266779, true, true)
CoordinatedAssault.cooldown_duration = 120
CoordinatedAssault.buff_duration = 20
CoordinatedAssault.requires_pet = true
local Harpoon = Ability.add(190925, false, true, 190927)
Harpoon.cooldown_duration = 20
Harpoon.buff_duration = 3
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
local WildfireBomb = Ability.add(259495, false, true, 269747)
WildfireBomb.cooldown_duration = 18
WildfireBomb.buff_duration = 6
WildfireBomb.tick_interval = 1
WildfireBomb.hasted_cooldown = true
WildfireBomb.requires_charge = true
WildfireBomb:setVelocity(35)
WildfireBomb:setAutoAoe(true)
------ Talents
local AlphaPredator = Ability.add(269737, false, true)
local AMurderOfCrows = Ability.add(131894, false, true, 131900)
AMurderOfCrows.focus_cost = 30
AMurderOfCrows.cooldown_duration = 60
AMurderOfCrows.tick_interval = 1
AMurderOfCrows.hasted_ticks = true
local BirdsOfPrey = Ability.add(260331, false, true)
local Bloodseeker = Ability.add(260248, false, true, 259277)
Bloodseeker.buff_duration = 8
Bloodseeker.tick_interval = 2
Bloodseeker.hasted_ticks = true
local Butchery = Ability.add(212436, false, true)
Butchery.focus_cost = 30
Butchery.cooldown_duration = 9
Butchery.hasted_cooldown = true
Butchery.requires_charge = true
Butchery:setAutoAoe(true)
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
PheromoneBomb:setAutoAoe(true)
local Predator = Ability.add(260249, true, true) -- Bloodseeker buff
local ShrapnelBomb = Ability.add(270335, false, true, 270339) -- Provided by Wildfire Infusion, replaces Wildfire Bomb
ShrapnelBomb.cooldown_duration = 18
ShrapnelBomb.buff_duration = 6
ShrapnelBomb.tick_interval = 1
ShrapnelBomb.hasted_cooldown = true
ShrapnelBomb.requires_charge = true
ShrapnelBomb:setVelocity(35)
ShrapnelBomb:setAutoAoe(true)
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
VolatileBomb:setAutoAoe(true)
local WildfireInfusion = Ability.add(271014, false, true)
------ Procs

-- Racials

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
		icon = icon
	}
	setmetatable(item, InventoryItem)
	inventoryItems[#inventoryItems + 1] = item
	return item
end

function InventoryItem:charges()
	local charges = GetItemCount(self.itemId, false, true) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		charges = max(charges, self.max_charges)
	end
	return charges
end

function InventoryItem:count()
	local count = GetItemCount(self.itemId, false, false) or 0
	if self.created_by and (self.created_by:previous() or PreviousGCD[1] == self.created_by) then
		count = max(count, 1)
	end
	return count
end

function InventoryItem:cooldown()
	local startTime, duration = GetItemCooldown(self.itemId)
	return startTime == 0 and 0 or duration - (var.time - startTime)
end

function InventoryItem:ready(seconds)
	return self:cooldown() <= (seconds or 0)
end

function InventoryItem:usable(seconds)
	if self:charges() == 0 then
		return false
	end
	return self:ready(seconds)
end

-- Inventory Items
local FlaskOfTheSeventhDemon = InventoryItem.add(127848)
FlaskOfTheSeventhDemon.buff = Ability.add(188033, true, true)
local FlaskOfTheCurrents = InventoryItem.add(152638)
FlaskOfTheCurrents.buff = Ability.add(251836, true, true)
local BattlePotionOfAgility = InventoryItem.add(163223)
BattlePotionOfAgility.buff = Ability.add(279152, true, true)
BattlePotionOfAgility.buff.triggers_gcd = false
local RepurposedFelFocuser = InventoryItem.add(147707)
RepurposedFelFocuser.buff = Ability.add(242551, true, true)
-- End Inventory Items

-- Start Helpful Functions

local function Focus()
	return var.focus
end

local function FocusDeficit()
	return var.focus_max - var.focus
end

local function FocusRegen()
	return var.focus_regen
end

local function FocusMax()
	return var.focus_max
end

local function FocusTimeToMax()
	local deficit = var.focus_max - var.focus
	if deficit <= 0 then
		return 0
	end
	return deficit / var.focus_regen
end

local function GCD()
	return var.gcd
end

local function Enemies()
	return targetModes[currentSpec][targetMode][1]
end

local function TimeInCombat()
	return combatStartTime > 0 and var.time - combatStartTime or 0
end

local function BloodlustActive()
	local _, i, id
	for i = 1, 40 do
		_, _, _, _, _, _, _, _, _, id = UnitAura('player', i, 'HELPFUL')
		if (
			id == 2825 or	-- Bloodlust (Horde Shaman)
			id == 32182 or	-- Heroism (Alliance Shaman)
			id == 80353 or	-- Time Warp (Mage)
			id == 90355 or	-- Ancient Hysteria (Hunter Pet - Core Hound)
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

local function TargetIsStunnable()
	if UnitIsPlayer('target') then
		return true
	end
	if Target.boss then
		return false
	end
	if var.instance == 'raid' then
		return false
	end
	if UnitHealthMax('target') > UnitHealthMax('player') * 25 then
		return false
	end
	return true
end

local function InArenaOrBattleground()
	return var.instance == 'arena' or var.instance == 'pvp'
end

-- End Helpful Functions

-- Start Ability Modifications

function SerpentSting:cost()
	if VipersVenom:up() then
		return 0
	end
	return Ability.cost(self)
end

-- hack to support Wildfire Bomb's changing spells on each cast
function WildfireInfusion:update()
	local _, _, _, _, _, _, spellId = GetSpellInfo(WildfireBomb.name)
	if self.current and spellId == self.current.spellId then
		return -- not a bomb change
	end
	ShrapnelBomb.known = spellId == ShrapnelBomb.spellId
	PheromoneBomb.known = spellId == PheromoneBomb.spellId
	VolatileBomb.known = spellId == VolatileBomb.spellId
	if ShrapnelBomb.known then
		self.current = ShrapnelBomb
	elseif PheromoneBomb.known then
		self.current = PheromoneBomb
	elseif VolatileBomb.known then
		self.current = VolatileBomb
	else
		self.current = WildfireBomb
	end
	WildfireBomb.icon = self.current.icon
	if var.main == WildfireBomb then
		var.main = false -- reset current ability if it was a bomb
	end
end

function CallPet:usable()
	if UnitExists('pet') or IsFlying() then
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

-- End Ability Modifications

local function UpdateVars()
	local _, start, duration, remains, hp, hp_lost, spellId
	var.last_main = var.main
	var.last_cd = var.cd
	var.last_extra = var.extra
	var.main =  nil
	var.cd = nil
	var.extra = nil
	var.time = GetTime()
	start, duration = GetSpellCooldown(61304)
	var.gcd_remains = start > 0 and duration - (var.time - start) or 0
	_, _, _, _, remains, _, _, _, spellId = UnitCastingInfo('player')
	var.execute_remains = max(remains and (remains / 1000 - var.time) or 0, var.gcd_remains)
	var.haste_factor = 1 / (1 + UnitSpellHaste('player') / 100)
	var.gcd = 1.5 * var.haste_factor
	var.focus_regen = GetPowerRegen()
	var.focus_max = UnitPowerMax('player', 2)
	var.focus = min(var.focus_max, floor(UnitPower('player', 2) + (var.focus_regen * var.execute_remains)))
	var.pet = UnitGUID('pet')
	var.pet_exists = UnitExists('pet') and not UnitIsDead('pet')
	hp = UnitHealth('target')
	table.remove(Target.healthArray, 1)
	Target.healthArray[#Target.healthArray + 1] = hp
	Target.timeToDieMax = hp / UnitHealthMax('player') * 5
	Target.healthPercentage = Target.guid == 0 and 100 or (hp / UnitHealthMax('target') * 100)
	hp_lost = Target.healthArray[1] - hp
	Target.timeToDie = hp_lost > 0 and min(Target.timeToDieMax, hp / (hp_lost / 3)) or Target.timeToDieMax
end

local function UseCooldown(ability, overwrite, always)
	if always or (Opt.cooldown and (not Opt.boss_only or Target.boss) and (not var.cd or overwrite)) then
		var.cd = ability
	end
end

local function UseExtra(ability, overwrite)
	if not var.extra or overwrite then
		var.extra = ability
	end
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
	if TimeInCombat() == 0 then
		if not InArenaOrBattleground() then
			if RepurposedFelFocuser:usable() and RepurposedFelFocuser.buff:remains() < 300 and not (FlaskOfTheSeventhDemon.buff:up() or FlaskOfTheCurrents.buff:up()) then
				return RepurposedFelFocuser
			end
			if Opt.pot and BattlePotionOfAgility:usable() then
				UseCooldown(BattlePotionOfAgility)
			end
		end
	end
	if not InArenaOrBattleground() then
		if RepurposedFelFocuser:usable() and RepurposedFelFocuser.buff:remains() < 30 and not (FlaskOfTheSeventhDemon.buff:up() or FlaskOfTheCurrents.buff:up()) then
			UseCooldown(RepurposedFelFocuser)
		end
	end
end

APL[SPEC.MARKSMANSHIP].main = function(self)
	if TimeInCombat() == 0 then
		if not InArenaOrBattleground() then
			if RepurposedFelFocuser:usable() and RepurposedFelFocuser.buff:remains() < 300 and not (FlaskOfTheSeventhDemon.buff:up() or FlaskOfTheCurrents.buff:up()) then
				return RepurposedFelFocuser
			end
			if Opt.pot and BattlePotionOfAgility:usable() then
				UseCooldown(BattlePotionOfAgility)
			end
		end
	end
	if not InArenaOrBattleground() then
		if RepurposedFelFocuser:usable() and RepurposedFelFocuser.buff:remains() < 30 and not (FlaskOfTheSeventhDemon.buff:up() or FlaskOfTheCurrents.buff:up()) then
			UseCooldown(RepurposedFelFocuser)
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
		if not InArenaOrBattleground() then
			if RepurposedFelFocuser:usable() and RepurposedFelFocuser.buff:remains() < 300 and not (FlaskOfTheSeventhDemon.buff:up() or FlaskOfTheCurrents.buff:up()) then
				return RepurposedFelFocuser
			end
			if Opt.pot and BattlePotionOfAgility:usable() then
				UseCooldown(BattlePotionOfAgility)
			end
		end
		if Harpoon:usable() then
			UseCooldown(Harpoon)
		end
	end
	if not InArenaOrBattleground() then
		if RepurposedFelFocuser:usable() and RepurposedFelFocuser.buff:remains() < 30 and not (FlaskOfTheSeventhDemon.buff:up() or FlaskOfTheCurrents.buff:up()) then
			UseCooldown(RepurposedFelFocuser)
		end
		if Opt.pot and BattlePotionOfAgility:usable() and CoordinatedAssault:up() and BloodlustActive() then
			UseCooldown(BattlePotionOfAgility)
		end
	end
--[[
actions=auto_attack
actions+=/use_items
actions+=/berserking,if=cooldown.coordinated_assault.remains>30
actions+=/blood_fury,if=cooldown.coordinated_assault.remains>30
actions+=/ancestral_call,if=cooldown.coordinated_assault.remains>30
actions+=/fireblood,if=cooldown.coordinated_assault.remains>30
actions+=/lights_judgment
actions+=/potion,if=buff.coordinated_assault.up&(buff.berserking.up|buff.blood_fury.up|!race.troll&!race.orc)
actions+=/variable,name=can_gcd,value=!talent.mongoose_bite.enabled|buff.mongoose_fury.down|(buff.mongoose_fury.remains-(((buff.mongoose_fury.remains*focus.regen+focus)%action.mongoose_bite.cost)*gcd.max)>gcd.max)
actions+=/steel_trap
actions+=/a_murder_of_crows
actions+=/coordinated_assault
actions+=/chakrams,if=active_enemies>1
actions+=/kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max&buff.tip_of_the_spear.stack<3&active_enemies<2
actions+=/wildfire_bomb,if=(focus+cast_regen<focus.max|active_enemies>1)&(dot.wildfire_bomb.refreshable&buff.mongoose_fury.down|full_recharge_time<gcd)
actions+=/kill_command,target_if=min:bloodseeker.remains,if=focus+cast_regen<focus.max&buff.tip_of_the_spear.stack<3
actions+=/butchery,if=(!talent.wildfire_infusion.enabled|full_recharge_time<gcd)&active_enemies>3|(dot.shrapnel_bomb.ticking&dot.internal_bleeding.stack<3)
actions+=/serpent_sting,if=(active_enemies<2&refreshable&(buff.mongoose_fury.down|(variable.can_gcd&!talent.vipers_venom.enabled)))|buff.vipers_venom.up
actions+=/carve,if=active_enemies>2&(active_enemies<6&active_enemies+gcd<cooldown.wildfire_bomb.remains|5+gcd<cooldown.wildfire_bomb.remains)
actions+=/harpoon,if=talent.terms_of_engagement.enabled
actions+=/flanking_strike
actions+=/chakrams
actions+=/serpent_sting,target_if=min:remains,if=refreshable&buff.mongoose_fury.down|buff.vipers_venom.up
actions+=/mongoose_bite,target_if=min:dot.internal_bleeding.stack,if=buff.mongoose_fury.up|focus>60
actions+=/butchery
actions+=/raptor_strike,target_if=min:dot.internal_bleeding.stack
]]
	var.can_gcd = not MongooseBite.known or MongooseFury:down() or ((MongooseFury:remains() - (((MongooseFury:remains() * FocusRegen() + Focus()) % MongooseBite:cost()) * GCD())) > GCD())
	if SteelTrap:usable() then
		UseCooldown(SteelTrap)
	end
	if AMurderOfCrows:usable() then
		UseCooldown(AMurderOfCrows)
	end
	if CoordinatedAssault:usable() then
		UseCooldown(CoordinatedAssault)
	end
	if Chakrams:usable() and Enemies() > 1 then
		return Chakrams
	end
	if KillCommand:usable() and (Focus() + KillCommand:castRegen()) < (FocusMax() - 5) and TipOfTheSpear:stack() < 3 and Enemies() < 2 then
		return KillCommand
	end
	if WildfireBomb:usable() and ((Focus() + WildfireBomb:castRegen()) < (FocusMax() - 5) or Enemies() > 1) and (WildfireBomb:refreshable() and MongooseFury:down() or WildfireBomb:fullRechargeTime() < GCD()) then
		return WildfireBomb
	end
	if KillCommand:usable() and (Focus() + KillCommand:castRegen()) < (FocusMax() - 5) and TipOfTheSpear:stack() < 3 then
		return KillCommand
	end
	if Butchery:usable() and ((not WildfireInfusion.known or Butchery:fullRechargeTime() < GCD()) and Enemies() > 3 or (WildfireInfusion.known and ShrapnelBomb:up() and InternalBleeding:stack() < 3)) then
		return Butchery
	end
	if SerpentSting:usable() and ((Enemies() < 2 and SerpentSting:refreshable() and (MongooseFury:down() or (var.can_gcd and not VipersVenom.known))) or (VipersVenom.known and VipersVenom:up())) then
		return SerpentSting
	end
	if Carve:usable() and Enemies() > 2 and (Enemies() < 6 and (Enemies() + GCD()) < WildfireBomb:cooldown() or (5 + GCD()) < WildfireBomb:cooldown()) then
		return Carve
	end
	if TermsOfEngagement.known and Harpoon:usable() then
		UseCooldown(Harpoon)
	end
	if FlankingStrike:usable() then
		return FlankingStrike
	end
	if Chakrams:usable() then
		return Chakrams
	end
	if SerpentSting:usable() and ((SerpentSting:refreshable() and MongooseFury:down()) or (VipersVenom.known and VipersVenom:up())) then
		return SerpentSting
	end
	if MongooseBite:usable() and (MongooseFury:up() or Focus() > 60) then
		return MongooseBite
	end
	if Butchery:usable() then
		return Butchery
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
	if Intimidation:usable() and TargetIsStunnable() then
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
		var.interrupt = nil
		ghInterruptPanel:Hide()
		return
	end
	var.interrupt = APL.Interrupt()
	if var.interrupt then
		ghInterruptPanel.icon:SetTexture(var.interrupt.icon)
		ghInterruptPanel.icon:Show()
		ghInterruptPanel.border:Show()
	else
		ghInterruptPanel.icon:Hide()
		ghInterruptPanel.border:Hide()
	end
	ghInterruptPanel:Show()
	ghInterruptPanel.cast:SetCooldown(start / 1000, (ends - start) / 1000)
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
			(Opt.glow.main and var.main and icon == var.main.icon) or
			(Opt.glow.cooldown and var.cd and icon == var.cd.icon) or
			(Opt.glow.interrupt and var.interrupt and icon == var.interrupt.icon) or
			(Opt.glow.extra and var.extra and icon == var.extra.icon)
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
	return (currentSpec == SPEC.NONE or
		   (currentSpec == SPEC.BEASTMASTERY and Opt.hide.beastmastery) or
		   (currentSpec == SPEC.MARKSMANSHIP and Opt.hide.marksmanship) or
		   (currentSpec == SPEC.SURVIVAL and Opt.hide.survival))

end

local function Disappear()
	ghPanel:Hide()
	ghPanel.icon:Hide()
	ghPanel.border:Hide()
	ghCooldownPanel:Hide()
	ghInterruptPanel:Hide()
	ghExtraPanel:Hide()
	var.main, var.last_main = nil
	var.cd, var.last_cd = nil
	var.interrupt = nil
	var.extra, var.last_extra = nil
	UpdateGlows()
end

function GoodHunting_ToggleTargetMode()
	local mode = targetMode + 1
	GoodHunting_SetTargetMode(mode > #targetModes[currentSpec] and 1 or mode)
end

function GoodHunting_ToggleTargetModeReverse()
	local mode = targetMode - 1
	GoodHunting_SetTargetMode(mode < 1 and #targetModes[currentSpec] or mode)
end

function GoodHunting_SetTargetMode(mode)
	targetMode = min(mode, #targetModes[currentSpec])
	ghPanel.targets:SetText(targetModes[currentSpec][targetMode][2])
end

function Equipped(name, slot)
	local function SlotMatches(name, slot)
		local ilink = GetInventoryItemLink('player', slot)
		if ilink then
			local iname = ilink:match('%[(.*)%]')
			return (iname and iname:find(name))
		end
		return false
	end
	if slot then
		return SlotMatches(name, slot)
	end
	local i
	for i = 1, 19 do
		if SlotMatches(name, i) then
			return true
		end
	end
	return false
end

local function UpdateDraggable()
	ghPanel:EnableMouse(Opt.aoe or not Opt.locked)
	if Opt.aoe then
		ghPanel.button:Show()
	else
		ghPanel.button:Hide()
	end
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

local function SnapAllPanels()
	ghPreviousPanel:ClearAllPoints()
	ghPreviousPanel:SetPoint('BOTTOMRIGHT', ghPanel, 'BOTTOMLEFT', -10, -5)
	ghCooldownPanel:ClearAllPoints()
	ghCooldownPanel:SetPoint('BOTTOMLEFT', ghPanel, 'BOTTOMRIGHT', 10, -5)
	ghInterruptPanel:ClearAllPoints()
	ghInterruptPanel:SetPoint('TOPLEFT', ghPanel, 'TOPRIGHT', 16, 25)
	ghExtraPanel:ClearAllPoints()
	ghExtraPanel:SetPoint('TOPRIGHT', ghPanel, 'TOPLEFT', -16, 25)
end

local resourceAnchor = {}

local ResourceFramePoints = {
	['blizzard'] = {
		[SPEC.BEASTMASTERY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.MARKSMANSHIP] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.SURVIVAL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		}
	},
	['kui'] = {
		[SPEC.BEASTMASTERY] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.MARKSMANSHIP] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
		},
		[SPEC.SURVIVAL] = {
			['above'] = { 'BOTTOM', 'TOP', 0, 41 },
			['below'] = { 'TOP', 'BOTTOM', 0, -16 }
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
		local p = ResourceFramePoints[resourceAnchor.name][currentSpec][Opt.snap]
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
		resourceAnchor.frame = NamePlatePlayerResourceFrame
	end
	resourceAnchor.frame:HookScript("OnHide", OnResourceFrameHide)
	resourceAnchor.frame:HookScript("OnShow", OnResourceFrameShow)
end

local function UpdateAlpha()
	ghPanel:SetAlpha(Opt.alpha)
	ghPreviousPanel:SetAlpha(Opt.alpha)
	ghCooldownPanel:SetAlpha(Opt.alpha)
	ghInterruptPanel:SetAlpha(Opt.alpha)
	ghExtraPanel:SetAlpha(Opt.alpha)
end

local function UpdateHealthArray()
	Target.healthArray = {}
	local i
	for i = 1, floor(3 / Opt.frequency) do
		Target.healthArray[i] = 0
	end
end

local function UpdateCombat()
	abilityTimer = 0
	UpdateVars()
	var.main = APL[currentSpec]:main()
	if var.main ~= var.last_main then
		if var.main then
			ghPanel.icon:SetTexture(var.main.icon)
			ghPanel.icon:Show()
			ghPanel.border:Show()
		else
			ghPanel.icon:Hide()
			ghPanel.border:Hide()
		end
	end
	if var.cd ~= var.last_cd then
		if var.cd then
			ghCooldownPanel.icon:SetTexture(var.cd.icon)
			ghCooldownPanel:Show()
		else
			ghCooldownPanel:Hide()
		end
	end
	if var.extra ~= var.last_extra then
		if var.extra then
			ghExtraPanel.icon:SetTexture(var.extra.icon)
			ghExtraPanel:Show()
		else
			ghExtraPanel:Hide()
		end
	end
	if Opt.dimmer then
		if not var.main then
			ghPanel.dimmer:Hide()
		elseif var.main.spellId and IsUsableSpell(var.main.spellId) then
			ghPanel.dimmer:Hide()
		elseif var.main.itemId and IsUsableItem(var.main.itemId) then
			ghPanel.dimmer:Hide()
		else
			ghPanel.dimmer:Show()
		end
	end
	if Opt.interrupt then
		UpdateInterrupt()
	end
	UpdateGlows()
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
			if start <= 0 then
				return ghPanel.swipe:Hide()
			end
		end
		ghPanel.swipe:SetCooldown(start, duration)
		ghPanel.swipe:Show()
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
		InitializeVariables()
		UpdateHealthArray()
		UpdateDraggable()
		UpdateAlpha()
		SnapAllPanels()
		ghPanel:SetScale(Opt.scale.main)
		ghPreviousPanel:SetScale(Opt.scale.previous)
		ghCooldownPanel:SetScale(Opt.scale.cooldown)
		ghInterruptPanel:SetScale(Opt.scale.interrupt)
		ghExtraPanel:SetScale(Opt.scale.extra)
	end
end

function events:COMBAT_LOG_EVENT_UNFILTERED()
	local timeStamp, eventType, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags, dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName = CombatLogGetCurrentEventInfo()
	if Opt.auto_aoe then
		if eventType == 'SWING_DAMAGE' or eventType == 'SWING_MISSED' then
			if dstGUID == var.player then
				autoAoe:add(srcGUID)
			elseif srcGUID == var.player then
				autoAoe:add(dstGUID)
			end
		elseif eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
			autoAoe:remove(dstGUID)
		end
	end
	if srcGUID ~= var.player and srcGUID ~= var.pet then
		return
	end
	local castedAbility = abilityBySpellId[spellId]
	if not castedAbility then
		return
	end
--[[ DEBUG ]
	print(format('EVENT %s TRACK CHECK FOR %s ID %d', eventType, spellName, spellId))
	if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' or eventType == 'SPELL_PERIODIC_DAMAGE' or eventType == 'SPELL_DAMAGE' then
		print(format('%s: %s - time: %.2f - time since last: %.2f', eventType, spellName, timeStamp, timeStamp - (castedAbility.last_trigger or timeStamp)))
		castedAbility.last_trigger = timeStamp
	end
--[ DEBUG ]]
	if eventType == 'SPELL_CAST_SUCCESS' then
		var.last_ability = castedAbility
		if castedAbility.triggers_gcd then
			PreviousGCD[10] = nil
			table.insert(PreviousGCD, 1, castedAbility)
		end
		if castedAbility.travel_start then
			castedAbility.travel_start[dstGUID] = GetTime()
		end
		if Opt.previous and ghPanel:IsVisible() then
			ghPreviousPanel.ability = castedAbility
			ghPreviousPanel.border:SetTexture('Interface\\AddOns\\GoodHunting\\border.blp')
			ghPreviousPanel.icon:SetTexture(castedAbility.icon)
			ghPreviousPanel:Show()
		end
		return
	end
	if eventType == 'SPELL_MISSED' or eventType == 'SPELL_DAMAGE' or eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
		if castedAbility.travel_start and castedAbility.travel_start[dstGUID] then
			castedAbility.travel_start[dstGUID] = nil
		end
		if Opt.auto_aoe and castedAbility.auto_aoe then
			castedAbility:recordTargetHit(dstGUID)
		end
		if Opt.previous and Opt.miss_effect and eventType == 'SPELL_MISSED' and ghPanel:IsVisible() and castedAbility == ghPreviousPanel.ability then
			ghPreviousPanel.border:SetTexture('Interface\\AddOns\\GoodHunting\\misseffect.blp')
		end
	end
	if castedAbility.aura_targets then
		if eventType == 'SPELL_AURA_APPLIED' or eventType == 'SPELL_AURA_REFRESH' then
			castedAbility:applyAura(dstGUID)
		elseif eventType == 'SPELL_AURA_REMOVED' or eventType == 'UNIT_DIED' or eventType == 'UNIT_DESTROYED' or eventType == 'UNIT_DISSIPATES' or eventType == 'SPELL_INSTAKILL' or eventType == 'PARTY_KILL' then
			castedAbility:removeAura(dstGUID)
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
		Target.hostile = true
		local i
		for i = 1, #Target.healthArray do
			Target.healthArray[i] = 0
		end
		if Opt.always_on then
			UpdateCombat()
			ghPanel:Show()
			return true
		end
		return
	end
	if guid ~= Target.guid then
		Target.guid = guid
		local i
		for i = 1, #Target.healthArray do
			Target.healthArray[i] = UnitHealth('target')
		end
	end
	Target.level = UnitLevel('target')
	if UnitIsPlayer('target') then
		Target.boss = false
	elseif Target.level == -1 then
		Target.boss = true
	elseif var.instance == 'party' and Target.level >= UnitLevel('player') + 2 then
		Target.boss = true
	else
		Target.boss = false
	end
	Target.hostile = UnitCanAttack('player', 'target') and not UnitIsDead('target')
	if Target.hostile or Opt.always_on then
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
	combatStartTime = GetTime()
end

function events:PLAYER_REGEN_ENABLED()
	combatStartTime = 0
	local _, ability, guid
	for _, ability in next, abilities do
		if ability.travel_start then
			for guid in next, ability.travel_start do
				ability.travel_start[guid] = nil
			end
		end
		if ability.aura_targets then
			for guid in next, ability.aura_targets do
				ability.aura_targets[guid] = nil
			end
		end
	end
	if Opt.auto_aoe then
		for guid in next, autoAoe.targets do
			autoAoe.targets[guid] = nil
		end
		GoodHunting_SetTargetMode(1)
	end
	if var.last_ability then
		var.last_ability = nil
		ghPreviousPanel:Hide()
	end
end

function events:PLAYER_EQUIPMENT_CHANGED()

end

function events:SPELL_UPDATE_ICON()
	if WildfireInfusion.known then
		WildfireInfusion:update()
	end
end

function events:PLAYER_SPECIALIZATION_CHANGED(unitName)
	if unitName == 'player' then
		local _, i
		for i = 1, #abilities do
			abilities[i].name, _, abilities[i].icon = GetSpellInfo(abilities[i].spellId)
			abilities[i].known = IsPlayerSpell(abilities[i].spellId) or (abilities[i].spellId2 and IsPlayerSpell(abilities[i].spellId2))
		end
		for i = 1, #inventoryItems do
			inventoryItems[i].name, _, _, _, _, _, _, _, _, inventoryItems[i].icon = GetItemInfo(inventoryItems[i].itemId)
		end
		ghPreviousPanel.ability = nil
		PreviousGCD = {}
		currentSpec = GetSpecialization() or 0
		GoodHunting_SetTargetMode(1)
		UpdateTargetInfo()
		events:SPELL_UPDATE_ICON()
	end
end

function events:PLAYER_ENTERING_WORLD()
	events:PLAYER_EQUIPMENT_CHANGED()
	events:PLAYER_SPECIALIZATION_CHANGED('player')
	if #glows == 0 then
		CreateOverlayGlows()
		HookResourceFrame()
	end
	local _
	_, var.instance = IsInInstance()
	var.player = UnitGUID('player')
	UpdateVars()
end

ghPanel.button:SetScript('OnClick', function(self, button, down)
	if down then
		if button == 'LeftButton' then
			GoodHunting_ToggleTargetMode()
		elseif button == 'RightButton' then
			GoodHunting_ToggleTargetModeReverse()
		elseif button == 'MiddleButton' then
			GoodHunting_SetTargetMode(1)
		end
	end
end)

ghPanel:SetScript('OnUpdate', function(self, elapsed)
	abilityTimer = abilityTimer + elapsed
	if abilityTimer >= Opt.frequency then
		trackAuras:purge()
		if Opt.auto_aoe then
			local _, ability
			for _, ability in next, autoAoe.abilities do
				ability:updateTargetsHit()
			end
			autoAoe:purge()
		end
		UpdateCombat()
	end
end)

ghPanel:SetScript('OnEvent', function(self, event, ...) events[event](self, ...) end)
local event
for event in next, events do
	ghPanel:RegisterEvent(event)
end

function SlashCmdList.GoodHunting(msg, editbox)
	msg = { strsplit(' ', strlower(msg)) }
	if startsWith(msg[1], 'lock') then
		if msg[2] then
			Opt.locked = msg[2] == 'on'
			UpdateDraggable()
		end
		return print('Good Hunting - Locked: ' .. (Opt.locked and '|cFF00C000On' or '|cFFC00000Off'))
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
		return print('Good Hunting - Snap to Blizzard combat resources frame: ' .. (Opt.snap and ('|cFF00C000' .. Opt.snap) or '|cFFC00000Off'))
	end
	if msg[1] == 'scale' then
		if startsWith(msg[2], 'prev') then
			if msg[3] then
				Opt.scale.previous = tonumber(msg[3]) or 0.7
				ghPreviousPanel:SetScale(Opt.scale.previous)
			end
			return print('Good Hunting - Previous ability icon scale set to: |cFFFFD000' .. Opt.scale.previous .. '|r times')
		end
		if msg[2] == 'main' then
			if msg[3] then
				Opt.scale.main = tonumber(msg[3]) or 1
				ghPanel:SetScale(Opt.scale.main)
			end
			return print('Good Hunting - Main ability icon scale set to: |cFFFFD000' .. Opt.scale.main .. '|r times')
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.scale.cooldown = tonumber(msg[3]) or 0.7
				ghCooldownPanel:SetScale(Opt.scale.cooldown)
			end
			return print('Good Hunting - Cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.cooldown .. '|r times')
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.scale.interrupt = tonumber(msg[3]) or 0.4
				ghInterruptPanel:SetScale(Opt.scale.interrupt)
			end
			return print('Good Hunting - Interrupt ability icon scale set to: |cFFFFD000' .. Opt.scale.interrupt .. '|r times')
		end
		if startsWith(msg[2], 'to') then
			if msg[3] then
				Opt.scale.extra = tonumber(msg[3]) or 0.4
				ghExtraPanel:SetScale(Opt.scale.extra)
			end
			return print('Good Hunting - Extra cooldown ability icon scale set to: |cFFFFD000' .. Opt.scale.extra .. '|r times')
		end
		if msg[2] == 'glow' then
			if msg[3] then
				Opt.scale.glow = tonumber(msg[3]) or 1
				UpdateGlowColorAndScale()
			end
			return print('Good Hunting - Action button glow scale set to: |cFFFFD000' .. Opt.scale.glow .. '|r times')
		end
		return print('Good Hunting - Default icon scale options: |cFFFFD000prev 0.7|r, |cFFFFD000main 1|r, |cFFFFD000cd 0.7|r, |cFFFFD000interrupt 0.4|r, |cFFFFD000extra 0.4|r, and |cFFFFD000glow 1|r')
	end
	if msg[1] == 'alpha' then
		if msg[2] then
			Opt.alpha = max(min((tonumber(msg[2]) or 100), 100), 0) / 100
			UpdateAlpha()
		end
		return print('Good Hunting - Icon transparency set to: |cFFFFD000' .. Opt.alpha * 100 .. '%|r')
	end
	if startsWith(msg[1], 'freq') then
		if msg[2] then
			Opt.frequency = tonumber(msg[2]) or 0.05
			UpdateHealthArray()
		end
		return print('Good Hunting - Calculation frequency: Every |cFFFFD000' .. Opt.frequency .. '|r seconds')
	end
	if startsWith(msg[1], 'glow') then
		if msg[2] == 'main' then
			if msg[3] then
				Opt.glow.main = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Good Hunting - Glowing ability buttons (main icon): ' .. (Opt.glow.main and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'cd' then
			if msg[3] then
				Opt.glow.cooldown = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Good Hunting - Glowing ability buttons (cooldown icon): ' .. (Opt.glow.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'int') then
			if msg[3] then
				Opt.glow.interrupt = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Good Hunting - Glowing ability buttons (interrupt icon): ' .. (Opt.glow.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'ex') then
			if msg[3] then
				Opt.glow.extra = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Good Hunting - Glowing ability buttons (extra icon): ' .. (Opt.glow.extra and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if startsWith(msg[2], 'bliz') then
			if msg[3] then
				Opt.glow.blizzard = msg[3] == 'on'
				UpdateGlows()
			end
			return print('Good Hunting - Blizzard default proc glow: ' .. (Opt.glow.blizzard and '|cFF00C000On' or '|cFFC00000Off'))
		end
		if msg[2] == 'color' then
			if msg[5] then
				Opt.glow.color.r = max(min(tonumber(msg[3]) or 0, 1), 0)
				Opt.glow.color.g = max(min(tonumber(msg[4]) or 0, 1), 0)
				Opt.glow.color.b = max(min(tonumber(msg[5]) or 0, 1), 0)
				UpdateGlowColorAndScale()
			end
			return print('Good Hunting - Glow color:', '|cFFFF0000' .. Opt.glow.color.r, '|cFF00FF00' .. Opt.glow.color.g, '|cFF0000FF' .. Opt.glow.color.b)
		end
		return print('Good Hunting - Possible glow options: |cFFFFD000main|r, |cFFFFD000cd|r, |cFFFFD000interrupt|r, |cFFFFD000extra|r, |cFFFFD000blizzard|r, and |cFFFFD000color')
	end
	if startsWith(msg[1], 'prev') then
		if msg[2] then
			Opt.previous = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Good Hunting - Previous ability icon: ' .. (Opt.previous and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'always' then
		if msg[2] then
			Opt.always_on = msg[2] == 'on'
			UpdateTargetInfo()
		end
		return print('Good Hunting - Show the Good Hunting UI without a target: ' .. (Opt.always_on and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'cd' then
		if msg[2] then
			Opt.cooldown = msg[2] == 'on'
		end
		return print('Good Hunting - Use Good Hunting for cooldown management: ' .. (Opt.cooldown and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'swipe' then
		if msg[2] then
			Opt.spell_swipe = msg[2] == 'on'
			if not Opt.spell_swipe then
				ghPanel.swipe:Hide()
			end
		end
		return print('Good Hunting - Spell casting swipe animation: ' .. (Opt.spell_swipe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'dim') then
		if msg[2] then
			Opt.dimmer = msg[2] == 'on'
			if not Opt.dimmer then
				ghPanel.dimmer:Hide()
			end
		end
		return print('Good Hunting - Dim main ability icon when you don\'t have enough focus to use it: ' .. (Opt.dimmer and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'miss' then
		if msg[2] then
			Opt.miss_effect = msg[2] == 'on'
		end
		return print('Good Hunting - Red border around previous ability when it fails to hit: ' .. (Opt.miss_effect and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'aoe' then
		if msg[2] then
			Opt.aoe = msg[2] == 'on'
			GoodHunting_SetTargetMode(1)
			UpdateDraggable()
		end
		return print('Good Hunting - Allow clicking main ability icon to toggle amount of targets (disables moving): ' .. (Opt.aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'bossonly' then
		if msg[2] then
			Opt.boss_only = msg[2] == 'on'
		end
		return print('Good Hunting - Only use cooldowns on bosses: ' .. (Opt.boss_only and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'hidespec' or startsWith(msg[1], 'spec') then
		if msg[2] then
			if startsWith(msg[2], 'b') then
				Opt.hide.beastmastery = not Opt.hide.beastmastery
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Good Hunting - BeastMastery specialization: |cFFFFD000' .. (Opt.hide.beastmastery and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 'm') then
				Opt.hide.marksmanship = not Opt.hide.marksmanship
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Good Hunting - Marksmanship specialization: |cFFFFD000' .. (Opt.hide.marksmanship and '|cFFC00000Off' or '|cFF00C000On'))
			end
			if startsWith(msg[2], 's') then
				Opt.hide.survival = not Opt.hide.survival
				events:PLAYER_SPECIALIZATION_CHANGED('player')
				return print('Good Hunting - Survival specialization: |cFFFFD000' .. (Opt.hide.survival and '|cFFC00000Off' or '|cFF00C000On'))
			end
		end
		return print('Good Hunting - Possible hidespec options: |cFFFFD000beastmastery|r/|cFFFFD000marksmanship|r/|cFFFFD000survival|r - toggle disabling Good Hunting for specializations')
	end
	if startsWith(msg[1], 'int') then
		if msg[2] then
			Opt.interrupt = msg[2] == 'on'
		end
		return print('Good Hunting - Show an icon for interruptable spells: ' .. (Opt.interrupt and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'auto' then
		if msg[2] then
			Opt.auto_aoe = msg[2] == 'on'
		end
		return print('Good Hunting - Automatically change target mode on AoE spells: ' .. (Opt.auto_aoe and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if msg[1] == 'ttl' then
		if msg[2] then
			Opt.auto_aoe_ttl = tonumber(msg[2]) or 10
		end
		return print('Good Hunting - Length of time target exists in auto AoE after being hit: |cFFFFD000' .. Opt.auto_aoe_ttl .. '|r seconds')
	end
	if startsWith(msg[1], 'pot') then
		if msg[2] then
			Opt.pot = msg[2] == 'on'
		end
		return print('Good Hunting - Show Battle potions in cooldown UI: ' .. (Opt.pot and '|cFF00C000On' or '|cFFC00000Off'))
	end
	if startsWith(msg[1], 'mend') then
		if msg[2] then
			Opt.mend_threshold = tonumber(msg[2]) or 65
		end
		return print('Good Hunting - Recommend Mend Pet when pet\'s health is below: |cFFFFD000' .. Opt.mend_threshold .. '|r%')
	end
	if msg[1] == 'reset' then
		ghPanel:ClearAllPoints()
		ghPanel:SetPoint('CENTER', 0, -169)
		SnapAllPanels()
		return print('Good Hunting - Position has been reset to default')
	end
	print('Good Hunting (version: |cFFFFD000' .. GetAddOnMetadata('GoodHunting', 'Version') .. '|r) - Commands:')
	local _, cmd
	for _, cmd in next, {
		'locked |cFF00C000on|r/|cFFC00000off|r - lock the Good Hunting UI so that it can\'t be moved',
		'snap |cFF00C000above|r/|cFF00C000below|r/|cFFC00000off|r - snap the Good Hunting UI to the Blizzard combat resources frame',
		'scale |cFFFFD000prev|r/|cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000glow|r - adjust the scale of the Good Hunting UI icons',
		'alpha |cFFFFD000[percent]|r - adjust the transparency of the Good Hunting UI icons',
		'frequency |cFFFFD000[number]|r - set the calculation frequency (default is every 0.05 seconds)',
		'glow |cFFFFD000main|r/|cFFFFD000cd|r/|cFFFFD000interrupt|r/|cFFFFD000extra|r/|cFFFFD000blizzard|r |cFF00C000on|r/|cFFC00000off|r - glowing ability buttons on action bars',
		'glow color |cFFF000000.0-1.0|r |cFF00FF000.1-1.0|r |cFF0000FF0.0-1.0|r - adjust the color of the ability button glow',
		'previous |cFF00C000on|r/|cFFC00000off|r - previous ability icon',
		'always |cFF00C000on|r/|cFFC00000off|r - show the Good Hunting UI without a target',
		'cd |cFF00C000on|r/|cFFC00000off|r - use Good Hunting for cooldown management',
		'swipe |cFF00C000on|r/|cFFC00000off|r - show spell casting swipe animation on main ability icon',
		'dim |cFF00C000on|r/|cFFC00000off|r - dim main ability icon when you don\'t have enough focus to use it',
		'miss |cFF00C000on|r/|cFFC00000off|r - red border around previous ability when it fails to hit',
		'aoe |cFF00C000on|r/|cFFC00000off|r - allow clicking main ability icon to toggle amount of targets (disables moving)',
		'bossonly |cFF00C000on|r/|cFFC00000off|r - only use cooldowns on bosses',
		'hidespec |cFFFFD000beastmastery|r/|cFFFFD000marksmanship|r/|cFFFFD000survival|r - toggle disabling Good Hunting for specializations',
		'interrupt |cFF00C000on|r/|cFFC00000off|r - show an icon for interruptable spells',
		'auto |cFF00C000on|r/|cFFC00000off|r  - automatically change target mode on AoE spells',
		'ttl |cFFFFD000[seconds]|r  - time target exists in auto AoE after being hit (default is 10 seconds)',
		'pot |cFF00C000on|r/|cFFC00000off|r - show Battle potions in cooldown UI',
		'mend |cFFFFD000[percent]|r  - health percentage to recommend Mend Pet at (default is 65%, 0 to disable)',
		'|cFFFFD000reset|r - reset the location of the Good Hunting UI to default',
	} do
		print('  ' .. SLASH_GoodHunting1 .. ' ' .. cmd)
	end
	print('Got ideas for improvement or found a bug? Contact |cFFABD473Waylay|cFFFFD000-Dalaran|r or |cFFFFD000Spy#1955|r (the author of this addon)')
end
