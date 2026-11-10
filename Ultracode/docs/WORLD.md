# HALCYON BAY - WORLD module (terrain, roads, lanes, sidewalks, lots, locations, navigation)

Owner: WORLD foundation. Contract: `docs/ARCHITECTURE.md` section 6.1. Everything here is generated in code at
boot from the deterministic data in `gta/code/world/world_layout.gd` (seed 520017). No hand-made scenes, no image
textures. Map axes: **+X east, +Z south**, 1 unit = 1 m, yaw 0 faces north (-Z).

Overview images (made by `gta/tests/wld_shots.gd`): `qa/screenshots/wld_overview_top.png` (north up),
`qa/screenshots/wld_overview_data.png` (lots by zone, lanes, walk graph, tram loop), `wld_overview_sw.png`,
`wld_data_downtown.png`, `wld_data_waterfront.png` and street level shots `wld_*.png`.
Machine readable dump of the generated data: `qa/world_dump.json` (made by `gta/tests/wld_dump.gd`).

## 1. Map

```
 z=-300 +--------------------------------------------------------------+
        |  apron   ===== RUNWAY 09-27 (380 x 24 m, z = -264) =====     |   AIRPORT
        |  #####   ----- taxiway A (z = -240) ------------  (H) helipad|
        | [P] Airfield Rd   [tower][hangar][hangars ......]      .     |
 z=-190 | +==+=======+====+====+====+===)         .  SIGNAL HILL  .    |
        | #  |  I1   | D1 | D2 | D3 | D4 #        . viewpoint o        |
 z=-105 | +--+--+----+----+----+----+----#        .    dirt road  (38 m)|
        | #I2|I3|    | D5 | D6 |PLZ | D8 #         . . _ . top + mast  |   DOWNTOWN (centre north)
 z= -20 | +--+--+----+----+----+----+----+===+=====)                   |
  docks | #I4|I5|    | M1 | M2 | M3 | M4 | R1| R2  #                   |   INDUSTRIAL (west)
 z=  70 | +--+--+----+----+----+----+----+---+-----+---.               |   MIDTOWN / RESIDENTIAL (east)
  quay  | #   I6     |   M5    |   M6    |   R3    # E1 |              |
 z= 115 | #          +---------+---------+---------+    |              |
  wall  | #  yard    |   M7    |   M8    |   R4    #    | Shore Rd     |
 z= 160 | (===========+=========+=========+========)    |              |
        | | W1        |   W2    |   W3    |    E2  [P]  |              |   WATERFRONT / BEACH
 z= 225 | '-----------+---------+----+----+-------------'              |
        |  (h) marina promenade      :      boardwalk ............     |
 z= 252 +--|----|----|--+   lighthouse o        s a n d   b e a c h    |
           pier pier pier            (8, 274)          x shipwreck (148, 298, -14.5 m)
   x = -279   -215 -168 -120  -60    0    60   120  168  215   255
```
`=`/`#` Coral Ring (arterial), `-`/`|` streets and alleys, `)`/`(` rounded bends, `[P]` parking lots.

| Feature | Where (x, z) | Notes |
|---|---|---|
| Island | inside +-300 | organic coast (`Terrain.organic_sd`), coves west (-290, -150) and east (298, 40), 31.1 ha land |
| City plateau | y = 2.5 | flat; roads +0.03, sidewalks / block slabs +0.15, decks +0.02 |
| Signal Hill | peak (225, -128), y = 38.0 | radius 92 m, flat top pad r 9 m, viewpoint terrace (166.5, -147) y 13.0 |
| Airport | z < -203 | runway (-170..210, -264), taxiway A z = -240, apron (-240..-150, -266..-229), helipad (95, -217) r 9 |
| Docks quay | x = -279, z -96..252 | vertical wall to -5.5 m water, deck 9.5 m wide |
| Marina quay | z = 252, x -279..-30 | plank promenade z 232.5..247.5, three finger piers x = -210 / -150 / -90 (z 252..284, deck y 1.15, ramp to z 260), harbour helipad (-262, 240) |
| Beach | south-east, z > 236 | boardwalk x 45..244 z 232.5..236, sand slope, deep basin with the wreck at (148, 298) -14.5 m |
| Lighthouse knoll | (8, 274), y 4.1 | dirt lane from the Shore Road, flat pad r 7 m |
| Open sea | beyond the coast | seabed slopes to -14.5 m; far seabed plane +-1700 m; world boundary plane at -14.5 m |

