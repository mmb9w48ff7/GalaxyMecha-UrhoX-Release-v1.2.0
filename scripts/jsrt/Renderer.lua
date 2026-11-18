-- Renderer.lua：E.render 的 UrhoX 后端。把网页版每帧生成的绘制列表（模型 + 4x4 矩阵 + 颜色替换）转成 UrhoX 节点：
-- 同一模型 / 同一颜色的节点放进对象池复用；矩阵分解为 位置 / 旋转 / 统一缩放；相机、灯光、辉光参数取自 f.env。
local VB = require("game.VoxelBuilder")
local R = { pools = {}, protos = {}, variants = {}, lastEnvSig = nil }
local sqrt = math.sqrt
local scene_, camNode_, camera_, drawRoot_, protoRoot_, starNode_, starSrc_, zone_, keyNode_, keyLight_, fillNode_, fillLight_, renderPath_
function R.Init(o)
    scene_, camNode_, camera_ = o.scene, o.camNode, o.camera
    zone_, keyNode_, keyLight_, fillNode_, fillLight_, renderPath_ = o.zone, o.keyNode, o.keyLight, o.fillNode, o.fillLight, o.renderPath
    drawRoot_ = scene_:CreateChild("Draws"); protoRoot_ = scene_:CreateChild("DrawProtos")
end
local function quant(v) return math.floor(v * 8 + 0.5) end
local function proto(id, tint)
    local key = tint and (id .. "|" .. quant(tint[0]) .. "," .. quant(tint[1]) .. "," .. quant(tint[2])) or id
    local p = R.protos[key]; if p ~= nil then return p or nil, key end
    if tint then
        R.variants[id] = (R.variants[id] or 0) + 1
        if R.variants[id] > 120 then R.protos[key] = false; return nil, key end           -- 颜色变体过多时放弃替换，避免内存膨胀
        local c = { (quant(tint[0]) / 8) ^ (1 / 2.2), (quant(tint[1]) / 8) ^ (1 / 2.2), (quant(tint[2]) / 8) ^ (1 / 2.2) }   -- 网页版 tint 是线性值，转成与模型颜色相同的空间
        p = VB.Build(protoRoot_, id, "proto_" .. key, c)
    else p = VB.Build(protoRoot_, id, "proto_" .. key) end
    p:SetDeepEnabled(false); R.protos[key] = p; return p, key
end
local function acquire(id, tint)
    local p, key = proto(id, tint)
    if not p then if tint then return acquire(id, nil) end return nil end
    local pool = R.pools[key]; if not pool then pool = { list = {}, n = 0, on = 0 }; R.pools[key] = pool end
    pool.n = pool.n + 1
    local node = pool.list[pool.n]
    if not node then node = p:Clone(); node:SetParent(drawRoot_); pool.list[pool.n] = node end
    node:SetDeepEnabled(true)
    return node
end
local function quat(m, sx)
    local r00, r10, r20, r01, r11, r21, r02, r12, r22 = m[0] / sx, m[1] / sx, m[2] / sx, m[4] / sx, m[5] / sx, m[6] / sx, m[8] / sx, m[9] / sx, m[10] / sx
    local tr = r00 + r11 + r22; local w, x, y, z
    if tr > 0 then local s = sqrt(tr + 1) * 2; w = 0.25 * s; x = (r21 - r12) / s; y = (r02 - r20) / s; z = (r10 - r01) / s
    elseif r00 > r11 and r00 > r22 then local s = sqrt(1 + r00 - r11 - r22) * 2; w = (r21 - r12) / s; x = 0.25 * s; y = (r01 + r10) / s; z = (r02 + r20) / s
    elseif r11 > r22 then local s = sqrt(1 + r11 - r00 - r22) * 2; w = (r02 - r20) / s; x = (r01 + r10) / s; y = 0.25 * s; z = (r12 + r21) / s
    else local s = sqrt(1 + r22 - r00 - r11) * 2; w = (r10 - r01) / s; x = (r02 + r20) / s; y = (r12 + r21) / s; z = 0.25 * s end
    return w, x, y, z
