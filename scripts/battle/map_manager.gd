extends RefCounted
class_name ZZMapManager

## Server sends map.chunks + walls; client loads image by stem (.jpg/.jpeg/.png/.webp).

const ASSET_DIR := "res://assets/maps/chunks/"
const _ASSET_EXTS := [".jpg", ".jpeg", ".png", ".webp"]


static func offset_to_axial(col: int, row: int) -> Vector2i:
	return Vector2i(col - int((row - (row & 1)) / 2), row)


static func axial_to_offset(q: int, r: int) -> Vector2i:
	return Vector2i(q + int((r - (r & 1)) / 2), r)


static func load_chunk_texture(asset: String) -> Texture2D:
	if asset.is_empty():
		return null
	for ext in _ASSET_EXTS:
		var path: String = ASSET_DIR + asset + ext
		if ResourceLoader.exists(path):
			return load(path) as Texture2D
	push_warning("ZZMapManager: missing chunk asset %s(.jpg/.png/…)" % (ASSET_DIR + asset))
	return null


static func chunk_pixel_size(w: int, h: int) -> Vector2:
	## Hex-map AABB for this chunk (ground sprite is scaled to this).
	return Vector2(ZZGridView.HEX_W * (float(w) + 0.5), ZZGridView.HEX_ROW * float(h))


static func chunk_origin_world(grid: ZZGridView, ox: int, oy: int) -> Vector2:
	## Top-left of chunk ground sprite in grid local space.
	return grid.grid_to_world(ox, oy) - Vector2(ZZGridView.HEX_W * 0.5, ZZGridView.HEX_ROW * 0.5)


static func apply_map_to_grid(grid: ZZGridView, map_dto: Variant) -> void:
	if grid == null:
		return
	if typeof(map_dto) != TYPE_DICTIONARY:
		grid.clear_chunk_grounds()
		return
	var md: Dictionary = map_dto
	var chunks: Array = md.get("chunks", [])
	grid.set_chunk_grounds(chunks)