Districts (`World.get_district`): `airport` z < -203; `hill` x > 128 and z < -30; south of z = 160: `beach` for
x >= 120 (and the sand x >= 45, z > 229.5), else `waterfront`; `industrial` x < -120; `residential` x > 120;
`downtown` z < -20; `midtown` otherwise; `ocean` over water (the marina basin counts as `waterfront`).

## 2. Roads (WorldLayout.ROADS)

Right-hand traffic. 75 segments, 41 intersections (23 signalised, 16 priority, 2 dead ends with U-turn), 174 lanes,
12.39 lane-km. Roads are split automatically wherever they meet.

| Name | Kind | Width m | Lanes / dir | Limit m/s | Length m | Segments | Parking lane |
|---|---|---|---|---|---|---|---|
| Coral Ring | arterial | 16 | 2 | 22 | 1515 | 16 | |
| Marlin Avenue (x = -120) | street | 11 | 1 | 14 | 415 | 6 | yes |
| Meridian Avenue (x = 0) | street | 11 | 1 | 14 | 415 | 6 | yes |
| Sandpiper Avenue (x = 120) | street | 11 | 1 | 14 | 245 | 4 | yes |
| Foundry Street (z = -105) | street | 11 | 1 | 14 | 335 | 6 | yes |
| Cannery Street (z = -20) | street | 11 | 1 | 14 | 335 | 6 | yes |
| Tideline Street (z = 70) | street | 11 | 1 | 14 | 430 | 8 | yes |
| Lantern Street (z = 115) | street | 9 | 1 | 14 | 335 | 3 | |
| Shore Road (coastal promenade loop) | street | 9 | 1 | 14 | 1058 | 4 | |
| Airfield Road | street | 9 | 1 | 14 | 149 | 1 | |
| Juniper Lane (x = 168) | street | 9 | 1 | 14 | 90 | 1 | |
| Pelican Alley (x = -60) | alley | 6 | 1 | 7 | 260 | 3 | |
| Gull Alley (x = 60) | alley | 6 | 1 | 7 | 260 | 3 | |
| Rivet Lane (x = -168) | alley | 6 | 1 | 7 | 175 | 2 | |
| Signal Hill Road | dirt | 6 | 1 | 9 | 293 | 1 | |
| Lighthouse Lane | dirt | 6 | 1 | 9 | 38 | 1 | |
| Runway 09-27 | runway | 24 | 0 | - | 380 | 1 | |
| Taxiway A / B / C | taxiway | 10 | 0 | - | 270 / 12 / 12 | 3 | |

Coral Ring corners: (-215, -190), (120, -190), (120, -20), (215, -20), (215, 160), (-215, 160); bends without a
junction are rounded with r = 26 m. Shore Road: (-215, -105) - (-262, -105) - (-262, 225) - (255, 225) - (255, 70) -
(215, 70), r = 18 m. Cross sections: arterial lanes at 2.0 / 5.5 m from the centre line (double yellow centre line,
white dashed lane lines); streets lane at 1.75 m, parking lane 3.5..5.5 m where marked; sidewalks 3 m with a sloped
0.15 m kerb (0.25 m run) on both sides of arterials and streets (Airfield Road: inner side only); alleys and dirt
tracks have no sidewalk. Dirt tracks are carved into / painted by the terrain (no asphalt mesh).

Intersections (id, position, control, roads):