end
function R.Env(env)
    local sig = tostring(env.bg[0]) .. tostring(env.ambient[0]) .. tostring(env.key.brightness) .. tostring(env.bloom and env.bloom.mix) .. tostring(R.glow) .. tostring(env.fog[0])
    if sig == R.lastEnvSig then return end
    R.lastEnvSig = sig
    zone_.ambientColor = Color(env.ambient[0], env.ambient[1], env.ambient[2]); zone_.fogColor = Color(env.bg[0], env.bg[1], env.bg[2])
    keyNode_.direction = Vector3(env.key.dir[0], env.key.dir[1], env.key.dir[2]):Normalized(); keyLight_.color = Color(env.key.color[0], env.key.color[1], env.key.color[2]); keyLight_.brightness = env.key.brightness
    fillNode_.direction = Vector3(env.fill.dir[0], env.fill.dir[1], env.fill.dir[2]):Normalized(); fillLight_.color = Color(env.fill.color[0], env.fill.color[1], env.fill.color[2]); fillLight_.brightness = env.fill.brightness
    -- 雾：网页版是 mix(col, bg, f*f)，f 从 fog[0] 到 fog[1] 线性增长；UrhoX 雾是线性混合，起点后移 25% 来近似二次曲线
    zone_.fogStart = env.fog[0] + (env.fog[1] - env.fog[0]) * 0.25; zone_.fogEnd = env.fog[1]
    -- 辉光：网页版在线性空间用 smoothstep(thr, thr + 1.2, 最大通道) 取亮部；UrhoX 的 Bloom 在 gamma 空间硬阈值，所以把阈值换算到 gamma 空间（thr^(1/2.2)）
    local thr = math.min(0.95, env.bloom.threshold ^ (1 / 2.2)); local mix = env.bloom.mix * (R.glow or 1) * 0.8
    renderPath_:SetShaderParameter("BloomThreshold", Variant(thr)); renderPath_:SetShaderParameter("BloomMix", Variant(Vector2(1.0, mix)))
end
-- E.backend：f = { env, eye, target, fov, aspect, near, far, draws, stars }
function R.Frame(f, VP)
    R.Env(f.env)
    camNode_.position = Vector3(f.eye[0], f.eye[1], f.eye[2]); camNode_:LookAt(Vector3(f.target[0], f.target[1], f.target[2])); camera_.fov = f.fov
    -- 星空：以相机为中心
    if f.stars then
        if starSrc_ ~= f.stars then
            if starNode_ then starNode_:Remove() end
            local st = f.stars.stars; local d = {}; for i = 0, st.data.length - 1 do d[#d + 1] = st.data[i] end
            local cols = {}; for i = 0, st.colors.length - 1 do local c = st.colors[i]; cols[#cols + 1] = { c[0], c[1], c[2] } end
            starNode_ = VB.BuildStars(drawRoot_, { data = d, colors = cols }); starSrc_ = f.stars
        end
        starNode_.position = Vector3(f.eye[0], f.eye[1], f.eye[2])
    end
    for _, p in pairs(R.pools) do p.n = 0 end
    local draws = f.draws
    for i = 0, draws.length - 1 do
        local d = draws[i]; local m = d.m.d or d.m
        local sx = sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2])
        if sx > 1e-6 and d.mesh then
            local node = acquire(d.mesh.id, d.tint)
            if node then
                node.position = Vector3(m[12], m[13], m[14]); local w, x, y, z = quat(m, sx); node.rotation = Quaternion(w, x, y, z); node:SetScale(sx)
            end
        end
    end
    for _, p in pairs(R.pools) do
        for i = p.n + 1, p.on do p.list[i]:SetEnabled(false) end
        p.on = p.n
    end
end
return R
