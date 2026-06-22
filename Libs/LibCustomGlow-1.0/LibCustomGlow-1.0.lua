--[[
This library contains work of Hendrick "nevcairiel" Leppkes
https://www.wowace.com/projects/libbuttonglow-1-0

Rewritten for WoW 3.3.5a compatibility:
- Manual texture/frame pool management (no CreateTexturePool/CreateFramePool)
- No mask textures (CreateMaskTexture added in 7.0)
- No SetColorTexture (use SetTexture with solid color workaround)
- No SetAtlas (added in 5.0)
- No FlipBook animations (added in 9.0)
- No SetChildKey on animations (added in 9.0)
- No SetToFinalAlpha on AnimationGroup (added in 4.0)
]]

local MAJOR_VERSION = "LibCustomGlow-1.0"
local MINOR_VERSION = 20
if not LibStub then error(MAJOR_VERSION .. " requires LibStub.") end
local lib, oldversion = LibStub:NewLibrary(MAJOR_VERSION, MINOR_VERSION)
if not lib then return end
local Masque = LibStub("Masque", true)

local textureList = {
    white = [[Interface\BUTTONS\WHITE8X8]],
    shine = [[Interface\ItemSocketingFrame\UI-ItemSockets]]
}

local shineCoords = {0.3984375, 0.4453125, 0.40234375, 0.44921875}

function lib.RegisterTextures(texture,id)
    textureList[id] = texture
end

lib.glowList = {}
lib.startList = {}
lib.stopList = {}

local GlowParent = UIParent

-- Manual Texture Pool (replaces CreateTexturePool)
local GlowTexPool = {
    inactive = {},
    active = {},
}
function GlowTexPool:Acquire()
    local tex = tremove(self.inactive)
    local new = tex == nil
    if new then
        tex = GlowParent:CreateTexture(nil, "ARTWORK")
    end
    tex:Show()
    self.active[tex] = true
    return tex, new
end
function GlowTexPool:Release(tex)
    if not self.active[tex] then return end
    self.active[tex] = nil
    tex:Hide()
    tex:ClearAllPoints()
    tex:SetTexture(nil)
    tex:SetParent(GlowParent)
    tinsert(self.inactive, tex)
end
lib.GlowTexPool = GlowTexPool

-- Manual Frame Pool (replaces CreateFramePool)
local function MakeFramePool(resetFunc)
    local pool = {
        inactive = {},
        active = {},
        resetFunc = resetFunc,
    }
    function pool:Acquire()
        local frame = tremove(self.inactive)
        local new = frame == nil
        if new then
            frame = CreateFrame("Frame", nil, GlowParent)
        end
        self.active[frame] = true
        return frame, new
    end
    function pool:Release(frame)
        if not self.active[frame] then return end
        self.active[frame] = nil
        if self.resetFunc then
            self.resetFunc(self, frame)
        end
        tinsert(self.inactive, frame)
    end
    return pool
end

local FramePoolResetter = function(framePool, frame)
    frame:SetScript("OnUpdate", nil)
    local parent = frame:GetParent()
    if parent and frame.name and parent[frame.name] then
        parent[frame.name] = nil
    end
    if frame.textures then
        for _, texture in pairs(frame.textures) do
            GlowTexPool:Release(texture)
        end
    end
    if frame.bg then
        GlowTexPool:Release(frame.bg)
        frame.bg = nil
    end
    frame.textures = {}
    frame.info = {}
    frame.name = nil
    frame.timer = nil
    frame:Hide()
    frame:ClearAllPoints()
end
local GlowFramePool = MakeFramePool(FramePoolResetter)
lib.GlowFramePool = GlowFramePool