| id | x | z | control | roads |
|---|---|---|---|---|
| 0 | -215 | -190 | signal | Coral Ring + Airfield Road |
| 1 | -120 | -190 | signal | Coral Ring + Marlin Avenue + Airfield Road |
| 2 | -60 | -190 | priority | Coral Ring + Pelican Alley |
| 3 | 0 | -190 | signal | Coral Ring + Meridian Avenue |
| 4 | 60 | -190 | priority | Coral Ring + Gull Alley |
| 5 | 120 | -105 | signal | Coral Ring + Foundry Street |
| 6 | 120 | -20 | signal | Coral Ring + Cannery Street + Sandpiper Avenue |
| 7 | 168 | -20 | signal | Coral Ring + Juniper Lane + Signal Hill Road |
| 8 | 215 | 70 | signal | Coral Ring + Tideline Street + Shore Road |
| 9 | 215 | 115 | signal | Coral Ring + Lantern Street |
| 10 / 11 / 12 | 120 / 0 / -120 | 160 | signal | Coral Ring + Sandpiper / Meridian / Marlin Avenue |
| 13 | -215 | 70 | signal | Coral Ring + Tideline Street |
| 14 | -215 | -20 | signal | Coral Ring + Cannery Street |
| 15 | -215 | -105 | signal | Coral Ring + Foundry Street + Shore Road |
| 16 / 17 / 18 | -120 | -105 / -20 / 70 | signal | Marlin Avenue + Foundry / Cannery / Tideline Street |
| 19 | -120 | 115 | priority | Marlin Avenue + Lantern Street |
| 20 | -120 | 225 | priority | Marlin Avenue + Shore Road |
| 21 / 22 / 23 / 24 | 0 | -105 / -20 / 70 / 115 | signal | Meridian Avenue + Foundry / Cannery / Tideline / Lantern Street |
| 25 | 0 | 225 | priority | Meridian Avenue + Shore Road + Lighthouse Lane |
| 26 / 27 | 120 | 70 / 115 | signal | Sandpiper Avenue + Tideline / Lantern Street |
| 28 | 120 | 225 | priority | Sandpiper Avenue + Shore Road |
| 29 / 32 / 35 | -168 | -105 / -20 / 70 | priority | Rivet Lane + Foundry / Cannery / Tideline Street |
| 30 / 33 / 36 | -60 | -105 / -20 / 70 | priority | Pelican Alley + Foundry / Cannery / Tideline Street |
| 31 / 34 / 37 | 60 | -105 / -20 / 70 | priority | Gull Alley + Foundry / Cannery / Tideline Street |
| 38 | 168 | 70 | priority | Juniper Lane + Tideline Street |
| 39 | 221 | -124 | dead end | Signal Hill Road (hill top, U-turn) |
| 40 | 4 | 262 | dead end | Lighthouse Lane (U-turn) |

Signal rule: >= 3 legs and (an arterial with >= 3 major legs, or >= 4 major legs). Cycle 26 s: 9 s green, 2.5 s
yellow, 1.5 s all red per axis; each intersection has its own phase offset. Lanes stop `STOP_SETBACK` = 4.2 m
before the intersection box; the zebra band lies 1.0..3.5 m from the box.

Tram loop (`get_transit_path`, 791 m, clockwise, rails painted on the road): Foundry Street eastbound (z = -103.25)
-> Coral Ring / Sandpiper Avenue southbound (x = 118) -> Tideline Street westbound (z = 68.25) -> Marlin Avenue
northbound (x = -118.25), corner radius 14 m. Stops: `tram_stop_1` (32.5, -103.2) offset 32.6 m, `tram_stop_2`
(118.0, 23.5) offset 238.8 m, `tram_stop_3` (-70.0, 68.3) offset 465.6 m.

## 3. Named locations (`World.get_location(name)`; basis = facing, -Z forward)

Use points of buildings stand in the middle of the sidewalk in front of the lot and face the building.

