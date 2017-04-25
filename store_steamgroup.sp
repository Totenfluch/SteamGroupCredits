#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <SteamWorks>
#include <store>
#include <multicolors>
#include <autoexecconfig>

Handle g_DB;

bool g_bIsInGroup[MAXPLAYERS + 1];
int g_iIsLocked[MAXPLAYERS + 1];

Handle g_hTag;
char g_cTag[128];

Handle g_hDBConfig;
char g_cDBConfig[128];

Handle g_hCreditsAmount;
int g_iCreditsAmount = 2500;

ConVar g_hGroupId;

/*
	ADD YOUR GROUP ID IN LINE 78 AND 86 !!!
*/
public Plugin myinfo = 
{
	name = "SteamGroup Credits", 
	author = "Totenfluch", 
	description = "Gives your Credits when you are in the Steam Group", 
	version = "3.0", 
	url = "http://ggc-base.de"
};

public void OnPluginStart()
{
	RegConsoleCmd("sm_claim", cmdClaimCredits, "Claims the credits for joining the group");
	
	AutoExecConfig_SetFile("steamGroupCredits");
	AutoExecConfig_SetCreateFile(true);
	
	g_hTag = AutoExecConfig_CreateConVar("group_chattag", "Group", "sets the chat tag before every message for the Group Plugin");
	g_hDBConfig = AutoExecConfig_CreateConVar("group_dbconfig", "group", "database config (MySQL) to use for this plugin");
	g_hGroupId = AutoExecConfig_CreateConVar("group_groupid", "103582791431203171", "Your Group ID in the format as default");
	g_hCreditsAmount = AutoExecConfig_CreateConVar("group_credits", "2500", "Amount of Credits a Player gets for joining the group");
	
	AutoExecConfig_CleanFile();
	AutoExecConfig_ExecuteFile();
	
	GetConVarString(g_hDBConfig, g_cDBConfig, sizeof(g_cDBConfig));
	
	char error[256];
	g_DB = SQL_Connect("gsxh_multiroot", true, error, sizeof(error));
	if (g_DB == INVALID_HANDLE) {
		char failstate[128];
		Format(failstate, sizeof(failstate), "You Database Config (%s) is invalid", g_cDBConfig);
		SetFailState(failstate);
	}
	SQL_SetCharset(g_DB, "utf8");
	char query[512];
	Format(query, sizeof(query), "CREATE TABLE IF NOT EXISTS `SteamGroupCredits` (`thekey` bigint(20) NOT NULL AUTO_INCREMENT, `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, `playerid` varchar(20) NOT NULL, `amount` int(11) NOT NULL, PRIMARY KEY (`thekey`)) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=latin1;");
	char error2[255];
	if (!SQL_FastQuery(g_DB, query)) {
		SQL_GetError(g_DB, error2, sizeof(error2));
		PrintToServer("Failed to query (error: %s)", error2);
	}
}

public void OnConfigsExecuted() {
	GetConVarString(g_hTag, g_cTag, sizeof(g_cTag));
	g_iCreditsAmount = GetConVarInt(g_hCreditsAmount);
}

public Action cmdClaimCredits(int client, int args) {
	SteamWorks_GetUserGroupStatus(client, 103582791431203171);
	checkIfGottenCredits(client);
	return Plugin_Handled;
}

public void OnClientPutInServer(int client)
{
	g_iIsLocked[client] = 0;
	SteamWorks_GetUserGroupStatus(client, 103582791431203171);
}

public void OnClientDisconnect(int client) {
	g_iIsLocked[client] = 0;
	g_bIsInGroup[client] = false;
}

public int SteamWorks_OnClientGroupStatus(int authid, int groupid, bool isMember, bool isOfficer)
{
	int client = GetUserFromAuthID(authid);
	if (isMember || isOfficer)
	{
		g_bIsInGroup = true;
		if (isValidClient(client)) {
			if (IsClientInGame(client) && !IsFakeClient(client) && Store_IsClientLoaded(client)) {
				
				char query[255];
				char client_id[20];
				GetClientAuthId(client, AuthId_Steam2, client_id, sizeof(client_id));
				Format(query, sizeof(query), "SELECT COUNT(*) FROM SteamGroupCredits WHERE playerid = '%s'", client_id);
				SQL_TQuery(g_DB, sql_CheckGroupCallback, query, GetClientUserId(client));
			}
		}
	}
	return 0;
}

public void checkIfGottenCredits(int client) {
	char client_id[20];
	GetClientAuthId(client, AuthId_Steam2, client_id, sizeof(client_id));
	char query[256];
	Format(query, sizeof(query), "SELECT timestamp,amount FROM SteamGroupCredits WHERE playerid = '%s'", client_id);
	SQL_TQuery(g_DB, sql_alreadyGottenCreditsQuery, query, client);
}

public void sql_alreadyGottenCreditsQuery(Handle owner, Handle hndl, const char[] error, any client) {
	if (hndl != INVALID_HANDLE) {
		while (SQL_FetchRow(hndl)) {
			char timestamp[128];
			SQL_FetchString(hndl, 0, timestamp, sizeof(timestamp));
			int amount = SQL_FetchInt(hndl, 1);
			CPrintToChat(client, "{green}[{purple}%s{green}]{lightred} Du hast bereits {green}%i Credits{lightred} zu dem Zeitpunkt: {green}%s{lightred} erhalten.", g_cTag, amount, timestamp);
		}
	}
}

public void sql_CheckGroupCallback(Handle owner, Handle hndl, const char[] error, any userid)
{
	if (hndl != INVALID_HANDLE)
	{
		int client = GetClientOfUserId(userid);
		while (SQL_FetchRow(hndl))
		{
			int grp = SQL_FetchInt(hndl, 0);
			if (grp > 0) {
				return;
			}
		}
		if (g_iIsLocked[client] == 1)
			return;
		
		g_iIsLocked[client] = 1;
		
		Store_SetClientCredits(client, Store_GetClientCredits(client) + g_iCreditsAmount);
		CPrintToChat(client, "{green}[{purple}%s{green}]{orange} Du hast {green}%i{orange} Credits bekommen, da du unserer Steam Gruppe beigetreten bist!", g_cTag, g_iCreditsAmount);
		char query[255];
		char c_id[20];
		GetClientAuthId(client, AuthId_Steam2, c_id, sizeof(c_id));
		Format(query, sizeof(query), "INSERT INTO `SteamGroupCredits` (`thekey`, `timestamp`, `playerid`, `amount`) VALUES (NULL, CURRENT_TIMESTAMP, '%s', '%i')", c_id, g_iCreditsAmount);
		SQL_TQuery(g_DB, sql_TQueryCallback, query);
	}
}

public int GetUserFromAuthID(int authid) {
	for (int i = 1; i < MAXPLAYERS + 1; i++) {
		if (isValidClient(i)) {
			char authstring[50];
			GetClientAuthId(i, AuthId_Steam3, authstring, sizeof(authstring));
			
			char authstring2[50];
			IntToString(authid, authstring2, sizeof(authstring2));
			
			if (StrContains(authstring, authstring2) != -1)
			{
				return i;
			}
		}
	}
	
	return -1;
}

public bool isValidClient(int client)
{
	if (!(1 <= client <= MaxClients) || !IsClientInGame(client))
		return false;
	
	return true;
}

public void sql_TQueryCallback(Handle owner, Handle hndl, const char[] error, any userid)
{
	if (!StrEqual(error, ""))
		LogError("SQL Error: %s", error);
} 