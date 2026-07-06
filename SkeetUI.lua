--[[
	SkeetUI — gamesense/skeet-style UI library for Roblox executors
	Author: built for zenn
	Version: 2.1.0 (pixel-matched to reference screenshot)
	Font: Verdana Bold requested — Roblox has no Verdana, so Arial Bold
	      (the closest built-in metric match) is used everywhere.

	Usage:
		local Skeet = loadstring(game:HttpGet("<raw url>/SkeetUI.lua"))()
		Skeet:CreateLogin({ ... })  -- optional login screen
		local Window = Skeet:CreateWindow({ ... })
]]

--// Services
local TweenService = game:GetService("TweenService")
local UserInput    = game:GetService("UserInputService")
local Players      = game:GetService("Players")
local CoreGui      = game:GetService("CoreGui")
local HttpService  = game:GetService("HttpService")

local LocalPlayer  = Players.LocalPlayer

--// Library root
local Library = {
	Flags       = {},
	Items       = {},
	Connections = {},
	Unloaded    = false,
	ToggleKey   = Enum.KeyCode.Delete, -- skeet uses DEL
}

--// Theme (pixel-sampled from the reference screenshot)
local Theme = {
	Sidebar      = Color3.fromRGB(12, 12, 12),
	SidebarTab   = Color3.fromRGB(12, 12, 12),
	SidebarOn    = Color3.fromRGB(17, 17, 17),
	Content      = Color3.fromRGB(17, 17, 17),
	Groupbox     = Color3.fromRGB(17, 17, 17),  -- same as content; only border differs
	Element      = Color3.fromRGB(35, 35, 35),  -- dropdown/button fill
	ElementDark  = Color3.fromRGB(35, 35, 35),
	ElementHover = Color3.fromRGB(42, 42, 42),
	BorderDark   = Color3.fromRGB(0, 0, 0),
	BorderLight  = Color3.fromRGB(48, 48, 48),
	CheckOffTop  = Color3.fromRGB(76, 76, 76),  -- checkbox-off gradient top
	CheckOffBot  = Color3.fromRGB(49, 49, 49),  -- checkbox-off gradient bottom
	Track        = Color3.fromRGB(1, 1, 1),     -- slider empty track (near black)
	Text         = Color3.fromRGB(210, 210, 210),
	TextDark     = Color3.fromRGB(97, 97, 97),  -- keybind tags [M5]
	TextDisabled = Color3.fromRGB(90, 90, 90),
	Accent       = Color3.fromRGB(149, 184, 45),   -- lime for active labels
	AccentTop    = Color3.fromRGB(161, 191, 74),   -- slider/checkbox fill gradient top
	AccentBot    = Color3.fromRGB(105, 141, 31),   -- slider/checkbox fill gradient bottom
	Error        = Color3.fromRGB(224, 82, 82),
}
Theme.CheckOff = Theme.CheckOffBot
Library.Theme = Theme

--// Font: Verdana Bold requested; Arial Bold is the closest Roblox built-in.
local FONT      = Enum.Font.ArialBold
local FONT_SIZE = 12

local TWEEN_FAST = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

--// Utilities -----------------------------------------------------------------

local function Tween(o, i, p)
	local t = TweenService:Create(o, i, p)
	t:Play()
	return t
end

local function Connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(Library.Connections, c)
	return c
end

local function Create(class, props, children)
	local inst = Instance.new(class)
	for k, v in pairs(props or {}) do
		if k ~= "Parent" then inst[k] = v end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if props and props.Parent then inst.Parent = props.Parent end
	return inst
end

-- skeet-style double border: 1px pure-black outline + 1px (48,48,48) inner line
local function DoubleBorder(inst)
	Create("UIStroke", {
		Color = Theme.BorderDark,
		Thickness = 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
	local inner = Create("Frame", {
		Name = "InnerHighlight",
		Size = UDim2.new(1, -2, 1, -2),
		Position = UDim2.new(0, 1, 0, 1),
		BackgroundTransparency = 1,
		Parent = inst,
	})
	Create("UIStroke", {
		Color = Theme.BorderLight,
		Thickness = 1,
		Transparency = 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inner,
	})
	return inner
end

local function Text(props)
	props.Font = FONT
	props.TextSize = props.TextSize or FONT_SIZE
	props.BackgroundTransparency = props.BackgroundTransparency or 1
	props.TextColor3 = props.TextColor3 or Theme.Text
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return Create("TextLabel", props)
end

-- rainbow strip used along the top edge of every window
local function RainbowStrip(parent)
	local strip = Create("Frame", {
		Name = "Rainbow",
		Size = UDim2.new(1, 0, 0, 2),
		Position = UDim2.new(0, 0, 0, 0),
		BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1),
		ZIndex = 5,
		Parent = parent,
	})
	Create("UIGradient", {
		Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0.00, Color3.fromRGB(224, 82, 82)),
			ColorSequenceKeypoint.new(0.16, Color3.fromRGB(224, 158, 82)),
			ColorSequenceKeypoint.new(0.33, Color3.fromRGB(217, 224, 82)),
			ColorSequenceKeypoint.new(0.50, Color3.fromRGB(94, 224, 82)),
			ColorSequenceKeypoint.new(0.66, Color3.fromRGB(82, 217, 224)),
			ColorSequenceKeypoint.new(0.83, Color3.fromRGB(94, 82, 224)),
			ColorSequenceKeypoint.new(1.00, Color3.fromRGB(196, 82, 224)),
		}),
		Parent = strip,
	})
	return strip
