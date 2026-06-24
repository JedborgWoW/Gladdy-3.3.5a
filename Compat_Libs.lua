--[[--------------------------------------------------------------------------
    Gladdy - WoW 3.3.5a post-library compatibility shims

    Loaded AFTER embeds.xml (so the libraries already exist) but BEFORE the
    addon's own modules. Use this file for fixes that must patch a library at
    runtime - things Compat.lua cannot do because the library is not loaded yet
    when Compat.lua runs. As with Compat.lua, the library source stays
    byte-for-byte untouched; we only re-point methods at runtime.
----------------------------------------------------------------------------]]

--==========================================================================
-- AceComm-3.0 comm-prefix length limit.
--
-- Gladdy bundles AceComm-3.0 (MINOR 14). When Gladdy loads first, its newer
-- AceComm wins LibStub for the whole session. That version enforces a retail-era
-- limit - RegisterComm() throws "prefix length is limited to 16 characters" for
-- any prefix longer than 16. On 3.3.5a there is no RegisterAddonMessagePrefix and
-- no such limit, so SendAddonMessage happily accepts longer prefixes. The limit
-- therefore only breaks OTHER addons whose libraries use a >16 char prefix (e.g.
-- the SpecializedAbsorbs-1.0 lib embedded in some addons), which is exactly why
-- that error appears only while Gladdy is enabled.
--
-- Relax the limit at runtime: for a >16 char prefix, register the same way the
-- library would, just without the length guard. Targets that embed AceComm after
-- this runs (Gladdy's own VersionCheck and any later-loading addon) pick up the
-- patched method; already-embedded targets are re-pointed below.
--==========================================================================
local AceComm = LibStub and LibStub:GetLibrary("AceComm-3.0", true)
if AceComm and AceComm.RegisterComm and not AceComm.__gladdy335PrefixPatch then
    AceComm.__gladdy335PrefixPatch = true

    local origRegisterComm = AceComm.RegisterComm
    function AceComm.RegisterComm(self, prefix, method)
        if type(prefix) == "string" and #prefix > 16 then
            if method == nil then method = "OnCommReceived" end
            if C_ChatInfo then
                C_ChatInfo.RegisterAddonMessagePrefix(prefix)
            elseif RegisterAddonMessagePrefix then
                RegisterAddonMessagePrefix(prefix) -- no-op shim on 3.3.5a (see Compat.lua)
            end
            return AceComm._RegisterComm(self, prefix, method) -- created by CallbackHandler
        end
        return origRegisterComm(self, prefix, method)
    end

    -- Re-point any target that already embedded the unpatched method.
    if AceComm.embeds then
        for target in pairs(AceComm.embeds) do
            if target.RegisterComm == origRegisterComm then
                target.RegisterComm = AceComm.RegisterComm
            end
        end
    end
end
