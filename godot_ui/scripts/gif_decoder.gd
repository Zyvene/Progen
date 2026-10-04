class_name GifDecoder
extends RefCounted

const MIN_DELAY_S := 0.02
const DEFAULT_DELAY_S := 0.1

static func decode_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "cannot open %s" % path}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return decode(bytes)

static func _palette(bytes: PackedByteArray, start: int, entries: int) -> PackedInt32Array:
	var table := PackedInt32Array()
	table.resize(256)
	for i in range(entries):
		var o := start + i * 3
		table[i] = ((255 << 24) | (bytes[o + 2] << 16) | (bytes[o + 1] << 8) | bytes[o]) - 4294967296
	return table

static func _skip_sub_blocks(bytes: PackedByteArray, pos: int) -> int:
	while pos < bytes.size() and bytes[pos] != 0:
		pos += bytes[pos] + 1
	return pos + 1

static func _lzw(data: PackedByteArray, min_code_size: int, count: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(count)
	var prefix := PackedInt32Array()
	prefix.resize(4096)
	var suffix := PackedByteArray()
	suffix.resize(4096)
	var stack := PackedByteArray()
	stack.resize(4097)
	var clear := 1 << min_code_size
	var end_code := clear + 1
	for i in range(clear):
		suffix[i] = i
	var code_size := min_code_size + 1
	var mask := (1 << code_size) - 1
	var available := clear + 2
	var old := -1
	var first := 0
	var datum := 0
	var bits := 0
	var pos := 0
	var size := data.size()
	var op := 0
	while op < count:
		while bits < code_size and pos < size:
			datum |= data[pos] << bits
			bits += 8
			pos += 1
		if bits < code_size:
			break
		var code := datum & mask
		datum >>= code_size
		bits -= code_size
		if code == clear:
			code_size = min_code_size + 1
			mask = (1 << code_size) - 1
			available = clear + 2
			old = -1
			continue
		if code == end_code:
			break
		if old == -1:
			out[op] = suffix[code]
			op += 1
			old = code
			first = code
			continue
		var in_code := code
		var sp := 0
		if code >= available:
			stack[sp] = first
			sp += 1
			code = old
		while code > end_code:
			stack[sp] = suffix[code]
			sp += 1
			code = prefix[code]
		first = suffix[code]
		stack[sp] = first
		sp += 1
		if available < 4096:
			prefix[available] = old
			suffix[available] = first
			available += 1
			if (available & mask) == 0 and available < 4096:
				code_size += 1
				mask = (1 << code_size) - 1
		old = in_code
		while sp > 0 and op < count:
			sp -= 1
			out[op] = stack[sp]
			op += 1
	return out

static func _deinterlace(indices: PackedByteArray, width: int, height: int) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(indices.size())
	var row := 0
	for pass_info in [[0, 8], [4, 8], [2, 4], [1, 2]]:
		var y: int = pass_info[0]
		while y < height:
			for x in range(width):
				out[y * width + x] = indices[row * width + x]
			row += 1
			y += pass_info[1]
	return out

static func decode(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 13 or bytes.slice(0, 3).get_string_from_ascii() != "GIF":
		return {"ok": false, "error": "not a GIF file"}
	var width := bytes.decode_u16(6)
	var height := bytes.decode_u16(8)
	var flags := bytes[10]
	var background_index := bytes[11]
	var pos := 13
	var global_table := PackedInt32Array()
	if flags & 0x80:
		var entries := 1 << ((flags & 7) + 1)
		global_table = _palette(bytes, pos, entries)
		pos += entries * 3
	var background := Color(0, 0, 0, 0)
	if not global_table.is_empty():
		var packed := global_table[background_index]
		background = Color8(packed & 255, (packed >> 8) & 255, (packed >> 16) & 255, 255)
	var canvas := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	canvas.fill(background)
	var frames: Array = []
	var delays := PackedFloat32Array()
	var delay_s := DEFAULT_DELAY_S
	var disposal := 0
	var transparent := -1
	while pos < bytes.size():
		var block := bytes[pos]
		if block == 0x21:
			var label := bytes[pos + 1]
			pos += 2
			if label == 0xF9 and bytes[pos] >= 4:
				var packed_flags := bytes[pos + 1]
				var centiseconds := bytes.decode_u16(pos + 2)
				delay_s = DEFAULT_DELAY_S if centiseconds <= 1 else max(centiseconds / 100.0, MIN_DELAY_S)
				disposal = (packed_flags >> 2) & 7
				transparent = bytes[pos + 4] if packed_flags & 1 else -1
			pos = _skip_sub_blocks(bytes, pos)
		elif block == 0x2C:
			var x := bytes.decode_u16(pos + 1)
			var y := bytes.decode_u16(pos + 3)
			var w := bytes.decode_u16(pos + 5)
			var h := bytes.decode_u16(pos + 7)
			var image_flags := bytes[pos + 9]
			pos += 10
			var table := global_table
			if image_flags & 0x80:
				var local_entries := 1 << ((image_flags & 7) + 1)
				table = _palette(bytes, pos, local_entries)
				pos += local_entries * 3
			var min_code_size := bytes[pos]
			pos += 1
			var data := PackedByteArray()
			while pos < bytes.size() and bytes[pos] != 0:
				var length := bytes[pos]
				data.append_array(bytes.slice(pos + 1, pos + 1 + length))
				pos += length + 1
			pos += 1
			var count := w * h
			if count <= 0 or table.is_empty():
				continue
			var indices := _lzw(data, min_code_size, count)
			if image_flags & 0x40:
				indices = _deinterlace(indices, w, h)
			var lookup := table.duplicate()
			if transparent >= 0 and transparent < 256:
				lookup[transparent] = 0
			var pixels := PackedInt32Array()
			pixels.resize(count)
			for i in range(count):
				pixels[i] = lookup[indices[i]]
			var tile := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, pixels.to_byte_array())
			var previous: Image = canvas.duplicate() if disposal == 3 else null
			if transparent >= 0:
				canvas.blend_rect(tile, Rect2i(0, 0, w, h), Vector2i(x, y))
			else:
				canvas.blit_rect(tile, Rect2i(0, 0, w, h), Vector2i(x, y))
			var snapshot := canvas.duplicate()
			snapshot.convert(Image.FORMAT_RGB8)
			frames.append(snapshot)
			delays.append(delay_s)
			if disposal == 2:
				canvas.fill_rect(Rect2i(x, y, w, h), background)
			elif disposal == 3 and previous != null:
				canvas = previous
			delay_s = DEFAULT_DELAY_S
			disposal = 0
			transparent = -1
		elif block == 0x3B:
			break
		else:
			break
	if frames.is_empty():
		return {"ok": false, "error": "GIF has no frames"}
	return {"ok": true, "width": width, "height": height, "frames": frames, "delays": delays}
