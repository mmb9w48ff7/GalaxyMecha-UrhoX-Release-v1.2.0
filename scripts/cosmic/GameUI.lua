-- GameUI.lua：战斗界面（HUD + 弹窗 + 触控输入），对应网页版 cosmic_run.js 里用 DOM 实现的 buildHUD / updateHUD / openLevelUp /
-- openShop / openPause / openRevive / endRun 弹窗 / startTutorial / bindPointer。游戏逻辑仍由转换后的网页版代码执行，这里只负责显示与点击。
local U = require("cosmic.Util")
local UI = require("cosmic.UI")
local GameUI = { toast = nil }
local S, C, HOST
local COL = UI.COL
local ORANGE_ = { 200, 130, 20 }
local u = {}                                  -- 界面状态：levelup / shop / pause / revive / tut
GameUI.state = u
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function R() return S.R end
function GameUI.Toast(msg) GameUI.toast = { text = msg, t = 2.6 } end

-- ---------------------------------------------------------------- 覆盖网页版的 DOM 函数
function GameUI.Install(mod, cosmic, host)
    S, C, HOST = mod, cosmic, host
    host.onToast = GameUI.Toast
    S.buildHUD = function() end
    S.updateHUD = function() end
    S.bindPointer = function() end
    local function finishLevel()
        u.levelup = nil; S.paused = false; S:afterChoice()
        local r = R(); r.gems:forEach(function(_, g) if S:dd(g, S:P()) < 2025 then g.pull = true end end)
    end
    GameUI.finishLevel = finishLevel
    S.openLevelUp = function()
        S.paused = true; local r = R(); r.pendingLevels = r.pendingLevels - 1; C:sfx("level"); r.rr = r.rr or { free = 1, ad = 0 }
        u.levelup = { ids = S:choices() }
    end
    S.openShop = function(_, n)
        S.paused = true; local r = R()
        local offers = {
            { name = "紧急维修", text = "修复 50% 耐久", cost = math.floor(150 + 0.5), go = function() r.hull = math.min(S:hullMax(), r.hull + S:hullMax() * 0.5) end },
            { name = "强化芯片", text = "立即升级 1 次", cost = 260, go = function() r.pendingLevels = r.pendingLevels + 1 end },
            { name = "星魂结晶", text = "驾驶员碎片 +5", cost = 400, go = function() r.frags[r.pilot] = (r.frags[r.pilot] or 0) + 5 end },
        }
        u.shop = { offers = offers }
    end
    S.openPause = function()
        if S.paused or not R() then return end
        S.paused = true; u.pause = true
    end
    S.openRevive = function()
        if R().ended then return end
        S.paused = true; u.revive = true
    end
    S.startTutorial = function()
        local r = R()
        local steps = {
            { text = "左半屏拖动：朝镜头方向飞行。右半屏拖动：转动视角", done = function() return math.sqrt(r.vx * r.vx + r.vy * r.vy + r.vz * r.vz) > 5 end },
            { text = "武器会自动锁定开火。飞过去捡青色的能量升级", done = function() return r.level >= 2 end },
            { text = "右下大按钮是机甲技能，旁边的小按钮是氮气推进，能冲刺并短暂无敌。点一下技能试试", done = function() return r.tutorialSkill end },
            { text = "跟着屏幕边缘的箭头，完成本星域的目标。目标可能在上方或下方", done = function() return S:objectiveDone() end },
            { text = "星门开启了！飞进去前往下一个星域", done = function() return r.sector >= 2 end },
        }
        local i = 1; u.tut = { text = steps[1].text, n = 1, total = #steps }
        r.tutorial = {
            event = function(_, k) if k == "skill" then r.tutorialSkill = true end end,
            tick = function()
                if i > #steps or S.paused then return end
                if steps[i].done() then
                    i = i + 1; C:sfx("pick")
                    if i > #steps then u.tut = nil; C.save.tutorialDone = true; C:write(); r.tutorial = nil; GameUI.Toast("引导完成，祝你远征顺利！")
                    else u.tut = { text = steps[i].text, n = i, total = #steps } end
                end
            end,
        }
    end
end
function GameUI.Reset() u.levelup, u.shop, u.pause, u.revive, u.tut = nil, nil, nil, nil, nil end
function GameUI.ModalOpen() return u.levelup or u.shop or u.pause or u.revive or (R() and R().result and R().ended) end

-- ---------------------------------------------------------------- 绘制
local function mmss(t) return U.fmtTime(t) end
local function dim(W) nvgBeginPath(UI.vg); nvgRect(UI.vg, 0, 0, W, 1080); nvgFillColor(UI.vg, nvgRGBA(0, 0, 10, 175)); nvgFill(UI.vg) end
local W = require("cosmic.WebUI")
local K = W.C
local function choiceIcon(id)
    local r = R()
    if id:sub(1, 3) == "new" then return C:modIcon(r.modPool[tonumber(id:sub(4))]) end
    if id:sub(1, 3) == "evo" or id:sub(1, 3) == "mod" then return C:modIcon(r.mods[tonumber(id:sub(4))].m) end
    if id == "heal" then return C.ICON.heal end
    if id == "main" then return UI.CatIcon(r.mech) end
    if id == "support" then return UI.CatIcon(r.pilot) end
    return C.ICON[id]
end
function GameUI.DrawHud()
    local r = R(); if not r then return end
    W.block = GameUI.ModalOpen() and true or false
    local Wd = UI.lw; local pad = 36; local m = S:M()
    -- 顶部经验条（带边框）与等级
    W.box(pad, 18, Wd - pad * 2, 30, { bg = K.lo, alpha = 200, border = K.hi, bw = 3 }); W.rect(pad + 3, 21, (Wd - pad * 2 - 6) * clamp(r.xp / S:xpNeed(r.level), 0, 1), 24, K.teal)
    W.text(Wd - pad - 12, 50, "Lv " .. r.level, 24, K.muted, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    -- 耐久 / 信用点 / 星源（带图标）
    W.text(pad, 60, "耐久 " .. math.ceil(r.hull) .. " / " .. S:hullMax(), 30, K.bone)
    UI.Icon(UI.ResIcon("credit"), pad, 104, 30); W.text(pad + 42, 102, tostring(math.floor(r.credits)), 28, K.bone)
    UI.Icon(UI.ResIcon("shard"), pad, 142, 30); W.text(pad + 42, 140, "星源 " .. r.src, 28, K.bone)
    -- 槽位：主武器 + 已装备卡牌 + 已获得的被动强化（图标 + 等级）
    local sx = pad
    local function slot(ic, label, hot)
        W.box(sx, 186, 58, 58, { bg = K.lo, alpha = 200, border = K.hi, bw = 3 }); W.pix(ic, sx + 8, 192, 38, nil, 255, true); W.text(sx + 52, 224, tostring(label), 18, hot and K.amber or K.bone, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP); sx = sx + 64
    end
    slot(UI.CatIcon(r.mech), S:lv("main"))
    r.mods:forEach(function(_, md) slot(C:modIcon(md.m), md.evo and "★" or md.lv, md.evo) end)
    for _, k in ipairs(require("jsrt.JS").keys(S.UPG)) do if k ~= "main" and k ~= "support" and S:lv(k) > 0 then slot(C.ICON[k], S:lv(k)) end end
    local head
    if r.daily then head = "每日挑战　第 " .. r.wave .. " 波　剩余 " .. mmss(C.DC_TIME - r.secT) .. "　得分 " .. S:dcScore()
    elseif r.endless then head = "无尽模式　第 " .. r.wave .. " 波　" .. mmss(r.t)
    else head = "星域 " .. r.sector .. " / " .. S.SECTORS .. "　" .. ((r.gate.state == "open") and "飞进星门" or tostring(r.objective or "")) end
    if r.danger > 1 then head = head .. "　危险 " .. r.danger end
    if r.affix then head = head .. "　[" .. r.affix.name .. "：" .. r.affix.desc .. "]" end
    W.title(Wd / 2, 52, "第 " .. r.ch.id .. " 章 " .. r.ch.name, 52, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    W.text(Wd / 2, 118, head, 28, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    -- 连击 / Boss / 提示 / 横幅
    if r.combo >= 5 and r.comboT > 0 then W.title(Wd - 340, 200, tostring(r.combo), 64, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); W.text(Wd - 340, 270, "连击", 26, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end
    if r.boss and r.boss.hp > 0 then
        W.text(Wd / 2, 160, r.boss.d.name, 30, K.danger, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); W.box(Wd / 2 - 460, 198, 920, 26, { bg = K.lo, alpha = 210, border = K.hi, bw = 3 }); W.rect(Wd / 2 - 457, 201, 914 * clamp(r.boss.hp / r.boss.max, 0, 1), 20, K.danger)
    end
    if r.bannerT > 0 and not GameUI.ModalOpen() then W.title(Wd / 2, 250, r.banner, 60, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, nil) end
    local n = r.nearNode
    if n then W.text(Wd / 2, 956, n.info.name .. "　" .. ((n.type == "derelict" and n.state == "active") and ("搜刮中 " .. math.floor(n.progress * 100 + 0.5) .. "%") or ((n.type == "gate" and n.state ~= "open") and ("先完成本星域目标：" .. tostring(r.objective)) or tostring(n.info.hint))), 28, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end
    if u.tut then
        W.box(Wd / 2 - 520, 790, 1040, 90, { bg = K.lo, alpha = 235, border = K.teal, bw = 3 }); W.tag("新手引导 " .. u.tut.n .. " / " .. u.tut.total, Wd / 2 - 90, 780, 180, 30, K.teal, K.ink, 20)
        W.text(Wd / 2, 824, u.tut.text, 26, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    end
    -- 驾驶员卡片（头像 + 支援技能冷却 + 等级）
    local cop = C:char(r.pilot); local st = S:supportStat()
    W.panel(pad, 905, 300, 108, { alpha = 235 }); W.pix(UI.CatIcon(r.pilot), pad + 14, 917, 80, nil, 255, true)
    W.text(pad + 92, 915, cop.name, 28, K.bone); W.text(pad + 284, 917, "Lv " .. st.lv, 20, K.muted, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    W.text(pad + 92, 946, r.match and "专属 +20%" or "驾驶员", 18, K.teal); W.text(pad + 92, 968, cop.support.name, 18, K.teal)
    W.rect(pad + 92, 996, 184, 8, K.lo, 220); W.rect(pad + 92, 996, 184 * clamp(1 - r.supportCd / (cop.support.cd * st.cd), 0, 1), 8, K.teal)
    -- 机甲技能 / 氮气 / 暂停
    local ready = r.activeCd <= 0
    local bx, by = Wd - 36 - 230, 1080 - 30 - 230
    W.rect(bx, by, 230, 230, { 20, 26, 60 }, 240); W.box(bx, by, 230, 230, { bg = { 0, 0, 0 }, alpha = 0, border = (r.nitroT > 0) and K.teal or (ready and K.amber or K.hi), bw = 6 })
    W.pix(UI.CatIcon(r.mech), bx + 70, by + 14, 150, nil, ready and 255 or 120, true)
    W.text(bx + 115, by + 175, ready and m.active.name or tostring(math.ceil(r.activeCd)), ready and 28 or 52, ready and K.bone or K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, ready and 255 or 230)
    if not ready then W.rect(bx + 6, by + 218, 218 * clamp(1 - r.activeCd / S:activeCdMax(), 0, 1), 8, K.amber) end
    if W.hit(bx, by, 230, 230) then S:castActive() end
    local N = S:nitroOf(); local dgReady = r.dodgeCd <= 0; local dx0, dy0 = Wd - 36 - 250 - 140, 1080 - 40 - 140
    W.rect(dx0, dy0, 140, 140, { 20, 26, 60 }, 240); W.box(dx0, dy0, 140, 140, { bg = { 0, 0, 0 }, alpha = 0, border = dgReady and K.blue or K.hi, bw = 6 })
    W.text(dx0 + 70, dy0 + 70, dgReady and N.name or tostring(math.ceil(r.dodgeCd)), dgReady and 26 or 44, dgReady and K.bone or K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if W.hit(dx0, dy0, 140, 140) then S:dodge() end
    local ex = HOST.exitRect; local pauseX = 1502 - ((ex and ex.right and ex.right > 0.8) and 140 or 0)
    W.rect(pauseX, 60, 112, 82, K.lo, 190); W.rect(pauseX, 60, 112, 4, K.hi); W.text(pauseX + 56, 101, "暂停", 28, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    if W.hit(pauseX, 60, 112, 82) then S:openPause() end
end
local function dim(a) W.rect(0, 0, UI.lw, 1080, { 0, 0, 10 }, a or 175) end
local function drawLevelUp()
    local r, Wd = R(), UI.lw; dim(150)
    W.title(Wd / 2, 130, "升级！", 120, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, K.amber); W.text(Wd / 2, 270, "选择一项强化", 32, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local ids = u.levelup.ids; local cw, gap = 441, 28; local x0 = (Wd - (ids.length * cw + (ids.length - 1) * gap)) / 2
    for i = 0, ids.length - 1 do
        local id = ids[i]; local info = S:choiceInfo(id); local x, y = x0 + i * (cw + gap), 324
        local accent = info.evo and K.amber or (info.crew and K.teal or K.hi)
        W.rect(x, y, cw, 498, { 22, 28, 70 }, 250); W.rect(x, y, cw, 6, accent); W.rect(x, y + 490, cw, 8, accent)
        if info.evo then W.box(x, y, cw, 498, { bg = { 0, 0, 0 }, alpha = 0, border = K.amber, bw = 4 }) end
        W.tag(info.tag, x + cw / 2 - 90, y + 24, 180, 36, accent, info.crew and K.ink or K.bone, 22)
        W.pix(choiceIcon(id), x + cw / 2 - 60, y + 86, 120, nil, 255, true)
        W.title(x + cw / 2, y + 242, info.name, 40, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        W.wrap(x + 30, y + 312, cw - 60, info.text, 24, K.bone, 1.5)
        if W.hit(x, y, cw, 498) then S:applyChoice(id); GameUI.finishLevel() end
    end
    local free = r.rr.free > 0; local left = free and 0 or math.max(0, 2 - r.rr.ad)
    local label = free and "刷新选项（免费 1 次）" or (left > 0 and ("看广告 刷新选项（还可 " .. left .. " 次）") or "刷新次数已用完")
    if W.btn(572, 846, 389, 96, label, { size = 26, disabled = (not free) and left <= 0, teal = not free and left > 0 }) then
        if free then r.rr.free = r.rr.free - 1; C:sfx("click"); u.levelup.ids = S:choices()
        elseif r.rr.ad < 2 then C:showAd("刷新升级选项", function(_, res) if not res.success then GameUI.Toast("需要完整看完广告才能刷新") return end r.rr.ad = r.rr.ad + 1; C:sfx("click"); u.levelup.ids = S:choices() end) end
    end
    if W.btn(975, 846, 372, 96, "跳过，回复 30% 耐久", { size = 26 }) then r.hull = math.min(S:hullMax(), r.hull + S:hullMax() * 0.3); GameUI.Toast("跳过：回复 30% 耐久"); GameUI.finishLevel() end
end
local function drawShop()
    local r, Wd = R(), UI.lw; dim(); W.panel(Wd / 2 - 600, 220, 1200, 600, { alpha = 248 })
    W.title(Wd / 2, 236, "流浪商人", 64, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, K.amber); W.text(Wd / 2, 320, "用本局收集的信用点交易。当前：" .. math.floor(r.credits), 28, K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    for i, o in ipairs(u.shop.offers) do
        local x = Wd / 2 - 560 + (i - 1) * 380
        W.panel(x, 380, 360, 300, { alpha = 235 }); W.text(x + 180, 404, o.name, 36, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); W.text(x + 180, 464, o.text, 26, K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if W.btn(x + 30, 586, 300, 74, o.cost .. " 信用点", { size = 28, primary = r.credits >= o.cost, disabled = r.credits < o.cost }) then r.credits = r.credits - o.cost; o.go(); GameUI.Toast("购买了 " .. o.name); S:openShop() end
    end
    if W.btn(Wd / 2 - 150, 714, 300, 70, "离开", { size = 30 }) then u.shop = nil; S.paused = false end
end
local function drawPause()
    local Wd = UI.lw; dim(); W.panel(Wd / 2 - 560, 200, 1120, 640, { alpha = 248 }); W.title(Wd / 2, 220, "暂停", 76, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, K.amber)
    W.wrap(Wd / 2 - 500, 330, 1000, "左半屏拖动飞行（朝镜头方向），右半屏拖动转视角；武器自动锁定开火。右下大按钮释放机甲技能（电脑空格），小按钮氮气推进（电脑 Shift，每台机甲氮气形态不同）。电脑：WASD 飞行，R/F 升降，方向键转视角。每个星域完成箭头指向的目标，星门就会开启。闯过 6 个星域、击败首领即可通关。", 28, K.bone, 1.55)
    if W.btn(Wd / 2 - 440, 690, 420, 96, "继续", { primary = true, size = 36 }) then u.pause = nil; S.paused = false end
    if W.btn(Wd / 2 + 20, 690, 420, 96, "撤退返回", { size = 34 }) then u.pause = nil; S:endRun(false, true) end
end
local function drawRevive()
    local r, Wd = R(), UI.lw; dim(); W.panel(Wd / 2 - 480, 280, 960, 460, { alpha = 248 }); W.title(Wd / 2, 300, "机甲被击毁", 68, K.danger, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    W.text(Wd / 2, 410, "看一段广告可以原地复活（耐久 50%），每局限一次。", 30, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if not r.adRevived then
        if W.btn(Wd / 2 - 440, 560, 420, 100, "看广告复活", { teal = true, size = 32 }) then
            C:showAd("复活机甲", function(_, res)
                if not res.success then GameUI.Toast("需要完整看完广告才能复活") return end
                u.revive = nil; r.adRevived = true; r.over = false; S.paused = false; r.hull = S:hullMax() * 0.5; r.iframe = 2; S:nova(S:P(), 14, 60, "#5CF2DC"); S:banner("复活！")
            end)
        end
    end
    if W.btn(Wd / 2 + 20, 560, 420, 100, "结束远征", { size = 32 }) then u.revive = nil; S:endRun(false) end
end
local function drawResult()
    local r, Wd = R(), UI.lw; local rs = r.result; local s = C.save; dim(170); W.panel(471, 138, 976, 798, { alpha = 250 })
    local title = r.daily and (rs.win and "每日挑战完成" or "每日挑战结束") or r.endless and "无尽模式结束" or rs.win and "远征成功" or rs.retreat and "已撤退返回" or "远征失败"
    W.title(526, 170, title, 86, rs.win and K.amber or K.danger, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, nil)
    local reach = r.daily and ("得分 " .. rs.dcScore) or r.endless and ("第 " .. r.wave .. " 波") or rs.win and "通关" or (r.sector .. " / " .. S.SECTORS)
    local row1 = { { "到达", reach }, { "用时", mmss(r.t) }, { "击破", tostring(r.kills) }, { "信用点", "+" .. rs.credits }, { "星源", "+" .. rs.src } }
    local xs1 = { 526, 727, 951, 1104, 1316 }
    for i, row in ipairs(row1) do W.text(xs1[i], 322, row[1], 22, K.muted); W.text(xs1[i], 352, row[2], 52, K.bone) end
    local row2 = { { "本局等级", "Lv " .. r.level }, { "最高连击", tostring(r.bestCombo or 0) }, { "造成伤害", tostring(math.floor((r.dmgDealt or 0) + 0.5)) }, { "承受伤害", tostring(math.floor((r.dmgTaken or 0) + 0.5)) } }
    local xs2 = { 526, 783, 1040, 1298 }
    for i, row in ipairs(row2) do W.text(xs2[i], 440, row[1], 22, K.muted); W.text(xs2[i], 470, row[2], 52, K.bone) end
    local ny = 584
    local function note(t, c) W.text(526, ny, t, 26, c or K.bone); ny = ny + 52 end
    if rs.achNow and rs.achNow > 0 then note("有 " .. rs.achNow .. " 个成就可以领取，去“每日”页领取星源。") end
    if rs.first then note("首次通关奖励：星源 +" .. r.ch.first .. (C.CHAPTERS.length > r.ch.id and ("。第 " .. (r.ch.id + 1) .. " 章已解锁。") or "。")) end
    if rs.dgUnlock then note("危险等级 " .. s.dangerMax .. " 已解锁（奖励更高，敌人更强）。", K.amber) end
    if r.endless and not r.daily then note("无尽最高纪录：第 " .. s.endlessBest .. " 波。") end
    if r.daily then note("今日最高分 " .. C:dailyChallenge().state.best .. (rs.dcFirst and "。首次完成奖励已发放。" or "。今日奖励已领取。")) end
    if not rs.win and not rs.retreat and not r.endless then note("远征失败只带回 70% 信用点。", K.muted) end
    if rs.fragTxt and rs.fragTxt ~= "" then note(rs.fragTxt, K.teal) end
    if W.btn(525, 820, 277, 104, rs.doubled and "已翻倍" or "看广告 信用点翻倍", { teal = not rs.doubled, size = 26, disabled = rs.doubled }) then
        C:showAd("结算奖励翻倍", function(_, res) if not res.success then GameUI.Toast("需要完整看完广告才能领取") return end s.credits = s.credits + rs.credits; C:write(); rs.doubled = true; GameUI.Toast("信用点再 +" .. rs.credits) end)
    end
    if W.btn(822, 820, 277, 104, "分享战绩", { size = 28 }) then
        local tx = "我在《宇宙银河机甲》" .. (r.daily and ("每日挑战拿到了 " .. rs.dcScore .. " 分") or r.endless and ("无尽模式撑到了第 " .. r.wave .. " 波") or rs.win and ("通关了第 " .. r.ch.id .. " 章") or ("闯到了星域 " .. r.sector)) .. "！用 " .. C:mech(r.mech).name .. "击破 " .. r.kills .. " 个敌人。来挑战我吧！"
        if HOST.onShare then HOST.onShare(tx) end; GameUI.Toast("战绩：" .. tx)
    end
    if W.btn(1118, 820, 278, 104, "返回机库", { primary = true, size = 32 }) then S.R = nil; GameUI.Reset(); if GameUI.onHome then GameUI.onHome() end end
end
function GameUI.DrawModals()
    local r = R(); if not r then return end
    W.block = false
    if r.ended and r.result then drawResult()
    elseif u.levelup then drawLevelUp()
    elseif u.shop then drawShop()
    elseif u.revive then drawRevive()
    elseif u.pause then drawPause() end
    GameUI.DrawToast()
end
-- ---------------------------------------------------------------- 输入（对应 bindPointer / keydown）
local KEYMAP = { KeyW = KEY_W, KeyA = KEY_A, KeyS = KEY_S, KeyD = KEY_D, KeyR = KEY_R, KeyF = KEY_F, ArrowLeft = KEY_LEFT, ArrowRight = KEY_RIGHT, ArrowUp = KEY_UP, ArrowDown = KEY_DOWN }
function GameUI.Input(W, H, viewS)
    local r = R(); if not r or GameUI.ModalOpen() then return end
    local joy, look, keys = S.joy, S.look, S.keys
    for _, t in ipairs(UI.taps) do
        if not t.used then
            if t.px < W * 0.5 and joy.id == nil then joy.id = t.id; joy.cx = t.px; joy.cy = t.py; joy.dx = 0; joy.dy = 0; t.used = true
            elseif look.id == nil then look.id = t.id; look.x = t.px; look.y = t.py; look.idle = 0; t.used = true end
        end
    end
    for id, st in pairs(UI.ptr) do
        if id == joy.id then
            local R0 = 60 * math.max(0.55, viewS * 1.5); local dx, dy = st.px - joy.cx, st.py - joy.cy; local l = math.sqrt(dx * dx + dy * dy)
            if l > R0 then dx = dx / l * R0; dy = dy / l * R0 end
            joy.dx = dx / R0; joy.dy = -dy / R0
        elseif id == look.id then
            local k = 0.32 / math.max(0.3, viewS * 1.5)
            r.camYaw = r.camYaw + (st.px - look.x) * k; r.camPitch = clamp(r.camPitch + (st.py - look.y) * k, -70, 70); look.x = st.px; look.y = st.py; look.idle = 0
        end
    end
    for _, st in ipairs(UI.released) do
        if st.id == joy.id then joy.id = nil; joy.dx = 0; joy.dy = 0 end
        if st.id == look.id then look.id = nil; look.idle = 0 end
    end
    for code, k in pairs(KEYMAP) do keys[code] = input:GetKeyDown(k) or nil end
    if input:GetKeyPress(KEY_SPACE) then S:castActive() end
    if input:GetKeyPress(KEY_SHIFT) then S:dodge() end
    if input:GetKeyPress(KEY_ESCAPE) and not r.ended then S:openPause() end
end
function GameUI.DrawToast() if GameUI.toast and GameUI.toast.t > 0 then local W2 = require("cosmic.WebUI"); W2.box(UI.lw / 2 - 380, 150, 760, 60, { bg = W2.C.lo, alpha = 235, border = W2.C.teal, bw = 3 }); W2.text(UI.lw / 2, 164, GameUI.toast.text, 28, W2.C.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end end
function GameUI.Update(dt) if GameUI.toast then GameUI.toast.t = GameUI.toast.t - dt end end
return GameUI
