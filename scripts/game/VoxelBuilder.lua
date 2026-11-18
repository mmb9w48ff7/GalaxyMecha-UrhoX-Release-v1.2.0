-- VoxelBuilder.lua
-- 把 voxeldata/models/*.lua 中贪婪合并后的四边形展开为 CustomGeometry。
-- 每种颜色一个子几何体 + 一个 PBR 纯色材质（只使用文档允许的 Technique）。
-- 四边形编码：face, p, u0, v0, u1, v1
--   face = 轴 * 2 + 方向（0 正 / 1 负）；u = (轴+1)%3，v = (轴+2)%3
--   p 为该面所在平面坐标，u0..u1 / v0..v1 为体素单位下的矩形范围

local VoxelBuilder = { verbose = false }

local TECH_PBR = "Techniques/PBR/PBRNoTexture.xml"
local TECH_UNLIT = "Techniques/NoTextureUnlit.xml"

local modelCache_ = {}
local materialCache_ = {}
local stats_ = { models = 0, quads = 0, vertices = 0 }

local NORMALS = {
    { 1, 0, 0 }, { -1, 0, 0 },
    { 0, 1, 0 }, { 0, -1, 0 },
    { 0, 0, 1 }, { 0, 0, -1 },
}
-- 两个三角形的角点（u 取 0/1 端，v 取 0/1 端）
local CORNERS = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 0 }, { 1, 1 }, { 0, 1 } }

function VoxelBuilder.LoadData(id)
    local data = modelCache_[id]
    if not data then
        local ok, result = pcall(require, "voxeldata.models." .. id)
        if not ok then
            print("[VoxelBuilder] 模型数据加载失败: " .. tostring(id) .. " " .. tostring(result))
            return nil
        end
        data = result
        modelCache_[id] = data
        if VoxelBuilder.verbose then print(string.format("[VoxelBuilder] 载入模型 %s（%d 个合并面）", id, data.quadCount)) end
    end
    return data
end

local function MaterialKey(c, metallic, roughness, emissive, unlit)
    return string.format("%.3f_%.3f_%.3f_%.2f_%.2f_%.2f_%s", c[1], c[2], c[3], metallic, roughness, emissive, unlit and "u" or "l")
end

function VoxelBuilder.GetMaterial(color, metallic, roughness, emissive, unlit)
    local key = MaterialKey(color, metallic or 0, roughness or 0.7, emissive or 0, unlit)
    local mat = materialCache_[key]
    if mat then
        return mat
    end
    mat = Material:new()
    if unlit then
        mat:SetTechnique(0, cache:GetResource("Technique", TECH_UNLIT))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(color[1], color[2], color[3], 1.0)))
    else
        mat:SetTechnique(0, cache:GetResource("Technique", TECH_PBR))
        mat:SetShaderParameter("MatDiffColor", Variant(Color(color[1], color[2], color[3], 1.0)))
        mat:SetShaderParameter("Metallic", Variant(metallic or 0.0))
        mat:SetShaderParameter("Roughness", Variant(roughness or 0.7))
        if emissive and emissive > 0 then
            mat:SetShaderParameter("MatEmissiveColor",
                Variant(Color(color[1] * emissive, color[2] * emissive, color[3] * emissive)))
        end
    end
    -- 体素面不依赖绕序：关闭背面剔除，法线由数据直接给出
    mat:SetCullMode(CULL_NONE)
    materialCache_[key] = mat
    return mat
end

-- 在 parent 下创建一个节点并生成体素网格，返回节点
function VoxelBuilder.Build(parent, id, nodeName, tint)
    local data = VoxelBuilder.LoadData(id)
    local node = parent:CreateChild(nodeName or id)
    if not data then
        return node
    end
    local sc = data.scale
    local ox, oy, oz = data.origin[1], data.origin[2], data.origin[3]
    local geom = node:CreateComponent("CustomGeometry")
    geom:SetNumGeometries(#data.mats)
    local pos = { 0, 0, 0 }
    local vertexCount = 0
    for gi, mt in ipairs(data.mats) do
        geom:BeginGeometry(gi - 1, TRIANGLE_LIST)
        local q = mt.quads
        for k = 1, #q, 6 do
            local face, p = q[k], q[k + 1]
            local uu = { q[k + 2], q[k + 4] }
            local vv = { q[k + 3], q[k + 5] }
            local axis = face // 2
            local n = NORMALS[face + 1]
            local normal = Vector3(n[1], n[2], n[3])
            for c = 1, 6 do
                local cu, cv = uu[CORNERS[c][1] + 1], vv[CORNERS[c][2] + 1]
                if axis == 0 then
                    pos[1], pos[2], pos[3] = p, cu, cv
                elseif axis == 1 then
                    pos[1], pos[2], pos[3] = cv, p, cu
                else
                    pos[1], pos[2], pos[3] = cu, cv, p
                end
                geom:DefineVertex(Vector3((pos[1] - ox) * sc, (pos[2] - oy) * sc, (pos[3] - oz) * sc))
                geom:DefineNormal(normal)
            end
            vertexCount = vertexCount + 6
        end
    end
    geom:Commit()
    for gi, mt in ipairs(data.mats) do
        -- 网页版着色器：emissive < -1.5 = 不受光（亮度 0.8）；< -0.5 = 不受光（亮度 1.6）；其余按 PBR 受光；tint 整体替换颜色
        local em, col = mt.emissive or 0, tint or mt.color
        if em < -0.5 then local k = (em < -1.5) and 0.8 or 1.6; geom:SetMaterial(gi - 1, VoxelBuilder.GetMaterial({ col[1] * k, col[2] * k, col[3] * k }, 0, 1, 0, true))
        else geom:SetMaterial(gi - 1, VoxelBuilder.GetMaterial(col, mt.metallic, mt.roughness, em, false)) end
    end
    geom.castShadows = true
    stats_.models = stats_.models + 1
    stats_.quads = stats_.quads + data.quadCount
    stats_.vertices = stats_.vertices + vertexCount
    return node
end

-- 星空：每颗星是一个不受光照的小立方体，按 3 种颜色分组
function VoxelBuilder.BuildStars(parent, def)
    local node = parent:CreateChild("Stars")
    local geom = node:CreateComponent("CustomGeometry")
    local colors = def.colors
    geom:SetNumGeometries(#colors)
    local d = def.data
    for ci = 1, #colors do
        geom:BeginGeometry(ci - 1, TRIANGLE_LIST)
        for i = 1, #d, 5 do
            if d[i + 4] == ci - 1 then
                local cx, cy, cz, hs = d[i], d[i + 1], d[i + 2], d[i + 3] * 0.5
                for f = 0, 5 do
                    local axis = f // 2
                    local sg = (f % 2 == 0) and 1 or -1
                    for c = 1, 6 do
                        local a = sg * hs
                        local b = CORNERS[c][1] == 1 and hs or -hs
                        local e = CORNERS[c][2] == 1 and hs or -hs
                        local x, y, z
                        if axis == 0 then x, y, z = a, b, e
                        elseif axis == 1 then x, y, z = e, a, b
                        else x, y, z = b, e, a end
                        geom:DefineVertex(Vector3(cx + x, cy + y, cz + z))
                        geom:DefineNormal(Vector3(0, 1, 0))
                    end
                end
            end
        end
    end
    geom:Commit()
    for ci, c in ipairs(colors) do
        geom:SetMaterial(ci - 1, VoxelBuilder.GetMaterial(c, 0, 1, 0, true))
    end
    geom.castShadows = false
    return node
end

-- 模型包围球半径（米，未乘节点缩放）
function VoxelBuilder.Radius(id)
    local d = VoxelBuilder.LoadData(id)
    if not d then return 1 end
    local s = d.size
    return 0.5 * math.sqrt(s[1] * s[1] + s[2] * s[2] + s[3] * s[3]) * d.scale
end

-- 实例化：每个模型只在 protoRoot 下生成一次网格，之后用 Node:Clone() 复制，
-- 避免小行星带几十个同款岩石在 Lua 里反复展开顶点。
local protos_ = {}
function VoxelBuilder.Instance(protoRoot, parent, id)
    local key = tostring(protoRoot) .. ":" .. id
    local proto = protos_[key]
    if not proto then
        proto = VoxelBuilder.Build(protoRoot, id, "proto_" .. id)
        proto:SetDeepEnabled(false)
        protos_[key] = proto
    end
    local node = proto:Clone()
    node:SetParent(parent)
    node:SetDeepEnabled(true)
    return node
end

function VoxelBuilder.GetStats()
    return stats_
end

return VoxelBuilder