| name | x | y | z | yaw deg | district |
|---|---|---|---|---|---|
| spawn_start | 105.5 | 2.65 | 219.0 | 180 | beach (in front of the safehouse, facing the street) |
| safehouse | 101.5 | 2.65 | 219.0 | 0 | beach |
| safehouse_garage | 87.5 | 2.65 | 211.5 | 180 | driveway gap beside the safehouse (kerb ramp) |
| hospital | -94.5 | 2.65 | -13.0 | 180 | midtown |
| police_station | -60.0 | 2.65 | 77.0 | 180 | midtown |
| gun_shop | -48.0 | 2.65 | 63.0 | 0 | midtown |
| mod_garage | -127.0 | 2.65 | 0.5 | 90 | industrial |
| shooting_range | -127.0 | 2.65 | 28.5 | 90 | industrial |
| clothing_store | 17.5 | 2.65 | -13.0 | 180 | midtown |
| barber | 33.5 | 2.65 | -13.0 | 180 | midtown |
| general_store | 17.5 | 2.65 | 219.0 | 0 | waterfront |
| gas_station | -96.5 | 2.65 | 150.5 | 0 | midtown |
| parking_garage | 80.0 | 2.65 | -112.0 | 0 | downtown |
| downtown_plaza | 32.8 | 2.65 | -59.5 | 0 | downtown |
| industrial_yard | -164.1 | 2.65 | 126.5 | 0 | industrial |
| residential_park | 187.6 | 2.65 | 28.4 | 0 | residential |
| hill_viewpoint | 166.5 | 13.04 | -147.0 | 123 | hill (faces the city) |
| hill_top | 222.5 | 37.99 | -124.5 | 119 | hill |
| beach | 150.0 | 1.26 | 252.0 | 180 | beach |
| marina_dock | -150.0 | 1.15 | 272.0 | 180 | middle pier |
| boat_spawn | -143.5 | 0.00 | 274.0 | 180 | water beside the middle pier |
| lighthouse | 8.0 | 4.31 | 267.5 | 180 | waterfront |
| airport_runway_start | -150.0 | 2.53 | -264.0 | -90 | faces east |
| airport_runway_end | 190.0 | 2.53 | -264.0 | 90 | faces west |
| airport_helipad | 95.0 | 2.52 | -217.0 | 0 | airport |
| airport_hangar | -82.0 | 2.53 | -235.5 | 180 | airport |
| rooftop_helipad | 80.0 | 13.25 | -128.5 | 180 | PROVISIONAL: above the parking_garage lot, see section 7 |
| shipwreck | 148.0 | -14.50 | 298.0 | 34 | seabed |
| tram_stop_1 / 2 / 3 | 32.5 / 113.0 / -70.0 | 2.65 | -98.0 / 23.5 / 63.0 | 180 / 90 / 0 | platforms |
| stunt_ramp_1 | -180.0 | 2.65 | 138.0 | -90 | Foundry Yard, faces east |
| stunt_ramp_2 | -274.2 | 2.52 | 205.0 | 180 | docks deck, faces the quay end |
| stunt_ramp_3 | -200.0 | 2.52 | -256.0 | -90 | apron |
| race_start | 60.0 | 2.53 | 156.2 | 90 | Coral Ring south, westbound lanes |
| taxi_stand | 30.0 | 2.53 | -15.5 | -90 | Cannery Street kerb |
| extras | | | | | `airport_tower` (-105, -235.5), `radio_mast` (229, -137), `harbor_helipad` (-262, 240) |

## 4. Lots (`World.get_lots()`)

182 lots. `{id, district, zone, center (ground), size (x width, z depth before rotation), yaw (front = local -Z
faces the street), landmark}` plus extras `block` (WorldLayout.BLOCKS id), `ground` (slab finish), `row`.

| district | office | apartment | house | storefront | warehouse | hangar | parking | park | plaza | landmark | total |
|---|---|---|---|---|---|---|---|---|---|---|---|
| downtown | 21 | 2 | | 3 | | | | | 1 | 2 | 29 |
| midtown | | 4 | | 33 | | | | | | 8 | 45 |
| residential | | 3 | 20 | | | | | 1 | | | 24 |
| industrial | | | | | 27 | | | | 1 | 2 | 30 |
| waterfront | | 4 | | 23 | 4 | | | | 1 | 3 | 35 |
| beach | | 2 | | 7 | | | 1 | | | | 10 |
| hill | | | | | | | | | | 1 | 1 |
| airport | | | | | | 5 | 1 | | | 2 | 8 |
| total | 21 | 15 | 20 | 66 | 31 | 5 | 2 | 1 | 3 | 18 | 182 |

Generic lot sizes (width x depth): office 23..31 x 32..33, apartment 23..30 x 22..33, house 14..16 x 16..26,
storefront 14..18 x 22..33, warehouse 17..37 x 20..34, hangar 29 x 32.

Landmark lots (reserved, `lot.landmark`):

