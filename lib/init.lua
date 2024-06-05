--!optimize 2
--!native
--!strict
--draft 4

type i53 = number
type i24 = number

type Ty = { i53 }
type ArchetypeId = number

type Column = { any }

type Archetype = {
	id: number,
	edges: {
		[i53]: {
			add: Archetype,
			remove: Archetype,
		},
	},
	types: Ty,
	type: string | number,
	entities: { number },
	columns: { Column },
	records: {},
}

type Record = {
	archetype: Archetype,
	row: number,
	dense: i24,
	componentRecord: ArchetypeMap,
}

type EntityIndex = { dense: { [i24]: i53 }, sparse: { [i53]: Record } }

type ArchetypeRecord = number
--[[
TODO:
{
	index: number,
	count: number,
	column: number
} 

]]

type ArchetypeMap = {
	cache: { [number]: ArchetypeRecord },
	first: ArchetypeMap,
	second: ArchetypeMap,
	parent: ArchetypeMap,
	size: number,
}

type ComponentIndex = { [i24]: ArchetypeMap }

type Archetypes = { [ArchetypeId]: Archetype }

type ArchetypeDiff = {
	added: Ty,
	removed: Ty,
}

local FLAGS_PAIR = 0x8
local HI_COMPONENT_ID = 256
local ON_ADD = HI_COMPONENT_ID + 1
local ON_REMOVE = HI_COMPONENT_ID + 2
local ON_SET = HI_COMPONENT_ID + 3
local WILDCARD = HI_COMPONENT_ID + 4
local REST = HI_COMPONENT_ID + 5

local ECS_ID_FLAGS_MASK = 0x10
local ECS_ENTITY_MASK = bit32.lshift(1, 24)
local ECS_GENERATION_MASK = bit32.lshift(1, 16)

local function addFlags(isPair: boolean)
	local typeFlags = 0x0

	if isPair then
		typeFlags = bit32.bor(typeFlags, FLAGS_PAIR) -- HIGHEST bit in the ID.
	end
	if false then
		typeFlags = bit32.bor(typeFlags, 0x4) -- Set the second flag to true
	end
	if false then
		typeFlags = bit32.bor(typeFlags, 0x2) -- Set the third flag to true
	end
	if false then
		typeFlags = bit32.bor(typeFlags, 0x1) -- LAST BIT in the ID.
	end

	return typeFlags
end

local function ECS_COMBINE(source: number, target: number): i53
	local e = source * 268435456 + target * ECS_ID_FLAGS_MASK
	return e
end

local function ECS_IS_PAIR(e: number)
	if e > ECS_ENTITY_MASK then
		return (e % 2 ^ 4) // FLAGS_PAIR ~= 0
	end
	return false
end

-- HIGH 24 bits LOW 24 bits
local function ECS_GENERATION(e: i53)
	if e > ECS_ENTITY_MASK then
		e = e // 0x10
		return e % ECS_GENERATION_MASK
	end
	return 0
end

local function ECS_GENERATION_INC(e: i53)
	if e > ECS_ENTITY_MASK then
		local flags = e // 0x10
		local id = flags // ECS_ENTITY_MASK
		local generation = flags % ECS_GENERATION_MASK

		return ECS_COMBINE(id, generation + 1) + flags
	end
	return ECS_COMBINE(e, 1)
end

-- FIRST gets the high ID
local function ECS_ENTITY_T_HI(e: i53): i24
	if e > ECS_ENTITY_MASK then
		e = e // 0x10
		return e % ECS_ENTITY_MASK
	end
	return e
end

-- SECOND
local function ECS_ENTITY_T_LO(e: i53)
	if e > ECS_ENTITY_MASK then
		e = e // 0x10
		return e // ECS_ENTITY_MASK
	end
	return e
end

local function ECS_PAIR(pred: i53, obj: i53): i53
	return ECS_COMBINE(ECS_ENTITY_T_LO(obj), ECS_ENTITY_T_LO(pred)) + addFlags(--[[isPair]] true)
end

local function getAlive(entityIndex: EntityIndex, id: i24)
	local entityId = entityIndex.dense[id]
	return entityId
