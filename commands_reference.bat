@echo off
REM AI Companion mod - console/RCON command syntax reference
REM Generated from commands/*.lua and control.lua
REM Legend: <required>  [optional, default shown if any]
REM All commands below are typed in the Factorio console (or sent via RCON)
REM with a leading slash, e.g.:  /fac_chat_get
setlocal
echo ============================================================
echo  AI COMPANION - COMMAND SYNTAX REFERENCE
echo ============================================================
echo.
echo --- Player chat command (control.lua) ---------------------
echo /fac ^<msg^>                  broadcast msg, recorded as untargeted message
echo /fac ^<id^|name^> ^<msg^>        send msg to one companion
echo /fac spawn [count=1]         request spawn (max 10)
echo /fac list                    print companion ids ^& positions to chat
echo /fac kill [id]                kill one companion, or all if id omitted
echo /fac clear                   clear all pending companion messages
echo /fac name ^<id^> ^<name^>        rename a companion
echo.
echo --- chat -----------------------------------------------------
echo fac_chat_get [filter]        filter: empty=all unread, "orchestrator"=untargeted only,
echo                              ^<id^>=messages targeted at that companion. Marks read.
echo fac_chat_say ^<id^|0^> ^<msg^>    id=0 speaks as [Claude]; else as companion id/name
echo.
echo --- action -----------------------------------------------------
echo fac_action_attack ^<id^> ^<x^> ^<y^>          shoot at position/entity there
echo fac_action_flee ^<id^> [dist=30]            run away from nearby enemies
echo fac_action_patrol ^<id^>                    NOT IMPLEMENTED
echo fac_action_wololo ^<id^>                    convert nearest enemy unit/spawner to your force
echo fac_action_attack_start ^<id^> ^<x^> ^<y^>     tick-based combat: start engaging at position
echo fac_action_attack_status ^<id^>              check ongoing attack status
echo fac_action_attack_stop ^<id^>                stop attacking, reports kills
echo fac_action_defend ^<id^> ^<on^|off^>            toggle auto-defend mode
echo.
echo --- building -----------------------------------------------------
echo fac_building_can_place ^<id^> ^<entity^> ^<x^> ^<y^> [dir=0]
echo fac_building_place ^<id^> ^<entity^> ^<x^> ^<y^> [dir=0]        instant placement
echo fac_building_place_start ^<id^> ^<entity^> ^<x^> ^<y^> [dir_name]  tick-based ^(realistic^) placement
echo fac_building_place_status ^<id^>              check tick-based placement progress
echo fac_building_remove ^<id^> ^<entity^> ^<x^> ^<y^>
echo fac_building_rotate ^<id^> ^<x^> ^<y^> ^<dir 0-3^>
echo fac_building_info ^<id^> ^<entity^> ^<x^> ^<y^>    entity name/type/health/energy/recipe
echo fac_building_recipe ^<id^> ^<recipe^> ^<x^> ^<y^>   set recipe on assembling machine
echo fac_building_fuel ^<id^> ^<fuel_item^> [amount=5]
echo fac_building_empty ^<id^> ^<item^> [count=10] [x] [y]   pull item out of nearby chest/machine
echo fac_building_fill ^<id^> ^<item^> [count=10] [x] [y]    push item into nearby chest/machine
echo   dir values: 0=north 1=east 2=south 3=west
echo.
echo --- companion -----------------------------------------------------
echo fac_companion_list                          list all companions
echo fac_companion_spawn [id=N]                  spawn a companion, optional explicit id
echo fac_companion_disappear ^<id^>                despawn, drops inventory
echo fac_companion_position ^<id^>                 position + nearby entities + nearby players
echo fac_companion_health ^<id^> [target]          own health, optional target player/companion
echo fac_companion_inventory ^<id^> [x] [y]        own inventory, or contents of entity at x,y
echo.
echo --- context -----------------------------------------------------
echo fac_context_clear [all^|id]                  default "all"; clears message queue
echo fac_context_check                            list ^& clear pending context-clear requests
echo.
echo --- goal -----------------------------------------------------
echo fac_goal_create ^<id^> [watch_type] [description]   watch_type: harvest^|craft^|build to auto-resolve, or blank for manual
echo fac_goal_update ^<id^> ^<status^> [note]              status: pending^|in_progress^|done^|failed
echo fac_goal_list [id^|status]                          blank = all goals
echo fac_goal_get ^<id^>
echo.
echo --- item -----------------------------------------------------
echo fac_item_craft ^<id^> ^<item^> [count=1]         instant craft
echo fac_item_craft_start ^<id^> ^<recipe^> [count=1] tick-based ^(realistic^) craft
echo fac_item_craft_status ^<id^>
echo fac_item_craft_stop ^<id^>                     reports items crafted so far
echo fac_item_pick ^<id^> [filter] [radius=5]        pick up dropped item entities
echo fac_item_recipes ^<id^> [filter^|active]         list unlocked recipes
echo.
echo --- move -----------------------------------------------------
echo fac_move_to ^<id^> ^<x^> ^<y^>
echo fac_move_follow ^<id^> ^<player_name^>
echo fac_move_stop ^<id^>
echo.
echo --- research -----------------------------------------------------
echo fac_research_get ^<id^>                        current + available researchable techs
echo fac_research_progress ^<id^> [tech_name]        defaults to current research
echo fac_research_set ^<id^> ^<tech_name^>
echo.
echo --- resource -----------------------------------------------------
echo fac_resource_list ^<id^> [resource_name] [radius=50]
echo fac_resource_mine ^<id^> ^<x^> ^<y^> [count=1] [resource_name]   tick-based mining
echo fac_resource_mine_status ^<id^>
echo fac_resource_mine_stop ^<id^>                  reports amount harvested
echo fac_resource_nearest ^<id^> ^<name^>             name aliases: copper,iron,coal,stone,uranium,oil
echo.
echo --- world -----------------------------------------------------
echo fac_world_nearest ^<id^> ^<name^>                 aliases: copper,iron,coal,stone,uranium,wood,water
echo fac_world_scan ^<id^> [radius=10] [filter]
echo fac_world_enemies ^<id^> [radius=30]            returns threat_level: safe^|caution^|danger
echo.
echo --- misc / diagnostics -----------------------------------------------------
echo fac_version                                   mod + factorio base version
echo fac_help                                      JSON list of all command categories
echo.
echo ============================================================
echo All responses are JSON printed via rcon.print / u.json_response.
echo ^<id^> = companion id number ^(or its name, where find_companion is used^).
echo ============================================================
endlocal
pause