end

-- green vertical gradient used on checkbox-on and slider fill
local function AccentGradient(parent)
	return Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Theme.AccentTop, Theme.AccentBot),
		Parent = parent,
	})
end

-- gray vertical gradient used on unchecked checkboxes (76 -> 49)
local function OffGradient(parent)
	return Create("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Theme.CheckOffTop, Theme.CheckOffBot),
		Parent = parent,
	})
end

--// Executor-safe parenting
local function GetGuiParent()
	local ok, ui = pcall(function()
		return (gethui and gethui()) or CoreGui
	end)
	if ok and ui then return ui end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local ScreenGui = Create("ScreenGui", {
	Name = "SkeetUI_" .. HttpService:GenerateGUID(false):sub(1, 8),
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
})
pcall(function()
	if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end
end)
ScreenGui.Parent = GetGuiParent()
Library.ScreenGui = ScreenGui

--// Dragging
local function MakeDraggable(handle, frame)
	local dragging, dragStart, startPos = false, nil, nil
	Connect(handle.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
		end
	end)
	Connect(UserInput.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
		or input.UserInputType == Enum.UserInputType.Touch) then
			local d = input.Position - dragStart
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + d.X,
				startPos.Y.Scale, startPos.Y.Offset + d.Y
			)
		end
	end)
	Connect(UserInput.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

--// Flag registration
local function RegisterFlag(flag, item, default, callback)
	if flag then
		Library.Flags[flag] = default
		Library.Items[flag] = item
	end
	return function(value)
		if flag then Library.Flags[flag] = value end
		if callback then task.spawn(callback, value) end
	end
end

--// Shared flat button factory (skeet-style raised button)
local function FlatButton(parent, size, position, label)
	local btn = Create("TextButton", {
		Size = size,
		Position = position,
		BackgroundColor3 = Theme.Element,
		BorderSizePixel = 0,
		Font = FONT,
		Text = label,
		TextColor3 = Theme.Text,
		TextSize = FONT_SIZE,
		AutoButtonColor = false,
		Parent = parent,
	})
	DoubleBorder(btn)
	Connect(btn.MouseEnter, function()
		Tween(btn, TWEEN_FAST, { BackgroundColor3 = Theme.ElementHover })
	end)
	Connect(btn.MouseLeave, function()
		Tween(btn, TWEEN_FAST, { BackgroundColor3 = Theme.Element })
	end)
	return btn
end

--// Shared flat textbox factory
local function FlatTextbox(parent, size, position, placeholder)
	local holder = Create("Frame", {
		Size = size,
		Position = position,
		BackgroundColor3 = Theme.ElementDark,
		BorderSizePixel = 0,
		Parent = parent,
	})
	DoubleBorder(holder)
	local box = Create("TextBox", {
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundTransparency = 1,
		Font = FONT,
		PlaceholderText = placeholder or "",
		PlaceholderColor3 = Theme.TextDark,
		Text = "",
		TextColor3 = Theme.Text,
		TextSize = FONT_SIZE,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = holder,
	})
	return holder, box
end

--// Confirmation dialog --------------------------------------------------------

function Library:Confirm(config)
	config = config or {}
	local backdrop = Create("TextButton", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.5,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 90,
		Parent = ScreenGui,
	})
	local dialog = Create("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(280, 110),
		BackgroundColor3 = Theme.Content,
		BorderSizePixel = 0,
		ZIndex = 91,
		Parent = backdrop,
	})
	DoubleBorder(dialog)
	RainbowStrip(dialog)

	Text({
		Size = UDim2.new(1, -24, 0, 30),
		Position = UDim2.new(0, 12, 0, 12),
		Text = config.Content or "Do you wish to unload the interface?",
		TextColor3 = Theme.Text,
		TextWrapped = true,
		ZIndex = 92,
		Parent = dialog,
	})

	local function DialogClose(confirmed)
		backdrop:Destroy()
		if config.Callback then task.spawn(config.Callback, confirmed) end
	end

	local yes = FlatButton(dialog, UDim2.fromOffset(120, 26), UDim2.new(0, 14, 1, -38), config.YesText or "Yes")
	yes.ZIndex = 92
	local no = FlatButton(dialog, UDim2.fromOffset(120, 26), UDim2.new(1, -134, 1, -38), config.NoText or "No")
	no.ZIndex = 92

	Connect(yes.MouseButton1Click, function() DialogClose(true) end)
	Connect(no.MouseButton1Click, function() DialogClose(false) end)
end

--// Login window ---------------------------------------------------------------