local function addFrameAndTex(r, color, name, key, N, xOffset, yOffset, texture, texCoord, desaturated, frameLevel)
    key = key or ""
    frameLevel = frameLevel or 8
    if not r[name..key] then
        r[name..key] = GlowFramePool:Acquire()
        r[name..key]:SetParent(r)
        r[name..key].name = name..key
    end
    local f = r[name..key]
    f:SetFrameLevel(r:GetFrameLevel()+frameLevel)
    f:SetPoint("TOPLEFT", r, "TOPLEFT", -xOffset+0.05, yOffset+0.05)
    f:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", xOffset, -yOffset+0.05)
    f:Show()

    if not f.textures then
        f.textures = {}
    end

    for i=1, N do
        if not f.textures[i] then
            f.textures[i] = GlowTexPool:Acquire()
            f.textures[i]:SetTexture(texture)
            f.textures[i]:SetTexCoord(texCoord[1], texCoord[2], texCoord[3], texCoord[4])
            if desaturated then
                f.textures[i]:SetDesaturated(desaturated)
            end
            f.textures[i]:SetParent(f)
            f.textures[i]:SetDrawLayer("ARTWORK", 7)
            if name == "_AutoCastGlow" then
                f.textures[i]:SetBlendMode("ADD")
            end
        end
        f.textures[i]:SetVertexColor(color[1], color[2], color[3], color[4])
        f.textures[i]:Show()
    end
    while #f.textures > N do
        GlowTexPool:Release(f.textures[#f.textures])
        table.remove(f.textures)
    end
end


--Pixel Glow Functions--
-- In 3.3.5a we cannot use mask textures to clip the pixel dots to the border.
-- Instead, we simply move the dots around the perimeter and show/hide them
-- based on their computed position. The visual is slightly different (no inner
-- masking) but provides the same spinning-dots feedback.

local pCalc1 = function(progress, s, th, p)
    local c
    if progress > p[3] or progress < p[0] then
        c = 0
    elseif progress > p[2] then
        c = s - th - (progress - p[2]) / (p[3] - p[2]) * (s - th)
    elseif progress > p[1] then
        c = s - th
    else
        c = (progress - p[0]) / (p[1] - p[0]) * (s - th)
    end
    return math.floor(c + 0.5)
end

local pCalc2 = function(progress, s, th, p)
    local c
    if progress > p[3] then
        c = s - th - (progress - p[3]) / (p[0] + 1 - p[3]) * (s - th)
    elseif progress > p[2] then
        c = s - th
    elseif progress > p[1] then
        c = (progress - p[1]) / (p[2] - p[1]) * (s - th)
    elseif progress > p[0] then
        c = 0
    else
        c = s - th - (progress + 1 - p[3]) / (p[0] + 1 - p[3]) * (s - th)
    end
    return math.floor(c + 0.5)
end

local pUpdate = function(self, elapsed)
    self.timer = self.timer + elapsed / self.info.period
    if self.timer > 1 or self.timer < -1 then
        self.timer = self.timer % 1
    end
    local progress = self.timer
    local width, height = self:GetSize()
    if width ~= self.info.width or height ~= self.info.height then
        local perimeter = 2 * (width + height)
        if not (perimeter > 0) then
            return
        end
        self.info.width = width
        self.info.height = height
        self.info.pTLx = {
            [0] = (height + self.info.length / 2) / perimeter,
            [1] = (height + width + self.info.length / 2) / perimeter,
            [2] = (2 * height + width - self.info.length / 2) / perimeter,
            [3] = 1 - self.info.length / 2 / perimeter
        }
        self.info.pTLy = {
            [0] = (height - self.info.length / 2) / perimeter,
            [1] = (height + width + self.info.length / 2) / perimeter,
            [2] = (height * 2 + width + self.info.length / 2) / perimeter,
            [3] = 1 - self.info.length / 2 / perimeter
        }
        self.info.pBRx = {
            [0] = self.info.length / 2 / perimeter,
            [1] = (height - self.info.length / 2) / perimeter,
            [2] = (height + width - self.info.length / 2) / perimeter,
            [3] = (height * 2 + width + self.info.length / 2) / perimeter
        }
        self.info.pBRy = {
            [0] = self.info.length / 2 / perimeter,
            [1] = (height + self.info.length / 2) / perimeter,
            [2] = (height + width - self.info.length / 2) / perimeter,
            [3] = (height * 2 + width - self.info.length / 2) / perimeter
        }
    end
    if self:IsShown() then
        if self.bg and not (self.bg:IsShown()) then
            self.bg:Show()
        end
        for k, line in pairs(self.textures) do
            line:SetPoint("TOPLEFT", self, "TOPLEFT",
                pCalc1((progress + self.info.step * (k - 1)) % 1, width, self.info.th, self.info.pTLx),
                -pCalc2((progress + self.info.step * (k - 1)) % 1, height, self.info.th, self.info.pTLy))
            line:SetPoint("BOTTOMRIGHT", self, "TOPLEFT",
                self.info.th + pCalc2((progress + self.info.step * (k - 1)) % 1, width, self.info.th, self.info.pBRx),
                -height + pCalc1((progress + self.info.step * (k - 1)) % 1, height, self.info.th, self.info.pBRy))
        end
    end
end

function lib.PixelGlow_Start(r, color, N, frequency, length, th, xOffset, yOffset, border, key, frameLevel)
    if not r then
        return
    end
    if not color then
        color = {0.95, 0.95, 0.32, 1}
    end

    if not (N and N > 0) then
        N = 8
    end

    local period
    if frequency then
        if not (frequency > 0 or frequency < 0) then
            period = 4
        else
            period = 1 / frequency
        end
    else
        period = 4
    end
    local width, height = r:GetSize()
    length = length or math.floor((width + height) * (2 / N - 0.1))
    length = min(length, min(width, height))
    th = th or 1
    xOffset = xOffset or 0
    yOffset = yOffset or 0
    key = key or ""

    addFrameAndTex(r, color, "_PixelGlow", key, N, xOffset, yOffset, textureList.white, {0, 1, 0, 1}, nil, frameLevel)
    local f = r["_PixelGlow"..key]

    -- No mask textures in 3.3.5a. Instead we use a dark border background
    -- to approximate the visual of dots constrained to the frame edge.
    if not (border == false) then
        if not f.bg then
            f.bg = GlowTexPool:Acquire()
            f.bg:SetTexture(textureList.white)
            f.bg:SetVertexColor(0.1, 0.1, 0.1, 0.8)
            f.bg:SetParent(f)
            f.bg:SetDrawLayer("ARTWORK", 6)
        end
        f.bg:ClearAllPoints()
        f.bg:SetPoint("TOPLEFT", f, "TOPLEFT", th + 1, -th - 1)
        f.bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -th - 1, th + 1)
        f.bg:Show()
    else
        if f.bg then
            GlowTexPool:Release(f.bg)
            f.bg = nil
        end
    end

    f.timer = f.timer or 0
    f.info = f.info or {}
    f.info.step = 1 / N
    f.info.period = period
    f.info.th = th
    if f.info.length ~= length then
        f.info.width = nil
        f.info.length = length
    end
    pUpdate(f, 0)
    f:SetScript("OnUpdate", pUpdate)
end

function lib.PixelGlow_Stop(r, key)
    if not r then
        return
    end
    key = key or ""
    if not r["_PixelGlow"..key] then
        return false
    else
        GlowFramePool:Release(r["_PixelGlow"..key])
    end
end

table.insert(lib.glowList, "Pixel Glow")
lib.startList["Pixel Glow"] = lib.PixelGlow_Start
lib.stopList["Pixel Glow"] = lib.PixelGlow_Stop


--Autocast Glow Functions--
local function acUpdate(self, elapsed)
    local width, height = self:GetSize()
    if width ~= self.info.width or height ~= self.info.height then
        if width * height == 0 then return end
        self.info.width = width
        self.info.height = height
        self.info.perimeter = 2 * (width + height)
        self.info.bottomlim = height * 2 + width
        self.info.rightlim = height + width
        self.info.space = self.info.perimeter / self.info.N
    end

    local texIndex = 0
    for k = 1, 4 do
        self.timer[k] = self.timer[k] + elapsed / (self.info.period * k)
        if self.timer[k] > 1 or self.timer[k] < -1 then
            self.timer[k] = self.timer[k] % 1
        end
        for i = 1, self.info.N do
            texIndex = texIndex + 1
            local position = (self.info.space * i + self.info.perimeter * self.timer[k]) % self.info.perimeter
            if position > self.info.bottomlim then
                self.textures[texIndex]:SetPoint("CENTER", self, "BOTTOMRIGHT", -position + self.info.bottomlim, 0)
            elseif position > self.info.rightlim then
                self.textures[texIndex]:SetPoint("CENTER", self, "TOPRIGHT", 0, -position + self.info.rightlim)
            elseif position > self.info.height then
                self.textures[texIndex]:SetPoint("CENTER", self, "TOPLEFT", position - self.info.height, 0)
            else
                self.textures[texIndex]:SetPoint("CENTER", self, "BOTTOMLEFT", 0, position)
            end
        end
    end
end

function lib.AutoCastGlow_Start(r, color, N, frequency, scale, xOffset, yOffset, key, frameLevel)
    if not r then
        return
    end

    if not color then
        color = {0.95, 0.95, 0.32, 1}
    end

    if not (N and N > 0) then
        N = 4
    end

    local period
    if frequency then
        if not (frequency > 0 or frequency < 0) then
            period = 8
        else
            period = 1 / frequency
        end
    else
        period = 8
    end
    scale = scale or 1
    xOffset = xOffset or 0
    yOffset = yOffset or 0
    key = key or ""

    addFrameAndTex(r, color, "_AutoCastGlow", key, N * 4, xOffset, yOffset, textureList.shine, shineCoords, true, frameLevel)
    local f = r["_AutoCastGlow"..key]
    local sizes = {7, 6, 5, 4}
    for k, size in pairs(sizes) do
        for i = 1, N do
            f.textures[i + N * (k - 1)]:SetSize(size * scale, size * scale)
        end
    end
    f.timer = f.timer or {0, 0, 0, 0}
    f.info = f.info or {}
    f.info.N = N
    f.info.period = period
    f:SetScript("OnUpdate", acUpdate)
    acUpdate(f, 0)
end

function lib.AutoCastGlow_Stop(r, key)
    if not r then
        return
    end

    key = key or ""
    if not r["_AutoCastGlow"..key] then
        return false
    else
        GlowFramePool:Release(r["_AutoCastGlow"..key])
    end
end

table.insert(lib.glowList, "Autocast Shine")
lib.startList["Autocast Shine"] = lib.AutoCastGlow_Start
lib.stopList["Autocast Shine"] = lib.AutoCastGlow_Stop

--Action Button Glow--
-- For 3.3.5a we cannot use SetChildKey on animations. Instead we drive the
-- entire intro/outro sequence with OnUpdate handlers that manually interpolate
-- alpha and scale values on each child texture.

local function ButtonGlowResetter(framePool, frame)
    frame:SetScript("OnUpdate", nil)
    frame:SetScript("OnHide", nil)
    local parent = frame:GetParent()
    if parent and parent._ButtonGlow then
        parent._ButtonGlow = nil
    end
    if frame.spark then frame.spark:Hide() end
    if frame.innerGlow then frame.innerGlow:Hide() end
    if frame.innerGlowOver then frame.innerGlowOver:Hide() end
    if frame.outerGlow then frame.outerGlow:Hide() end
    if frame.outerGlowOver then frame.outerGlowOver:Hide() end
    if frame.ants then frame.ants:Hide() end
    frame:Hide()
    frame:ClearAllPoints()
end
local ButtonGlowPool = MakeFramePool(ButtonGlowResetter)
lib.ButtonGlowPool = ButtonGlowPool

local ButtonGlowTextures = {
    ["spark"] = true,
    ["innerGlow"] = true,
    ["innerGlowOver"] = true,
    ["outerGlow"] = true,
    ["outerGlowOver"] = true,
    ["ants"] = true,
}

local function noZero(num)
    if num == 0 then
        return 0.001
    else
        return num
    end
end

-- OnUpdate-driven animation state machine for ButtonGlow
-- States: "animIn" -> "loop" -> "animOut" -> done
local function bgAnimUpdate(self, elapsed)
    if not self.animState then return end

    self.animTimer = (self.animTimer or 0) + elapsed

    if self.animState == "animIn" then
        -- Phase 1 (0 - 0.2s): spark scales up 1->1.5, fades in
        -- Phase 2 (0 - 0.3s): innerGlow scales 1->2, innerGlowOver scales 1->2 fades out
        --                      outerGlow scales 1->0.5, outerGlowOver scales 1->0.5 fades out
        -- Phase 3 (0.2 - 0.4s): spark scales 1.5->1 (i.e. 2/3 relative), fades out
        -- Phase 4 (0.3 - 0.5s): innerGlow fades out, ants fade in
        local t = self.animTimer
        local alpha = self.animAlpha or 1

        -- spark
        if t < 0.2 then
            local p = t / 0.2
            self.spark:SetAlpha(p * alpha)
            local s = 1 + 0.5 * p
            local fw, fh = self:GetSize()
            self.spark:SetSize(fw * s, fh * s)
        elseif t < 0.4 then
            local p = (t - 0.2) / 0.2
            self.spark:SetAlpha((1 - p) * alpha)
            local s = 1.5 - 0.5 * p
            local fw, fh = self:GetSize()
            self.spark:SetSize(fw * s, fh * s)
        else
            self.spark:SetAlpha(0)
        end

        -- innerGlow + innerGlowOver
        if t < 0.3 then
            local p = t / 0.3
            local fw, fh = self:GetSize()
            local s = 0.5 + 0.5 * p  -- half to full (started at half in OnPlay)
            self.innerGlow:SetSize(fw * s, fh * s)
            self.innerGlow:SetAlpha(alpha)
            self.innerGlowOver:SetAlpha((1 - p) * alpha)
        else
            self.innerGlow:SetAlpha(alpha)
            self.innerGlowOver:SetAlpha(0)
        end

        -- outerGlow + outerGlowOver
        if t < 0.3 then
            local p = t / 0.3
            local fw, fh = self:GetSize()
            local s = 2 - p  -- 2x down to 1x
            self.outerGlow:SetSize(fw * s, fh * s)
            self.outerGlow:SetAlpha(alpha)
            self.outerGlowOver:SetAlpha((1 - p) * alpha)
        else
            local fw, fh = self:GetSize()
            self.outerGlow:SetSize(fw, fh)
            self.outerGlow:SetAlpha(alpha)
            self.outerGlowOver:SetAlpha(0)
        end

        -- innerGlow fade out after 0.3s
        if t >= 0.3 and t < 0.5 then
            local p = (t - 0.3) / 0.2
            self.innerGlow:SetAlpha((1 - p) * alpha)
        elseif t >= 0.5 then
            self.innerGlow:SetAlpha(0)
        end

        -- ants fade in after 0.3s
        if t >= 0.3 and t < 0.5 then
            local p = (t - 0.3) / 0.2
            self.ants:SetAlpha(p * alpha)
        elseif t >= 0.5 then
            self.ants:SetAlpha(alpha)
        end

        if t >= 0.5 then
            -- animIn finished - go to loop
            self.spark:SetAlpha(0)
            self.innerGlow:SetAlpha(0)
            self.innerGlowOver:SetAlpha(0)
            self.outerGlowOver:SetAlpha(0)
            local fw, fh = self:GetSize()
            self.outerGlow:SetSize(fw, fh)
            self.innerGlow:SetSize(fw, fh)
            self.ants:SetAlpha(alpha)
            self.animState = "loop"
            self.animTimer = 0
        end

    elseif self.animState == "loop" then
        -- Marching ants phase - animate tex coords
        AnimateTexCoords(self.ants, 256, 256, 48, 48, 22, elapsed, self.throttle)
        local cooldown = self:GetParent() and self:GetParent().cooldown
        if cooldown and cooldown:IsShown() and cooldown:GetCooldownDuration() > 3000 then
            self:SetAlpha(0.5)
        else
            self:SetAlpha(1.0)
        end

    elseif self.animState == "animOut" then
        local t = self.animTimer
        local alpha = self.animAlpha or 1

        -- Phase 1 (0 - 0.2s): outerGlowOver fades in, ants fade out
        -- Phase 2 (0.2 - 0.4s): outerGlowOver fades out, outerGlow fades out
        if t < 0.2 then
            local p = t / 0.2
            self.outerGlowOver:SetAlpha(p * alpha)
            self.ants:SetAlpha((1 - p) * alpha)
        elseif t < 0.4 then
            local p = (t - 0.2) / 0.2
            self.outerGlowOver:SetAlpha((1 - p) * alpha)
            self.outerGlow:SetAlpha((1 - p) * alpha)
            self.ants:SetAlpha(0)
        else
            -- animOut finished
            self.animState = nil
            self.animTimer = 0
            self:SetScript("OnUpdate", nil)
            ButtonGlowPool:Release(self)
            return
        end
    end
end

local function bgHide(self)
    if self.animState == "animOut" then
        self.animState = nil
        self.animTimer = 0
        self:SetScript("OnUpdate", nil)
        ButtonGlowPool:Release(self)
    end
end

local function configureButtonGlow(f)
    f.spark = f:CreateTexture(nil, "BACKGROUND")
    f.spark:SetPoint("CENTER")
    f.spark:SetAlpha(0)
    f.spark:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.spark:SetTexCoord(0.00781250, 0.61718750, 0.00390625, 0.26953125)

    f.innerGlow = f:CreateTexture(nil, "ARTWORK")
    f.innerGlow:SetPoint("CENTER")
    f.innerGlow:SetAlpha(0)
    f.innerGlow:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.innerGlow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)

    f.innerGlowOver = f:CreateTexture(nil, "ARTWORK")
    f.innerGlowOver:SetPoint("TOPLEFT", f.innerGlow, "TOPLEFT")
    f.innerGlowOver:SetPoint("BOTTOMRIGHT", f.innerGlow, "BOTTOMRIGHT")
    f.innerGlowOver:SetAlpha(0)
    f.innerGlowOver:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.innerGlowOver:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)

    f.outerGlow = f:CreateTexture(nil, "ARTWORK")
    f.outerGlow:SetPoint("CENTER")
    f.outerGlow:SetAlpha(0)
    f.outerGlow:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.outerGlow:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)

    f.outerGlowOver = f:CreateTexture(nil, "ARTWORK")
    f.outerGlowOver:SetPoint("TOPLEFT", f.outerGlow, "TOPLEFT")
    f.outerGlowOver:SetPoint("BOTTOMRIGHT", f.outerGlow, "BOTTOMRIGHT")
    f.outerGlowOver:SetAlpha(0)
    f.outerGlowOver:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.outerGlowOver:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)

    f.ants = f:CreateTexture(nil, "OVERLAY")
    f.ants:SetPoint("CENTER")
    f.ants:SetAlpha(0)
    f.ants:SetTexture([[Interface\SpellActivationOverlay\IconAlertAnts]])

    f:SetScript("OnHide", bgHide)
