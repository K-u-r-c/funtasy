class_name LegendaryAffixes
extends RefCounted
## Code hooks for the few legendary affixes (and keystones) that a data proc recipe cannot express.
## A proc names one with {"hook": "<id>", ...}; every hook is a function `hook_<id>`.

static var _probe: LegendaryAffixes


static func has_hook(id: String) -> bool:
	if _probe == null:
		_probe = LegendaryAffixes.new()
	return _probe.has_method("hook_" + id)