| landmark | block | centre x | centre z | size | yaw deg | fronts |
|---|---|---|---|---|---|---|
| parking_garage | D4 | 80.0 | -128.5 | 34 x 30 | 180 | Foundry Street |
| tram_stop_1 | D7 | 32.5 | -93.5 | 14 x 6 | 0 | Foundry Street (plaza edge) |
| hospital | M1 | -94.5 | 3.5 | 34 x 30 | 0 | Cannery Street |
| tram_stop_3 | M1 | -70.0 | 58.5 | 14 x 6 | 180 | Tideline Street |
| gun_shop | M2 | -48.0 | 53.5 | 18 x 16 | 180 | Tideline Street |
| clothing_store | M3 | 17.5 | -3.5 | 18 x 16 | 0 | Cannery Street |
| barber | M3 | 33.5 | -4.5 | 14 x 14 | 0 | Cannery Street |
| tram_stop_2 | M4 | 108.5 | 23.5 | 14 x 6 | -90 | Sandpiper Avenue |
| police_station | M5 | -60.0 | 91.5 | 30 x 26 | 0 | Tideline Street |
| gas_station | M7 | -96.5 | 137.0 | 30 x 24 | 180 | Coral Ring (south section) |
| mod_garage | I5 | -138.5 | 0.5 | 24 x 20 | -90 | Marlin Avenue |
| shooting_range | I5 | -135.5 | 28.5 | 32 x 14 | -90 | Marlin Avenue |
| general_store | W3 | 17.5 | 209.5 | 18 x 16 | 180 | Shore Road |
| safehouse | W3 | 101.5 | 208.5 | 20 x 18 | 180 | Shore Road (8 m driveway gap on its west side) |
| airport_tower | A2 | -105.0 | -227.0 | 14 x 14 | 0 | taxiway A |
| airport_hangar | A2 | -82.0 | -218.0 | 32 x 32 | 0 | taxiway A |
| lighthouse | - | 8.0 | 274.0 | 10 x 10 | 0 | terrain pad, y 4.1 |
| radio_mast | - | 229.0 | -131.5 | 8 x 8 | 0 | hill top pad, y 38.0 |

Other fixed lots: `downtown_plaza` (D7, 49 x 62, tiles), `industrial_yard` (I6, 71 x 36, concrete),
`residential_park` (R2, 24 x 66, lawn), marina promenade (MQ, 220 x 15, planks), parking lots A1 (airport, 77 x 12,
26 bays) and E2 (beach, 60 x 22, 40 bays). Kerb ramps (asphalt wedges over the kerb) exist in front of the beach
parking, gas station (3), mod garage, parking garage, hospital, police station and the safehouse driveway.

## 5. Spawn points (`World.get_spawn_points(kind)`)

| kind | count | where / orientation |
|---|---|---|
| parking | 284 | kerb-side bays of the six parking streets (4.5 m from the centre line, facing the travel direction, none within 8 m of taxi / police / tram / driveway spots) + painted bays of the two parking lots |
| police_car | 4 | Tideline Street kerb in front of the police station |
| taxi | 3 | taxi stand, Cannery Street kerb |
| boat | 12 | both sides of the three piers, y = 0, bow south |
| heli | 2 | airport helipad, harbour helipad |
| plane | 3 | two apron stands and the runway start, facing east |
| ped | 834 | every second walk-graph node (not crosswalks), facing along the path |
| wildlife_land | 39 | Signal Hill 24, lighthouse knoll 3, east dunes 4, park 4, beach 4 |
| wildlife_water | 17 | around the wreck 5, open sea (depth > 3.5 m) 12, y = half depth |
| pickup_weapon / health / armor / cash | 13 / 10 / 8 / 12 | alleys, docks, piers, hill, plaza, beach, in front of shops |
| parachute | 3 | hill top, airport helipad edge, lighthouse |
| roadblock | 21 | middle of arterial stretches > 55 m and street stretches > 100 m, -Z along the road |
| gang | 5 | Rivet Lane, docks, Gull Alley, Foundry Yard, beach parking |
| ladder | 12 | quay walls (5 west, 4 south) and pier heads (3): origin at sea level on the wall face, -Z into the wall, top = deck (2.52 / 1.15) |
| bench | 26 | plaza, park, promenade, boardwalk, viewpoint, tram stops |
| street_light | 166 | every 28 m along sidewalk roads, alternating sides, 0.6 m behind the kerb, -Z towards the road |
| tree_street | 94 | between the lamps on the other side (not in industrial / airport) |
| traffic_light | 86 | one per signalised approach = `get_signal_heads()[i].transform` (right kerb at the stop line, -Z towards the approaching drivers) |
| bin / hydrant / bus_stop | 39 / 31 / 4 | signalised corners / one per street segment / four on the ring |