end

function lib.ButtonGlow_Start(r, color, frequency, frameLevel)
    if not r then
        return
    end
    frameLevel = frameLevel or 8
    local throttle
    if frequency and frequency > 0 then
        throttle = 0.25 / frequency * 0.01
    else
        throttle = 0.01
    end
    if r._ButtonGlow then
        local f = r._ButtonGlow
        local width, height = r:GetSize()
        f:SetFrameLevel(r:GetFrameLevel() + frameLevel)
        f:SetSize(width * 1.4, height * 1.4)
        f:SetPoint("TOPLEFT", r, "TOPLEFT", -width * 0.2, height * 0.2)
        f:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", width * 0.2, -height * 0.2)
        f.ants:SetSize(width * 1.4 * 0.85, height * 1.4 * 0.85)

        -- If animating out, restart
        if f.animState == "animOut" then
            f.animState = "animIn"
            f.animTimer = 0
        end

        local alpha
        if not color then
            for texture in pairs(ButtonGlowTextures) do
                f[texture]:SetDesaturated(nil)
                f[texture]:SetVertexColor(1, 1, 1)
            end
            f.color = false
            alpha = 1
        else
            for texture in pairs(ButtonGlowTextures) do
                f[texture]:SetDesaturated(1)
                f[texture]:SetVertexColor(color[1], color[2], color[3])
            end
            f.color = color
            alpha = color[4] or 1
        end
        f.animAlpha = alpha
        f.throttle = throttle
    else
        local f, new = ButtonGlowPool:Acquire()
        if new then
            configureButtonGlow(f)
        end
        r._ButtonGlow = f
        local width, height = r:GetSize()
        f:SetParent(r)
        f:SetFrameLevel(r:GetFrameLevel() + frameLevel)
        f:SetSize(width * 1.4, height * 1.4)
        f:SetPoint("TOPLEFT", r, "TOPLEFT", -width * 0.2, height * 0.2)
        f:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", width * 0.2, -height * 0.2)

        local alpha
        if not color then
            f.color = false
            for texture in pairs(ButtonGlowTextures) do
                f[texture]:SetDesaturated(nil)
                f[texture]:SetVertexColor(1, 1, 1)
            end
            alpha = 1
        else
            f.color = color
            for texture in pairs(ButtonGlowTextures) do
                f[texture]:SetDesaturated(1)
                f[texture]:SetVertexColor(color[1], color[2], color[3])
            end
            alpha = color[4] or 1
        end

        f.animAlpha = alpha
        f.throttle = throttle
        f.animState = "animIn"
        f.animTimer = 0
        f:Show()
        f:SetScript("OnUpdate", bgAnimUpdate)

        if Masque and Masque.UpdateSpellAlert and (not r.overlay or not issecurevariable(r, "overlay")) then
            local old_overlay = r.overlay
            r.overlay = f
            Masque:UpdateSpellAlert(r)
            r.overlay = old_overlay
        end
    end