end

-- ECS_PAIR_FIRST, gets the relationship target / obj / HIGH bits
local function ECS_PAIR_RELATION(entityIndex, e)
	return getAlive(entityIndex, ECS_ENTITY_T_HI(e))
end

-- ECS_PAIR_SECOND gets the relationship / pred / LOW bits
local function ECS_PAIR_OBJECT(entityIndex, e)
	return getAlive(entityIndex, ECS_ENTITY_T_LO(e))
end

local function nextEntityId(entityIndex, index: i24): i53
	--local id = ECS_COMBINE(index, 0)
	local id = index
	entityIndex.sparse[id] = {
		dense = index,
	} :: Record
	entityIndex.dense[index] = id

	return id
end

local function transitionArchetype(
	entityIndex: EntityIndex,
	to: Archetype,
	destinationRow: i24,
	from: Archetype,
	sourceRow: i24
)
	local columns = from.columns
	local sourceEntities = from.entities
	local destinationEntities = to.entities
	local destinationColumns = to.columns
	local tr = to.records
	local types = from.types

	for i, column in columns do
		-- Retrieves the new column index from the source archetype's record from each component
		-- We have to do this because the columns are tightly packed and indexes may not correspond to each other.
		local targetColumn = destinationColumns[tr[types[i]]]

		-- Sometimes target column may not exist, e.g. when you remove a component.
		if targetColumn then
			targetColumn[destinationRow] = column[sourceRow]
		end
		-- If the entity is the last row in the archetype then swapping it would be meaningless.
		local last = #column
		if sourceRow ~= last then
			-- Swap rempves columns to ensure there are no holes in the archetype.
			column[sourceRow] = column[last]
		end
		column[last] = nil
	end

	local sparse = entityIndex.sparse
	local movedAway = #sourceEntities

	-- Move the entity from the source to the destination archetype.
	-- Because we have swapped columns we now have to update the records
	-- corresponding to the entities' rows that were swapped.
	local e1 = sourceEntities[sourceRow]
	local e2 = sourceEntities[movedAway]

	if sourceRow ~= movedAway then
		sourceEntities[sourceRow] = e2
	end

	sourceEntities[movedAway] = nil
	destinationEntities[destinationRow] = e1

	local record1 = sparse[e1]
	local record2 = sparse[e2]

	record1.row = destinationRow
	record2.row = sourceRow
end

local function archetypeAppend(entity: number, archetype: Archetype): number
	local entities = archetype.entities
	local length = #entities + 1
	entities[length] = entity
	return length
end

local function newEntity(entityId: i53, record: Record, archetype: Archetype)
	local row = archetypeAppend(entityId, archetype)
	record.archetype = archetype
	record.row = row
	return record
end

local function moveEntity(entityIndex: EntityIndex, entityId: i53, record: Record, to: Archetype)
	local sourceRow = record.row
	local from = record.archetype
	local destinationRow = archetypeAppend(entityId, to)
	transitionArchetype(entityIndex, to, destinationRow, from, sourceRow)
	record.archetype = to
	record.row = destinationRow
end

local function hash(arr): string | number
	return table.concat(arr, "_")
end

local function ensureComponentRecord(
	componentIndex: ComponentIndex,
	archetypeId: number,
	componentId: number,
	i: number
): ArchetypeMap
	local archetypesMap = componentIndex[componentId]

	if not archetypesMap then
		archetypesMap = { size = 0, cache = {}, first = {}, second = {} } :: ArchetypeMap
		componentIndex[componentId] = archetypesMap
	end

	archetypesMap.cache[archetypeId] = i
	archetypesMap.size += 1

	return archetypesMap
end

local function ECS_ID_IS_WILDCARD(e)
	assert(ECS_IS_PAIR(e))
	local first = ECS_ENTITY_T_HI(e)
	local second = ECS_ENTITY_T_LO(e)
	return first == WILDCARD or second == WILDCARD
end

