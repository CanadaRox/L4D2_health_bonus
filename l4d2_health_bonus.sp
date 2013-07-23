#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <left4downtown>

public Plugin:myinfo = {
	name = "Health Bonus",
	author = "Grego, CanadaRox",
	description = "Health Bonus",
	version = "0.2",
	url = ""
};

// Stores the default tie bonus/survival, in case of disabling the plugin
new defaultSurvivalBonus;
new defaultTieBreaker;

// Flags indicating the state of the plugin
new bool:isHealthBonusEnabled;
new bool:pluginEnabled = false;

// Saves first round score
new bool:firstRoundOver = false;
new firstRoundScore;

// Plugin cvars
new Handle:enableHealthBonusCvar;
new Handle:permanentHealthBonusPointsCvar;
new permanentHealthBonusPoints;
new Handle:temporaryHealthBonusPointsCvar;
new temporaryHealthBonusPoints;

new Handle:medkitPointValueCvar;
new medkitPointValue;
new Handle:defibPointValueCvar;
new defibPointValue;
new Handle:pillPointValueCvar;
new pillPointValue;
new Handle:adrenPointValueCvar;
new adrenPointValue;

// Default bonus cvars
new Handle:survivalBonusCvar;
new Handle:tieBreakerCvar;

// Cvars to read values from
new Handle:maxIncapCvar;
new maxIncapCount;
new Handle:postIncapHealthCvar;
new postIncapHealth;

public OnPluginStart() {
	enableHealthBonusCvar = CreateConVar("hb_enable", "1", "Health Bonus - Enable/Disable", FCVAR_PLUGIN);
	HookConVarChange(enableHealthBonusCvar, HandleHealthBonusEnableChangeEvent);

	permanentHealthBonusPointsCvar = CreateConVar("hb_permanent_health_bonus_points", "0.5", "Number of bonus points to receive for a permanent health point.", FCVAR_PLUGIN, true, 0.0);
	permanentHealthBonusPoints = GetConVarInt(permanentHealthBonusPointsCvar);

	temporaryHealthBonusPointsCvar = CreateConVar("hb_temporary_health_bonus_points", "0.25", "Number of bonus points to receive for a temporary health point.", FCVAR_PLUGIN, true, 0.0);
	temporaryHealthBonusPoints = GetConVarInt(temporaryHealthBonusPointsCvar);

	medkitPointValueCvar = CreateConVar("hb_medkit_point_value", "80", "Number of pre-scaling points to reward for a medkit", FCVAR_PLUGIN, true, 0.0);
	medkitPointValue = GetConVarInt(medkitPointValueCvar);
	defibPointValueCvar = CreateConVar("hb_defib_point_value", "50", "Number of pre-scaling points to reward for a defib", FCVAR_PLUGIN, true, 0.0);
	defibPointValue = GetConVarInt(defibPointValueCvar);
	pillPointValueCvar = CreateConVar("hb_pill_point_value", "50", "Number of pre-scaling points to reward for pain pills", FCVAR_PLUGIN, true, 0.0);
	pillPointValue = GetConVarInt(pillPointValueCvar);
	adrenPointValueCvar = CreateConVar("hb_adren_point_value", "25", "Number of pre-scaling points to reward for adrenaline", FCVAR_PLUGIN, true, 0.0);
	adrenPointValue = GetConVarInt(adrenPointValueCvar);

	HookConVarChange(permanentHealthBonusPointsCvar, CvarChanged);
	HookConVarChange(temporaryHealthBonusPointsCvar, CvarChanged);
	HookConVarChange(medkitPointValueCvar, CvarChanged);
	HookConVarChange(defibPointValueCvar, CvarChanged);
	HookConVarChange(pillPointValueCvar, CvarChanged);
	HookConVarChange(adrenPointValueCvar, CvarChanged);

	survivalBonusCvar = FindConVar("vs_survival_bonus");
	tieBreakerCvar = FindConVar("vs_tiebreak_bonus");
	maxIncapCvar = FindConVar("survivor_max_incapacitated_count");
	postIncapHealthCvar = FindConVar("survivor_revive_health");

	defaultSurvivalBonus = GetConVarInt(survivalBonusCvar);
	defaultTieBreaker = GetConVarInt(tieBreakerCvar);
	maxIncapCount = GetConVarInt(maxIncapCvar);
	postIncapHealth = GetConVarInt(postIncapHealthCvar);

	RegConsoleCmd("sm_health", PrintHealth);
}