end

function lib.ButtonGlow_Stop(r)
    if r._ButtonGlow then
        local f = r._ButtonGlow
        if f.animState == "animIn" then
            -- Cancel intro immediately
            f.animState = nil
            f.animTimer = 0
            f:SetScript("OnUpdate", nil)
            ButtonGlowPool:Release(f)
        elseif r:IsVisible() then
            -- Play outro
            f.animState = "animOut"
            f.animTimer = 0
            -- Make sure the OnUpdate is running
            f:SetScript("OnUpdate", bgAnimUpdate)
        else
            ButtonGlowPool:Release(f)
        end
    end
end

table.insert(lib.glowList, "Action Button Glow")
lib.startList["Action Button Glow"] = lib.ButtonGlow_Start
lib.stopList["Action Button Glow"] = lib.ButtonGlow_Stop


-- ProcGlow
-- In 3.3.5a there are no FlipBook animations or SetAtlas. We replace the proc
-- glow with a simple pulsing glow overlay using OnUpdate-driven alpha cycling
-- and the SpellActivationOverlay textures that exist in 3.3.5a.

local function ProcGlowResetter(framePool, frame)
    frame:SetScript("OnUpdate", nil)
    frame:SetScript("OnShow", nil)
    frame:SetScript("OnHide", nil)
    frame:Hide()
    frame:ClearAllPoints()
    local parent = frame:GetParent()
    if frame.key and parent and parent[frame.key] then
        parent[frame.key] = nil
    end
    if frame.procOverlay then
        frame.procOverlay:Hide()
    end
    if frame.procGlowTexture then
        frame.procGlowTexture:Hide()
    end