local function archetypeOf(world: any, types: { i24 }, prev: Archetype?): Archetype
	local ty = hash(types)

	local id = world.nextArchetypeId + 1
	world.nextArchetypeId = id

	local length = #types
	local columns = table.create(length)
	local componentIndex = world.componentIndex

	local records = {}
	for i, componentId in types do
		ensureComponentRecord(componentIndex, id, componentId, i)
		records[componentId] = i
		if ECS_IS_PAIR(componentId) then
			local relation = ECS_PAIR_RELATION(world.entityIndex, componentId)
			local object = ECS_PAIR_OBJECT(world.entityIndex, componentId)

			local idr_r = ECS_PAIR(relation, WILDCARD)
			ensureComponentRecord(componentIndex, id, idr_r, i)
			records[idr_r] = i

			local idr_t = ECS_PAIR(WILDCARD, object)
			ensureComponentRecord(componentIndex, id, idr_t, i)
			records[idr_t] = i
		end
		columns[i] = {}
	end

	local archetype = {
		columns = columns,
		edges = {},
		entities = {},
		id = id,
		records = records,
		type = ty,
		types = types,
	}
	world.archetypeIndex[ty] = archetype
	world.archetypes[id] = archetype

	return archetype
end

local World = {}
World.__index = World
function World.new()
	local self = setmetatable({
		archetypeIndex = {},
		archetypes = {} :: Archetypes,
		componentIndex = {} :: ComponentIndex,
		entityIndex = {
			dense = {},
			sparse = {},
		} :: EntityIndex,
		hooks = {
			[ON_ADD] = {},
		},
		nextArchetypeId = 0,
		nextComponentId = 0,
		nextEntityId = 0,
		ROOT_ARCHETYPE = (nil :: any) :: Archetype,
	}, World)
	self.ROOT_ARCHETYPE = archetypeOf(self, {})
	return self
end

function World.component(world: World)
	local componentId = world.nextComponentId + 1
	if componentId > HI_COMPONENT_ID then
		-- IDs are partitioned into ranges because component IDs are not nominal,
		-- so it needs to error when IDs intersect into the entity range.
		error("Too many components, consider using world:entity() instead to create components.")
	end
	world.nextComponentId = componentId
	return nextEntityId(world.entityIndex, componentId)
end

function World.entity(world: World)
	local entityId = world.nextEntityId + 1
	world.nextEntityId = entityId
	return nextEntityId(world.entityIndex, entityId + REST)
end

-- TODO:
-- should have an additional `index` parameter which selects the nth target
-- this is important when an entity can have multiple relationships with the same target
function World.target(world: World, entity: i53, relation: i24): i24?
	local entityIndex = world.entityIndex
	local record = entityIndex.sparse[entity]
	local archetype = record.archetype
	if not archetype then
		return nil
	end

	local componentRecord = world.componentIndex[ECS_PAIR(relation, WILDCARD)]
	if not componentRecord then
		return nil
	end

	local archetypeRecord = componentRecord.cache[archetype.id]
	if not archetypeRecord then
		return nil
	end

	return ECS_PAIR_OBJECT(entityIndex, archetype.types[archetypeRecord])
end

-- should reuse this logic in World.set instead of swap removing in transition archetype
local function destructColumns(columns, count, row)
	if row == count then
		for _, column in columns do
			column[count] = nil
		end
	else
		for _, column in columns do
			column[row] = column[count]
			column[count] = nil
		end
	end
end

local function archetypeDelete(world: World, id: i53)
	local componentIndex = world.componentIndex
	local archetypesMap = componentIndex[id]
	local archetypes = world.archetypes
	if archetypesMap then
		for archetypeId in archetypesMap.cache do
			for _, entity in archetypes[archetypeId].entities do
				world:remove(entity, id)
			end
		end

		componentIndex[id] = nil
	end
end

