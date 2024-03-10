#include <sourcemod>
#include <dhooks>

#include <neotokyo>

#pragma semicolon 1
#pragma newdecls required


#define PLUGIN_VERSION "0.2.1"

#define MAX_SMOKES NEO_MAXPLAYERS*2
#define SMOKE_FADE_DURATION 2.0 // Time it takes for smoke to fully fade in/out
#define SMOKE_FULL_BLOOM_DURATION 17.5 // The full vision obscure duration
#define SMOKE_FULL_BLOOM_RADIUS 180.0 // The full vision obscure radius
#define TIMER_INACCURACY 0.1

#define HEAL_INTERVAL 1.0
#define HEAL_PER_SECOND 5.0
#define HURT_INTERVAL 1.0

#define FFADE_IN 0x1
#define FFADE_OUT 0x2
#define FFADE_MODULATE 0x4

#if SOURCEMOD_V_MAJOR > 1 || (SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR >= 11)
#assert HEAL_INTERVAL > 0.0 // Avoid div by zero
#assert HEAL_PER_SECOND >= 0.0 // Negative healing is unsupported
#endif

public Plugin myinfo = {
	name = "NT Healing Smokes",
	description = "Experimental plugin. Healing smoke grenades for Neotokyo.",
	author = "Rain",
	version = PLUGIN_VERSION,
	url = "https://github.com/Rainyan/sourcemod-nt-smokeheal"
};

float _last_heal[NEO_MAXPLAYERS+1];
float _last_hurt[NEO_MAXPLAYERS+1];

enum SmokeStatus {
	FADE_IN, // Smoke is currently deploying, but not full bloomed yet.
	FULL_BLOOM, // Smoke is completely obscuring vision.
	FADE_OUT, // Smoke is fading out.
	EXPIRED // Smoke has completely expired.
}

enum struct Smoke {
	float start_time;
	float pos[3];

	// Return the SmokeStatus enumeration associated with this smoke.
	SmokeStatus GetStatus()
	{
		float dt = GetGameTime() - this.start_time;
		if (dt < 0)
		{
			return EXPIRED;
		}
		if (dt < SMOKE_FADE_DURATION)
		{
			return FADE_IN;
		}
		if (dt < SMOKE_FADE_DURATION + SMOKE_FULL_BLOOM_DURATION)
		{
			return FULL_BLOOM;
		}
		if (dt < SMOKE_FADE_DURATION*2 + SMOKE_FULL_BLOOM_DURATION)
		{
			return FADE_OUT;
		}
		return EXPIRED;
	}

	// For a valid client, return whether their eye position is within
	// the radius of this smoke.
	bool IsInRadius(int client)
	{
		float pos[3];
		GetClientEyePosition(client, pos);
		return SMOKE_FULL_BLOOM_RADIUS > GetVectorDistance(pos, this.pos, false);
	}

	// Heal every alive client inside this smoke's radius.
	void RadiusHeal()
	{
		int heal_amount = RoundToNearest(HEAL_PER_SECOND / HEAL_INTERVAL);
		float time = GetGameTime();
		for (int client = 1; client <= MaxClients; ++client)
		{
			if (!IsClientInGame(client) || !IsPlayerAlive(client) ||
				!this.IsInRadius(client))
			{
				continue;
			}
			// Prevent stacking heals
			float dt = time - _last_heal[client];
			if (dt < HEAL_INTERVAL - TIMER_INACCURACY)
			{
				continue;
			}
			// Prevent healing until HURT_INTERVAL since last taking damage
			dt = time - _last_hurt[client];
			if (dt < HURT_INTERVAL - TIMER_INACCURACY)
			{
				continue;
			}
			Heal(client, heal_amount);
			_last_heal[client] = time;
		}
	}
}
ArrayList _smokes = null;

public void OnPluginStart()
{
	Handle dd = new DynamicDetour(view_as<Address>(0x22107C40),
		CallConv_THISCALL, ReturnType_Void, ThisPointer_CBaseEntity);
	if (dd == INVALID_HANDLE)
	{
		SetFailState("Failed to create dynamic hook");
	}
	if (!DHookEnableDetour(dd, true, Detonate))
	{
		SetFailState("Failed to detour");
	}
	CloseHandle(dd);

	if (!HookEventEx("player_hurt", OnPlayerHurt))
	{
		SetFailState("Failed to hook");
	}

	CreateTimer(HEAL_INTERVAL, Timer_Heal, _, TIMER_REPEAT);
}

void OnPlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	int victim = GetClientOfUserId(event.GetInt("userid"));
	_last_hurt[victim] = GetGameTime();
}

public void OnClientDisconnect(int client)
{
	_last_heal[client] = 0.0;
	_last_hurt[client] = 0.0;
}

public void OnMapStart()
{
	delete _smokes;
	// TODO: optimize!
	// We could preallocate, and loop through known amt of pushed values
	// on the stack, for example checking for 0 start time,
	// to entirely avoid heap reallocations.
	_smokes = new ArrayList(sizeof(Smoke));//, MAX_SMOKES);

	for (int i = 0; i < sizeof(_last_heal); ++i)
	{
		_last_heal[i] = 0.0;
		_last_hurt[i] = 0.0;
	}
}

// Periodically heal players who are inside a smoke,
// and remove expired smokes from the stack.
public Action Timer_Heal(Handle timer)
{
	Smoke smoke;
	for (int i = 0; i < _smokes.Length; ++i)
	{
		_smokes.GetArray(i, smoke);

		SmokeStatus status = smoke.GetStatus();
		if (status == EXPIRED)
		{
			_smokes.Erase(i--); // TODO: optimize
			continue;
		}
		if (status == FULL_BLOOM)
		{
			smoke.RadiusHeal();
		}
	}
	return Plugin_Continue;
}

bool IsSmokeProjectile(int basegrenade)
{
	char classname[32];
	if (!GetEntityClassname(basegrenade, classname, sizeof(classname)))
	{
		return false;
	}
	return StrEqual(classname, "smokegrenade_projectile");
}

MRESReturn Detonate(int pThis)
{
	// Some other kind of projectile going off
	if (!IsSmokeProjectile(pThis))
	{
		return MRES_Ignored;
	}

	Smoke smoke;
	GetEntPropVector(pThis, Prop_Send, "m_vecOrigin", smoke.pos);
	smoke.start_time = GetGameTime();

	_smokes.PushArray(smoke); // TODO: optimize

	return MRES_Ignored;
}

any Min(any a, any b)
{
	return a < b ? a : b;
}

// For a valid alive client, adds "amount" to their health value.
// Assumes positive healing amount (we don't handle death by "negative heal").
void Heal(int client, int amount)
{
	int health = Min(100, GetEntProp(client, Prop_Send, "m_iHealth") + amount);
	SetEntProp(client, Prop_Send, "m_iHealth", health);

	int color[4] = {
		0, 255, 0, 12
	};
	FlashScreen(client, color);
}

void FlashScreen(int client, int rgba[4])
{
	int in_time_ms = 66;
	int hold_time_ms = 666;
	Handle msg = StartMessageOne("Fade", client);
	BfWriteShort(msg, in_time_ms);
	BfWriteShort(msg, hold_time_ms);
	BfWriteShort(msg, FFADE_IN);
	BfWriteByte(msg, rgba[0]);
	BfWriteByte(msg, rgba[1]);
	BfWriteByte(msg, rgba[2]);
	BfWriteByte(msg, rgba[3]);
	EndMessage();
}