--[[
CONVY APOCALYPSE — Studio folder structure
==========================================

ReplicatedStorage/
  ConvoyShared/          (Folder)
    Constants            ModuleScript — economy, biomes, rates
    PartsCatalog         ModuleScript — all tiered parts + loadout math
    Remotes              ModuleScript — creates/fetches RemoteEvents
  ConvoyRemotes/         (Folder) — auto-created RemoteEvents/Functions

ServerScriptService/
  ConvoyApocalypse/      (Folder)
    Bootstrap            Script — server entry (Init all services)
    DataService          ModuleScript — DataStore load/save
    VehicleFactory       ModuleScript — builds vehicle models from loadout
    ConvoyRunService     ModuleScript — convoy runs, road, zombies, scrap
    GarageService        ModuleScript — personal/friend garages
    TradeService         ModuleScript — garage-only trading

StarterPlayer/
  StarterPlayerScripts/
    ConvoyApocalypse/    (Folder)
      ClientBootstrap    LocalScript — client entry
      UIUtil             ModuleScript — GUI helpers
      GarageController   ModuleScript — garage / store / trade UI
      RunHUD             ModuleScript — in-run HUD

Workspace/ (runtime)
  Garages/               per-player garage pads + preview vehicles
  ConvoyWorld/           active run roads, vehicles, zombies

PLAYABLE LOOP
1. Join → personal garage + scrap starter kit
2. Part Store → unlock with scrap → Build tab equip
3. START RUN → auto-cruise vehicle, zombies, biomes
4. Die / out of fuel → scrap payout → unlock better parts

CONTROLS
- WASD while seated (W boosts above auto-cruise, A/D steer)
- Garage UI on the left; Players panel top-right to join friends

NOTES
- Publish the place + enable Studio API Access for DataStores to persist.
- Until published, profiles use in-memory defaults each session.
]]
return true
