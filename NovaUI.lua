--[[
	NovaUI — Modern dark-themed UI library for Roblox executors
	Author: built for zenn
	Version: 1.0.0

	Usage:
		local Nova = loadstring(game:HttpGet("<raw url>/NovaUI.lua"))()
		local Window = Nova:CreateWindow({ Title = "My Hub" })
		-- see EXAMPLE.lua / README.md for full API
]]

--// Services
local TweenService  = game:GetService("TweenService")
local UserInput     = game:GetService("UserInputService")
local Players       = game:GetService("Players")
local CoreGui       = game:GetService("CoreGui")
local HttpService   = game:GetService("HttpService")

local LocalPlayer   = Players.LocalPlayer

--// Library root
local Library = {
	Flags        = {},        -- flag -> current value
	Items        = {},        -- flag -> item object (for Set/Get)
	Connections  = {},
	Windows      = {},
	Unloaded     = false,
	ToggleKey    = Enum.KeyCode.RightShift,
}
Library.__index = Library

--// Theme
local Theme = {
	Background   = Color3.fromRGB(15, 15, 19),
	Secondary    = Color3.fromRGB(22, 22, 28),
	Tertiary     = Color3.fromRGB(29, 29, 37),
	Element      = Color3.fromRGB(35, 35, 45),
	ElementHover = Color3.fromRGB(42, 42, 54),
	Stroke       = Color3.fromRGB(38, 38, 47),
	StrokeLight  = Color3.fromRGB(52, 52, 64),
	Accent       = Color3.fromRGB(124, 92, 255),
	AccentDim    = Color3.fromRGB(94, 70, 196),
	Text         = Color3.fromRGB(230, 230, 235),
	SubText      = Color3.fromRGB(138, 138, 150),
	Success      = Color3.fromRGB(72, 199, 142),
	Warning      = Color3.fromRGB(255, 189, 89),
	Error        = Color3.fromRGB(255, 95, 95),
}
Library.Theme = Theme

--// Tween presets
local TWEEN_FAST   = TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local TWEEN_MED    = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TWEEN_SLOW   = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

--// Utilities ----------------------------------------------------------------

local function Tween(object, info, props)
	local t = TweenService:Create(object, info, props)
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

local function Round(inst, radius)
	return Create("UICorner", { CornerRadius = UDim.new(0, radius or 6), Parent = inst })
end

local function Stroke(inst, color, thickness)
	return Create("UIStroke", {
		Color = color or Theme.Stroke,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
end

local function Padding(inst, t, b, l, r)
	return Create("UIPadding", {
		PaddingTop = UDim.new(0, t or 0), PaddingBottom = UDim.new(0, b or 0),
		PaddingLeft = UDim.new(0, l or 0), PaddingRight = UDim.new(0, r or 0),
		Parent = inst,
	})
end

--// Safe GUI parenting for executors
local function GetGuiParent()
	local ok, ui = pcall(function()
		return (gethui and gethui()) or CoreGui
	end)
	if ok and ui then return ui end
	return LocalPlayer:WaitForChild("PlayerGui")
end

local function ProtectGui(gui)
	pcall(function()
		if syn and syn.protect_gui then
			syn.protect_gui(gui)
		elseif protect_gui then
			protect_gui(gui)
		end
	end)
end

--// ScreenGui root
local ScreenGui = Create("ScreenGui", {
	Name = "NovaUI_" .. HttpService:GenerateGUID(false):sub(1, 8),
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	IgnoreGuiInset = true,
})
ProtectGui(ScreenGui)
ScreenGui.Parent = GetGuiParent()
Library.ScreenGui = ScreenGui

--// Dragging helper
local function MakeDraggable(dragHandle, frame)
	local dragging, dragStart, startPos = false, nil, nil
	Connect(dragHandle.InputBegan, function(input)
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
			local delta = input.Position - dragStart
			Tween(frame, TWEEN_FAST, {
				Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y
				)
			})
		end
	end)
	Connect(UserInput.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
		or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

--// Notifications ------------------------------------------------------------

local NotifyHolder = Create("Frame", {
	Name = "Notifications",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -16, 1, -16),
	Size = UDim2.new(0, 280, 1, -32),
	BackgroundTransparency = 1,
	Parent = ScreenGui,
}, {
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding = UDim.new(0, 8),
	}),
})