function Library:CreateLogin(config)
	config = config or {}
	local validate = config.Validate       -- function(user, pass) -> boolean
	local users    = config.Accounts or {} -- { [username] = password }
	local onLogin  = config.Callback

	local Login = Create("Frame", {
		Name = "Login",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.fromOffset(296, 202),
		BackgroundColor3 = Theme.Content,
		BorderSizePixel = 0,
		Parent = ScreenGui,
	})
	DoubleBorder(Login)
	RainbowStrip(Login)
	MakeDraggable(Login, Login)

	local userHolder, userBox = FlatTextbox(Login, UDim2.fromOffset(160, 22), UDim2.new(0.5, -80, 0, 30), "Username")
	local passHolder, passBox = FlatTextbox(Login, UDim2.fromOffset(160, 22), UDim2.new(0.5, -80, 0, 64), "Password")
	passBox.Text = ""
	pcall(function() passBox.TextEditable = true end)

	-- mask password manually (Roblox TextBox has no native masking pre-2023 API)
	local realPass = ""
	Connect(passBox:GetPropertyChangedSignal("Text"), function()
		local txt = passBox.Text
		if txt:gsub("•", "") ~= "" then
			-- user typed new plain chars; rebuild real password
			local masked = txt:gsub("•", "")
			if #txt < #realPass then
				realPass = realPass:sub(1, #txt)
			else
				realPass = realPass .. masked
			end
			passBox.Text = string.rep("•", #realPass)
		elseif #txt < #realPass then
			realPass = realPass:sub(1, #txt)
		end
	end)

	local status = Text({
		Size = UDim2.new(1, -40, 0, 14),
		Position = UDim2.new(0, 20, 0, 92),
		Text = "",
		TextColor3 = Theme.Error,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
		Parent = Login,
	})

	local loginBtn = FlatButton(Login, UDim2.fromOffset(140, 24), UDim2.new(0.5, -70, 0, 118), "Login")
	local exitBtn  = FlatButton(Login, UDim2.fromOffset(140, 24), UDim2.new(0.5, -70, 0, 150), "Exit")

	local function TryLogin()
		local user = userBox.Text
		local pass = realPass ~= "" and realPass or passBox.Text
		local ok = false
		if validate then
			local s, res = pcall(validate, user, pass)
			ok = s and res == true
		else
			ok = users[user] ~= nil and users[user] == pass
		end
		if ok then
			Login:Destroy()
			if onLogin then task.spawn(onLogin, user) end
		else
			status.Text = "invalid username or password"
			userHolder.BackgroundColor3 = Theme.ElementDark
			passHolder.BackgroundColor3 = Theme.ElementDark
		end
	end

	Connect(loginBtn.MouseButton1Click, TryLogin)
	Connect(passBox.FocusLost, function(enter) if enter then TryLogin() end end)
	Connect(exitBtn.MouseButton1Click, function()
		Library:Confirm({
			Content = "Do you wish to unload the interface?",
			Callback = function(confirmed)
				if confirmed then Library:Unload() end
			end,
		})
	end)
end

--// Main window ----------------------------------------------------------------

function Library:CreateWindow(config)
	config = config or {}
	local windowSize = config.Size or UDim2.fromOffset(647, 516)
	Library.ToggleKey = config.ToggleKey or Library.ToggleKey

	local Window = { Tabs = {}, ActiveTab = nil, Hidden = false }

	local Main = Create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = windowSize,
		BackgroundColor3 = Theme.Content,
		BorderSizePixel = 0,
		Parent = ScreenGui,
	})
	DoubleBorder(Main)
	RainbowStrip(Main)
	MakeDraggable(Main, Main)

	--// Sidebar
	local Sidebar = Create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 97, 1, -2),
		Position = UDim2.new(0, 0, 0, 2),
		BackgroundColor3 = Theme.Sidebar,
		BorderSizePixel = 0,
		Parent = Main,
	})

	local TabHolder = Create("Frame", {
		Size = UDim2.new(1, 0, 1, -16),
		Position = UDim2.new(0, 0, 0, 8),
		BackgroundTransparency = 1,
		Parent = Sidebar,
	}, {
		Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 0),
		}),
	})

	--// Content
	local Content = Create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -97, 1, -2),
		Position = UDim2.new(0, 97, 0, 2),
		BackgroundColor3 = Theme.Content,
		BorderSizePixel = 0,
		Parent = Main,
	})

	--// Toggle key
	Connect(UserInput.InputBegan, function(input, processed)
		if processed then return end
		if input.KeyCode == Library.ToggleKey then
			Window.Hidden = not Window.Hidden
			Main.Visible = not Window.Hidden
		end
	end)

	--// Tab ---------------------------------------------------------------------
	function Window:AddTab(tabConfig)
		tabConfig = tabConfig or {}
		local icon = tabConfig.Icon -- rbxassetid or text glyph

		local Tab = {}

		local TabButton = Create("TextButton", {
			Size = UDim2.new(1, 0, 0, 78),
			BackgroundColor3 = Theme.SidebarOn,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Parent = TabHolder,
		})

		local iconInst
		if icon and tostring(icon):find("rbxassetid") then
			iconInst = Create("ImageLabel", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.fromOffset(34, 34),
				BackgroundTransparency = 1,
				Image = icon,
				ImageColor3 = Color3.fromRGB(90, 90, 90),
				Parent = TabButton,
			})
		else
			iconInst = Text({
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.new(0.5, 0, 0.5, 0),
				Size = UDim2.fromOffset(40, 40),
				Text = icon or "?",
				TextColor3 = Theme.TextDark,
				TextSize = 26,
				TextXAlignment = Enum.TextXAlignment.Center,
				Parent = TabButton,
			})
		end

		local Page = Create("ScrollingFrame", {
			Name = "Page",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Theme.BorderLight,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			Visible = false,
			Parent = Content,
		})

		-- two columns; groupbox titles hang 7px above the box so give 16px headroom
		local LeftCol = Create("Frame", {
			Size = UDim2.new(0.5, -28, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.new(0, 20, 0, 16),
			BackgroundTransparency = 1,
			Parent = Page,
		}, {
			Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 18) }),
			Create("UIPadding", { PaddingBottom = UDim.new(0, 20) }),
		})
		local RightCol = Create("Frame", {
			Size = UDim2.new(0.5, -28, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.new(0.5, 4, 0, 16),
			BackgroundTransparency = 1,
			Parent = Page,
		}, {
			Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 18) }),
			Create("UIPadding", { PaddingBottom = UDim.new(0, 20) }),
		})

		local function SelectTab()
			for _, other in ipairs(Window.Tabs) do
				other.Page.Visible = false
				Tween(other.Button, TWEEN_FAST, { BackgroundTransparency = 1 })
				if other.Icon:IsA("ImageLabel") then
					Tween(other.Icon, TWEEN_FAST, { ImageColor3 = Color3.fromRGB(90, 90, 90) })
				else
					Tween(other.Icon, TWEEN_FAST, { TextColor3 = Color3.fromRGB(90, 90, 90) })
				end
			end
			Page.Visible = true
			Window.ActiveTab = Tab
			Tween(TabButton, TWEEN_FAST, { BackgroundTransparency = 0 })
			if iconInst:IsA("ImageLabel") then
				Tween(iconInst, TWEEN_FAST, { ImageColor3 = Color3.new(1, 1, 1) })
			else
				Tween(iconInst, TWEEN_FAST, { TextColor3 = Color3.new(1, 1, 1) })
			end
		end

		Connect(TabButton.MouseButton1Click, SelectTab)
		Connect(TabButton.MouseEnter, function()
			if Window.ActiveTab ~= Tab then
				if iconInst:IsA("ImageLabel") then
					Tween(iconInst, TWEEN_FAST, { ImageColor3 = Theme.Text })
				else
					Tween(iconInst, TWEEN_FAST, { TextColor3 = Theme.Text })
				end
			end
		end)
		Connect(TabButton.MouseLeave, function()
			if Window.ActiveTab ~= Tab then
				if iconInst:IsA("ImageLabel") then
					Tween(iconInst, TWEEN_FAST, { ImageColor3 = Color3.fromRGB(90, 90, 90) })
				else
					Tween(iconInst, TWEEN_FAST, { TextColor3 = Color3.fromRGB(90, 90, 90) })
				end
			end
		end)

		Tab.Button = TabButton
		Tab.Icon = iconInst
		Tab.Page = Page
		Tab.Select = SelectTab
		table.insert(Window.Tabs, Tab)
		if #Window.Tabs == 1 then SelectTab() end

		--// Groupbox --------------------------------------------------------------
		function Tab:AddGroupbox(gbConfig)
			gbConfig = gbConfig or {}
			local title = gbConfig.Title or "Group"
			local side  = (gbConfig.Side or "Left"):lower()
			local parent = side == "right" and RightCol or LeftCol

			local Groupbox = {}

			local Box = Create("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Theme.Groupbox,
				BorderSizePixel = 0,
				Parent = parent,
			})
			DoubleBorder(Box)

			-- title patch sits ON the top border line, like the reference
			local titleLabel = Text({
				Size = UDim2.new(0, 0, 0, 14),
				AutomaticSize = Enum.AutomaticSize.X,
				Position = UDim2.new(0, 12, 0, -7),
				Text = " " .. title .. " ",
				TextColor3 = Color3.fromRGB(205, 205, 205),
				TextSize = 12,
				BackgroundTransparency = 0,
				BackgroundColor3 = Theme.Content,
				ZIndex = 3,
				Parent = Box,
			})
			titleLabel.BorderSizePixel = 0

			-- elements start 20px in from the box edge (checkbox at x+20 in reference)
			local Inner = Create("Frame", {
				Size = UDim2.new(1, -40, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				Position = UDim2.new(0, 20, 0, 18),
				BackgroundTransparency = 1,
				Parent = Box,
			}, {
				Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }),
				Create("UIPadding", { PaddingBottom = UDim.new(0, 14) }),
			})

			Groupbox.Frame = Inner
			Groupbox.Box = Box
			Library._AttachComponents(Groupbox)
			return Groupbox
		end

		return Tab
	end

	Window.Main = Main
	Window.Close = function()
		Library:Confirm({
			Content = "Do you wish to unload the interface?",
			Callback = function(confirmed)
				if confirmed then Library:Unload() end
			end,
		})
	end
	return Window