**Nature placement data** (for the city dressing; added in resume #4; all origins on the ground / seabed, random yaw,
own RNG `SEED + 4111` so the kinds above are unaffected). Every land item stands on natural ground (wild land or
unpaved grass outside the city box, checked on the 3 m lattice and with `World._paved`), at least 4.5 m from paved /
non-wild ground, clear of dirt tracks and pads (trees 6 m), traffic lanes incl. dirt roads (4.6 m, not ground
cover), walk paths, named locations / pickups / benches / wildlife points, the lighthouse and radio-mast lots, and
of each other (occupancy radii tree 2.6, palm 2.2, rock 1.6, bush 1.2, ground cover 0.5). No trees, bushes or
inland rocks in the runway clear zone `z < -212`.

| kind | count | where |
|---|---|---|
| tree_hill | 127 | Signal Hill (hill bump > 1 m): wooded, 7.5 m jittered grid, 80 % |
| tree_wild | 41 | other natural grass (NE flats, coast margins, lighthouse knoll), 16 % |
| tree_palm | 30 | near the sea on the southern half (beach back, knoll, east dunes), coast distance 8..40 m |
| tree_park | 21 | inside `park` lots (residential park), 2.6 m off the paths |
| bush | 95 | hill 22 %, elsewhere 9 % (6 m grid) |
| rock | 47 | rocky (non-beach) shore band 40 %, hill slopes 16 % |
| ground_cover | 708 | grass tufts / ferns / flowers on natural ground (4.5 m grid): use a MultiMesh with a short visibility range |
| reef | 163 | seabed decor (coral / kelp) deeper than 2.5 m: dense within 48 m of the wreck (not within 11 m), sparse on the shelf, never in the harbour basin |

Matching nature assets exist in `gta/generated/models/nature/manifest_nature.json` (tags hill / park / beach / coast /
underwater). Markers: `qa/screenshots/wld_data_nature.png`, `wld_data_nature_hill.png`, `wld_data_nature_beach.png`,
`wld_data_nature_park.png`.

**Footpaths**: `WorldLayout.FOOTPATHS` = walk paths that also get a visible ribbon (visual only, the ground below
collides): residential park loop + cross path (gravel, on the slab) and the east shore dune trail (follows the
terrain). Shots `wld_park_paths.png`, `wld_dune_trail.png`.

## 6. API

### World (`Game.world`, `gta/code/world/world.gd`)

Contract methods exactly as in ARCHITECTURE 6.1. Notes and additions:

- `get_height(x, z)` returns the height of the **surface you stand on**: terrain mesh, road (2.53), kerb slope,
  sidewalk / slab (2.65), deck (2.52), pier (1.15 / ramp). About 6 us per call. `get_terrain_height(x, z)` is the raw
  terrain (seabed under piers). `Terrain.height(x, z)` is the analytic source function (static, slower).
- `get_water_depth`, `is_water_at` use the seabed (water under the piers is water; the quay decks are land).
- `get_surface_at(pos)`: `asphalt`, `concrete`, `grass`, `sand`, `dirt`, `wood`, `water` (all in `Fx.SURFACES`).
  The same names are the `surface` meta of the static bodies (`TerrainBody_*`, `CityBody_*`).
- `has_location(name)`, `set_location(name, xform)`, `get_landmark_lot(landmark) -> Dictionary`,
  `add_spawn_point(kind, xform)`, `get_spawn_kinds()`, `get_signal_heads() -> Array[Dictionary]`
  `{transform, lane_ids: PackedInt32Array, intersection_id}`, `get_terrain_height`, `stats` (Dictionary).
- `get_transit_stops()` entries also carry `platform` (use point Transform3D).
- `get_minimap_data()` extras: `piers` and `decks` (Rect2 arrays, x / z), `transit` (PackedVector2Array),
  `helipads` (Vector3(x, z, radius)), `bounds` (Rect2). Road entries: `{points: PackedVector2Array, width, kind,
  name}`; lots: `{center: Vector2, size, yaw, zone, landmark, district}`; labels: `{text, position: Vector2,
  kind: "district" | "location", id}`. Cached after the first call (about 15 ms for the coast polygon).