public OnPluginEnd() {
	PluginDisable(false);
}

PluginEnable() {
	HookEvent("door_close", HandleDoorCloseEvent);
	HookEvent("player_death", HandlePlayerDeathEvent);
	HookEvent("round_end", HandleRoundEndEvent);
	HookEvent("finale_vehicle_leaving", HandleFinaleVehicleLeavingEvent, EventHookMode_PostNoCopy);
	RegConsoleCmd("say", SayCommandIntercept);
	RegConsoleCmd("say_team", SayCommandIntercept);
	defaultSurvivalBonus = GetConVarInt(survivalBonusCvar);
	defaultTieBreaker = GetConVarInt(tieBreakerCvar);
	maxIncapCount = GetConVarInt(maxIncapCvar);
	postIncapHealth = GetConVarInt(postIncapHealthCvar);
	SetConVarInt(tieBreakerCvar, 0);
	pluginEnabled = true;
}

PluginDisable(bool:unhook=true) {
	if(unhook) {
		UnhookEvent("door_close", HandleDoorCloseEvent);
		UnhookEvent("player_death", HandlePlayerDeathEvent);
		UnhookEvent("round_end", HandleRoundEndEvent, EventHookMode_PostNoCopy);
		UnhookEvent("finale_vehicle_leaving", HandleFinaleVehicleLeavingEvent, EventHookMode_PostNoCopy);
	}
	SetConVarInt(survivalBonusCvar, defaultSurvivalBonus);
	SetConVarInt(tieBreakerCvar, defaultTieBreaker);
	pluginEnabled = false;
}

public OnMapStart() {
	isHealthBonusEnabled = GetConVarBool(enableHealthBonusCvar);
	
	if (isHealthBonusEnabled) {
		if (!pluginEnabled) {
			PluginEnable();
		}
		SetConVarInt(tieBreakerCvar, 0);
	}
	
	firstRoundOver = false;
	firstRoundScore = 0;
}

public Action:HandleRoundEndEvent(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!isHealthBonusEnabled) return;

	if(!firstRoundOver) {
		// First round just ended, save the current score.
		firstRoundOver = true;
		firstRoundScore = CalculateDisplayBonus();
		
		PrintToChatAll("[HB] Round 1 Bonus: %d", firstRoundScore);
	} else {
		// Second round has ended, print scores
		new secondRoundScore = CalculateDisplayBonus();
		PrintToChatAll("[HB] Round 1 Bonus: %d", firstRoundScore);
		PrintToChatAll("[HB] Round 2 Bonus: %d", secondRoundScore);
	}
}

public HandleHealthBonusEnableChangeEvent(Handle:convar, const String:oldValue[], const String:newValue[]) {
	if (StringToInt(newValue) == 0) {
		PluginDisable();
		isHealthBonusEnabled = false;
	} else {
		PluginEnable();
		isHealthBonusEnabled = true;
	}
}

public CvarChanged(Handle:convar, const String:oldValue[], const String:newValue[]) {
	if (convar == medkitPointValueCvar) {
		medkitPointValue = GetConVarInt(medkitPointValueCvar);
	} else if (convar == defibPointValueCvar) {
		defibPointValue = GetConVarInt(defibPointValueCvar);
	} else if (convar == pillPointValueCvar) {
		pillPointValue = GetConVarInt(pillPointValueCvar);
	} else if (convar == adrenPointValueCvar) {
		adrenPointValue = GetConVarInt(adrenPointValueCvar);
	}
}

public Action:HandleDoorCloseEvent(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!isHealthBonusEnabled) return;

	if (GetEventBool(event, "checkpoint")) {
		SetConVarInt(survivalBonusCvar, RoundToFloor(CalculateHealthBonus()));
	}
}

public Action:HandlePlayerDeathEvent(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!isHealthBonusEnabled) return;

	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	// Can't just check for fakeclient
	if(client && GetClientTeam(client) == 2) {
		SetConVarInt(survivalBonusCvar, RoundToFloor(CalculateHealthBonus()));
	}
}

