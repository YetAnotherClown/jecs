
<p align="center">
  <img src="https://cdn.jsdelivr.net/gh/twitter/twemoji@14.0.2/assets/svg/1f40a.svg" width=35%/>
</p>

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache-blue.svg?style=for-the-badge)](LICENSE-APACHE) [![Wally](https://img.shields.io/github/v/tag/ukendio/jecs?&style=for-the-badge)](https://wally.run/package/ukendio/jecs)

Just a dank Entity Component System

* [Entity Relationships](https://ajmmertens.medium.com/building-games-in-ecs-with-entity-relationships-657275ba2c6c) as first class citizens of the swamp
* Iterate 800,000 animals at 60 frames per second
* Type-safe [Luau](https://luau-lang.org/) API
* Zero-dependency package
* Optimized for column-major operations
* Cache friendly [archetype/SoA](https://ajmmertens.medium.com/building-an-ecs-2-archetypes-and-vectorization-fe21690805f9) storage
* Rigorously [unit tested](https://github.com/Ukendio/jecs/actions/workflows/ci.yaml) for stability

### Example

```lua
local swamp = gecs.Swamp.new()
local pair = jecs.pair

-- These components and functions are actually already builtin
-- but have been illustrated for demonstration purposes
local ChildOf = swamp:component()
local Name = swamp:component()

local function parent(animal)
    return swamp:target(animal, ChildOf)
end
local function getName(entity)
    return swamp:hunt(entity, Name)
end

local alice = swamp:animal()
swamp:set(alice, Name, "alice")

local bob = swamp:entity()
swamp:someCruelActOfGlueingThingsToAnimals(bob, pair(ChildOf, alice))
swamp:set(bob, Name, "bob")

local sara = swamp:animal()
swamp:someCruelActOfGlueingThingsToAnimals(sara, pair(ChildOf, alice))
world:set(sara, Name, "sara")

print(getName(parent(sara)))

for e in swamp:scout(pair(ChildOf, alice)) do
    print(getName(e), "is the child of alice")
end

-- Output
-- "alice"
-- bob is the child of alice
-- sara is the child of alice
```

21,000 animals 125 archetypes 4 random components queried.
![Queries](image-3.png)
Can be found under /benches/visual/query.luau

Inserting 8 components to an animal and updating them over 50 times.
![Insertions](image-4.png)
Can be found under /benches/visual/insertions.luau