- Navigation: `nav_region` gets a Recast mesh baked on a worker thread from the generated ground (about 0.9 s after
  boot the first time, then cached in `user://halcyon_nav_*.res`; 2683 polygons). Signal `nav_ready`,
  `is_nav_ready()`. Building lots are carved out (lot rectangle minus 1 m); plazas, parks, parking lots, tram stops,
  roads, sidewalks, beach, hill, piers are walkable. `rebuild_navigation(obstacles: Array, carve_lots := false)`
  re-bakes with explicit rectangles `[x0, z0, x1, z1]` (real building footprints). The navigation server applies a
  new mesh asynchronously: queries answer a few frames after `nav_ready`. User flags: `--nav_grid` (direct 2 m grid
  mesh instead of Recast, also the automatic fallback), `--nav_nocache`.

### RoadGraph (`World.roads`)

`segments`, `lanes`, `intersections` with the contract keys, plus:

- segment: `pts2` (PackedVector2Array x / z), `length`, `hw` (half width), `node_a`, `node_b`, `parking`, `sw_l`,
  `sw_r`, `trim_a`, `trim_b` (intersection box setback at both ends), `lanes_fwd`, `lanes_back`, `sw_l_span`,
  `sw_r_span` (`[s0, s1, cap0, cap1]` of the sidewalk ribbon, `[]` = none).
- lane: `start_intersection`, `direction` (+1 along the segment), `index` (0 = next to the centre line), `cum`,
  `pts2`, `kind`, `signal_group` (-1 = unsignalised end), `yield` (true on the minor approach of a priority junction).
  Lane points end at the stop line; `get_connection(from_lane, to_lane)` gives the curve through the junction.
- intersection: `legs` (clockwise: `{seg, start, dir, hw, kind, trim, crosswalk, lanes_in, lanes_out, ...}`), `box`
  (half extents of the junction rectangle), `corners`, `phase_offset`, `lanes_in`, `lanes_out`.
- `get_signal_state(lane_id)` 0 / 1 / 2, `get_signal_time_left(lane_id)`, `advance(delta)` (World calls it in
  `_physics_process`), `get_signal_heads()`, `get_lane_length(id)`, `get_segment_at(pos)`, `seg_grid`.
- Turn rules: 1 -> 1 lane: all turns; 2 -> 2 lanes: lane i -> lane i; 2 -> 1: left from the inner lane, right and
  straight from the outer lane; 1 -> 2: left into the inner lane, right / straight into the outer lane; U-turns only
  at the two dead ends. The lane graph is strongly connected (tested).
- `find_route(from, to)` tries both directions of the nearest road at each end and returns the cheaper lane route
  as a polyline (lane points + junction curves), about 1..2.5 ms. `find_lane_route(a, b)` = A* over lanes (time
  cost). `random_lane_point(near, min_d, max_d)` uses `Game.rng`.

### WalkGraph (`World.walk`)

1812 nodes about 9 m apart: `points`, `links`, `kinds` (0 sidewalk, 1 crosswalk / mouth crossing, 2 path), `main`.
Sidewalk centre lines on both sides of streets and arterials, corner connectors, marked crosswalks on every
sidewalk leg of signalised junctions (and street T junctions), unmarked crossings of alley / track mouths, foot
paths along both dirt tracks, plaza diagonals, park loop, marina promenade and piers, docks quay, beach, dunes.
`random_point`, `get_nearest_point`, `find_path` (A*, crosswalks cost +4 m), plus `get_nearest_node`,
`find_node_path`, `node_count`.

### Terrain (`World.terrain`)

`Terrain.height / sample / surface / coast_sd / organic_sd` (static, analytic), `get_mesh_height`, `get_kind`,
`get_land_faces`. 3 m lattice (257 x 257, +-384 m), 16 render chunks with one ShaderMaterial
(`shaders/world_terrain.gdshader`: flat-shaded facets, grass / sand / dirt / rock / seabed from vertex masks,
height and slope), trimesh colliders per surface (`grass`, `sand`, `dirt`).

## 7. Integration notes