public Action:HandleFinaleVehicleLeavingEvent(Handle:event, const String:name[], bool:dontBroadcast) {
	if (!isHealthBonusEnabled) return;
	
	SetConVarInt(survivalBonusCvar, RoundToFloor(CalculateHealthBonus()));
}

public Action:SayCommandIntercept(client, args) {
	if (!isHealthBonusEnabled) return Plugin_Continue;
	
	decl String:message[MAX_NAME_LENGTH];
	GetCmdArg(1, message, sizeof(message));
	
	if (StrEqual(message, "!health")) return Plugin_Handled;
	
	return Plugin_Continue;
}

public Action:PrintHealth(client, args) {
	if (!isHealthBonusEnabled) return;
	
	if (firstRoundOver) {
		PrintToChat(client, "[HB] Round 1 Bonus: %d", firstRoundScore);
	}
	
	new currentScore = CalculateDisplayBonus();
	
	if (client) {
		PrintToChat(client, "[HB] Health Bonus: %d", currentScore);
	} else {
		PrintToServer("[HB] Health Bonus: %d", currentScore);
	}
}

CalculateDisplayBonus() {
	decl aliveSurvivors;
	new Float:healthBonus = CalculateHealthBonus(aliveSurvivors);
	return RoundToFloor(healthBonus * float(aliveSurvivors));
}

Float:CalculateHealthBonus(&aliveSurvivors=0) {
	new totalPermHealth = 0;
	new totalTempHealth = 0;

	for (new index = 1; index <= MaxClients; index++) {
		if (IsSurvivor(index) && IsPlayerAlive(index) && !IsPlayerIncapped(index)) {
			totalPermHealth += GetSurvivorPermanentHealth(index);

			totalTempHealth += GetSurvivorTempHealth(index);

			totalTempHealth += (maxIncapCount - GetSurvivorIncapCount(index)) * postIncapHealth;

			if (SurvivorHasHealthPack(index)) {
				totalPermHealth += medkitPointValue;
			} else if (SurvivorHasDefibrillator(index)) {
				totalPermHealth += defibPointValue;
			}

			if (SurvivorHasPills(index)) {
				totalTempHealth += pillPointValue;
			} else if (SurvivorHasShot(index)) {
				totalTempHealth += adrenPointValue;

				aliveSurvivors++;
			}
		}
	}
	return (float(totalPermHealth) * permanentHealthBonusPoints+ float(totalTempHealth) * temporaryHealthBonusPoints);
}

bool:IsPlayerIncapped(client) {
	return GetEntProp(client, Prop_Send, "m_isIncapacitated") == 1;
}

bool:IsSurvivor(client) {
	return IsClientInGame(client) && GetClientTeam(client) == 2;
}

GetSurvivorPermanentHealth(client) {
    return GetEntProp(client, Prop_Send, "m_iHealth");
}

GetSurvivorTempHealth(client) {
	new temphp =  RoundToFloor(GetEntPropFloat(client, Prop_Send, "m_healthBuffer") - ((GetGameTime() - GetEntPropFloat(client, Prop_Send, "m_healthBufferTime")) * GetConVarFloat(pain_pills_decay_rate)));
	return (temphp > 0 ? temphp : 0)
}

GetSurvivorIncapCount(client) {
    return GetEntProp(client, Prop_Send, "m_currentReviveCount");
}

bool:SurvivorHasHealthPack(client) {
	return SurvivorHasItemAtSlot(client, 3, "weapon_first_aid_kit");
}

bool:SurvivorHasDefibrillator(client) {
	return SurvivorHasItemAtSlot(client, 3, "weapon_defibrillator");
}

bool:SurvivorHasPills(client) {
	return SurvivorHasItemAtSlot(client, 4, "weapon_pain_pills");
}

bool:SurvivorHasShot(client) {
	return SurvivorHasItemAtSlot(client, 4, "weapon_adrenaline");
}

bool:SurvivorHasItemAtSlot(client, slotIndex, String:itemName[50]) {
	decl String:strTemp[50];
	new iTemp = GetPlayerWeaponSlot(client, slotIndex);
	if (iTemp > -1) {
		GetEdictClassname(iTemp, strTemp, sizeof(strTemp));
		return StrEqual(strTemp, itemName);
	}
	return false;
}