end

local ProcGlowPool = MakeFramePool(ProcGlowResetter)
lib.ProcGlowPool = ProcGlowPool

local function InitProcGlow(f)
    -- Use SpellActivationOverlay glow texture for the proc effect
    f.procOverlay = f:CreateTexture(nil, "ARTWORK")
    f.procOverlay:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.procOverlay:SetTexCoord(0.00781250, 0.50781250, 0.27734375, 0.52734375)
    f.procOverlay:SetBlendMode("ADD")
    f.procOverlay:SetAllPoints()
    f.procOverlay:SetAlpha(0)

    -- A second overlay for pulse effect
    f.procGlowTexture = f:CreateTexture(nil, "ARTWORK")
    f.procGlowTexture:SetTexture([[Interface\SpellActivationOverlay\IconAlert]])
    f.procGlowTexture:SetTexCoord(0.00781250, 0.50781250, 0.53515625, 0.78515625)
    f.procGlowTexture:SetBlendMode("ADD")
    f.procGlowTexture:SetAllPoints()
    f.procGlowTexture:SetAlpha(0)
end

local function ProcGlowUpdate(self, elapsed)
    if not self.procTimer then self.procTimer = 0 end
    self.procTimer = self.procTimer + elapsed

    local duration = self.procDuration or 1
    local phase = (self.procTimer % duration) / duration

    -- Start animation: quick flash in first cycle
    if self.procStartAnim and self.procTimer < 0.5 then
        local startPhase = self.procTimer / 0.5
        if startPhase < 0.3 then
            -- Flash bright
            local p = startPhase / 0.3
            self.procOverlay:SetAlpha(p)
            self.procGlowTexture:SetAlpha(p * 0.7)
        else
            -- Settle down
            local p = (startPhase - 0.3) / 0.7
            self.procOverlay:SetAlpha(1 - p * 0.3)
            self.procGlowTexture:SetAlpha(0.7 - p * 0.4)
        end
        return
    end

    -- Looping pulse: alpha oscillates between 0.5 and 1.0
    local pulse = 0.5 + 0.5 * math.sin(phase * math.pi * 2)
    self.procOverlay:SetAlpha(0.4 + pulse * 0.6)
    self.procGlowTexture:SetAlpha(0.2 + pulse * 0.3)