function Library:Notify(config)
	config = config or {}
	local title    = config.Title or "Notification"
	local content  = config.Content or ""
	local duration = config.Duration or 4
	local accent   = config.Color or Theme.Accent

	local frame = Create("Frame", {
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = Theme.Secondary,
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = NotifyHolder,
	})
	Round(frame, 8)
	local stroke = Stroke(frame, Theme.Stroke)
	stroke.Transparency = 1

	local bar = Create("Frame", {
		Size = UDim2.new(0, 3, 1, -16),
		Position = UDim2.new(0, 8, 0, 8),
		BackgroundColor3 = accent,
		BackgroundTransparency = 1,
		Parent = frame,
	})
	Round(bar, 2)

	local titleLabel = Create("TextLabel", {
		Size = UDim2.new(1, -32, 0, 18),
		Position = UDim2.new(0, 20, 0, 10),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = title,
		TextColor3 = Theme.Text,
		TextTransparency = 1,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})

	local contentLabel = Create("TextLabel", {
		Size = UDim2.new(1, -32, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.new(0, 20, 0, 30),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = content,
		TextColor3 = Theme.SubText,
		TextTransparency = 1,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})
	Padding(frame, 0, 12, 0, 0)

	-- animate in
	Tween(frame, TWEEN_MED, { BackgroundTransparency = 0.05 })
	Tween(stroke, TWEEN_MED, { Transparency = 0 })
	Tween(bar, TWEEN_MED, { BackgroundTransparency = 0 })
	Tween(titleLabel, TWEEN_MED, { TextTransparency = 0 })
	Tween(contentLabel, TWEEN_MED, { TextTransparency = 0.15 })

	task.delay(duration, function()
		if not frame.Parent then return end
		Tween(frame, TWEEN_MED, { BackgroundTransparency = 1 })
		Tween(stroke, TWEEN_MED, { Transparency = 1 })
		Tween(bar, TWEEN_MED, { BackgroundTransparency = 1 })
		Tween(titleLabel, TWEEN_MED, { TextTransparency = 1 })
		local t = Tween(contentLabel, TWEEN_MED, { TextTransparency = 1 })
		t.Completed:Wait()
		frame:Destroy()
	end)
end

--// Window -------------------------------------------------------------------

function Library:CreateWindow(config)
	config = config or {}
	local windowTitle = config.Title or "NovaUI"
	local subTitle    = config.SubTitle or "by zenn"
	local windowSize  = config.Size or UDim2.fromOffset(560, 400)
	Library.ToggleKey = config.ToggleKey or Library.ToggleKey

	local Window = {
		Tabs = {},
		ActiveTab = nil,
		Minimized = false,
		Hidden = false,
	}

	--// Main frame
	local Main = Create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = windowSize,
		BackgroundColor3 = Theme.Background,
		Parent = ScreenGui,
	})
	Round(Main, 10)
	Stroke(Main, Theme.Stroke)

	-- subtle drop shadow
	Create("ImageLabel", {
		Name = "Shadow",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 4),
		Size = UDim2.new(1, 40, 1, 40),
		BackgroundTransparency = 1,
		Image = "rbxassetid://6015897843",
		ImageColor3 = Color3.new(0, 0, 0),
		ImageTransparency = 0.45,
		ScaleType = Enum.ScaleType.Slice,
		SliceCenter = Rect.new(49, 49, 450, 450),
		ZIndex = -1,
		Parent = Main,
	})

	--// Titlebar
	local TitleBar = Create("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 42),
		BackgroundTransparency = 1,
		Parent = Main,
	})

	Create("TextLabel", {
		Size = UDim2.new(0.5, 0, 0, 16),
		Position = UDim2.new(0, 16, 0, 8),
		BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold,
		Text = windowTitle,
		TextColor3 = Theme.Text,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = TitleBar,
	})

	Create("TextLabel", {
		Size = UDim2.new(0.5, 0, 0, 12),
		Position = UDim2.new(0, 16, 0, 24),
		BackgroundTransparency = 1,
		Font = Enum.Font.Gotham,
		Text = subTitle,
		TextColor3 = Theme.SubText,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = TitleBar,
	})

	local function TitleButton(text, offset)
		local btn = Create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, offset, 0.5, 0),
			Size = UDim2.fromOffset(26, 26),
			BackgroundColor3 = Theme.Tertiary,
			Font = Enum.Font.GothamBold,
			Text = text,
			TextColor3 = Theme.SubText,
			TextSize = 12,
			AutoButtonColor = false,
			Parent = TitleBar,
		})
		Round(btn, 6)
		Connect(btn.MouseEnter, function()
			Tween(btn, TWEEN_FAST, { BackgroundColor3 = Theme.ElementHover })
			Tween(btn, TWEEN_FAST, { TextColor3 = Theme.Text })
		end)
		Connect(btn.MouseLeave, function()
			Tween(btn, TWEEN_FAST, { BackgroundColor3 = Theme.Tertiary })
			Tween(btn, TWEEN_FAST, { TextColor3 = Theme.SubText })
		end)
		return btn
	end

	local CloseBtn = TitleButton("X", -12)
	local MinBtn   = TitleButton("-", -44)

	Connect(CloseBtn.MouseButton1Click, function()
		Library:Unload()
	end)

	local ContentHolder -- forward declared
	Connect(MinBtn.MouseButton1Click, function()
		Window.Minimized = not Window.Minimized
		if Window.Minimized then
			Tween(Main, TWEEN_MED, { Size = UDim2.new(windowSize.X.Scale, windowSize.X.Offset, 0, 42) })
			task.delay(0.1, function() if ContentHolder then ContentHolder.Visible = false end end)
		else
			if ContentHolder then ContentHolder.Visible = true end
			Tween(Main, TWEEN_MED, { Size = windowSize })
		end
	end)

	MakeDraggable(TitleBar, Main)

	-- divider under titlebar
	Create("Frame", {
		Size = UDim2.new(1, -24, 0, 1),
		Position = UDim2.new(0, 12, 0, 42),
		BackgroundColor3 = Theme.Stroke,
		BorderSizePixel = 0,
		Parent = Main,
	})

	--// Content area: tab list (left) + pages (right)
	ContentHolder = Create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, 0, 1, -43),
		Position = UDim2.new(0, 0, 0, 43),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Parent = Main,
	})

	local TabList = Create("ScrollingFrame", {
		Name = "TabList",
		Size = UDim2.new(0, 140, 1, -16),
		Position = UDim2.new(0, 12, 0, 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 0,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Parent = ContentHolder,
	}, {
		Create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 4),
		}),
	})

	local PageHolder = Create("Frame", {
		Name = "Pages",
		Size = UDim2.new(1, -172, 1, -16),
		Position = UDim2.new(0, 160, 0, 8),
		BackgroundTransparency = 1,
		Parent = ContentHolder,
	})

	--// Toggle visibility keybind
	Connect(UserInput.InputBegan, function(input, processed)
		if processed then return end
		if input.KeyCode == Library.ToggleKey then
			Window.Hidden = not Window.Hidden
			Main.Visible = not Window.Hidden
		end
	end)

	--// Tab -------------------------------------------------------------------
	function Window:AddTab(tabConfig)
		tabConfig = tabConfig or {}
		local tabName = tabConfig.Title or "Tab"
		local tabIcon = tabConfig.Icon -- optional rbxassetid

		local Tab = { Sections = {} }

		local TabButton = Create("TextButton", {
			Size = UDim2.new(1, 0, 0, 32),
			BackgroundColor3 = Theme.Tertiary,
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = "",
			AutoButtonColor = false,
			Parent = TabList,
		})
		Round(TabButton, 6)

		local iconOffset = 12
		if tabIcon then
			Create("ImageLabel", {
				Size = UDim2.fromOffset(16, 16),
				Position = UDim2.new(0, 10, 0.5, -8),
				BackgroundTransparency = 1,
				Image = tabIcon,
				ImageColor3 = Theme.SubText,
				Name = "Icon",
				Parent = TabButton,
			})
			iconOffset = 32
		end

		local TabLabel = Create("TextLabel", {
			Size = UDim2.new(1, -iconOffset - 4, 1, 0),
			Position = UDim2.new(0, iconOffset, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = tabName,
			TextColor3 = Theme.SubText,
			TextSize = 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = TabButton,
		})

		local AccentPill = Create("Frame", {
			Size = UDim2.fromOffset(3, 16),
			Position = UDim2.new(0, 0, 0.5, -8),
			BackgroundColor3 = Theme.Accent,
			BackgroundTransparency = 1,
			Parent = TabButton,
		})
		Round(AccentPill, 2)

		local Page = Create("ScrollingFrame", {
			Name = tabName,
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ScrollBarThickness = 2,
			ScrollBarImageColor3 = Theme.StrokeLight,
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			CanvasSize = UDim2.new(0, 0, 0, 0),
			Visible = false,
			Parent = PageHolder,
		}, {
			Create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 8),
			}),
			Create("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }),
		})

		local function SelectTab()
			for _, other in ipairs(Window.Tabs) do
				other.Page.Visible = false
				Tween(other.Button, TWEEN_FAST, { BackgroundTransparency = 1 })
				Tween(other.Label, TWEEN_FAST, { TextColor3 = Theme.SubText })
				Tween(other.Pill, TWEEN_FAST, { BackgroundTransparency = 1 })
				local ic = other.Button:FindFirstChild("Icon")
				if ic then Tween(ic, TWEEN_FAST, { ImageColor3 = Theme.SubText }) end
			end
			Page.Visible = true
			Window.ActiveTab = Tab
			Tween(TabButton, TWEEN_FAST, { BackgroundTransparency = 0 })
			Tween(TabLabel, TWEEN_FAST, { TextColor3 = Theme.Text })
			Tween(AccentPill, TWEEN_FAST, { BackgroundTransparency = 0 })
			local ic = TabButton:FindFirstChild("Icon")
			if ic then Tween(ic, TWEEN_FAST, { ImageColor3 = Theme.Accent }) end
		end

		Connect(TabButton.MouseButton1Click, SelectTab)
		Connect(TabButton.MouseEnter, function()
			if Window.ActiveTab ~= Tab then
				Tween(TabButton, TWEEN_FAST, { BackgroundTransparency = 0.5 })
			end
		end)
		Connect(TabButton.MouseLeave, function()
			if Window.ActiveTab ~= Tab then
				Tween(TabButton, TWEEN_FAST, { BackgroundTransparency = 1 })
			end
		end)

		Tab.Button = TabButton
		Tab.Label = TabLabel
		Tab.Pill = AccentPill
		Tab.Page = Page
		Tab.Select = SelectTab
		table.insert(Window.Tabs, Tab)

		if #Window.Tabs == 1 then SelectTab() end

		--// Section ----------------------------------------------------------
		function Tab:AddSection(sectionConfig)
			sectionConfig = sectionConfig or {}
			local sectionTitle = sectionConfig.Title or "Section"

			local Section = {}

			local SectionFrame = Create("Frame", {
				Size = UDim2.new(1, 0, 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundColor3 = Theme.Secondary,
				Parent = Page,
			})
			Round(SectionFrame, 8)
			Stroke(SectionFrame, Theme.Stroke)
			Padding(SectionFrame, 12, 12, 12, 12)

			Create("TextLabel", {
				Size = UDim2.new(1, 0, 0, 16),
				BackgroundTransparency = 1,
				Font = Enum.Font.GothamBold,
				Text = sectionTitle,
				TextColor3 = Theme.Text,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				LayoutOrder = -1,
				Parent = SectionFrame,
			})

			Create("UIListLayout", {
				SortOrder = Enum.SortOrder.LayoutOrder,
				Padding = UDim.new(0, 6),
				Parent = SectionFrame,
			})

			Section.Frame = SectionFrame
			Section.Page = Page

			-- component implementations are attached below via Library._AttachComponents
			Library._AttachComponents(Section)
			table.insert(Tab.Sections, Section)
			return Section
		end

		return Tab
	end

	--// Intro animation
	Main.Size = UDim2.fromOffset(windowSize.X.Offset, 0)
	Main.BackgroundTransparency = 1
	Tween(Main, TWEEN_SLOW, { Size = windowSize, BackgroundTransparency = 0 })

	table.insert(Library.Windows, Window)
	Window.Main = Main
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

--// Shared element factory: creates a base row frame with label
local function BaseElement(section, height, labelText)
	local frame = Create("Frame", {
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Theme.Element,
		Parent = section.Frame,
	})
	Round(frame, 6)
	local stroke = Stroke(frame, Theme.Stroke)

	local label
	if labelText then
		label = Create("TextLabel", {
			Size = UDim2.new(1, -20, 0, height >= 44 and 20 or height),
			Position = UDim2.new(0, 10, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = labelText,
			TextColor3 = Theme.Text,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
	end
	return frame, label, stroke
end

local function RegisterFlag(flag, item, default, callback)
	if flag then
		Library.Flags[flag] = default
		Library.Items[flag] = item
	end
	return function(value)
		if flag then Library.Flags[flag] = value end
		if callback then
			task.spawn(callback, value)
		end
	end
end

function Library._AttachComponents(Section)

	--// Label -----------------------------------------------------------------
	function Section:AddLabel(text)
		local label = Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = text or "Label",
			TextColor3 = Theme.SubText,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = Section.Frame,
		})
		local item = {}
		function item:Set(newText) label.Text = newText end
		return item
	end

	--// Paragraph -------------------------------------------------------------
	function Section:AddParagraph(config)
		config = config or {}
		local frame = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.Element,
			Parent = Section.Frame,
		})
		Round(frame, 6)
		Stroke(frame, Theme.Stroke)
		Padding(frame, 8, 8, 10, 10)
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4), Parent = frame })

		local titleLabel = Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 14),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = config.Title or "Paragraph",
			TextColor3 = Theme.Text,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local bodyLabel = Create("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = config.Content or "",
			TextColor3 = Theme.SubText,
			TextSize = 12,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local item = {}
		function item:Set(newConfig)
			if newConfig.Title then titleLabel.Text = newConfig.Title end
			if newConfig.Content then bodyLabel.Text = newConfig.Content end
		end
		return item
	end

	--// Button ----------------------------------------------------------------
	function Section:AddButton(config)
		config = config or {}
		local frame, label, stroke = BaseElement(self, 32, config.Title or "Button")
		label.Size = UDim2.new(1, -20, 1, 0)

		local btn = Create("TextButton", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = "",
			Parent = frame,
		})

		Create("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = ">",
			TextColor3 = Theme.SubText,
			TextSize = 12,
			Parent = frame,
		})

		Connect(btn.MouseEnter, function()
			Tween(frame, TWEEN_FAST, { BackgroundColor3 = Theme.ElementHover })
			Tween(stroke, TWEEN_FAST, { Color = Theme.StrokeLight })
		end)
		Connect(btn.MouseLeave, function()
			Tween(frame, TWEEN_FAST, { BackgroundColor3 = Theme.Element })
			Tween(stroke, TWEEN_FAST, { Color = Theme.Stroke })
		end)
		Connect(btn.MouseButton1Click, function()
			Tween(stroke, TWEEN_FAST, { Color = Theme.Accent })
			task.delay(0.15, function()
				Tween(stroke, TWEEN_FAST, { Color = Theme.Stroke })
			end)
			if config.Callback then task.spawn(config.Callback) end
		end)

		local item = {}
		function item:SetTitle(t) label.Text = t end
		return item
	end

	--// Toggle ----------------------------------------------------------------
	function Section:AddToggle(config)
		config = config or {}
		local state = config.Default or false
		local frame, label = BaseElement(self, 32, config.Title or "Toggle")
		label.Size = UDim2.new(1, -60, 1, 0)

		local track = Create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(34, 18),
			BackgroundColor3 = state and Theme.Accent or Theme.Tertiary,
			Parent = frame,
		})
		Round(track, 9)
		Stroke(track, Theme.StrokeLight)

		local knob = Create("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = state and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
			Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = Theme.Text,
			Parent = track,
		})
		Round(knob, 7)

		local item = {}
		local fire = RegisterFlag(config.Flag, item, state, config.Callback)

		local function Render()
			Tween(track, TWEEN_FAST, { BackgroundColor3 = state and Theme.Accent or Theme.Tertiary })
			Tween(knob, TWEEN_FAST, {
				Position = state and UDim2.new(1, -16, 0.5, 0) or UDim2.new(0, 2, 0.5, 0),
			})
		end

		local btn = Create("TextButton", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = "",
			Parent = frame,
		})
		Connect(btn.MouseButton1Click, function()
			state = not state
			Render()
			fire(state)
		end)
		Connect(btn.MouseEnter, function()
			Tween(frame, TWEEN_FAST, { BackgroundColor3 = Theme.ElementHover })
		end)
		Connect(btn.MouseLeave, function()
			Tween(frame, TWEEN_FAST, { BackgroundColor3 = Theme.Element })
		end)

		function item:Set(value)
			state = value and true or false
			Render()
			fire(state)
		end
		function item:Get() return state end

		if state then fire(state) end
		return item
	end

	--// Slider ----------------------------------------------------------------
	function Section:AddSlider(config)
		config = config or {}
		local min      = config.Min or 0
		local max      = config.Max or 100
		local step     = config.Step or 1
		local value    = math.clamp(config.Default or min, min, max)
		local suffix   = config.Suffix or ""

		local frame, label = BaseElement(self, 48, config.Title or "Slider")

		local valueLabel = Create("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -10, 0, 0),
			Size = UDim2.new(0, 80, 0, 20),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = tostring(value) .. suffix,
			TextColor3 = Theme.SubText,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = frame,
		})

		local bar = Create("Frame", {
			Position = UDim2.new(0, 10, 0, 30),
			Size = UDim2.new(1, -20, 0, 6),
			BackgroundColor3 = Theme.Tertiary,
			Parent = frame,
		})
		Round(bar, 3)

		local fill = Create("Frame", {
			Size = UDim2.new((value - min) / (max - min), 0, 1, 0),
			BackgroundColor3 = Theme.Accent,
			Parent = bar,
		})
		Round(fill, 3)

		local knob = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new((value - min) / (max - min), 0, 0.5, 0),
			Size = UDim2.fromOffset(12, 12),
			BackgroundColor3 = Theme.Text,
			Parent = bar,
		})
		Round(knob, 6)
		Stroke(knob, Theme.Accent, 2)

		local item = {}
		local fire = RegisterFlag(config.Flag, item, value, config.Callback)

		local function SetValue(newValue, skipCallback)
			newValue = math.clamp(newValue, min, max)
			newValue = math.floor((newValue - min) / step + 0.5) * step + min
			newValue = math.clamp(newValue, min, max)
			-- avoid float dust
			if step % 1 == 0 then
				newValue = math.floor(newValue + 0.5)
			else
				newValue = math.floor(newValue * 100 + 0.5) / 100
			end
			value = newValue
			local alpha = (max == min) and 0 or (value - min) / (max - min)
			Tween(fill, TWEEN_FAST, { Size = UDim2.new(alpha, 0, 1, 0) })
			Tween(knob, TWEEN_FAST, { Position = UDim2.new(alpha, 0, 0.5, 0) })
			valueLabel.Text = tostring(value) .. suffix
			if not skipCallback then fire(value) end
		end

		local dragging = false
		local function UpdateFromInput(input)
			local alpha = math.clamp((input.Position.X - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
			SetValue(min + alpha * (max - min))
		end

		Connect(bar.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
				dragging = true
				UpdateFromInput(input)
			end
		end)
		Connect(UserInput.InputChanged, function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
				UpdateFromInput(input)
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
		return item
	end

	--// Dropdown --------------------------------------------------------------
	function Section:AddDropdown(config)
		config = config or {}
		local options  = config.Options or {}
		local multi    = config.Multi or false
		local selected = multi and {} or (config.Default or nil)
		if multi and config.Default then
			for _, v in ipairs(config.Default) do selected[v] = true end
		end

		local frame, label = BaseElement(self, 32, config.Title or "Dropdown")
		label.Size = UDim2.new(0.45, -10, 1, 0)

		local open = false

		local display = Create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0.5, 0, 0, 24),
			BackgroundColor3 = Theme.Tertiary,
			Font = Enum.Font.Gotham,
			Text = "",
			AutoButtonColor = false,
			Parent = frame,
		})
		Round(display, 5)
		Stroke(display, Theme.StrokeLight)

		local displayText = Create("TextLabel", {
			Size = UDim2.new(1, -26, 1, 0),
			Position = UDim2.new(0, 8, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			Text = "None",
			TextColor3 = Theme.SubText,
			TextSize = 11,
			TextTruncate = Enum.TextTruncate.AtEnd,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = display,
		})

		local arrow = Create("TextLabel", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.fromOffset(10, 10),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamBold,
			Text = "v",
			TextColor3 = Theme.SubText,
			TextSize = 10,
			Parent = display,
		})

		local listFrame = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundColor3 = Theme.Tertiary,
			Visible = false,
			Parent = Section.Frame,
		})
		Round(listFrame, 6)
		Stroke(listFrame, Theme.StrokeLight)
		Padding(listFrame, 4, 4, 4, 4)
		Create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2), Parent = listFrame })

		-- keep the option list right below the dropdown row
		listFrame.LayoutOrder = frame.LayoutOrder + 1

		local item = {}
		local fire = RegisterFlag(config.Flag, item, selected, config.Callback)
		local optionButtons = {}

		local function GetDisplayText()
			if multi then
				local parts = {}
				for _, opt in ipairs(options) do
					if selected[opt] then table.insert(parts, opt) end
				end
				return #parts > 0 and table.concat(parts, ", ") or "None"
			end
			return selected or "None"
		end

		local function RenderOptions()
			for _, b in ipairs(optionButtons) do b:Destroy() end
			table.clear(optionButtons)
			for _, opt in ipairs(options) do
				local isSelected = multi and selected[opt] or selected == opt
				local optBtn = Create("TextButton", {
					Size = UDim2.new(1, 0, 0, 26),
					BackgroundColor3 = isSelected and Theme.Element or Theme.Tertiary,
					Font = Enum.Font.Gotham,
					Text = "",
					AutoButtonColor = false,
					Parent = listFrame,
				})
				Round(optBtn, 4)
				Create("TextLabel", {
					Size = UDim2.new(1, -16, 1, 0),
					Position = UDim2.new(0, 8, 0, 0),
					BackgroundTransparency = 1,
					Font = Enum.Font.Gotham,
					Text = opt,
					TextColor3 = isSelected and Theme.Accent or Theme.SubText,
					TextSize = 11,
					TextXAlignment = Enum.TextXAlignment.Left,
					Parent = optBtn,
				})
				Connect(optBtn.MouseButton1Click, function()
					if multi then
						selected[opt] = not selected[opt] or nil
					else
						selected = opt
					end
					displayText.Text = GetDisplayText()
					displayText.TextColor3 = Theme.Text
					fire(selected)
					RenderOptions()
					if not multi then
						open = false
						listFrame.Visible = false
						arrow.Text = "v"
					end
				end)
				table.insert(optionButtons, optBtn)
			end
		end

		Connect(display.MouseButton1Click, function()
			open = not open
			listFrame.Visible = open
			arrow.Text = open and "^" or "v"
			if open then RenderOptions() end
		end)

		displayText.Text = GetDisplayText()

		function item:Set(value)
			if multi then
				selected = {}
				for _, v in ipairs(value) do selected[v] = true end
			else
				selected = value
			end
			displayText.Text = GetDisplayText()
			displayText.TextColor3 = Theme.Text
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

	--// Textbox ---------------------------------------------------------------
	function Section:AddTextbox(config)
		config = config or {}
		local frame, label = BaseElement(self, 32, config.Title or "Textbox")
		label.Size = UDim2.new(0.45, -10, 1, 0)

		local boxHolder = Create("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0.5, 0, 0, 24),
			BackgroundColor3 = Theme.Tertiary,
			Parent = frame,
		})
		Round(boxHolder, 5)
		local boxStroke = Stroke(boxHolder, Theme.StrokeLight)

		local box = Create("TextBox", {
			Size = UDim2.new(1, -16, 1, 0),
			Position = UDim2.new(0, 8, 0, 0),
			BackgroundTransparency = 1,
			Font = Enum.Font.Gotham,
			PlaceholderText = config.Placeholder or "Type here...",
			PlaceholderColor3 = Theme.SubText,
			Text = config.Default or "",
			TextColor3 = Theme.Text,
			TextSize = 11,
			ClearTextOnFocus = config.ClearOnFocus == true,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = boxHolder,
		})

		local item = {}
		local fire = RegisterFlag(config.Flag, item, box.Text, config.Callback)

		Connect(box.Focused, function()
			Tween(boxStroke, TWEEN_FAST, { Color = Theme.Accent })
		end)
		Connect(box.FocusLost, function(enterPressed)
			Tween(boxStroke, TWEEN_FAST, { Color = Theme.StrokeLight })
			fire(box.Text)
		end)

		function item:Set(text)
			box.Text = text
			fire(text)
		end
		function item:Get() return box.Text end
		return item
	end

	--// Keybind ---------------------------------------------------------------
	function Section:AddKeybind(config)
		config = config or {}
		local currentKey = config.Default -- Enum.KeyCode or nil
		local listening = false

		local frame, label = BaseElement(self, 32, config.Title or "Keybind")
		label.Size = UDim2.new(1, -110, 1, 0)

		local keyBtn = Create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(90, 24),
			BackgroundColor3 = Theme.Tertiary,
			Font = Enum.Font.GothamMedium,
			Text = currentKey and currentKey.Name or "None",
			TextColor3 = Theme.SubText,
			TextSize = 11,
			AutoButtonColor = false,
			Parent = frame,
		})
		Round(keyBtn, 5)
		local keyStroke = Stroke(keyBtn, Theme.StrokeLight)

		local item = {}
		local fire = RegisterFlag(config.Flag, item, currentKey, nil)

		Connect(keyBtn.MouseButton1Click, function()
			listening = true
			keyBtn.Text = "..."
			Tween(keyStroke, TWEEN_FAST, { Color = Theme.Accent })
		end)

		Connect(UserInput.InputBegan, function(input, processed)
			if listening then
				if input.UserInputType == Enum.UserInputType.Keyboard then
					if input.KeyCode == Enum.KeyCode.Escape then
						currentKey = nil
						keyBtn.Text = "None"
					else
						currentKey = input.KeyCode
						keyBtn.Text = currentKey.Name
					end
					listening = false
					Tween(keyStroke, TWEEN_FAST, { Color = Theme.StrokeLight })
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

		function item:Set(keyCode)
			currentKey = keyCode
			keyBtn.Text = currentKey and currentKey.Name or "None"
			fire(currentKey)
		end
		function item:Get() return currentKey end
		return item
	end

	--// ColorPicker (compact HSV) --------------------------------------------
	function Section:AddColorPicker(config)
		config = config or {}
		local color = config.Default or Theme.Accent
		local h, s, v = color:ToHSV()

		local frame, label = BaseElement(self, 32, config.Title or "Color")
		label.Size = UDim2.new(1, -60, 1, 0)

		local preview = Create("TextButton", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(36, 20),
			BackgroundColor3 = color,
			Text = "",
			AutoButtonColor = false,
			Parent = frame,
		})
		Round(preview, 5)
		Stroke(preview, Theme.StrokeLight)

		local open = false
		local picker = Create("Frame", {
			Size = UDim2.new(1, 0, 0, 130),
			BackgroundColor3 = Theme.Tertiary,
			Visible = false,
			Parent = Section.Frame,
		})
		Round(picker, 6)
		Stroke(picker, Theme.StrokeLight)
		picker.LayoutOrder = frame.LayoutOrder + 1

		-- saturation/value square
		local svSquare = Create("ImageButton", {
			Position = UDim2.new(0, 8, 0, 8),
			Size = UDim2.new(1, -40, 1, -16),
			BackgroundColor3 = Color3.fromHSV(h, 1, 1),
			AutoButtonColor = false,
			Image = "",
			Parent = picker,
		})
		Round(svSquare, 4)
		-- white gradient (saturation)
		Create("UIGradient", {
			Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(1, 1, 1)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(1, 1),
			}),
			Parent = svSquare,
		})
		-- black overlay (value)
		local blackOverlay = Create("Frame", {
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			Parent = svSquare,
		})
		Round(blackOverlay, 4)
		Create("UIGradient", {
			Rotation = 90,
			Color = ColorSequence.new(Color3.new(0, 0, 0), Color3.new(0, 0, 0)),
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(1, 0),
			}),
			Parent = blackOverlay,
		})
		blackOverlay.BackgroundTransparency = 0
		blackOverlay.BackgroundColor3 = Color3.new(0, 0, 0)

		local svCursor = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(s, 0, 1 - v, 0),
			Size = UDim2.fromOffset(10, 10),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 3,
			Parent = svSquare,
		})
		Round(svCursor, 5)
		Stroke(svCursor, Color3.new(0, 0, 0), 1)

		-- hue bar
		local hueBar = Create("ImageButton", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -8, 0, 8),
			Size = UDim2.new(0, 16, 1, -16),
			AutoButtonColor = false,
			Image = "",
			BackgroundColor3 = Color3.new(1, 1, 1),
			Parent = picker,
		})
		Round(hueBar, 4)
		local hueKeypoints = {}
		for i = 0, 6 do
			table.insert(hueKeypoints, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV(i / 6, 1, 1)))
		end
		Create("UIGradient", { Rotation = 90, Color = ColorSequence.new(hueKeypoints), Parent = hueBar })

		local hueCursor = Create("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, h, 0),
			Size = UDim2.new(1, 4, 0, 4),
			BackgroundColor3 = Color3.new(1, 1, 1),
			ZIndex = 3,
			Parent = hueBar,
		})
		Round(hueCursor, 2)

		local item = {}
		local fire = RegisterFlag(config.Flag, item, color, config.Callback)

		local function UpdateColor(skipCallback)
			color = Color3.fromHSV(h, s, v)
			preview.BackgroundColor3 = color
			svSquare.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
			svCursor.Position = UDim2.new(s, 0, 1 - v, 0)
			hueCursor.Position = UDim2.new(0.5, 0, h, 0)
			if not skipCallback then fire(color) end
		end

		local svDragging, hueDragging = false, false

		Connect(svSquare.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then svDragging = true end
		end)
		Connect(hueBar.InputBegan, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then hueDragging = true end
		end)
		Connect(UserInput.InputEnded, function(input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				svDragging, hueDragging = false, false
			end
		end)
		Connect(UserInput.InputChanged, function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
			if svDragging then
				s = math.clamp((input.Position.X - svSquare.AbsolutePosition.X) / svSquare.AbsoluteSize.X, 0, 1)
				v = 1 - math.clamp((input.Position.Y - svSquare.AbsolutePosition.Y) / svSquare.AbsoluteSize.Y, 0, 1)
				UpdateColor()
			elseif hueDragging then
				h = math.clamp((input.Position.Y - hueBar.AbsolutePosition.Y) / hueBar.AbsoluteSize.Y, 0, 1)
				UpdateColor()
			end
		end)

		Connect(preview.MouseButton1Click, function()
			open = not open
			picker.Visible = open
		end)

		function item:Set(newColor)
			h, s, v = newColor:ToHSV()
			UpdateColor()
		end
		function item:Get() return color end
		return item
	end
end

return Library
