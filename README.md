# sourcemod-nt-smokeheal
Experimental plugin that adds healing smoke grenades to Neotokyo.
The healing takes place only inside the fully bloomed area of a smoke,
and ignores teams (i.e. you can heal inside an enemy smoke).

## Build requirements
* SourceMod version 1.10 or newer
  * If using SourceMod older than 1.11: you also need the [DHooks extension](https://forums.alliedmods.net/showpost.php?p=2588686).
Download links are at the bottom of the opening post of the AlliedMods thread.
Be sure to choose the correct one for your SM version! You don't need this if you're using SourceMod 1.11 or newer.
* The [Neotokyo include](https://github.com/softashell/sourcemod-nt-include/blob/master/scripting/include/neotokyo.inc)

## Usage
### Cvars
* sm_smokeheal_hps
  * Default value: `5.0`
  * Description: `Amount to heal per second.`
  * Min: `0.0`
* sm_smokeheal_cooldown
  * Default value: `1.0`
  * Description: `Cooldown since player hurt until they can start healing.`
  * Min: `0.0`
* sm_smokeheal_supheal
  * Default value: `1`
  * Description: `Modifier for the heal amount for support targets.`
  * Min: `0.0`
  * Max: `1.0`
* sm_smokeheal_maxheal
  * Default value: `100`
  * Description: `Up to what HP value to heal players, at most.`
  * Min: `0.0`