function World.delete(world: World, entityId: i53)
	local record = world.entityIndex.sparse[entityId]
	if not record then
		return
	end
	local entityIndex = world.entityIndex
	local sparse, dense = entityIndex.sparse, entityIndex.dense
	local archetype = record.archetype
	local row = record.row

	archetypeDelete(world, entityId)
	-- TODO: should traverse linked )component records to pairs including entityId
	archetypeDelete(world, ECS_PAIR(entityId, WILDCARD))
	archetypeDelete(world, ECS_PAIR(WILDCARD, entityId))

	if archetype then
		local entities = archetype.entities
		local last = #entities

		if row ~= last then
			local entityToMove = entities[last]
			dense[record.dense] = entityToMove
			sparse[entityToMove] = record
		end

		entities[row], entities[last] = entities[last], nil

		local columns = archetype.columns

		destructColumns(columns, last, row)
	end

	sparse[entityId] = nil
	dense[#dense] = nil
end

export type World = typeof(World.new())

local function ensureArchetype(world: World, types, prev)
	if #types < 1 then
		return world.ROOT_ARCHETYPE
	end

	local ty = hash(types)
	local archetype = world.archetypeIndex[ty]
	if archetype then
		return archetype
	end

	return archetypeOf(world, types, prev)
end

local function findInsert(types: { i53 }, toAdd: i53)
	for i, id in types do
		if id == toAdd then
			return -1
		end
		if id > toAdd then
			return i
		end
	end
	return #types + 1
end

local function findArchetypeWith(world: World, node: Archetype, componentId: i53)
	local types = node.types
	-- Component IDs are added incrementally, so inserting and sorting
	-- them each time would be expensive. Instead this insertion sort can find the insertion
	-- point in the types array.

	local destinationType = table.clone(node.types)
	local at = findInsert(types, componentId)
	if at == -1 then
		-- If it finds a duplicate, it just means it is the same archetype so it can return it
		-- directly instead of needing to hash types for a lookup to the archetype.
		return node
	end
	table.insert(destinationType, at, componentId)

	return ensureArchetype(world, destinationType, node)
end

local function ensureEdge(archetype: Archetype, componentId: i53)
	local edges = archetype.edges
	local edge = edges[componentId]
	if not edge then
		edge = {} :: any
		edges[componentId] = edge
	end
	return edge
end

local function archetypeTraverseAdd(world: World, componentId: i53, from: Archetype): Archetype
	from = from or world.ROOT_ARCHETYPE

	local edge = ensureEdge(from, componentId)
	local add = edge.add
	if not add then
		-- Save an edge using the component ID to the archetype to allow
		-- faster traversals to adjacent archetypes.
		add = findArchetypeWith(world, from, componentId)
		edge.add = add :: never
	end

	return add
end

function World.add(world: World, entityId: i53, componentId: i53)
	local entityIndex = world.entityIndex
	local record = entityIndex.sparse[entityId]
	local from = record.archetype
	local to = archetypeTraverseAdd(world, componentId, from)
	if from and not (from == world.ROOT_ARCHETYPE) then
		moveEntity(entityIndex, entityId, record, to)
	else
		if #to.types > 0 then
			newEntity(entityId, record, to)
		end
	end
end

-- Symmetric like `World.add` but idempotent
function World.set(world: World, entityId: i53, componentId: i53, data: unknown)
	local record = world.entityIndex.sparse[entityId]
	local from = record.archetype
	local to = archetypeTraverseAdd(world, componentId, from)

	if from == to then
		-- If the archetypes are the same it can avoid moving the entity
		-- and just set the data directly.
		local archetypeRecord = to.records[componentId]
		from.columns[archetypeRecord][record.row] = data
		-- Should fire an OnSet event here.
		return
	end

	if from then
		-- If there was a previous archetype, then the entity needs to move the archetype
		moveEntity(world.entityIndex, entityId, record, to)
	else
		if #to.types > 0 then
			-- When there is no previous archetype it should create the archetype
			newEntity(entityId, record, to)
		end
	end

	local archetypeRecord = to.records[componentId]
	to.columns[archetypeRecord][record.row] = data
end

local function archetypeTraverseRemove(world: World, componentId: i53, from: Archetype): Archetype
	local edge = ensureEdge(from, componentId)

	local remove = edge.remove
	if not remove then
		local to = table.clone(from.types)
		local at = table.find(to, componentId)
		if not at then
			return from
		end
		table.remove(to, at)
		remove = ensureArchetype(world, to, from)
		edge.remove = remove :: never
	end

	return remove
end

function World.remove(world: World, entityId: i53, componentId: i53)
	local entityIndex = world.entityIndex
	local record = entityIndex.sparse[entityId]
	local sourceArchetype = record.archetype
	local destinationArchetype = archetypeTraverseRemove(world, componentId, sourceArchetype)

	if sourceArchetype and not (sourceArchetype == destinationArchetype) then
		moveEntity(entityIndex, entityId, record, destinationArchetype)
	end
end

-- Keeping the function as small as possible to enable inlining
local function get(record: Record, componentId: i24)
	local archetype = record.archetype
	if not archetype then
		return nil
	end

	local archetypeRecord = archetype.records[componentId]

	if not archetypeRecord then
		return nil
	end

	return archetype.columns[archetypeRecord][record.row]
end

function World.get(world: World, entityId: i53, a: i53, b: i53?, c: i53?, d: i53?, e: i53?)
	local id = entityId
	local record = world.entityIndex.sparse[id]
	if not record then
		return nil
	end

	local va = get(record, a)

	if b == nil then
		return va
	elseif c == nil then
		return va, get(record, b)
	elseif d == nil then
		return va, get(record, b), get(record, c)
	elseif e == nil then
		return va, get(record, b), get(record, c), get(record, d)
	else
		error("args exceeded")
	end
end

-- the less creation the better
local function actualNoOperation() end
local function noop(_self: Query, ...): () -> ()
	return actualNoOperation :: any
end

local EmptyQuery = {
	__iter = noop,
	without = noop,
}
EmptyQuery.__index = EmptyQuery
setmetatable(EmptyQuery, EmptyQuery)

export type Query = typeof(EmptyQuery)

function World.query(world: World, ...): Query
	-- breaking?
	if (...) == nil then
		error("Missing components")
	end

	local compatibleArchetypes = {}
	local length = 0

	local components = { ... }
	local archetypes = world.archetypes
	local queryLength = #components

	local firstArchetypeMap
	local componentIndex = world.componentIndex

	for _, componentId in components do
		local map = componentIndex[componentId]
		if not map then
			return EmptyQuery
		end

		if firstArchetypeMap == nil or map.size < firstArchetypeMap.size then
			firstArchetypeMap = map
		end
	end

	for id in firstArchetypeMap.cache do
		local archetype = archetypes[id]
		local archetypeRecords = archetype.records

		local indices = {}
		local skip = false

		for i, componentId in components do
			local index = archetypeRecords[componentId]
			if not index then
				skip = true
				break
			end
			-- index should be index.offset
			indices[i] = index
		end

		if skip then
			continue
		end

		length += 1
		compatibleArchetypes[length] = {
			archetype = archetype,
			indices = indices,
		}
	end

	local lastArchetype, compatibleArchetype = next(compatibleArchetypes)
	if not lastArchetype then
		return EmptyQuery
	end

	local preparedQuery = {}
	preparedQuery.__index = preparedQuery

	function preparedQuery:without(...)
		local withoutComponents = { ... }
		for i = #compatibleArchetypes, 1, -1 do
			local archetype = compatibleArchetypes[i].archetype
			local records = archetype.records
			local shouldRemove = false

			for _, componentId in withoutComponents do
				if records[componentId] then
					shouldRemove = true
					break
				end
			end

			if shouldRemove then
				table.remove(compatibleArchetypes, i)
			end
		end

		lastArchetype, compatibleArchetype = next(compatibleArchetypes)
		if not lastArchetype then
			return EmptyQuery
		end

		return self
	end

	local lastRow
	local queryOutput = {}

	function preparedQuery:__iter()
		return function()
			local archetype = compatibleArchetype.archetype
			local row: number = next(archetype.entities, lastRow) :: number
			while row == nil do
				lastArchetype, compatibleArchetype = next(compatibleArchetypes, lastArchetype)
				if lastArchetype == nil then
					return
				end
				archetype = compatibleArchetype.archetype
				row = next(archetype.entities, row) :: number
			end
			lastRow = row

			local entityId = archetype.entities[row :: number]
			local columns = archetype.columns
			local tr = compatibleArchetype.indices

			if queryLength == 1 then
				return entityId, columns[tr[1]][row]
			elseif queryLength == 2 then
				return entityId, columns[tr[1]][row], columns[tr[2]][row]
			elseif queryLength == 3 then
				return entityId, columns[tr[1]][row], columns[tr[2]][row], columns[tr[3]][row]
			elseif queryLength == 4 then
				return entityId, columns[tr[1]][row], columns[tr[2]][row], columns[tr[3]][row], columns[tr[4]][row]
			elseif queryLength == 5 then
				return entityId,
					columns[tr[1]][row],
					columns[tr[2]][row],
					columns[tr[3]][row],
					columns[tr[4]][row],
					columns[tr[5]][row]
			elseif queryLength == 6 then
				return entityId,
					columns[tr[1]][row],
					columns[tr[2]][row],
					columns[tr[3]][row],
					columns[tr[4]][row],
					columns[tr[5]][row],
					columns[tr[6]][row]
			elseif queryLength == 7 then
				return entityId,
					columns[tr[1]][row],
					columns[tr[2]][row],
					columns[tr[3]][row],
					columns[tr[4]][row],
					columns[tr[5]][row],
					columns[tr[6]][row],
					columns[tr[7]][row]
			elseif queryLength == 8 then
				return entityId,
					columns[tr[1]][row],
					columns[tr[2]][row],
					columns[tr[3]][row],
					columns[tr[4]][row],
					columns[tr[5]][row],
					columns[tr[6]][row],
					columns[tr[7]][row],
					columns[tr[8]][row]
			end

			for i in components do
				queryOutput[i] = columns[tr[i]][row]
			end

			return entityId, unpack(queryOutput, 1, queryLength)
		end
	end

	return setmetatable({}, preparedQuery) :: any
end

function World.__iter(world: World): () -> (number?, unknown?)
	local dense = world.entityIndex.dense
	local sparse = world.entityIndex.sparse
	local last

	return function()
		local lastEntity, entityId = next(dense, last)
		if not lastEntity then
			return
		end

		last = lastEntity

		local record = sparse[entityId]
		local archetype = record.archetype
		if not archetype then
			-- Returns only the entity id as an entity without data should not return
			-- data and allow the user to get an error if they don't handle the case.
			return entityId
		end

		local row = record.row
		local types = archetype.types
		local columns = archetype.columns
		local entityData = {}
		for i, column in columns do
			-- We use types because the key should be the component ID not the column index
			entityData[types[i]] = column[row]
		end

		return entityId, entityData
	end
end

-- __nominal_type_dont_use could not be any or T as it causes a type error
-- or produces a union
export type Component<T=any> = T & {__nominal_type_dont_use: never}
export type Entity<T=any> = Component<T>
export type Relationship<T=any> = Component<T>
type ctype<T> = Component<T>

export type QueryShim<T...> = typeof(setmetatable(
	{} :: {
		--- Excludes the given selection from the query
		without: <U...>(QueryShim<T...>, U...) -> QueryShim<T...>
	},
	{} :: {
		__iter: (QueryShim<T...>) -> () -> (Entity, T...)
	}
))

export type WorldShim = typeof(setmetatable(
	{} :: {

		--- Creates a new entity
		entity: <T>(WorldShim) -> Entity<T>,
		--- Creates a new entity located in the first 256 ids.
		--- These should be used for static components for fast access.
		component: <T>(WorldShim) -> Component<T>,
		--- Gets the target of an relationship. For example, when a user calls
		--- `world:target(id, ChildOf(parent))`, you will obtain the parent entity.
		target: (WorldShim, id: Entity, relation: Relationship) -> Entity?,
		--- Deletes an entity and all it's related components and relationships.
		delete: (WorldShim, id: Entity) -> (),
	
		--- Adds a component to the entity with no value
		add: <T>(WorldShim, id: Entity, component: Component<T>) -> (),
		--- Assigns a value to a component on the given entity
		set: <T>(WorldShim, id: Entity, component: Component<T>, data: T) -> (),
		--- Removes a component from the given entity
		remove: (WorldShim, id: Entity, component: Component) -> (),
		--- Retrieves the value of up to 4 components. These values may be nil.
		get:
			(<A>(WorldShim, id: any, ctype<A>) -> A)
			& (<A, B>(WorldShim, id: Entity, ctype<A>, ctype<B>) -> (A, B))
			& (<A, B, C>(WorldShim, id: Entity, ctype<A>, ctype<B>, ctype<C>) -> (A, B, C))
			& <A, B, C, D>(WorldShim, id: Entity, ctype<A>, ctype<B>, ctype<C>, ctype<D>) -> (A, B, C, D),
	
		--- Searches the world for entities that match a given query
		query:
			(<A>(WorldShim, ctype<A>) -> QueryShim<A>)
			& (<A, B>(WorldShim, ctype<A>, ctype<B>) -> QueryShim<A, B>)
			& (<A, B, C>(WorldShim, ctype<A>, ctype<B>, ctype<C>) -> QueryShim<A, B, C>)
			& (<A, B, C, D>(WorldShim, ctype<A>, ctype<B>, ctype<C>, ctype<D>) -> QueryShim<A, B, C, D>)
			& (<A, B, C, D, E>(WorldShim, ctype<A>, ctype<B>, ctype<C>, ctype<D>, ctype<E>) -> QueryShim<A, B, C, D, E>)
			& (<A, B, C, D, E, F>(WorldShim, ctype<A>, ctype<B>, ctype<C>, ctype<D>, ctype<E>, ctype<F>) -> QueryShim<A, B, C, D, E, F>)
			& (<A, B, C, D, E, F, G>(WorldShim, ctype<A>, ctype<B>, ctype<C>, ctype<D>, ctype<E>, ctype<F>, ctype<G>) -> QueryShim<A, B, C, D, E, F, G>)
			& (<A, B, C, D, E, F, G, H>(WorldShim, ctype<A>, ctype<B>, ctype<C>, ctype<D>, ctype<E>, ctype<F>, ctype<G>, ctype<H>) -> QueryShim<A, B, C, D, E, F, G, H>)
			& (<A, B, C, D, E, F, G, H, I>(WorldShim, ctype<A>, ctype<B>, ctype<C>, ctype<D>, ctype<E>, ctype<F>, ctype<G>, ctype<H>, ctype<I>) -> QueryShim<A, B, C, D, E, F, G, H, I>)
			& (<A, B, C, D, E, F, G, H, I, J>(WorldShim, ctype<A>, ctype<B>, ctype<C>, ctype<D>, ctype<E>, ctype<F>, ctype<G>, ctype<H>, ctype<I>, ctype<J>) -> QueryShim<A, B, C, D, E, F, G, H, I, J>)
			& (<A, B, C, D, E, F, G, H, I, J, K>(WorldShim, ctype<A>, ctype<B>, ctype<C>, ctype<D>, ctype<E>, ctype<F>, ctype<G>, ctype<H>, ctype<I>, ctype<J>, ctype<K>, ...ctype<any>) -> QueryShim<A, B, C, D, E, F, G, H, I, J, K>)
		
	},
	{} :: {
		__iter: (world: WorldShim) -> () -> (number, {[unknown]: unknown?})
	}

))

return table.freeze({
	World = (World :: any) :: {new: () -> WorldShim},

	OnAdd = (ON_ADD :: any) :: Component,
	OnRemove = (ON_REMOVE :: any) :: Component,
	OnSet = (ON_SET :: any) :: Component,
	Wildcard = (WILDCARD :: any) :: Component,
	w = (WILDCARD :: any) :: Component,
	Rest = REST,

	IS_PAIR = ECS_IS_PAIR,
	ECS_ID = ECS_ENTITY_T_LO,
	ECS_PAIR = ECS_PAIR,
	ECS_GENERATION_INC = ECS_GENERATION_INC,
	ECS_GENERATION = ECS_GENERATION,
	ECS_PAIR_RELATION = ECS_PAIR_RELATION,
	ECS_PAIR_OBJECT = ECS_PAIR_OBJECT,

	pair = (ECS_PAIR :: any) :: <R, T>(pred: Entity<R>, obj: Entity<T>) -> Relationship<R>,
	getAlive = getAlive
})
