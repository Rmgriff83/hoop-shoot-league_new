extends RefCounted
## The Net Roster additions (Ross's design "Net Roster", 2026-10-25): two
## neon tints on the cotton body, the wool net in ocean and ember yarns, and
## the Rasta net on the red-white-blue build.


func run(t) -> void:
	var blue := CosmeticLibrary.get_net("neon_blue")
	var purple := CosmeticLibrary.get_net("neon_purple")
	t.ok(blue != null and blue.body_style() == "cotton" and blue.tint.to_html(false) == Color("#1AB8FF").to_html(false), "neon blue: the cotton body tinted #1AB8FF")
	t.ok(purple != null and purple.body_style() == "cotton" and purple.tint.to_html(false) == Color("#B43CFF").to_html(false), "neon purple: tinted #B43CFF")
	for id in ["wool_ocean", "wool_ember", "rasta"]:
		var ns := CosmeticLibrary.get_net(id)
		t.ok(ns != null and ns.kind == "cotton" and ns.body_style() == id and ns.validate().is_empty(), "%s is a valid cotton style" % id)
		t.ok(NetBodies.has_style(id) and NetBodies.kind_of(id) == "cotton", "%s is registered" % id)
	t.ok(NetBodies.for_style("wool_ocean") is WoolOceanNet and NetBodies.for_style("wool_ember") is WoolEmberNet and NetBodies.for_style("rasta") is RastaNet, "each style builds its own body")

	var root := Node3D.new()
	for spec in [["wool_ocean", WoolOceanNet.OCEAN], ["wool_ember", WoolEmberNet.EMBER]]:
		var body: NetRig = NetBodies.for_style(spec[0])
		root.add_child(body)
		var lay := NetBodies.layout(spec[0])
		body.call("build", lay)
		t.eq(body.bone_count(), 109, "%s: the wool rig (109 bones)" % spec[0])
		var cords := body.skeleton.get_node("Net_Cords") as MeshInstance3D
		var seen := {}
		for c in cords.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
			seen[(c as Color).to_html(false)] = true
		var want := {}
		for h in spec[1]:
			want[Color(h).to_html(false)] = true
		t.eq(seen.size(), 12, "%s: twelve yarns" % spec[0])
		var match_all := true
		for k in seen:
			if not want.has(k):
				match_all = false
		t.ok(match_all, "%s: the design's yarns, and only those" % spec[0])
		t.eq((lay["knots"] as PackedVector3Array), (WoolNet.layout()["knots"] as PackedVector3Array), "%s: the wool net's hand-tied layout" % spec[0])
	var rasta: NetRig = NetBodies.for_style("rasta")
	root.add_child(rasta)
	rasta.call("build", NetBodies.layout("rasta"))
	var rc := rasta.skeleton.get_node("Net_Cords") as MeshInstance3D
	var bands := {}
	for c in rc.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]:
		bands[(c as Color).to_html(false)] = true
	t.eq(bands.size(), 3, "rasta: three bands")
	t.ok(bands.has(Color("#D8322E").to_html(false)) and bands.has(Color("#F2C21B").to_html(false)) and bands.has(Color("#1F8A3C").to_html(false)), "…red, gold, green")
	t.eq(RastaNet.rasta_band(0), Color("#D8322E"), "red on top")
	t.eq(RastaNet.rasta_band(2), Color("#F2C21B"), "gold in the middle")
	t.eq(RastaNet.rasta_band(5), Color("#1F8A3C"), "green at the bottom")
	var rwb := RwbNet.new()
	t.eq(rwb._band(0), Color(RwbNet.RED), "the red-white-blue net keeps its own bands")
	rwb.free()
	root.free()