- City builder: fill `get_lots()`; building front = lot front (`yaw`). Lot `center.y` is the slab top (2.65; 2.52 on
  the flat airport block). Street furniture positions come from the spawn kinds `street_light`, `traffic_light`
  (+ `get_signal_heads()` for the lane ids), `tree_street`, `bench`, `bin`, `hydrant`, `bus_stop`; vegetation from
  `tree_hill`, `tree_wild`, `tree_palm`, `tree_park`, `bush`, `rock`, `ground_cover`, `reef` (section 5). After placing
  buildings call `world.rebuild_navigation(footprint_rects)`; override the provisional roof helipad with
  `world.set_location("rooftop_helipad", xform)` and add roof spawn points with `add_spawn_point("heli", ...)` /
  `add_spawn_point("parachute", ...)`.
- Traffic: follow `lanes[..].points`, stop at the lane end while `get_signal_state(lane) != 0`, give way when
  `lane.yield`; the tram shares the inner traffic lane along its loop.
- The asphalt / ground shaders read the global uniform `gta_wetness` (darker, glossy, puddles).
- Ladders at the `ladder` points are needed to climb out of the harbour (quay walls are vertical, 2.5 m high).

## 8. Tuning constants (`world_layout.gd`)

`PLATEAU_Y` 2.5, `CURB_H` 0.15, `CURB_RUN` 0.25, `SIDEWALK_W` 3.0, `ROAD_LIFT` 0.03, `MARK_LIFT` 0.055, `DECK_LIFT`
0.02, `STOP_SETBACK` 4.2, `CORNER_R` 1.5, `CROSSWALK_NEAR / FAR` 1.0 / 3.5, `KINDS` (half widths, lane offsets,
limits), `ROADS`, `AIRFIELD`, `BLOCKS` (rows of lots per block), `EXTRA_LOTS`, `WALK_PATHS`, `TRAM_LOOP`, quay / pier
constants, `HILL_*`, `LOT_WIDTH`, `GROUND_OF_ZONE`. Signals: `RoadGraph.GREEN_TIME / YELLOW_TIME / ALL_RED_TIME`.
Terrain: `Terrain.CELL`, `SEA_FLOOR`, `PORT_DEPTH`. Navigation: bake parameters in `World._start_navigation`.

## 9. Tests

```
tools\godot.ps1 -Mode headless -Frames 9000 -UserArgs '--test=wld_api','--disable=traffic,peds,police','--no_player'
tools\godot.ps1 -Mode headless -Frames 2600 -UserArgs '--test=wld_ground','--disable=traffic,peds,police','--no_player'
tools\godot.ps1 -Mode headless -Frames 400  -UserArgs '--test=wld_dump','--disable=traffic,peds,police','--no_player'
tools\godot.ps1 -Mode window  -Frames 420  -UserArgs '--test=wld_shots','--disable=environment,...','--no_player'
```
`wld_api`: 395 checks (contract methods, 36 locations, 32 spawn kinds incl. nature placement rules, lots, strong lane connectivity, routes,
signals, walk graph, transit, minimap, colliders vs get_height, navmesh paths). `wld_ground`: rigid spheres on 18
kinds of ground, a capsule walking over kerbs / kerb ramp / pier ramp / hill track / beach, a wheel rolling over a
kerb, query timings. `wld_shots`: 29 screenshots incl. nature markers (`--wld_only=a,b` to limit).
`wld_spawn` (full boot with the player, standing at `spawn_start`).

Boot cost measured headless (2026-11-10, resume #4): `world.setup()` about 560 ms (terrain 325, roads + lots 15,
city mesh 26, walk graph 30, points 160 of which about 150 are the nature placement); navmesh bake 0.9 s on a worker
thread (0 ms with the cache).

## 10. Known limits

- One navigation region: roads are walkable at the same cost as sidewalks (pedestrians should use WalkGraph).
- Kerb ramps are small asphalt wedges on the road side of the kerb; `get_height` ignores them (max error 0.12 m on
  1.1 m). The airport car park (A1) gets its ramp from the whole-block parking rule (north side).
- The terrain is a 3 m lattice: the dirt tracks have soft, slightly blocky edges and the quay / bank transitions
  are one cell wide (hidden under the quay decks).
- `rooftop_helipad` is provisional until a builder that knows the garage roof overrides it.
- Nature points are data only: the visible trees / rocks / reef are placed by the city dressing (next wave).
