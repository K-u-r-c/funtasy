class_name LoreCycle
extends RefCounted
## #76 The legendary tomes are one story in chapters (lore books with "cycle" / "chapter"): the
## Ownerless Book, I-V. They are found in order - chapter N drops only once the party (any hero)
## has read chapter N-1 in this run, and a chapter already out on this run doesn't drop again.
## The run's record ({read: [ids], dropped: [ids]}) is kept in GameState.game, so it is saved
## with the game and gone with a wipe. Host-side.


## The cycle's chapter ids in order.
static func chapters(cycle: String = "") -> Array:
	var out: Array = []
	for id in GameData.lore_order:
		var b: Dictionary = GameData.lore_books[id]
		if b.has("chapter") and (cycle.is_empty() or str(b.cycle) == cycle):
			out.append(id)
	out.sort_custom(func(a, b): return int(GameData.lore_books[a].chapter) < int(GameData.lore_books[b].chapter))
	return out


static func record() -> Dictionary:
	if not GameState.game.has("cycle"):
		GameState.game["cycle"] = {"read": [], "dropped": []}
	return GameState.game["cycle"]


## The chapter that may drop now ("" = none: the next one is already out, or all were read).
static func next_droppable() -> String:
	var rec := record()
	var read: Array = rec.get("read", [])
	for id in chapters():
		if read.has(id):
			continue
		return "" if Array(rec.get("dropped", [])).has(id) else str(id)
	return ""


static func note_dropped(id: String) -> void:
	var rec := record()
	if not Array(rec.dropped).has(id):
		rec.dropped.append(id)


## Records a chapter as read on this run; false when it was read before (no second reward).
static func note_read(id: String) -> bool:
	var rec := record()
	if Array(rec.read).has(id):
		return false
	rec.read.append(id)
	return true


## "Chapter II of V" for a chapter of a cycle, "" otherwise.
static func chapter_text(book: Dictionary) -> String:
	if not book.has("chapter"):
		return ""
	return Loc.f("Chapter %s of %s", [roman(int(book.chapter)), roman(int(book.get("chapters", 5)))])


static func roman(n: int) -> String:
	return ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][clampi(n, 0, 10)]
