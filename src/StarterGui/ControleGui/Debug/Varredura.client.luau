-- ============================================================
--  VARREDURA DE GUI — dump completo da hierarquia + propriedades
--  ONDE COLOCAR: dentro da ScreenGui que você quer escanear
--                (Insert Object > LocalScript, cole isto, dê Play)
--  RESULTADO: sai no Output (F9). Selecione tudo (Ctrl+A) e me mande.
-- ============================================================

local ALVO = script:FindFirstAncestorOfClass("ScreenGui") or script.Parent -- o que será escaneado (normalmente a ScreenGui)

-- Propriedades candidatas. São lidas com pcall; as que a classe não tiver
-- são ignoradas automaticamente. Cobre praticamente tudo de GUI.
local PROPS = {
	-- GuiObject (base)
	"Visible",
	"Active",
	"AnchorPoint",
	"Position",
	"Size",
	"Rotation",
	"ZIndex",
	"LayoutOrder",
	"ClipsDescendants",
	"AutomaticSize",
	"SizeConstraint",
	"BackgroundColor3",
	"BackgroundTransparency",
	"BorderColor3",
	"BorderSizePixel",
	"BorderMode",
	-- Image*
	"Image",
	"ImageColor3",
	"ImageTransparency",
	"ScaleType",
	"SliceCenter",
	"SliceScale",
	"TileSize",
	"ResampleMode",
	"ImageRectOffset",
	"ImageRectSize",
	-- Text*
	"Text",
	"TextColor3",
	"TextTransparency",
	"TextSize",
	"TextScaled",
	"TextWrapped",
	"RichText",
	"Font",
	"FontFace",
	"LineHeight",
	"TextXAlignment",
	"TextYAlignment",
	"TextStrokeColor3",
	"TextStrokeTransparency",
	"TextTruncate",
	"PlaceholderText",
	"PlaceholderColor3",
	"ClearTextOnFocus",
	"MultiLine",
	-- ScrollingFrame
	"CanvasSize",
	"CanvasPosition",
	"ScrollBarThickness",
	"ScrollBarImageColor3",
	"ScrollBarImageTransparency",
	"AutomaticCanvasSize",
	"ScrollingDirection",
	"ElasticBehavior",
	"VerticalScrollBarInset",
	"HorizontalScrollBarInset",
	-- ViewportFrame
	"Ambient",
	"LightColor",
	"LightDirection",
	-- ScreenGui
	"Enabled",
	"IgnoreGuiInset",
	"ResetOnSpawn",
	"DisplayOrder",
	"ZIndexBehavior",
	"ScreenInsets",
	"ClipToDeviceSafeArea",
	-- UICorner / UIStroke / UIGradient / UIPadding
	"CornerRadius",
	"Color",
	"Thickness",
	"ApplyStrokeMode",
	"LineJoinMode",
	"Transparency",
	"Offset",
	"PaddingTop",
	"PaddingBottom",
	"PaddingLeft",
	"PaddingRight",
	-- Layouts / Constraints
	"FillDirection",
	"HorizontalAlignment",
	"VerticalAlignment",
	"SortOrder",
	"Padding",
	"Wraps",
	"ItemLineAlignment",
	"HorizontalFlex",
	"VerticalFlex",
	"CellSize",
	"CellPadding",
	"FillDirectionMaxCells",
	"StartCorner",
	"AspectRatio",
	"AspectType",
	"DominantAxis",
	"Scale",
	"MinSize",
	"MaxSize",
	"MinTextSize",
	"MaxTextSize",
}

local function round(n)
	return math.floor(n * 1000 + 0.5) / 1000
end

local function serializar(v)
	local t = typeof(v)
	if t == "string" then
		return string.format("%q", v)
	elseif t == "number" then
		return tostring(round(v))
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "EnumItem" then
		return tostring(v)
	elseif t == "UDim" then
		return string.format("UDim(%s, %s)", round(v.Scale), v.Offset)
	elseif t == "UDim2" then
		return string.format("{%s, %s | %s, %s}", round(v.X.Scale), v.X.Offset, round(v.Y.Scale), v.Y.Offset)
	elseif t == "Vector2" then
		return string.format("(%s, %s)", round(v.X), round(v.Y))
	elseif t == "Vector3" then
		return string.format("(%s, %s, %s)", round(v.X), round(v.Y), round(v.Z))
	elseif t == "Color3" then
		return string.format("RGB(%d, %d, %d)", math.round(v.R * 255), math.round(v.G * 255), math.round(v.B * 255))
	elseif t == "Rect" then
		return string.format("Rect(%s, %s, %s, %s)", v.Min.X, v.Min.Y, v.Max.X, v.Max.Y)
	elseif t == "NumberRange" then
		return string.format("Range(%s, %s)", v.Min, v.Max)
	elseif t == "Font" then
		return string.format("Font(%q, %s, %s)", v.Family, tostring(v.Weight), tostring(v.Style))
	elseif t == "ColorSequence" then
		local p = {}
		for _, k in ipairs(v.Keypoints) do
			table.insert(
				p,
				string.format(
					"%s:RGB(%d,%d,%d)",
					round(k.Time),
					math.round(k.Value.R * 255),
					math.round(k.Value.G * 255),
					math.round(k.Value.B * 255)
				)
			)
		end
		return "ColorSeq[" .. table.concat(p, ", ") .. "]"
	elseif t == "NumberSequence" then
		local p = {}
		for _, k in ipairs(v.Keypoints) do
			table.insert(p, string.format("%s:%s", round(k.Time), round(k.Value)))
		end
		return "NumberSeq[" .. table.concat(p, ", ") .. "]"
	elseif t == "Instance" then
		return "<" .. v.ClassName .. " " .. v.Name .. ">"
	else
		return tostring(v)
	end
end

local linhas = {}
local function add(s)
	table.insert(linhas, s)
end

local function escanear(inst, profundidade)
	local ind = string.rep("  ", profundidade)
	add(ind .. "[" .. inst.ClassName .. "] " .. inst.Name)

	-- propriedades (. prop = valor)
	local vistos = {}
	for _, prop in ipairs(PROPS) do
		if not vistos[prop] then
			vistos[prop] = true
			local ok, val = pcall(function()
				return inst[prop]
			end)
			if ok and val ~= nil then
				add(ind .. "   . " .. prop .. " = " .. serializar(val))
			end
		end
	end

	-- attributes (@ nome = valor)
	for nome, val in pairs(inst:GetAttributes()) do
		add(ind .. "   @ " .. nome .. " = " .. serializar(val))
	end

	-- filhos (pula este próprio script)
	for _, filho in ipairs(inst:GetChildren()) do
		if filho ~= script then
			escanear(filho, profundidade + 1)
		end
	end
end

escanear(ALVO, 0)
add("")
add("===== FIM DA VARREDURA (" .. #linhas .. " linhas) =====")

-- imprime em blocos p/ não truncar no Output
local BLOCO = 40
for i = 1, #linhas, BLOCO do
	print(table.concat(linhas, "\n", i, math.min(i + BLOCO - 1, #linhas)))
end
