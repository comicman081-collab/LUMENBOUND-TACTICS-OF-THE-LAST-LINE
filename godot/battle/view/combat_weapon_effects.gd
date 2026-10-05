extends RefCounted
const CachedDraw := preload("res://battle/view/battle_cached_draw.gd")

## Small, bounded vector accents connect weapon intent to contact. They are
## attached to the acting weapon/target, never full-screen particle noise.
static func family(id: String, role: String) -> String:
	var named := {"CHR001":"shield", "CHR002":"blade", "CHR003":"rifle", "CHR004":"burst", "CHR005":"mortar", "CHR006":"prism", "CHR007":"seal", "CHR008":"heal", "ENM001":"claw", "ENM002":"rifle", "ENM003":"shield", "BOSS001":"siege"}
	if named.has(id): return str(named[id])
	return str({"GUARDIAN":"shield", "DEFENDER":"shield", "VANGUARD":"blade", "MELEE_RUSH":"claw", "ASSAULT":"rifle", "RANGED":"rifle", "ARTILLERY":"mortar", "AREA":"siege", "MEDIC":"heal", "HEALER":"heal", "SPECIALIST":"prism", "BUFFER":"seal"}.get(role,"seal"))

static func ellipse(c: CanvasItem, p: Vector2, radius: Vector2, color: Color, width: float) -> void:
	var line := PackedVector2Array()
	for i in range(41):
		var a := TAU * float(i) / 40.0
		line.append(p + Vector2(cos(a), sin(a)) * radius)
	c.draw_polyline(line, color, width, true)

static func telegraph(c: CanvasItem, target: Vector2, style: String, elapsed: float, contact: float, hostile: bool, strength: float) -> void:
	if elapsed >= contact or elapsed < maxf(0.0,contact-.42): return
	var t := clampf(1.0-(contact-elapsed)/.42,0,1)
	var radius := (62.0 if style in ["mortar","siege"] else 35.0) * strength
	var color := Color("ff9464") if hostile else Color("7bdeed")
	color.a = .30 + .40 * t
	ellipse(c,target,Vector2(radius*(1.35-t*.35),radius*.30),color,2.0*strength)
	if style in ["mortar","siege"]:
		for i in range(4):
			var offset := Vector2.RIGHT.rotated(PI*.5*i)*radius
			c.draw_line(target+offset*.7,target+offset,color,2.0*strength,true)

