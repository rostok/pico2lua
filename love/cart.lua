local api = require("love/api")

local parse = require("parser/ParseLua")
local format = require("parser/FormatPico8")
local util = require("parser/Util")

pico8_glyphs = { [0] = "\0",
	"¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "\t", "\n", "ᵇ",
	"ᶜ", "\r", "ᵉ", "ᶠ", "▮", "■", "□", "⁙", "⁘", "‖", "◀",
	"▶", "「", "」", "¥", "•", "、", "。", "゛", "゜", " ", "!",
	"\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",", "-", ".", "/", "0",
	"1", "2", "3", "4", "5", "6", "7", "8", "9", ":", ";", "<", "=", ">", "?",
	"@", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N",
	"O", "P", "Q", "R", "S", "T", "U", "V", "W", "X", "Y", "Z", "[", "\\", "]",
	"^", "_", "`", "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
	"m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "{",
	"|", "}", "~", "○", "█", "▒", "🐱", "⬇️", "░", "✽", "●",
	"♥", "☉", "웃", "⌂", "⬅️", "😐", "♪", "🅾️", "◆",
	"…", "➡️", "★", "⧗", "⬆️", "ˇ", "∧", "❎", "▤", "▥",
	"あ", "い", "う", "え", "お", "か", "き", "く", "け", "こ", "さ",
	"し", "す", "せ", "そ", "た", "ち", "つ", "て", "と", "な", "に",
	"ぬ", "ね", "の", "は", "ひ", "ふ", "へ", "ほ", "ま", "み", "む",
	"め", "も", "や", "ゆ", "よ", "ら", "り", "る", "れ", "ろ", "わ",
	"を", "ん", "っ", "ゃ", "ゅ", "ょ", "ア", "イ", "ウ", "エ", "オ",
	"カ", "キ", "ク", "ケ", "コ", "サ", "シ", "ス", "セ", "ソ", "タ",
	"チ", "ツ", "テ", "ト", "ナ", "ニ", "ヌ", "ネ", "ノ", "ハ", "ヒ",
	"フ", "ヘ", "ホ", "マ", "ミ", "ム", "メ", "モ", "ヤ", "ユ", "ヨ",
	"ラ", "リ", "ル", "レ", "ロ", "ワ", "ヲ", "ン", "ッ", "ャ", "ュ",
	"ョ", "◜", "◝"
}

local compression_map = {}
for entry in
	("\n 0123456789abcdefghijklmnopqrstuvwxyz!#%(){}[]<>+=/*:;.,~_"):gmatch(".")
do
	table.insert(compression_map, entry)
end

local function decompress(code)
	local lua = ""
	local mode = 0
	local copy = nil
	local i = 8
	local codelen = bit.lshift(code:byte(5, 5), 8) + code:byte(6, 6)
	log("codelen", codelen)
	while #lua < codelen do
		i = i + 1
		local byte = string.byte(code, i, i)
		if byte == nil then
			error("reached end of code")
		else
			if mode == 1 then
				lua = lua .. code:sub(i, i)
				mode = 0
			elseif mode == 2 then
				-- copy from buffer
				local offset = (copy - 0x3c) * 16 + bit.band(byte, 0xf)
				local length = bit.rshift(byte, 4) + 2
				offset = #lua - offset
				local buffer = lua:sub(offset + 1, offset + length)
				lua = lua .. buffer
				mode = 0
			elseif byte == 0x00 then
				-- output next byte
				mode = 1
			elseif byte >= 0x01 and byte <= 0x3b then
				-- output this byte from map
				lua = lua .. compression_map[byte]
			elseif byte >= 0x3c then
				-- copy previous bytes
				mode = 2
				copy = byte
			end
		end
	end
	return lua
end

local cart = {}

function cart.load_p8(filename)
	log("Loading", filename)

	local lua = ""

	if false then
	else
		local data, size = api.readFile(filename)
		if not data or size == 0 then
			error(string.format("Unable to open: %s", filename))
		end

		-- strip carriage returns pico-8 style
		data = data:gsub("\r\n", "\n")
		-- tack on a fake header
		if data:sub(-1) ~= "\n" then
			data = data .. "\n"
		end
		data = data .. "__eof__\n"

		-- check for header and version
		local header = "pico%-8 cartridge"
		local header_len = #header - 1 -- subtract escape char
		local version_header = "\nversion"

		local header_start = data:find(header)
		if header_start == nil then
			print("creating missing header")
			data = "pico-8 cartridge // http://www.pico-8.com\nversion 41\n__lua__\n"..data
			header_start = data:find(header)
		end

		if header_start == nil then
			error("invalid cart (missing header)")
		end

		local header_end = data:find(version_header, header_start + header_len)
		if header_end == nil then
			error("invalid cart (missing header-version)")
		end
		if header_end ~= data:find("\n", header_start + header_len) then
			error("invalid cart (malformed header)")
		end
		header_end = header_end + #version_header

		local next_line = data:find("\n", header_end)
		if next_line == nil then
			error("invalid cart (incomplete header)")
		end

		local version_str = data:sub(header_end, next_line - 1)
		local version = tonumber(version_str)
		log("version", version)

		-- extract the lua
		lua = data:match("\n__lua__.-\n(.-)\n__[%w]+__") or ""
		-- rostok: add newllines so that line numbering will match that of p8 file
        local prefix = data:match("(.-)__lua__\n")
        if prefix then
          lua = prefix:gsub("[^\n]", "").."\n"..lua
        end

		local shared = 0

	end

	local orglua = patch_lua(lua)
	--api.writeFile("_code.lua",lua);
	lua = patch_lua(lua)
	--api.writeFile("_code_patched.lua",lua);
	--lua = lua .. "\n_picolove_end()"

	--log("finished loading cart", filename)

	loaded_code = lua

	return loaded_code, orglua
end

function patch_lua(lua)
	--replace glyphs with respective ascii chars

	-- very carefully replace these glyphs with the respective ascii chars
	-- need to be careful because utf-8 and extended ascii are not compatible, and some of the glyphs are more than 1 char (even more than 1 utf8 char)
	--
	-- TODO: optimize this code

	local gmatch_magic = util.lookupify{'(', ')', '.', '%', '+', '-', '*', '?', '[', '^', '$'}
	local i = 1
	while i<=#lua do
		local c = lua:sub(i,i)
		if string.byte(c) >= 128 then
			for n, gl in ipairs(pico8_glyphs) do
				local escaped_gl
				if gmatch_magic[gl] then
					escaped_gl = "%"..gl
				else
					escaped_gl = gl
				end

				if lua:sub(i):match("^"..escaped_gl) then
					lua = lua:sub(1,i-1) .. lua:sub(i):gsub("^"..escaped_gl,string.char(n))
					break
				end
			end
		end
		i=i+1
	end


	-- not strictly required, but should help improve performance
	lua = "local _ENV = _ENV " .. lua

	local status, ast =parse.ParseLua(lua)
	if not status then
		error(ast)
	end
	local status, patched = format(ast)
	if not status then
		error(patched)
	end
	-- print(patched)
	return patched
end

return cart