end

local ProcGlowDefaults = {
    frameLevel = 8,
    color = nil,
    startAnim = true,
    xOffset = 0,
    yOffset = 0,
    duration = 1,
    key = ""
}

function lib.ProcGlow_Start(r, options)
    if not r then
        return
    end
    options = options or {}
    setmetatable(options, { __index = ProcGlowDefaults })
    local key = "_ProcGlow" .. options.key
    local f, new
    if r[key] then
        f = r[key]
    else
        f, new = ProcGlowPool:Acquire()
        if new then
            InitProcGlow(f)
        end
        r[key] = f
    end
    f:SetParent(r)
    f:SetFrameLevel(r:GetFrameLevel() + options.frameLevel)

    local width, height = r:GetSize()
    local xOffset = options.xOffset + width * 0.2
    local yOffset = options.yOffset + height * 0.2
    f:SetPoint("TOPLEFT", r, "TOPLEFT", -xOffset, yOffset)
    f:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", xOffset, -yOffset)

    f.key = key

    -- Apply color
    if not options.color then
        f.procOverlay:SetDesaturated(nil)
        f.procOverlay:SetVertexColor(1, 1, 1, 1)
        f.procGlowTexture:SetDesaturated(nil)
        f.procGlowTexture:SetVertexColor(1, 1, 1, 1)
    else
        f.procOverlay:SetDesaturated(1)
        f.procOverlay:SetVertexColor(options.color[1], options.color[2], options.color[3], options.color[4])
        f.procGlowTexture:SetDesaturated(1)
        f.procGlowTexture:SetVertexColor(options.color[1], options.color[2], options.color[3], options.color[4])
    end

    f.procDuration = options.duration
    f.procStartAnim = options.startAnim
    f.procTimer = 0

    f.procOverlay:Show()
    f.procGlowTexture:Show()

    f:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        self.procTimer = 0
    end)
    f:SetScript("OnShow", function(self)
        self.procTimer = 0
        self:SetScript("OnUpdate", ProcGlowUpdate)
    end)

    f:Show()
    f:SetScript("OnUpdate", ProcGlowUpdate)
end

function lib.ProcGlow_Stop(r, key)
    key = key or ""
    local f = r["_ProcGlow" .. key]
    if f then
        ProcGlowPool:Release(f)
    end
end

table.insert(lib.glowList, "Proc Glow")
lib.startList["Proc Glow"] = lib.ProcGlow_Start
lib.stopList["Proc Glow"] = lib.ProcGlow_Stop