static func action(c: CanvasItem, origin: Vector2, target: Vector2, style: String, elapsed: float, action_name: String, color: Color, strength: float) -> void:
	var ultimate := action_name == "ultimate"
	var melee := style in ["blade","claw","shield"]
	var release := (1.10 if melee else .82) if ultimate else (.40 if melee else .14)
	var age := elapsed-release
	var direction := (target-origin).normalized()
	if direction.length_squared()<.01: direction=Vector2.RIGHT
	var normal := Vector2(-direction.y,direction.x)
	var size := strength * (1.35 if ultimate else 1.0)
	if style in ["blade","claw"]:
		if age < -.06 or age > .22: return
		var t := clampf((age+.06)/.28,0,1)
		var radius := (68.0 if style=="blade" else 47.0)*size
		for slash in range(3 if style=="claw" else 1):
			var center := origin+direction*26.0*size+normal*(slash-1)*12.0*size
			var angle := direction.angle()-.95+t*1.20
			var arc := PackedVector2Array()
			for i in range(17):
				var a := angle+float(i)/16.0*.9
				arc.append(center+Vector2(cos(a),sin(a))*radius)
			var tint := color; tint.a = sin(t*PI)*.90
			c.draw_polyline(arc,tint,7.0*size,true)
			c.draw_polyline(arc,Color(1,.98,.88,tint.a),2.0*size,true)
			if style == "blade":
				# Slash trail: three ghost arcs lag behind the leading edge.
				for ghost in range(1,4):
					var lag := t-float(ghost)*.09
					if lag <= 0.0: continue
					var ghost_angle := direction.angle()-.95+lag*1.20
					var ghost_arc := PackedVector2Array()
					for i in range(13):
						var a := ghost_angle+float(i)/12.0*.9
						ghost_arc.append(center+Vector2(cos(a),sin(a))*(radius-float(ghost)*3.0*size))
					c.draw_polyline(ghost_arc,Color(color.r,color.g,color.b,sin(lag*PI)*.46/float(ghost)),(7.0-float(ghost)*1.6)*size,true)
	elif style in ["rifle","burst","mortar","siege"]:
		if age < 0 or age > .22: return
		var alpha := 1.0-age/.22
		var length := (43.0 if style in ["mortar","siege"] else 29.0)*size
		var flare := PackedVector2Array([origin-direction*5*size,origin+direction*length*.42+normal*11*size,origin+direction*length,origin+direction*length*.42-normal*11*size])
		CachedDraw.fill(c, flare,Color(color.r,color.g,color.b,alpha*.88))
		c.draw_line(origin,origin+direction*length,Color(1,.98,.90,alpha),4*size,true)
		CachedDraw.disc(c, origin+direction*length*.12,(7.0+4.0*alpha)*size,Color(1,.97,.80,alpha*.85))
		if style in ["rifle","burst"] and age < .16:
			# Tracer: a thin hot streak runs from the muzzle towards the target.
			var run := clampf(age/.14,0.0,1.0)
			var reach := origin.distance_to(target)
			var head := origin+direction*reach*run
			var tail := origin+direction*maxf(0.0,reach*run-46.0*size)
			c.draw_line(tail,head,Color(color.r,color.g,color.b,(1.0-run*.5)*.55),3.0*size,true)
			c.draw_line(origin.lerp(head,.45).lerp(tail,.0),head,Color(1,.98,.90,(1.0-run*.5)*.85),1.6*size,true)
		if style=="burst":
			for i in range(3):
				var start := origin+direction*(age*620.0+i*26.0)*size
				c.draw_line(start,start+direction*21*size,Color(color.r,color.g,color.b,alpha*.7),3*size,true)
		elif style in ["mortar","siege"]:
			c.draw_arc(origin,12*size+age*80*size,0,TAU,24,Color(1,.78,.38,alpha*.6),3*size,true)
			CachedDraw.disc(c, origin+direction*length*.5+Vector2(0,-age*60.0*size),(9.0+age*50.0)*size,Color(.42,.36,.33,alpha*.35))
	elif style=="shield":
		if age < -.12 or age > .25: return
		var t := clampf((age+.12)/.37,0,1)
		var center := origin+direction*28*size
		var radius := 35*size*(.7+t*.6)
		c.draw_arc(center,radius,direction.angle()-1.1,direction.angle()+1.1,24,Color(color.r,color.g,color.b,sin(t*PI)*.9),8*size,true)
	else:
		if elapsed > release+.22: return
		var t := clampf(elapsed/maxf(.01,release),0,1)
		var radius := (18.0+16.0*t)*size
		var sides := 4 if style=="prism" else 6
		var ring := PackedVector2Array()
		for i in range(sides+1):
			var a := float(i)/sides*TAU+elapsed*1.5
			ring.append(origin+Vector2(cos(a),sin(a))*radius)
		c.draw_polyline(ring,Color(color.r,color.g,color.b,.3+t*.5),2.5*size,true)
		if style=="heal":
			c.draw_line(origin-normal*radius*.45,origin+normal*radius*.45,Color(.8,1,.9,.9),4*size,true)
			c.draw_line(origin-direction*radius*.45,origin+direction*radius*.45,Color(.8,1,.9,.9),4*size,true)

