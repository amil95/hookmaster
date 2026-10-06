extends SceneTree

const TILE_SIZE := Vector2i(64, 64)
const OUTPUT_PATH := "res://tilesets/ground_tileset.tres"
const TEXTURE_PATH := "res://assets/kenney/new_platformer/terrain_grass_horizontal_middle.png"
const WALL_TEXTURE_PATH := "res://assets/kenney/new_platformer/terrain_grass_vertical_middle.png"

func _init() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = TILE_SIZE
	tile_set.add_physics_layer()
	tile_set.set_physics_layer_collision_layer(0, 1)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(TEXTURE_PATH)
	atlas.texture_region_size = TILE_SIZE
	tile_set.add_source(atlas, 0)
	atlas.create_tile(Vector2i.ZERO)

	var tile_data := atlas.get_tile_data(Vector2i.ZERO, 0)
	tile_data.add_collision_polygon(0)
	tile_data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-32, -32), Vector2(32, -32), Vector2(32, 32), Vector2(-32, 32)
	]))
	atlas.emit_changed()

	var wall_atlas := TileSetAtlasSource.new()
	wall_atlas.texture = ResourceLoader.load(WALL_TEXTURE_PATH, "Texture2D")
	wall_atlas.texture_region_size = TILE_SIZE
	tile_set.add_source(wall_atlas, 1)
	wall_atlas.create_tile(Vector2i.ZERO)
	var wall_tile_data := wall_atlas.get_tile_data(Vector2i.ZERO, 0)
	wall_tile_data.add_collision_polygon(0)
	wall_tile_data.set_collision_polygon_points(0, 0, PackedVector2Array([
		Vector2(-32, -32), Vector2(32, -32), Vector2(32, 32), Vector2(-32, 32)
	]))
	wall_atlas.emit_changed()
	tile_set.emit_changed()
	ResourceSaver.save(tile_set, OUTPUT_PATH)
	quit()
