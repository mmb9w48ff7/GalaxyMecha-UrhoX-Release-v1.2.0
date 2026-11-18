-- Hub.lua：机库（出击 / 机库 / 驾驶员 / 工坊 / 召唤 / 每日 / 设置 / 关于）。
-- 版面、配色、控件样式、坐标均取自网页版 cosmic_hub.js + index.template.html 在 1920x1080 下的真实渲染（用浏览器导出每个元素的位置与样式）；
-- 网页版是 HTML + CSS，这里用 NanoVG 绘制（WebUI.lua 提供与网页版 CSS 一致的面板 / 按钮 / 导航 / 资源条 / 属性条 / 星级 / 像素图标 / 滚动区域）。
-- 每个按钮的处理逻辑与 cosmic_hub.js 里的 onclick 逐条对应，所有数据与规则（抽取、费用、保底、成就、每日挑战……）直接调用由网页版转换来的 C。
local U = require("cosmic.Util")
local UI = require("cosmic.UI")
local W = require("cosmic.WebUI")
local Hub = { tab = "home", wsub = "mods", banner = "mech", chapterSel = 1, dangerSel = 1, wk = { form = "homing", elem = "light", tier = 0, v = 0 }, modal = nil, results = nil, t = 0 }
local C, HOST
local K, GRADE = W.C, W.GRADE
local ORDER = { S = 0, SS = 1, SSR = 2, SSSR = 3 }
local TIERC = { { 230, 234, 245 }, { 87, 184, 255 }, { 180, 124, 255 }, { 245, 165, 36 } }
local drawSummonAnim
local function toast(m) if HOST.onToast then HOST.onToast(m) end end
local function sv() return C.save end
local function list(a) local t = {}; if a then for i = 0, a.length - 1 do t[#t + 1] = a[i] end end return t end
local function find(a, f) for i = 0, a.length - 1 do if f(a[i]) then return a[i], i end end return nil end
local function has(a, id) for i = 0, a.length - 1 do if a[i] == id then return i end end return nil end
local function fmt(n) return tostring(math.floor(n + 0.5)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "") end
local function save() C:write() end
function Hub.Init(cosmic, host)
    C, HOST = cosmic, host; Hub.chapterSel = math.min(sv().chapter, C.CHAPTERS.length); Hub.dangerSel = 1
end
local function sortG(arr)
    local t = list(arr); local s = sv()
    local function own(x) return (arr == C.MECHS and s.mechs[x.id] or (arr ~= C.MECHS and s.chars[x.id])) and 1 or 0 end
    table.sort(t, function(a, b) if ORDER[a.grade] ~= ORDER[b.grade] then return ORDER[a.grade] > ORDER[b.grade] end return own(a) > own(b) end)
    return t
end
local function mechPower(id) local m, k = C:mech(id), C:mechMul(id); return { hp = m.hp * k, fire = m.fire * 20 * k, spd = m.spd * 6 } end
local function mechUpgradable() local s = sv(); for _, m in ipairs(list(C.MECHS)) do if s.mechs[m.id] then local lv = C:mechLv(m.id); local st = C:mechStar(m.id)
    if (lv < C.MECH_MAX and s.credits >= C:mechCost(lv)) or (st < 5 and (s.frags[m.id] or 0) >= C.STAR_FRAGS[st]) then return true end end end return false end
local function pilotUpgradable() local s = sv(); for _, c in ipairs(list(C.CHARS)) do local o = s.chars[c.id]; if o and o.star < 5 and (s.frags[c.id] or 0) >= (C.STAR_FRAGS[o.star] or 10) then return true end end return false end
local function dailyClaimable()
    local s = sv(); if not s.daily.supply or s.daily.supply == 0 then return true end
    if not C:loginState().claimed then return true end
    if C:achReady() > 0 then return true end
    for _, t in ipairs(list(C.TASKS)) do if (s.daily[t.key] or 0) >= t.need and not s.daily.claimed[t.id] then return true end end
    return false
end
local function nextSteps()
    local s, out = sv(), {}; local cards, eqN = s.modules.length, s.modEq.length
    if (s.runs or 0) == 0 and not s.best[1] then out[#out + 1] = { go = "home", t = "出击第 1 章", d = "跟着新手引导飞一圈，赚信用点和星源" } end
    if cards < 3 or eqN < 3 then out[#out + 1] = { go = "work", t = "去工坊抽技能卡牌", d = "装备 3 张卡牌，出击时全部生效（现有 " .. cards .. " 张，已装备 " .. eqN .. " / 3）" } end
    if s.credits >= C:MOD_COST(s.modBuys or 0) and cards >= 3 then out[#out + 1] = { go = "work", t = "信用点够抽卡了", d = "再抽一张：重复抽到会升级卡牌，抽到金卡有专属特效" } end
    local nc = C.CHAPTERS[math.min(C.CHAPTERS.length, s.chapter) - 1]
    if nc and C:power() < nc.rec * 0.9 then table.insert(out, 1, { go = "hangar", t = "战力不足（" .. C:power() .. " / 推荐 " .. nc.rec .. "）", d = "先升级机甲等级 / 星级，再装备卡牌与芯片" }) end
    if mechUpgradable() then out[#out + 1] = { go = "hangar", t = "机甲可以升级", d = "到机库提升等级或星级，耐久与火力一起变强" } end
    if pilotUpgradable() then out[#out + 1] = { go = "pilots", t = "驾驶员可以升星", d = "碎片足够了，升星提高支援技能" } end
    if dailyClaimable() then out[#out + 1] = { go = "daily", t = "每日有奖励可领", d = "补给、任务和巡航收益" } end
    if s.chips.length < 3 then out[#out + 1] = { go = "work", t = "研发天赋芯片", d = "芯片属性永久生效，凑齐同系列有额外效果" } end
    local r = {}; for i = 1, math.min(3, #out) do r[i] = out[i] end return r
end

-- ---------------------------------------------------------------- 公共：顶栏 / 导航
local function resChips(y, x0)
    local s = sv()
    W.res(x0, y, 190, 69, "credit", fmt(s.credits)); W.res(x0 + 202, y, 190, 69, "shard", fmt(s.src))
    if W.btn(x0 + 202 + 160, y + 13, 44, 44, "+", { teal = true, size = 34 }) then Hub.modal = "getsrc"; C:sfx("click") end
end
local function topbar()
    local s = sv(); local cleared = 0; for _ in pairs(s.cleared) do cleared = cleared + 1 end
    W.box(36, 18, 253, 100, { bg = K.lo, alpha = 200, border = K.lo, bw = 0, left = K.amber })
    W.pix(UI.CatIcon("char_captain"), 52, 31, 74, nil, 255, true)
    W.text(118, 32, "舰长 罗汉", 30, K.bone); W.text(118, 74, "已通关 " .. cleared .. " / " .. C.CHAPTERS.length .. " 章", 22, K.muted)
    W.title(960, 8, "宇宙银河机甲", 70, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, K.amber); W.text(960, 94, "VOXEL MECHA", 22, K.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, 255, 12)
    resChips(33, 1180)
    if W.btn(1594, 35, 100, 66, "设置", { flat = true, size = 30 }) then Hub.modal = "settings"; C:sfx("click") end
end
local TABS = { { "home", "出击", "go" }, { "hangar", "机库", "mech" }, { "pilots", "驾驶员", "pilot" }, { "work", "工坊", "work" }, { "summon", "召唤", "summon" }, { "daily", "每日", "daily" } }
local function nav()
    W.box(529, 936, 862, 128, { bg = K.lo, alpha = 225 })
    local dots = { hangar = mechUpgradable(), pilots = pilotUpgradable(), daily = dailyClaimable(), work = false, summon = false, home = false }
    for i, t in ipairs(TABS) do
        local on = Hub.tab == t[1]; local x, y, w, h = 537 + (i - 1) * 142, on and 934 or 944, 136, on and 124 or 112
        if on then W.rect(x, y, w, h, K.amber); W.rect(x, y, w, 5, K.amberHi); W.rect(x, y + h - 8, w, 8, K.amberLo) end
        W.navIcon(t[3], x + 40, y + 8, 56, on and K.ink or K.muted, on and K.ink or K.teal)
        W.text(x + w / 2, y + 66, t[2], 28, on and K.ink or K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if dots[t[1]] then W.rect(x + w - 26, y + 10, 16, 16, K.danger) end
        if W.hit(x, y, w, h) then C:sfx("click"); Hub.tab = t[1]; Hub.mechSel = nil; Hub.pilotSel = nil; Hub.wsel = nil end
    end
end
local function frameTop(title, sub)                       -- .mk-ftop：返回 + 标题 + 资源（工坊 / 每日页）
    W.panel(36, 16, 1848, 108, { alpha = 235 })
    if W.btn(60, 32, 140, 76, "‹ 返回", { size = 30 }) then C:sfx("click"); Hub.tab = "home" end
    W.title(224, 16, title, 56, K.amber, NVG_ALIGN_LEFT + NVG_ALIGN_TOP); W.text(224, 82, sub, 22, K.muted)
    resChips(36, 1272)
end
local function body() W.rect(36, 138, 1848, 918, K.lo, 150); W.box(36, 138, 1848, 918, { bg = K.lo, alpha = 0, border = K.hi, bw = 3 }) end

-- ---------------------------------------------------------------- 出击
local function mechCard(x, y, w, h, id)
    local m = C:mech(id); local pw = mechPower(id)
    W.panel(x, y, w, h); W.badge(m.grade, x + 26, y + 18, 48, 46, 30); W.tag(m.type, x + 84, y + 21, 110, 40, K.hi, K.bone, 24)
    W.title(x + 204, y + 12, m.name, 46, K.bone, NVG_ALIGN_LEFT + NVG_ALIGN_TOP); W.text(x + w - 28, y + 32, "Lv " .. C:mechLv(id), 26, K.amber, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    W.stars(C:mechStar(id), x + 26, y + 76, 20)
    W.stat("耐久", pw.hp, 260, K.hp, x + 26, y + 96, w - 52); W.stat("火力", pw.fire, 190, K.amber, x + 26, y + 141, w - 52); W.stat("机动", pw.spd, 100, K.blue, x + 26, y + 186, w - 52)
    W.text(x + 26, y + h - 42, m.weapon.name .. "，技能 " .. m.active.name, 22, K.muted)
end
local function pilotCard(x, y, w, h, id)
    local p = C:char(id); local s = sv(); local own = s.chars[id]
    W.panel(x, y, w, h); W.box(x + 20, y + 22, 100, 150, { bg = K.lo, alpha = 150, border = K.lo, bw = 0 }); W.pix(UI.CatIcon(id), x + 26, y + 26, 142, nil, 255, true)
    W.badge(p.grade, x + 122, y + 20, 48, 46, 30); W.title(x + 180, y + 12, p.name, 46, K.bone, NVG_ALIGN_LEFT + NVG_ALIGN_TOP); W.text(x + 190 + #p.name * 18 + 60, y + 30, p.role, 26, K.amber)
    if own then W.stars(own.star, x + 122, y + 76, 20) end
    W.wrap(x + 122, y + 100, w - 146, p.support.name .. "：" .. p.support.desc, 20, K.bone, 1.3)
    W.text(x + 122, y + 164, "被动：" .. p.passive.name, 20, K.bone)
    local m = C:mech(p.mech); local match = s.mech == p.mech
    W.tag("专属机甲 耐久与火力 +20%", x + 122, y + h - 44, 330, 32, match and K.teal or K.hi, match and K.ink or K.muted, 21)
end
local function homeView()
    local W_, s = UI.lw, sv(); topbar()
    W.text(36, 134, "出战机甲", 22, K.teal)
    mechCard(36, 177, 520, 282, s.mech)
    W.text(36, 474, "驾驶员", 22, K.teal)
    pilotCard(36, 516, 520, 242, s.pilot)
    if W.btn(36, 768, 254, 64, "更换机甲", { size = 28 }) then C:sfx("click"); Hub.tab = "hangar" end
    if W.btn(302, 768, 254, 64, "更换驾驶员", { size = 28 }) then C:sfx("click"); Hub.tab = "pilots" end
    local steps = nextSteps()
    if #steps > 0 then W.text(36, 846, "推荐下一步", 22, K.teal) end
    for i, t in ipairs(steps) do local y = 876 + (i - 1) * 70
        W.box(36, y, 520, 64, { bg = { 14, 18, 44 }, alpha = 225, border = K.lo, bw = 0, left = K.teal }); W.text(54, y + 6, t.t, 24, K.bone); W.text(54, y + 38, t.d, 18, K.muted)
        if W.hit(36, y, 520, 64) then C:sfx("click"); Hub.tab = t.go end end
    -- 章节 / 危险等级 / 出击
    local ch = C.CHAPTERS[Hub.chapterSel - 1]; local locked = Hub.chapterSel > s.chapter; local pwr = C:power()
    W.panel(1344, 378, 540, 369); W.rect(1344, 380, 5, 365, K.amber)
    if W.btn(1352, 396, 54, 99, "‹", { flat = true, size = 40 }) then C:sfx("click"); Hub.chapterSel = math.max(1, Hub.chapterSel - 1) end
    if W.btn(1822, 396, 54, 99, "›", { flat = true, size = 40 }) then C:sfx("click"); Hub.chapterSel = math.min(C.CHAPTERS.length, Hub.chapterSel + 1) end
    W.text(1614, 400, "第 " .. ch.id .. " 章", 22, K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); W.title(1614, 424, ch.name, 62, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    W.wrap(1370, 508, 494, ch.desc, 24, K.bone, 1.5)
    for i = 1, 6 do local sc = (i == 6) and K.danger or (s.best[ch.id] and s.best[ch.id] >= i and K.teal or K.hi); W.rect(1370 + (i - 1) * 83, 580, 77, 8, sc, i == 3 and 255 or 220) end
    local pcol = pwr >= ch.rec and { 124, 242, 154 } or (pwr >= ch.rec * 0.8 and K.amber or K.danger)
    W.rect(1370, 604, 4, 92, K.teal); W.text(1388, 606, "推荐战力 " .. ch.rec, 24, K.muted); W.text(1864, 604, "你的战力 " .. pwr, 30, pcol, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    W.text(1388, 654, pwr / ch.rec >= 1.15 and "战力充足，可以放心挑战" or pwr / ch.rec >= 1 and "战力达标" or pwr / ch.rec >= 0.8 and "略显吃力，建议先升级机甲或装备卡牌" or "战力不足，建议先去机库 / 工坊变强", 22, pcol)
    W.text(1370, 706, "首领 " .. ch.bossName, 24, K.bone); W.text(1864, 706, (s.cleared[ch.id] and "已通关" or (locked and "未解锁" or "")), 24, K.muted, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
    local dm = s.dangerMax or 1; Hub.dangerSel = math.max(1, math.min(dm, Hub.dangerSel))
    W.panel(1344, 767, 540, 74, { alpha = 200, flat = true })
    if W.btn(1352, 771, 54, 66, "‹", { flat = true, size = 34, disabled = Hub.dangerSel <= 1 }) then C:sfx("click"); Hub.dangerSel = Hub.dangerSel - 1 end
    if W.btn(1822, 771, 54, 66, "›", { flat = true, size = 34, disabled = Hub.dangerSel >= dm }) then C:sfx("click"); Hub.dangerSel = Hub.dangerSel + 1 end
    W.text(1614, 770, "危险等级 " .. Hub.dangerSel, 32, { 255, 138, 58 }, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    W.text(1614, 812, "敌人血量 +" .. 12 * (Hub.dangerSel - 1) .. "%　伤害 +" .. 8 * (Hub.dangerSel - 1) .. "%　奖励 +" .. 15 * (Hub.dangerSel - 1) .. "%", 20, K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if W.btn(1344, 857, 540, 89, locked and "通关上一章解锁" or "出  击", { primary = true, size = 56, sub = locked and nil or "6 个星域，约 6 分钟", subSize = 22, disabled = locked }) then C:sfx("gate"); Hub.onStart(Hub.chapterSel, { danger = Hub.dangerSel }) end
    local endOk = s.cleared[1] and true or false
    W.rect(1344, 966, 540, 74, { 60, 38, 100 }, endOk and 255 or 140); W.rect(1344, 966, 6, 74, GRADE.SS)
    W.text(1366, 972, "无尽模式", 30, K.bone, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, endOk and 255 or 150); W.text(1366, 1010, endOk and ("最高纪录：第 " .. (s.endlessBest or 0) .. " 波") or "通关第 1 章解锁", 22, K.muted)
    if endOk and W.hit(1344, 966, 540, 74) then C:sfx("gate"); Hub.onStart(Hub.chapterSel <= s.chapter and Hub.chapterSel or 1, { danger = Hub.dangerSel, endless = true }) end
end

-- ---------------------------------------------------------------- 机库 / 驾驶员
local function listCol(arr, selId, isMech)
    local s = sv(); local items = sortG(arr)
    for i, x in ipairs(items) do
        local own = isMech and s.mechs[x.id] or (not isMech and s.chars[x.id]); local y = 128 + (i - 1) * 100; local gc = GRADE[x.grade]; local a = own and 255 or 150
        W.rect(36, y, 300, 92, { 14, 18, 44 }, own and 225 or 170); W.rect(36, y, 5, 92, gc, a)
        if selId == x.id then W.box(36, y, 300, 92, { bg = { 0, 0, 0 }, alpha = 0, border = K.teal, bw = 3 }) end
        W.pix(UI.CatIcon(x.id), 50, y + 10, 72, nil, a, true)
        W.text(124, y + 12, x.name, 30, own and K.bone or K.muted, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, a)
        W.text(124, y + 54, own and (isMech and ("Lv " .. C:mechLv(x.id) .. " · " .. C:mechStar(x.id) .. " 星") or (x.role .. " · " .. own.star .. " 星")) or "召唤获得", 21, K.muted, NVG_ALIGN_LEFT + NVG_ALIGN_TOP, a)
        W.badge(x.grade, 258, y + 32, 68, 28, 20)
        if own and ((isMech and s.mech == x.id) or (not isMech and s.pilot == x.id)) then W.tag("出战", 42, y + 4, 44, 24, K.amber, K.ink, 14) end
        if W.hit(36, y, 300, 92) then C:sfx("click"); if isMech then Hub.mechSel = x.id else Hub.pilotSel = x.id end end
    end
end
local function plate(grade, name, sub, stars)                -- .mk-plate：展台下方的名牌
    W.badge(grade, 780, 744, 60, 30, 20); W.title(810, 774, name, 56, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); W.text(810, 842, sub, 22, K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    W.stars(stars, 760, 872, 19); W.text(810, 902, "自动旋转展示", 18, K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, 200)
end
local function dl(x, y, w, dt, dd, text)                     -- .dl：小标题 / 名称 / 说明（返回下一块的 y）
    W.text(x, y, dt, 20, K.muted); W.text(x, y + 24, dd, 28, K.bone)
    if not text then return y + 66 end
    W.wrap(x, y + 58, w, text, 21, K.muted, 1.3); return y + 58 + W.lines(text, w, 21) * 27 + 12
end
local function hangarView()
    local s = sv(); local id = Hub.mechSel or s.mech; local m = C:mech(id); local own = C:ownsMech(id); local lv = C:mechLv(id); local pw = mechPower(id)
    local aw = lv >= C.MECH_AWAKE; local cost = C:mechCost(lv); local max = lv >= C.MECH_MAX; local st = C:mechStar(id); local frags = s.frags[id] or 0; local need = st >= 5 and 0 or C.STAR_FRAGS[st]; local pilot = C:char(m.match)
    topbar(); listCol(C.MECHS, id, true); plate(m.grade, m.name, m.type, own and st or 0)
    local gc = GRADE[m.grade]; W.panel(1284, 128, 600, 802, { accent = gc })
    W.badge(m.grade, 1308, 150, 54, 50, 32); W.title(1376, 140, m.name, 60, K.bone, NVG_ALIGN_LEFT + NVG_ALIGN_TOP); W.text(1376, 212, m.type .. " · " .. (own and ("Lv " .. lv .. (aw and " · 已觉醒" or "")) or "未获得"), 22, K.muted)
    W.stat("耐久", pw.hp, 260, K.hp, 1308, 255, 552); W.stat("火力", pw.fire, 190, K.amber, 1308, 300, 552); W.stat("机动", pw.spd, 100, K.blue, 1308, 345, 552)
    local y = dl(1308, 396, 552, "主武器", m.weapon.name, m.weapon.desc)
    y = dl(1308, y, 552, "机甲技能 · 冷却 " .. m.active.cd .. " 秒", m.active.name, m.active.desc .. "。" .. m.active.awake)
    dl(1308, y, 552, "专属驾驶员", pilot.name, (s.chars[pilot.id] and "已拥有，" or "未获得，") .. "搭配时耐久与火力 +20%")
    if own then
        if W.btn(1308, 751, 271, 90, max and "已满级" or ("升级  " .. fmt(cost)), { primary = true, size = 30, disabled = max }) then
            if s.credits < cost then toast("信用点不足：去出击赚取，或在每日里领巡航收益") else s.credits = s.credits - cost; s.mechs[id].lv = lv + 1; save(); C:sfx("level"); toast(m.name .. " 升到 Lv " .. (lv + 1) .. ((lv + 1 == C.MECH_AWAKE) and "，技能觉醒！" or "")) end end
        if W.btn(1589, 751, 271, 90, st >= 5 and "已满星" or ("升星（碎片 " .. frags .. "/" .. need .. "）"), { size = 26, disabled = st >= 5 or frags < need }) then s.frags[id] = frags - need; s.mechs[id].star = st + 1; save(); C:sfx("win"); toast(m.name .. " 升到 " .. (st + 1) .. " 星") end
        if id ~= s.mech and W.btn(1308, 851, 552, 60, "设为出战机甲", { size = 28 }) then s.mech = id; save(); C:sfx("click"); toast("出战机甲：" .. m.name) end
    elseif W.btn(1308, 751, 552, 90, "前往机甲召唤", { primary = true, size = 32 }) then Hub.tab = "summon"; Hub.banner = "mech" end
end
local function pilotsView()
    local s = sv(); local id = Hub.pilotSel or s.pilot; local c = C:char(id); local own = s.chars[id]; local st = own and own.star or 0
    local frags = s.frags[id] or 0; local need = st >= 5 and 0 or (C.STAR_FRAGS[st] or 10)
    topbar(); listCol(C.CHARS, id, false); plate(c.grade, c.name, c.role, st)
    W.panel(1284, 128, 600, 802, { accent = GRADE[c.grade] })
    W.badge(c.grade, 1308, 150, 54, 50, 32); W.title(1376, 140, c.name, 60, K.bone, NVG_ALIGN_LEFT + NVG_ALIGN_TOP); W.text(1376, 212, c.role .. (own and (" · " .. st .. " 星") or " · 未获得"), 22, K.muted)
    local y = dl(1308, 257, 552, "支援技能 · 冷却 " .. c.support.cd .. " 秒", c.support.name, c.support.desc)
    y = dl(1308, y, 552, "被动", c.passive.name, nil)
    y = dl(1308, y, 552, "专属机甲", C:mech(c.mech).name, (C:ownsMech(c.mech) and "已拥有，" or "未获得，") .. "搭配时耐久与火力 +20%")
    dl(1308, y, 552, "当前倍率", "支援技能 x" .. string.format("%.2f", C:pilotMul(id)), c.grade .. " 级基础 x" .. C.GRADE[c.grade].mul .. "，每升 1 星 +15%")
    if own then
        if W.btn(1308, 660, 552, 90, st >= 5 and "已满星" or ("升星（碎片 " .. frags .. "/" .. need .. "）"), { primary = true, size = 28, disabled = st >= 5 or frags < need }) then s.frags[id] = frags - need; own.star = own.star + 1; save(); C:sfx("level"); toast(c.name .. " 升到 " .. own.star .. " 星") end
        if id ~= s.pilot and W.btn(1308, 770, 552, 70, "设为驾驶员", { size = 30 }) then s.pilot = id; save(); C:sfx("click"); toast("驾驶员：" .. c.name) end
    elseif W.btn(1308, 660, 552, 90, "前往驾驶员召唤", { primary = true, size = 32 }) then Hub.tab = "summon"; Hub.banner = "pilot" end
end

-- ---------------------------------------------------------------- 工坊
local function doAdUp(it, name)
    C:showAd("升级" .. name, function(_, r) if not r.success then toast("需要完整看完广告才能升级") return end local u = C:adUpgrade(it); if u.err then toast(u.err) return end C:sfx("level"); toast(name .. " 升到 Lv " .. it.lvl) end)
end
local function modsView()
    local s, wk = sv(), Hub.wk; local eq = s.modEq
    -- 右侧详情（固定）
    local card = C:makeModule(wk.tier, wk.form, wk.elem, wk.v); local own = C:modOwned(wk.form, wk.elem, wk.tier, wk.v); local F, E = C:modForm(wk.form), C:modElem(wk.elem)
    W.panel(1302, 160, 560, 669, { alpha = 235 }); W.rect(1302, 162, 5, 665, K.teal)
    W.pix(C:modIcon(card), 1328, 182, 56, nil, 255, true); W.title(1404, 174, card.name, 40, K.bone, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
    W.text(1404, 228, C.RARITY[wk.tier].n .. " · " .. (F.n), 24, K.muted); if own then W.pips(own.lvl or 1, C.LV_MAX, 1600, 234, 12) W.text(1700, 224, "Lv " .. (own.lvl or 1), 24, K.muted) end
    for t = 0, 3 do local x = 1328 + t * 130; local on = wk.tier == t
        W.rect(x, 284, 124, 56, on and { 235, 238, 248 } or { 40, 46, 84 }); if on then W.rect(x, 284, 124, 56, TIERC[t + 1], 40) end; W.text(x + 62, 312, C.RARITY[t].n:sub(1, 6), 28, on and K.ink or K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if W.hit(x, 284, 124, 56) then wk.tier = t; wk.v = 0; C:sfx("click") end end
    for v = 0, C.VARIANTS[wk.tier] - 1 do local x = 1328 + v * 148; local c2 = C:makeModule(wk.tier, wk.form, wk.elem, v); local o2 = C:modOwned(wk.form, wk.elem, wk.tier, v)
        W.rect(x, 350, 142, 52, wk.v == v and { 70, 84, 150 } or { 28, 34, 70 }); if wk.v == v then W.box(x, 350, 142, 52, { bg = { 0, 0, 0 }, alpha = 0, border = K.teal, bw = 3 }) end
        W.text(x + 71, 376, (v == 0 and "基础" or ("变体" .. v)) .. (o2 and (" Lv" .. (o2.lvl or 1)) or ""), 22, o2 and K.bone or K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
        if W.hit(x, 350, 142, 52) then wk.v = v; C:sfx("click") end end
    local ly = 416
    local function bullet(t, c) W.text(1334, ly, "•", 22, K.muted); W.wrap(1362, ly, 470, t, 21, c or K.bone, 1.35); ly = ly + 28 * W.lines(t, 470, 21) + 4 end
    bullet(C:modDesc(card)); bullet(E.d, K.teal); for _, k in ipairs(list(card.tags)) do local tg = C:modTag(k); bullet(tg.n .. "：" .. tg.d) end
    local g = C:goldTag(card); if g then bullet("金色特效：" .. g.d, K.amber) end
    if own then
        local eqd = has(eq, own.id); local lv, left = own.lvl or 1, C:adUpLeft()
        if W.btn(1328, 521, 252, 109, eqd and "卸下" or "装备", { primary = true, size = 34 }) then if eqd then eq:splice(eqd, 1) elseif eq.length >= 3 then toast("槽位已满，先卸下一个") else eq:push(own.id) end; save(); C:sfx("click") end
        if W.btn(1590, 521, 252, 109, lv >= C.LV_MAX and "已满级" or ("看广告 升到 Lv " .. math.min(C.LV_MAX, lv + 1)), { teal = true, size = 26, sub = lv >= C.LV_MAX and nil or ("今日还可 " .. left .. " 次"), disabled = lv >= C.LV_MAX or left <= 0 }) then doAdUp(own, own.name) end
    end
    if W.btn(1328, 642, 514, 109, "研发技能卡牌", { primary = true, size = 34, sub = fmt(C:MOD_COST(s.modBuys or 0)) .. " 信用点，随机抽取 " .. C:MOD_TOTAL() .. " 张之一", subSize = 22 }) then
        local r = C:buyModule(); if r.err then toast(r.err) else local it = r.mod; save(); C:sfx(it.tier >= 2 and "win" or "level"); wk.form, wk.elem, wk.tier, wk.v = it.form, it.elem, it.tier, it.v or 0
            if r.isNew and eq.length < 3 then eq:push(it.id) end; Hub.results = { kind = "card", item = it, dup = r.dup, refund = r.refund, name = it.name, tier = it.tier } end end
    W.wrap(1328, 764, 514, "品质概率：白 60%，蓝 28%，紫 10%，金 2%。每 10 次必出蓝色以上，每 40 次必出金色。重复抽到 = 卡牌 +1 级。", 18, K.muted, 1.4)
    -- 左侧主区（滚动）：汇总 / 装备槽 / 图鉴
    local top, bot = 150, 1050; local contentH = 330 + 21 * 83 + 20
    local oy, sc, mo = W.scrollBegin("codex", 58, top, 1226, bot - top, contentH)
    local y0 = oy + 10
    W.text(58, y0, "已收集 " .. s.modules.length .. " / " .. C:MOD_TOTAL() .. " 张卡牌", 34, K.teal)
    W.wrap(58, y0 + 50, 1200, "20 种形态 x 6 种元素 x 4 种品质（白 / 蓝 / 紫 / 金）x 词条变体，共 " .. C:MOD_TOTAL() .. " 张。只有抽到并装备的卡牌才会在局内出现；重复抽到会升级该卡牌。", 22, K.muted, 1.4)
    W.text(58, y0 + 140, "出击装备（3 张开局全部生效，局内升级可继续强化）", 24, K.teal)
    for i = 0, 2 do local c2 = eq[i] and find(s.modules, function(x) return x.id == eq[i] end); local x = 58 + i * 411
        W.rect(x, y0 + 180, 401, 125, { 12, 16, 40 }, 230); W.box(x, y0 + 180, 401, 125, { bg = { 0, 0, 0 }, alpha = 0, border = c2 and TIERC[c2.tier + 1] or K.hi, bw = 3 })
        if c2 then W.pix(C:modIcon(c2), x + 170, y0 + 190, 60, nil, 255, true); W.text(x + 200, y0 + 256, c2.name, 24, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); W.text(x + 200, y0 + 284, "Lv " .. (c2.lvl or 1), 18, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            if W.hit(x, y0 + 180, 401, 125, true) then local k = has(eq, c2.id); if k then eq:splice(k, 1); save(); C:sfx("click") end end
        else W.text(x + 200, y0 + 232, "空槽位", 24, K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end end
    local hy = y0 + 330
    for j, E2 in ipairs(list(C.ELEMENTS)) do W.text(214 + (j - 1) * 179 + 86, hy, E2.n, 22, K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end
    for i, F2 in ipairs(list(C.MOD_FORMS)) do
        local ry = hy + 40 + (i - 1) * 83
        if W.visible(ry, 78, top, bot) then
            W.text(58, ry + 22, F2.n, 26, K.bone)
            for j, E2 in ipairs(list(C.ELEMENTS)) do
                local x = 214 + (j - 1) * 179; local best, bestTier, any = nil, -1, false
                for _, c2 in ipairs(list(s.modules)) do if c2.form == F2.k and c2.elem == E2.k then any = true; if c2.tier > bestTier then best, bestTier = c2, c2.tier end end end
                local sel = wk.form == F2.k and wk.elem == E2.k
                W.rect(x, ry, 173, 78, { 12, 16, 40 }, any and 235 or 150)
                local ic = C:modIcon(C:makeModule(any and bestTier or 0, F2.k, E2.k, 0)); local eqd = best and has(eq, best.id)
                if any then W.pix(ic, x + 68, ry + 8, 38, nil, 255, true) else W.pix(ic, x + 68, ry + 8, 38, { 90, 96, 125 }, 140, true) end
                if best then W.pips(best.lvl or 1, C.LV_MAX, x + 55, ry + 58, 10, TIERC[bestTier + 1]) else W.pips(0, 5, x + 55, ry + 58, 10) end
                if eqd then W.tag("装备", x + 124, ry + 2, 44, 24, K.teal, K.ink, 14) end
                if sel then W.box(x, ry, 173, 78, { bg = { 0, 0, 0 }, alpha = 0, border = K.teal, bw = 4 }) end
                if W.hit(x, ry, 173, 78, true) then wk.form, wk.elem = F2.k, E2.k; if best then wk.tier, wk.v = best.tier, best.v or 0 end; C:sfx("click") end
            end
        end
    end
    W.scrollEnd(sc, 58, top, 1226, bot - top, mo)
end
local function chipsView()
    local s = sv(); local slots = C:chipSlots(); local eq = s.chipEq; if not eq then eq = require("jsrt.JS").newarr(0); s.chipEq = eq end
    local c = Hub.wsel and find(s.chips, function(x) return x.id == Hub.wsel end)
    W.panel(1302, 160, 560, 669, { alpha = 235 }); W.rect(1302, 162, 5, 665, K.teal)
    if c then
        W.title(1328, 176, c.name, 40, K.bone, NVG_ALIGN_LEFT + NVG_ALIGN_TOP); W.text(1328, 232, C.RARITY[c.tier].n .. "　Lv " .. (c.lvl or 1), 24, TIERC[c.tier + 1]); W.pips(c.lvl or 1, C.LV_MAX, 1328, 266, 12)
        for i, a in ipairs(list(c.aff)) do W.text(1334, 300 + (i - 1) * 40, "•  " .. C:affText(a, c), 26, K.bone) end
        if c.trait then local t = C:trait(c.trait); W.wrap(1334, 300 + #list(c.aff) * 40 + 10, 490, "金色特性「" .. t.n .. "」：" .. t.d, 22, K.amber, 1.4) end
        local k = has(eq, c.id); local lv, left = c.lvl or 1, C:adUpLeft()
        if W.btn(1328, 521, 252, 109, k and "卸下" or "装备", { primary = true, size = 34 }) then if k then eq:splice(k, 1) elseif eq.length >= slots then toast("槽位已满，先卸下一个") else eq:push(c.id) end; save(); C:sfx("click") end
        if W.btn(1590, 521, 252, 109, lv >= C.LV_MAX and "已满级" or ("看广告 升到 Lv " .. math.min(C.LV_MAX, lv + 1)), { teal = true, size = 26, sub = lv >= C.LV_MAX and nil or ("今日还可 " .. left .. " 次"), disabled = lv >= C.LV_MAX or left <= 0 }) then doAdUp(c, c.name) end
        if W.btn(1328, 650, 514, 62, "分解  +" .. C.REFUND[c.tier] .. " 信用点", { size = 24 }) then
            local kk = has(eq, c.id); if kk then eq:splice(kk, 1) end; local _, idx = find(s.chips, function(x) return x == c end); s.chips:splice(idx, 1); s.credits = s.credits + C.REFUND[c.tier]; Hub.wsel = nil; save(); C:sfx("pop"); toast("分解完成：信用点 +" .. C.REFUND[c.tier]) end
    else W.wrap(1328, 190, 500, "点选左侧的芯片查看详情。芯片属性永久生效，装备越多越强；每升 1 级词条 +12%。同系列芯片凑齐有额外效果。", 24, K.muted, 1.5) end
    if W.btn(1328, 728, 514, 90, "研发天赋芯片", { primary = true, size = 32, sub = fmt(C:CHIP_COST(s.chipBuys or 0)) .. " 信用点，仓库 " .. s.chips.length .. " / " .. C.INV_MAX, subSize = 21 }) then
        local r = C:buyChip(); if r.err then toast(r.err) else local it = r.chip; save(); C:sfx(it.tier >= 2 and "win" or "level"); if eq.length < slots then eq:push(it.id) end; Hub.wsel = it.id; Hub.results = { kind = "chip", item = it, name = it.name, tier = it.tier } end end
    local top, bot = 150, 1050; local items = list(s.chips); table.sort(items, function(a, b) if a.tier ~= b.tier then return a.tier > b.tier end return (a.lvl or 1) > (b.lvl or 1) end)
    local rows = math.ceil(#items / 6); local contentH = 200 + rows * 150 + 40
    local oy, sc, mo = W.scrollBegin("chips", 58, top, 1226, bot - top, contentH); local y0 = oy + 10
    W.text(58, y0, "天赋芯片　已装备 " .. eq.length .. " / " .. slots .. "（通关章节解锁更多槽位）　仓库 " .. s.chips.length .. " / " .. C.INV_MAX, 28, K.teal)
    for i = 0, 5 do local c2 = eq[i] and find(s.chips, function(x) return x.id == eq[i] end); local x = 58 + i * 206
        W.rect(x, y0 + 50, 196, 100, { 12, 16, 40 }, 230); W.box(x, y0 + 50, 196, 100, { bg = { 0, 0, 0 }, alpha = 0, border = c2 and TIERC[c2.tier + 1] or K.hi, bw = 3 })
        if c2 then W.text(x + 98, y0 + 62, c2.series, 24, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); W.text(x + 98, y0 + 100, "Lv " .. (c2.lvl or 1), 20, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); if W.hit(x, y0 + 50, 196, 100, true) then Hub.wsel = c2.id; C:sfx("click") end
        else W.text(x + 98, y0 + 86, i >= slots and "未解锁" or "空槽", 22, K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end end
    for i, c2 in ipairs(items) do local col, row = (i - 1) % 6, (i - 1) // 6; local x, y = 58 + col * 206, y0 + 180 + row * 150
        if W.visible(y, 140, top, bot) then
            W.rect(x, y, 196, 140, { 14, 18, 44 }, 235); W.rect(x, y, 196, 5, TIERC[c2.tier + 1])
            if Hub.wsel == c2.id then W.box(x, y, 196, 140, { bg = { 0, 0, 0 }, alpha = 0, border = K.teal, bw = 4 }) end
            W.text(x + 98, y + 16, c2.series, 24, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); W.text(x + 98, y + 50, C.RARITY[c2.tier].n, 20, TIERC[c2.tier + 1], NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            W.pips(c2.lvl or 1, C.LV_MAX, x + 48, y + 84, 12); if has(eq, c2.id) then W.tag("装备", x + 148, y + 10, 44, 24, K.teal, K.ink, 14) end
            W.text(x + 98, y + 108, C:affText(c2.aff[0], c2), 18, K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            if W.hit(x, y, 196, 140, true) then Hub.wsel = c2.id; C:sfx("click") end
        end end
    W.scrollEnd(sc, 58, top, 1226, bot - top, mo)
end
local function workView()
    frameTop("工坊", "收集技能卡牌（形态 x 元素），装备后才能在局内使用与升级"); body()
    local function sub(x, label, on, key) W.rect(x, 35, 172, 70, on and K.teal or { 28, 34, 70 }); W.text(x + 86, 70, label, 30, on and K.ink or K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE); if W.hit(x, 35, 172, 70) then Hub.wsub = key; C:sfx("click") end end
    sub(898, "技能模块", Hub.wsub == "mods", "mods"); sub(1076, "天赋芯片", Hub.wsub == "chips", "chips")
    if Hub.wsub == "mods" then modsView() else chipsView() end
end

-- ---------------------------------------------------------------- 召唤
local function summonView()
    local s = sv(); topbar()
    local isM = Hub.banner == "mech"; local arr = isM and C.MECHS or C.CHARS; local RT = C.SUMMON.rates; local b = Hub.banner
    local function banner(y, h, key, title, list_, on)
        local p1 = s[key .. "Pity"] or 0
        W.panel(36, y, 380, h, { alpha = on and 235 or 200 }); if on then W.box(36, y, 380, h, { bg = { 0, 0, 0 }, alpha = 0, border = K.amber, bw = 4 }) end
        W.title(54, y + 12, title, 44, K.bone, NVG_ALIGN_LEFT + NVG_ALIGN_TOP)
        local top = {}; for _, x in ipairs(list(list_)) do if x.grade == "SSR" or x.grade == "SSSR" then top[#top + 1] = x end end
        for i, x in ipairs(top) do W.pix(UI.CatIcon(x.id), 54 + (i - 1) * 84, y + 76, 80, nil, 255, true) end
        local names = {}; for _, x in ipairs(top) do names[#names + 1] = x.name end
        W.text(54, y + h - 58, "SSR / SSSR " .. table.concat(names, "、"), 20, K.bone); W.text(398, y + h - 36, "保底 " .. p1 .. " / " .. C.SUMMON.pitySSR, 18, K.muted, NVG_ALIGN_RIGHT + NVG_ALIGN_TOP)
        if W.hit(36, y, 380, h) then Hub.banner = key == "mech" and "mech" or "pilot"; C:sfx("click") end
    end
    banner(140, 240, "mech", "机甲召唤", C.MECHS, isM); banner(394, 231, "pilot", "驾驶员召唤", C.CHARS, not isM)
    W.title(960, 126, isM and "机甲召唤" or "驾驶员召唤", 76, K.amberHi, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, K.amber)
    W.text(960, 250, "SSR+ 出现率 " .. string.format("%.0f", (RT.SSR + RT.SSSR) * 100) .. "%　·　十连必出 SS+　·　" .. C.SUMMON.pitySSR .. " 抽内必出 SSR+　·　" .. C.SUMMON.pitySSSR .. " 抽内必出 SSSR", 21, K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    local function pull(n, cost)
        if s.src < cost then Hub.modal = "getsrc" return end
        s.src = s.src - cost; s.daily.pulls = (s.daily.pulls or 0) + n
        local out = {}; for i = 1, n do out[#out + 1] = C:pull(b, false) end
        local all = true; for _, r in ipairs(out) do if r.grade ~= "S" then all = false end end
        if n == 10 and all then s[b .. "Pity"] = s[b .. "Pity"] - 1; out[10] = C:pull(b, true) end
        save(); Hub.StartSummon(out)
    end
    local freeDone = s.daily.free and true or false
    if W.btn(1124, 715, 245, 137, "每日免费", { teal = true, size = 36, sub = freeDone and "今日已领取" or "看广告召唤 1 次", subSize = 24, disabled = freeDone }) then
        C:showAd("每日免费召唤", function(_, r) if not r.success then toast("需要完整看完广告才能召唤") return end s.daily.free = 1; s.daily.pulls = (s.daily.pulls or 0) + 1; local res = { C:pull(b, false) }; save(); Hub.StartSummon(res) end) end
    if W.btn(1381, 715, 245, 137, "召唤 1 次", { size = 36, sub = tostring(C.SUMMON.single), subSize = 26 }) then pull(1, C.SUMMON.single) end
    if W.btn(1638, 715, 246, 137, "召唤 10 次", { primary = true, size = 36, sub = tostring(C.SUMMON.ten) .. "（9 折）", subSize = 26 }) then pull(10, C.SUMMON.ten) end
    if W.btn(1728, 862, 156, 58, "概率详情", { flat = true, size = 24 }) then Hub.modal = "rates" end
end

-- ---------------------------------------------------------------- 每日
local function dailyView()
    local s = sv(); frameTop("每日", "每天回来领取补给、任务奖励与巡航收益"); body()
    local top, bot = 150, 1050; local contentH = 1240
    local oy, sc, mo = W.scrollBegin("daily", 52, top, 1820, bot - top, contentH)
    local y0 = oy + 10; local ls = C:loginState()
    -- 左列：登录 / 每日挑战 / 巡航 / 补给
    W.text(66, y0, "7 日登录奖励", 22, K.teal)
    for i, r in ipairs(list(C.LOGIN_REWARDS)) do
        local x = 66 + (i - 1) * 126; local done = (ls.claimed and (i - 1) <= ls.idx) or ((not ls.claimed) and (i - 1) < ls.idx); local cur = (not ls.claimed) and (i - 1) == ls.idx
        W.rect(x, y0 + 37, 121, 133, { 14, 18, 44 }, done and 120 or 235); W.box(x, y0 + 37, 121, 133, { bg = { 0, 0, 0 }, alpha = 0, border = cur and K.amber or K.hi, bw = 3 })
        W.text(x + 60, y0 + 46, "第" .. i .. "天", 22, cur and K.amber or K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        UI.Icon(UI.ResIcon(r.cr and "credit" or "shard"), x + 40, y0 + 78, 40); W.text(x + 60, y0 + 124, r.cr and (r.cr .. " 信用点") or (r.src .. " 星源"), 17, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        if r.draw then W.text(x + 60, y0 + 146, "+抽卡", 16, K.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end
    end
    W.text(66, y0 + 190, ls.claimed and "今日奖励已领取，明天再来" or "今日奖励可领取", 24, K.bone)
    if W.btn(828, y0 + 190, 100, 64, ls.claimed and "已领" or "领取", { primary = true, size = 24, disabled = ls.claimed and true or false, click = true }) then local t = C:loginClaim(); if t then C:sfx("win"); toast("登录奖励：" .. t) end end
    local dc = C:dailyChallenge(); local cy = y0 + 330
    W.panel(66, cy, 880, 304, { alpha = 230 }); W.rect(66, cy + 2, 5, 290, { 255, 138, 58 })
    W.text(92, cy + 16, "每日挑战　第 " .. dc.chapter .. " 章　限时 4 分钟", 30, { 255, 138, 58 })
    for i, id in ipairs(list(dc.mods)) do local m = C:dcMod(id); W.text(92, cy + 64 + (i - 1) * 40, m.n .. "：" .. m.d, 24, K.bone) end
    W.text(92, cy + 150, "今日最高分 " .. dc.state.best .. "　历史最高 " .. (s.dcBest or 0) .. "　" .. (dc.state.done and "今日奖励已领取" or "首次完成：信用点 +800，星源 +10"), 22, K.muted)
    if W.btn(92, cy + 192, 834, 90, "开始挑战", { primary = true, size = 36, click = true }) then C:sfx("gate"); Hub.onStart(dc.chapter, { daily = true, mods = dc.mods, danger = dc.danger }) end
    local iy = cy + 320; local a = C:idleAmount()
    W.text(66, iy, "巡航收益", 22, K.teal); W.text(66, iy + 36, "离线也会累积，最多 8 小时", 22, K.muted)
    UI.Icon(UI.ResIcon("credit"), 66, iy + 74, 36); W.text(114, iy + 70, fmt(a.credits), 44, K.bone)
    local function claimIdle(mult) s.credits = s.credits + a.credits * mult; s.idleT = require("jsrt.JS").G.Date:now(); save(); C:sfx("pick"); toast("巡航收益：信用点 +" .. fmt(a.credits * mult)) end
    if W.btn(666, iy, 260, 74, "领取", { size = 28, click = true }) then claimIdle(1) end
    if W.btn(666, iy + 84, 260, 74, "看广告 双倍", { teal = true, size = 26, click = true }) then C:showAd("巡航收益双倍", function(_, r) if not r.success then toast("需要完整看完广告才能领取") return end claimIdle(2) end) end
    local sy = iy + 190; W.text(66, sy, "每日补给", 22, K.teal)
    local got = s.daily.supply and s.daily.supply ~= 0
    if W.btn(66, sy + 36, 430, 70, got and "补给已领取" or ("领取补给 星源 +" .. C.DAILY_SUPPLY), { size = 26, disabled = got and true or false, click = true }) then s.daily.supply = 1; s.src = s.src + C.DAILY_SUPPLY; save(); C:sfx("pick"); toast("每日补给：星源 +" .. C.DAILY_SUPPLY) end
    local left = C.AD.srcDaily - (s.daily.ads or 0)
    if W.btn(516, sy + 36, 430, 70, "看广告 星源 +" .. C.AD.srcReward .. "（今日还可 " .. math.max(0, left) .. " 次）", { teal = true, size = 22, disabled = left <= 0, click = true }) then
        C:showAd("领取星源", function(_, r) if not r.success then toast("需要完整看完广告才能领取") return end s.daily.ads = (s.daily.ads or 0) + 1; s.src = s.src + C.AD.srcReward; save(); C:sfx("pick"); toast("星源 +" .. C.AD.srcReward) end) end
    -- 右列：任务 / 成就
    W.text(980, y0, "每日任务", 22, K.teal)
    for i, t in ipairs(list(C.TASKS)) do local yy = y0 + 37 + (i - 1) * 88; local v = math.min(t.need, s.daily[t.key] or 0); local done = v >= t.need
        W.panel(980, yy, 880, 80, { alpha = 215, flat = true }); W.text(1000, yy + 10, t.name, 26, K.bone); W.text(1000, yy + 46, v .. " / " .. t.need, 22, K.muted)
        UI.Icon(UI.ResIcon("shard"), 1500, yy + 22, 34); W.text(1546, yy + 22, "+" .. t.reward, 28, K.teal)
        if W.btn(1690, yy + 10, 150, 60, s.daily.claimed[t.id] and "已领取" or "领取", { size = 24, primary = done and not s.daily.claimed[t.id], disabled = s.daily.claimed[t.id] and true or (not done), click = true }) then s.daily.claimed[t.id] = 1; s.src = s.src + t.reward; save(); C:sfx("pick"); toast("任务奖励：星源 +" .. t.reward) end end
    local nach = 0; for _ in pairs(s.ach) do nach = nach + 1 end
    local ay = y0 + 37 + 3 * 88 + 30; W.text(980, ay, "成就（" .. nach .. " / " .. C.ACH.length .. "）", 22, K.teal)
    for i, a in ipairs(list(C.ACH)) do local col, row = (i - 1) % 2, (i - 1) // 2; local x, yy = 980 + col * 446, ay + 36 + row * 86; local ok = a.ok(nil, s)
        W.panel(x, yy, 434, 78, { alpha = 215, flat = true }); W.text(x + 16, yy + 8, a.name, 24, ok and K.bone or K.muted); W.text(x + 16, yy + 42, a.desc, 17, K.muted)
        UI.Icon(UI.ResIcon("shard"), x + 250, yy + 10, 26); W.text(x + 284, yy + 8, "+" .. a.src, 22, K.teal)
        if W.btn(x + 296, yy + 38, 126, 36, s.ach[a.id] and "已领取" or "领取", { size = 20, primary = ok and not s.ach[a.id], disabled = s.ach[a.id] and true or (not ok), click = true }) then if C:achClaim(a.id) then C:sfx("pick"); toast("成就奖励已领取") end end end
    W.scrollEnd(sc, 52, top, 1820, bot - top, mo)
end

-- ---------------------------------------------------------------- 弹窗：结果 / 设置 / 关于 / 获取星源 / 概率
local function dim(a) W.rect(0, 0, UI.lw, 1080, { 0, 0, 10 }, a or 190) end
local function drawResults()
    local Wd, r = UI.lw, Hub.results; dim(); W.panel(Wd / 2 - 700, 120, 1400, 800, { alpha = 245 })
    W.title(Wd / 2, 140, r.kind == "card" and "研发完成" or "芯片研发完成", 64, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, K.amber)
    W.text(Wd / 2, 250, C.RARITY[r.tier].n, 32, TIERC[r.tier + 1], NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if r.kind == "card" then W.pix(C:modIcon(r.item), Wd / 2 - 50, 300, 100, nil, 255, true) end
    W.title(Wd / 2, 420, r.name, 56, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
    if r.kind == "card" then
        W.text(Wd / 2, 500, r.dup and ("已拥有：卡牌升到 Lv " .. (r.item.lvl or 1) .. (r.refund and ("（已满级，折算信用点 +" .. r.refund .. "）") or "")) or "新卡牌", 28, K.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        W.wrap(Wd / 2 - 450, 560, 900, C:modDesc(r.item), 26, K.bone, 1.5)
    else for i, a in ipairs(list(r.item.aff)) do W.text(Wd / 2, 500 + (i - 1) * 44, "•  " .. C:affText(a, r.item), 30, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP) end end
    if W.btn(Wd / 2 - 150, 810, 300, 80, "确定", { primary = true, size = 34 }) then Hub.results = nil end
end
local function drawSettings()
    local Wd, s = UI.lw, sv(); dim(); W.panel(Wd / 2 - 560, 120, 1120, 820, { alpha = 248 }); W.title(Wd / 2, 140, "设置", 60, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, K.amber)
    local st = s.settings
    if W.btn(Wd / 2 - 520, 240, 500, 70, "音效：" .. (st.sound and "开" or "关"), { size = 28 }) then st.sound = not st.sound; save() end
    if W.btn(Wd / 2 + 20, 240, 500, 70, "背景音乐：" .. (st.music and "开" or "关"), { size = 28 }) then st.music = not st.music; save(); C.music:refresh() end
    local camN = { chase = "标准", high = "远景", mid = "近景" }
    W.text(Wd / 2 - 520, 346, "镜头", 26, K.muted)
    for i, k in ipairs({ "mid", "chase", "high" }) do if W.btn(Wd / 2 - 400 + (i - 1) * 300, 330, 280, 60, camN[k], { size = 26, primary = (st.cam or "chase") == k }) then st.cam = k; save() end end
    W.text(Wd / 2 - 520, 436, "特效", 26, K.muted)
    for i, k in ipairs({ "high", "soft" }) do if W.btn(Wd / 2 - 400 + (i - 1) * 300, 420, 280, 60, k == "high" and "完整" or "柔和（减少粒子）", { size = 24, primary = (st.fx or "high") == k }) then st.fx = k; save() end end
    W.text(Wd / 2 - 520, 526, "辉光", 26, K.muted)
    for i, k in ipairs({ "low", "mid", "high" }) do if W.btn(Wd / 2 - 400 + (i - 1) * 190, 510, 180, 60, ({ low = "弱", mid = "标准", high = "强" })[k], { size = 26, primary = (st.glow or "mid") == k }) then st.glow = k; save() end end
    if W.btn(Wd / 2 + 190, 510, 330, 60, "色调映射（实验）：" .. (st.tone and "开" or "关"), { size = 22, primary = st.tone and true or false }) then st.tone = not st.tone; save(); toast("色调映射将在重启游戏后生效") end
    if W.btn(Wd / 2 - 520, 610, 500, 70, "省电模式：" .. (st.saver and "开" or "关"), { size = 26 }) then st.saver = not st.saver; save() end
    if W.btn(Wd / 2 + 20, 610, 500, 70, "重播新手引导", { size = 26 }) then s.tutorialDone = false; save(); toast("下一次出击会重新播放新手引导") end
    if W.btn(Wd / 2 - 520, 700, 500, 70, "关于与合规", { size = 26 }) then Hub.modal = "about" end
    if W.btn(Wd / 2 - 150, 810, 300, 80, "关闭", { primary = true, size = 34 }) then Hub.modal = nil end
end
local function drawAbout()
    local Wd = UI.lw; dim(); W.panel(Wd / 2 - 800, 80, 1600, 900, { alpha = 248 }); W.title(Wd / 2, 96, "关于与合规", 56, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, K.amber); local RT = C.SUMMON.rates
    local lines = {
        { "原创声明", "游戏内全部机甲、角色、敌人、场景模型均为原创体素建模；音效与背景音乐为程序合成的原创音频。与任何现有动漫、游戏、影视作品及其角色、机体、商标无关联。" },
        { "抽取概率公示", string.format("召唤（机甲 / 驾驶员）：SSSR %.0f%%，SSR %.0f%%，SS %.0f%%，S %.0f%%；连续 %d 次未出 SSR 以上时下一次必出 SSR 以上，连续 %d 次未出 SSSR 时下一次必出 SSSR。工坊（技能卡牌 / 天赋芯片）：白色 60%%，蓝色 28%%，紫色 10%%，金色 2%%；每 10 次至少蓝色，每 40 次必出金色；技能卡牌共 %d 张。所有抽取只消耗游戏内货币，本版本无真实货币付费。", RT.SSSR * 100, RT.SSR * 100, RT.SS * 100, RT.S * 100, C.SUMMON.pitySSR, C.SUMMON.pitySSSR, C:MOD_TOTAL()) },
        { "广告", "“看广告”为可选行为，用于升级卡牌 / 芯片、刷新升级选项、复活、免费召唤、信用点翻倍或领取星源；不看不影响通关。只有完整观看才发放奖励。" },
        { "隐私", "本游戏不要求登录，不收集个人信息；存档保存在设备本地。" },
        { "适龄提示", "含卡通风格的科幻战斗（无血腥），建议 12 岁及以上；请合理安排游戏时间。" },
    }
    local y = 180; for _, l in ipairs(lines) do W.text(Wd / 2 - 740, y, l[1], 28, K.teal); W.wrap(Wd / 2 - 740, y + 38, 1480, l[2], 24, K.bone, 1.5); y = y + 38 + 36 * (math.floor(#l[2] / 62) + 1) + 20 end
    if W.btn(Wd / 2 - 150, 880, 300, 70, "关闭", { primary = true, size = 32 }) then Hub.modal = "settings" end
end
local function drawRates()
    local Wd = UI.lw; local RT = C.SUMMON.rates; dim(); W.panel(Wd / 2 - 520, 220, 1040, 560, { alpha = 248 }); W.title(Wd / 2, 240, "概率详情", 60, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, K.amber)
    for i, g in ipairs({ "SSSR", "SSR", "SS", "S" }) do local y = 340 + (i - 1) * 60; W.badge(g, Wd / 2 - 400, y, 90, 40, 26); W.text(Wd / 2 - 280, y + 4, string.format("%.0f%%", RT[g] * 100), 32, K.bone) end
    W.wrap(Wd / 2 - 480, 590, 960, "十连必出 SS 以上；" .. C.SUMMON.pitySSR .. " 抽内必出 SSR 以上，" .. C.SUMMON.pitySSSR .. " 抽内必出 SSSR（机甲池与驾驶员池分开计算）。重复获得会转成碎片，用于升星。", 24, K.muted, 1.5)
    if W.btn(Wd / 2 - 150, 690, 300, 70, "关闭", { primary = true, size = 32 }) then Hub.modal = nil end
end
local function drawGetSrc()
    local Wd, s = UI.lw, sv(); dim(); W.panel(Wd / 2 - 520, 220, 1040, 520, { alpha = 248 }); W.title(Wd / 2, 240, "获取星源", 60, K.amber, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, K.amber)
    local left = C.AD.srcDaily - (s.daily.ads or 0)
    W.text(Wd / 2 - 480, 350, "观看广告　今日还可领取 " .. math.max(0, left) .. " 次　+" .. C.AD.srcReward, 28, K.bone)
    if W.btn(Wd / 2 + 200, 336, 280, 64, "看广告", { teal = true, size = 26, disabled = left <= 0 }) then C:showAd("领取星源", function(_, r) if not r.success then toast("需要完整看完广告才能领取") return end s.daily.ads = (s.daily.ads or 0) + 1; s.src = s.src + C.AD.srcReward; save(); C:sfx("pick"); toast("星源 +" .. C.AD.srcReward) end) end
    W.text(Wd / 2 - 480, 440, "每日补给与每日任务：在“每日”页领取", 26, K.bone); if W.btn(Wd / 2 + 200, 426, 280, 64, "前往", { size = 26 }) then Hub.modal = nil; Hub.tab = "daily" end
    W.text(Wd / 2 - 480, 530, "章节首通、营救逃生舱、击败首领：出击时获得", 26, K.muted)
    if W.btn(Wd / 2 - 150, 630, 300, 70, "关闭", { primary = true, size = 32 }) then Hub.modal = nil end
end


-- ---------------------------------------------------------------- 机库 3D 场景（移植自 cosmic_hub.js 的 DECOR / frame / summonScene）
local JS = require("jsrt.JS")
local Hostmod = require("jsrt.Host")
local ENV, SUM_ENV
local DECOR
local function buildDecor()
    local d = {}
    for x = -5, 5 do for z = -3, 3 do d[#d + 1] = { "env_deck_tile", x * 2, -0.25, z * 2, 0, 1 } end end
    local k = 0; for _, x in ipairs({ -7.5, -4.5, -1.5, 1.5, 4.5, 7.5 }) do d[#d + 1] = { k == 2 and "env_door" or "env_wall", x, 0, -6.6, 0, 1 }; k = k + 1 end
    d[#d + 1] = { "env_antenna", -9.5, 0, -4.8, 30, 1 }; d[#d + 1] = { "env_antenna", 9.5, 0, -4.8, -30, 1 }
    d[#d + 1] = { "prop_cargo_container", -7.4, 0, -2.6, 90, 1.1 }; d[#d + 1] = { "prop_cargo_container", -7.4, 1.32, -2.6, 85, 1.1 }
    d[#d + 1] = { "prop_supply_crate", 6.6, 0, -3.4, 15, 1.2 }; d[#d + 1] = { "prop_supply_crate", 7.6, 0, -2.6, -10, 1.2 }; d[#d + 1] = { "prop_supply_crate", 7.0, 0.95, -3.0, 30, 1.2 }
    d[#d + 1] = { "prop_fuel_canister", 5.6, 0, -4.4, 0, 1.2 }; d[#d + 1] = { "prop_fuel_canister", 6.2, 0, -5.0, 0, 1.2 }
    d[#d + 1] = { "prop_console", -4.8, 0, -4.6, 20, 1.1 }; d[#d + 1] = { "env_crystal_cluster", 8.8, 0, 1.6, -40, 1.2 }; d[#d + 1] = { "prop_turret", -8.6, 0, 1.8, 140, 1.1 }
    return d
end
local GTINT = { S = { 0.3, 0.7, 1.5 }, SS = { 0.75, 0.4, 1.5 }, SSR = { 1.6, 1.0, 0.25 }, SSSR = { 1.7, 0.35, 0.55 } }
local function top(g) return g == "SSR" or g == "SSSR" end
local starBuf
local function hubStars(E, jsarr)
    if not starBuf then
        local d = jsarr(0); local n = 0
        for _ = 1, 420 do local x, y, z = math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1; local l = math.sqrt(x * x + y * y + z * z); if l == 0 then l = 1 end
            local vals = { x / l * 300, y / l * 300, z / l * 300, 3 + math.random() * 6, math.random() < 0.7 and 0 or (math.random() < 0.5 and 1 or 2) }
            for _, v in ipairs(vals) do rawset(d, n, v); n = n + 1 end end
        rawset(d, "length", n)
        starBuf = E:buildStars({ data = d, colors = jsarr(3, jsarr(3, 0.92, 0.93, 1.0), jsarr(3, 0.6, 0.85, 1.0), jsarr(3, 1.0, 0.8, 0.5)) })
    end
    return starBuf
end
local hp = {}
local function burst(n, c, speed, tint, life, up)
    for _ = 1, n do if #hp >= 220 then break end
        local u, a = math.random() * 2 - 1, math.random() * math.pi * 2; local r = math.sqrt(1 - u * u); local sp = speed * (0.4 + math.random() * 0.6)
        hp[#hp + 1] = { x = c[1], y = c[2], z = c[3], vx = math.cos(a) * r * sp, vy = (up and math.abs(u) or u) * sp, vz = math.min(math.sin(a) * r * sp, sp * 0.15), life = life * (0.6 + math.random() * 0.6), max = life, tint = tint, size = 0.6 + math.random() * 0.6 } end
end
function Hub.StartSummon(res)
    local best = "S"; for _, r in ipairs(res) do if ORDER[r.grade] > ORDER[best] then best = r.grade end end
    local show = {}; for _, r in ipairs(res) do if r.isNew and r.grade ~= "S" then show[#show + 1] = r end end
    Hub.sa = { phase = "charge", t = 0, grade = best, res = res, show = show, si = 1, flipped = {}, flash = 0 }; hp = {}; C:sfx("skill")
end
function Hub.FinishSummon() Hub.sa = nil; hp = {} end
function Hub.Scene(E, jsarr, aspect, dt)
    local A, V = HOST.A, HOST.view
    if not ENV then
        ENV = Hostmod.jsify({ bg = { 0.05, 0.06, 0.14 }, ambient = { 0.46, 0.44, 0.6 }, fog = { 30, 70 }, key = { dir = { -0.4, -0.8, -0.45 }, color = { 1, 0.95, 0.88 }, brightness = 1.25 }, fill = { dir = { 0.6, -0.3, 0.7 }, color = { 0.45, 0.75, 1.0 }, brightness = 0.55 }, bloom = { threshold = 0.55, mix = 0.95 } })
        SUM_ENV = Hostmod.jsify({ bg = { 0.03, 0.03, 0.09 }, ambient = { 0.38, 0.36, 0.55 }, fog = { 40, 160 }, key = { dir = { -0.3, -0.8, -0.5 }, color = { 1, 0.92, 0.85 }, brightness = 1.1 }, fill = { dir = { 0.5, -0.2, 0.8 }, color = { 0.6, 0.45, 1.0 }, brightness = 0.7 }, bloom = { threshold = 0.5, mix = 1.1 } })
        DECOR = buildDecor()
    end
    Hub.t = Hub.t + dt; local t = Hub.t; local s = sv(); local sa = Hub.sa
    local draws = jsarr(0)
    local function add(model, x, y, z, yaw, sc, tint, pitch)
        local m = E:getMesh(model); if m then draws:push({ mesh = m, m = E:trs(jsarr(3, x, y, z), yaw, pitch or 0, 0, sc), s = sc, tint = tint and jsarr(3, tint[1], tint[2], tint[3]) or nil }) end
    end
    local eye, tgt, fov
    if Hub.tab == "summon" or sa then
        local isM = Hub.banner == "mech"; local feat = {}; for _, x in ipairs(list(isM and C.MECHS or C.CHARS)) do if top(x.grade) then feat[#feat + 1] = x end end
        add("sys_pedestal", 0, 0, 0, t * 6, 3.4)
        for i = 0, 4 do local a = math.pi + i / 4 * math.pi; add("env_crystal_cluster", math.cos(a) * 8, 0, math.sin(a) * 5 - 3, a * 57 + t * 8, 1.15) end
        eye, tgt, fov = { 0, 3.3, 12.5 }, { 0, 2.6, 0 }, 44
        local shard = { 0, 3.4 + math.sin(t * 1.5) * 0.25, 0 }; local spin = t * 40
        if not sa then
            add("prop_meteor_shard", shard[1], shard[2], shard[3], spin, 2.2)
            for k, x in ipairs(feat) do local px = (k == 2) and 4.4 or -4.4; local py = 1.6 + math.sin(t * 1.2 + (k - 1) * 2) * 0.15
                add("sys_pedestal", px, py, -1.5, 0, 1.1); add(x.id, px, py + 0.12, -1.5, ((k == 2) and -20 or 20) + math.sin(t * 0.8 + (k - 1)) * 10, isM and 0.72 or 1.5) end
            if math.random() < 0.18 then burst(1, shard, 1, { 0.3, 0.55, 0.85 }, 1.6, true) end
        else
            sa.t = sa.t + dt; local T, tint = sa.t, GTINT[sa.grade]; sa.flash = math.max(0, sa.flash - dt)
            if sa.phase == "charge" then
                spin = t * 40 + T * T * 900; shard[2] = shard[2] + T * 2.5; add("prop_meteor_shard", shard[1], shard[2], shard[3], spin, 2.2 + T)
                for _ = 1, 2 do local aa, rr = math.pi + math.random() * math.pi, 7; hp[#hp + 1] = { x = math.cos(aa) * rr, y = 0.5 + math.random() * 4, z = math.sin(aa) * rr, vx = -math.cos(aa) * rr * 1.4, vy = 1.5, vz = -math.sin(aa) * rr * 1.4, life = 0.7, max = 0.7, tint = { 0.7, 0.75, 0.95 }, size = 1 } end
                if T > 0.9 then sa.phase = "fall"; sa.t = 0; C:sfx("warp") end
            elseif sa.phase == "fall" then
                local k = math.min(1, T / 0.6); local y = 34 - 32 * k * k; local col = k > 0.55 and tint or { 0.8, 0.8, 0.95 }
                add("prop_meteor_shard", 0, y, 0, t * 500, 3.2); burst(2, { 0, y + 1, 0 }, 2.5, col, 0.5)
                eye = { 0, 3.3 + k * 0.6, 12.5 }; tgt = { 0, 2.6 + (1 - k) * 4, 0 }
                if k >= 1 then sa.phase = "burst"; sa.t = 0; burst(90, { 0, 1.5, 0 }, 16, tint, 1.4); C:sfx(top(sa.grade) and "win" or "boom"); sa.flash = 0.6 end
            elseif sa.phase == "burst" then
                local sh = math.max(0, 0.6 - T) * 0.5; eye = { math.random() * sh - sh / 2, 3.3 + math.random() * sh, 12.5 }
                if math.random() < 0.9 then burst(3, { 0, 1, 0 }, 6, tint, 1, true) end
                if T > 0.75 then sa.phase = "cards"; sa.t = 0 end
            elseif sa.phase == "cards" then if math.random() < 0.5 then burst(1, { 0, 1, 0 }, 4, tint, 1.2, true) end
            elseif sa.phase == "show" then
                local it = sa.show[sa.si]; local g = it.grade; local isMech = it.kind == "mech"
                add(it.id, 0, 0.15, 0, math.sin(T * 0.7) * 25 + T * 20, isMech and 1.05 or 2.1)
                if math.random() < 0.9 then burst(2, { math.random() * 4 - 2, 0.2, math.random() * 4 - 2 }, 3, GTINT[g], 1.6, true) end
                eye = { 0, 2.8, 10.5 }; tgt = { 0, 2.3, 0 }
            end
        end
        local keep = {}
        for _, p in ipairs(hp) do p.life = p.life - dt; p.x, p.y, p.z = p.x + p.vx * dt, p.y + p.vy * dt, p.z + p.vz * dt; local d = math.exp(-dt * 1.8); p.vx, p.vy, p.vz = p.vx * d, p.vy * d, p.vz * d
            if p.life > 0 then keep[#keep + 1] = p; if p.z <= 5 then add("fx_white", p.x, p.y, p.z, p.life * 300, p.size * 1.3 * math.max(0.2, p.life / p.max), p.tint, 45) end end end
        hp = keep
        return { env = SUM_ENV, eye = jsarr(3, eye[1], eye[2], eye[3]), target = jsarr(3, tgt[1], tgt[2], tgt[3]), fov = A:fitFov(fov, aspect), aspect = aspect, near = 0.1, far = 400, draws = draws, stars = hubStars(E, jsarr) }
    end
    for _, d in ipairs(DECOR) do add(d[1], d[2], d[3], d[4], d[5], d[6]) end
    local f = (Hub.tab == "pilots") and { pilot = Hub.pilotSel or s.pilot } or (Hub.tab == "hangar" and { mech = Hub.mechSel or s.mech } or { mech = s.mech, pilot = s.pilot })
    if Hub.tab == "hangar" or Hub.tab == "pilots" then
        Hub.yaw = (Hub.yaw or 0) + dt * 14
        add("sys_pedestal", 0, 0, 0, 0, 2.6)
        if f.mech then add(f.mech, 0, 0.24 + math.sin(t * 1.6) * 0.05, 0, Hub.yaw, 1.15) else add(f.pilot, 0, 0.25 + math.sin(t * 2) * 0.04, 0, Hub.yaw, 2.3) end
        fov = A:fitFov(38, aspect); local dist = 11
        -- 让主体出现在左列表与右详情之间的空白区域中央
        local l, r = 336 * V.s, 1284 * V.s; local ndc = ((l + r) / 2) / V.w * 2 - 1; local sx = ndc * math.tan(fov * math.pi / 360) * (V.w / V.h) * dist
        eye, tgt = { sx, 3.1, dist }, { sx, 2.2, 0 }
    else
        local sway = math.sin(t * 0.5) * 18
        add("sys_pedestal", 0, 0, 0, 0, 2.4)
        if f.mech then add(f.mech, -0.6, 0.24 + math.sin(t * 1.6) * 0.05, 0, sway, 1.1) end
        if f.pilot then add(f.pilot, 2.7, 0, 1.4, -25 + math.sin(t * 0.9) * 6, 1.25) end
        eye, tgt, fov = { 3.2, 3.6, 11.5 }, { 0.2, 2.1, 0 }, A:fitFov(36, aspect)
    end
    return { env = ENV, eye = jsarr(3, eye[1], eye[2], eye[3]), target = jsarr(3, tgt[1], tgt[2], tgt[3]), fov = fov, aspect = aspect, near = 0.1, far = 400, draws = draws }
end


-- ---------------------------------------------------------------- 召唤动画：2D 叠加层（闪光 / 光线 / 翻牌 / 新角色展示）
local GCOLS = GRADE
drawSummonAnim = function()
    local sa, Wd = Hub.sa, UI.lw; local gc = GCOLS[sa.grade]
    if sa.phase == "burst" or sa.phase == "cards" or sa.phase == "show" then
        local lit = sa.phase == "burst" and math.min(1, sa.t / 0.4) or 1
        W.rect(0, 0, Wd, 1080, { gc[1] // 4, gc[2] // 4, gc[3] // 4 }, math.floor(120 * lit))
        for k = 0, 15 do
            local a = k / 16 * math.pi * 2 + Hub.t * 0.3; nvgBeginPath(UI.vg); nvgMoveTo(UI.vg, Wd / 2, 470); nvgLineTo(UI.vg, Wd / 2 + math.cos(a - 0.05) * 1800, 470 + math.sin(a - 0.05) * 1800); nvgLineTo(UI.vg, Wd / 2 + math.cos(a + 0.05) * 1800, 470 + math.sin(a + 0.05) * 1800)
            nvgFillColor(UI.vg, nvgRGBA(gc[1], gc[2], gc[3], math.floor(26 * lit))); nvgFill(UI.vg)
        end
    end
    if sa.flash > 0 then W.rect(0, 0, Wd, 1080, { 255, 255, 255 }, math.floor(255 * sa.flash / 0.6)) end
    if W.btn(Wd - 220, 40, 180, 64, "跳过", { size = 28 }) then
        if sa.phase == "charge" or sa.phase == "fall" or sa.phase == "burst" then sa.phase = "cards"; sa.t = 0; sa.instant = true elseif sa.phase == "cards" then sa.instant = true else Hub.FinishSummon() end
    end
    if sa.phase == "cards" then
        local res = sa.res; local n = #res; local cw, ch = n > 1 and 250 or 420, n > 1 and 300 or 520; local cols = n > 5 and 5 or n; local rows = math.ceil(n / cols)
        for i, r in ipairs(res) do
            local x0 = Wd / 2 - (cols * (cw + 20) - 20) / 2 + ((i - 1) % cols) * (cw + 20); local y0 = 540 - (rows * (ch + 20) - 20) / 2 + ((i - 1) // cols) * (ch + 20) - 40
            local delay = sa.instant and 0 or (0.15 + (i - 1) * 0.16 + (top(r.grade) and 0.35 or 0)); local p = math.max(0, math.min(1, (sa.t - delay) / 0.4))
            if p >= 0.5 and not sa.flipped[i] then sa.flipped[i] = true; C:sfx(top(r.grade) and "win" or (r.grade == "SS" and "level" or "click")) end
            local gcol = GCOLS[r.grade]; local sw = math.max(2, math.abs(1 - 2 * p) * cw); local cx = x0 + cw / 2
            W.rect(cx - sw / 2, y0, sw, ch, p < 0.5 and { 20, 26, 60 } or { 14, 18, 44 }, 250); W.rect(cx - sw / 2, y0, sw, 8, gcol); W.rect(cx - sw / 2, y0 + ch - 8, sw, 8, gcol)
            W.rect(cx - sw / 2, y0, 6, ch, gcol); W.rect(cx + sw / 2 - 6, y0, 6, ch, gcol)
            if p < 0.5 then W.text(cx, y0 + ch / 2, "✦", 90, { 150, 160, 220 }, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE, math.floor(255 * (1 - 2 * p)))
            elseif sw > cw * 0.5 then
                local it = r.kind == "mech" and C:mech(r.id) or C:char(r.id)
                W.badge(r.grade, cx - 40, y0 + 22, 80, 40, 28); W.pix(UI.CatIcon(r.id), cx - 55, y0 + 76, ch * 0.46, nil, 255, true)
                W.text(cx, y0 + ch * 0.66, it.name, n > 1 and 34 or 54, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); W.text(cx, y0 + ch - 50, r.isNew and "新获得！" or ("碎片 +" .. (r.frag or 0)), n > 1 and 22 or 30, r.isNew and K.teal or K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
            end
        end
        if sa.t > (sa.instant and 0.1 or 1.2 + #res * 0.16) and W.btn(Wd / 2 - 170, 940, 340, 80, (#sa.show > 0) and "查看新角色" or "完成", { primary = true, size = 34 }) then
            if #sa.show > 0 then sa.phase = "show"; sa.t = 0; sa.si = 1; hp = {}; C:sfx(top(sa.show[1].grade) and "win" or "level") else Hub.FinishSummon() end
        end
    elseif sa.phase == "show" then
        local r = sa.show[sa.si]; local it = r.kind == "mech" and C:mech(r.id) or C:char(r.id); local gcol = GCOLS[r.grade]
        W.title(Wd / 2 - 520, 200, r.grade, 150, gcol, NVG_ALIGN_CENTER + NVG_ALIGN_TOP, gcol); W.title(Wd / 2 + 480, 220, it.name, 84, K.bone, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        W.text(Wd / 2 + 480, 330, r.kind == "mech" and (it.type .. " 机甲") or it.role, 36, K.muted, NVG_ALIGN_CENTER + NVG_ALIGN_TOP); W.text(Wd / 2 + 480, 390, "新获得！", 44, K.teal, NVG_ALIGN_CENTER + NVG_ALIGN_TOP)
        W.wrap(Wd / 2 + 160, 470, 640, r.kind == "mech" and (it.active.name .. "：" .. it.active.desc) or (it.support.name .. "：" .. it.support.desc), 28, K.bone, 1.5)
        if W.btn(Wd / 2 - 170, 940, 340, 80, (sa.si < #sa.show) and "下一个" or "完成", { primary = true, size = 34 }) then
            if sa.si < #sa.show then sa.si = sa.si + 1; sa.t = 0; hp = {}; C:sfx(top(sa.show[sa.si].grade) and "win" or "level") else Hub.FinishSummon() end
        end
    end
end

-- ---------------------------------------------------------------- 入口
function Hub.Draw()
    if Hub.sa then W.block = false; drawSummonAnim(); return end
    W.block = (Hub.modal ~= nil or Hub.results ~= nil)
    if Hub.tab == "home" then homeView() elseif Hub.tab == "hangar" then hangarView() elseif Hub.tab == "pilots" then pilotsView() elseif Hub.tab == "work" then workView()
    elseif Hub.tab == "summon" then summonView() elseif Hub.tab == "daily" then dailyView() end
    if Hub.tab ~= "work" and Hub.tab ~= "daily" then nav() end
    W.block = false
    if Hub.results then drawResults() elseif Hub.modal == "settings" then drawSettings() elseif Hub.modal == "about" then drawAbout() elseif Hub.modal == "getsrc" then drawGetSrc() elseif Hub.modal == "rates" then drawRates() end
end
return Hub