static func impact(c: CanvasItem, p: Vector2, style: String, t: float, color: Color, strength: float, accent := "") -> void:
	var fade := 1.0-smoothstep(.15,1.0,t)
	var r := (22+48*t)*strength
	# Contact spark: a white core for the first two or three frames, matching
	# the victim's white flash.
	if t < .12:
		var core := 1.0-t/.12
		CachedDraw.disc(c, p,(12.0+13.0*core)*strength,Color(1,1,1,.85*core))
	if style in ["blade","claw"]:
		for i in range(3 if style=="claw" else 2):
			var offset := Vector2((i-1)*13,0)*strength
			var dir := Vector2(.65,-.76 if i%2==0 else .76)
			c.draw_line(p+offset-dir*r,p+offset+dir*r,Color(color.r,color.g,color.b,fade),5*strength,true)
			c.draw_line(p+offset-dir*r*.7,p+offset+dir*r*.7,Color(1,.98,.90,fade),2*strength,true)
		if style=="blade":
			for i in range(5):
				var spark_dir := Vector2.RIGHT.rotated(-.9+float(i)*.45)
				c.draw_line(p+spark_dir*r*.55,p+spark_dir*r*(.75+t*.45),Color(1,.95,.75,fade*.8),1.8*strength,true)
	elif style in ["mortar","siege"]:
		ellipse(c,p+Vector2(0,30*strength),Vector2(r*1.8,r*.36),Color(color.r,color.g,color.b,fade*.9),4*strength)
		for i in range(9):
			var direction := Vector2.RIGHT.rotated(float(i)/9*TAU)
			var tip := p+direction*r+Vector2(0,t*t*45*strength)
			c.draw_line(tip-direction*11*strength,tip,Color(1,.83,.56,fade),3*strength,true)
		# Explosion: layered fireball, rising smoke and a scorch under it.
		var ball := r*.62*(1.0-t*.35)
		CachedDraw.disc(c, p,ball,Color(1.0,.42,.14,fade*.55))
		CachedDraw.disc(c, p,ball*.66,Color(1.0,.74,.32,fade*.75))
		CachedDraw.disc(c, p,ball*.32,Color(1.0,.96,.80,fade))
		CachedDraw.disc(c, p+Vector2(0,-t*30.0*strength),r*.46*(.6+t),Color(.24,.21,.21,(1.0-t)*.34))
		for i in range(6):
			var debris_dir := Vector2.RIGHT.rotated(float(i)*1.05+.4)
			var debris := p+debris_dir*r*(.45+t*.8)+Vector2(0,t*t*58.0*strength)
			c.draw_rect(Rect2(debris-Vector2(2,2)*strength,Vector2(4,4)*strength),Color(.98,.76,.42,fade))
	elif style in ["rifle","burst"]:
		for i in range(5):
			var d := Vector2.RIGHT.rotated(float(i)*TAU/5+.35)
			c.draw_line(p+d*r*.15,p+d*r,Color(1,.96,.79,fade),2.5*strength,true)
	elif style in ["prism","seal"]:
		# Magic sigil: a rotating hexagram on the ground under the target.
		var centre := p+Vector2(0,58*strength)
		var sigil := Vector2(r*1.35,r*.36)
		var spin := t*2.4
		ellipse(c,centre,sigil,Color(color.r,color.g,color.b,fade*.9),2.6*strength)
		ellipse(c,centre,sigil*.62,Color(color.r,color.g,color.b,fade*.6),1.6*strength)
		for triangle in range(2):
			var tri := PackedVector2Array()
			for corner in range(4):
				var a := spin+float(triangle)*PI/3.0+float(corner%3)*TAU/3.0
				tri.append(centre+Vector2(cos(a)*sigil.x*.9,sin(a)*sigil.y*.9))
			c.draw_polyline(tri,Color(1,.97,.88,fade*.85),1.8*strength,true)
		c.draw_arc(p,r*.7,0,TAU,28,Color(color.r,color.g,color.b,fade*.75),2.4*strength,true)
		for i in range(4):
			var rune := p+Vector2.RIGHT.rotated(spin*1.6+float(i)*TAU/4.0)*r*.7
			CachedDraw.disc(c, rune,2.2*strength,Color(1,.97,.88,fade))
	elif style=="shield":
		c.draw_arc(p,r,0,TAU,32,Color(color.r,color.g,color.b,fade),3*strength,true)
		for i in range(6):
			var plate_dir := Vector2.RIGHT.rotated(float(i)*TAU/6.0+.5)
			c.draw_line(p+plate_dir*r*.78,p+plate_dir*r*1.18,Color(1,.97,.88,fade*.85),2.4*strength,true)
	else:
		c.draw_arc(p,r,0,TAU,32,Color(color.r,color.g,color.b,fade),3*strength,true)
	if accent=="crit":
		# Critical: eight gold spokes, alternating long and short.
		for i in range(8):
			var spoke := Vector2.RIGHT.rotated(TAU*float(i)/8.0+.2)
			c.draw_line(p+spoke*r*.35,p+spoke*r*(1.3 if i%2==0 else 1.0),Color(1.0,.83,.30,fade),(4.5 if i%2==0 else 2.5)*strength,true)
	elif accent=="weak":
		# Weak point: a cyan ring and an up chevron over the hit.
		c.draw_arc(p,r*.92,0,TAU,28,Color(.55,.92,1.0,fade*.9),2.2*strength,true)
		var tip := p+Vector2(0,-r*1.1)
		CachedDraw.fill(c, PackedVector2Array([tip,tip+Vector2(-8,11)*strength,tip+Vector2(8,11)*strength]),Color(.55,.92,1.0,fade*.9))