end

--// Unload
function Library:Unload()
	if Library.Unloaded then return end
	Library.Unloaded = true
	for _, c in ipairs(Library.Connections) do
		pcall(function() c:Disconnect() end)
	end
	if ScreenGui then ScreenGui:Destroy() end
end

--// Components --------------------------------------------------------------

function Library._AttachComponents(Groupbox)
	local Frame = Groupbox.Frame

	--// Label ---------------------------------------------------------------
	function Groupbox:AddLabel(text)
		local label = Text({
			Size = UDim2.new(1, 0, 0, 14),
			Text = text or "Label",
			TextColor3 = Theme.Text,
			Parent = Frame,
		})
		local item = {}
		function item:Set(t) label.Text = t end
		return item
	end

	--// Checkbox (skeet toggle) ----------------------------------------------
	function Groupbox:AddCheckbox(config)
		config = config or {}
		local state = config.Default or false
		local bindText = config.Keybind        -- display tag e.g. "M5"
		local bindKey  = config.KeybindKey     -- optional Enum.KeyCode that toggles it

		local row = Create("TextButton", {
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
			Parent = Frame,
		})

		-- 8x8 interior + 1px black outline = 10px like the reference
		local box = Create("Frame", {
			Position = UDim2.new(0, 1, 0.5, -4),
			Size = UDim2.fromOffset(8, 8),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			Parent = row,
		})
		Create("UIStroke", { Color = Theme.BorderDark, Thickness = 1, Parent = box })
		local onGrad = AccentGradient(box)
		local offGrad = OffGradient(box)
		onGrad.Enabled = state
		offGrad.Enabled = not state

		local label = Text({
			Size = UDim2.new(1, -70, 1, 0),
			Position = UDim2.new(0, 20, 0, 0),
			Text = config.Title or "Checkbox",
			TextColor3 = state and Theme.Accent or Theme.Text,
			Parent = row,
		})

		local bindLabel
		if bindText ~= nil or config.ShowBind then
			bindLabel = Text({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.fromOffset(50, 14),
				Text = "[" .. (bindText or "-") .. "]",
				TextColor3 = Theme.TextDark,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Right,
				Parent = row,
			})
		end

		local item = {}
		local fire = RegisterFlag(config.Flag, item, state, config.Callback)

		local hovering = false
		local function Render()
			onGrad.Enabled = state
			offGrad.Enabled = not state
			-- enabled items show a lime label, exactly like "Remove spread"
			if state then
				label.TextColor3 = Theme.Accent
			else
				label.TextColor3 = hovering and Color3.new(1, 1, 1) or Theme.Text
			end
		end

		Connect(row.MouseButton1Click, function()
			state = not state
			Render()
			fire(state)
		end)
		Connect(row.MouseEnter, function()
			hovering = true
			Render()
		end)
		Connect(row.MouseLeave, function()
			hovering = false
			Render()
		end)

		if bindKey then
			Connect(UserInput.InputBegan, function(input, processed)
				if processed then return end
				if input.KeyCode == bindKey then
					state = not state
					Render()
					fire(state)
				end
			end)
		end

		function item:Set(v)
			state = v and true or false
			Render()
			fire(state)
		end
		function item:Get() return state end
		function item:SetBindText(t)
			if bindLabel then bindLabel.Text = "[" .. t .. "]" end
		end

		if state then fire(state) end
		return item
	end
	Groupbox.AddToggle = Groupbox.AddCheckbox

	--// Slider ---------------------------------------------------------------
	function Groupbox:AddSlider(config)
		config = config or {}
		local min    = config.Min or 0
		local max    = config.Max or 100
		local step   = config.Step or 1
		local value  = math.clamp(config.Default or min, min, max)
		local suffix = config.Suffix or ""

		-- extra 10px under the bar for the inline value text ("90%")
		local holder = Create("Frame", {
			Size = UDim2.new(1, 0, 0, config.Title and 38 or 22),
			BackgroundTransparency = 1,
			Parent = Frame,
		})

		-- sub-elements are indented 20px to align with checkbox labels
		local indent = (config.Indent ~= false) and 20 or 0

		if config.Title then
			Text({
				Size = UDim2.new(1, -indent, 0, 14),
				Position = UDim2.new(0, indent, 0, 0),
				Text = config.Title,
				Parent = holder,
			})
		end

		local bar = Create("Frame", {
			Size = UDim2.new(1, -indent - 2, 0, 7),
			Position = UDim2.new(0, indent + 1, 1, -19),
			BackgroundColor3 = Theme.Track,
			BorderSizePixel = 0,
			Parent = holder,
		})
		Create("UIStroke", { Color = Theme.BorderDark, Thickness = 1, Parent = bar })

		local fill = Create("Frame", {
			Size = UDim2.new((value - min) / math.max(max - min, 1e-9), 0, 1, 0),
			BackgroundColor3 = Theme.Accent,
			BorderSizePixel = 0,
			Parent = bar,
		})
		AccentGradient(fill)

		-- value text sits just under the bar at the end of the fill, like "90%" in the reference
		local valueLabel = Text({
			AnchorPoint = Vector2.new(0.5, 0),
			Size = UDim2.fromOffset(70, 12),
			Position = UDim2.new((value - min) / math.max(max - min, 1e-9), 0, 1, -2),
			Text = tostring(value) .. suffix,
			TextColor3 = Theme.Text,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 3,
			Parent = bar,
		})

		local item = {}
		local fire = RegisterFlag(config.Flag, item, value, config.Callback)

		local function SetValue(v, skip)
			v = math.clamp(v, min, max)
			v = math.floor((v - min) / step + 0.5) * step + min
			v = math.clamp(v, min, max)
			if step % 1 == 0 then
				v = math.floor(v + 0.5)
			else
				v = math.floor(v * 100 + 0.5) / 100
			end
			value = v
			local alpha = (max == min) and 0 or (value - min) / (max - min)
			fill.Size = UDim2.new(alpha, 0, 1, 0)
			local xOff = 0
			if alpha < 0.08 then xOff = 14 elseif alpha > 0.92 then xOff = -20 end
			valueLabel.Position = UDim2.new(alpha, xOff, 1, -2)
			valueLabel.Text = tostring(value) .. suffix
			if not skip then fire(value) end
		end

		local dragging = false
		local function FromInput(input)
			local alpha = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
			SetValue(min + alpha * (max - min))
		end

		Connect(bar.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				FromInput(input)
			end
		end)
		Connect(UserInput.InputChanged, function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
				FromInput(input)
			end
		end)
		Connect(UserInput.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
				dragging = false
			end
		end)

		function item:Set(v) SetValue(v) end
		function item:Get() return value end
		SetValue(value, true)
		return item
	end

	--// Dropdown -------------------------------------------------------------
	function Groupbox:AddDropdown(config)
		config = config or {}
		local options  = config.Options or {}
		local multi    = config.Multi or false
		local selected = multi and {} or config.Default
		if multi and config.Default then
			for _, v in ipairs(config.Default) do selected[v] = true end
		end

		-- sub-elements are indented 20px to align with checkbox labels
		local indent = (config.Indent ~= false) and 20 or 0
		local baseHeight = config.Title and 36 or 18

		local holder = Create("Frame", {
			Size = UDim2.new(1, 0, 0, baseHeight),
			BackgroundTransparency = 1,
			Parent = Frame,
		})

		if config.Title then
			Text({
				Size = UDim2.new(1, -indent, 0, 14),
				Position = UDim2.new(0, indent, 0, 0),
				Text = config.Title,
				Parent = holder,
			})
		end

		-- 17px tall, (35,35,35) fill, 1px black border like the reference
		local display = Create("TextButton", {
			Size = UDim2.new(1, -indent - 2, 0, 17),
			Position = UDim2.new(0, indent + 1, 1, -18),
			BackgroundColor3 = Theme.Element,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Parent = holder,
		})
		Create("UIStroke", { Color = Theme.BorderDark, Thickness = 1, Parent = display })

		local function GetDisplayText()
			if multi then
				local parts = {}
				for _, o in ipairs(options) do
					if selected[o] then table.insert(parts, o) end
				end
				return #parts > 0 and table.concat(parts, ", ") or "-"
			end
			return selected or "-"
		end

		local displayText = Text({
			Size = UDim2.new(1, -28, 1, 0),
			Position = UDim2.new(0, 8, 0, 0),
			Text = GetDisplayText(),
			TextColor3 = Color3.fromRGB(154, 154, 154),
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Parent = display,
		})

		local arrow = Text({
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(10, 10),
			Text = "▼",
			TextColor3 = Theme.TextDark,
			TextSize = 8,
			TextXAlignment = Enum.TextXAlignment.Center,
			Parent = display,
		})

		local open = false
		local listFrame = Create("ScrollingFrame", {
			Size = UDim2.new(1, -indent - 2, 0, 0),
			Position = UDim2.new(0, indent + 1, 1, 1),
			BackgroundColor3 = Theme.ElementDark,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Theme.BorderLight,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			Visible = false,
			ZIndex = 10,
			ClipsDescendants = true,
			Parent = holder,
		}, {
			Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		Create("UIStroke", { Color = Theme.BorderDark, Thickness = 1, Parent = listFrame })

		local item = {}
		local fire = RegisterFlag(config.Flag, item, selected, config.Callback)
		local optionButtons = {}

		local function RenderOptions()
			for _, b in ipairs(optionButtons) do b:Destroy() end
			table.clear(optionButtons)
			for _, opt in ipairs(options) do
				local isSel = multi and selected[opt] or selected == opt
				local optBtn = Create("TextButton", {
					Size = UDim2.new(1, 0, 0, 18),
					BackgroundColor3 = isSel and Theme.ElementHover or Theme.Element,
					BorderSizePixel = 0,
					Font = FONT,
					Text = "",
					AutoButtonColor = false,
					ZIndex = 11,
					Parent = listFrame,
				})
				Text({
					Size = UDim2.new(1, -16, 1, 0),
					Position = UDim2.new(0, 8, 0, 0),
					Text = opt,
					TextColor3 = isSel and Theme.Accent or Color3.fromRGB(154, 154, 154),
					TextSize = 11,
					ZIndex = 12,
					Parent = optBtn,
				})
				Connect(optBtn.MouseEnter, function()
					Tween(optBtn, TWEEN_FAST, { BackgroundColor3 = Theme.ElementHover })
				end)
				Connect(optBtn.MouseLeave, function()
					Tween(optBtn, TWEEN_FAST, { BackgroundColor3 = (multi and selected[opt] or selected == opt) and Theme.ElementHover or Theme.Element })
				end)
				Connect(optBtn.MouseButton1Click, function()
					if multi then
						selected[opt] = not selected[opt] or nil
					else
						selected = opt
					end
					displayText.Text = GetDisplayText()
					fire(selected)
					RenderOptions()
					if not multi then
						open = false
						listFrame.Visible = false
						holder.Size = UDim2.new(1, 0, 0, baseHeight)
						arrow.Text = "▼"
					end
				end)
				table.insert(optionButtons, optBtn)
			end
		end

		local LIST_MAX = 132
		Connect(display.MouseButton1Click, function()
			open = not open
			arrow.Text = open and "▲" or "▼"
			if open then
				RenderOptions()
				local h = math.min(#options * 18, LIST_MAX)
				listFrame.Size = UDim2.new(1, -indent - 2, 0, h)
				listFrame.Visible = true
				holder.Size = UDim2.new(1, 0, 0, baseHeight + h + 2)
			else
				listFrame.Visible = false
				holder.Size = UDim2.new(1, 0, 0, baseHeight)
			end
		end)

		function item:Set(value)
			if multi then
				selected = {}
				for _, v in ipairs(value) do selected[v] = true end
			else
				selected = value
			end
			displayText.Text = GetDisplayText()
			fire(selected)
			if open then RenderOptions() end
		end
		function item:Get() return selected end
		function item:SetOptions(newOptions)
			options = newOptions
			if multi then selected = {} else selected = nil end
			displayText.Text = GetDisplayText()
			if open then RenderOptions() end
		end
		return item
	end

	--// Button ---------------------------------------------------------------
	function Groupbox:AddButton(config)
		config = config or {}
		local btn = FlatButton(Frame, UDim2.new(1, -4, 0, 24), nil, config.Title or "Button")
		Connect(btn.MouseButton1Click, function()
			if config.Callback then task.spawn(config.Callback) end
		end)
		local item = {}
		function item:SetTitle(t) btn.Text = t end
		return item
	end

	--// Textbox --------------------------------------------------------------
	function Groupbox:AddTextbox(config)
		config = config or {}
		local holder = Create("Frame", {
			Size = UDim2.new(1, 0, 0, config.Title and 38 or 20),
			BackgroundTransparency = 1,
			Parent = Frame,
		})
		if config.Title then
			Text({ Size = UDim2.new(1, 0, 0, 14), Text = config.Title, Parent = holder })
		end
		local _boxHolder, box = FlatTextbox(holder, UDim2.new(1, -4, 0, 20), UDim2.new(0, 1, 1, -21), config.Placeholder)
		box.Text = config.Default or ""

		local item = {}
		local fire = RegisterFlag(config.Flag, item, box.Text, config.Callback)
		Connect(box.FocusLost, function()
			fire(box.Text)
		end)
		function item:Set(t)
			box.Text = t
			fire(t)
		end
		function item:Get() return box.Text end
		return item
	end

	--// Listbox (presets / lua list style) ------------------------------------
	function Groupbox:AddListbox(config)
		config = config or {}
		local options  = config.Options or {}
		local selected = config.Default
		local height   = config.Height or 140

		local listFrame = Create("ScrollingFrame", {
			Size = UDim2.new(1, -4, 0, height),
			BackgroundColor3 = Theme.ElementDark,
			BorderSizePixel = 0,
			ScrollBarThickness = 3,
			ScrollBarImageColor3 = Theme.BorderLight,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			Parent = Frame,
		}, {
			Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }),
		})
		Create("UIStroke", { Color = Theme.BorderDark, Thickness = 1, Parent = listFrame })

		local item = {}
		local fire = RegisterFlag(config.Flag, item, selected, config.Callback)
		local rows = {}

		local function Render()
			for _, r in ipairs(rows) do r:Destroy() end
			table.clear(rows)
			for _, opt in ipairs(options) do
				local isSel = selected == opt
				local rowBtn = Create("TextButton", {
					Size = UDim2.new(1, 0, 0, 22),
					BackgroundColor3 = isSel and Theme.Element or Theme.ElementDark,
					BorderSizePixel = 0,
					Text = "",
					AutoButtonColor = false,
					Parent = listFrame,
				})
				Text({
					Size = UDim2.new(1, -16, 1, 0),
					Position = UDim2.new(0, 8, 0, 0),
					Text = opt,
					TextColor3 = isSel and Theme.Accent or Theme.Text,
					TextSize = 11,
					Parent = rowBtn,
				})
				Connect(rowBtn.MouseEnter, function()
					Tween(rowBtn, TWEEN_FAST, { BackgroundColor3 = Theme.ElementHover })
				end)
				Connect(rowBtn.MouseLeave, function()
					Tween(rowBtn, TWEEN_FAST, { BackgroundColor3 = selected == opt and Theme.Element or Theme.ElementDark })
				end)
				Connect(rowBtn.MouseButton1Click, function()
					selected = opt
					fire(selected)
					Render()
				end)
				table.insert(rows, rowBtn)
			end
		end
		Render()

		function item:Set(v)
			selected = v
			fire(v)
			Render()
		end
		function item:Get() return selected end
		function item:SetOptions(newOptions)
			options = newOptions
			selected = nil
			Render()
		end
		return item
	end

	--// Keybind --------------------------------------------------------------
	function Groupbox:AddKeybind(config)
		config = config or {}
		local currentKey = config.Default
		local listening = false

		local row = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Parent = Frame,
		})
		Text({
			Size = UDim2.new(1, -70, 1, 0),
			Text = config.Title or "Keybind",
			Parent = row,
		})
		local keyBtn = Create("TextButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 0),
			Size = UDim2.fromOffset(60, 14),
			BackgroundTransparency = 1,
			Font = FONT,
			Text = "[" .. (currentKey and currentKey.Name or "-") .. "]",
			TextColor3 = Theme.TextDark,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			AutoButtonColor = false,
			Parent = row,
		})

		local item = {}
		local fire = RegisterFlag(config.Flag, item, currentKey, nil)

		Connect(keyBtn.MouseButton1Click, function()
			listening = true
			keyBtn.Text = "[...]"
			keyBtn.TextColor3 = Theme.Accent
		end)

		Connect(UserInput.InputBegan, function(input, processed)
			if listening then
				if input.UserInputType == Enum.UserInputType.Keyboard then
					if input.KeyCode == Enum.KeyCode.Escape then
						currentKey = nil
					else
						currentKey = input.KeyCode
					end
					keyBtn.Text = "[" .. (currentKey and currentKey.Name or "-") .. "]"
					keyBtn.TextColor3 = Theme.TextDark
					listening = false
					fire(currentKey)
					if config.ChangedCallback then task.spawn(config.ChangedCallback, currentKey) end
				end
				return
			end
			if processed then return end
			if currentKey and input.KeyCode == currentKey and config.Callback then
				task.spawn(config.Callback, currentKey)
			end
		end)

		function item:Set(k)
			currentKey = k
			keyBtn.Text = "[" .. (currentKey and currentKey.Name or "-") .. "]"
			fire(currentKey)
		end
		function item:Get() return currentKey end
		return item
	end

	--// Color swatch + picker --------------------------------------------------
	function Groupbox:AddColorPicker(config)
		config = config or {}
		local color = config.Default or Theme.Accent
		local h, s, v = color:ToHSV()

		local row = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Parent = Frame,
		})
		Text({
			Size = UDim2.new(1, -40, 1, 0),
			Text = config.Title or "Color",
			Parent = row,
		})
		local swatch = Create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, 0, 0.5, 0),
			Size = UDim2.fromOffset(22, 10),
			BackgroundColor3 = color,
			BorderSizePixel = 0,
			Text = "",
			AutoButtonColor = false,
			Parent = row,
		})
		Create("UIStroke", { Color = Theme.BorderDark, Thickness = 1, Parent = swatch })

		local open = false
		local picker = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 110),
			BackgroundColor3 = Theme.ElementDark,
			BorderSizePixel = 0,
			Visible = false,
			Parent = Frame,
		})
		DoubleBorder(picker)

		local svSquare = Create("ImageButton", {
			Position = UDim2.new(0, 6, 0, 6),
			Size = UDim2.new(1, -36, 1, -12),
			BackgroundColor3 = Color3.fromHSV(h, 1, 1),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Image = "",
			Parent = picker,
		})
		Create("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = svSquare,
		})
		local blackOverlay = Create("Frame", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Parent = svSquare,
		})
		Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Parent = blackOverlay,
		})

		local svCursor = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(s, 0, 1 - v, 0),
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = svSquare,
		})
		Create("UIStroke", { Color = Color3.new(0, 0, 0), Thickness = 1, Parent = svCursor })

		local hueBar = Create("ImageButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 0, 6),
			Size = UDim2.new(0, 14, 1, -12),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			AutoButtonColor = false,
			Image = "",
			Parent = picker,
		})
		local hueKeypoints = {}
		for i = 0, 6 do
			table.insert(hueKeypoints, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)))
		end
		Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(hueKeypoints), Parent = hueBar })

		local hueCursor = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, h, 0),
			Size = UDim2.new(1, 2, 0, 3),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = hueBar,
		})

		local item = {}
		local fire = RegisterFlag(config.Flag, item, color, config.Callback)

		local function UpdateColor(skip)
			color = Color3.fromHSV(h, s, v)
			swatch.BackgroundColor3 = color
			svSquare.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
			hueCursor.Position = UDim2.new(0.5, 0, h, 0)
			if not skip then fire(color) end
		end

		local svDrag, hueDrag = false, false
		Connect(svSquare.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then svDrag = true end
		end)
		Connect(hueBar.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then hueDrag = true end
		end)
		Connect(UserInput.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				svDrag, hueDrag = false, false
			end
		end)
		Connect(UserInput.InputChanged, function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
			if svDrag then
				s = math.clamp((input.Position.X - svSquare.AbsolutePosition.X) / svSquare.AbsoluteSize.X, 0, 1)
				v = 1 - math.clamp((input.Position.Y - svSquare.AbsolutePosition.Y) / svSquare.AbsoluteSize.Y, 0, 1)
				UpdateColor()
			elseif hueDrag then
				h = math.clamp((input.Position.Y - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 1)
				UpdateColor()
			end
		end)

		Connect(swatch.MouseButton1Click, function()
			open = not open
			picker.Visible = open
		end)

		function item:Set(c)
			h, s, v = c:ToHSV()
			UpdateColor()
		end
		function item:Get() return color end
		return item
	end
end

--// Notifications (kept minimal, skeet style: top-left log lines) --------------

local NotifyHolder = Create("Frame", {
	Name = "Notifications",
	Position = UDim2.new(0, 10, 0, 10),
	Size = UDim2.new(0, 320, 1, -20),
	BackgroundTransparency = 1,
	Parent = ScreenGui,
}, {
	Create("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 4),
	}),
})

function Library:Notify(config)
	config = config or {}
	local duration = config.Duration or 4

	local line = Create("Frame", {
		Size = UDim2.new(0, 0, 0, 20),
		AutomaticSize = Enum.AutomaticSize.X,
		BackgroundColor3 = Theme.ElementDark,
		BorderSizePixel = 0,
		Parent = NotifyHolder,
	})
	DoubleBorder(line)
	local accent = Create("Frame", {
		Size = UDim2.new(0, 2, 1, 0),
		BackgroundColor3 = config.Color or Theme.Accent,
		BorderSizePixel = 0,
		Parent = line,
	})
	AccentGradient(accent)
	Text({
		Size = UDim2.new(0, 0, 1, 0),
		AutomaticSize = Enum.AutomaticSize.X,
		Position = UDim2.new(0, 8, 0, 0),
		Text = (config.Title and (config.Title .. ": ") or "") .. (config.Content or ""),
		TextColor3 = Theme.Text,
		TextSize = 11,
		Parent = line,
	})
	Create("UIPadding", { PaddingRight = UDim.new(0, 10), Parent = line })

	task.delay(duration, function()
		if line.Parent then line:Destroy() end
	end)
end

return Library
